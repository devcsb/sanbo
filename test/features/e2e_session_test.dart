import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/fixtures/synthetic_trace.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/pipeline/segment_merger.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/features/history/history_providers.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';

import '../helpers/test_db.dart';

/// End-to-end on the production path:
/// start → synthetic samples → SessionPipeline → persist → list/detail/label.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('e2e pipeline: start → samples → stop → windows → user label', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.granted,
    );
    var now = DateTime.now();
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
        sessionClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    await controller.start();
    final session = container.read(sessionControllerProvider).session!;
    expect(session.id, isNotEmpty);

    final localTrace = buildWalkTrace(
      start: session.startedAt,
      duration: const Duration(minutes: 3),
      step: const Duration(seconds: 4),
      speedMps: 1.25,
    );
    // Production-shaped: geolocator timestamps are UTC (isUtc:true).
    final utcTrace = localTrace
        .map(
          (s) => LocationSample(
            timestamp: s.timestamp.toUtc(),
            latitude: s.latitude,
            longitude: s.longitude,
            accuracyM: s.accuracyM,
            speedMps: s.speedMps,
            altitudeM: s.altitudeM,
          ),
        )
        .toList();
    expect(utcTrace.every((s) => s.timestamp.isUtc), isTrue);
    for (final s in utcTrace) {
      engine.emit(s);
    }
    controller.debugIngestSamples(utcTrace);
    now = session.startedAt.add(const Duration(minutes: 3));

    final ended = await controller.stop();
    expect(ended, isNotNull);
    expect(ended!.totalDistanceM, greaterThan(100));
    expect(ended.avgSpeedMps, greaterThan(0));
    expect(ended.validSampleCount, greaterThan(20));

    final listed = await repo.listCompleted();
    expect(listed.map((e) => e.id), contains(ended.id));

    final detail = await repo.getSession(ended.id);
    expect(detail!.totalDistanceM, greaterThan(100));

    final samples = await repo.getSamples(ended.id);
    expect(samples.length, greaterThan(20));
    // Filter flags must be persisted (not all raw).
    expect(samples.any((s) => !s.isFilteredOut), isTrue);

    final windows = await repo.getWindows(ended.id);
    expect(windows, isNotEmpty);

    // Segments collapse mechanical minute rows.
    final segments = SegmentMerger().merge(windows);
    expect(segments, isNotEmpty);
    expect(segments.length, lessThanOrEqualTo(windows.length));

    final target = windows.firstWhere((w) => w.sampleCount > 0);
    await repo.updateWindowUserLabel(
      sessionId: ended.id,
      windowStart: target.windowStart,
      userLabel: ActivityLabel.parkLinger,
    );
    final after = await repo.getWindows(ended.id);
    final updated =
        after.firstWhere((w) => w.windowStart == target.windowStart);
    expect(updated.displayLabel, ActivityLabel.parkLinger);
    expect(updated.userConfirmed, isTrue);

    container.read(historyTickProvider.notifier).state++;
  });
}
