import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/route_exclusion.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/pipeline/route_partitioner.dart';
import 'package:sanbo/domain/pipeline/session_rollup.dart';
import 'package:sanbo/domain/pipeline/window_aggregator.dart';

void main() {
  test('unobserved time and long GPS gaps are not counted as movement', () {
    final startedAt = DateTime(2026, 8, 7, 9);
    final session = WalkSession(
      id: 'gap',
      startedAt: startedAt,
      timezone: 'Asia/Seoul',
      trackingMode: TrackingMode.balanced,
    );
    final samples = [
      LocationSample(
        timestamp: startedAt.add(const Duration(minutes: 5)),
        latitude: 37.5,
        longitude: 127,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: startedAt.add(const Duration(minutes: 5, seconds: 10)),
        latitude: 37.5001,
        longitude: 127,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: startedAt.add(const Duration(minutes: 15)),
        latitude: 37.51,
        longitude: 127,
        accuracyM: 5,
      ),
    ];
    final result = SessionRollup().compute(
      session: session,
      partition: RoutePartitioner.partition(
        samples: samples,
        exclusions: const [],
      ),
      exclusions: const [],
      endedAt: startedAt.add(const Duration(minutes: 20)),
    );

    expect(result.durationS, 1200);
    final int duration = result.durationS;
    expect(duration, 1200);
    expect(result.movingTimeS, 10);
    expect(result.stationaryTimeS, 0);
    expect(result.totalDistanceM, lessThan(20));
    expect(result.avgSpeedMps, greaterThan(0));
  });

  test('observed stationary and moving intervals remain separate', () {
    final startedAt = DateTime(2026, 8, 7, 9);
    final session = WalkSession(
      id: 'mixed',
      startedAt: startedAt,
      timezone: 'Asia/Seoul',
      trackingMode: TrackingMode.balanced,
    );
    final samples = [
      LocationSample(timestamp: startedAt, latitude: 37.5, longitude: 127),
      LocationSample(
        timestamp: startedAt.add(const Duration(seconds: 10)),
        latitude: 37.5,
        longitude: 127,
      ),
      LocationSample(
        timestamp: startedAt.add(const Duration(seconds: 20)),
        latitude: 37.5001,
        longitude: 127,
      ),
    ];
    final result = SessionRollup().compute(
      session: session,
      partition: RoutePartitioner.partition(
        samples: samples,
        exclusions: const [],
      ),
      exclusions: const [],
      endedAt: startedAt.add(const Duration(seconds: 30)),
    );

    expect(result.stationaryTimeS, 10);
    expect(result.movingTimeS, 10);
  });

  test('micro-jitter keeps observed time but contributes zero distance', () {
    final start = DateTime.utc(2026, 8, 21);
    final session = _session(id: 'micro-jitter', start: start);
    final samples = [
      LocationSample(timestamp: start, latitude: 37.5, longitude: 127),
      LocationSample(
        timestamp: start.add(const Duration(seconds: 10)),
        latitude: 37.5,
        longitude: 127.00001,
      ),
    ];

    final result = SessionRollup().compute(
      session: session,
      partition: RoutePartitioner.partition(
        samples: samples,
        exclusions: const [],
      ),
      exclusions: const [],
      endedAt: start.add(const Duration(seconds: 10)),
    );

    expect(result.totalDistanceM, 0);
    expect(result.movingTimeS + result.stationaryTimeS, 10);
  });

  test(
    'keeps the full duration for completed sessions longer than seven days',
    () {
      final startedAt = DateTime.utc(2026, 8, 1);
      final session = WalkSession(
        id: 'long',
        startedAt: startedAt,
        timezone: 'Asia/Seoul',
        trackingMode: TrackingMode.balanced,
      );
      final result = SessionRollup().compute(
        session: session,
        partition: RoutePartitioner.partition(
          samples: const [],
          exclusions: const [],
        ),
        exclusions: const [],
        endedAt: startedAt.add(const Duration(days: 10)),
      );

      final int duration = result.durationS;
      expect(duration, const Duration(days: 10).inSeconds);
    },
  );

  test('keeps zero samples as finite zero route metrics', () {
    final start = DateTime.utc(2026, 8, 21);
    final end = start.add(const Duration(minutes: 1));
    final session = _session(id: 'zero-samples', start: start);
    final partition = RoutePartitioner.partition(
      samples: const [],
      exclusions: const [],
    );

    final windows = WindowAggregator().aggregate(
      partition: partition,
      rawSamples: const [],
      exclusions: const [],
      sessionStart: start,
      sessionEnd: end,
    );
    final result = SessionRollup().compute(
      session: session,
      partition: partition,
      exclusions: const [],
      endedAt: end,
    );

    expect(partition.fragments, isEmpty);
    expect(windows.single.sampleCount, 0);
    _expectFiniteZeroMetrics(result);
  });

  test('keeps one included sample as finite zero route metrics', () {
    final start = DateTime.utc(2026, 8, 21);
    final end = start.add(const Duration(minutes: 1));
    final sample = LocationSample(
      timestamp: start,
      latitude: 37.5,
      longitude: 127,
      accuracyM: 5,
    );
    final session = _session(id: 'one-sample', start: start);
    final partition = RoutePartitioner.partition(
      samples: [sample],
      exclusions: const [],
    );

    final windows = WindowAggregator().aggregate(
      partition: partition,
      rawSamples: [sample],
      exclusions: const [],
      sessionStart: start,
      sessionEnd: end,
    );
    final result = SessionRollup().compute(
      session: session,
      partition: partition,
      exclusions: const [],
      endedAt: end,
    );

    expect(partition.fragments.single.samples, [sample]);
    expect(windows.single.sampleCount, 1);
    _expectFiniteZeroMetrics(result);
  });

  test('rounds a positive sub-second summary consistently with its window', () {
    final start = DateTime.utc(2026, 8, 21, 0, 0, 59, 500);
    final end = start.add(const Duration(microseconds: 500000));
    final session = _session(id: 'sub-second', start: start);
    final sample = LocationSample(
      timestamp: start,
      latitude: 37.5,
      longitude: 127,
      accuracyM: 5,
    );
    final partition = RoutePartitioner.partition(
      samples: [sample],
      exclusions: const [],
    );
    final windows = WindowAggregator().aggregate(
      partition: partition,
      rawSamples: [sample],
      exclusions: const [],
      sessionStart: start,
      sessionEnd: end,
    );
    final result = SessionRollup().compute(
      session: session,
      partition: partition,
      exclusions: const [],
      endedAt: end,
    );

    expect(windows.single.durationS, 1);
    expect(result.durationS, windows.single.durationS);
  });

  test('excludes every sample without creating route movement', () {
    final start = DateTime.utc(2026, 8, 21);
    final end = start.add(const Duration(minutes: 1));
    final session = _session(id: 'all-excluded', start: start);
    final exclusion = _exclusion(
      id: 'vehicle-1',
      sessionId: session.id,
      start: start,
      end: end,
    );
    final samples = [
      LocationSample(
        timestamp: start.add(const Duration(seconds: 10)),
        latitude: 37.5,
        longitude: 127,
      ),
      LocationSample(
        timestamp: start.add(const Duration(seconds: 20)),
        latitude: 37.5001,
        longitude: 127,
      ),
    ];
    final partition = RoutePartitioner.partition(
      samples: samples,
      exclusions: [exclusion],
    );

    final windows = WindowAggregator().aggregate(
      partition: partition,
      rawSamples: samples,
      exclusions: [exclusion],
      sessionStart: start,
      sessionEnd: end,
    );
    final result = SessionRollup().compute(
      session: session,
      partition: partition,
      exclusions: [exclusion],
      endedAt: end,
    );

    expect(partition.includedSamples, isEmpty);
    expect(windows.single.userExclusionId, exclusion.id);
    _expectFiniteZeroMetrics(result);
    expect(result.durationS, 0);
  });

  test('excludes the half-open start and keeps the end point', () {
    final start = DateTime.utc(2026, 8, 21);
    final end = start.add(const Duration(minutes: 1));
    final session = _session(id: 'endpoint', start: start);
    final exclusion = _exclusion(
      id: 'vehicle-1',
      sessionId: session.id,
      start: start.add(const Duration(seconds: 10)),
      end: start.add(const Duration(seconds: 20)),
    );
    final before = LocationSample(
      timestamp: start,
      latitude: 37.5,
      longitude: 127,
    );
    final atStart = LocationSample(
      timestamp: start.add(const Duration(seconds: 10)),
      latitude: 37.5001,
      longitude: 127,
    );
    final atEnd = LocationSample(
      timestamp: start.add(const Duration(seconds: 20)),
      latitude: 37.5002,
      longitude: 127,
    );
    final samples = [before, atStart, atEnd];
    final partition = RoutePartitioner.partition(
      samples: samples,
      exclusions: [exclusion],
    );

    final windows = WindowAggregator().aggregate(
      partition: partition,
      rawSamples: samples,
      exclusions: [exclusion],
      sessionStart: start,
      sessionEnd: end,
    );
    expect(windows.single.userExclusionId, exclusion.id);
    final result = SessionRollup().compute(
      session: session,
      partition: partition,
      exclusions: [exclusion],
      endedAt: end,
    );

    expect(exclusion.contains(atStart.timestamp), isTrue);
    expect(exclusion.contains(atEnd.timestamp), isFalse);
    expect(partition.includedSamples, [before, atEnd]);
    expect(partition.segments, isEmpty);
    _expectFiniteZeroMetrics(result);
    expect(result.durationS, 50);
  });

  test(
    'uses offset-equivalent exclusion instants for partition and rollup',
    () {
      final utcStart = DateTime.utc(2026, 8, 21);
      final sessionEnd = utcStart.add(const Duration(minutes: 2));
      final session = _session(id: 'offset', start: utcStart);
      final offsetStart = DateTime.parse('2026-08-21T09:00:00+09:00');
      final exclusion = _exclusion(
        id: 'vehicle-1',
        sessionId: session.id,
        start: offsetStart,
        end: offsetStart.add(const Duration(minutes: 1)),
      );
      final first = LocationSample(
        timestamp: utcStart,
        latitude: 37.5,
        longitude: 127,
      );
      final middle = LocationSample(
        timestamp: utcStart.add(const Duration(seconds: 30)),
        latitude: 37.5001,
        longitude: 127,
      );
      final endpoint = LocationSample(
        timestamp: utcStart.add(const Duration(minutes: 1)),
        latitude: 37.5002,
        longitude: 127,
      );
      final samples = [first, middle, endpoint];
      final partition = RoutePartitioner.partition(
        samples: samples,
        exclusions: [exclusion],
      );

      final windows = WindowAggregator().aggregate(
        partition: partition,
        rawSamples: samples,
        exclusions: [exclusion],
        sessionStart: utcStart,
        sessionEnd: sessionEnd,
      );
      final result = SessionRollup().compute(
        session: session,
        partition: partition,
        exclusions: [exclusion],
        endedAt: sessionEnd,
      );

      expect(exclusion.startAt, utcStart);
      expect(partition.includedSamples, [endpoint]);
      expect(windows.first.userExclusionId, exclusion.id);
      _expectFiniteZeroMetrics(result);
      expect(result.durationS, 60);
    },
  );
}

WalkSession _session({required String id, required DateTime start}) =>
    WalkSession(
      id: id,
      startedAt: start,
      timezone: 'Asia/Seoul',
      trackingMode: TrackingMode.balanced,
    );

RouteExclusion _exclusion({
  required String id,
  required String sessionId,
  required DateTime start,
  required DateTime end,
}) => RouteExclusion(
  id: id,
  sessionId: sessionId,
  startAt: start,
  endAt: end,
  reason: RouteExclusionReason.vehicle,
  createdAt: start,
);

void _expectFiniteZeroMetrics(SessionRollupResult result) {
  expect(result.totalDistanceM, 0);
  expect(result.movingTimeS, 0);
  expect(result.stationaryTimeS, 0);
  expect(result.avgSpeedMps, 0);
  expect(result.avgSpeedMps.isFinite, isTrue);
}
