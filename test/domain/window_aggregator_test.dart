import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/pipeline/route_partitioner.dart';
import 'package:sanbo/domain/pipeline/window_aggregator.dart';

void main() {
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
}
