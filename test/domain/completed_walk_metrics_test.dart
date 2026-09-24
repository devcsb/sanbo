import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/services/completed_walk_metrics.dart';
import 'package:sanbo/domain/services/walk_stats.dart';

void main() {
  group('completedAverageSpeedMps', () {
    test('divides trusted distance by moving time', () {
      expect(
        completedAverageSpeedMps(totalDistanceM: 1200, movingTimeS: 600),
        2,
      );
    });

    test('does not depend on the last provider speed persisted elsewhere', () {
      final average = completedAverageSpeedMps(
        totalDistanceM: 1200,
        movingTimeS: 600,
      );

      expect(average, isNot(0.5));
      expect(pacePerKmLabel(average), '8:20 /km');
    });

    test('returns null when distance or moving time is unavailable', () {
      expect(
        completedAverageSpeedMps(totalDistanceM: 0, movingTimeS: 0),
        isNull,
      );
      expect(
        completedAverageSpeedMps(totalDistanceM: 100, movingTimeS: 0),
        isNull,
      );
      expect(
        completedAverageSpeedMps(totalDistanceM: double.nan, movingTimeS: 10),
        isNull,
      );
      expect(
        completedAverageSpeedMps(totalDistanceM: 100, movingTimeS: -1),
        isNull,
      );
    });
  });
}
