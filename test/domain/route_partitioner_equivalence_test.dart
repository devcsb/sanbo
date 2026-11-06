import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/route_exclusion.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/pipeline/route_partitioner.dart';
import '../helpers/legacy_route_partitioner.dart';

class CountedExclusion implements RouteExclusion {
  CountedExclusion(this.value);
  final RouteExclusion value;
  int calls = 0;
  @override
  String get id => value.id;
  @override
  String get sessionId => value.sessionId;
  @override
  DateTime get startAt => value.startAt;
  @override
  DateTime get endAt => value.endAt;
  @override
  DateTime get createdAt => value.createdAt;
  @override
  RouteExclusionReason get reason => value.reason;
  @override
  RouteExclusion clampedTo(WalkSession s) => value.clampedTo(s);
  @override
  bool contains(DateTime t) {
    calls++;
    return value.contains(t);
  }

  @override
  bool overlaps(DateTime a, DateTime b) {
    calls++;
    return value.overlaps(a, b);
  }
}

Object snapshot(RoutePartitionResult r) => [
  r.includedSamples.map((s) => s.timestamp.microsecondsSinceEpoch).toList(),
  r.fragments
      .map(
        (f) =>
            f.samples.map((s) => s.timestamp.microsecondsSinceEpoch).toList(),
      )
      .toList(),
  r.segments
      .map(
        (s) => [
          s.start.timestamp.microsecondsSinceEpoch,
          s.end.timestamp.microsecondsSinceEpoch,
          s.distanceM,
        ],
      )
      .toList(),
];
void main() {
  final t = DateTime.utc(2026, 11, 7);
  RouteExclusion exclude(int a, int b) => RouteExclusion(
    id: '$a',
    sessionId: 'walk',
    startAt: t.add(Duration(seconds: a)),
    endAt: t.add(Duration(seconds: b)),
    reason: RouteExclusionReason.vehicle,
    createdAt: t,
  );
  test(
    'duplicates, touching exclusions, invalid fixes and session bounds keep their exact geometry',
    () {
      final samples = [
        for (final second in [
          -10,
          0,
          10,
          10,
          20,
          30,
          40,
          50,
          120,
          130,
          150,
          160,
        ])
          LocationSample(
            timestamp: t.add(Duration(seconds: second)),
            latitude: second == 50 ? double.nan : 0,
            longitude: second * .00001,
            isFilteredOut: second == 130,
          ),
      ];
      final exclusions = [exclude(20, 30), exclude(30, 40), exclude(140, 150)];
      for (final preserve in [false, true]) {
        final actual = RoutePartitioner.partition(
          samples: samples,
          exclusions: exclusions,
          sessionStart: t,
          sessionEnd: t.add(const Duration(seconds: 150)),
          preserveExclusionStartEndpoint: preserve,
        );
        final expected = LegacyRoutePartitioner.partition(
          samples: samples,
          exclusions: exclusions,
          sessionStart: t,
          sessionEnd: t.add(const Duration(seconds: 150)),
          preserveExclusionStartEndpoint: preserve,
        );
        expect(snapshot(actual), snapshot(expected));
      }
    },
  );
  test('exclusion checks grow with inputs rather than their product', () {
    final exclusions = [
      for (var i = 0; i < 1000; i++)
        CountedExclusion(exclude(10000 + i * 2, 10001 + i * 2)),
    ];
    final samples = [
      for (var i = 0; i < 100; i++)
        LocationSample(
          timestamp: t.add(Duration(seconds: i)),
          latitude: 0,
          longitude: i * .00001,
        ),
    ];
    RoutePartitioner.partition(samples: samples, exclusions: exclusions);
    expect(
      exclusions.fold<int>(0, (sum, x) => sum + x.calls),
      lessThanOrEqualTo(4 * (exclusions.length + samples.length)),
    );
  });
  test(
    'sorted cursors preserve the old boundary behavior over seeded mixed routes',
    () {
      final random = Random(7026);
      for (var run = 0; run < 300; run++) {
        final exclusions = [
          for (var i = 0; i < 10; i++)
            exclude(i * 60 + 10, i * 60 + 20 + random.nextInt(20)),
        ]..shuffle(random);
        final samples = [
          for (var i = 0; i < 60; i++)
            LocationSample(
              timestamp: t.add(Duration(seconds: i * 10 + random.nextInt(3))),
              latitude: 37.5,
              longitude: 127 + i * .00001,
              accuracyM: 5,
              isFilteredOut: random.nextInt(9) == 0,
            ),
        ]..shuffle(random);
        for (final endpoint in [false, true]) {
          final actual = RoutePartitioner.partition(
            samples: samples,
            exclusions: exclusions,
            preserveExclusionStartEndpoint: endpoint,
          );
          final expected = LegacyRoutePartitioner.partition(
            samples: samples,
            exclusions: exclusions,
            preserveExclusionStartEndpoint: endpoint,
          );
          expect(
            snapshot(actual),
            snapshot(expected),
            reason: 'run=$run endpoint=$endpoint',
          );
        }
      }
    },
  );
}
