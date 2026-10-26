import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/pipeline/geo.dart';
import 'package:sanbo/domain/services/session_week_summary.dart';

WalkSession walk(
  String id,
  String start,
  String end, {
  int? moving = 600,
  String zone = 'Asia/Seoul',
  double distance = 800,
}) => WalkSession(
  id: id,
  startedAt: parseStoredInstant(start, timezone: zone),
  endedAt: parseStoredInstant(end, timezone: zone),
  timezone: zone,
  trackingMode: TrackingMode.values.first,
  status: SessionStatus.completed,
  durationS: 1200,
  movingTimeS: moving,
  totalDistanceM: distance,
);
void main() {
  test(
    'uses moving seconds, deduplicates reference, and ignores later records',
    () {
      final reference = walk('a', '2026-10-27T09:00:00', '2026-10-27T09:20:00');
      final result = summarizeSessionWeek(
        reference: reference,
        sessions: [
          reference,
          reference,
          walk('b', '2026-10-26T09:00:00Z', '2026-10-26T09:20:00Z'),
          walk('future', '2026-10-27T10:00:00', '2026-10-27T10:20:00'),
        ],
      );
      expect(result.movingTimeS, 1200);
      expect(result.sessionCount, 2);
      expect(result.sessions.map((entry) => entry.id), ['b', 'a']);
      expect(result.referenceMovingTimeS, 600);
      expect(result.days, hasLength(7));
      expect(result.weekStart.toUtc(), DateTime.utc(2026, 10, 25, 15));
      expect(result.partial, isFalse);
    },
  );
  test(
    'unknown, invalid and midnight spanning aggregates are partial without allocation',
    () {
      final reference = walk('a', '2026-10-27T09:00:00', '2026-10-27T09:20:00');
      for (final invalid in [
        walk('bad', '2026-10-26T23:50:00', '2026-10-27T00:10:00'),
        walk('bad', '2026-10-26T09:00:00', '2026-10-26T09:20:00', moving: null),
        walk('bad', '2026-10-26T09:00:00', '2026-10-26T09:20:00', moving: -1),
        walk(
          'bad',
          '2026-10-26T09:00:00',
          '2026-10-26T09:20:00',
          distance: double.nan,
        ),
      ]) {
        final result = summarizeSessionWeek(
          reference: reference,
          sessions: [reference, invalid],
        );
        expect(result.movingTimeS, 600);
        expect(result.partial, isTrue);
        expect(result.previousMovingTimeS, isNull);
        expect(result.omittedSessionIds, contains('bad'));
      }
    },
  );
  test(
    'week crossing cannot be apportioned and comparison cutoff crossing is partial',
    () {
      final reference = walk('a', '2026-10-27T09:00:00', '2026-10-27T09:20:00');
      final result = summarizeSessionWeek(
        reference: reference,
        sessions: [
          reference,
          walk('boundary', '2026-10-25T23:50:00', '2026-10-26T00:10:00'),
          walk('previous', '2026-10-20T09:00:00', '2026-10-20T09:30:00'),
        ],
      );
      expect(result.partial, isTrue);
      expect(result.previousMovingTimeS, isNull);
    },
  );
  test('DST compares calendar wall clock, not fixed 168 hours', () {
    final reference = walk(
      'a',
      '2026-11-01T07:00:00Z',
      '2026-11-01T08:00:00Z',
      zone: 'America/New_York',
    );
    final result = summarizeSessionWeek(
      reference: reference,
      sessions: [reference],
    );
    expect(result.previousEnd.toUtc(), DateTime.utc(2026, 10, 25, 7));
    expect(result.weekStart.toUtc(), DateTime.utc(2026, 10, 26, 4));
    expect(
      result.previousMovingTimeS,
      isNull,
    ); // absent comparison is not zero activity
  });
  test(
    'midnight end belongs to the last included date and fractional seconds accept rounded totals',
    () {
      final reference = walk('a', '2026-10-25T23:50:00', '2026-10-26T00:00:00');
      final result = summarizeSessionWeek(
        reference: reference,
        sessions: [reference],
      );
      expect(result.weekStart.toUtc(), DateTime.utc(2026, 10, 18, 15));
      expect(result.partial, isFalse);
      expect(result.movingTimeS, 600);
      final short = walk(
        'short',
        '2026-10-27T09:00:00.000Z',
        '2026-10-27T09:00:09.900Z',
        moving: 10,
      );
      expect(
        summarizeSessionWeek(reference: short, sessions: [short]).movingTimeS,
        10,
      );
    },
  );
  test('empty source stays empty and active sessions do not contribute', () {
    final reference = walk('a', '2026-10-27T09:00:00', '2026-10-27T09:20:00');
    final result = summarizeSessionWeek(reference: reference, sessions: []);
    expect(result.movingTimeS, 0);
    expect(result.referenceMovingTimeS, isNull);
    expect(result.sessionCount, 0);
  });
}
