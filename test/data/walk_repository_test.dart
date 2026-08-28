import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/pipeline/segment_merger.dart';
import 'package:sanbo/domain/pipeline/geo.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';
import 'package:sanbo/domain/services/walk_stats.dart';

import '../helpers/test_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/route_exclusion_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('retrying the same sample batch is idempotent', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final session = await repo.startSession(
      startedAt: DateTime.utc(2026, 8, 29, 0),
    );
    final sample = LocationSample(
      timestamp: session.startedAt,
      latitude: 37.5665,
      longitude: 126.978,
      accuracyM: 6,
      speedMps: 1,
    );
    await repo.insertSamples(session.id, [sample]);
    await repo.insertSamples(session.id, [sample]);

    expect(await repo.getSamples(session.id), hasLength(1));
  });

  test('replaceWindows rolls back when a replacement violates uniqueness', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final session = await repo.startSession(
      startedAt: DateTime.utc(2026, 8, 29, 0),
    );
    MinuteWindow makeWindow() => MinuteWindow(
      windowStart: DateTime.utc(2026, 8, 29, 0),
      durationS: 60,
      partial: false,
      sampleCount: 1,
      rawSampleCount: 1,
      distanceM: 1,
      avgSpeedMps: 1,
      maxSpeedMps: 1,
      stationaryRatio: 0,
      quality: WindowQuality.high,
      hypothesisLabel: ActivityLabel.walkSteady,
    );
    await repo.replaceWindows(session.id, [makeWindow()]);

    await expectLater(
      repo.replaceWindows(session.id, [makeWindow(), makeWindow()]),
      throwsA(isA<DatabaseException>()),
    );
    expect(await repo.getWindows(session.id), hasLength(1));
  });

  test('daily stats sums completed sessions by local start date', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);

    final first = DateTime(2026, 8, 10, 23, 50);
    await _completeSession(
      repo,
      startedAt: first,
      endedAt: DateTime(2026, 8, 11, 0, 10),
      distanceM: 1200,
      durationS: 1200,
    );
    await _completeSession(
      repo,
      startedAt: DateTime(2026, 8, 10, 10),
      endedAt: DateTime(2026, 8, 10, 10, 30),
      distanceM: 800,
      durationS: 1800,
    );
    await _completeSession(
      repo,
      startedAt: DateTime(2026, 8, 11, 9),
      endedAt: DateTime(2026, 8, 11, 10),
      distanceM: 3000,
      durationS: 3600,
    );
    await repo.startSession(startedAt: DateTime(2026, 8, 10, 18));

    final days = await repo.dailyStats(
      startDate: DateTime(2026, 8, 10),
      endDateExclusive: DateTime(2026, 8, 13),
    );

    expect(days.map((day) => day.date), [
      DateTime(2026, 8, 10),
      DateTime(2026, 8, 11),
      DateTime(2026, 8, 12),
    ]);
    expect(days[0].walkCount, 2);
    expect(days[0].totalDistanceM, 2000);
    expect(days[0].totalDurationS, 3000);
    expect(days[1].walkCount, 1);
    expect(days[1].totalDistanceM, 3000);
    expect(days[2].walkCount, 0);
  });

  test('restores persisted window minutes in the session timezone', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);

    final fixture = await seedCompletedTwoMinuteWalk(repo);
    final windows = await repo.getWindows(fixture.session.id);
    final first = windows.first;

    expect(first.windowStart.isUtc, isFalse);
    expect(first.windowStart.year, 2026);
    expect(first.windowStart.month, 8);
    expect(first.windowStart.day, 21);
    expect(first.windowStart.hour, 9);
    expect(first.windowStart.minute, 0);
    expect(first.windowStart.toUtc(), DateTime.utc(2026, 8, 21));
  });

  test(
    'mutates New York windows from a Seoul device using canonical UTC keys',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final start = DateTime.utc(2026, 8, 21, 5, 30);
      final session = await repo.startSession(
        timezone: 'America/New_York',
        startedAt: start,
      );
      final window = MinuteWindow(
        windowStart: floorToMinute(start, timezone: session.timezone),
        durationS: 60,
        partial: false,
        sampleCount: 3,
        rawSampleCount: 3,
        distanceM: 10,
        avgSpeedMps: 1,
        maxSpeedMps: 1,
        stationaryRatio: 0,
        quality: WindowQuality.high,
        hypothesisLabel: ActivityLabel.walkSteady,
      );
      await repo.replaceWindows(session.id, [window]);

      final persisted = (await repo.getWindows(session.id)).single;
      expect(persisted.windowStart.hour, 1);
      expect(persisted.windowStart.toUtc(), start);

      await repo.updateWindowUserLabel(
        sessionId: session.id,
        windowStart: persisted.windowStart,
        userLabel: ActivityLabel.vehicle,
      );
      final place = await repo.rememberPlaceForWindows(
        sessionId: session.id,
        windowStarts: [persisted.windowStart],
        latitude: 40.7,
        longitude: -74,
        name: '뉴욕 장소',
      );

      final updated = (await repo.getWindows(session.id)).single;
      expect(updated.userLabel, ActivityLabel.vehicle);
      expect(updated.placeId, place.id);
    },
  );

  test('DST fold windows mutate the selected UTC occurrence only', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final session = await repo.startSession(
      timezone: 'America/New_York',
      startedAt: DateTime.utc(2026, 11, 1, 5, 30),
    );
    final first = floorToMinute(
      DateTime.utc(2026, 11, 1, 5, 30),
      timezone: session.timezone,
    );
    final second = floorToMinute(
      DateTime.utc(2026, 11, 1, 6, 30),
      timezone: session.timezone,
    );
    MinuteWindow makeWindow(DateTime windowStart) => MinuteWindow(
      windowStart: windowStart,
      durationS: 60,
      partial: false,
      sampleCount: 3,
      rawSampleCount: 3,
      distanceM: 10,
      avgSpeedMps: 1,
      maxSpeedMps: 1,
      stationaryRatio: 0,
      quality: WindowQuality.high,
    );
    await repo.replaceWindows(session.id, [
      makeWindow(first),
      makeWindow(second),
    ]);

    final persisted = await repo.getWindows(session.id);
    expect(persisted, hasLength(2));
    expect(persisted[0].windowStart.hour, 1);
    expect(persisted[1].windowStart.hour, 1);
    expect(persisted[0].windowStart.toUtc(), first.toUtc());
    expect(persisted[1].windowStart.toUtc(), second.toUtc());

    await repo.updateWindowUserLabel(
      sessionId: session.id,
      windowStart: persisted[1].windowStart,
      userLabel: ActivityLabel.vehicle,
    );
    final updated = await repo.getWindows(session.id);
    expect(updated[0].userLabel, isNull);
    expect(updated[1].userLabel, ActivityLabel.vehicle);
  });

  test(
    'daily stats excludes the end boundary and includes zero days',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);

      await _completeSession(
        repo,
        startedAt: DateTime(2026, 8, 12, 8),
        endedAt: DateTime(2026, 8, 12, 9),
        distanceM: 500,
        durationS: 3600,
      );
      await _completeSession(
        repo,
        startedAt: DateTime(2026, 8, 14, 8),
        endedAt: DateTime(2026, 8, 14, 9),
        distanceM: 900,
        durationS: 3600,
      );

      final days = await repo.dailyStats(
        startDate: DateTime(2026, 8, 12, 23, 59),
        endDateExclusive: DateTime(2026, 8, 14),
      );

      expect(days, hasLength(2));
      expect(days.first.walkCount, 1);
      expect(days.last.walkCount, 0);
    },
  );

  test(
    'exclude and restore atomically recalculate while preserving source rows and metadata',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final fixture = await seedCompletedTwoMinuteWalk(repo);
      final beforeSamples = await repo.getSamples(fixture.session.id);

      final exclusion = await repo.excludeRouteSegment(
        sessionId: fixture.session.id,
        segment: fixture.segments.last,
        createdAt: DateTime.utc(2026, 8, 21, 1),
      );

      expect(exclusion.startAt.isUtc, isTrue);
      expect(exclusion.endAt.isUtc, isTrue);
      expect(
        _sampleSnapshot(await repo.getSamples(fixture.session.id)),
        _sampleSnapshot(beforeSamples),
      );
      final excludedWindows = await repo.getWindows(fixture.session.id);
      expect(
        excludedWindows.where(
          (window) => window.userExclusionId == exclusion.id,
        ),
        isNotEmpty,
      );
      expect(excludedWindows.first.userNote, fixture.windows.first.userNote);
      expect(excludedWindows.first.placeId, fixture.windows.first.placeId);
      final reduced = await repo.getSession(fixture.session.id);
      expect(reduced!.durationS, 60);

      await repo.restoreRouteExclusion(
        sessionId: fixture.session.id,
        exclusionId: exclusion.id,
      );
      expect(await repo.getRouteExclusions(fixture.session.id), isEmpty);
      expect(
        _sampleSnapshot(await repo.getSamples(fixture.session.id)),
        _sampleSnapshot(beforeSamples),
      );
      final restored = await repo.getSession(fixture.session.id);
      expect(restored!.durationS, fixture.session.durationS);
      expect(
        restored.totalDistanceM,
        closeTo(fixture.session.totalDistanceM!, 0.001),
      );
    },
  );

  test(
    'multiple exclusions can remove every route segment and restore the full walk',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final fixture = await seedCompletedTwoMinuteWalk(repo);
      expect(fixture.segments, hasLength(2));
      final beforeSamples = _sampleSnapshot(
        await repo.getSamples(fixture.session.id),
      );
      final before = await repo.getSession(fixture.session.id);

      final first = await repo.excludeRouteSegment(
        sessionId: fixture.session.id,
        segment: fixture.segments.first,
      );
      final second = await repo.excludeRouteSegment(
        sessionId: fixture.session.id,
        segment: fixture.segments.last,
      );

      final excludedSession = await repo.getSession(fixture.session.id);
      expect(excludedSession!.totalDistanceM, closeTo(0, 0.001));
      expect(excludedSession.validSampleCount, 1);
      expect(await repo.getRouteExclusions(fixture.session.id), hasLength(2));
      expect(
        (await repo.getWindows(
          fixture.session.id,
        )).every((window) => window.userExclusionId != null),
        isTrue,
      );
      expect(
        _sampleSnapshot(await repo.getSamples(fixture.session.id)),
        beforeSamples,
      );

      await repo.restoreRouteExclusion(
        sessionId: fixture.session.id,
        exclusionId: first.id,
      );
      await repo.restoreRouteExclusion(
        sessionId: fixture.session.id,
        exclusionId: second.id,
      );

      final restored = await repo.getSession(fixture.session.id);
      expect(await repo.getRouteExclusions(fixture.session.id), isEmpty);
      expect(restored!.totalDistanceM, closeTo(before!.totalDistanceM!, 0.001));
      expect(restored.validSampleCount, before.validSampleCount);
      expect(
        (await repo.getWindows(
          fixture.session.id,
        )).every((window) => window.userExclusionId == null),
        isTrue,
      );
      expect(
        _sampleSnapshot(await repo.getSamples(fixture.session.id)),
        beforeSamples,
      );
    },
  );

  test(
    'route exclusion rejects active, unknown, empty, and overlapping selections',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final active = await repo.startSession(
        startedAt: DateTime.utc(2026, 8, 21),
      );
      final empty = _segment(
        start: DateTime.utc(2026, 8, 21),
        windows: const [],
      );
      await expectLater(
        repo.excludeRouteSegment(sessionId: active.id, segment: empty),
        throwsA(isA<StateError>()),
      );
      await repo.completeSession(
        sessionId: active.id,
        endedAt: DateTime.utc(2026, 8, 21, 0, 1),
        totalDistanceM: 0,
        durationS: 60,
        movingTimeS: 0,
        stationaryTimeS: 60,
        avgSpeedMps: 0,
        validSampleCount: 0,
      );
      final fixture = await seedCompletedTwoMinuteWalk(repo);
      await expectLater(
        repo.excludeRouteSegment(sessionId: fixture.session.id, segment: empty),
        throwsA(isA<StateError>()),
      );
      final first = await repo.excludeRouteSegment(
        sessionId: fixture.session.id,
        segment: fixture.segments.last,
      );
      await expectLater(
        repo.excludeRouteSegment(
          sessionId: fixture.session.id,
          segment: fixture.segments.last,
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        repo.restoreRouteExclusion(
          sessionId: fixture.session.id,
          exclusionId: '${first.id}-unknown',
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'route exclusion rejects an arbitrary range that is not an authoritative segment',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final fixture = await seedCompletedTwoMinuteWalk(repo);
      final segment = _segment(
        start: fixture.windows.first.windowStart.add(
          const Duration(seconds: 10),
        ),
        endInclusive: fixture.windows.first.windowStart,
        durationS: 20,
        sessionId: fixture.session.id,
        windows: [fixture.windows.first],
      );

      await expectLater(
        repo.excludeRouteSegment(
          sessionId: fixture.session.id,
          segment: segment,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('touching authoritative route exclusions are accepted', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final fixture = await seedCompletedTwoMinuteWalk(repo);
    final first = fixture.segments.first;
    final last = fixture.segments.last;

    final firstExclusion = await repo.excludeRouteSegment(
      sessionId: fixture.session.id,
      segment: first,
    );
    final secondExclusion = await repo.excludeRouteSegment(
      sessionId: fixture.session.id,
      segment: last,
    );

    expect(firstExclusion.endAt, secondExclusion.startAt);
    expect(
      (await repo.getRouteExclusions(
        fixture.session.id,
      )).map((item) => item.id),
      [firstExclusion.id, secondExclusion.id],
    );
  });

  test(
    'DST offset instant selects the same persisted completed minute',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final start = DateTime.parse('2026-11-01T01:00:00-04:00');
      final session = await repo.startSession(startedAt: start);
      final samples = [
        for (var second = 0; second <= 120; second += 20)
          LocationSample(
            timestamp: start.add(Duration(seconds: second)),
            latitude: 37.5,
            longitude: 127 + second * 0.00001,
            accuracyM: 5,
          ),
      ];
      final pipeline = SessionPipeline();
      final result = pipeline.process(
        session: session,
        rawSamples: samples,
        endedAt: start.add(const Duration(minutes: 2)),
      );
      await repo.finalizeSession(
        session: session,
        samples: result.filteredSamples,
        windows: result.windows,
        endedAt: start.add(const Duration(minutes: 2)),
        totalDistanceM: result.metrics.totalDistanceM,
        durationS: result.metrics.durationS,
        movingTimeS: result.metrics.movingTimeS,
        stationaryTimeS: result.metrics.stationaryTimeS,
        avgSpeedMps: result.metrics.avgSpeedMps,
        validSampleCount: result.metrics.validSampleCount,
        medianAccuracyM: result.metrics.medianAccuracyM,
      );
      await repo.updateWindowUserLabel(
        sessionId: session.id,
        windowStart: result.windows.first.windowStart,
        userLabel: ActivityLabel.vehicle,
      );
      final windows = await repo.getWindows(session.id);
      final segment = pipeline.segmentMerger
          .merge(
            windows,
            sessionId: session.id,
            sessionStart: session.startedAt,
            sessionEnd: start.add(const Duration(minutes: 2)),
          )
          .first;

      final exclusion = await repo.excludeRouteSegment(
        sessionId: session.id,
        segment: segment,
      );

      expect(exclusion.startAt, start.toUtc());
      expect(exclusion.endAt, start.toUtc().add(const Duration(minutes: 1)));
    },
  );

  test('route exclusion rejects a discontinuous window selection', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final start = DateTime.utc(2026, 8, 21);
    final session = await repo.startSession(startedAt: start);
    final samples = [
      for (var second = 0; second <= 180; second += 20)
        LocationSample(
          timestamp: start.add(Duration(seconds: second)),
          latitude: 37.5,
          longitude: 127 + second * 0.00001,
          accuracyM: 5,
        ),
    ];
    final result = SessionPipeline().process(
      session: session,
      rawSamples: samples,
      endedAt: start.add(const Duration(minutes: 3)),
    );
    await repo.finalizeSession(
      session: session,
      samples: result.filteredSamples,
      windows: result.windows,
      endedAt: start.add(const Duration(minutes: 3)),
      totalDistanceM: result.metrics.totalDistanceM,
      durationS: result.metrics.durationS,
      movingTimeS: result.metrics.movingTimeS,
      stationaryTimeS: result.metrics.stationaryTimeS,
      avgSpeedMps: result.metrics.avgSpeedMps,
      validSampleCount: result.metrics.validSampleCount,
    );
    final windows = await repo.getWindows(session.id);
    final discontinuous = _segment(
      start: windows.first.windowStart,
      endInclusive: windows.last.windowStart,
      durationS: 120,
      sessionId: session.id,
      windows: [windows.first, windows.last],
    );

    await expectLater(
      repo.excludeRouteSegment(sessionId: session.id, segment: discontinuous),
      throwsA(isA<StateError>()),
    );
  });

  test('first partial minute can be excluded and restored exactly', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final minute = DateTime.utc(2026, 8, 21);
    final start = minute.add(const Duration(seconds: 50));
    final end = minute.add(const Duration(minutes: 1));
    final session = await repo.startSession(startedAt: start);
    final samples = [
      LocationSample(
        timestamp: start,
        latitude: 37.5,
        longitude: 127,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: start.add(const Duration(seconds: 5)),
        latitude: 37.5001,
        longitude: 127,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: end,
        latitude: 37.5002,
        longitude: 127,
        accuracyM: 5,
      ),
    ];
    final pipeline = SessionPipeline();
    final result = pipeline.process(
      session: session,
      rawSamples: samples,
      endedAt: end,
    );
    final completed = await repo.finalizeSession(
      session: session,
      samples: result.filteredSamples,
      windows: result.windows,
      endedAt: end,
      totalDistanceM: result.metrics.totalDistanceM,
      durationS: result.metrics.durationS,
      movingTimeS: result.metrics.movingTimeS,
      stationaryTimeS: result.metrics.stationaryTimeS,
      avgSpeedMps: result.metrics.avgSpeedMps,
      validSampleCount: result.metrics.validSampleCount,
    );
    final windows = await repo.getWindows(session.id);
    final segment = pipeline.segmentMerger
        .merge(
          windows,
          sessionId: session.id,
          sessionStart: completed.startedAt,
          sessionEnd: completed.endedAt,
        )
        .single;

    final exclusion = await repo.excludeRouteSegment(
      sessionId: session.id,
      segment: segment,
    );
    expect(exclusion.startAt, start);
    expect(exclusion.endAt, end);
    expect((await repo.getSession(session.id))!.durationS, 0);

    await repo.restoreRouteExclusion(
      sessionId: session.id,
      exclusionId: exclusion.id,
    );
    expect(await repo.getRouteExclusions(session.id), isEmpty);
    expect((await repo.getSession(session.id))!.durationS, 10);
    expect((await repo.getWindows(session.id)).single.userExclusionId, isNull);
  });

  test('exclude and restore never reintroduce micro-jitter distance', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final start = DateTime.utc(2026, 8, 21);
    final end = start.add(const Duration(minutes: 2));
    final session = await repo.startSession(startedAt: start);
    const degreesPerMeter = 1 / 111320.0;
    final samples = [
      LocationSample(
        timestamp: start,
        latitude: 37.5,
        longitude: 127,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: start.add(const Duration(seconds: 10)),
        latitude: 37.5 + 0.8 * degreesPerMeter,
        longitude: 127,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: start.add(const Duration(minutes: 1, seconds: 11)),
        latitude: 37.5 + 100 * degreesPerMeter,
        longitude: 127,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: end,
        latitude: 37.5 + 200 * degreesPerMeter,
        longitude: 127,
        accuracyM: 5,
      ),
    ];
    final pipeline = SessionPipeline();
    final result = pipeline.process(
      session: session,
      rawSamples: samples,
      endedAt: end,
    );
    final completed = await repo.finalizeSession(
      session: session,
      samples: result.filteredSamples,
      windows: result.windows,
      endedAt: end,
      totalDistanceM: result.metrics.totalDistanceM,
      durationS: result.metrics.durationS,
      movingTimeS: result.metrics.movingTimeS,
      stationaryTimeS: result.metrics.stationaryTimeS,
      avgSpeedMps: result.metrics.avgSpeedMps,
      validSampleCount: result.metrics.validSampleCount,
    );
    await repo.updateWindowUserLabel(
      sessionId: session.id,
      windowStart: start.add(const Duration(minutes: 1)),
      userLabel: ActivityLabel.vehicle,
    );
    final windows = await repo.getWindows(session.id);
    expect(windows.first.distanceM, 0);
    final segment = pipeline.segmentMerger
        .merge(
          windows,
          sessionId: session.id,
          sessionStart: completed.startedAt,
          sessionEnd: completed.endedAt,
        )
        .last;

    final exclusion = await repo.excludeRouteSegment(
      sessionId: session.id,
      segment: segment,
    );
    expect((await repo.getSession(session.id))!.totalDistanceM, 0);

    await repo.restoreRouteExclusion(
      sessionId: session.id,
      exclusionId: exclusion.id,
    );
    expect(
      (await repo.getSession(session.id))!.totalDistanceM,
      closeTo(completed.totalDistanceM!, 0.001),
    );
    expect((await repo.getWindows(session.id)).first.distanceM, 0);
  });

  test(
    'route exclusion rejects a segment from another session at the same instant',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final target = await seedCompletedTwoMinuteWalk(repo);
      final foreign = await seedCompletedTwoMinuteWalk(repo);

      await expectLater(
        repo.excludeRouteSegment(
          sessionId: target.session.id,
          segment: foreign.segments.last,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'route exclusion rejects a segment with zero declared duration',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final fixture = await seedCompletedTwoMinuteWalk(repo);

      await expectLater(
        repo.excludeRouteSegment(
          sessionId: fixture.session.id,
          segment: _segment(
            start: fixture.windows.first.windowStart,
            durationS: 0,
            sessionId: fixture.session.id,
            windows: [fixture.windows.first],
          ),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  for (final failure in <({String name, String sql})>[
    (
      name: 'exclusion_insert',
      sql: '''
CREATE TRIGGER fail_route_exclusion_insert
BEFORE INSERT ON route_exclusions
BEGIN SELECT RAISE(ABORT, 'forced exclusion failure'); END
''',
    ),
    (
      name: 'window_replacement',
      sql: '''
CREATE TRIGGER fail_window_insert
BEFORE INSERT ON minute_windows
BEGIN SELECT RAISE(ABORT, 'forced window failure'); END
''',
    ),
    (
      name: 'session_update',
      sql: '''
CREATE TRIGGER fail_session_rollup_update
BEFORE UPDATE OF total_distance_m ON sessions
BEGIN SELECT RAISE(ABORT, 'forced session failure'); END
''',
    ),
  ]) {
    test('${failure.name} rolls back every route-edit table', () async {
      final path =
          '${Directory.systemTemp.path}/sanbo_route_rollback_${failure.name}_${DateTime.now().microsecondsSinceEpoch}.db';
      addTearDown(() => databaseFactory.deleteDatabase(path));
      final repo = await openTestRepository(path: path);
      addTearDown(repo.close);
      final fixture = await seedCompletedTwoMinuteWalk(repo);
      final before = await snapshotRouteEditTables(path);
      final injector = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await injector.execute(failure.sql);
      await injector.close();

      await expectLater(
        repo.excludeRouteSegment(
          sessionId: fixture.session.id,
          segment: fixture.segments.last,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await snapshotRouteEditTables(path), before);
    });
  }

  test('daily stats rejects an empty or reversed date range', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);

    expect(
      () => repo.dailyStats(
        startDate: DateTime(2026, 8, 10),
        endDateExclusive: DateTime(2026, 8, 10),
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.dailyStats(
        startDate: DateTime(2026, 8, 11),
        endDateExclusive: DateTime(2026, 8, 10),
      ),
      throwsArgumentError,
    );
  });

  test('daily stats range uses the completed-start index', () async {
    final path =
        '${Directory.systemTemp.path}/sanbo_daily_plan_${DateTime.now().microsecondsSinceEpoch}.db';
    final repo = await openTestRepository(path: path);
    await repo.close();
    final db = await databaseFactory.openDatabase(path);
    addTearDown(db.close);

    final plan = await db.rawQuery(
      '''
EXPLAIN QUERY PLAN
SELECT started_at,
       timezone,
       total_distance_m,
       duration_s
FROM sessions
WHERE status = ? AND started_at >= ? AND started_at < ?
ORDER BY started_at ASC
''',
      ['completed', '2026-08-10T00:00:00', '2026-08-17T00:00:00'],
    );

    expect(plan.join(' '), contains('idx_sessions_status_started_at'));
  });

  test(
    'completed history supports bounded pages and aggregate stats',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      for (var i = 0; i < 3; i++) {
        final started = DateTime.utc(2026, 7, 20, 10 + i);
        final session = await repo.startSession(
          startedAt: started,
          timezone: 'UTC',
        );
        await repo.completeSession(
          sessionId: session.id,
          endedAt: started.add(Duration(minutes: i + 1)),
          totalDistanceM: (i + 1) * 1000,
          durationS: (i + 1) * 60,
          movingTimeS: (i + 1) * 50,
          stationaryTimeS: (i + 1) * 10,
          avgSpeedMps: 1,
          validSampleCount: i + 1,
        );
      }

      final page = await repo.listCompleted(limit: 2);
      expect(page, hasLength(2));
      expect(page.first.startedAt.hour, 12);

      final stats = await repo.completedStats();
      expect(stats, isA<WalkStats>());
      expect(stats.walkCount, 3);
      expect(stats.totalDistanceM, 6000);
      expect(stats.totalDurationS, 360);
      expect(stats.longestDurationS, 180);
    },
  );

  test(
    'completed pages use a stable id tie-breaker for equal start times',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final started = DateTime(2026, 7, 20, 10);
      for (var i = 0; i < 3; i++) {
        final session = await repo.startSession(startedAt: started);
        await repo.completeSession(
          sessionId: session.id,
          endedAt: started.add(const Duration(minutes: 1)),
          totalDistanceM: 100,
          durationS: 60,
          movingTimeS: 60,
          stationaryTimeS: 0,
          avgSpeedMps: 1,
          validSampleCount: 1,
        );
      }

      final firstPage = await repo.listCompleted(limit: 2);
      final secondPage = await repo.listCompleted(limit: 2, offset: 2);
      final ids = [...firstPage, ...secondPage].map((s) => s.id).toList();

      expect(firstPage, hasLength(2));
      expect(secondPage, hasLength(1));
      expect(ids.toSet(), hasLength(3));
      expect(ids, orderedEquals([...ids]..sort((a, b) => b.compareTo(a))));
    },
  );

  test(
    'completed history sorts mixed legacy and UTC instants by real time',
    () async {
      final path =
          '${Directory.systemTemp.path}/sanbo_mixed_timestamp_${DateTime.now().microsecondsSinceEpoch}.db';
      final repo = await openTestRepository(path: path);
      final legacy = await repo.startSession(
        timezone: 'Asia/Seoul',
        startedAt: DateTime(2026, 8, 22, 10),
      );
      await repo.completeSession(
        sessionId: legacy.id,
        endedAt: DateTime(2026, 8, 22, 10, 1),
        totalDistanceM: 100,
        durationS: 60,
        movingTimeS: 60,
        stationaryTimeS: 0,
        avgSpeedMps: 1,
        validSampleCount: 1,
      );
      final modern = await repo.startSession(
        startedAt: DateTime.utc(2026, 8, 22, 1, 30),
      );
      await repo.completeSession(
        sessionId: modern.id,
        endedAt: DateTime.utc(2026, 8, 22, 1, 31),
        totalDistanceM: 100,
        durationS: 60,
        movingTimeS: 60,
        stationaryTimeS: 0,
        avgSpeedMps: 1,
        validSampleCount: 1,
      );
      await repo.close();

      final db = await databaseFactory.openDatabase(path);
      await db.update(
        'sessions',
        {'started_at': '2026-08-22T10:00:00.000'},
        where: 'id = ?',
        whereArgs: [legacy.id],
      );
      await db.close();

      final reopened = await WalkRepository.open(path: path);
      final page = await reopened.listCompleted(limit: 1);

      expect(page.single.id, modern.id);
      await reopened.close();

      final normalizedDb = await databaseFactory.openDatabase(path);
      addTearDown(normalizedDb.close);
      final normalized = await normalizedDb.query(
        'sessions',
        columns: const ['started_at'],
        where: 'id = ?',
        whereArgs: [legacy.id],
      );
      expect(normalized.single['started_at'], '2026-08-22T01:00:00.000000Z');
    },
  );

  test(
    'completed history falls back for offset and fractional precision variants',
    () async {
      final path =
          '${Directory.systemTemp.path}/sanbo_timestamp_variants_${DateTime.now().microsecondsSinceEpoch}.db';
      final repo = await openTestRepository(path: path);
      final offset = await repo.startSession(
        startedAt: DateTime.utc(2026, 8, 22, 1),
      );
      await repo.completeSession(
        sessionId: offset.id,
        endedAt: DateTime.utc(2026, 8, 22, 1, 1),
        totalDistanceM: 100,
        durationS: 60,
        movingTimeS: 60,
        stationaryTimeS: 0,
        avgSpeedMps: 1,
        validSampleCount: 1,
      );
      final precise = await repo.startSession(
        startedAt: DateTime.utc(2026, 8, 22, 1, 0, 0, 0, 1),
      );
      await repo.completeSession(
        sessionId: precise.id,
        endedAt: DateTime.utc(2026, 8, 22, 1, 1, 0, 0, 1),
        totalDistanceM: 100,
        durationS: 60,
        movingTimeS: 60,
        stationaryTimeS: 0,
        avgSpeedMps: 1,
        validSampleCount: 1,
      );
      final later = await repo.startSession(
        startedAt: DateTime.utc(2026, 8, 22, 2),
      );
      await repo.completeSession(
        sessionId: later.id,
        endedAt: DateTime.utc(2026, 8, 22, 2, 1),
        totalDistanceM: 100,
        durationS: 60,
        movingTimeS: 60,
        stationaryTimeS: 0,
        avgSpeedMps: 1,
        validSampleCount: 1,
      );
      await repo.close();

      final db = await databaseFactory.openDatabase(path);
      await db.update(
        'sessions',
        {'started_at': '2026-08-22T10:00:00.000+09:00'},
        where: 'id = ?',
        whereArgs: [offset.id],
      );
      await db.close();

      final reopened = await WalkRepository.open(path: path);
      addTearDown(reopened.close);
      final page = await reopened.listCompleted();

      expect(
        page.map((session) => session.id),
        orderedEquals([later.id, precise.id, offset.id]),
      );
    },
  );

  test('persist session samples windows and survive re-open query', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);

    final start = DateTime(2026, 7, 12, 10, 0, 0);
    final session = await repo.startSession(
      mode: TrackingMode.balanced,
      startedAt: start,
    );

    final samples = List.generate(20, (i) {
      return LocationSample(
        timestamp: start.add(Duration(seconds: i * 4)),
        latitude: 37.5 + i * 0.00004,
        longitude: 127.0,
        accuracyM: 8,
        speedMps: 1.2,
      );
    });
    await repo.insertSamples(session.id, samples);

    final endedAt = start.add(const Duration(minutes: 2));
    final result = SessionPipeline().process(
      session: session,
      rawSamples: samples,
      endedAt: endedAt,
    );
    expect(result.metrics.totalDistanceM, greaterThan(0));
    expect(result.windows, isNotEmpty);

    await repo.replaceWindows(session.id, result.windows);
    final completed = await repo.completeSession(
      sessionId: session.id,
      endedAt: endedAt,
      totalDistanceM: result.metrics.totalDistanceM,
      durationS: result.metrics.durationS,
      movingTimeS: result.metrics.movingTimeS,
      stationaryTimeS: result.metrics.stationaryTimeS,
      avgSpeedMps: result.metrics.avgSpeedMps,
      validSampleCount: result.metrics.validSampleCount,
      medianAccuracyM: result.metrics.medianAccuracyM,
    );

    expect(completed.totalDistanceM, greaterThan(0));
    final listed = await repo.listCompleted();
    expect(listed.any((s) => s.id == session.id), isTrue);

    final loadedSamples = await repo.getSamples(session.id);
    expect(loadedSamples.length, samples.length);

    final windows = await repo.getWindows(session.id);
    expect(windows.length, result.windows.length);
    expect(windows.first.hypothesisLabel, isNot(ActivityLabel.unknown));

    final first = windows.first;
    await repo.updateWindowUserLabel(
      sessionId: session.id,
      windowStart: first.windowStart,
      userLabel: ActivityLabel.cafeOrShop,
    );
    final updated = await repo.getWindows(session.id);
    final u = updated.firstWhere((w) => w.windowStart == first.windowStart);
    expect(u.userLabel, ActivityLabel.cafeOrShop);
    expect(u.displayLabel, ActivityLabel.cafeOrShop);
    expect(u.userConfirmed, isTrue);

    await repo.deleteSession(session.id);
    expect(await repo.getSession(session.id), isNull);
    expect(await repo.getSamples(session.id), isEmpty);
    expect(await repo.getWindows(session.id), isEmpty);
  });

  test(
    'does not persist non-finite or out-of-range location samples',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final session = await repo.startSession(
        startedAt: DateTime.utc(2026, 8, 21),
      );

      await repo.insertSamples(session.id, [
        LocationSample(
          timestamp: session.startedAt,
          latitude: double.nan,
          longitude: 127,
        ),
        LocationSample(
          timestamp: session.startedAt.add(const Duration(seconds: 1)),
          latitude: 37.5,
          longitude: double.infinity,
        ),
        LocationSample(
          timestamp: session.startedAt.add(const Duration(seconds: 2)),
          latitude: 37.5,
          longitude: 127,
          speedMps: double.infinity,
          accuracyM: double.nan,
        ),
      ]);

      final samples = await repo.getSamples(session.id);
      expect(samples, hasLength(1));
      expect(samples.single.latitude, 37.5);
      expect(samples.single.longitude, 127);
      expect(samples.single.speedMps, isNull);
      expect(samples.single.accuracyM, isNull);

      await repo.completeSession(
        sessionId: session.id,
        endedAt: session.startedAt.add(const Duration(seconds: 3)),
        totalDistanceM: 0,
        durationS: 3,
        movingTimeS: 0,
        stationaryTimeS: 3,
        avgSpeedMps: 0,
        validSampleCount: 1,
      );

      final finalizeSession = await repo.startSession(
        startedAt: session.startedAt.add(const Duration(minutes: 1)),
      );
      await repo.finalizeSession(
        session: finalizeSession,
        samples: [
          LocationSample(
            timestamp: finalizeSession.startedAt,
            latitude: double.infinity,
            longitude: 127,
          ),
        ],
        windows: const [],
        endedAt: finalizeSession.startedAt.add(const Duration(seconds: 1)),
        totalDistanceM: 0,
        durationS: 1,
        movingTimeS: 0,
        stationaryTimeS: 1,
        avgSpeedMps: 0,
        validSampleCount: 0,
      );
      expect(await repo.getSamples(finalizeSession.id), isEmpty);
    },
  );

  test('session notes can be updated', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final session = await repo.startSession(
      startedAt: DateTime(2026, 7, 18, 12, 0),
    );
    await repo.completeSession(
      sessionId: session.id,
      endedAt: DateTime(2026, 7, 18, 12, 20),
      totalDistanceM: 1000,
      durationS: 1200,
      movingTimeS: 1000,
      stationaryTimeS: 200,
      avgSpeedMps: 1.0,
      validSampleCount: 10,
    );
    await repo.updateSessionNotes(session.id, '  공원 한 바퀴  ');
    final loaded = await repo.getSession(session.id);
    expect(loaded?.notes, '공원 한 바퀴');
    await repo.updateSessionNotes(session.id, '   ');
    final cleared = await repo.getSession(session.id);
    expect(cleared?.notes, isNull);
  });

  test('gap window quality is stored', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final start = DateTime(2026, 7, 12, 11, 0, 0);
    final session = await repo.startSession(startedAt: start);
    final samples = [
      for (var i = 0; i < 5; i++)
        LocationSample(
          timestamp: start.add(Duration(seconds: i * 3)),
          latitude: 37.5,
          longitude: 127.0 + i * 0.00001,
          accuracyM: 5,
          speedMps: 0.5,
        ),
    ];
    await repo.insertSamples(session.id, samples);
    final endedAt = start.add(const Duration(minutes: 3));
    final result = SessionPipeline().process(
      session: session,
      rawSamples: samples,
      endedAt: endedAt,
    );
    await repo.replaceWindows(session.id, result.windows);
    final windows = await repo.getWindows(session.id);
    expect(windows.any((w) => w.quality == WindowQuality.gap), isTrue);
  });

  test('place memory links to windows and can be reused nearby', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final start = DateTime(2026, 7, 20, 14, 0);
    final session = await repo.startSession(startedAt: start);
    final windows = [
      for (var minute = 0; minute < 3; minute++)
        MinuteWindow(
          windowStart: start.add(Duration(minutes: minute)),
          durationS: 60,
          partial: false,
          sampleCount: 8,
          rawSampleCount: 8,
          distanceM: 2,
          avgSpeedMps: 0.05,
          maxSpeedMps: 0.1,
          stationaryRatio: 0.95,
          quality: WindowQuality.high,
          centroidLat: 37.5665,
          centroidLon: 126.978,
          hypothesisLabel: ActivityLabel.placeStay,
          hypothesisConfidence: 0.7,
        ),
    ];
    await repo.replaceWindows(session.id, windows);

    final place = await repo.rememberPlaceForWindows(
      sessionId: session.id,
      windowStarts: windows.map((window) => window.windowStart).toList(),
      latitude: 37.5665,
      longitude: 126.978,
      name: '  시청 앞 벤치  ',
      address: ' 서울특별시 중구 ',
    );
    expect(place.name, '시청 앞 벤치');

    final linked = await repo.getWindows(session.id);
    expect(linked.every((window) => window.placeId == place.id), isTrue);
    expect(linked.every((window) => window.placeName == '시청 앞 벤치'), isTrue);
    expect(linked.every((window) => window.placeAddress == '서울특별시 중구'), isTrue);

    final nearby = await repo.findNearestPlace(
      latitude: 37.56658,
      longitude: 126.978,
    );
    expect(nearby?.id, place.id);

    await repo.deletePlace(place.id);
    final unlinked = await repo.getWindows(session.id);
    expect(unlinked.every((window) => window.placeId == null), isTrue);
    expect(unlinked.every((window) => window.placeName == null), isTrue);
  });

  test(
    'deleting the last linked session prunes its place coordinates',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final start = DateTime(2026, 7, 20, 16, 0);
      final session = await repo.startSession(startedAt: start);
      final window = MinuteWindow(
        windowStart: start,
        durationS: 60,
        partial: false,
        sampleCount: 6,
        rawSampleCount: 6,
        distanceM: 1,
        avgSpeedMps: 0,
        maxSpeedMps: 0,
        stationaryRatio: 1,
        quality: WindowQuality.high,
        centroidLat: 37.5,
        centroidLon: 127,
        hypothesisLabel: ActivityLabel.placeStay,
        hypothesisConfidence: 0.7,
      );
      await repo.replaceWindows(session.id, [window]);
      await repo.rememberPlaceForWindows(
        sessionId: session.id,
        windowStarts: [window.windowStart],
        latitude: 37.5,
        longitude: 127,
        name: '작은 공원',
      );

      await repo.deleteSession(session.id);
      expect(
        await repo.findNearestPlace(latitude: 37.5, longitude: 127),
        isNull,
      );
    },
  );
}

Future<void> _completeSession(
  WalkRepository repo, {
  required DateTime startedAt,
  required DateTime endedAt,
  required double distanceM,
  required int durationS,
}) async {
  final session = await repo.startSession(startedAt: startedAt);
  await repo.completeSession(
    sessionId: session.id,
    endedAt: endedAt,
    totalDistanceM: distanceM,
    durationS: durationS,
    movingTimeS: durationS,
    stationaryTimeS: 0,
    avgSpeedMps: distanceM / durationS,
    validSampleCount: 1,
  );
}

ActivitySegment _segment({
  required DateTime start,
  DateTime? endInclusive,
  int durationS = 0,
  String? sessionId,
  required List<MinuteWindow> windows,
}) => ActivitySegment(
  start: start,
  endInclusive: endInclusive ?? start,
  label: ActivityLabel.unknown,
  confidenceMin: 0,
  distanceM: 0,
  sampleCount: 0,
  durationS: durationS,
  userConfirmed: false,
  windows: windows,
  sessionId: sessionId,
);

List<String> _sampleSnapshot(List<LocationSample> samples) => samples
    .map(
      (sample) => [
        sample.timestamp.toUtc().toIso8601String(),
        sample.latitude,
        sample.longitude,
        sample.accuracyM,
        sample.speedMps,
        sample.altitudeM,
        sample.isFilteredOut,
      ].join('|'),
    )
    .toList(growable: false);
