import '../models/activity_label.dart';
import '../models/location_sample.dart';
import '../models/minute_window.dart';
import '../models/route_exclusion.dart';
import '../pipeline/geo.dart';
import '../pipeline/route_partitioner.dart';
import '../pipeline/sample_filter.dart';

/// A deterministic exclusion range found by the automatic route policy.
/// The repository assigns the durable ID when it writes the range.
class AutomaticRouteExclusionCandidate {
  const AutomaticRouteExclusionCandidate({
    required this.startAt,
    required this.endAt,
    this.reason = RouteExclusionReason.vehicle,
  });

  final DateTime startAt;
  final DateTime endAt;
  final RouteExclusionReason reason;
}

/// Finds route ranges that must not contribute to walking statistics.
///
/// Speed evidence comes from continuous, quality-checked GPS segments, never
/// a minute's peak speed or an inferred vehicle label. Raw samples stay
/// immutable; exclusions retain the existing session-clamped minute contract.
class AutomaticRouteExclusionPolicy {
  const AutomaticRouteExclusionPolicy({this.speedThresholdMps = 10 / 3.6});

  static const _filterConfig = SampleFilterConfig();

  /// 10 km/h expressed in metres per second.
  final double speedThresholdMps;

  List<AutomaticRouteExclusionCandidate> detect({
    required List<MinuteWindow> windows,
    required List<LocationSample> samples,
    required DateTime sessionStart,
    required DateTime sessionEnd,
    Iterable<RouteExclusion> existingExclusions = const [],
  }) {
    final start = sessionStart.toUtc();
    final end = sessionEnd.toUtc();
    if (!start.isBefore(end)) return const [];

    final existing = existingExclusions.toList(growable: false);
    final ranges = <_AutomaticRange>[];
    final runs = _highSpeedRuns(samples, start, end);
    final orderedWindows = [...windows]
      ..sort((a, b) => a.windowStart.compareTo(b.windowStart));
    var runIndex = 0;
    var edgeIndex = 0;

    for (final window in orderedWindows) {
      if (window.isUserExcluded || window.durationS <= 0) continue;
      final range = _clampRange(
        window.windowStart,
        window.windowStart.add(const Duration(minutes: 1)),
        start,
        end,
      );
      if (range == null) continue;
      final explicitVehicle =
          window.userConfirmed && window.userLabel == ActivityLabel.vehicle;
      if (_hasExplicitNonVehicleLabel(window)) continue;
      while (runIndex < runs.length &&
          !runs[runIndex].last.end.timestamp.isAfter(range.startAt)) {
        runIndex++;
        edgeIndex = 0;
      }
      var supportedSpeed = false;
      if (runIndex < runs.length) {
        final run = runs[runIndex];
        if (!run.first.start.timestamp.isAfter(range.startAt) &&
            !run.last.end.timestamp.isBefore(range.endAt)) {
          while (edgeIndex < run.length &&
              !run[edgeIndex].end.timestamp.isAfter(range.startAt)) {
            edgeIndex++;
          }
          var lastIndex = edgeIndex;
          var distance = 0.0;
          while (lastIndex < run.length &&
              run[lastIndex].start.timestamp.isBefore(range.endAt)) {
            distance += run[lastIndex].distanceM;
            lastIndex++;
          }
          final first = run[edgeIndex].start;
          final last = run[lastIndex - 1].end;
          final displacement = haversineMeters(
            lat1: first.latitude,
            lon1: first.longitude,
            lat2: last.latitude,
            lon2: last.longitude,
          );
          // Use real bracketing fixes, not invented boundary coordinates.
          // A strongly reversing path is uncertain: leave it included rather
          // than treating repeated GPS oscillation as sustained travel.
          supportedSpeed =
              displacement > first.accuracyM! + last.accuracyM! &&
              displacement >= distance * 0.6;
        }
      }
      if (!supportedSpeed && !explicitVehicle) {
        continue;
      }
      ranges.addAll(
        _subtractExisting(
          range,
          existing,
          reason: supportedSpeed
              ? RouteExclusionReason.highSpeed
              : RouteExclusionReason.vehicle,
        ),
      );
    }

    ranges.sort((a, b) {
      final byStart = a.startAt.compareTo(b.startAt);
      return byStart != 0 ? byStart : a.endAt.compareTo(b.endAt);
    });

    final merged = <_AutomaticRange>[];
    for (final range in ranges) {
      if (merged.isEmpty || range.startAt.isAfter(merged.last.endAt)) {
        merged.add(range);
      } else {
        final previous = merged.last;
        merged[merged.length - 1] = _AutomaticRange(
          startAt: previous.startAt,
          endAt: range.endAt.isAfter(previous.endAt)
              ? range.endAt
              : previous.endAt,
          reason: _mergeReason(previous.reason, range.reason),
        );
      }
    }
    return [
      for (final range in merged)
        AutomaticRouteExclusionCandidate(
          startAt: range.startAt,
          endAt: range.endAt,
          reason: range.reason,
        ),
    ];
  }

  List<List<RouteSegment>> _highSpeedRuns(
    List<LocationSample> samples,
    DateTime start,
    DateTime end,
  ) {
    final partition = RoutePartitioner.partition(
      samples: samples,
      exclusions: const [],
      sessionStart: start,
      sessionEnd: end,
    );
    final runs = <List<RouteSegment>>[];
    var current = <RouteSegment>[];
    void finish() {
      if (current.length >= 3 &&
          current.last.end.timestamp.difference(
                current.first.start.timestamp,
              ) >=
              const Duration(seconds: 30)) {
        runs.add(current);
      }
      current = <RouteSegment>[];
    }

    for (final segment in partition.segments) {
      final firstAccuracy = segment.start.accuracyM;
      final lastAccuracy = segment.end.accuracyM;
      final usable =
          firstAccuracy != null &&
          firstAccuracy.isFinite &&
          firstAccuracy >= 0 &&
          firstAccuracy <= 25 &&
          lastAccuracy != null &&
          lastAccuracy.isFinite &&
          lastAccuracy >= 0 &&
          lastAccuracy <= 25 &&
          segment.duration <= const Duration(seconds: 30) &&
          // Absorb floating-point roundoff at the inclusive speed boundary.
          segment.speedMps + 1e-9 >= speedThresholdMps &&
          segment.speedMps <= _filterConfig.maxJumpSpeedMps;
      if (!usable) {
        finish();
        continue;
      }
      if (current.isNotEmpty && !identical(current.last.end, segment.start)) {
        finish();
      }
      current.add(segment);
    }
    finish();
    return runs;
  }

  bool _hasExplicitNonVehicleLabel(MinuteWindow window) {
    return window.userConfirmed &&
        window.userLabel != null &&
        window.userLabel != ActivityLabel.vehicle;
  }

  List<_AutomaticRange> _subtractExisting(
    _AutomaticRange range,
    Iterable<RouteExclusion> exclusions, {
    required RouteExclusionReason reason,
  }) {
    final ordered = exclusions.toList(growable: false)
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final uncovered = <_AutomaticRange>[];
    var cursor = range.startAt;
    for (final exclusion in ordered) {
      final exclusionStart = exclusion.startAt.toUtc();
      final exclusionEnd = exclusion.endAt.toUtc();
      if (!exclusionEnd.isAfter(cursor)) continue;
      if (!exclusionStart.isBefore(range.endAt)) break;
      if (exclusionStart.isAfter(cursor)) {
        final end = exclusionStart.isBefore(range.endAt)
            ? exclusionStart
            : range.endAt;
        if (cursor.isBefore(end)) {
          uncovered.add(
            _AutomaticRange(startAt: cursor, endAt: end, reason: reason),
          );
        }
      }
      if (exclusionEnd.isAfter(cursor)) {
        cursor = exclusionEnd.isBefore(range.endAt)
            ? exclusionEnd
            : range.endAt;
      }
      if (!cursor.isBefore(range.endAt)) break;
    }
    if (cursor.isBefore(range.endAt)) {
      uncovered.add(
        _AutomaticRange(startAt: cursor, endAt: range.endAt, reason: reason),
      );
    }
    return uncovered;
  }

  RouteExclusionReason _mergeReason(
    RouteExclusionReason left,
    RouteExclusionReason right,
  ) {
    // A shared range may satisfy both triggers. Keep the more specific
    // measured-speed reason so exports and future UI can explain it.
    if (left == RouteExclusionReason.highSpeed ||
        right == RouteExclusionReason.highSpeed) {
      return RouteExclusionReason.highSpeed;
    }
    return RouteExclusionReason.vehicle;
  }

  _AutomaticRange? _clampRange(
    DateTime rawStart,
    DateTime rawEnd,
    DateTime sessionStart,
    DateTime sessionEnd,
  ) {
    final start = rawStart.toUtc().isAfter(sessionStart)
        ? rawStart.toUtc()
        : sessionStart;
    final end = rawEnd.toUtc().isBefore(sessionEnd)
        ? rawEnd.toUtc()
        : sessionEnd;
    if (!start.isBefore(end)) return null;
    return _AutomaticRange(startAt: start, endAt: end);
  }
}

class _AutomaticRange {
  const _AutomaticRange({
    required this.startAt,
    required this.endAt,
    this.reason = RouteExclusionReason.vehicle,
  });

  final DateTime startAt;
  final DateTime endAt;
  final RouteExclusionReason reason;
}
