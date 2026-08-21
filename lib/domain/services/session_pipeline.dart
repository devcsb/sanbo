import '../models/location_sample.dart';
import '../models/minute_window.dart';
import '../models/route_exclusion.dart';
import '../models/walk_session.dart';
import '../pipeline/activity_inferencer.dart';
import '../pipeline/route_partitioner.dart';
import '../pipeline/sample_filter.dart';
import '../pipeline/segment_merger.dart';
import '../pipeline/session_rollup.dart';
import '../pipeline/window_aggregator.dart';

/// Production session processing path: filter → partition → windows → rollup.
class SessionPipeline {
  SessionPipeline({
    SampleFilter? filter,
    WindowAggregator? aggregator,
    SessionRollup? rollup,
    SegmentMerger? segmentMerger,
  }) : filter = filter ?? SampleFilter(),
       aggregator = aggregator ?? WindowAggregator(),
       rollup = rollup ?? SessionRollup(),
       segmentMerger = segmentMerger ?? SegmentMerger();

  final SampleFilter filter;
  final WindowAggregator aggregator;
  final SessionRollup rollup;
  final SegmentMerger segmentMerger;

  SessionProcessResult process({
    required WalkSession session,
    required List<LocationSample> rawSamples,
    required DateTime endedAt,
  }) {
    final markedSamples = filter.apply(rawSamples);
    final partition = RoutePartitioner.partition(
      samples: markedSamples,
      exclusions: const [],
    );
    final windows = aggregator.aggregate(
      partition: partition,
      rawSamples: markedSamples,
      exclusions: const [],
      sessionStart: session.startedAt,
      sessionEnd: endedAt,
    );
    final metrics = rollup.compute(
      session: session,
      partition: partition,
      exclusions: const [],
      endedAt: endedAt,
    );
    final segments = segmentMerger.merge(windows);
    return SessionProcessResult(
      filteredSamples: markedSamples,
      fragments: partition.fragments,
      windows: windows,
      segments: segments,
      metrics: metrics,
    );
  }

  CompletedSessionRecalculation recalculateCompleted({
    required WalkSession session,
    required List<LocationSample> storedSamples,
    required List<RouteExclusion> exclusions,
    required List<MinuteWindow> previousWindows,
  }) {
    final endedAt = session.endedAt;
    if (endedAt == null || session.status != SessionStatus.completed) {
      throw StateError('완료된 산책만 다시 계산할 수 있습니다');
    }
    final normalized =
        exclusions.map((item) => item.clampedTo(session)).toList()
          ..sort((a, b) => a.startAt.compareTo(b.startAt));
    for (var index = 1; index < normalized.length; index++) {
      if (normalized[index].startAt.isBefore(normalized[index - 1].endAt)) {
        throw StateError('겹치는 제외 범위가 있습니다');
      }
    }
    final partition = RoutePartitioner.partition(
      samples: storedSamples,
      exclusions: normalized,
    );
    final metadata = {
      for (final window in previousWindows) window.windowStart.toUtc(): window,
    };
    final rebuilt = aggregator.aggregate(
      partition: partition,
      exclusions: normalized,
      rawSamples: storedSamples,
      sessionStart: session.startedAt,
      sessionEnd: endedAt,
    );
    final windows = rebuilt
        .map(
          (window) =>
              _restoreMetadata(window, metadata[window.windowStart.toUtc()]),
        )
        .toList();
    final metrics = rollup.compute(
      session: session,
      partition: partition,
      exclusions: normalized,
      endedAt: endedAt,
    );
    if (!_finiteMetrics(metrics)) {
      throw StateError('재계산 결과가 올바르지 않습니다');
    }
    return CompletedSessionRecalculation(
      windows: List.unmodifiable(windows),
      fragments: partition.fragments,
      metrics: metrics,
    );
  }

  MinuteWindow _restoreMetadata(MinuteWindow rebuilt, MinuteWindow? previous) {
    if (previous == null) return rebuilt;
    return MinuteWindow(
      windowStart: rebuilt.windowStart,
      durationS: rebuilt.durationS,
      partial: rebuilt.partial,
      sampleCount: rebuilt.sampleCount,
      rawSampleCount: rebuilt.rawSampleCount,
      distanceM: rebuilt.distanceM,
      avgSpeedMps: rebuilt.avgSpeedMps,
      maxSpeedMps: rebuilt.maxSpeedMps,
      stationaryRatio: rebuilt.stationaryRatio,
      quality: rebuilt.quality,
      centroidLat: rebuilt.centroidLat,
      centroidLon: rebuilt.centroidLon,
      startLat: rebuilt.startLat,
      startLon: rebuilt.startLon,
      endLat: rebuilt.endLat,
      endLon: rebuilt.endLon,
      gapReason: rebuilt.gapReason,
      hypothesisLabel: rebuilt.hypothesisLabel,
      hypothesisConfidence: rebuilt.hypothesisConfidence,
      evidence: rebuilt.evidence,
      userLabel: previous.userLabel,
      userNote: previous.userNote,
      userConfirmed: previous.userConfirmed,
      userExclusionId: rebuilt.userExclusionId,
      placeId: previous.placeId,
    );
  }

  bool _finiteMetrics(SessionRollupResult metrics) {
    return metrics.totalDistanceM.isFinite &&
        metrics.totalDistanceM >= 0 &&
        metrics.durationS >= 0 &&
        metrics.movingTimeS >= 0 &&
        metrics.stationaryTimeS >= 0 &&
        metrics.avgSpeedMps.isFinite &&
        metrics.avgSpeedMps >= 0 &&
        (metrics.medianAccuracyM == null ||
            (metrics.medianAccuracyM!.isFinite &&
                metrics.medianAccuracyM! >= 0));
  }
}

class SessionProcessResult {
  const SessionProcessResult({
    required this.filteredSamples,
    required this.fragments,
    required this.windows,
    required this.metrics,
    this.segments = const [],
  });

  final List<LocationSample> filteredSamples;
  final List<RouteFragment> fragments;
  final List<MinuteWindow> windows;
  final List<ActivitySegment> segments;
  final SessionRollupResult metrics;
}

class CompletedSessionRecalculation {
  const CompletedSessionRecalculation({
    required this.windows,
    required this.fragments,
    required this.metrics,
  });

  final List<MinuteWindow> windows;
  final List<RouteFragment> fragments;
  final SessionRollupResult metrics;
}

/// Shared inferencer instance for optional re-use.
final defaultInferencer = ActivityInferencer();
