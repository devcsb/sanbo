import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/pipeline/route_partitioner.dart';
import 'package:sanbo/domain/services/route_playback.dart';

LocationSample _sample(DateTime timestamp, {bool filtered = false}) {
  return LocationSample(
    timestamp: timestamp,
    latitude: 37.5,
    longitude: 127,
    isFilteredOut: filtered,
  );
}

void main() {
  final start = DateTime(2026, 7, 31, 10);

  test('playable samples exclude filtered fixes and sort by time', () {
    final samples = RoutePlayback.playableSamples([
      _sample(start.add(const Duration(seconds: 20))),
      _sample(start, filtered: true),
      _sample(start.add(const Duration(seconds: 10))),
    ]);

    expect(samples, hasLength(2));
    expect(samples.first.timestamp, start.add(const Duration(seconds: 10)));
    expect(samples.last.timestamp, start.add(const Duration(seconds: 20)));
  });

  test('nearest index finds bounds and the closest recorded fix', () {
    final samples = [
      _sample(start),
      _sample(start.add(const Duration(seconds: 10))),
      _sample(start.add(const Duration(seconds: 20))),
    ];

    expect(
      RoutePlayback.nearestIndex(
        samples,
        start.subtract(const Duration(seconds: 2)),
      ),
      0,
    );
    expect(
      RoutePlayback.nearestIndex(
        samples,
        start.add(const Duration(seconds: 16)),
      ),
      2,
    );
    expect(
      RoutePlayback.nearestIndex(
        samples,
        start.add(const Duration(minutes: 1)),
      ),
      2,
    );
  });

  test('segment range uses an exclusive end boundary', () {
    final samples = [
      _sample(start),
      _sample(start.add(const Duration(seconds: 59))),
      _sample(start.add(const Duration(minutes: 1))),
    ];

    final inRange = RoutePlayback.samplesInRange(
      samples,
      start: start,
      endExclusive: start.add(const Duration(minutes: 1)),
    );

    expect(inRange, hasLength(2));
  });

  test('long routes advance in at most about fifty ticks', () {
    expect(RoutePlayback.stepForSampleCount(0), 1);
    expect(RoutePlayback.stepForSampleCount(1), 1);
    expect(RoutePlayback.stepForSampleCount(50), 1);
    expect(RoutePlayback.stepForSampleCount(51), 1);
    expect(RoutePlayback.stepForSampleCount(501), 10);
    expect(
      RoutePlayback.intervalForSampleCount(501),
      const Duration(milliseconds: 400),
    );
  });

  test('flatten keeps fragment boundaries during playback', () {
    final a = _sample(start);
    final b = _sample(start.add(const Duration(seconds: 10)));
    final c = _sample(start.add(const Duration(seconds: 20)));
    final d = _sample(start.add(const Duration(seconds: 30)));

    final points = RoutePlayback.flatten(
      RoutePartitionResult(
        includedSamples: [a, b, c, d],
        segments: [
          RouteSegment(start: a, end: b, distanceM: 1),
          RouteSegment(start: c, end: d, distanceM: 1),
        ],
        fragments: [
          RouteFragment([a, b]),
          RouteFragment([c, d]),
        ],
      ),
    );

    expect(points.map((point) => point.fragmentIndex), [0, 0, 1, 1]);
    expect(points.map((point) => point.pointIndex), [0, 1, 0, 1]);
    expect(points[2].startsFragment, isTrue);
  });
}
