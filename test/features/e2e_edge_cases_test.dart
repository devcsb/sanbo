import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/fixtures/synthetic_trace.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/pipeline/segment_merger.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';

import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('empty walk (no GPS) is discarded, not saved as 0 km session', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.granted,
    );
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await controller.start();
    expect(container.read(sessionControllerProvider).isTracking, isTrue);

    final ended = await controller.stop();
    expect(ended, isNull);
    expect(await repo.listCompleted(), isEmpty);
    expect(await repo.getActiveSession(), isNull);

    final state = container.read(sessionControllerProvider);
    expect(state.isTracking, isFalse);
    expect(state.errorMessage, isNotNull);
    expect(state.errorMessage, contains('GPS'));
  });

  test('double start while tracking is ignored', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.granted,
    );
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await controller.start();
    final firstId = container.read(sessionControllerProvider).session!.id;

    await controller.start(); // should no-op
    final secondId = container.read(sessionControllerProvider).session!.id;
    expect(secondId, firstId);
    expect(await repo.getActiveSession(), isNotNull);
  });

  test('filtered GPS jumps are not shown on map after stop', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.granted,
    );
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await controller.start();
    final session = container.read(sessionControllerProvider).session!;

    final good = buildWalkTrace(
      start: session.startedAt,
      duration: const Duration(minutes: 1),
      step: const Duration(seconds: 4),
      speedMps: 1.2,
    );
    // Impossible jump: ~1 degree lon in 1s.
    final jump = LocationSample(
      timestamp: session.startedAt.add(const Duration(minutes: 1, seconds: 2)),
      latitude: 37.5,
      longitude: 128.0,
      accuracyM: 5,
      speedMps: 100,
    );
    controller.debugIngestSamples([...good, jump]);

    final ended = await controller.stop();
    expect(ended, isNotNull);

    final samples = await repo.getSamples(ended!.id);
    expect(samples, isNotEmpty);
    final jumpRows = samples.where(
      (s) => (s.longitude - 128.0).abs() < 0.01,
    );
    expect(jumpRows, isNotEmpty);
    expect(jumpRows.every((s) => s.isFilteredOut), isTrue);

    // Map path uses non-filtered only.
    final mapPoints = samples.where((s) => !s.isFilteredOut).toList();
    expect(mapPoints.any((s) => (s.longitude - 128.0).abs() < 0.01), isFalse);
    expect(ended.totalDistanceM, greaterThan(20));
    // Distance should not include ~80+ km jump.
    expect(ended.totalDistanceM, lessThan(5000));
  });

  test('segment bulk label edit applies to all minutes', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);

    final start = DateTime(2026, 7, 12, 9, 0, 0);
    final session = await repo.startSession(
      mode: TrackingMode.balanced,
      startedAt: start,
    );
    final samples = buildWalkTrace(
      start: start,
      duration: const Duration(minutes: 5),
      step: const Duration(seconds: 4),
    );
    await repo.insertSamples(session.id, samples);
    final endedAt = start.add(const Duration(minutes: 5, seconds: 5));
    final result = SessionPipeline().process(
      session: session,
      rawSamples: samples,
      endedAt: endedAt,
    );
    await repo.replaceSamples(session.id, result.filteredSamples);
    await repo.replaceWindows(session.id, result.windows);
    await repo.completeSession(
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

    final windows = await repo.getWindows(session.id);
    expect(windows.length, greaterThanOrEqualTo(5));
    final segments = SegmentMerger().merge(windows);
    expect(segments, isNotEmpty);
    final walkSeg = segments.firstWhere(
      (s) =>
          s.label == ActivityLabel.walkSteady ||
          s.label == ActivityLabel.walkBrisk ||
          s.label == ActivityLabel.strollSlow,
      orElse: () => segments.first,
    );
    expect(walkSeg.minuteCount, greaterThanOrEqualTo(2));

    await repo.updateWindowsUserLabel(
      sessionId: session.id,
      windowStarts: walkSeg.windows.map((w) => w.windowStart).toList(),
      userLabel: ActivityLabel.parkLinger,
    );

    final after = await repo.getWindows(session.id);
    final touched = after.where(
      (w) => walkSeg.windows.any(
        (ow) =>
            ow.windowStart.year == w.windowStart.year &&
            ow.windowStart.month == w.windowStart.month &&
            ow.windowStart.day == w.windowStart.day &&
            ow.windowStart.hour == w.windowStart.hour &&
            ow.windowStart.minute == w.windowStart.minute,
      ),
    );
    expect(touched, isNotEmpty);
    expect(
      touched.every((w) => w.displayLabel == ActivityLabel.parkLinger),
      isTrue,
    );
    expect(touched.every((w) => w.userConfirmed), isTrue);

    final merged = SegmentMerger().merge(after);
    expect(
      merged.any(
        (s) =>
            s.label == ActivityLabel.parkLinger &&
            s.minuteCount >= walkSeg.minuteCount,
      ),
      isTrue,
    );
  });

  test('urban soft-poor + recovery continue keeps distance', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.granted,
    );
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await controller.start();
    final session = container.read(sessionControllerProvider).session!;

    const degPerMeter = 1 / 111320.0;
    final samples = <LocationSample>[
      for (var i = 0; i < 25; i++)
        LocationSample(
          timestamp: session.startedAt.add(Duration(seconds: i * 4)),
          latitude: 37.5 + i * 4 * 1.2 * degPerMeter,
          longitude: 127.0,
          accuracyM: i < 4 ? 120 : 12,
          speedMps: 1.2,
        ),
    ];
    controller.debugIngestSamples(samples);
    // Simulate checkpoint persistence mid-walk.
    await repo.insertSamples(session.id, samples);

    // Cold-start recovery path.
    final container2 = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(
          SyntheticLocationEngine(permission: LocationPermissionState.granted),
        ),
      ],
    );
    addTearDown(container2.dispose);
    final c2 = container2.read(sessionControllerProvider.notifier);
    await c2.restoreIfNeeded();
    expect(container2.read(sessionControllerProvider).needsRecovery, isTrue);
    expect(container2.read(sessionControllerProvider).liveDistanceM, greaterThan(20));

    final ended = await c2.stop();
    expect(ended, isNotNull);
    expect(ended!.totalDistanceM, greaterThan(20));
    expect(ended.validSampleCount, greaterThan(10));
  });

  test('too-short walk is discarded from history', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.granted,
    );
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await controller.start();
    final session = container.read(sessionControllerProvider).session!;
    // 2 samples ~ a few meters, duration under 20s.
    final samples = [
      LocationSample(
        timestamp: session.startedAt,
        latitude: 37.5,
        longitude: 127.0,
        accuracyM: 8,
        speedMps: 1.0,
      ),
      LocationSample(
        timestamp: session.startedAt.add(const Duration(seconds: 3)),
        latitude: 37.50001,
        longitude: 127.0,
        accuracyM: 8,
        speedMps: 1.0,
      ),
    ];
    controller.debugIngestSamples(samples);
    final ended = await controller.stop();
    expect(ended, isNull);
    expect(await repo.listCompleted(), isEmpty);
    final state = container.read(sessionControllerProvider);
    expect(state.errorMessage, isNotNull);
    expect(state.errorMessage, contains('짧'));
  });

  test('history duration format includes hours when needed', () {
    // Pure format parity with HistoryScreen (inlined assertion of algorithm).
    String fmt(Duration d) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      if (h > 0) return '$h:$m:$s';
      return '$m:$s';
    }
    expect(fmt(const Duration(minutes: 5, seconds: 7)), '05:07');
    expect(fmt(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });
}
