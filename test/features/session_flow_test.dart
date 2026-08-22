import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/data/app_database.dart';
import 'package:sanbo/domain/fixtures/synthetic_trace.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/models/walk_session.dart';
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
  Future<void> setAppForeground(bool foreground) async {}

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

class _ErroringLocationEngine implements LocationEngine {
  _ErroringLocationEngine();

  final _samples = StreamController<LocationSample>.broadcast();
  TrackingMode _mode = TrackingMode.balanced;
  bool running = false;
  bool endDuringStart = false;
  int stopCalls = 0;

  void emitError(Object error) {
    if (!_samples.isClosed) _samples.addError(error);
  }

  void emit(LocationSample sample) {
    if (running && !_samples.isClosed) _samples.add(sample);
  }

  Future<void> closeStream() => _samples.close();

  @override
  Stream<LocationSample> get samples => _samples.stream;

  @override
  TrackingMode get mode => _mode;

  @override
  Future<void> setMode(TrackingMode mode) async => _mode = mode;

  @override
  Future<void> setAppForeground(bool foreground) async {}

  @override
  Future<LocationPermissionState> checkPermission() async =>
      LocationPermissionState.granted;

  @override
  Future<LocationPermissionState> requestPermission() async =>
      LocationPermissionState.granted;

  @override
  Future<bool> openSystemSettings() async => true;

  @override
  Future<void> start() async {
    running = true;
    if (endDuringStart) await _samples.close();
  }

  @override
  Future<void> stop() async {
    running = false;
    stopCalls++;
  }

  @override
  Future<void> dispose() async => _samples.close();
}

class _DelayedInsertRepository extends WalkRepository {
  _DelayedInsertRepository(super.db);

  final insertStarted = Completer<void>();
  final releaseInsert = Completer<void>();
  var delayNextInsert = true;

  @override
  Future<void> insertSamples(
    String sessionId,
    List<LocationSample> samples,
  ) async {
    if (delayNextInsert) {
      delayNextInsert = false;
      insertStarted.complete();
      await releaseInsert.future;
    }
    return super.insertSamples(sessionId, samples);
  }
}

class _RetryableFailureRepository extends WalkRepository {
  _RetryableFailureRepository(super.db);

  var failWrites = true;

  @override
  Future<void> insertSamples(
    String sessionId,
    List<LocationSample> samples,
  ) async {
    if (failWrites) throw StateError('sample write failed');
    return super.insertSamples(sessionId, samples);
  }

  @override
  Future<WalkSession> finalizeSession({
    required WalkSession session,
    required List<LocationSample> samples,
    required List<MinuteWindow> windows,
    required DateTime endedAt,
    required double totalDistanceM,
    required int durationS,
    required int movingTimeS,
    required int stationaryTimeS,
    required double avgSpeedMps,
    required int validSampleCount,
    double? medianAccuracyM,
  }) {
    if (failWrites) throw StateError('finalize failed');
    return super.finalizeSession(
      session: session,
      samples: samples,
      windows: windows,
      endedAt: endedAt,
      totalDistanceM: totalDistanceM,
      durationS: durationS,
      movingTimeS: movingTimeS,
      stationaryTimeS: stationaryTimeS,
      avgSpeedMps: avgSpeedMps,
      validSampleCount: validSampleCount,
      medianAccuracyM: medianAccuracyM,
    );
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
      var now = DateTime.now();

      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
          sessionClockProvider.overrideWithValue(() => now),
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
      for (final sample in trace) {
        now = sample.timestamp;
        controller.debugIngestSamples([sample]);
      }

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

  test('location stream errors enter a stopped recovery state', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = _ErroringLocationEngine();
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(sessionControllerProvider.notifier);

    await controller.start();
    expect(controller.state.isTracking, isTrue);

    engine.emitError(StateError('location_stream_ended'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = controller.state;
    expect(state.isTracking, isFalse);
    expect(state.isBusy, isFalse);
    expect(state.needsRecovery, isTrue);
    expect(state.errorMessage, isNotNull);
    expect(state.statusMessage, '기록은 기기에 남아 있습니다.');
    expect(engine.stopCalls, 1);
  });

  test('location stream onDone enters the same recovery state', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = _ErroringLocationEngine();
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(sessionControllerProvider.notifier);

    await controller.start();
    await engine.closeStream();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.isTracking, isFalse);
    expect(controller.state.needsRecovery, isTrue);
    expect(engine.stopCalls, 1);
  });

  test('stream ending during engine startup stays recoverable', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = _ErroringLocationEngine()..endDuringStart = true;
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
    expect(state.needsRecovery, isTrue);
    expect(state.errorMessage, isNotNull);
    expect(engine.stopCalls, 1);
  });

  test(
    'terminal stream cleanup flushes pending samples before recovery',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final engine = _ErroringLocationEngine();
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionControllerProvider.notifier);
      await controller.start();
      final session = controller.state.session!;
      final sample = LocationSample(
        timestamp: session.startedAt,
        latitude: 37.5,
        longitude: 127,
        accuracyM: 5,
      );

      engine.emit(sample);
      await Future<void>.delayed(Duration.zero);
      engine.emitError(StateError('location_stream_ended'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(await repo.getSamples(session.id), hasLength(1));
    },
  );

  test('ordinary location stream errors remain non-terminal', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = _ErroringLocationEngine();
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(sessionControllerProvider.notifier);

    await controller.start();
    engine.emitError(StateError('temporary_location_error'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.isTracking, isTrue);
    expect(controller.state.needsRecovery, isFalse);
    expect(controller.state.errorMessage, isNotNull);
    expect(engine.stopCalls, 0);
  });

  test('stop clamps a far-future GPS fix to the receipt skew policy', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.granted,
    );
    var now = DateTime.utc(2026, 8, 21, 9);
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
        sessionClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(sessionControllerProvider.notifier);
    await controller.start();
    final session = controller.state.session!;
    final trace = buildWalkTrace(
      start: session.startedAt,
      duration: const Duration(minutes: 1),
      step: const Duration(seconds: 4),
    );
    controller.debugIngestSamples(trace);
    controller.debugIngestSamples([
      LocationSample(
        timestamp: session.startedAt.add(const Duration(hours: 1)),
        latitude: 37.6,
        longitude: 127.1,
        accuracyM: 5,
      ),
    ]);
    now = session.startedAt.add(const Duration(minutes: 1));

    final ended = await controller.stop();

    expect(ended, isNotNull);
    expect(ended!.durationS, lessThan(120));
    expect(ended.durationS, greaterThanOrEqualTo(60));
    expect(ended.endedAt!.difference(now).inSeconds, lessThanOrEqualTo(5));
    final stored = await repo.getSamples(ended.id);
    expect(
      stored
          .singleWhere((sample) => sample.timestamp.isAfter(now))
          .isFilteredOut,
      isTrue,
    );
  });

  test(
    'live ingest does not anchor on cached pre-session or far-future fixes',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final engine = SyntheticLocationEngine(
        permission: LocationPermissionState.granted,
      );
      var now = DateTime.utc(2026, 8, 21, 9);
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
          sessionClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionControllerProvider.notifier);
      await controller.start();
      final session = controller.state.session!;

      LocationSample fix(int second, double longitude) => LocationSample(
        timestamp: session.startedAt.add(Duration(seconds: second)),
        latitude: 37.5,
        longitude: longitude,
        accuracyM: 5,
      );

      controller.debugIngestSamples([fix(-10, 126.9), fix(0, 127.0)]);
      now = session.startedAt;
      controller.debugIngestSamples([fix(3600, 127.2)]);
      for (var second = 8; second <= 48; second += 8) {
        now = session.startedAt.add(Duration(seconds: second));
        controller.debugIngestSamples([fix(second, 127.0 + second * 0.0001)]);
      }

      final live = controller.state;
      expect(live.validSampleCount, 7);
      expect(live.liveDistanceM, greaterThan(300));
      expect(live.liveDistanceM, lessThan(500));

      now = session.startedAt.add(const Duration(seconds: 48));
      final ended = await controller.stop();
      expect(ended, isNotNull);
      final stored = await repo.getSamples(session.id);
      expect(
        stored
            .singleWhere(
              (sample) =>
                  sample.timestamp ==
                  session.startedAt.subtract(const Duration(seconds: 10)),
            )
            .isFilteredOut,
        isTrue,
      );
      expect(
        stored
            .singleWhere(
              (sample) =>
                  sample.timestamp ==
                  session.startedAt.add(const Duration(hours: 1)),
            )
            .isFilteredOut,
        isTrue,
      );
    },
  );

  test(
    'live ingest does not accept a stale cached fix as the first anchor',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final engine = SyntheticLocationEngine(
        permission: LocationPermissionState.granted,
      );
      var now = DateTime.utc(2026, 8, 21, 9);
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
          sessionClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionControllerProvider.notifier);
      await controller.start();
      final session = controller.state.session!;

      now = session.startedAt.add(const Duration(minutes: 1));
      controller.debugIngestSamples([
        LocationSample(
          timestamp: session.startedAt.add(const Duration(seconds: 20)),
          latitude: 37.5,
          longitude: 127,
          accuracyM: 5,
        ),
      ]);

      expect(controller.state.sampleCount, 1);
      expect(controller.state.validSampleCount, 0);
      expect(controller.state.liveDistanceM, 0);
    },
  );

  test(
    'recovery also marks a far-future fix outside the persisted route',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final start = DateTime.utc(2026, 8, 21, 9);
      final now = start.add(const Duration(minutes: 2));
      final session = await repo.startSession(startedAt: start);
      final trace = buildWalkTrace(
        start: start,
        duration: const Duration(minutes: 2),
        speedMps: 1.3,
        step: const Duration(seconds: 4),
      );
      final future = LocationSample(
        timestamp: start.add(const Duration(hours: 1)),
        latitude: 37.6,
        longitude: 127.1,
        accuracyM: 5,
      );
      await repo.insertSamples(session.id, [...trace, future]);
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(
            SyntheticLocationEngine(
              permission: LocationPermissionState.granted,
            ),
          ),
          sessionClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionControllerProvider.notifier);
      await controller.restoreIfNeeded();

      final ended = await controller.stop();

      expect(ended, isNotNull);
      expect(ended!.durationS, lessThan(180));
      final stored = await repo.getSamples(ended.id);
      expect(
        stored
            .singleWhere((sample) => sample.timestamp == future.timestamp)
            .isFilteredOut,
        isTrue,
      );
    },
  );

  test('recovery clamps cached samples before session start', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final start = DateTime.utc(2026, 8, 21, 9);
    final session = await repo.startSession(startedAt: start);
    final cached = LocationSample(
      timestamp: start.subtract(const Duration(seconds: 10)),
      latitude: 37.5,
      longitude: 127,
      accuracyM: 5,
    );
    final current = LocationSample(
      timestamp: start.add(const Duration(seconds: 30)),
      latitude: 37.501,
      longitude: 127,
      accuracyM: 5,
    );
    await repo.insertSamples(session.id, [cached, current]);
    final now = start.add(const Duration(minutes: 1));
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(
          SyntheticLocationEngine(permission: LocationPermissionState.granted),
        ),
        sessionClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(sessionControllerProvider.notifier);
    await controller.restoreIfNeeded();
    expect(controller.state.liveDistanceM, 0);

    final ended = await controller.stop();

    expect(ended, isNotNull);
    expect(!ended!.endedAt!.toUtc().isBefore(start), isTrue);
    final stored = await repo.getSamples(session.id);
    expect(
      stored.singleWhere((s) => s.timestamp == cached.timestamp).isFilteredOut,
      isTrue,
    );
  });

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
    'non-finite GPS metadata cannot corrupt persistence or backup',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final engine = SyntheticLocationEngine(
        permission: LocationPermissionState.granted,
      );
      var now = DateTime.now();
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
          sessionClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.start();
      final session = container.read(sessionControllerProvider).session!;
      controller.debugIngestSamples([
        for (var index = 0; index < 10; index++)
          LocationSample(
            timestamp: session.startedAt.add(Duration(seconds: index * 4)),
            latitude: 37.5665 + index * 0.00005,
            longitude: 126.978,
            accuracyM: 6,
            speedMps: index == 2 ? double.infinity : 1.2,
            altitudeM: index == 3 ? double.negativeInfinity : 25,
          ),
      ]);
      now = session.startedAt.add(const Duration(seconds: 36));

      final ended = await controller.stop();
      expect(ended, isNotNull);
      final stored = await repo.getSamples(ended!.id);
      expect(stored[2].speedMps, isNull);
      expect(stored[3].altitudeM, isNull);
      expect(
        jsonDecode(await repo.createBackupJson()),
        isA<Map<String, dynamic>>(),
      );
    },
  );

  test(
    'live speed falls back to GPS displacement when provider speed is zero',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final engine = SyntheticLocationEngine(
        permission: LocationPermissionState.granted,
      );
      var now = DateTime.now();
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
          sessionClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.start();
      final session = container.read(sessionControllerProvider).session!;
      now = session.startedAt.add(const Duration(seconds: 8));
      controller.debugIngestSamples([
        LocationSample(
          timestamp: session.startedAt,
          latitude: 37.5,
          longitude: 127,
          accuracyM: 5,
          speedMps: 0,
        ),
        LocationSample(
          timestamp: session.startedAt.add(const Duration(seconds: 8)),
          latitude: 37.500108,
          longitude: 127,
          accuracyM: 5,
          speedMps: 0,
        ),
      ]);

      final live = container.read(sessionControllerProvider);
      expect(live.liveDistanceM, greaterThan(8));
      expect(live.liveSpeedMps, closeTo(1.5, 0.3));
    },
  );

  test('filtered GPS fixes cannot overwrite live speed', () async {
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
    controller.debugIngestSamples([
      LocationSample(
        timestamp: session.startedAt,
        latitude: 37.5,
        longitude: 127,
        accuracyM: 5,
        speedMps: 0,
      ),
      LocationSample(
        timestamp: session.startedAt.add(const Duration(seconds: 8)),
        latitude: 37.500108,
        longitude: 127,
        accuracyM: 5,
        speedMps: 0,
      ),
      LocationSample(
        timestamp: session.startedAt.add(const Duration(seconds: 9)),
        latitude: 37.5,
        longitude: 128,
        accuracyM: 5,
        speedMps: 100,
      ),
    ]);

    final live = container.read(sessionControllerProvider);
    expect(live.liveSpeedMps, lessThan(10));
    expect(live.liveDistanceM, lessThan(100));
  });

  test(
    'live route keeps micro-jitter samples without adding distance',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      var now = DateTime.now();
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(
            SyntheticLocationEngine(
              permission: LocationPermissionState.granted,
            ),
          ),
          sessionClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionControllerProvider.notifier);
      await controller.start();
      final start = controller.state.session!.startedAt;
      now = start.add(const Duration(seconds: 10));
      controller.debugIngestSamples([
        LocationSample(
          timestamp: start,
          latitude: 37.5,
          longitude: 127,
          accuracyM: 5,
        ),
        LocationSample(
          timestamp: start.add(const Duration(seconds: 10)),
          latitude: 37.5,
          longitude: 127.00001,
          accuracyM: 5,
        ),
      ]);

      expect(controller.state.validSampleCount, 2);
      expect(controller.state.liveDistanceM, 0);
    },
  );

  test('live distance does not bridge a long GPS gap', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.granted,
    );
    var now = DateTime.now();
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
        sessionClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await controller.start();
    final session = container.read(sessionControllerProvider).session!;
    now = session.startedAt.add(const Duration(minutes: 10, seconds: 8));
    controller.debugIngestSamples([
      LocationSample(
        timestamp: session.startedAt,
        latitude: 37.5,
        longitude: 127,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: session.startedAt.add(const Duration(seconds: 8)),
        latitude: 37.5009,
        longitude: 127,
        accuracyM: 5,
      ),
      // A ten-minute gap must not be interpreted as a continuous 1000 m path.
      LocationSample(
        timestamp: session.startedAt.add(const Duration(minutes: 10)),
        latitude: 37.51,
        longitude: 127,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: session.startedAt.add(
          const Duration(minutes: 10, seconds: 8),
        ),
        latitude: 37.5109,
        longitude: 127,
        accuracyM: 5,
      ),
    ]);

    final live = container.read(sessionControllerProvider);
    expect(live.liveDistanceM, greaterThan(100));
    expect(live.liveDistanceM, lessThan(300));
  });

  test('out-of-order fixes stay filtered after a recovery restart', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    var now = DateTime(2026, 8, 22, 9);
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(
          SyntheticLocationEngine(permission: LocationPermissionState.granted),
        ),
        sessionClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await controller.start();
    final session = controller.state.session!;
    LocationSample fix(int second, double longitude) => LocationSample(
      timestamp: session.startedAt.add(Duration(seconds: second)),
      latitude: 37.5,
      longitude: longitude,
      accuracyM: 5,
    );
    final received = [
      (sample: fix(0, 127.0000), receivedAt: 0),
      (sample: fix(60, 127.0050), receivedAt: 60),
      (sample: fix(120, 127.0100), receivedAt: 120),
      // The provider delivers this older fix after the 120-second fix.
      (sample: fix(90, 127.0075), receivedAt: 120),
      (sample: fix(180, 127.0150), receivedAt: 180),
      (sample: fix(240, 127.0200), receivedAt: 240),
    ];
    for (final item in received) {
      now = session.startedAt.add(Duration(seconds: item.receivedAt));
      controller.debugIngestSamples([item.sample]);
    }
    expect(controller.state.sampleCount, 6);
    expect(controller.state.validSampleCount, greaterThanOrEqualTo(5));
    expect(controller.state.liveDistanceM, greaterThan(100));

    now = session.startedAt.add(const Duration(minutes: 5));
    final completed = await controller.stop();
    expect(completed, isNotNull);
    final stored = await repo.getSamples(session.id);
    expect(
      stored
          .singleWhere(
            (sample) =>
                sample.timestamp.difference(session.startedAt) ==
                const Duration(seconds: 90),
          )
          .isFilteredOut,
      isTrue,
    );
  });

  test('recovered live distance does not bridge a long GPS gap', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final start = DateTime(2026, 8, 16, 9);
    final session = await repo.startSession(startedAt: start);
    await repo.insertSamples(session.id, [
      LocationSample(
        timestamp: start,
        latitude: 37.5,
        longitude: 127,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: start.add(const Duration(seconds: 8)),
        latitude: 37.5009,
        longitude: 127,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: start.add(const Duration(minutes: 10)),
        latitude: 37.51,
        longitude: 127,
        accuracyM: 5,
      ),
    ]);
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
    await controller.restoreIfNeeded();

    final live = container.read(sessionControllerProvider);
    expect(live.needsRecovery, isTrue);
    expect(live.liveDistanceM, greaterThan(100));
    expect(live.liveDistanceM, lessThan(300));
  });

  test(
    'recovery ending on a minute boundary keeps the endpoint sample',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final minute = DateTime.utc(2026, 8, 21);
      final start = minute.add(const Duration(seconds: 50));
      final end = minute.add(const Duration(minutes: 1));
      final session = await repo.startSession(startedAt: start);
      await repo.insertSamples(session.id, [
        LocationSample(
          timestamp: start,
          latitude: 37.5,
          longitude: 127,
          accuracyM: 5,
        ),
        LocationSample(
          timestamp: end,
          latitude: 37.5002,
          longitude: 127,
          accuracyM: 5,
        ),
      ]);
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(
            SyntheticLocationEngine(
              permission: LocationPermissionState.granted,
            ),
          ),
          sessionClockProvider.overrideWithValue(() => end),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionControllerProvider.notifier);
      await controller.restoreIfNeeded();

      final completed = await controller.stop();

      expect(completed, isNotNull);
      expect(completed!.validSampleCount, 2);
      expect((await repo.getWindows(session.id)).single.sampleCount, 2);
    },
  );

  test(
    'background fixes are checkpointed without rebuilding live UI state',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final engine = SyntheticLocationEngine(
        permission: LocationPermissionState.granted,
      );
      var now = DateTime.now();
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
          sessionClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.start(mode: TrackingMode.balanced);
      final session = container.read(sessionControllerProvider).session!;
      controller.setAppInactive();
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
      now = session.startedAt.add(const Duration(seconds: 24));
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

  test(
    'stop waits for an in-flight checkpoint before finalizing samples',
    () async {
      ensureSqfliteFfi();
      final path =
          '${Directory.systemTemp.path}/sanbo_delayed_${DateTime.now().microsecondsSinceEpoch}.db';
      final db = await openAppDatabase(path: path);
      final repo = _DelayedInsertRepository(db);
      addTearDown(repo.close);
      final engine = SyntheticLocationEngine(
        permission: LocationPermissionState.granted,
      );
      var now = DateTime.now();
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
          sessionClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.start(mode: TrackingMode.balanced);
      final session = container.read(sessionControllerProvider).session!;
      controller.setAppForeground(false);
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
      now = session.startedAt.add(const Duration(seconds: 24));
      await repo.insertStarted.future;

      final stopFuture = controller.stop();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(sessionControllerProvider).isBusy, isTrue);

      repo.releaseInsert.complete();
      final ended = await stopFuture;
      expect(ended, isNotNull);
      final stored = await repo.getSamples(ended!.id);
      final logicalKeys = stored
          .map(
            (sample) =>
                '${sample.timestamp.toUtc().microsecondsSinceEpoch}|'
                '${sample.latitude.toStringAsFixed(6)}|'
                '${sample.longitude.toStringAsFixed(6)}',
          )
          .toSet();
      expect(logicalKeys.length, stored.length);
      expect(stored, hasLength(fixes.length));
    },
  );

  test(
    'discard closes the session before removing its checkpoint data',
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
      await controller.start();
      final session = container.read(sessionControllerProvider).session!;
      controller.debugIngestSamples([
        LocationSample(
          timestamp: session.startedAt,
          latitude: 37.5665,
          longitude: 126.978,
          accuracyM: 6,
          speedMps: 1.2,
        ),
      ]);

      await controller.discardActive();
      expect(await repo.getActiveSession(), isNull);
      expect(await repo.getSamples(session.id), isEmpty);
      expect(container.read(sessionControllerProvider).session, isNull);
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

  test('foreground-only location permission still starts with settings guidance',
      () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.grantedForegroundOnly,
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
    var state = container.read(sessionControllerProvider);
    expect(state.isTracking, isTrue);
    expect(
      state.permissionState,
      LocationPermissionState.grantedForegroundOnly,
    );
    expect(state.errorMessage, contains('항상 허용'));

    controller.debugIngestSamples([
      LocationSample(
        timestamp: state.session!.startedAt,
        latitude: 37.5665,
        longitude: 126.978,
        accuracyM: 6,
      ),
    ]);
    state = container.read(sessionControllerProvider);
    expect(state.errorMessage, contains('항상 허용'));
    controller.clearError();
    expect(
      container.read(sessionControllerProvider).errorMessage,
      contains('항상 허용'),
    );
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
          sessionClockProvider.overrideWithValue(
            () => DateTime(2026, 7, 29, 9),
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

  test(
    'synchronous cached first fix before session start is filtered',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final start = DateTime(2026, 7, 29, 9);
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(
            _ImmediateFixEngine(
              LocationSample(
                timestamp: start.subtract(const Duration(seconds: 10)),
                latitude: 37.5665,
                longitude: 126.978,
                accuracyM: 6,
              ),
            ),
          ),
          sessionClockProvider.overrideWithValue(() => start),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionControllerProvider.notifier).start();

      final state = container.read(sessionControllerProvider);
      expect(state.isTracking, isTrue);
      expect(state.sampleCount, 1);
      expect(state.validSampleCount, 0);
      expect(state.liveDistanceM, 0);
    },
  );

  test('filtered first fix still triggers the GPS watchdog guidance', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final start = DateTime(2026, 7, 29, 9);
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(
          _ImmediateFixEngine(
            LocationSample(
              timestamp: start.subtract(const Duration(seconds: 10)),
              latitude: 37.5665,
              longitude: 126.978,
              accuracyM: 6,
            ),
          ),
        ),
        sessionClockProvider.overrideWithValue(() => start),
        firstFixWatchdogDurationProvider.overrideWithValue(
          const Duration(milliseconds: 1),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final state = controller.state;
    expect(state.sampleCount, 1);
    expect(state.validSampleCount, 0);
    expect(state.errorMessage, contains('위치를 아직 받지 못했어요'));
    expect(state.statusMessage, 'GPS 대기 중');
  });

  test('long session with only filtered fixes is discarded', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final start = DateTime(2026, 7, 29, 9);
    var now = start;
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(
          _ImmediateFixEngine(
            LocationSample(
              timestamp: start.subtract(const Duration(seconds: 10)),
              latitude: 37.5665,
              longitude: 126.978,
              accuracyM: 6,
            ),
          ),
        ),
        sessionClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await controller.start();
    final session = container.read(sessionControllerProvider).session!;
    now = start.add(const Duration(minutes: 2));

    final ended = await controller.stop();

    expect(ended, isNull);
    expect(await repo.listCompleted(), isEmpty);
    expect(await repo.getActiveSession(), isNull);
    expect(
      (await repo.getSession(session.id))?.status,
      SessionStatus.discarded,
    );
    final samples = await repo.getSamples(session.id);
    expect(samples, hasLength(1));
    expect(samples.single.isFilteredOut, isTrue);
    expect(container.read(sessionControllerProvider).notice, contains('저장하지'));
  });

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
    var now = DateTime.now();
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
        sessionClockProvider.overrideWithValue(() => now),
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
    now = session.startedAt.add(const Duration(minutes: 1));

    // New controller instance simulating cold start.
    final container2 = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
        sessionClockProvider.overrideWithValue(() => now),
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

  test(
    'resume re-checkpoints memory-only samples after a failed finalization',
    () async {
      ensureSqfliteFfi();
      final path =
          '${Directory.systemTemp.path}/sanbo_retry_${DateTime.now().microsecondsSinceEpoch}.db';
      final db = await openAppDatabase(path: path);
      final repo = _RetryableFailureRepository(db);
      addTearDown(repo.close);
      final engine = SyntheticLocationEngine(
        permission: LocationPermissionState.granted,
      );
      var now = DateTime.now();
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
          sessionClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.start();
      final session = container.read(sessionControllerProvider).session!;
      final trace = buildWalkTrace(
        start: session.startedAt,
        duration: const Duration(minutes: 1),
        step: const Duration(seconds: 4),
      );
      controller.debugIngestSamples(trace);
      now = session.startedAt.add(const Duration(minutes: 1));

      expect(await controller.stop(), isNull);
      expect(await repo.getSamples(session.id), isEmpty);

      repo.failWrites = false;
      await controller.start();
      controller.setAppForeground(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await repo.getSamples(session.id), hasLength(trace.length));
    },
  );
}
