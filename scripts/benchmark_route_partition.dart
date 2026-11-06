import 'dart:io';

import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/route_exclusion.dart';
import 'package:sanbo/domain/pipeline/route_partitioner.dart';

import '../test/helpers/legacy_route_partitioner.dart';

/// Synthetic local CPU comparison, not a battery or physical GPS benchmark.
void main() {
  final start = DateTime.utc(2026, 11, 7);
  for (final size in [1000, 3000]) {
    final samples = [
      for (var i = 0; i < size; i++)
        LocationSample(
          timestamp: start.add(Duration(seconds: i)),
          latitude: 0,
          longitude: i * .00001,
        ),
    ];
    final exclusions = [
      for (var i = 0; i < size; i++)
        RouteExclusion(
          id: '$i',
          sessionId: 'synthetic',
          startAt: start.add(Duration(seconds: size + i * 2)),
          endAt: start.add(Duration(seconds: size + i * 2 + 1)),
          reason: RouteExclusionReason.vehicle,
          createdAt: start,
        ),
    ];
    final times = <String, List<int>>{'previous': [], 'current': []};
    double? expectedDistance;
    for (var round = 0; round < 4; round++) {
      // Alternate order and discard the first run of each implementation.
      for (final name
          in round.isEven ? ['previous', 'current'] : ['current', 'previous']) {
        final watch = Stopwatch()..start();
        final result = name == 'previous'
            ? LegacyRoutePartitioner.partition(
                samples: samples,
                exclusions: exclusions,
              )
            : RoutePartitioner.partition(
                samples: samples,
                exclusions: exclusions,
              );
        watch.stop();
        final distance = result.segments.fold(
          0.0,
          (sum, edge) => sum + edge.distanceM,
        );
        expectedDistance ??= distance;
        if (distance != expectedDistance ||
            result.includedSamples.length != size ||
            result.fragments.length != 1) {
          throw StateError('Partition output mismatch');
        }
        if (round > 0) times[name]!.add(watch.elapsedMicroseconds);
      }
    }
    for (final values in times.values) {
      values.sort();
    }
    final previous = times['previous']![1] / 1000;
    final current = times['current']![1] / 1000;
    stdout.writeln(
      'samples=$size exclusions=$size previous_ms=${previous.toStringAsFixed(2)} current_ms=${current.toStringAsFixed(2)} equivalent=true',
    );
  }
}
