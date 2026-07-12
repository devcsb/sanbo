import '../models/location_sample.dart';
import '../models/minute_window.dart';
import '../models/walk_session.dart';
import '../pipeline/activity_inferencer.dart';
import '../pipeline/sample_filter.dart';
import '../pipeline/session_rollup.dart';
import '../pipeline/window_aggregator.dart';

/// Production session processing path: filter → windows → rollup.
/// Used by UI controller and e2e so tests drive the same shipped functions.
class SessionPipeline {
  SessionPipeline({
    SampleFilter? filter,
    WindowAggregator? aggregator,
    SessionRollup? rollup,
  })  : filter = filter ?? SampleFilter(),
        aggregator = aggregator ?? WindowAggregator(),
        rollup = rollup ?? SessionRollup();

  final SampleFilter filter;
  final WindowAggregator aggregator;
  final SessionRollup rollup;

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
    return SessionProcessResult(
      filteredSamples: filtered,
      windows: windows,
      metrics: metrics,
    );
  }
}

class SessionProcessResult {
  const SessionProcessResult({
    required this.filteredSamples,
    required this.windows,
    required this.metrics,
  });

  final List<LocationSample> filteredSamples;
  final List<MinuteWindow> windows;
  final SessionRollupResult metrics;
}

/// Shared inferencer instance for optional re-use.
final defaultInferencer = ActivityInferencer();
