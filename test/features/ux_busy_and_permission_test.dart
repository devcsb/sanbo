import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';

import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start sets isBusy then clears; double start ignored while busy',
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
  });

  test('permission denied surfaces actionable Korean error, not tracking',
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
  });

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
}
