import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanbo/app.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/models/session_warning.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/features/intro/intro_providers.dart';
import 'package:sanbo/platform/location/geolocator_location_engine.dart';
import 'package:sanbo/platform/notifications/session_notification_service.dart';

class _RecordingSessionNotifications implements SessionNotificationService {
  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationPermissionResult> requestPermission() async {
    return NotificationPermissionResult.granted;
  }

  @override
  Stream<SessionNotificationTap> get taps => const Stream.empty();

  @override
  Future<void> showWarning(SessionWarning warning, {String? sessionId}) async {}

  @override
  Future<void> showCompletion({
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancel({required SessionWarningKind kind}) async {}

  @override
  Future<void> cancelAllWarnings() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('integration: iOS simulator uses the real location provider', (
    tester,
  ) async {
    final dbPath =
        '${Directory.systemTemp.path}/sanbo_native_${DateTime.now().microsecondsSinceEpoch}.db';
    final repo = await WalkRepository.open(path: dbPath);
    final engine = GeolocatorLocationEngine();
    final notifications = _RecordingSessionNotifications();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
          sessionNotificationServiceProvider.overrideWithValue(notifications),
          introSeenProvider.overrideWith((ref) => true),
        ],
        child: const SanboApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final element = tester.element(find.byType(SanboApp));
    final container = ProviderScope.containerOf(element);
    final controller = container.read(sessionControllerProvider.notifier);
    var trackingStarted = false;
    addTearDown(() async {
      if (trackingStarted) {
        try {
          await engine.stop();
        } catch (_) {
          // The test may already have stopped the provider during cleanup.
        }
      }
      await engine.dispose();
      await repo.close();
    });

    await controller.start();
    trackingStarted = true;
    var observedDistance = 0.0;
    var observedSamples = 0;
    for (var second = 0; second < 45; second++) {
      await tester.pump(const Duration(seconds: 1));
      final live = container.read(sessionControllerProvider);
      observedDistance = live.liveDistanceM;
      observedSamples = live.validSampleCount;
      if (observedDistance > 15 && observedSamples >= 3) break;
    }

    final live = container.read(sessionControllerProvider);
    expect(live.isTracking, isTrue, reason: live.errorMessage);
    expect(observedDistance, greaterThan(15));
    expect(observedSamples, greaterThanOrEqualTo(3));

    final ended = await controller.stop();
    trackingStarted = false;
    expect(ended, isNotNull);
    expect(ended!.status, SessionStatus.completed);
    expect(ended.totalDistanceM, greaterThan(15));
    expect((await repo.listCompleted()), hasLength(1));
  });
}
