import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/data/activity_data_source.dart';

void main() {
  test('unavailable source returns no fabricated zero totals', () async {
    final rows = await const UnavailableActivityDataSource().readDailySteps(
      startDate: DateTime(2026, 8, 1),
      endDateExclusive: DateTime(2026, 8, 2),
    );

    expect(rows, isEmpty);
  });

  test('zero is distinct from unavailable', () {
    final zero = DailyStepSnapshot(
      date: DateTime(2026, 8, 1),
      steps: 0,
      source: ActivitySourceKind.healthConnect,
      coverage: ActivityCoverage.complete,
    );
    final unavailable = DailyStepSnapshot.unavailable(DateTime(2026, 8, 1));

    expect(zero.isAvailable, isTrue);
    expect(unavailable.isAvailable, isFalse);
    expect(unavailable.steps, isNull);
  });
}
