import 'session_guard.dart';

enum SessionDeadlineEvent {
  none,
  stationaryWarning,
  stationaryLimit,
  durationWarning,
  durationLimit,
}

class SessionDeadlines {
  const SessionDeadlines({
    this.stationaryWarningAt,
    this.stationaryLimitAt,
    required this.durationWarningAt,
    required this.durationLimitAt,
  });

  final DateTime? stationaryWarningAt;
  final DateTime? stationaryLimitAt;
  final DateTime durationWarningAt;
  final DateTime durationLimitAt;

  SessionDeadlines copyWith({
    DateTime? stationaryWarningAt,
    DateTime? stationaryLimitAt,
    bool clearStationary = false,
  }) {
    return SessionDeadlines(
      stationaryWarningAt: clearStationary
          ? null
          : (stationaryWarningAt ?? this.stationaryWarningAt),
      stationaryLimitAt: clearStationary
          ? null
          : (stationaryLimitAt ?? this.stationaryLimitAt),
      durationWarningAt: durationWarningAt,
      durationLimitAt: durationLimitAt,
    );
  }
}

abstract final class SessionDeadlinePolicy {
  static SessionDeadlines calculate(
    DateTime startedAt,
    SessionGuardPolicy policy,
  ) {
    final start = startedAt.toUtc();
    return SessionDeadlines(
      durationWarningAt: start.add(policy.durationWarningAfter),
      durationLimitAt: start.add(policy.durationLimit),
    );
  }

  static SessionDeadlineEvent evaluate(
    SessionDeadlines deadlines,
    DateTime now,
  ) {
    final instant = now.toUtc();
    if (!instant.isBefore(deadlines.durationLimitAt)) {
      return SessionDeadlineEvent.durationLimit;
    }
    final stationaryLimitAt = deadlines.stationaryLimitAt;
    if (stationaryLimitAt != null && !instant.isBefore(stationaryLimitAt)) {
      return SessionDeadlineEvent.stationaryLimit;
    }
    if (!instant.isBefore(deadlines.durationWarningAt)) {
      return SessionDeadlineEvent.durationWarning;
    }
    final stationaryWarningAt = deadlines.stationaryWarningAt;
    if (stationaryWarningAt != null && !instant.isBefore(stationaryWarningAt)) {
      return SessionDeadlineEvent.stationaryWarning;
    }
    return SessionDeadlineEvent.none;
  }
}
