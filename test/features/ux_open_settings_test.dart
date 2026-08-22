import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/features/home/home_screen.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';

import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('openSystemSettings on LocationEngine increments synthetic spy',
      () async {
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.deniedForever,
    );
    final ok = await engine.openSystemSettings();
    expect(ok, isTrue);
    expect(engine.openSystemSettingsCalls, 1);
    await engine.openSystemSettings();
    expect(engine.openSystemSettingsCalls, 2);
  });

  testWidgets(
    'deniedForever error banner exposes 설정 열기 and calls openSystemSettings',
    (tester) async {
      late WalkRepository repo;
      await tester.runAsync(() async {
        repo = await openTestRepository();
      });
      addTearDown(() async {
        await tester.runAsync(() => repo.close());
      });

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

      // Drive shipped controller path before mount so permissionState is set.
      await tester.runAsync(() async {
        await container.read(sessionControllerProvider.notifier).start();
      });

      final live = container.read(sessionControllerProvider);
      expect(live.isTracking, isFalse);
      expect(live.permissionState, LocationPermissionState.deniedForever);
      expect(live.errorMessage, isNotNull);
      expect(live.errorMessage!, contains('설정'));
      expect(live.errorMessage!, isNot(contains('Exception')));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      // Allow brand Image.asset resolve / errorBuilder.
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('설정 열기'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);

      expect(engine.openSystemSettingsCalls, 0);
      await tester.tap(find.text('설정 열기'));
      await tester.pump();
      expect(engine.openSystemSettingsCalls, 1);
    },
  );

  testWidgets(
    'foreground-only tracking exposes 설정 열기 without blocking the walk',
    (tester) async {
      late WalkRepository repo;
      await tester.runAsync(() async {
        repo = await openTestRepository();
      });
      addTearDown(() async {
        await tester.runAsync(() => repo.close());
      });

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

      await tester.runAsync(() async {
        await container.read(sessionControllerProvider.notifier).start();
      });
      expect(container.read(sessionControllerProvider).isTracking, isTrue);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('설정 열기'), findsOneWidget);
      expect(find.textContaining('항상 허용'), findsWidgets);
      await tester.tap(find.text('설정 열기'));
      await tester.pump();
      expect(engine.openSystemSettingsCalls, 1);
    },
  );
}
