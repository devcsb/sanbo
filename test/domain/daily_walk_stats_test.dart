import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/services/daily_walk_stats.dart';

void main() {
  test('daily stats exposes distance and duration helpers', () {
    final stats = DailyWalkStats(
      date: DateTime(2026, 8, 15),
      walkCount: 2,
      totalDistanceM: 2345,
      totalDurationS: 3723,
    );

    expect(stats.date, DateTime(2026, 8, 15));
    expect(stats.totalDistanceKm, 2.345);
    expect(
      stats.totalDuration,
      const Duration(hours: 1, minutes: 2, seconds: 3),
    );
  });

  test('zero day is normalized to local midnight', () {
    final stats = DailyWalkStats.zero(DateTime(2026, 8, 15, 23, 59));

    expect(stats.date, DateTime(2026, 8, 15));
    expect(stats.walkCount, 0);
    expect(stats.totalDistanceM, 0);
    expect(stats.totalDurationS, 0);
  });
}
