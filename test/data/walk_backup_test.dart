import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/data/app_database.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/services/app_backup.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_db.dart';
import '../helpers/route_exclusion_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'full backup restores route, edits, notes, and remembered place',
    () async {
      final source = await openTestRepository();
      final target = await openTestRepository();
      addTearDown(source.close);
      addTearDown(target.close);

      final start = DateTime(2026, 8, 1, 9);
      final session = await source.startSession(
        mode: TrackingMode.batterySaver,
        startedAt: start,
      );
      final samples = [
        for (var index = 0; index < 4; index++)
          LocationSample(
            timestamp: start.add(Duration(seconds: index * 20)),
            latitude: 37.5665 + index * 0.0001,
            longitude: 126.978,
            accuracyM: 7,
            speedMps: 1.1,
            altitudeM: 28,
            isFilteredOut: index == 3,
          ),
      ];
      await source.insertSamples(session.id, samples);
      final window = MinuteWindow(
        windowStart: start,
        durationS: 60,
        partial: false,
        sampleCount: 3,
        rawSampleCount: 4,
        distanceM: 33,
        avgSpeedMps: 0.55,
        maxSpeedMps: 1.1,
        stationaryRatio: 0.2,
        quality: WindowQuality.high,
        centroidLat: 37.56665,
        centroidLon: 126.978,
        startLat: 37.5665,
        startLon: 126.978,
        endLat: 37.5668,
        endLon: 126.978,
        hypothesisLabel: ActivityLabel.walkSteady,
        hypothesisConfidence: 0.86,
        evidence: const ['평균 속도 0.55m/s'],
        userLabel: ActivityLabel.cafeOrShop,
        userNote: '잠시 커피',
        userConfirmed: true,
      );
      await source.replaceWindows(session.id, [window]);
      await source.rememberPlaceForWindows(
        sessionId: session.id,
        windowStarts: [window.windowStart],
        latitude: 37.56665,
        longitude: 126.978,
        name: '시청 옆 카페',
        address: '서울특별시 중구',
      );
      await source.completeSession(
        sessionId: session.id,
        endedAt: start.add(const Duration(minutes: 1)),
        totalDistanceM: 33,
        durationS: 60,
        movingTimeS: 48,
        stationaryTimeS: 12,
        avgSpeedMps: 0.55,
        validSampleCount: 3,
        medianAccuracyM: 7,
      );
      await source.updateSessionNotes(session.id, '토요일 아침 산책');

      final raw = await source.createBackupJson(
        exportedAt: DateTime.utc(2026, 8, 1, 1),
      );
      final archive = AppBackupCodec.decode(raw);
      expect(archive.table('sessions'), hasLength(1));
      expect(archive.table('location_samples'), hasLength(4));
      expect(archive.table('minute_windows'), hasLength(1));
      expect(archive.table('places'), hasLength(1));

      final result = await target.importBackup(archive);
      expect(result.importedSessions, 1);
      expect(result.skippedSessions, 0);
      expect(result.importedSamples, 4);
      expect(result.importedWindows, 1);

      final restored = await target.getSession(session.id);
      expect(restored?.notes, '토요일 아침 산책');
      expect(restored?.trackingMode, TrackingMode.batterySaver);
      final restoredSamples = await target.getSamples(session.id);
      expect(restoredSamples, hasLength(4));
      expect(restoredSamples.last.isFilteredOut, isTrue);
      final restoredWindows = await target.getWindows(session.id);
      expect(restoredWindows.single.userLabel, ActivityLabel.cafeOrShop);
      expect(restoredWindows.single.userNote, '잠시 커피');
      expect(restoredWindows.single.placeName, '시청 옆 카페');
      expect(restoredWindows.single.placeAddress, '서울특별시 중구');

      final duplicate = await target.importBackup(archive);
      expect(duplicate.importedSessions, 0);
      expect(duplicate.skippedSessions, 1);
      expect(await target.listCompleted(), hasLength(1));
      expect(await target.getSamples(session.id), hasLength(4));
    },
  );

  test('invalid coordinates roll back the entire merge', () async {
    final source = await openTestRepository();
    final target = await openTestRepository();
    addTearDown(source.close);
    addTearDown(target.close);

    final start = DateTime(2026, 8, 1, 11);
    final session = await source.startSession(startedAt: start);
    await source.insertSamples(session.id, [
      LocationSample(
        timestamp: start,
        latitude: 37.5,
        longitude: 127,
        accuracyM: 5,
      ),
    ]);
    await source.completeSession(
      sessionId: session.id,
      endedAt: start.add(const Duration(minutes: 1)),
      totalDistanceM: 0,
      durationS: 60,
      movingTimeS: 0,
      stationaryTimeS: 60,
      avgSpeedMps: 0,
      validSampleCount: 1,
    );
    final decoded =
        jsonDecode(await source.createBackupJson()) as Map<String, dynamic>;
    final tables = decoded['tables'] as Map<String, dynamic>;
    final samples = tables['location_samples'] as List<dynamic>;
    (samples.single as Map<String, dynamic>)['lat'] = 999;

    expect(
      () => target.importBackupJson(jsonEncode(decoded)),
      throwsFormatException,
    );
    expect(await target.listCompleted(), isEmpty);
  });

  test('historical invalid REAL values export and import safely', () async {
    final path =
        '${Directory.systemTemp.path}/sanbo_historical_non_finite_${DateTime.now().microsecondsSinceEpoch}.db';
    final source = await openTestRepository(path: path);
    final target = await openTestRepository();
    addTearDown(source.close);
    addTearDown(target.close);

    final start = DateTime(2026, 8, 1, 11, 30);
    final session = await source.startSession(startedAt: start);
    await source.insertSamples(session.id, [
      LocationSample(
        timestamp: start,
        latitude: 37.5,
        longitude: 127,
        accuracyM: 5,
        speedMps: 1,
        altitudeM: 20,
      ),
    ]);
    await source.replaceWindows(session.id, [
      MinuteWindow(
        windowStart: start,
        durationS: 60,
        partial: false,
        sampleCount: 1,
        rawSampleCount: 1,
        distanceM: 0,
        avgSpeedMps: 0,
        maxSpeedMps: 1,
        stationaryRatio: 1,
        quality: WindowQuality.high,
        centroidLat: 37.5,
        centroidLon: 127,
        startLat: 37.5,
        startLon: 127,
        endLat: 37.5,
        endLon: 127,
        hypothesisLabel: ActivityLabel.stationary,
        hypothesisConfidence: 1,
        evidence: const ['historical fixture'],
      ),
    ]);
    await source.completeSession(
      sessionId: session.id,
      endedAt: start.add(const Duration(minutes: 1)),
      totalDistanceM: 0,
      durationS: 60,
      movingTimeS: 0,
      stationaryTimeS: 60,
      avgSpeedMps: 0,
      validSampleCount: 1,
    );

    // Simulate a row written by 0.7.0 before non-finite normalization was
    // enforced at repository boundaries.
    final historicalDb = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await historicalDb.update(
      'location_samples',
      {
        'accuracy_m': -1,
        'speed_mps': -1,
        'altitude_m': double.negativeInfinity,
      },
      where: 'session_id = ?',
      whereArgs: [session.id],
    );
    await historicalDb.insert('location_samples', {
      'session_id': session.id,
      'ts': start.add(const Duration(seconds: 30)).toIso8601String(),
      'lat': double.infinity,
      'lon': 127,
      'accuracy_m': 5,
      'speed_mps': 1,
      'altitude_m': 20,
      'is_filtered_out': 1,
    });
    await historicalDb.update(
      'minute_windows',
      {
        'distance_m': -1,
        'max_speed_mps': double.infinity,
        'stationary_ratio': -1,
        'centroid_lat': 999,
      },
      where: 'session_id = ?',
      whereArgs: [session.id],
    );
    await historicalDb.update(
      'sessions',
      {'total_distance_m': double.infinity},
      where: 'id = ?',
      whereArgs: [session.id],
    );
    await historicalDb.close();

    final raw = await source.createBackupJson();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final tables = decoded['tables'] as Map<String, dynamic>;
    final samples = tables['location_samples'] as List<dynamic>;
    final sample = samples.single as Map<String, dynamic>;
    expect(sample['accuracy_m'], isNull);
    expect(sample['speed_mps'], isNull);
    expect(sample['altitude_m'], isNull);
    final windows = tables['minute_windows'] as List<dynamic>;
    final window = windows.single as Map<String, dynamic>;
    expect(window['distance_m'], 0);
    expect(window['max_speed_mps'], 0);
    expect(window['stationary_ratio'], 0);
    expect(window['centroid_lat'], isNull);
    expect(window['centroid_lon'], isNull);
    final sessions = tables['sessions'] as List<dynamic>;
    expect(
      (sessions.single as Map<String, dynamic>)['total_distance_m'],
      isNull,
    );

    final result = await target.importBackupJson(raw);
    expect(result.importedSessions, 1);
    expect(result.importedSamples, 1);
    expect(result.importedWindows, 1);
  });

  test(
    'future database backups and active sessions are handled safely',
    () async {
      final source = await openTestRepository();
      final target = await openTestRepository();
      addTearDown(source.close);
      addTearDown(target.close);

      await source.startSession(startedAt: DateTime(2026, 8, 1, 12));
      final raw = await source.createBackupJson();
      expect(AppBackupCodec.decode(raw).table('sessions'), isEmpty);

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded['database_schema_version'] = schemaVersion + 1;
      expect(
        () => target.importBackupJson(jsonEncode(decoded)),
        throwsFormatException,
      );
      expect(await target.listCompleted(), isEmpty);
      expect(await target.getActiveSession(), isNull);
    },
  );

  test(
    'backup v2 round-trips exclusions and v1 imports as unexcluded',
    () async {
      final source = await openTestRepository();
      final target = await openTestRepository();
      addTearDown(source.close);
      addTearDown(target.close);
      final fixture = await seedCompletedTwoMinuteWalk(source);
      final exclusion = await source.excludeRouteSegment(
        sessionId: fixture.session.id,
        segment: fixture.segments.last,
        createdAt: DateTime.utc(2026, 8, 21, 1),
      );

      final raw = await source.createBackupJson();
      final archive = AppBackupCodec.decode(raw);
      expect(archive.backupSchemaVersion, 2);
      expect(archive.table('route_exclusions').single['id'], exclusion.id);

      await target.importBackup(archive);
      expect(
        (await target.getRouteExclusions(fixture.session.id)).single.id,
        exclusion.id,
      );
      expect(
        (await target.getWindows(
          fixture.session.id,
        )).any((window) => window.userExclusionId == exclusion.id),
        isTrue,
      );

      final v1Target = await openTestRepository();
      addTearDown(v1Target.close);
      await v1Target.importBackupJson(_downgradeFixtureToBackupV1(raw));
      expect(await v1Target.getRouteExclusions(fixture.session.id), isEmpty);
      expect(
        (await v1Target.getWindows(
          fixture.session.id,
        )).every((window) => window.userExclusionId == null),
        isTrue,
      );
    },
  );

  test('first partial minute exclusion exports imports and restores', () async {
    final source = await openTestRepository();
    final target = await openTestRepository();
    addTearDown(source.close);
    addTearDown(target.close);
    final fixture = await _seedCompletedPartialMinuteWalk(source);
    final exclusion = await source.excludeRouteSegment(
      sessionId: fixture.session.id,
      segment: fixture.segments.single,
    );

    final result = await target.importBackupJson(
      await source.createBackupJson(),
    );

    expect(result.importedSessions, 1);
    expect(
      (await target.getRouteExclusions(fixture.session.id)).single.id,
      exclusion.id,
    );
    expect(
      (await target.getWindows(fixture.session.id)).single.userExclusionId,
      exclusion.id,
    );

    await target.restoreRouteExclusion(
      sessionId: fixture.session.id,
      exclusionId: exclusion.id,
    );

    expect(await target.getRouteExclusions(fixture.session.id), isEmpty);
    expect((await target.getSession(fixture.session.id))!.durationS, 10);
    expect(
      (await target.getWindows(fixture.session.id)).single.userExclusionId,
      isNull,
    );
  });

  test(
    'sub-second partial minute from the app round-trips through backup',
    () async {
      final source = await openTestRepository();
      final target = await openTestRepository();
      addTearDown(source.close);
      addTearDown(target.close);

      final start = DateTime.utc(2026, 8, 21, 0, 0, 59, 500);
      final end = start.add(const Duration(microseconds: 500000));
      final session = await source.startSession(startedAt: start);
      final sample = LocationSample(
        timestamp: start,
        latitude: 37.5,
        longitude: 127,
        accuracyM: 5,
      );
      final result = SessionPipeline().process(
        session: session,
        rawSamples: [sample],
        endedAt: end,
      );
      expect(result.windows.single.durationS, 1);
      await source.finalizeSession(
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

      final imported = await target.importBackupJson(
        await source.createBackupJson(),
      );
      expect(imported.importedWindows, 1);
      expect((await target.getWindows(session.id)).single.durationS, 1);
    },
  );

  test(
    'backup rejects window spans that cannot be produced by a completed session',
    () async {
      final source = await openTestRepository();
      addTearDown(source.close);
      final fixture = await _seedCompletedPartialMinuteWalk(source);
      final raw = await source.createBackupJson();

      final corruptions = <void Function(Map<String, dynamic>)>[
        (backup) {
          final window =
              (_tables(backup)['minute_windows'] as List<dynamic>).single
                  as Map<String, dynamic>;
          window['duration_s'] = 11;
        },
        (backup) {
          final window =
              (_tables(backup)['minute_windows'] as List<dynamic>).single
                  as Map<String, dynamic>;
          window['partial'] = 0;
        },
        (backup) {
          final sample =
              (_tables(backup)['location_samples'] as List<dynamic>).first
                  as Map<String, dynamic>;
          sample['ts'] = fixture.session.endedAt!
              .add(const Duration(microseconds: 1))
              .toIso8601String();
          sample['is_filtered_out'] = 0;
        },
      ];

      for (final corrupt in corruptions) {
        final target = await openTestRepository();
        addTearDown(target.close);
        final backup = jsonDecode(raw) as Map<String, dynamic>;
        corrupt(backup);

        await expectLater(
          target.importBackupJson(jsonEncode(backup)),
          throwsFormatException,
        );
        expect(await target.listCompleted(), isEmpty);
      }
    },
  );

  test(
    'backup keeps filtered audit samples outside the completed session',
    () async {
      final source = await openTestRepository();
      final target = await openTestRepository();
      addTearDown(source.close);
      addTearDown(target.close);
      final fixture = await _seedCompletedPartialMinuteWalk(source);
      final backup =
          jsonDecode(await source.createBackupJson()) as Map<String, dynamic>;
      final sample =
          (_tables(backup)['location_samples'] as List<dynamic>).first
              as Map<String, dynamic>;
      sample['ts'] = fixture.session.endedAt!
          .add(const Duration(minutes: 1))
          .toIso8601String();
      sample['is_filtered_out'] = 1;

      final result = await target.importBackupJson(jsonEncode(backup));

      expect(result.importedSamples, fixture.samples.length);
      expect(
        (await target.getSamples(
          fixture.session.id,
        )).any((item) => item.timestamp.isAfter(fixture.session.endedAt!)),
        isTrue,
      );
    },
  );

  test(
    'same-minute disjoint v2 exclusions import with their representative id',
    () async {
      final path =
          '${Directory.systemTemp.path}/sanbo_disjoint_exclusions_${DateTime.now().microsecondsSinceEpoch}.db';
      final source = await openTestRepository(path: path);
      final target = await openTestRepository();
      addTearDown(source.close);
      addTearDown(target.close);
      final fixture = await seedCompletedTwoMinuteWalk(source);
      final minute = fixture.windows.first.windowStart.toUtc();
      final legacyDb = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(legacyDb.close);
      await legacyDb.insert('route_exclusions', {
        'id': 'same-minute-a',
        'session_id': fixture.session.id,
        'start_at': minute.add(const Duration(seconds: 10)).toIso8601String(),
        'end_at': minute.add(const Duration(seconds: 20)).toIso8601String(),
        'reason': 'vehicle',
        'created_at': minute.toIso8601String(),
      });
      await legacyDb.insert('route_exclusions', {
        'id': 'same-minute-b',
        'session_id': fixture.session.id,
        'start_at': minute.add(const Duration(seconds: 30)).toIso8601String(),
        'end_at': minute.add(const Duration(seconds: 40)).toIso8601String(),
        'reason': 'vehicle',
        'created_at': minute.add(const Duration(seconds: 1)).toIso8601String(),
      });
      await legacyDb.update(
        'minute_windows',
        {'user_exclusion_id': 'same-minute-a'},
        where: 'session_id = ? AND window_start = ?',
        whereArgs: [
          fixture.session.id,
          fixture.windows.first.windowStart.toIso8601String(),
        ],
      );

      final backup =
          jsonDecode(await source.createBackupJson()) as Map<String, dynamic>;
      final tables = _tables(backup);
      // Keep only the legacy representative on the minute row.
      final window = (tables['minute_windows'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((row) => row['window_start'] == minute.toIso8601String());
      window['user_exclusion_id'] = 'same-minute-a';

      final imported = await target.importBackupJson(jsonEncode(backup));
      expect(imported.importedSessions, 1);
      expect(
        (await target.getRouteExclusions(
          fixture.session.id,
        )).map((item) => item.id),
        containsAll(<String>['same-minute-a', 'same-minute-b']),
      );
      expect(
        (await target.getWindows(fixture.session.id)).first.userExclusionId,
        'same-minute-a',
      );

      await target.restoreRouteExclusion(
        sessionId: fixture.session.id,
        exclusionId: 'same-minute-a',
      );
      expect(
        (await target.getRouteExclusions(
          fixture.session.id,
        )).map((item) => item.id),
        contains('same-minute-b'),
      );
    },
  );

  test('corrupt v2 exclusions reject the full import', () async {
    final source = await openTestRepository();
    addTearDown(source.close);
    final fixture = await seedCompletedTwoMinuteWalk(source);
    await source.excludeRouteSegment(
      sessionId: fixture.session.id,
      segment: fixture.segments.last,
      createdAt: DateTime.utc(2026, 8, 21, 1),
    );
    final raw = await source.createBackupJson();

    final corruptions = <void Function(Map<String, dynamic>)>[
      (backup) {
        final exclusions = _tables(backup)['route_exclusions'] as List<dynamic>;
        (exclusions.single as Map<String, dynamic>)['session_id'] = 'other';
      },
      (backup) {
        final tables = _tables(backup);
        final exclusions = tables['route_exclusions'] as List<dynamic>;
        final exclusion = exclusions.single as Map<String, dynamic>;
        final windows = tables['minute_windows'] as List<dynamic>;
        final excluded = windows.cast<Map<String, dynamic>>().firstWhere(
          (window) => window['user_exclusion_id'] == exclusion['id'],
        );
        excluded['window_start'] = DateTime.utc(
          2026,
          8,
          21,
          3,
        ).toIso8601String();
      },
      (backup) {
        final windows = _tables(backup)['minute_windows'] as List<dynamic>;
        final window = windows.cast<Map<String, dynamic>>().first;
        final start = DateTime.parse(window['window_start'] as String);
        window['window_start'] = start
            .add(const Duration(seconds: 30))
            .toIso8601String();
      },
      (backup) {
        final exclusions = _tables(backup)['route_exclusions'] as List<dynamic>;
        final duplicate = Map<String, dynamic>.from(
          exclusions.single as Map<String, dynamic>,
        )..['id'] = 'overlap';
        exclusions.add(duplicate);
      },
      (backup) {
        final windows = _tables(backup)['minute_windows'] as List<dynamic>;
        (windows.first as Map<String, dynamic>).remove('user_exclusion_id');
      },
      (backup) => backup['backup_schema_version'] = 3,
    ];

    for (final corrupt in corruptions) {
      final target = await openTestRepository();
      addTearDown(target.close);
      final backup = jsonDecode(raw) as Map<String, dynamic>;
      corrupt(backup);

      expect(
        () => target.importBackupJson(jsonEncode(backup)),
        throwsFormatException,
      );
      expect(await target.listCompleted(), isEmpty);
      expect(await target.getRouteExclusions(fixture.session.id), isEmpty);
    }
  });

  test(
    'a window referencing another completed session exclusion rolls back all imports',
    () async {
      final source = await openTestRepository();
      final target = await openTestRepository();
      addTearDown(source.close);
      addTearDown(target.close);
      final first = await seedCompletedTwoMinuteWalk(source);
      final exclusion = await source.excludeRouteSegment(
        sessionId: first.session.id,
        segment: first.segments.last,
      );
      final second = await seedCompletedTwoMinuteWalk(source);
      final backup =
          jsonDecode(await source.createBackupJson()) as Map<String, dynamic>;
      final windows = _tables(backup)['minute_windows'] as List<dynamic>;
      final foreignWindow = windows.cast<Map<String, dynamic>>().firstWhere(
        (window) => window['session_id'] == second.session.id,
      );
      foreignWindow['user_exclusion_id'] = exclusion.id;

      await expectLater(
        target.importBackupJson(jsonEncode(backup)),
        throwsFormatException,
      );
      expect(await target.listCompleted(), isEmpty);
      expect(await target.getRouteExclusions(first.session.id), isEmpty);
      expect(await target.getRouteExclusions(second.session.id), isEmpty);
    },
  );

  test('empty v2 backup imports without writing rows', () async {
    final target = await openTestRepository();
    addTearDown(target.close);
    final raw = AppBackupCodec.encode(
      databaseSchemaVersion: 2,
      tables: const {
        'sessions': [],
        'location_samples': [],
        'minute_windows': [],
        'places': [],
        'route_exclusions': [],
      },
    );
    final archive = await compute(
      AppBackupCodec.decodeBytes,
      Uint8List.fromList(utf8.encode(raw)),
    );

    final result = await target.importBackup(archive);

    expect(result.importedSessions, 0);
    expect(await target.listCompleted(), isEmpty);
  });
}

Map<String, dynamic> _tables(Map<String, dynamic> backup) =>
    backup['tables'] as Map<String, dynamic>;

String _downgradeFixtureToBackupV1(String raw) {
  final backup = jsonDecode(raw) as Map<String, dynamic>;
  backup['backup_schema_version'] = 1;
  backup['database_schema_version'] = 3;
  final tables = _tables(backup);
  tables.remove('route_exclusions');
  for (final row in tables['minute_windows']! as List<dynamic>) {
    (row as Map<String, dynamic>).remove('user_exclusion_id');
  }
  return jsonEncode(backup);
}

Future<CompletedRouteFixture> _seedCompletedPartialMinuteWalk(
  WalkRepository repo,
) async {
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
  return (
    session: completed,
    samples: await repo.getSamples(session.id),
    windows: windows,
    segments: pipeline.segmentMerger.merge(
      windows,
      sessionId: session.id,
      sessionStart: completed.startedAt,
      sessionEnd: completed.endedAt,
    ),
  );
}
