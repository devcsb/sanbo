import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanbo/app.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/route_exclusion.dart';
import 'package:sanbo/domain/models/session_warning.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/pipeline/segment_merger.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/features/intro/intro_providers.dart';
import 'package:sanbo/platform/location/geolocator_location_engine.dart';
import 'package:sanbo/platform/notifications/session_notification_service.dart';

class _RecordingSessionNotifications implements SessionNotificationService {
  final warnings = <SessionWarning>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationPermissionResult> requestPermission() async {
    return NotificationPermissionResult.granted;
  }

  @override
  Stream<SessionNotificationTap> get taps => const Stream.empty();

  @override
  Future<void> showWarning(SessionWarning warning, {String? sessionId}) async {
    warnings.add(warning);
  }

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

  testWidgets(
    'integration: iOS simulator raises a high-speed warning from real GPS',
    (tester) async {
      final dbPath =
          '${Directory.systemTemp.path}/sanbo_high_speed_${DateTime.now().microsecondsSinceEpoch}.db';
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

      await controller.start(mode: TrackingMode.highAccuracy);
      trackingStarted = true;

      for (var second = 0; second < 105; second++) {
        await tester.pump(const Duration(seconds: 1));
        if (container.read(sessionControllerProvider).activeWarning?.kind ==
            SessionWarningKind.highSpeed) {
          break;
        }
      }

      final state = container.read(sessionControllerProvider);
      expect(state.isTracking, isTrue, reason: state.errorMessage);
      expect(state.validSampleCount, greaterThanOrEqualTo(5));
      expect(state.liveDistanceM, greaterThan(300));
      expect(state.activeWarning?.kind, SessionWarningKind.highSpeed);
      // Foreground high-speed warnings stay in-app and deliberately suppress
      // a system notification. Background publication is covered by Android
      // cold-tap smoke and the native notification contract tests.
      expect(notifications.warnings, isEmpty);

      await controller.continueAfterWarning();
      expect(container.read(sessionControllerProvider).activeWarning, isNull);

      final ended = await controller.stop();
      trackingStarted = false;
      expect(ended, isNotNull);
      expect(ended!.status, SessionStatus.completed);
      expect(ended.totalDistanceM, greaterThan(300));
      expect((await repo.listCompleted()), hasLength(1));

      final windows = await repo.getWindows(ended.id);
      final segments = SegmentMerger().merge(
        windows,
        sessionId: ended.id,
        sessionStart: ended.startedAt,
        sessionEnd: ended.endedAt,
      );
      final candidate = segments.firstWhere(
        (segment) => segment.durationS > 0 && segment.distanceM > 0,
      );
      final beforeExclusion = (await repo.getSession(ended.id))!;
      final exclusion = await repo.excludeRouteSegment(
        sessionId: ended.id,
        segment: candidate,
        reason: RouteExclusionReason.vehicle,
      );
      final afterExclusion = (await repo.getSession(ended.id))!;
      expect(
        afterExclusion.totalDistanceM,
        lessThan(beforeExclusion.totalDistanceM ?? double.infinity),
      );

      await repo.restoreRouteExclusion(
        sessionId: ended.id,
        exclusionId: exclusion.id,
      );
      final restored = (await repo.getSession(ended.id))!;
      expect(
        restored.totalDistanceM,
        closeTo(beforeExclusion.totalDistanceM ?? 0, 1e-6),
      );
    },
  );
}
