import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/services/session_deadline.dart';
import 'package:sanbo/domain/services/session_guard.dart';

void main() {
  test('calculates absolute duration deadlines from UTC instants', () {
    final started = DateTime.utc(2026, 8, 29);
    final deadlines = SessionDeadlinePolicy.calculate(
      started,
      const SessionGuardPolicy(),
    );

    expect(deadlines.durationWarningAt, DateTime.utc(2026, 8, 29, 4, 45));
    expect(deadlines.durationLimitAt, DateTime.utc(2026, 8, 29, 5));
  });

  test('evaluates the five-hour limit at the exact instant', () {
    final started = DateTime.utc(2026, 8, 29);
    final deadlines = SessionDeadlinePolicy.calculate(
      started,
      const SessionGuardPolicy(),
    );

    expect(
      SessionDeadlinePolicy.evaluate(
        deadlines,
        started.add(const Duration(hours: 5)),
      ),
      SessionDeadlineEvent.durationLimit,
    );
  });

  test('returns no event before warning and keeps a due limit priority', () {
    final started = DateTime.utc(2026, 8, 29);
    final deadlines = SessionDeadlinePolicy.calculate(
      started,
      const SessionGuardPolicy(),
    );

    expect(
      SessionDeadlinePolicy.evaluate(
        deadlines,
        started.add(const Duration(hours: 4, minutes: 44, seconds: 59)),
      ),
      SessionDeadlineEvent.none,
    );
    expect(
      SessionDeadlinePolicy.evaluate(
        deadlines.copyWith(
          stationaryWarningAt: started.add(const Duration(hours: 4)),
          stationaryLimitAt: started.add(const Duration(hours: 4, minutes: 30)),
        ),
        started.add(const Duration(hours: 4, minutes: 46)),
      ),
      SessionDeadlineEvent.stationaryLimit,
    );
  });
}
