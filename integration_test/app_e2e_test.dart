import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanbo/app.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('integration: session pipeline via UI', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path =
        '${DateTime.now().microsecondsSinceEpoch}_sanbo_int.db';
    // Use temp via factory default path under ffi
    final repo = await WalkRepository.open(
      path: path,
    );
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.granted,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          locationEngineProvider.overrideWithValue(engine),
        ],
        child: const SanboApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('산책 시작'));
    await tester.pump(const Duration(milliseconds: 200));

    const degPerMeter = 1 / 111320.0;
    for (var i = 0; i < 25; i++) {
      engine.emit(
        LocationSample(
          timestamp: DateTime.now(),
          latitude: 37.5 + i * 5 * 1.2 * degPerMeter,
          longitude: 127.0,
          accuracyM: 5,
          speedMps: 1.2,
        ),
      );
      await tester.pump(const Duration(milliseconds: 15));
    }

    await tester.tap(find.text('산책 종료'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final sessions = await repo.listCompleted();
    expect(sessions, isNotEmpty);
    expect(sessions.first.totalDistanceM ?? 0, greaterThan(0));
  });
}
