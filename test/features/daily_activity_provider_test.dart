import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanbo/data/activity_data_source.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/features/history/history_providers.dart';

import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('daily activity starts with today as the selected week end', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final fixedToday = DateTime(2026, 8, 15);
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        dailyWeekEndProvider.overrideWith((_) => fixedToday),
        dailySelectedDayProvider.overrideWith((_) => fixedToday),
      ],
    );
    addTearDown(container.dispose);

    final snapshot = await container.read(dailyActivityProvider.future);

    expect(snapshot.days, hasLength(7));
    expect(snapshot.days.first.date, DateTime(2026, 8, 9));
    expect(snapshot.days.last.date, fixedToday);
    expect(container.read(dailySelectedDayProvider), fixedToday);
  });

  test('selecting a day does not reload the repository', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final fixedToday = DateTime(2026, 8, 15);
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        dailyWeekEndProvider.overrideWith((_) => fixedToday),
        dailySelectedDayProvider.overrideWith((_) => fixedToday),
      ],
    );
    addTearDown(container.dispose);

    final before = await container.read(dailyActivityProvider.future);
    container.read(dailySelectedDayProvider.notifier).state = DateTime(
      2026,
      8,
      12,
    );
    final after = await container.read(dailyActivityProvider.future);

    expect(identical(after, before), isTrue);
    expect(container.read(dailySelectedDayProvider), DateTime(2026, 8, 12));
  });

  test('moving a week requests exactly a seven-day half-open range', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final fixedToday = DateTime(2026, 8, 15);
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        dailyWeekEndProvider.overrideWith((_) => fixedToday),
        dailySelectedDayProvider.overrideWith((_) => fixedToday),
      ],
    );
    addTearDown(container.dispose);

    await container.read(dailyActivityProvider.future);
    container.read(dailyWeekEndProvider.notifier).state = DateTime(2026, 8, 8);
    container.read(dailySelectedDayProvider.notifier).state = DateTime(
      2026,
      8,
      8,
    );
    final snapshot = await container.read(dailyActivityProvider.future);

    expect(snapshot.days.first.date, DateTime(2026, 8, 2));
    expect(snapshot.days.last.date, DateTime(2026, 8, 8));
  });

  test('history tick refreshes daily activity', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final fixedToday = DateTime(2026, 8, 15);
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        dailyWeekEndProvider.overrideWith((_) => fixedToday),
        dailySelectedDayProvider.overrideWith((_) => fixedToday),
      ],
    );
    addTearDown(container.dispose);

    final before = await container.read(dailyActivityProvider.future);
    await _completeSession(repo, DateTime(2026, 8, 15));
    container.read(historyTickProvider.notifier).state++;
    final after = await container.read(dailyActivityProvider.future);

    expect(identical(after, before), isFalse);
    expect(after.days.last.walkCount, 1);
  });

  test('health steps remain separate from gps walk totals', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final fixedToday = DateTime(2026, 8, 15);
    final source = _FakeActivitySource([
      DailyStepSnapshot(
        date: DateTime(2026, 8, 15),
        steps: 1234,
        source: ActivitySourceKind.healthConnect,
        coverage: ActivityCoverage.complete,
      ),
    ]);
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        activityDataSourceProvider.overrideWithValue(source),
        dailyWeekEndProvider.overrideWith((_) => fixedToday),
        dailySelectedDayProvider.overrideWith((_) => fixedToday),
      ],
    );
    addTearDown(container.dispose);

    final snapshot = await container.read(dailyActivityProvider.future);

    expect(snapshot.days.last.totalDistanceM, 0);
    expect(snapshot.stepsByDate[fixedToday]?.steps, 1234);
  });
}

class _FakeActivitySource implements ActivityDataSource {
  _FakeActivitySource(this.rows);

  final List<DailyStepSnapshot> rows;

  @override
  Future<List<DailyStepSnapshot>> readDailySteps({
    required DateTime startDate,
    required DateTime endDateExclusive,
  }) async => rows;
}

Future<void> _completeSession(WalkRepository repo, DateTime startedAt) async {
  final session = await repo.startSession(startedAt: startedAt);
  await repo.completeSession(
    sessionId: session.id,
    endedAt: startedAt.add(const Duration(minutes: 10)),
    totalDistanceM: 500,
    durationS: 600,
    movingTimeS: 600,
    stationaryTimeS: 0,
    avgSpeedMps: 0.83,
    validSampleCount: 1,
  );
}
