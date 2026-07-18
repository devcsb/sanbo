import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanbo/app.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/features/intro/intro_providers.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
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
      engine.emit(
        LocationSample(
          timestamp: start.add(Duration(seconds: i * 4)),
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
}
