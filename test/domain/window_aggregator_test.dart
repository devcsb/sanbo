import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/models/route_exclusion.dart';
import 'package:sanbo/domain/pipeline/route_partitioner.dart';
import 'package:sanbo/domain/pipeline/window_aggregator.dart';

void main() {
  test(
    'keeps a deterministic representative when legacy exclusions share a minute row',
    () {
      final start = DateTime.utc(2026, 8, 21);
      final sample = LocationSample(
        timestamp: start,
        latitude: 37.5,
        longitude: 127,
        accuracyM: 5,
      );
      final exclusions = [
        RouteExclusion(
          id: 'first',
          sessionId: 'walk-1',
          startAt: start.add(const Duration(seconds: 10)),
          endAt: start.add(const Duration(seconds: 30)),
          reason: RouteExclusionReason.vehicle,
          createdAt: start,
        ),
        RouteExclusion(
          id: 'second',
          sessionId: 'walk-1',
          startAt: start.add(const Duration(seconds: 30)),
          endAt: start.add(const Duration(minutes: 1)),
          reason: RouteExclusionReason.vehicle,
          createdAt: start,
        ),
      ];
      final partition = RoutePartitioner.partition(
        samples: [sample],
        exclusions: exclusions,
      );

      final windows = WindowAggregator().aggregate(
        partition: partition,
        rawSamples: [sample],
        exclusions: exclusions,
        sessionStart: start,
        sessionEnd: start.add(const Duration(minutes: 1)),
      );

      expect(windows.single.userExclusionId, 'first');
    },
  );

  test('keeps a representative for a legacy partial minute exclusion', () {
    final start = DateTime.utc(2026, 8, 21);
    final sample = LocationSample(
      timestamp: start.add(const Duration(seconds: 5)),
      latitude: 37.5,
      longitude: 127,
      accuracyM: 5,
    );
    final exclusion = RouteExclusion(
      id: 'partial',
      sessionId: 'walk-1',
      startAt: start.add(const Duration(seconds: 10)),
      endAt: start.add(const Duration(seconds: 30)),
      reason: RouteExclusionReason.vehicle,
      createdAt: start,
    );
    final partition = RoutePartitioner.partition(
      samples: [sample],
      exclusions: [exclusion],
    );

    final windows = WindowAggregator().aggregate(
      partition: partition,
      rawSamples: [sample],
      exclusions: [exclusion],
      sessionStart: start,
      sessionEnd: start.add(const Duration(minutes: 1)),
    );

    expect(windows.single.userExclusionId, exclusion.id);
  });

  test('rounds a positive sub-second partial window up for persistence', () {
    final start = DateTime.utc(2026, 8, 21, 0, 0, 59, 500);
    final end = start.add(const Duration(microseconds: 500000));
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

    expect(windows, hasLength(1));
    expect(windows.single.durationS, 1);
    expect(windows.single.partial, isTrue);
  });

  test('buckets samples into minute windows with walk hypothesis', () {
    final start = DateTime(2026, 7, 12, 14, 0, 10);
    final samples = <LocationSample>[];
    // ~1.2 m/s walk for one minute
    for (var i = 0; i < 15; i++) {
      samples.add(
        LocationSample(
          timestamp: start.add(Duration(seconds: i * 4)),
          latitude: 37.5 + (i * 0.00004),
          longitude: 127.0,
          accuracyM: 8,
          speedMps: 1.2,
        ),
      );
    }
    final end = start.add(const Duration(minutes: 1, seconds: 5));
    final partition = RoutePartitioner.partition(
      samples: samples,
      exclusions: const [],
    );
    final windows = WindowAggregator().aggregate(
      partition: partition,
      rawSamples: samples,
      exclusions: const [],
      sessionStart: start,
      sessionEnd: end,
    );

    expect(windows, isNotEmpty);
    final first = windows.first;
    expect(first.windowStart, DateTime(2026, 7, 12, 14, 0));
    expect(first.sampleCount, greaterThanOrEqualTo(3));
    expect(first.distanceM, greaterThan(0));
    expect(first.quality, isNot(WindowQuality.gap));
    expect(
      first.hypothesisLabel,
      anyOf(
        ActivityLabel.walkSteady,
        ActivityLabel.walkBrisk,
        ActivityLabel.strollSlow,
      ),
    );
  });

  test('emits gap window when no samples in a minute', () {
    final start = DateTime(2026, 7, 12, 15, 0, 0);
    final end = start.add(const Duration(minutes: 2));
    final samples = [
      LocationSample(
        timestamp: start.add(const Duration(seconds: 5)),
        latitude: 37.5,
        longitude: 127.0,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: start.add(const Duration(seconds: 10)),
        latitude: 37.50005,
        longitude: 127.0,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: start.add(const Duration(seconds: 15)),
        latitude: 37.5001,
        longitude: 127.0,
        accuracyM: 5,
      ),
      // second minute empty
    ];
    final partition = RoutePartitioner.partition(
      samples: samples,
      exclusions: const [],
    );
    final windows = WindowAggregator().aggregate(
      partition: partition,
      rawSamples: samples,
      exclusions: const [],
      sessionStart: start,
      sessionEnd: end,
    );
    expect(windows.length, greaterThanOrEqualTo(2));
    final second = windows[1];
    expect(second.quality, WindowQuality.gap);
    expect(second.hypothesisLabel, ActivityLabel.unknown);
  });

  test('splits one trusted segment proportionally at a minute boundary', () {
    final start = DateTime.utc(2026, 8, 21, 0, 0, 50);
    final first = LocationSample(
      timestamp: start,
      latitude: 37.5,
      longitude: 127,
      accuracyM: 5,
    );
    final second = LocationSample(
      timestamp: start.add(const Duration(seconds: 20)),
      latitude: 37.5,
      longitude: 127.000226,
      accuracyM: 5,
    );
    final partition = RoutePartitioner.partition(
      samples: [first, second],
      exclusions: const [],
    );
    final windows = WindowAggregator().aggregate(
      partition: partition,
      rawSamples: [first, second],
      exclusions: const [],
      sessionStart: start,
      sessionEnd: second.timestamp,
    );
    expect(windows, hasLength(2));
    expect(
      windows[0].distanceM,
      closeTo(partition.segments.single.distanceM / 2, 0.01),
    );
    expect(
      windows[1].distanceM,
      closeTo(partition.segments.single.distanceM / 2, 0.01),
    );
    expect(
      windows[0].distanceM + windows[1].distanceM,
      closeTo(partition.segments.single.distanceM, 0.01),
    );
  });

  test('does not allocate distance across a fragment boundary', () {
    final start = DateTime.utc(2026, 8, 21, 0, 0, 50);
    final before = LocationSample(
      timestamp: start,
      latitude: 37.5,
      longitude: 127,
      accuracyM: 5,
    );
    final boundary = LocationSample(
      timestamp: start.add(const Duration(seconds: 10)),
      latitude: 37.5,
      longitude: 127.0001,
      accuracyM: 5,
      isFilteredOut: true,
    );
    final after = LocationSample(
      timestamp: start.add(const Duration(seconds: 20)),
      latitude: 37.5,
      longitude: 127.0002,
      accuracyM: 5,
    );
    final partition = RoutePartitioner.partition(
      samples: [before, boundary, after],
      exclusions: const [],
    );
    final windows = WindowAggregator().aggregate(
      partition: partition,
      rawSamples: [before, boundary, after],
      exclusions: const [],
      sessionStart: start,
      sessionEnd: after.timestamp,
    );
    expect(partition.fragments, hasLength(2));
    expect(partition.segments, isEmpty);
    expect(windows.fold<double>(0, (sum, window) => sum + window.distanceM), 0);
  });

  test('keeps micro-jitter samples but contributes zero window distance', () {
    final start = DateTime.utc(2026, 8, 21);
    final samples = [
      LocationSample(
        timestamp: start,
        latitude: 37.5,
        longitude: 127,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: start.add(const Duration(seconds: 10)),
        latitude: 37.5,
        longitude: 127.00001,
        accuracyM: 5,
      ),
    ];
    final partition = RoutePartitioner.partition(
      samples: samples,
      exclusions: const [],
    );

    final windows = WindowAggregator().aggregate(
      partition: partition,
      rawSamples: samples,
      exclusions: const [],
      sessionStart: start,
      sessionEnd: start.add(const Duration(seconds: 11)),
    );

    expect(partition.segments, hasLength(1));
    expect(partition.fragments.single.samples, hasLength(2));
    expect(partition.segments.single.distanceM, lessThan(1.5));
    expect(windows.single.sampleCount, 2);
    expect(windows.single.distanceM, 0);
  });

  test('assigns a session-end boundary sample to the last actual minute', () {
    final start = DateTime.utc(2026, 8, 21);
    final end = start.add(const Duration(minutes: 1));
    final samples = [
      LocationSample(
        timestamp: start.add(const Duration(seconds: 50)),
        latitude: 37.5,
        longitude: 127,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: end,
        latitude: 37.5001,
        longitude: 127,
        accuracyM: 5,
      ),
    ];
    final partition = RoutePartitioner.partition(
      samples: samples,
      exclusions: const [],
    );

    final windows = WindowAggregator().aggregate(
      partition: partition,
      rawSamples: samples,
      exclusions: const [],
      sessionStart: start,
      sessionEnd: end,
    );

    expect(windows, hasLength(1));
    expect(windows.single.sampleCount, 2);
    expect(windows.single.rawSampleCount, 2);
    expect(windows.single.endLat, 37.5001);
  });
}
