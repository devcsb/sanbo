import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';
import '../helpers/test_db.dart';
import '../helpers/route_exclusion_fixture.dart';

Map<String, Object?> row({
  String end = '2026-11-07T00:01:00Z',
  num? duration = 60,
  num? moving,
  num? stationary,
  num distance = 10,
}) => {
  'id': 'input',
  'started_at': '2026-11-07T00:00:00Z',
  'ended_at': end,
  'timezone': 'UTC',
  'status': 'completed',
  'tracking_mode': 'balanced',
  'duration_s': duration,
  'moving_time_s': moving,
  'stationary_time_s': stationary,
  'total_distance_m': distance,
};
String backup(Map<String, Object?> session) => jsonEncode({
  'export_kind': 'sanbo_backup',
  'backup_schema_version': 2,
  'database_schema_version': 6,
  'exported_at': '2026-11-07T00:00:00Z',
  'tables': {
    'sessions': [session],
    'location_samples': [],
    'minute_windows': [],
    'route_exclusions': [],
    'places': [],
  },
});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('rejected numeric backups preserve all five populated tables', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final fixture = await seedCompletedTwoMinuteWalk(repo);
    await repo.excludeRouteSegment(
      sessionId: fixture.session.id,
      segment: fixture.segments.last,
    );
    final at = DateTime.utc(2026, 11, 7);
    final before = await repo.createBackupJson(exportedAt: at);
    final tables =
        (jsonDecode(before) as Map<String, dynamic>)['tables']
            as Map<String, dynamic>;
    expect(tables, hasLength(5));
    for (final rows in tables.values) {
      expect(rows as List<dynamic>, isNotEmpty);
    }
    for (final input in [
      row(duration: 9223372036854775807),
      row(distance: 1e308),
      row(end: '3026-11-07T00:00:00Z'),
      row(moving: 50, stationary: 20),
      row(duration: 1e100),
      row(moving: 61),
    ]) {
      await expectLater(
        repo.importBackupJson(backup(input)),
        throwsFormatException,
      );
      expect(await repo.createBackupJson(exportedAt: at), before);
    }
  });
  for (final input in [
    row(duration: 9223372036854775807),
    row(distance: 1e308),
    row(end: '3026-11-07T00:00:00Z'),
    row(moving: 50, stationary: 20),
    row(duration: 1e100),
    row(moving: 61),
  ]) {
    test('invalid backup is rejected atomically: $input', () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      await expectLater(
        repo.importBackupJson(backup(input)),
        throwsFormatException,
      );
      expect(await repo.listCompleted(), isEmpty);
    });
  }
  test(
    'seven day boundary and unknown old movement remain restorable',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      await repo.importBackupJson(
        backup(row(end: '2026-11-14T00:00:00Z', duration: 604800)),
      );
      expect((await repo.getSession('input'))!.movingTimeS, isNull);
    },
  );
  test('one second rounding tolerance is accepted', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    await repo.importBackupJson(backup(row(moving: 31, stationary: 30)));
    expect(await repo.listCompleted(), hasLength(1));
  });
  test(
    'one microsecond beyond seven days is rejected without truncation',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      await expectLater(
        repo.importBackupJson(backup(row(end: '2026-11-14T00:00:00.000001Z'))),
        throwsFormatException,
      );
      expect(await repo.listCompleted(), isEmpty);
    },
  );
  test(
    'seven days starting within a minute produces at most 10081 windows',
    () {
      final start = DateTime.utc(2026, 11, 7, 0, 0, 30);
      final session = WalkSession(
        id: 'partial',
        startedAt: start,
        endedAt: start.add(const Duration(days: 7)),
        timezone: 'UTC',
        status: SessionStatus.completed,
        trackingMode: TrackingMode.balanced,
      );
      final result = SessionPipeline().recalculateCompleted(
        session: session,
        storedSamples: [],
        exclusions: [],
        previousWindows: [],
      );
      expect(result.windows, hasLength(10081));
      expect(result.windows.first.durationS, 30);
      expect(result.windows.last.durationS, 30);
    },
  );
  test(
    'existing overlong records cannot allocate windows on recalculation',
    () {
      final session = WalkSession(
        id: 'legacy',
        startedAt: DateTime.utc(2020),
        endedAt: DateTime.utc(3020),
        timezone: 'UTC',
        status: SessionStatus.completed,
        trackingMode: TrackingMode.balanced,
      );
      expect(
        () => SessionPipeline().recalculateCompleted(
          session: session,
          storedSamples: [],
          exclusions: [],
          previousWindows: [],
        ),
        throwsFormatException,
      );
    },
  );
}
