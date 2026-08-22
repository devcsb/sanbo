import '../models/location_sample.dart';
import '../models/minute_window.dart';
import '../models/route_exclusion.dart';
import 'activity_inferencer.dart';
import 'geo.dart';
import 'route_partitioner.dart';

class WindowAggregatorConfig {
  const WindowAggregatorConfig({
    this.minSamplesPerWindow = 3,
    this.stationarySpeedMps = 0.3,
    this.medianAccuracyHighM = 25,
    this.medianAccuracyMediumM = 50,
  });

  final int minSamplesPerWindow;
  final double stationarySpeedMps;
  final double medianAccuracyHighM;
  final double medianAccuracyMediumM;
}

class _WindowMotion {
  double distanceM = 0;
  double movingSeconds = 0;
  double stationarySeconds = 0;
  double maxSpeedMps = 0;
}

/// Buckets the shared trusted route into wall-clock minute windows.
class WindowAggregator {
  WindowAggregator({
    this.config = const WindowAggregatorConfig(),
    ActivityInferencer? inferencer,
  }) : inferencer = inferencer ?? ActivityInferencer();

  final WindowAggregatorConfig config;
  final ActivityInferencer inferencer;

  List<MinuteWindow> aggregate({
    required RoutePartitionResult partition,
    required List<LocationSample> rawSamples,
    required List<RouteExclusion> exclusions,
    required DateTime sessionStart,
    required DateTime sessionEnd,
    String? timezone,
  }) {
    if (!sessionEnd.isAfter(sessionStart)) return const [];

    final startLocal = asLocal(sessionStart, timezone: timezone);
    final endLocal = asLocal(sessionEnd, timezone: timezone);
    final rawByMinute = _bucketSamples(
      rawSamples,
      sessionStart,
      sessionEnd,
      timezone: timezone,
      includeSessionEnd: true,
    );
    final includedByMinute = _bucketSamples(
      partition.includedSamples,
      sessionStart,
      sessionEnd,
      timezone: timezone,
      includeSessionEnd: true,
    );
    final motionByMinute = _allocateMotion(
      partition.segments,
      sessionStart,
      sessionEnd,
      timezone: timezone,
    );
    final excludedWindows = _excludedWindows(
      exclusions,
      sessionStart,
      sessionEnd,
      timezone: timezone,
    );

    final windows = <MinuteWindow>[];
    var cursor = floorToMinute(startLocal, timezone: timezone);
    while (cursor.isBefore(endLocal)) {
      final windowEnd = cursor.add(const Duration(minutes: 1));
      final spanStart = startLocal.isAfter(cursor) ? startLocal : cursor;
      final spanEnd = endLocal.isBefore(windowEnd) ? endLocal : windowEnd;
      final durationS = positiveDurationSeconds(spanStart, spanEnd);
      final rawSampleCount = rawByMinute[cursor]?.length ?? 0;
      final exclusionId = excludedWindows[cursor];
      if (exclusionId != null) {
        windows.add(
          _excludedWindow(
            windowStart: cursor,
            durationS: durationS,
            rawSampleCount: rawSampleCount,
            exclusionId: exclusionId,
          ),
        );
      } else {
        windows.add(
          _buildWindow(
            windowStart: cursor,
            durationS: durationS,
            partial: durationS < 60,
            samples: includedByMinute[cursor] ?? const [],
            rawSampleCount: rawSampleCount,
            motion: motionByMinute[cursor] ?? _WindowMotion(),
          ),
        );
      }
      cursor = windowEnd;
    }
    return List.unmodifiable(windows);
  }

  Map<DateTime, List<LocationSample>> _bucketSamples(
    List<LocationSample> samples,
    DateTime sessionStart,
    DateTime sessionEnd, {
    String? timezone,
    bool includeSessionEnd = false,
  }) {
    final result = <DateTime, List<LocationSample>>{};
    for (final sample in samples) {
      if (sample.timestamp.isBefore(sessionStart) ||
          sample.timestamp.isAfter(sessionEnd) ||
          (!includeSessionEnd &&
              sample.timestamp.isAtSameMomentAs(sessionEnd))) {
        continue;
      }
      final timestampForBucket = sample.timestamp.isAtSameMomentAs(sessionEnd)
          ? sample.timestamp.subtract(const Duration(microseconds: 1))
          : sample.timestamp;
      final key = floorToMinute(timestampForBucket, timezone: timezone);
      result.putIfAbsent(key, () => []).add(sample);
    }
    return result;
  }

  Map<DateTime, _WindowMotion> _allocateMotion(
    List<RouteSegment> segments,
    DateTime sessionStart,
    DateTime sessionEnd, {
    String? timezone,
  }) {
    final motionByMinute = <DateTime, _WindowMotion>{};
    for (final segment in segments) {
      final segmentStart = segment.start.timestamp;
      final segmentEnd = segment.end.timestamp;
      final durationUs = segment.duration.inMicroseconds;
      if (durationUs <= 0 || !segment.distanceM.isFinite) continue;

      var cursor = floorToMinute(segmentStart, timezone: timezone);
      final segmentEndLocal = asLocal(segmentEnd, timezone: timezone);
      while (cursor.isBefore(segmentEndLocal)) {
        final windowEnd = cursor.add(const Duration(minutes: 1));
        final overlapStart = _later(_later(segmentStart, sessionStart), cursor);
        final overlapEnd = _earlier(
          _earlier(segmentEnd, sessionEnd),
          windowEnd,
        );
        final overlapUs = overlapEnd.difference(overlapStart).inMicroseconds;
        if (overlapUs > 0) {
          final bucket = motionByMinute.putIfAbsent(cursor, _WindowMotion.new);
          final overlapSeconds = overlapUs / Duration.microsecondsPerSecond;
          if (segment.distanceM >= minMeaningfulSegmentDistanceM) {
            bucket.distanceM += segment.distanceM * overlapUs / durationUs;
          }
          if (segment.speedMps < config.stationarySpeedMps) {
            bucket.stationarySeconds += overlapSeconds;
          } else {
            bucket.movingSeconds += overlapSeconds;
          }
          if (segment.speedMps > bucket.maxSpeedMps) {
            bucket.maxSpeedMps = segment.speedMps;
          }
        }
        cursor = windowEnd;
      }
    }
    return motionByMinute;
  }

  Map<DateTime, String> _excludedWindows(
    List<RouteExclusion> exclusions,
    DateTime sessionStart,
    DateTime sessionEnd, {
    String? timezone,
  }) {
    final result = <DateTime, String>{};
    final ordered = [...exclusions]
      ..sort((a, b) {
        final byStart = a.startAt.compareTo(b.startAt);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });
    var cursor = floorToMinute(sessionStart, timezone: timezone);
    final endLocal = asLocal(sessionEnd, timezone: timezone);
    while (cursor.isBefore(endLocal)) {
      final windowEnd = cursor.add(const Duration(minutes: 1));
      final spanStart = _later(cursor, sessionStart);
      final spanEnd = _earlier(windowEnd, sessionEnd);
      final touching = ordered
          .where((exclusion) => exclusion.overlaps(spanStart, spanEnd))
          .toList(growable: false);
      if (touching.isNotEmpty) {
        // v2 backups may contain partial or disjoint exclusions in one minute
        // even though newly-created route edits are authoritative full-minute
        // selections. The row has one representative ID, so preserve the
        // stable first touching ID for that legacy shape.
        result[cursor] = touching.first.id;
      }
      cursor = windowEnd;
    }
    return result;
  }

  MinuteWindow _excludedWindow({
    required DateTime windowStart,
    required int durationS,
    required int rawSampleCount,
    required String exclusionId,
  }) => MinuteWindow(
    windowStart: windowStart,
    durationS: durationS,
    partial: durationS < 60,
    sampleCount: 0,
    rawSampleCount: rawSampleCount,
    distanceM: 0,
    avgSpeedMps: 0,
    maxSpeedMps: 0,
    stationaryRatio: 1,
    quality: WindowQuality.gap,
    gapReason: 'user_excluded',
    userExclusionId: exclusionId,
  );

  MinuteWindow _buildWindow({
    required DateTime windowStart,
    required int durationS,
    required bool partial,
    required List<LocationSample> samples,
    required int rawSampleCount,
    required _WindowMotion motion,
  }) {
    final hasMotion =
        motion.distanceM > 0 ||
        motion.movingSeconds > 0 ||
        motion.stationarySeconds > 0;
    if (samples.isEmpty && !hasMotion) {
      final gap = MinuteWindow(
        windowStart: windowStart,
        durationS: durationS,
        partial: partial,
        sampleCount: 0,
        rawSampleCount: rawSampleCount,
        distanceM: 0,
        avgSpeedMps: 0,
        maxSpeedMps: 0,
        stationaryRatio: 1,
        quality: WindowQuality.gap,
        gapReason: rawSampleCount == 0 ? 'no_samples' : 'all_filtered',
      );
      return _withInference(gap);
    }

    final sorted = [...samples]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final accuracies =
        sorted
            .map((sample) => sample.accuracyM)
            .whereType<double>()
            .where((accuracy) => accuracy.isFinite)
            .toList()
          ..sort();
    final medianAccuracy = accuracies.isEmpty
        ? null
        : accuracies[accuracies.length ~/ 2];
    final stationaryRatio = durationS <= 0
        ? 1.0
        : (motion.stationarySeconds / durationS).clamp(0.0, 1.0);
    final distance = motion.distanceM.isFinite ? motion.distanceM : 0.0;
    final avgSpeed = motion.movingSeconds > 0
        ? distance / motion.movingSeconds
        : 0.0;
    final draft = MinuteWindow(
      windowStart: windowStart,
      durationS: durationS,
      partial: partial,
      sampleCount: sorted.length,
      rawSampleCount: rawSampleCount,
      distanceM: distance,
      avgSpeedMps: avgSpeed.isFinite ? avgSpeed : 0.0,
      maxSpeedMps: motion.maxSpeedMps,
      stationaryRatio: stationaryRatio,
      quality: _quality(
        sampleCount: sorted.length,
        medianAccuracyM: medianAccuracy,
      ),
      centroidLat: sorted.isEmpty
          ? null
          : sorted.map((sample) => sample.latitude).reduce((a, b) => a + b) /
                sorted.length,
      centroidLon: sorted.isEmpty
          ? null
          : sorted.map((sample) => sample.longitude).reduce((a, b) => a + b) /
                sorted.length,
      startLat: sorted.isEmpty ? null : sorted.first.latitude,
      startLon: sorted.isEmpty ? null : sorted.first.longitude,
      endLat: sorted.isEmpty ? null : sorted.last.latitude,
      endLon: sorted.isEmpty ? null : sorted.last.longitude,
    );
    return _withInference(draft);
  }

  MinuteWindow _withInference(MinuteWindow window) {
    final hypothesis = inferencer.infer(window);
    return MinuteWindow(
      windowStart: window.windowStart,
      durationS: window.durationS,
      partial: window.partial,
      sampleCount: window.sampleCount,
      rawSampleCount: window.rawSampleCount,
      distanceM: window.distanceM,
      avgSpeedMps: window.avgSpeedMps,
      maxSpeedMps: window.maxSpeedMps,
      stationaryRatio: window.stationaryRatio,
      quality: window.quality,
      centroidLat: window.centroidLat,
      centroidLon: window.centroidLon,
      startLat: window.startLat,
      startLon: window.startLon,
      endLat: window.endLat,
      endLon: window.endLon,
      gapReason: window.gapReason,
      userExclusionId: window.userExclusionId,
      hypothesisLabel: hypothesis.label,
      hypothesisConfidence: hypothesis.confidence,
      evidence: hypothesis.evidence,
    );
  }

  WindowQuality _quality({
    required int sampleCount,
    required double? medianAccuracyM,
  }) {
    if (sampleCount < config.minSamplesPerWindow) return WindowQuality.low;
    if (medianAccuracyM == null) return WindowQuality.medium;
    if (medianAccuracyM <= config.medianAccuracyHighM) {
      return WindowQuality.high;
    }
    if (medianAccuracyM <= config.medianAccuracyMediumM) {
      return WindowQuality.medium;
    }
    return WindowQuality.low;
  }
}

DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
