import '../models/location_sample.dart';
import '../models/minute_window.dart';
import '../models/walk_session.dart';
import '../pipeline/activity_inferencer.dart';
import '../pipeline/sample_filter.dart';
import '../pipeline/segment_merger.dart';
import '../pipeline/session_rollup.dart';
import '../pipeline/window_aggregator.dart';

/// Production session processing path: filter → windows → rollup → segments.
/// Used by UI controller and e2e so tests drive the same shipped functions.
class SessionPipeline {
  SessionPipeline({
    SampleFilter? filter,
    WindowAggregator? aggregator,
    SessionRollup? rollup,
    SegmentMerger? segmentMerger,
  })  : filter = filter ?? SampleFilter(),
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
    final filtered = filter.apply(rawSamples);
    final windows = aggregator.aggregate(
      samples: filtered,
      sessionStart: session.startedAt,
      sessionEnd: endedAt,
    );
    final metrics = rollup.compute(
      session: session,
      samples: filtered,
      endedAt: endedAt,
    );
    final segments = segmentMerger.merge(windows);
    return SessionProcessResult(
      filteredSamples: filtered,
      windows: windows,
      segments: segments,
      metrics: metrics,
    );
  }
}

class SessionProcessResult {
  const SessionProcessResult({
    required this.filteredSamples,
    required this.windows,
    required this.metrics,
    this.segments = const [],
  });

  final List<LocationSample> filteredSamples;
  final List<MinuteWindow> windows;
  final List<ActivitySegment> segments;
  final SessionRollupResult metrics;
}

/// Shared inferencer instance for optional re-use.
final defaultInferencer = ActivityInferencer();
