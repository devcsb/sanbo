import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sanbo/app.dart';
import 'package:sanbo/app/router.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/fixtures/synthetic_trace.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/session_warning.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';
import 'package:sanbo/features/history/history_providers.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/features/home/home_screen.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';
import 'package:sanbo/platform/notifications/session_notification_service.dart';

import '../helpers/test_db.dart';

class _FakeSessionNotifications implements SessionNotificationService {
  final warnings = <String>[];
  final completions = <String>[];
  int cancelCalls = 0;
  int tapDeliveries = 0;
  SessionNotificationTap? _pendingColdTap;
  late final _tapController =
      StreamController<SessionNotificationTap>.broadcast(
        onListen: _flushPendingColdTap,
      );

  @override
  Future<void> cancel({required SessionWarningKind kind}) async {
    cancelCalls++;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationPermissionResult> requestPermission() async {
    return NotificationPermissionResult.granted;
  }

  @override
  Future<void> showCompletion({
    required String title,
    required String body,
  }) async {
    completions.add('$title|$body');
  }

  @override
  Future<void> showWarning(SessionWarning warning) async {
    warnings.add('${warning.title}|${warning.message}');
  }

  @override
  Stream<SessionNotificationTap> get taps => _tapController.stream.map((tap) {
    tapDeliveries++;
    return tap;
  });

  void emitTap(SessionWarningKind kind) {
    _tapController.add(SessionNotificationTap(kind));
  }

  void emitColdTap(SessionWarningKind kind) {
    _pendingColdTap = SessionNotificationTap(kind);
  }

  void _flushPendingColdTap() {
    final tap = _pendingColdTap;
    _pendingColdTap = null;
    if (tap != null) _tapController.add(tap);
  }

  void dispose() {
    unawaited(_tapController.close());
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
      expect(live.activeWarning?.kind, SessionWarningKind.stationary);
      expect(live.activeWarning?.message, contains('20분'));
      expect(live.activeWarning?.actions, {
        SessionWarningAction.continueRecording,
      });
      expect(notifications.warnings, hasLength(1));

      controller.continueAfterWarning();
      live = container.read(sessionControllerProvider);
      expect(live.activeWarning, isNull);
      expect(live.isTracking, isTrue);

      now = now.add(const Duration(minutes: 20));
      await controller.debugEvaluateSessionGuard();
      expect(
        container.read(sessionControllerProvider).activeWarning?.message,
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
    expect(live.activeWarning?.kind, SessionWarningKind.duration);
    expect(live.activeWarning?.message, contains('4시간 45분'));
    expect(live.activeWarning?.actions, isEmpty);
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
    'a filter-accepted high-speed-invalid sample immediately evaluates duration',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final engine = SyntheticLocationEngine(
        permission: LocationPermissionState.granted,
      );
      var now = DateTime(2026, 8, 22, 9);
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
      final startedAt = container
          .read(sessionControllerProvider)
          .session!
          .startedAt;
      now = startedAt.add(const Duration(hours: 4, minutes: 45));
      controller.debugIngestSamples([
        LocationSample(
          timestamp: now,
          latitude: 37.5665,
          longitude: 126.9780,
          // Accepted by SampleFilter but rejected by the high-speed guard.
          accuracyM: 100,
        ),
      ]);
      await _pumpGuard();

      expect(
        container.read(sessionControllerProvider).activeWarning?.kind,
        SessionWarningKind.duration,
      );
    },
  );

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
      expect(live.activeWarning, isNull);
      expect(notifications.completions, isEmpty);
      expect(notifications.warnings.last, contains('저장을 마치지 못했어요'));
      expect(container.read(historyTickProvider), 0);
      expect((await repo.getActiveSession())?.id, session.id);
      expect(await repo.listCompleted(), isEmpty);
    },
  );

  test(
    'foreground high speed warns once and continue only dismisses its presentation',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final engine = SyntheticLocationEngine(
        permission: LocationPermissionState.granted,
      );
      final notifications = _FakeSessionNotifications();
      var now = DateTime(2026, 8, 21, 9);
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
      final startedAt = container
          .read(sessionControllerProvider)
          .session!
          .startedAt;
      for (final sample in _highSpeedTrace(startedAt, seconds: 60)) {
        now = sample.timestamp;
        controller.debugIngestSamples([sample]);
      }
      await _pumpGuard();

      var live = container.read(sessionControllerProvider);
      expect(live.activeWarning?.kind, SessionWarningKind.highSpeed);
      expect(live.activeWarning?.actions, {
        SessionWarningAction.stopRecording,
        SessionWarningAction.continueRecording,
      });
      expect(notifications.warnings, isEmpty);

      controller.continueAfterWarning();
      live = container.read(sessionControllerProvider);
      expect(live.activeWarning, isNull);

      for (final sample in _highSpeedTrace(
        startedAt.add(const Duration(seconds: 70)),
        seconds: 30,
      )) {
        now = sample.timestamp;
        controller.debugIngestSamples([sample]);
      }
      await _pumpGuard();
      expect(container.read(sessionControllerProvider).activeWarning, isNull);
    },
  );

  test(
    'background high speed notifies once and retains the active warning',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final engine = SyntheticLocationEngine(
        permission: LocationPermissionState.granted,
      );
      final notifications = _FakeSessionNotifications();
      var now = DateTime(2026, 8, 21, 9);
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
      controller.setAppForeground(false);
      final startedAt = container
          .read(sessionControllerProvider)
          .session!
          .startedAt;
      for (final sample in _highSpeedTrace(startedAt, seconds: 60)) {
        now = sample.timestamp;
        controller.debugIngestSamples([sample]);
      }
      await _pumpGuard();
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(sessionControllerProvider).activeWarning?.kind,
        SessionWarningKind.highSpeed,
      );
      expect(notifications.warnings, hasLength(1));
    },
  );

  test('high-speed stop action invokes the user stop flow once', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.granted,
    );
    var now = DateTime(2026, 8, 21, 9);
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
    final startedAt = container
        .read(sessionControllerProvider)
        .session!
        .startedAt;
    for (final sample in _highSpeedTrace(startedAt, seconds: 60)) {
      now = sample.timestamp;
      controller.debugIngestSamples([sample]);
    }
    await _pumpGuard();

    final ended = await Future.wait([
      controller.stopFromHighSpeedWarning(),
      controller.stopFromHighSpeedWarning(),
    ]);
    expect(ended.whereType<WalkSession>(), hasLength(1));
    expect(await repo.listCompleted(), hasLength(1));
    expect(container.read(historyTickProvider), 0);
  });

  testWidgets(
    'warm high-speed tap routes home and keeps the active warning actions',
    (tester) async {
      final repo = (await tester.runAsync<WalkRepository>(openTestRepository))!;
      addTearDown(repo.close);
      await tester.runAsync(
        () => repo.startSession(mode: TrackingMode.balanced),
      );
      final notifications = _FakeSessionNotifications();
      addTearDown(notifications.dispose);
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(
            SyntheticLocationEngine(
              permission: LocationPermissionState.granted,
            ),
          ),
          sessionNotificationServiceProvider.overrideWithValue(notifications),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionControllerProvider.notifier);
      await tester.runAsync(controller.restoreIfNeeded);
      final router = container.read(routerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SanboApp(),
        ),
      );
      router.go('/settings');
      await tester.pump();
      await tester.pump();
      notifications.emitTap(SessionWarningKind.highSpeed);
      await tester.pump();

      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(
        container.read(sessionControllerProvider).activeWarning?.kind,
        SessionWarningKind.highSpeed,
      );
      expect(container.read(sessionControllerProvider).activeWarning?.actions, {
        SessionWarningAction.stopRecording,
        SessionWarningAction.continueRecording,
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  test(
    'cold high-speed tap waits for recovery and ignores ended sessions',
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

      controller.handleNotificationTap(
        const SessionNotificationTap(SessionWarningKind.highSpeed),
      );
      await controller.restoreIfNeeded();

      expect(container.read(sessionControllerProvider).activeWarning, isNull);
    },
  );

  test('cold recovered high-speed stop finalizes once', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final session = await repo.startSession(mode: TrackingMode.balanced);
    await repo.insertSamples(
      session.id,
      _highSpeedTrace(session.startedAt, seconds: 60),
    );
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(
          SyntheticLocationEngine(permission: LocationPermissionState.granted),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(sessionControllerProvider.notifier);

    controller.handleNotificationTap(
      const SessionNotificationTap(SessionWarningKind.highSpeed),
    );
    await controller.restoreIfNeeded();

    expect(controller.state.isTracking, isFalse);
    expect(controller.state.activeWarning?.kind, SessionWarningKind.highSpeed);
    expect(await controller.stopFromHighSpeedWarning(), isNotNull);
    expect(await controller.stopFromHighSpeedWarning(), isNull);
    expect(await repo.getActiveSession(), isNull);
    expect(await repo.listCompleted(), hasLength(1));
  });

  test(
    'cold recovered high-speed continue preserves warning on resume failure',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final session = await repo.startSession(mode: TrackingMode.balanced);
      await repo.insertSamples(
        session.id,
        _highSpeedTrace(session.startedAt, seconds: 60),
      );
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(
            SyntheticLocationEngine(
              permission: LocationPermissionState.deniedForever,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(sessionControllerProvider.notifier);

      controller.handleNotificationTap(
        const SessionNotificationTap(SessionWarningKind.highSpeed),
      );
      await controller.restoreIfNeeded();
      await controller.continueAfterWarning();

      expect(controller.state.isTracking, isFalse);
      expect(controller.state.needsRecovery, isTrue);
      expect(
        controller.state.activeWarning?.kind,
        SessionWarningKind.highSpeed,
      );
      expect(controller.state.errorMessage, contains('위치 권한'));
    },
  );

  testWidgets(
    'cold high-speed tap routes home, shows recovered warning, and resumes once',
    (tester) async {
      final fixture = await _coldWarningFixture(tester);
      addTearDown(fixture.dispose);

      expect(fixture.router.routeInformationProvider.value.uri.path, '/');
      expect(fixture.notifications.tapDeliveries, 1);
      expect(find.text('산책 기록을 계속할까요?'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '계속 기록'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '기록 종료'), findsOneWidget);

      final continueButton = find.widgetWithText(TextButton, '계속 기록');
      final continueAction = tester
          .widget<TextButton>(continueButton)
          .onPressed!;
      await tester.runAsync(() async {
        continueAction.call();
        for (var attempt = 0; attempt < 20; attempt++) {
          if (fixture.controller.state.isTracking) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('Recovered session did not resume tracking.');
      });
      await tester.pump();

      final live = fixture.container.read(sessionControllerProvider);
      expect(live.isTracking, isTrue);
      expect(live.activeWarning, isNull);
      expect(fixture.notifications.tapDeliveries, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('cold recovered high-speed warning exposes one stop action', (
    tester,
  ) async {
    final fixture = await _coldWarningFixture(tester);
    addTearDown(fixture.dispose);

    final stop = find.widgetWithText(FilledButton, '기록 종료');
    expect(tester.widget<FilledButton>(stop).onPressed, isNotNull);

    expect(
      fixture.container.read(sessionControllerProvider).activeWarning,
      isNotNull,
    );
    expect(fixture.notifications.tapDeliveries, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _ColdWarningFixture {
  const _ColdWarningFixture({
    required this.repo,
    required this.container,
    required this.controller,
    required this.notifications,
    required this.router,
  });

  final WalkRepository repo;
  final ProviderContainer container;
  final SessionController controller;
  final _FakeSessionNotifications notifications;
  final GoRouter router;

  Future<void> dispose() async {
    router.dispose();
    container.dispose();
    notifications.dispose();
    await repo.close();
  }
}

Future<_ColdWarningFixture> _coldWarningFixture(WidgetTester tester) async {
  final repo = (await tester.runAsync<WalkRepository>(openTestRepository))!;
  final session = (await tester.runAsync<WalkSession>(
    () => repo.startSession(mode: TrackingMode.balanced),
  ))!;
  await tester.runAsync(
    () => repo.insertSamples(
      session.id,
      _highSpeedTrace(session.startedAt, seconds: 60),
    ),
  );
  final notifications = _FakeSessionNotifications();
  notifications.emitColdTap(SessionWarningKind.highSpeed);
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const Scaffold()),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      walkRepositoryProvider.overrideWithValue(repo),
      locationEngineProvider.overrideWithValue(
        SyntheticLocationEngine(permission: LocationPermissionState.granted),
      ),
      sessionNotificationServiceProvider.overrideWithValue(notifications),
      routerProvider.overrideWithValue(router),
    ],
  );
  final controller = container.read(sessionControllerProvider.notifier);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SanboApp()),
  );
  await tester.pump();
  await tester.runAsync(controller.restoreIfNeeded);
  await tester.pump();

  return _ColdWarningFixture(
    repo: repo,
    container: container,
    controller: controller,
    notifications: notifications,
    router: router,
  );
}

Future<void> _pumpGuard() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

List<LocationSample> _highSpeedTrace(DateTime start, {required int seconds}) {
  const degreesPerMeter = 1 / 111320.0;
  return [
    for (var second = 0; second <= seconds; second += 10)
      LocationSample(
        timestamp: start.add(Duration(seconds: second)),
        latitude: 37.5665 + (second * 10 * degreesPerMeter),
        longitude: 126.9780,
        accuracyM: 6,
      ),
  ];
}
