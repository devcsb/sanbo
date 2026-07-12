import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/fixtures/synthetic_trace.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';

import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start → ingest samples → stop yields non-zero metrics and windows',
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

    final controller = container.read(sessionControllerProvider.notifier);
    await controller.start(mode: TrackingMode.balanced);
    expect(container.read(sessionControllerProvider).isTracking, isTrue);

    final session = container.read(sessionControllerProvider).session!;
    // Samples aligned to session start so pipeline includes them.
    final trace = buildWalkTrace(
      start: session.startedAt,
      duration: const Duration(minutes: 2),
      speedMps: 1.3,
      step: const Duration(seconds: 3),
    );
    controller.debugIngestSamples(trace);

    final live = container.read(sessionControllerProvider);
    expect(live.sampleCount, trace.length);
    expect(live.liveDistanceM, greaterThan(50));

    final ended = await controller.stop();
    expect(ended, isNotNull);
    expect(ended!.totalDistanceM, greaterThan(50));
    expect(ended.durationS, greaterThan(0));
    expect(ended.validSampleCount, greaterThan(10));
    expect(ended.avgSpeedMps, greaterThan(0));

    final windows = await repo.getWindows(ended.id);
    expect(windows, isNotEmpty);
    expect(windows.any((w) => w.sampleCount > 0), isTrue);

    final listed = await repo.listCompleted();
    expect(listed.map((s) => s.id), contains(ended.id));
  });

  test('stream emit path also accumulates samples', () async {
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

    final controller = container.read(sessionControllerProvider.notifier);
    await controller.start();
    final session = container.read(sessionControllerProvider).session!;
    final trace = buildWalkTrace(
      start: session.startedAt,
      duration: const Duration(seconds: 60),
      step: const Duration(seconds: 4),
    );
    for (final s in trace) {
      engine.emit(s);
    }
    // Allow stream delivery
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      container.read(sessionControllerProvider).sampleCount,
      greaterThan(0),
      reason: 'broadcast stream should deliver to SessionController listener',
    );
  });

  test('permission denied does not start tracking', () async {
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

    final controller = container.read(sessionControllerProvider.notifier);
    await controller.start();
    final state = container.read(sessionControllerProvider);
    expect(state.isTracking, isFalse);
    expect(state.errorMessage, isNotNull);
  });
}
