import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/features/home/discard_confirm.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';

import '../helpers/test_db.dart';

/// UX-H01: confirmDiscardIncompleteWalk gates discardActive (shipped path).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'dialog cancel does not delete; confirm + discardActive deletes session',
    (tester) async {
      late WalkRepository repo;
      late ProviderContainer container;
      late SessionController controller;

      await tester.runAsync(() async {
        repo = await openTestRepository();
        await repo.startSession(mode: TrackingMode.balanced);
        final engine = SyntheticLocationEngine(
          permission: LocationPermissionState.granted,
        );
        container = ProviderContainer(
          overrides: [
            walkRepositoryProvider.overrideWithValue(repo),
            locationEngineProvider.overrideWithValue(engine),
          ],
        );
        controller = container.read(sessionControllerProvider.notifier);
        await controller.restoreIfNeeded();
        expect(container.read(sessionControllerProvider).needsRecovery, isTrue);
      });
      addTearDown(() async {
        container.dispose();
        await tester.runAsync(() => repo.close());
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () async {
                    final ok = await confirmDiscardIncompleteWalk(context);
                    if (ok) {
                      // discardActive uses sqflite; finish via outer settle.
                      await controller.discardActive();
                    }
                  },
                  child: const Text('기록 삭제…'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('기록 삭제…'));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('미완료 기록 삭제'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pump();

      WalkSession? active = await tester.runAsync<WalkSession?>(
        () => repo.getActiveSession(),
      );
      expect(active, isNotNull);
      expect(container.read(sessionControllerProvider).needsRecovery, isTrue);

      await tester.tap(find.text('기록 삭제…'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump();

      active = await tester.runAsync<WalkSession?>(() => repo.getActiveSession());
      expect(active, isNull);
      expect(container.read(sessionControllerProvider).needsRecovery, isFalse);
    },
  );

  test('HomeScreen wires confirmDiscardIncompleteWalk before discardActive', () {
    final home = File('lib/features/home/home_screen.dart').readAsStringSync();
    expect(home, contains('confirmDiscardIncompleteWalk'));
    expect(home, contains('discardActive'));
    expect(
      home.indexOf('confirmDiscardIncompleteWalk'),
      lessThan(home.lastIndexOf('discardActive')),
    );
  });
}
