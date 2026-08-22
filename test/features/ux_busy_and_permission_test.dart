import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/session_warning.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';
import 'package:sanbo/platform/notifications/session_notification_service.dart';

import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'start sets isBusy then clears; double start ignored while busy',
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

      final c = container.read(sessionControllerProvider.notifier);
      final f1 = c.start();
      // Immediately busy during permission/start path.
      expect(container.read(sessionControllerProvider).isBusy, isTrue);
      final f2 = c.start(); // should no-op while busy
      await f1;
      await f2;
      final live = container.read(sessionControllerProvider);
      expect(live.isBusy, isFalse);
      expect(live.isTracking, isTrue);
    },
  );

  test(
    'permission denied surfaces actionable Korean error, not tracking',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final engine = SyntheticLocationEngine(
        permission: LocationPermissionState.deniedForever,
      );
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
        ],
      );
      addTearDown(container.dispose);

      final c = container.read(sessionControllerProvider.notifier);
      await c.start();
      final live = container.read(sessionControllerProvider);
      expect(live.isTracking, isFalse);
      expect(live.isBusy, isFalse);
      expect(live.errorMessage, isNotNull);
      expect(live.errorMessage!, contains('설정'));
      expect(live.errorMessage!, isNot(contains('Exception')));
    },
  );

  test(
    'notification permission waits until location permission is granted',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final notifications = _NeverCompletingPermissionNotifications();
      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(
            SyntheticLocationEngine(permission: LocationPermissionState.denied),
          ),
          sessionNotificationServiceProvider.overrideWithValue(notifications),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionControllerProvider.notifier).start();

      expect(notifications.permissionRequests, 0);
    },
  );

  test('clearError removes banner message', () async {
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
    final c = container.read(sessionControllerProvider.notifier);
    await c.start();
    expect(container.read(sessionControllerProvider).errorMessage, isNotNull);
    c.clearError();
    expect(container.read(sessionControllerProvider).errorMessage, isNull);
  });

  test(
    'notification permission never blocks a granted location start',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final notifications = _NeverCompletingPermissionNotifications();
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

      final start = container.read(sessionControllerProvider.notifier).start();
      await start.timeout(const Duration(seconds: 1));

      expect(container.read(sessionControllerProvider).isTracking, isTrue);
      expect(notifications.permissionRequests, 1);
    },
  );
}

class _NeverCompletingPermissionNotifications
    implements SessionNotificationService {
  int permissionRequests = 0;

  @override
  Future<void> cancel({required SessionWarningKind kind}) async {}

  @override
  Future<void> cancelAllWarnings() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationPermissionResult> requestPermission() {
    permissionRequests++;
    return Completer<NotificationPermissionResult>().future;
  }

  @override
  Future<void> showCompletion({
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> showWarning(SessionWarning warning, {String? sessionId}) async {}

  @override
  Stream<SessionNotificationTap> get taps => const Stream.empty();
}
