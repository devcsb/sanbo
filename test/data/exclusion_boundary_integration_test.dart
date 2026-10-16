import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/pipeline/route_partitioner.dart';
import 'package:sanbo/domain/services/route_playback.dart';
import 'package:sanbo/domain/services/session_export.dart';

import '../helpers/route_exclusion_fixture.dart';
import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final cadence in [4, 20]) {
    test(
      'walking boundary survives storage, playback, export and backup at ${cadence}s',
      () async {
        final repo = await openTestRepository();
        addTearDown(repo.close);
        final fixture = await seedCompletedBoundaryWalk(repo, cadence: cadence);
        final session = fixture.session;
        final exclusions = await repo.getRouteExclusions(session.id);
        final exclusion = exclusions.single;
        expect(session.totalDistanceM, closeTo(60, 0.001));
        expect(session.durationS, 60);
        expect(session.movingTimeS, 60);
        expect(session.avgSpeedMps, closeTo(1, 0.001));
        final history = await repo.listCompleted();
        expect(history.single.totalDistanceM, closeTo(60, 0.001));
        final stats = await repo.completedStats();
        expect(stats.totalDistanceM, closeTo(60, 0.001));
        expect(stats.totalDurationS, 60);
        final daily = await repo.dailyStats(
          startDate: DateTime(2026, 10, 16),
          endDateExclusive: DateTime(2026, 10, 17),
        );
        expect(daily.single.totalDistanceM, closeTo(60, 0.001));
        expect(daily.single.totalDurationS, 60);
        expect(exclusion.startAt, DateTime.utc(2026, 10, 16, 9, 1));
        expect(exclusion.endAt, DateTime.utc(2026, 10, 16, 9, 2));
        expect(fixture.windows.first.distanceM, closeTo(60, 0.001));
        expect(fixture.windows.last.distanceM, 0);
        expect(
          fixture.windows.last.evidence,
          contains('distance_window:exclusion_start_endpoint'),
        );

        final route = RoutePartitioner.partition(
          samples: fixture.samples,
          exclusions: exclusions,
        );
        expect(route.fragments.first.samples.last.timestamp, exclusion.startAt);
        expect(
          route.includedSamples.any(
            (sample) => exclusion.contains(sample.timestamp),
          ),
          isFalse,
        );
        final playback = RoutePlayback.flatten(route);
        expect(
          playback
              .where((point) => point.fragmentIndex == 0)
              .last
              .sample
              .timestamp,
          exclusion.startAt,
        );
        expect(playback.last.startsFragment, isTrue);
        expect(playback.last.sample.timestamp, exclusion.endAt);

        const export = SessionExport();
        final document = export.toJsonDocument(
          session: session,
          windows: fixture.windows,
          samples: fixture.samples,
          exclusions: exclusions,
          includeSamples: true,
        );
        expect(
          (document['session'] as Map)['total_distance_m'],
          closeTo(60, 0.001),
        );
        expect(
          (document['session'] as Map)['avg_speed_mps'],
          closeTo(1, 0.001),
        );
        expect(
          (document['windows'] as List).last['evidence'],
          contains('distance_window:exclusion_start_endpoint'),
        );
        expect(document['samples'], hasLength(120 ~/ cadence + 1));
        final lines = export
            .toNdjson(
              session: session,
              windows: fixture.windows,
              samples: fixture.samples,
              exclusions: exclusions,
            )
            .trim()
            .split('\n')
            .map((line) => jsonDecode(line) as Map)
            .toList();
        expect(lines.first['session']['moving_time_s'], 60);
        expect(
          lines.last['evidence'],
          contains('distance_window:exclusion_start_endpoint'),
        );
        expect(
          lines.where((line) => line['type'] == 'sample').length,
          fixture.samples.length,
        );
        expect(export.humanSummary(session: session), contains('거리: 0.06 km'));

        final restored = await openTestRepository();
        addTearDown(restored.close);
        final backup = await repo.createBackupJson();
        await restored.importBackupJson(backup);
        expect(
          (await restored.getSession(session.id))!.totalDistanceM,
          closeTo(60, 0.001),
        );
        expect(
          (await restored.getWindows(session.id)).last.evidence,
          contains('distance_window:exclusion_start_endpoint'),
        );
        final restoredExclusion = (await restored.getRouteExclusions(
          session.id,
        )).single;
        expect(restoredExclusion.id, exclusion.id);
        final rawBeforeRestore = (await repo.createBackupJson(
          exportedAt: session.startedAt,
        ));
        await repo.restoreRouteExclusion(
          sessionId: session.id,
          exclusionId: exclusion.id,
        );
        expect(
          (await repo.getSession(session.id))!.totalDistanceM,
          closeTo(240, 0.001),
        );
        expect((await repo.getSession(session.id))!.durationS, 120);
        final before = jsonDecode(rawBeforeRestore) as Map;
        final after =
            jsonDecode(
                  await repo.createBackupJson(exportedAt: session.startedAt),
                )
                as Map;
        expect(
          before['tables']['location_samples'],
          hasLength(120 ~/ cadence + 1),
        );
        expect(
          after['tables']['location_samples'],
          before['tables']['location_samples'],
        );
      },
    );
  }
}
