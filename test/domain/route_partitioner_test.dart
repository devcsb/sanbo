import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/route_exclusion.dart';
import 'package:sanbo/domain/pipeline/route_partitioner.dart';

void main() {
  test('partition never bridges filters, exclusions, or trusted gaps', () {
    final t = DateTime.utc(2026, 8, 21, 0);
    LocationSample fix(int second, double lon, {bool filtered = false}) {
      return LocationSample(
        timestamp: t.add(Duration(seconds: second)),
        latitude: 37.5,
        longitude: lon,
        accuracyM: 5,
        isFilteredOut: filtered,
      );
    }

    final result = RoutePartitioner.partition(
      samples: [
        fix(0, 127.0000),
        fix(10, 127.0001),
        fix(20, 127.0002, filtered: true),
        fix(30, 127.0003),
        fix(70, 127.0007),
        fix(80, 127.0008),
        fix(120, 127.0012),
      ],
      exclusions: [
        RouteExclusion(
          id: 'vehicle-1',
          sessionId: 'walk-1',
          startAt: t.add(const Duration(seconds: 35)),
          endAt: t.add(const Duration(seconds: 65)),
          reason: RouteExclusionReason.vehicle,
          createdAt: t,
        ),
      ],
      maxGap: const Duration(seconds: 30),
    );

    expect(result.includedSamples.map((sample) => sample.timestamp), [
      t,
      t.add(const Duration(seconds: 10)),
      t.add(const Duration(seconds: 30)),
      t.add(const Duration(seconds: 70)),
      t.add(const Duration(seconds: 80)),
      t.add(const Duration(seconds: 120)),
    ]);
    expect(result.fragments.map((fragment) => fragment.samples.length), [
      2,
      1,
      2,
      1,
    ]);
    expect(result.segments, hasLength(2));
    expect(
      result.segments.every(
        (segment) => segment.duration <= const Duration(seconds: 30),
      ),
      isTrue,
    );
  });

  test('partition ignores samples outside the completed session bounds', () {
    final t = DateTime.utc(2026, 8, 21, 0);
    LocationSample fix(int second) {
      return LocationSample(
        timestamp: t.add(Duration(seconds: second)),
        latitude: 37.5,
        longitude: 127.0 + second / 100000.0,
        accuracyM: 5,
      );
    }

    final result = RoutePartitioner.partition(
      samples: [fix(-10), fix(0), fix(10), fix(20)],
      exclusions: const [],
      sessionStart: t,
      sessionEnd: t.add(const Duration(seconds: 10)),
    );

    expect(result.includedSamples.map((sample) => sample.timestamp), [
      t,
      t.add(const Duration(seconds: 10)),
    ]);
  });

  test('an exclusion crossing a segment splits two outside endpoints', () {
    final t = DateTime.utc(2026, 8, 21, 0);
    final result = RoutePartitioner.partition(
      samples: [
        LocationSample(
          timestamp: t,
          latitude: 37.5,
          longitude: 127,
          accuracyM: 5,
        ),
        LocationSample(
          timestamp: t.add(const Duration(seconds: 20)),
          latitude: 37.5,
          longitude: 127.001,
          accuracyM: 5,
        ),
      ],
      exclusions: [
        RouteExclusion(
          id: 'vehicle-1',
          sessionId: 'walk-1',
          startAt: t.add(const Duration(seconds: 8)),
          endAt: t.add(const Duration(seconds: 12)),
          reason: RouteExclusionReason.vehicle,
          createdAt: t,
        ),
      ],
    );
    expect(result.fragments.map((fragment) => fragment.samples.length), [1, 1]);
    expect(result.segments, isEmpty);
  });

  test('computes a finite speed for a positive sub-millisecond segment', () {
    final start = DateTime.utc(2026, 8, 21);
    final result = RoutePartitioner.partition(
      samples: [
        LocationSample(
          timestamp: start,
          latitude: 37.5,
          longitude: 127,
          accuracyM: 5,
        ),
        LocationSample(
          timestamp: start.add(const Duration(microseconds: 500)),
          latitude: 37.5,
          longitude: 127.000001,
          accuracyM: 5,
        ),
      ],
      exclusions: const [],
    );

    expect(result.segments, hasLength(1));
    expect(result.segments.single.duration, const Duration(microseconds: 500));
    expect(result.segments.single.speedMps.isFinite, isTrue);
  });

  test(
    'normalizes instants to UTC and rejects invalid identities and ranges',
    () {
      final start = DateTime.parse('2026-08-21T09:00:00+09:00');
      final exclusion = RouteExclusion(
        id: 'vehicle-1',
        sessionId: 'walk-1',
        startAt: start,
        endAt: start.add(const Duration(minutes: 1)),
        reason: RouteExclusionReason.vehicle,
        createdAt: start,
      );
      expect(exclusion.startAt, DateTime.utc(2026, 8, 21));
      expect(exclusion.endAt, DateTime.utc(2026, 8, 21, 0, 1));
      expect(exclusion.createdAt.isUtc, isTrue);
      expect(
        () => RouteExclusion(
          id: ' ',
          sessionId: 'walk-1',
          startAt: start,
          endAt: start.add(const Duration(minutes: 1)),
          reason: RouteExclusionReason.vehicle,
          createdAt: start,
        ),
        throwsArgumentError,
      );
      expect(
        () => RouteExclusion(
          id: 'vehicle-2',
          sessionId: '',
          startAt: start,
          endAt: start,
          reason: RouteExclusionReason.vehicle,
          createdAt: start,
        ),
        throwsArgumentError,
      );
    },
  );
}
