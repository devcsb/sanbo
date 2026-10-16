import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/data/app_database.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_db.dart';

typedef _Draft = ({
  WalkSession session,
  SessionProcessResult result,
  DateTime end,
});

Future<_Draft> _prepare(
  WalkRepository repo, {
  double speed = 3,
  String timezone = 'Asia/Seoul',
}) async {
  final start = DateTime.utc(2026, 10, 16, 9);
  final session = await repo.startSession(startedAt: start, timezone: timezone);
  final end = start.add(const Duration(minutes: 2));
  final result = SessionPipeline().process(
    session: session,
    rawSamples: [
      for (var t = 0; t <= 120; t += 20)
        LocationSample(
          timestamp: start.add(Duration(seconds: t)),
          latitude: t * speed / 111194.92664455874,
          longitude: 0,
          accuracyM: 5,
        ),
    ],
    endedAt: end,
  );
  return (session: session, result: result, end: end);
}

Future<WalkSession> _finalize(WalkRepository repo, _Draft draft) =>
    repo.finalizeSession(
      session: draft.session,
      samples: draft.result.filteredSamples,
      windows: draft.result.windows,
      endedAt: draft.end,
      totalDistanceM: draft.result.metrics.totalDistanceM,
      durationS: draft.result.metrics.durationS,
      movingTimeS: draft.result.metrics.movingTimeS,
      stationaryTimeS: draft.result.metrics.stationaryTimeS,
      avgSpeedMps: draft.result.metrics.avgSpeedMps,
      validSampleCount: draft.result.metrics.validSampleCount,
      medianAccuracyM: draft.result.metrics.medianAccuracyM,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late WalkRepository repo;
  setUp(() async {
    ensureSqfliteFfi();
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = WalkRepository(db);
  });
  tearDown(() => repo.close());

  for (final zone in [
    (name: 'Asia/Seoul', wall: '2026-10-16T18:00:00.000', hour: 18),
    (name: 'America/New_York', wall: '2026-10-16T05:00:00.000', hour: 5),
  ]) {
    for (final bulk in [false, true]) {
      test(
        'vehicle edit uses the actual legacy ${zone.name} row, bulk=$bulk',
        () async {
          final draft = await _prepare(repo, speed: 1, timezone: zone.name);
          await _finalize(repo, draft);
          final beforeSamples = await db.query('location_samples');
          await db.update(
            'minute_windows',
            {'window_start': zone.wall},
            where: 'session_id = ? AND window_start = ?',
            whereArgs: [
              draft.session.id,
              draft.result.windows.first.windowStart.toUtc().toIso8601String(),
            ],
          );
          final oldWallKey = DateTime.utc(2026, 10, 16, zone.hour);
          if (bulk) {
            await repo.updateWindowsUserLabel(
              sessionId: draft.session.id,
              windowStarts: [oldWallKey],
              userLabel: ActivityLabel.vehicle,
            );
          } else {
            await repo.updateWindowUserLabel(
              sessionId: draft.session.id,
              windowStart: oldWallKey,
              userLabel: ActivityLabel.vehicle,
            );
          }
          final windows = await repo.getWindows(draft.session.id);
          expect(windows.first.userLabel, ActivityLabel.vehicle);
          final exclusions = await repo.getRouteExclusions(draft.session.id);
          expect(exclusions, hasLength(1));
          final excluded = exclusions.single;
          expect(excluded.startAt, DateTime.utc(2026, 10, 16, 9));
          expect(excluded.endAt, DateTime.utc(2026, 10, 16, 9, 1));
          expect(windows.last.isUserExcluded, isFalse);
          expect((await repo.getSession(draft.session.id))!.durationS, 60);
          expect(await db.query('location_samples'), beforeSamples);
        },
      );
    }
  }

  test(
    'repeated finalization preserves the first exclusion and raw row IDs',
    () async {
      final draft = await _prepare(repo);
      await _finalize(repo, draft);
      final beforeExclusions = await db.query('route_exclusions');
      final beforeSamples = await db.query('location_samples');
      final beforeWindows = await db.query('minute_windows');
      final again = await _finalize(repo, draft);
      expect(await db.query('route_exclusions'), beforeExclusions);
      expect(await db.query('location_samples'), beforeSamples);
      expect(await db.query('minute_windows'), beforeWindows);
      expect(again.totalDistanceM, 0);
    },
  );

  test('concurrent finalization creates only one exclusion', () async {
    final draft = await _prepare(repo);
    final saved = await Future.wait([
      _finalize(repo, draft),
      _finalize(repo, draft),
    ]);
    expect(await repo.getRouteExclusions(draft.session.id), hasLength(1));
    expect(saved.every((session) => session.durationS == 0), isTrue);
    expect((await repo.getWindows(draft.session.id)).length, 2);
  });

  test(
    'a stale completion retry cannot overwrite a restored and edited walk',
    () async {
      final draft = await _prepare(repo);
      await _finalize(repo, draft);
      final exclusion = (await repo.getRouteExclusions(
        draft.session.id,
      )).single;
      await repo.restoreRouteExclusion(
        sessionId: draft.session.id,
        exclusionId: exclusion.id,
      );
      await repo.updateWindowUserLabel(
        sessionId: draft.session.id,
        windowStart: draft.result.windows.first.windowStart,
        userLabel: ActivityLabel.walkBrisk,
        note: '제외 취소 후 확정',
      );
      await repo.updateSessionNotes(draft.session.id, '보존할 산책 메모');
      final before = await db.query('minute_windows');
      final again = await _finalize(repo, draft);
      expect(await repo.getRouteExclusions(draft.session.id), isEmpty);
      expect(again.totalDistanceM, closeTo(360, 0.001));
      expect(again.notes, '보존할 산책 메모');
      expect(await db.query('minute_windows'), before);
    },
  );

  test(
    'completeSession retry cannot write unexcluded metrics over existing exclusions',
    () async {
      final draft = await _prepare(repo);
      await _finalize(repo, draft);
      final again = await repo.completeSession(
        sessionId: draft.session.id,
        endedAt: draft.end,
        totalDistanceM: 360,
        durationS: 120,
        movingTimeS: 120,
        stationaryTimeS: 0,
        avgSpeedMps: 3,
        validSampleCount: 7,
      );
      expect(again.totalDistanceM, 0);
      expect(again.durationS, 0);
      expect(await repo.getRouteExclusions(draft.session.id), hasLength(1));
    },
  );

  for (final atomic in [true, false]) {
    test(
      'completion cannot resurrect a discarded session, atomic=$atomic',
      () async {
        final draft = await _prepare(repo);
        await db.update(
          'sessions',
          {'status': 'discarded'},
          where: 'id = ?',
          whereArgs: [draft.session.id],
        );
        final operation = atomic
            ? _finalize(repo, draft)
            : repo.completeSession(
                sessionId: draft.session.id,
                endedAt: draft.end,
                totalDistanceM: 360,
                durationS: 120,
                movingTimeS: 120,
                stationaryTimeS: 0,
                avgSpeedMps: 3,
                validSampleCount: 7,
              );
        await expectLater(operation, throwsStateError);
        expect(
          (await repo.getSession(draft.session.id))!.status,
          SessionStatus.discarded,
        );
        expect(await db.query('location_samples'), isEmpty);
        expect(await db.query('route_exclusions'), isEmpty);
      },
    );
  }
}
