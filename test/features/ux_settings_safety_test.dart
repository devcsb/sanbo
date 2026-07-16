import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/core/theme/app_theme.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/features/settings/settings_screen.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';

import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recovered walk disables mode changes and delete-all', (
    tester,
  ) async {
    late WalkRepository repository;
    await tester.runAsync(() async {
      repository = await openTestRepository();
      await repository.startSession(
        mode: TrackingMode.highAccuracy,
        startedAt: DateTime(2026, 7, 16, 8),
      );
    });
    addTearDown(() => tester.runAsync(repository.close));

    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repository),
        locationEngineProvider.overrideWithValue(
          SyntheticLocationEngine(permission: LocationPermissionState.granted),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () =>
          container.read(sessionControllerProvider.notifier).restoreIfNeeded(),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    final deleteTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '모든 기록 삭제'),
    );
    final selector = tester.widget<SegmentedButton<TrackingMode>>(
      find.byType(SegmentedButton<TrackingMode>),
    );
    expect(deleteTile.enabled, isFalse);
    expect(deleteTile.onTap, isNull);
    expect(selector.onSelectionChanged, isNull);
    expect(find.textContaining('진행 중인 산책을 마친 뒤'), findsNWidgets(2));
  });
}
