import '../models/activity_label.dart';
import '../models/minute_window.dart';
import '../models/route_exclusion.dart';
import '../pipeline/segment_merger.dart';

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
/// This policy intentionally works from the trusted, derived minute windows
/// and merged activity segments. Raw samples stay immutable and the caller
/// persists the returned ranges as ordinary route exclusions.
class AutomaticRouteExclusionPolicy {
  const AutomaticRouteExclusionPolicy({this.speedThresholdMps = 10 / 3.6});

  /// 10 km/h expressed in metres per second.
  final double speedThresholdMps;

  List<AutomaticRouteExclusionCandidate> detect({
    required List<MinuteWindow> windows,
    required List<ActivitySegment> segments,
    required DateTime sessionStart,
    required DateTime sessionEnd,
    Iterable<RouteExclusion> existingExclusions = const [],
  }) {
    final start = sessionStart.toUtc();
    final end = sessionEnd.toUtc();
    if (!start.isBefore(end)) return const [];

    final existing = existingExclusions.toList(growable: false);
    final ranges = <_AutomaticRange>[];

    for (final window in windows) {
      if (window.isUserExcluded ||
          window.durationS <= 0 ||
          window.maxSpeedMps < speedThresholdMps ||
          !window.maxSpeedMps.isFinite ||
          _hasExplicitNonVehicleLabel(window)) {
        continue;
      }
      final range = _clampRange(
        window.windowStart,
        window.windowStart.add(const Duration(minutes: 1)),
        start,
        end,
      );
      if (range == null) continue;
      ranges.addAll(
        _subtractExisting(
          range,
          existing,
          reason: RouteExclusionReason.highSpeed,
        ),
      );
    }

    for (final segment in segments) {
      if (segment.label != ActivityLabel.vehicle ||
          segment.userExclusionId != null ||
          segment.durationS <= 0 ||
          segment.windows.any((window) => window.durationS <= 0)) {
        continue;
      }
      final range = _clampRange(
        segment.startAt,
        segment.endExclusive,
        start,
        end,
      );
      if (range == null) continue;
      ranges.addAll(
        _subtractExisting(
          range,
          existing,
          reason: RouteExclusionReason.vehicle,
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
