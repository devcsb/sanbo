import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/services/session_export.dart';
import 'package:sanbo/domain/services/walk_stats.dart';

void main() {
  group('WalkStats', () {
    test('aggregates completed walks only', () {
      final sessions = [
        _session(
          id: 'a',
          distance: 1200,
          duration: 600,
          status: SessionStatus.completed,
        ),
        _session(
          id: 'b',
          distance: 4000,
          duration: 1800,
          status: SessionStatus.completed,
        ),
        _session(
          id: 'c',
          distance: 9999,
          duration: 9999,
          status: SessionStatus.active,
        ),
      ];
      final stats = WalkStats.fromSessions(sessions);
      expect(stats.walkCount, 2);
      expect(stats.totalDistanceM, 5200);
      expect(stats.totalDurationS, 2400);
      expect(stats.longestDistanceM, 4000);
      expect(stats.longestDurationS, 1800);
      expect(stats.summaryLine(), contains('산책 2번'));
      expect(stats.summaryLine(), contains('5.2 km'));
    });

    test('milestones unlock without competitive streak language', () {
      const stats = WalkStats(
        walkCount: 5,
        totalDistanceM: 5000,
        totalDurationS: 3600,
        longestDurationS: 3600,
        longestDistanceM: 2000,
      );
      final ids = stats.satisfied().map((m) => m.id).toSet();
      expect(ids, contains('first_walk'));
      expect(ids, contains('walks_5'));
      expect(ids, contains('distance_5km'));
      expect(ids, contains('long_walk_60m'));
      expect(ids, isNot(contains('walks_10')));

      final newly = stats.newlyUnlocked({'first_walk', 'walks_5'});
      expect(newly.map((m) => m.id), containsAll(['distance_5km', 'long_walk_60m']));
      expect(newly.map((m) => m.id), isNot(contains('first_walk')));
    });
  });

  group('pacePerKmLabel', () {
    test('formats walking pace', () {
      // 1.4 m/s ≈ 11:54 /km
      final label = pacePerKmLabel(1.4);
      expect(label, isNotNull);
      expect(label, endsWith('/km'));
      expect(pacePerKmLabel(0.1), isNull);
      expect(pacePerKmLabel(null), isNull);
    });
  });

  group('SessionExport', () {
    test('human summary includes distance time and notes', () {
      final session = _session(
        id: 'x',
        distance: 2500,
        duration: 1500,
        notes: '강변 산책',
      );
      final text = const SessionExport().humanSummary(session: session);
      expect(text, contains('산보 산책 요약'));
      expect(text, contains('2.50 km'));
      expect(text, contains('강변 산책'));
      expect(text, contains('로컬 기록'));
    });

    test('ndjson starts with session meta and includes samples', () {
      final session = _session(id: 'export-1', distance: 100, duration: 60);
      final samples = [
        LocationSample(
          timestamp: DateTime(2026, 7, 18, 9, 0, 0),
          latitude: 37.5,
          longitude: 127.0,
          accuracyM: 5,
          speedMps: 1.2,
        ),
      ];
      final windows = [
        MinuteWindow(
          windowStart: DateTime(2026, 7, 18, 9, 0),
          durationS: 60,
          partial: false,
          sampleCount: 1,
          rawSampleCount: 1,
          distanceM: 100,
          avgSpeedMps: 1.2,
          maxSpeedMps: 1.5,
          stationaryRatio: 0,
          quality: WindowQuality.high,
          hypothesisLabel: ActivityLabel.walkSteady,
          hypothesisConfidence: 0.8,
          evidence: const ['speed_band'],
        ),
      ];
      final ndjson = const SessionExport().toNdjson(
        session: session,
        windows: windows,
        samples: samples,
      );
      final lines = ndjson.trim().split('\n');
      expect(lines.length, greaterThanOrEqualTo(3));
      expect(lines.first, contains('"type":"session"'));
      expect(lines.first, contains('schema_version'));
      expect(ndjson, contains('"type":"sample"'));
      expect(ndjson, contains('"type":"window"'));
    });
  });
}

WalkSession _session({
  required String id,
  required double distance,
  required int duration,
  SessionStatus status = SessionStatus.completed,
  String? notes,
}) {
  return WalkSession(
    id: id,
    startedAt: DateTime(2026, 7, 18, 8, 0),
    endedAt: DateTime(2026, 7, 18, 8, 0).add(Duration(seconds: duration)),
    timezone: 'Asia/Seoul',
    trackingMode: TrackingMode.balanced,
    status: status,
    totalDistanceM: distance,
    durationS: duration,
    avgSpeedMps: duration > 0 ? distance / duration : 0,
    notes: notes,
  );
}
