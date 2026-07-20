import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';

import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restoreIfNeeded sets needsRecovery without tracking', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    await repo.startSession(mode: TrackingMode.balanced);

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
    await c.restoreIfNeeded();
    final live = container.read(sessionControllerProvider);
    expect(live.needsRecovery, isTrue);
    expect(live.isTracking, isFalse);
    expect(live.session, isNotNull);
    expect(live.statusMessage, isNotNull);
  });

  test('recovery stop caps duration at last sample, not wall-clock now',
      () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);

    // Session started 3h ago, app killed; the real walk lasted ~10 min. All
    // samples are in the past relative to `now` (unlike a live stop).
    final start = DateTime.now().subtract(const Duration(hours: 3));
    final session = await repo.startSession(
      mode: TrackingMode.balanced,
      startedAt: start,
    );
    const degPerMeter = 1 / 111320.0;
    final samples = <LocationSample>[
      for (var i = 0; i < 60; i++)
        LocationSample(
          timestamp: start.add(Duration(seconds: i * 10)), // 0..590s, all past
          latitude: 37.5 + i * 10 * 1.2 * degPerMeter,
          longitude: 127.0,
          accuracyM: 8,
          speedMps: 1.2,
        ),
    ];
    await repo.insertSamples(session.id, samples);

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
    await c.restoreIfNeeded();
    expect(container.read(sessionControllerProvider).needsRecovery, isTrue);

    final ended = await c.stop();
    expect(ended, isNotNull);
    // Duration reflects the real ~590s walk, NOT the 3h app-dead gap.
    expect(ended!.durationS, greaterThan(400));
    expect(ended.durationS, lessThan(1200));
    // The dead gap must not be counted as moving time.
    expect(ended.movingTimeS!, lessThanOrEqualTo(ended.durationS!));
  });

  test('discardActive clears incomplete session', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    await repo.startSession(mode: TrackingMode.balanced);
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
    await c.restoreIfNeeded();
    await c.discardActive();
    final live = container.read(sessionControllerProvider);
    expect(live.session, isNull);
    expect(live.needsRecovery, isFalse);
    expect(await repo.getActiveSession(), isNull);
  });

  test('HomeScreen + discard_confirm ship recovery confirm and busy hierarchy',
      () {
    final home = File('lib/features/home/home_screen.dart').readAsStringSync();
    final confirm =
        File('lib/features/home/discard_confirm.dart').readAsStringSync();
    expect(home, contains('이어서 기록'));
    expect(home, contains('저장하고 종료'));
    expect(home, contains('confirmDiscardIncompleteWalk'));
    expect(home, contains('isBusy'));
    expect(home, contains('needsRecovery'));
    expect(home, contains('다시 시도'));
    expect(home, contains('설정 열기'));
    expect(home, contains('openSystemSettings'));
    expect(home, contains('else if (!recovery)'));
    expect(home, isNot(contains("'LIVE'")));
    expect(confirm, contains('기록 지우기'));
  });
}
