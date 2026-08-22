import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanbo/app.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/route_exclusion.dart';
import 'package:sanbo/domain/models/session_warning.dart';
import 'package:sanbo/domain/pipeline/segment_merger.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/features/intro/intro_providers.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';
import 'package:sanbo/platform/notifications/session_notification_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _RecordingSessionNotifications implements SessionNotificationService {
  final warnings = <SessionWarningKind>[];

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
    warnings.add(warning.kind);
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

  testWidgets('integration: session pipeline via UI', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dbPath =
        '${Directory.systemTemp.path}/sanbo_int_${DateTime.now().microsecondsSinceEpoch}.db';
    final repo = await WalkRepository.open(path: dbPath);
    addTearDown(repo.close);
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.granted,
    );
    final notifications = _RecordingSessionNotifications();
    var now = DateTime.now();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
          sessionNotificationServiceProvider.overrideWithValue(notifications),
          sessionClockProvider.overrideWithValue(() => now),
          introSeenProvider.overrideWith((ref) => true),
        ],
        child: const SanboApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('산책 시작'), findsOneWidget);
    await tester.tap(find.text('산책 시작'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final element = tester.element(find.byType(SanboApp));
    final container = ProviderScope.containerOf(element);
    final session = container.read(sessionControllerProvider).session;
    expect(session, isNotNull);
    final start = session!.startedAt;

    const degPerMeter = 1 / 111320.0;
    for (var i = 0; i < 30; i++) {
      final timestamp = start.add(Duration(seconds: i * 4));
      now = timestamp;
      engine.emit(
        LocationSample(
          timestamp: timestamp,
          latitude: 37.5 + i * 4 * 1.2 * degPerMeter,
          longitude: 127.0,
          accuracyM: 5,
          speedMps: 1.2,
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text('산책 종료'), findsOneWidget);
    await tester.tap(find.text('산책 종료'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final sessions = await repo.listCompleted();
    expect(sessions, isNotEmpty);
    expect(sessions.first.totalDistanceM ?? 0, greaterThan(50));
  });

  testWidgets('integration: high-speed warning and route exclusion recovery', (
    tester,
  ) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dbPath =
        '${Directory.systemTemp.path}/sanbo_int_guard_${DateTime.now().microsecondsSinceEpoch}.db';
    final repo = await WalkRepository.open(path: dbPath);
    addTearDown(repo.close);
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.granted,
    );
    final notifications = _RecordingSessionNotifications();
    var now = DateTime.now();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
          sessionNotificationServiceProvider.overrideWithValue(notifications),
          sessionClockProvider.overrideWithValue(() => now),
          introSeenProvider.overrideWith((ref) => true),
        ],
        child: const SanboApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final element = tester.element(find.byType(SanboApp));
    final container = ProviderScope.containerOf(element);
    final controller = container.read(sessionControllerProvider.notifier);
    await controller.start();
    final startedAt = container
        .read(sessionControllerProvider)
        .session!
        .startedAt;

    const degreesPerMeter = 1 / 111320.0;
    for (var i = 0; i <= 6; i++) {
      final timestamp = startedAt.add(Duration(seconds: i * 10));
      now = timestamp;
      engine.emit(
        LocationSample(
          timestamp: timestamp,
          latitude: 37.5 + i * 10 * 9.0 * degreesPerMeter,
          longitude: 127,
          accuracyM: 5,
          speedMps: 9,
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    await controller.debugEvaluateSessionGuard(now);

    var live = container.read(sessionControllerProvider);
    expect(live.activeWarning?.kind, SessionWarningKind.highSpeed);
    expect(live.activeWarning?.actions, {
      SessionWarningAction.stopRecording,
      SessionWarningAction.continueRecording,
    });
    expect(
      notifications.warnings,
      isEmpty,
      reason: 'foreground warnings remain in the in-app surface',
    );

    await controller.continueAfterWarning();
    live = container.read(sessionControllerProvider);
    expect(live.isTracking, isTrue);
    expect(live.activeWarning, isNull);

    for (var i = 7; i <= 11; i++) {
      final timestamp = startedAt.add(Duration(seconds: i * 10));
      now = timestamp;
      engine.emit(
        LocationSample(
          timestamp: timestamp,
          latitude:
              37.5 + (6 * 10 * 9.0 + (i - 6) * 10 * 1.2) * degreesPerMeter,
          longitude: 127,
          accuracyM: 5,
          speedMps: 1.2,
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    now = startedAt.add(const Duration(seconds: 116));
    final ended = await controller.stop();
    expect(ended, isNotNull);
    expect(ended!.totalDistanceM ?? 0, greaterThan(100));

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
    final beforeDistance = (await repo.getSession(ended.id))!.totalDistanceM!;
    final exclusion = await repo.excludeRouteSegment(
      sessionId: ended.id,
      segment: candidate,
      reason: RouteExclusionReason.vehicle,
    );
    final excludedDistance = (await repo.getSession(ended.id))!.totalDistanceM!;
    expect(excludedDistance, lessThan(beforeDistance));

    await repo.restoreRouteExclusion(
      sessionId: ended.id,
      exclusionId: exclusion.id,
    );
    final restoredDistance = (await repo.getSession(ended.id))!.totalDistanceM!;
    expect(restoredDistance, closeTo(beforeDistance, 1e-6));
  });
}
