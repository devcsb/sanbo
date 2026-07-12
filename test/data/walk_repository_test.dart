import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';

import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
