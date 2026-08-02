import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/fixtures/synthetic_trace.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';

import '../helpers/test_db.dart';

class _ThrowingPermissionEngine extends SyntheticLocationEngine {
  _ThrowingPermissionEngine()
    : super(permission: LocationPermissionState.granted);

  @override
  Future<LocationPermissionState> requestPermission() {
    throw StateError('permission channel unavailable');
  }
}

class _ImmediateFixEngine implements LocationEngine {
  _ImmediateFixEngine(this.firstFix);

  final LocationSample firstFix;
  final _samples = StreamController<LocationSample>.broadcast(sync: true);
  TrackingMode _mode = TrackingMode.balanced;

  @override
  Stream<LocationSample> get samples => _samples.stream;

  @override
  TrackingMode get mode => _mode;

  @override
  Future<LocationPermissionState> checkPermission() async =>
      LocationPermissionState.granted;

  @override
  Future<LocationPermissionState> requestPermission() async =>
      LocationPermissionState.granted;

  @override
  Future<bool> openSystemSettings() async => true;

  @override
  Future<void> setMode(TrackingMode mode) async => _mode = mode;

  @override
  Future<void> start() async => _samples.add(firstFix);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() => _samples.close();
}

class _ThrowingStartEngine extends SyntheticLocationEngine {
  _ThrowingStartEngine() : super(permission: LocationPermissionState.granted);

  @override
  Future<void> start() {
    throw StateError('foreground service start failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'start → ingest samples → stop yields non-zero metrics and windows',
    () async {
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
      await controller.start(mode: TrackingMode.balanced);
      expect(container.read(sessionControllerProvider).isTracking, isTrue);

      final session = container.read(sessionControllerProvider).session!;
      // Samples aligned to session start so pipeline includes them.
      final trace = buildWalkTrace(
        start: session.startedAt,
        duration: const Duration(minutes: 2),
        speedMps: 1.3,
        step: const Duration(seconds: 3),
      );
      controller.debugIngestSamples(trace);

      final live = container.read(sessionControllerProvider);
      expect(live.sampleCount, trace.length);
      expect(live.liveDistanceM, greaterThan(50));
      expect(live.validSampleCount, greaterThan(10));

      final ended = await controller.stop();
      expect(ended, isNotNull);
      expect(ended!.totalDistanceM, greaterThan(50));
      expect(ended.durationS, greaterThan(0));
      expect(ended.validSampleCount, greaterThan(10));
      expect(ended.avgSpeedMps, greaterThan(0));

      final windows = await repo.getWindows(ended.id);
      expect(windows, isNotEmpty);
      expect(windows.any((w) => w.sampleCount > 0), isTrue);

      // Checkpoint path: samples must have been persisted.
      final samples = await repo.getSamples(ended.id);
      expect(samples.length, greaterThanOrEqualTo(trace.length));

      final listed = await repo.listCompleted();
      expect(listed.map((s) => s.id), contains(ended.id));
    },
  );

  test('stream emit path also accumulates samples', () async {
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
    final trace = buildWalkTrace(
      start: session.startedAt,
      duration: const Duration(seconds: 60),
      step: const Duration(seconds: 4),
    );
    for (final s in trace) {
      engine.emit(s);
    }
    // Allow stream delivery
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      container.read(sessionControllerProvider).sampleCount,
      greaterThan(0),
      reason: 'broadcast stream should deliver to SessionController listener',
    );
  });

  test(
    'background fixes are checkpointed without rebuilding live UI state',
    () async {
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
      await controller.start(mode: TrackingMode.balanced);
      final session = container.read(sessionControllerProvider).session!;
      controller.setAppForeground(false);
      await Future<void>.delayed(Duration.zero);

      final fixes = [
        for (var index = 0; index < 4; index++)
          LocationSample(
            timestamp: session.startedAt.add(Duration(seconds: index * 8)),
            latitude: 37.5665 + index * 0.0001,
            longitude: 126.978,
            accuracyM: 6,
            speedMps: 1.2,
          ),
      ];
      controller.debugIngestSamples(fixes);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(container.read(sessionControllerProvider).sampleCount, 0);
      expect(await repo.getSamples(session.id), hasLength(4));

      controller.setAppForeground(true);
      final caughtUp = container.read(sessionControllerProvider);
      expect(caughtUp.sampleCount, 4);
      expect(caughtUp.liveDistanceM, greaterThan(0));
    },
  );

  test('permission denied does not start tracking', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.denied,
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
    final state = container.read(sessionControllerProvider);
    expect(state.isTracking, isFalse);
    expect(state.errorMessage, isNotNull);
  });

  test('unknown permission state does not create an active walk', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.unknown,
    );
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);

    await container.read(sessionControllerProvider.notifier).start();

    final state = container.read(sessionControllerProvider);
    expect(state.isTracking, isFalse);
    expect(state.isBusy, isFalse);
    expect(state.errorMessage, contains('확인할 수 없습니다'));
    expect(await repo.getActiveSession(), isNull);
  });

  test('permission channel failure releases the busy state', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(_ThrowingPermissionEngine()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(sessionControllerProvider.notifier).start();

    final state = container.read(sessionControllerProvider);
    expect(state.isTracking, isFalse);
    expect(state.isBusy, isFalse);
    expect(state.errorMessage, isNotNull);
    expect(await repo.getActiveSession(), isNull);
  });

  test(
    'first fix emitted during engine start is visible immediately',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final firstFix = LocationSample(
        timestamp: DateTime(2026, 7, 29, 9),
        latitude: 37.5665,
        longitude: 126.9780,
        accuracyM: 6,
        speedMps: 1.2,
      );
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(
            _ImmediateFixEngine(firstFix),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionControllerProvider.notifier).start();

      final state = container.read(sessionControllerProvider);
      expect(state.isTracking, isTrue);
      expect(state.sampleCount, 1);
      expect(state.validSampleCount, 1);
      expect(state.statusMessage, '기록 중');
    },
  );

  test('engine start failure keeps the new session recoverable', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(_ThrowingStartEngine()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(sessionControllerProvider.notifier).start();

    final state = container.read(sessionControllerProvider);
    final active = await repo.getActiveSession();
    expect(state.isTracking, isFalse);
    expect(state.isBusy, isFalse);
    expect(state.needsRecovery, isTrue);
    expect(state.session?.id, active?.id);
    expect(state.errorMessage, isNotNull);
  });

  test('recovery continues with checkpointed samples for distance', () async {
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
    final trace = buildWalkTrace(
      start: session.startedAt,
      duration: const Duration(minutes: 1),
      step: const Duration(seconds: 3),
    );
    controller.debugIngestSamples(trace);

    // Simulate process death: dispose controller state, keep DB samples via stop flush path.
    // Force flush by stopping engine mid-walk without completing — use discard? No.
    // Insert samples via stop's pending flush: call stop after "crash" recovery path.
    // Instead: write samples directly (what checkpoint would do), then restore.
    await repo.insertSamples(session.id, trace);

    // New controller instance simulating cold start.
    final container2 = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container2.dispose);
    final controller2 = container2.read(sessionControllerProvider.notifier);
    await controller2.restoreIfNeeded();
    final recovered = container2.read(sessionControllerProvider);
    expect(recovered.needsRecovery, isTrue);
    expect(recovered.sampleCount, greaterThan(0));
    expect(recovered.liveDistanceM, greaterThan(20));

    // Save and end without new samples — distance must remain non-zero.
    final ended = await controller2.stop();
    expect(ended, isNotNull);
    expect(ended!.totalDistanceM, greaterThan(20));
  });
}
