import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/pipeline/segment_merger.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';
import 'package:sanbo/domain/services/session_export.dart';
import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'review evidence survives backup and edits while raw GPS and metrics remain intact',
    () async {
      final source = await openTestRepository();
      final target = await openTestRepository();
      addTearDown(source.close);
      addTearDown(target.close);
      final start = DateTime.utc(2026, 11, 7);
      final session = await source.startSession(startedAt: start);
      final samples = [
        for (var i = 0; i < 6; i++)
          LocationSample(
            timestamp: start.add(Duration(seconds: i * 10)),
            latitude: (i.isEven ? 0 : 20) / 111194.92664455874,
            longitude: 0,
            accuracyM: 30,
            speedMps: 0,
          ),
      ];
      final result = SessionPipeline().process(
        session: session,
        rawSamples: samples,
        endedAt: samples.last.timestamp,
      );
      await source.finalizeSession(
        session: session,
        samples: result.filteredSamples,
        windows: result.windows,
        endedAt: samples.last.timestamp,
        totalDistanceM: result.metrics.totalDistanceM,
        durationS: result.metrics.durationS,
        movingTimeS: result.metrics.movingTimeS,
        stationaryTimeS: result.metrics.stationaryTimeS,
        avgSpeedMps: result.metrics.avgSpeedMps,
        validSampleCount: result.metrics.validSampleCount,
        medianAccuracyM: result.metrics.medianAccuracyM,
      );
      final before = await source.getSession(session.id);
      expect(
        (await source.getWindows(session.id)).single.needsGpsReview,
        isTrue,
      );
      await source.updateWindowUserLabel(
        sessionId: session.id,
        windowStart: start,
        userLabel: ActivityLabel.strollSlow,
        note: '실제 왕복 확인',
        confirmed: true,
      );
      await target.importBackupJson(await source.createBackupJson());
      var windows = await target.getWindows(session.id);
      expect(windows.single.evidence, contains(MinuteWindow.gpsJitterEvidence));
      expect(windows.single.needsGpsReview, isFalse);
      expect(windows.single.userNote, '실제 왕복 확인');
      final raw = await target.getSamples(session.id);
      expect(
        raw.map((s) => [s.latitude, s.longitude, s.isFilteredOut]),
        samples.map((s) => [s.latitude, s.longitude, false]),
      );
      final restored = await target.getSession(session.id);
      expect(restored!.totalDistanceM, before!.totalDistanceM);
      expect(restored.movingTimeS, before.movingTimeS);
      expect(
        const SessionExport().toNdjson(
          session: restored,
          windows: windows,
          samples: raw,
          exclusions: const [],
        ),
        contains(MinuteWindow.gpsJitterEvidence),
      );
      final segment = SegmentMerger()
          .merge(
            windows,
            sessionId: session.id,
            sessionStart: start,
            sessionEnd: restored.endedAt,
          )
          .single;
      final exclusion = await target.excludeRouteSegment(
        sessionId: session.id,
        segment: segment,
      );
      expect(
        (await target.getWindows(session.id)).single.needsGpsReview,
        isFalse,
      );
      await target.restoreRouteExclusion(
        sessionId: session.id,
        exclusionId: exclusion.id,
      );
      windows = await target.getWindows(session.id);
      expect(windows.single.evidence, contains(MinuteWindow.gpsJitterEvidence));
      expect(windows.single.userLabel, ActivityLabel.strollSlow);
      expect(windows.single.userConfirmed, isTrue);
      expect(windows.single.userNote, '실제 왕복 확인');
      expect(
        (await target.getSession(session.id))!.totalDistanceM,
        before.totalDistanceM,
      );
      expect(await target.getSamples(session.id), hasLength(6));
    },
  );
}
