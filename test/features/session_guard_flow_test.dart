import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/fixtures/synthetic_trace.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';
import 'package:sanbo/features/history/history_providers.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';
import 'package:sanbo/platform/notifications/session_notification_service.dart';

import '../helpers/test_db.dart';

class _FakeSessionNotifications implements SessionNotificationService {
  final warnings = <String>[];
  final completions = <String>[];
  int cancelCalls = 0;

  @override
  Future<void> cancelWarning() async {
    cancelCalls++;
  }

  @override
  Future<void> showCompletion({
    required String title,
    required String body,
  }) async {
    completions.add('$title|$body');
  }

  @override
  Future<void> showWarning({
    required String title,
    required String body,
  }) async {
    warnings.add('$title|$body');
  }
}

class _ThrowingSessionPipeline extends SessionPipeline {
  @override
  SessionProcessResult process({
    required WalkSession session,
    required List<LocationSample> rawSamples,
    required DateTime endedAt,
  }) {
    throw StateError('synthetic finalize failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'long stay warns, can continue, then auto-saves at the next limit',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final engine = SyntheticLocationEngine(
        permission: LocationPermissionState.granted,
      );
      final notifications = _FakeSessionNotifications();
      var now = DateTime(2026, 7, 29, 9);
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
          sessionNotificationServiceProvider.overrideWithValue(notifications),
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
        step: const Duration(seconds: 8),
      );
      controller.debugIngestSamples(trace);

      now = session.startedAt.add(const Duration(minutes: 21));
      await controller.debugEvaluateSessionGuard();
      var live = container.read(sessionControllerProvider);
      expect(live.autoStopWarning, contains('20분'));
      expect(live.canContinueAfterWarning, isTrue);
      expect(notifications.warnings, hasLength(1));

      controller.continueTrackingAfterStay();
      live = container.read(sessionControllerProvider);
      expect(live.autoStopWarning, isNull);
      expect(live.isTracking, isTrue);

      now = now.add(const Duration(minutes: 20));
      await controller.debugEvaluateSessionGuard();
      expect(
        container.read(sessionControllerProvider).autoStopWarning,
        contains('20분'),
      );
      expect(notifications.warnings, hasLength(2));

      now = now.add(const Duration(minutes: 10));
      await controller.debugEvaluateSessionGuard();

      live = container.read(sessionControllerProvider);
      expect(live.isTracking, isFalse);
      expect(live.notice, contains('자동으로 저장하고 종료'));
      expect(notifications.completions, hasLength(1));
      expect(container.read(historyTickProvider), 1);
      expect(await repo.getActiveSession(), isNull);
      expect(await repo.listCompleted(), hasLength(1));
    },
  );

  test('five-hour limit warns at 4h45 and auto-saves at 5h', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.granted,
    );
    final notifications = _FakeSessionNotifications();
    var now = DateTime(2026, 7, 29, 9);
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
        sessionNotificationServiceProvider.overrideWithValue(notifications),
        sessionClockProvider.overrideWithValue(() => now),
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
        longitude: 126.9780,
        accuracyM: 6,
        speedMps: 1.2,
      ),
    ]);
    now = session.startedAt.add(const Duration(hours: 2, minutes: 44));
    controller.debugIngestSamples([
      LocationSample(
        timestamp: now,
        latitude: 37.5675,
        longitude: 126.9780,
        accuracyM: 6,
        speedMps: 1.2,
      ),
    ]);

    // Keep the stationary guard from ending this synthetic trace before the
    // duration boundary under test.
    now = session.startedAt.add(const Duration(hours: 4, minutes: 44));
    controller.debugIngestSamples([
      LocationSample(
        timestamp: now,
        latitude: 37.5685,
        longitude: 126.9780,
        accuracyM: 6,
        speedMps: 1.2,
      ),
    ]);

    now = session.startedAt.add(const Duration(hours: 4, minutes: 45));
    await controller.debugEvaluateSessionGuard();
    var live = container.read(sessionControllerProvider);
    expect(live.isTracking, isTrue);
    expect(live.autoStopWarning, contains('4시간 45분'));
    expect(live.canContinueAfterWarning, isFalse);
    expect(notifications.warnings.single, contains('곧 종료'));

    now = session.startedAt.add(const Duration(hours: 5));
    await controller.debugEvaluateSessionGuard();
    live = container.read(sessionControllerProvider);
    expect(live.isTracking, isFalse);
    expect(live.notice, contains('5시간'));
    expect(notifications.completions.single, contains('5시간'));
    expect(container.read(historyTickProvider), 1);
    expect(await repo.getActiveSession(), isNull);
    expect(await repo.listCompleted(), hasLength(1));
  });

  test(
    'auto-save failure stays recoverable and never claims completion',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final engine = SyntheticLocationEngine(
        permission: LocationPermissionState.granted,
      );
      final notifications = _FakeSessionNotifications();
      var now = DateTime(2026, 7, 29, 9);
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
          sessionPipelineProvider.overrideWithValue(_ThrowingSessionPipeline()),
          sessionNotificationServiceProvider.overrideWithValue(notifications),
          sessionClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.start();
      final session = container.read(sessionControllerProvider).session!;
      controller.debugIngestSamples(
        buildWalkTrace(
          start: session.startedAt,
          duration: const Duration(minutes: 1),
          step: const Duration(seconds: 8),
        ),
      );

      now = session.startedAt.add(const Duration(hours: 3));
      await controller.debugEvaluateSessionGuard();

      final live = container.read(sessionControllerProvider);
      expect(live.isTracking, isFalse);
      expect(live.needsRecovery, isTrue);
      expect(live.session?.id, session.id);
      expect(live.errorMessage, contains('저장에 실패'));
      expect(live.autoStopWarning, isNull);
      expect(notifications.completions, isEmpty);
      expect(notifications.warnings.last, contains('저장을 마치지 못했어요'));
      expect(container.read(historyTickProvider), 0);
      expect((await repo.getActiveSession())?.id, session.id);
      expect(await repo.listCompleted(), isEmpty);
    },
  );
}
