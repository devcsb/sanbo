import 'package:timezone/timezone.dart' as tz;

import '../models/walk_session.dart';
import '../pipeline/geo.dart';

class SessionWeekEntry {
  const SessionWeekEntry({
    required this.id,
    required this.startedAt,
    required this.movingTimeS,
  });
  final String id;
  final DateTime startedAt;
  final int movingTimeS;
}

class SessionWeekDay {
  const SessionWeekDay({required this.date, required this.movingTimeS});
  final DateTime date;
  final int movingTimeS;
}

/// Saved movement totals only. No GPS reclassification or time apportioning.
class SessionWeekSummary {
  const SessionWeekSummary({
    required this.weekStart,
    required this.end,
    required this.previousStart,
    required this.previousEnd,
    required this.timezone,
    required this.days,
    required this.movingTimeS,
    required this.sessionCount,
    required this.referenceMovingTimeS,
    required this.omittedSessionIds,
    required this.previousMovingTimeS,
    required this.sessions,
  });
  final DateTime weekStart, end, previousStart, previousEnd;
  final String timezone;
  final List<SessionWeekDay> days;
  final List<SessionWeekEntry> sessions;
  final int movingTimeS, sessionCount;
  final int? referenceMovingTimeS, previousMovingTimeS;
  final List<String> omittedSessionIds;
  bool get partial => omittedSessionIds.isNotEmpty;
}

SessionWeekSummary summarizeSessionWeek({
  required WalkSession reference,
  required List<WalkSession> sessions,
}) {
  final localEnd = asLocal(
    reference.endedAt ?? reference.startedAt,
    timezone: reference.timezone,
  );
  // Use calendar constructors across DST, including the previous cutoff clock.
  DateTime calendar(int offset, {bool clock = false}) {
    if (localEnd is tz.TZDateTime) {
      return tz.TZDateTime(
        localEnd.location,
        localEnd.year,
        localEnd.month,
        localEnd.day + offset,
        clock ? localEnd.hour : 0,
        clock ? localEnd.minute : 0,
        clock ? localEnd.second : 0,
        clock ? localEnd.millisecond : 0,
        clock ? localEnd.microsecond : 0,
      );
    }
    return DateTime(
      localEnd.year,
      localEnd.month,
      localEnd.day + offset,
      clock ? localEnd.hour : 0,
      clock ? localEnd.minute : 0,
      clock ? localEnd.second : 0,
      clock ? localEnd.millisecond : 0,
      clock ? localEnd.microsecond : 0,
    );
  }

  final lastIncluded = asLocal(
    (reference.endedAt ?? reference.startedAt).subtract(
      const Duration(microseconds: 1),
    ),
    timezone: reference.timezone,
  );
  final lastDateOffset =
      DateTime.utc(lastIncluded.year, lastIncluded.month, lastIncluded.day)
          .difference(DateTime.utc(localEnd.year, localEnd.month, localEnd.day))
          .inDays;
  final mondayOffset = lastDateOffset + 1 - lastIncluded.weekday;
  final weekStart = calendar(mondayOffset);
  final previousStart = calendar(mondayOffset - 7);
  final previousEnd = calendar(-7, clock: true);
  final seconds = List<int>.filled(7, 0);
  final omitted = <String>[];
  final included = <SessionWeekEntry>[];
  var total = 0, count = 0, previous = 0, previousCount = 0;
  var previousPartial = false;
  int? contribution;
  final seen = <String>{};
  for (final session in sessions) {
    if (session.status != SessionStatus.completed || !seen.add(session.id)) {
      continue;
    }
    final start = session.startedAt;
    final end = session.endedAt;
    for (final isPrevious in [false, true]) {
      final lower = isPrevious ? previousStart : weekStart;
      final upper = isPrevious ? previousEnd : localEnd;
      if (start.isAfter(upper) ||
          !start.isBefore(upper) ||
          (end != null && !end.isAfter(lower))) {
        continue;
      }
      final localStart = asLocal(start, timezone: reference.timezone);
      final localStop = end == null
          ? null
          : asLocal(
              end.subtract(const Duration(microseconds: 1)),
              timezone: reference.timezone,
            );
      final moving = session.movingTimeS;
      final distance = session.totalDistanceM;
      final valid =
          end != null &&
          !end.isAfter(upper) &&
          !start.isBefore(lower) &&
          end.isAfter(start) &&
          localStop!.year == localStart.year &&
          localStop.month == localStart.month &&
          localStop.day == localStart.day &&
          moving != null &&
          moving >= 0 &&
          moving <= positiveDurationSeconds(start, end) &&
          distance != null &&
          distance.isFinite &&
          distance >= 0;
      if (!valid) {
        if (isPrevious) {
          previousPartial = true;
        } else {
          omitted.add(session.id);
        }
        continue;
      }
      if (isPrevious) {
        previous += moving;
        if (moving > 0) previousCount++;
      } else {
        total += moving;
        seconds[localStart.weekday - 1] += moving;
        if (moving > 0) {
          count++;
          included.add(
            SessionWeekEntry(
              id: session.id,
              startedAt: localStart,
              movingTimeS: moving,
            ),
          );
        }
        if (session.id == reference.id) contribution = moving;
      }
    }
  }
  included.sort((a, b) {
    final byStart = a.startedAt.compareTo(b.startedAt);
    return byStart != 0 ? byStart : a.id.compareTo(b.id);
  });
  return SessionWeekSummary(
    sessions: List.unmodifiable(included),
    weekStart: weekStart,
    end: localEnd,
    previousStart: previousStart,
    previousEnd: previousEnd,
    timezone: reference.timezone,
    days: List.unmodifiable([
      for (var i = 0; i < 7; i++)
        SessionWeekDay(
          date: calendar(mondayOffset + i),
          movingTimeS: seconds[i],
        ),
    ]),
    movingTimeS: total,
    sessionCount: count,
    referenceMovingTimeS: contribution,
    omittedSessionIds: List.unmodifiable(omitted),
    previousMovingTimeS:
        omitted.isEmpty && !previousPartial && previousCount > 0
        ? previous
        : null,
  );
}
