import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/route_exclusion.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';

import '../helpers/test_db.dart';

final _start = DateTime.utc(2026, 10, 16, 9);

List<LocationSample> _trace({
  int seconds = 120,
  int interval = 4,
  double? accuracy = 5,
  double? providerSpeed,
  double Function(int)? position,
}) => [
  for (var t = 0; t <= seconds; t += interval)
    LocationSample(
      timestamp: _start.add(Duration(seconds: t)),
      latitude: (position?.call(t) ?? t * 3) / 111194.92664455874,
      longitude: 0,
      accuracyM: accuracy,
      speedMps: providerSpeed,
    ),
];

Future<({String id, SessionProcessResult original})> _finish(
  WalkRepository repo,
  List<LocationSample> samples,
) async {
  final session = await repo.startSession(startedAt: samples.first.timestamp);
  final end = samples.last.timestamp;
  final result = SessionPipeline().process(
    session: session,
    rawSamples: samples,
    endedAt: end,
  );
  await repo.finalizeSession(
    session: session,
    samples: result.filteredSamples,
    windows: result.windows,
    endedAt: end,
    totalDistanceM: result.metrics.totalDistanceM,
    durationS: result.metrics.durationS,
    movingTimeS: result.metrics.movingTimeS,
    stationaryTimeS: result.metrics.stationaryTimeS,
    avgSpeedMps: result.metrics.avgSpeedMps,
    validSampleCount: result.metrics.validSampleCount,
    medianAccuracyM: result.metrics.medianAccuracyM,
  );
  return (id: session.id, original: result);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WalkRepository repo;
  setUp(() async => repo = await openTestRepository());
  tearDown(() => repo.close());

  test(
    'one 15-metre GPS spike keeps the walking minute and raw fixes',
    () async {
      final walk = await _finish(
        repo,
        _trace(seconds: 60, position: (t) => t * 1.2 + (t == 32 ? 15 : 0)),
      );
      expect(await repo.getRouteExclusions(walk.id), isEmpty);
      final saved = (await repo.getSession(walk.id))!;
      expect(saved.durationS, 60);
      expect(saved.totalDistanceM, closeTo(92.4, 0.001));
      expect(await repo.getSamples(walk.id), hasLength(16));
    },
  );

  for (final accuracy in <double?>[26, null]) {
    test(
      'untrusted accuracy $accuracy cannot bypass evidence via vehicle inference',
      () async {
        final walk = await _finish(
          repo,
          _trace(accuracy: accuracy, position: (t) => t * 12),
        );
        expect(
          walk.original.windows.first.hypothesisLabel,
          ActivityLabel.vehicle,
        );
        expect(await repo.getRouteExclusions(walk.id), isEmpty);
        expect((await repo.getSession(walk.id))!.durationS, 120);
        expect(
          (await repo.getSession(walk.id))!.totalDistanceM,
          closeTo(1440, 0.001),
        );
      },
    );
  }

  test(
    'a 60-second observation gap cannot prove sustained high speed',
    () async {
      final walk = await _finish(repo, _trace(interval: 60));
      expect(await repo.getRouteExclusions(walk.id), isEmpty);
    },
  );

  test(
    'three fixes cannot prove high speed even across thirty seconds',
    () async {
      final walk = await _finish(repo, _trace(seconds: 30, interval: 15));
      expect(await repo.getRouteExclusions(walk.id), isEmpty);
    },
  );

  test('recurring GPS back-and-forth does not remove the minute', () async {
    final walk = await _finish(
      repo,
      _trace(seconds: 60, position: (t) => (t ~/ 4).isEven ? 0 : 20),
    );
    expect(await repo.getRouteExclusions(walk.id), isEmpty);
  });

  test(
    'high speed across a minute boundary keeps both partly walking minutes',
    () async {
      final walk = await _finish(
        repo,
        _trace(
          position: (t) => t <= 20
              ? t.toDouble()
              : t <= 100
              ? 20 + (t - 20) * 3.0
              : 260 + (t - 100).toDouble(),
        ),
      );
      expect(await repo.getRouteExclusions(walk.id), isEmpty);
      expect((await repo.getSession(walk.id))!.durationS, 120);
    },
  );

  for (final interval in [4, 8, 20]) {
    test(
      'sustained high speed is excluded at the $interval-second tracking cadence',
      () async {
        final walk = await _finish(
          repo,
          _trace(interval: interval, providerSpeed: 0),
        );
        final exclusion = (await repo.getRouteExclusions(walk.id)).single;
        expect(exclusion.reason, RouteExclusionReason.highSpeed);
        expect(exclusion.startAt, _start);
        expect(exclusion.endAt, _start.add(const Duration(minutes: 2)));
        expect((await repo.getSession(walk.id))!.durationS, 0);
        expect((await repo.getSession(walk.id))!.totalDistanceM, 0);

        await repo.restoreRouteExclusion(
          sessionId: walk.id,
          exclusionId: exclusion.id,
        );
        expect((await repo.getSession(walk.id))!.durationS, 120);
        expect(
          (await repo.getSession(walk.id))!.totalDistanceM,
          closeTo(360, 0.001),
        );
        expect(await repo.getSamples(walk.id), hasLength(120 ~/ interval + 1));
      },
    );
  }

  test(
    'editing a different minute does not recreate a cancelled speed exclusion',
    () async {
      final walk = await _finish(
        repo,
        _trace(position: (t) => t <= 60 ? t * 3.0 : 180 + (t - 60).toDouble()),
      );
      final exclusion = (await repo.getRouteExclusions(walk.id)).single;
      await repo.restoreRouteExclusion(
        sessionId: walk.id,
        exclusionId: exclusion.id,
      );
      await repo.updateWindowUserLabel(
        sessionId: walk.id,
        windowStart: _start.add(const Duration(minutes: 1)),
        userLabel: ActivityLabel.strollSlow,
      );
      expect(await repo.getRouteExclusions(walk.id), isEmpty);
      expect((await repo.getSession(walk.id))!.durationS, 120);
      expect(
        (await repo.getSession(walk.id))!.totalDistanceM,
        closeTo(240, 0.001),
      );
    },
  );

  test(
    'an unconfirmed vehicle label does not remove a completed walk',
    () async {
      final walk = await _finish(repo, _trace(position: (t) => t.toDouble()));
      await repo.updateWindowUserLabel(
        sessionId: walk.id,
        windowStart: _start,
        userLabel: ActivityLabel.vehicle,
        confirmed: false,
      );
      expect(await repo.getRouteExclusions(walk.id), isEmpty);
      expect((await repo.getSession(walk.id))!.durationS, 120);
    },
  );

  test(
    'editing another minute keeps a cancelled explicit vehicle exclusion',
    () async {
      final walk = await _finish(repo, _trace(position: (t) => t.toDouble()));
      await repo.updateWindowUserLabel(
        sessionId: walk.id,
        windowStart: _start,
        userLabel: ActivityLabel.vehicle,
      );
      final exclusion = (await repo.getRouteExclusions(walk.id)).single;
      await repo.restoreRouteExclusion(
        sessionId: walk.id,
        exclusionId: exclusion.id,
      );
      await repo.updateWindowUserLabel(
        sessionId: walk.id,
        windowStart: _start.add(const Duration(minutes: 1)),
        userLabel: ActivityLabel.strollSlow,
      );
      expect(await repo.getRouteExclusions(walk.id), isEmpty);
      expect((await repo.getSession(walk.id))!.durationS, 120);
    },
  );

  for (final wasSpeedExclusion in [true, false]) {
    test(
      'confirming another vehicle minute preserves cancelled ${wasSpeedExclusion ? 'speed' : 'vehicle'} exclusion',
      () async {
        final walk = await _finish(
          repo,
          _trace(
            position: (t) => wasSpeedExclusion && t <= 60
                ? t * 3.0
                : wasSpeedExclusion
                ? 180 + (t - 60).toDouble()
                : t.toDouble(),
          ),
        );
        if (!wasSpeedExclusion) {
          await repo.updateWindowUserLabel(
            sessionId: walk.id,
            windowStart: _start,
            userLabel: ActivityLabel.vehicle,
          );
        }
        final firstExclusion = (await repo.getRouteExclusions(walk.id)).single;
        await repo.restoreRouteExclusion(
          sessionId: walk.id,
          exclusionId: firstExclusion.id,
        );
        await repo.updateWindowUserLabel(
          sessionId: walk.id,
          windowStart: _start.add(const Duration(minutes: 1)),
          userLabel: ActivityLabel.vehicle,
        );
        final remaining = (await repo.getRouteExclusions(walk.id)).single;
        expect(remaining.startAt, _start.add(const Duration(minutes: 1)));
        expect(remaining.endAt, _start.add(const Duration(minutes: 2)));
        expect(remaining.id, isNot(firstExclusion.id));
        expect((await repo.getWindows(walk.id)).first.isUserExcluded, isFalse);
        expect((await repo.getSession(walk.id))!.durationS, 60);
      },
    );
  }
}
