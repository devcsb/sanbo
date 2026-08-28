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

  test('health source reads one local half-open day at a time', () async {
    final reader = _FakeDailyStepsReader(
      sourceKind: ActivitySourceKind.healthConnect,
      totals: {DateTime(2026, 8, 1): 0, DateTime(2026, 8, 2): 1234},
    );
    final source = HealthActivityDataSource(reader);

    final rows = await source.readDailySteps(
      startDate: DateTime(2026, 8, 1, 22),
      endDateExclusive: DateTime(2026, 8, 3, 1),
    );

    expect(rows, hasLength(2));
    expect(rows[0].steps, 0);
    expect(rows[1].steps, 1234);
    expect(
      rows.every((row) => row.source == ActivitySourceKind.healthConnect),
      isTrue,
    );
    expect(reader.configureCalls, 1);
    expect(reader.ranges, [
      [DateTime(2026, 8, 1), DateTime(2026, 8, 2)],
      [DateTime(2026, 8, 2), DateTime(2026, 8, 3)],
    ]);
  });

  test('permission denial never fabricates zero steps', () async {
    final reader = _FakeDailyStepsReader(
      sourceKind: ActivitySourceKind.healthConnect,
      permission: false,
    );
    final source = HealthActivityDataSource(reader);

    final rows = await source.readDailySteps(
      startDate: DateTime(2026, 8, 1),
      endDateExclusive: DateTime(2026, 8, 3),
    );

    expect(rows, hasLength(2));
    expect(rows.every((row) => row.steps == null), isTrue);
    expect(
      rows.every((row) => row.source == ActivitySourceKind.denied),
      isTrue,
    );
    expect(reader.readCalls, 0);
  });

  test('one day read failure does not discard the rest of the range', () async {
    final reader = _FakeDailyStepsReader(
      sourceKind: ActivitySourceKind.healthKit,
      totals: {DateTime(2026, 8, 1): 100, DateTime(2026, 8, 3): 300},
      throwOn: DateTime(2026, 8, 2),
    );
    final rows = await HealthActivityDataSource(reader).readDailySteps(
      startDate: DateTime(2026, 8, 1),
      endDateExclusive: DateTime(2026, 8, 4),
    );

    expect(rows.map((row) => row.steps), [100, null, 300]);
    expect(rows[1].coverage, ActivityCoverage.unavailable);
    expect(rows[1].source, ActivitySourceKind.error);
  });

  test(
    'successful daily totals are cached for repeated history reads',
    () async {
      final reader = _FakeDailyStepsReader(
        sourceKind: ActivitySourceKind.healthConnect,
        totals: {DateTime(2026, 8, 1): 100, DateTime(2026, 8, 2): 200},
      );
      final source = HealthActivityDataSource(reader);

      await source.readDailySteps(
        startDate: DateTime(2026, 8, 1),
        endDateExclusive: DateTime(2026, 8, 3),
      );
      await source.readDailySteps(
        startDate: DateTime(2026, 8, 1),
        endDateExclusive: DateTime(2026, 8, 3),
      );

      expect(reader.readCalls, 2);
      expect(reader.permissionChecks, 1);
    },
  );

  test('requesting health access invalidates the daily cache', () async {
    final reader = _FakeDailyStepsReader(
      sourceKind: ActivitySourceKind.healthConnect,
      totals: {DateTime(2026, 8, 1): 100},
    );
    final source = HealthActivityDataSource(reader);

    await source.readDailySteps(
      startDate: DateTime(2026, 8, 1),
      endDateExclusive: DateTime(2026, 8, 2),
    );
    await source.requestAccess();
    await source.readDailySteps(
      startDate: DateTime(2026, 8, 1),
      endDateExclusive: DateTime(2026, 8, 2),
    );

    expect(reader.readCalls, 2);
  });

  test(
    'availability failures remain distinguishable from a read error',
    () async {
      final reader = _FakeDailyStepsReader(
        sourceKind: ActivitySourceKind.healthConnect,
        permissionError: true,
      );
      final rows = await HealthActivityDataSource(reader).readDailySteps(
        startDate: DateTime(2026, 8, 1),
        endDateExclusive: DateTime(2026, 8, 2),
      );

      expect(rows.single.source, ActivitySourceKind.error);
    },
  );
}

final class _FakeDailyStepsReader implements DailyStepsReader {
  _FakeDailyStepsReader({
    required this.sourceKind,
    this.permission = true,
    this.permissionError = false,
    this.totals = const {},
    this.throwOn,
  });

  @override
  final ActivitySourceKind sourceKind;
  final bool permission;
  final bool permissionError;
  final Map<DateTime, int> totals;
  final DateTime? throwOn;
  var configureCalls = 0;
  var permissionChecks = 0;
  var readCalls = 0;
  final ranges = <List<DateTime>>[];

  @override
  Future<void> configure() async => configureCalls++;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool?> hasReadPermission() async {
    permissionChecks++;
    if (permissionError) throw StateError('temporary health failure');
    return permission;
  }

  @override
  Future<bool> requestReadPermission() async => permission;

  @override
  Future<int?> readTotalSteps({
    required DateTime start,
    required DateTime end,
  }) async {
    readCalls++;
    ranges.add([start, end]);
    if (start == throwOn) throw StateError('protected');
    return totals[start];
  }
}
