import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/data/app_database.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/session_warning.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';

import '../helpers/test_db.dart';

class _DelayedRestoreRepository extends WalkRepository {
  _DelayedRestoreRepository(super.db);

  final restoreStarted = Completer<void>();
  final releaseRestore = Completer<void>();
  var delayNextRestore = true;

  @override
  Future<List<LocationSample>> getSamples(String sessionId) async {
    if (delayNextRestore) {
      delayNextRestore = false;
      restoreStarted.complete();
      await releaseRestore.future;
    }
    return super.getSamples(sessionId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restoreIfNeeded sets needsRecovery without tracking', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    await repo.startSession(mode: TrackingMode.balanced);

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

    final c = container.read(sessionControllerProvider.notifier);
    await c.restoreIfNeeded();
    final live = container.read(sessionControllerProvider);
    expect(live.needsRecovery, isTrue);
    expect(live.isTracking, isFalse);
    expect(live.session, isNotNull);
    expect(live.statusMessage, isNotNull);
  });

  test(
    'start waits for an in-flight recovery before resuming the session',
    () async {
      ensureSqfliteFfi();
      final db = await openAppDatabase(
        path:
            '${Directory.systemTemp.path}/sanbo_restore_start_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      final repo = _DelayedRestoreRepository(db);
      addTearDown(repo.close);
      await repo.startSession(mode: TrackingMode.balanced);

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
      final restore = controller.restoreIfNeeded();
      await repo.restoreStarted.future;
      final start = controller.start();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(sessionControllerProvider).isTracking, isFalse);
      expect(container.read(sessionControllerProvider).isBusy, isFalse);

      repo.releaseRestore.complete();
      await restore;
      await start;

      expect(container.read(sessionControllerProvider).isTracking, isTrue);
    },
  );

  test('restoreIfNeeded surfaces a recoverable storage error', () async {
    final repo = await openTestRepository();
    await repo.close();
    addTearDown(() async {
      try {
        await repo.close();
      } catch (_) {}
    });

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

    await container.read(sessionControllerProvider.notifier).restoreIfNeeded();
    final live = container.read(sessionControllerProvider);
    expect(live.needsRecovery, isFalse);
    expect(live.canRetryRecovery, isTrue);
    expect(live.errorMessage, contains('기록을 확인하지 못했어요'));
    expect(live.errorMessage, isNot(contains('DatabaseException')));

    final retry = container
        .read(sessionControllerProvider.notifier)
        .retryRecovery();
    expect(container.read(sessionControllerProvider).isBusy, isTrue);
    await retry;
    expect(container.read(sessionControllerProvider).isBusy, isFalse);
    expect(container.read(sessionControllerProvider).canRetryRecovery, isTrue);
  });

  test(
    'recovery stop caps duration at last sample, not wall-clock now',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);

      // Session started 3h ago, app killed; the real walk lasted ~10 min. All
      // samples are in the past relative to `now` (unlike a live stop).
      final start = DateTime.now().subtract(const Duration(hours: 3));
      final session = await repo.startSession(
        mode: TrackingMode.balanced,
        startedAt: start,
      );
      const degPerMeter = 1 / 111320.0;
      final samples = <LocationSample>[
        for (var i = 0; i < 60; i++)
          LocationSample(
            timestamp: start.add(
              Duration(seconds: i * 10),
            ), // 0..590s, all past
            latitude: 37.5 + i * 10 * 1.2 * degPerMeter,
            longitude: 127.0,
            accuracyM: 8,
            speedMps: 1.2,
          ),
      ];
      await repo.insertSamples(session.id, samples);

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

      final c = container.read(sessionControllerProvider.notifier);
      await c.restoreIfNeeded();
      expect(container.read(sessionControllerProvider).needsRecovery, isTrue);

      final ended = await c.stop();
      expect(ended, isNotNull);
      // Duration reflects the real ~590s walk, NOT the 3h app-dead gap.
      expect(ended!.durationS, greaterThan(400));
      expect(ended.durationS, lessThan(1200));
      // The dead gap must not be counted as moving time.
      expect(ended.movingTimeS!, lessThanOrEqualTo(ended.durationS!));
    },
  );

  test('discardActive clears incomplete session', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    await repo.startSession(mode: TrackingMode.balanced);
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

    final c = container.read(sessionControllerProvider.notifier);
    await c.restoreIfNeeded();
    await c.discardActive();
    final live = container.read(sessionControllerProvider);
    expect(live.session, isNull);
    expect(live.needsRecovery, isFalse);
    expect(await repo.getActiveSession(), isNull);
  });

  test(
    'recovery rebuilds only recent high-speed state before resuming',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final now = DateTime(2026, 8, 21, 9);
      final recent = await repo.startSession(
        mode: TrackingMode.balanced,
        startedAt: now.subtract(const Duration(seconds: 60)),
      );
      await repo.insertSamples(recent.id, _highSpeedSamples(recent.startedAt));

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
      expect(container.read(sessionControllerProvider).activeWarning, isNull);
      await controller.start();
      expect(
        container.read(sessionControllerProvider).activeWarning?.kind,
        SessionWarningKind.highSpeed,
      );
    },
  );

  test('recovery card resume dismisses a rebuilt high-speed warning', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final now = DateTime(2026, 8, 21, 9);
    final session = await repo.startSession(
      mode: TrackingMode.balanced,
      startedAt: now.subtract(const Duration(seconds: 60)),
    );
    await repo.insertSamples(session.id, _highSpeedSamples(session.startedAt));

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
    await controller.resumeRecoveredSession();

    expect(container.read(sessionControllerProvider).isTracking, isTrue);
    expect(container.read(sessionControllerProvider).activeWarning, isNull);
  });

  test('recovery ignores stale high-speed samples', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final now = DateTime(2026, 8, 21, 9);
    final staleStart = now.subtract(const Duration(minutes: 10));
    final session = await repo.startSession(
      mode: TrackingMode.balanced,
      startedAt: staleStart,
    );
    await repo.insertSamples(session.id, _highSpeedSamples(staleStart));

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
    await controller.start();
    expect(container.read(sessionControllerProvider).activeWarning, isNull);
  });

  test(
    'pending notification tap hook is a no-op before native wiring',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(
            SyntheticLocationEngine(
              permission: LocationPermissionState.granted,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.restorePendingNotificationTap();
      expect(
        container.read(sessionControllerProvider),
        isA<LiveSessionState>(),
      );
    },
  );

  test(
    'recovery invokes the pending notification tap hook after state restore',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      await repo.startSession(mode: TrackingMode.balanced);
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(
            SyntheticLocationEngine(
              permission: LocationPermissionState.granted,
            ),
          ),
          sessionControllerProvider.overrideWith(_HookSessionController.new),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(sessionControllerProvider.notifier)
              as _HookSessionController;
      await controller.restoreIfNeeded();
      expect(controller.restoreCalls, 1);
      expect(controller.wasRecoveryStateVisible, isTrue);
    },
  );

  test(
    'HomeScreen + discard_confirm ship recovery confirm and busy hierarchy',
    () {
      final home = File(
        'lib/features/home/home_screen.dart',
      ).readAsStringSync();
      final confirm = File(
        'lib/features/home/discard_confirm.dart',
      ).readAsStringSync();
      expect(home, contains('이어서 기록'));
      expect(home, contains('저장하고 종료'));
      expect(home, contains('confirmDiscardIncompleteWalk'));
      expect(home, contains('isBusy'));
      expect(home, contains('needsRecovery'));
      expect(home, contains('다시 시도'));
      expect(home, contains('설정 열기'));
      expect(home, contains('openSystemSettings'));
      expect(home, contains('계속 기록'));
      expect(home, contains('activeWarning'));
      expect(home, contains('_SessionWarningBanner'));
      expect(home, contains('canRetryRecovery'));
      expect(home, contains('retryRecovery'));
      expect(home, contains('else if (!recovery)'));
      expect(home, isNot(contains("'LIVE'")));
      expect(confirm, contains('기록 지우기'));
    },
  );
}

class _HookSessionController extends SessionController {
  int restoreCalls = 0;
  bool wasRecoveryStateVisible = false;

  @override
  Future<void> restorePendingNotificationTap() async {
    restoreCalls++;
    wasRecoveryStateVisible = state.needsRecovery;
  }
}

List<LocationSample> _highSpeedSamples(DateTime start) {
  const degreesPerMeter = 1 / 111320.0;
  return [
    for (var second = 0; second <= 60; second += 10)
      LocationSample(
        timestamp: start.add(Duration(seconds: second)),
        latitude: 37.5665 + (second * 10 * degreesPerMeter),
        longitude: 126.9780,
        accuracyM: 6,
      ),
  ];
}
