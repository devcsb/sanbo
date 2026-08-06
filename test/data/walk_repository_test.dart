import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';
import 'package:sanbo/domain/services/walk_stats.dart';

import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('completed history supports bounded pages and aggregate stats', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    for (var i = 0; i < 3; i++) {
      final started = DateTime(2026, 7, 20, 10 + i);
      final session = await repo.startSession(startedAt: started);
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
  });

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
