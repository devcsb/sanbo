import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/data/app_database.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/services/app_backup.dart';

import '../helpers/test_db.dart';

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

      final result = await target.importBackupJson(raw);
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

      final duplicate = await target.importBackupJson(raw);
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
}
