import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/route_exclusion.dart';
import 'package:sanbo/domain/pipeline/route_partitioner.dart';

final _start = DateTime.utc(2026, 10, 16, 9);

LocationSample _fix(int second, {bool filtered = false, double? latitude}) =>
    LocationSample(
      timestamp: _start.add(Duration(seconds: second)),
      latitude: latitude ?? second / 111194.92664455874,
      longitude: 0,
      accuracyM: 5,
      isFilteredOut: filtered,
    );

RouteExclusion _exclude(int start, int end) => RouteExclusion(
  id: 'exclude-$start',
  sessionId: 'boundary',
  startAt: _start.add(Duration(seconds: start)),
  endAt: _start.add(Duration(seconds: end)),
  reason: RouteExclusionReason.vehicle,
  createdAt: _start,
);

void main() {
  test('the exact start fix is only the preceding fragment endpoint', () {
    final fixes = [for (var t = 0; t <= 120; t += 20) _fix(t)];
    final exclusion = _exclude(60, 100);
    final result = RoutePartitioner.partition(
      samples: fixes,
      exclusions: [exclusion],
    );
    expect(result.fragments.first.samples, [
      fixes[0],
      fixes[1],
      fixes[2],
      fixes[3],
    ]);
    expect(identical(result.fragments.first.samples.last, fixes[3]), isTrue);
    expect(result.includedSamples, [
      fixes[0],
      fixes[1],
      fixes[2],
      fixes[5],
      fixes[6],
    ]);
    expect(result.fragments.last.samples, [fixes[5], fixes[6]]);
    expect(result.segments, hasLength(4));
    expect(
      result.segments.every(
        (edge) => !exclusion.overlaps(edge.start.timestamp, edge.end.timestamp),
      ),
      isTrue,
    );
    expect(
      result.segments.fold<double>(0, (sum, edge) => sum + edge.distanceM),
      closeTo(80, 0.001),
    );
    expect(fixes.every((fix) => !fix.isFilteredOut), isTrue);
  });

  test(
    'adjacent exclusions cannot turn a shared start into a route anchor',
    () {
      final fixes = [for (var t = 0; t <= 120; t += 20) _fix(t)];
      final result = RoutePartitioner.partition(
        samples: fixes,
        exclusions: [_exclude(60, 80), _exclude(80, 100)],
      );
      expect(result.fragments.map((fragment) => fragment.samples.length), [
        4,
        2,
      ]);
      expect(
        result.fragments.expand((fragment) => fragment.samples),
        isNot(contains(fixes[4])),
      );
      expect(result.segments, hasLength(4));
    },
  );

  for (final boundary in [_fix(60, filtered: true), _fix(60, latitude: 91)]) {
    test(
      'an unusable boundary fix is not retained: filtered=${boundary.isFilteredOut}',
      () {
        final result = RoutePartitioner.partition(
          samples: [
            _fix(0),
            _fix(20),
            _fix(40),
            boundary,
            _fix(100),
            _fix(120),
          ],
          exclusions: [_exclude(60, 100)],
        );
        expect(
          result.fragments.first.samples.last.timestamp,
          _start.add(const Duration(seconds: 40)),
        );
        expect(result.segments, hasLength(3));
      },
    );
  }

  test('a boundary cannot bridge a trusted-location gap', () {
    final result = RoutePartitioner.partition(
      samples: [_fix(0), _fix(20), _fix(60), _fix(100), _fix(120)],
      exclusions: [_exclude(60, 100)],
      maxGap: const Duration(seconds: 30),
    );
    expect(result.fragments.map((fragment) => fragment.samples.length), [2, 2]);
    expect(result.segments, hasLength(2));
  });

  test('a filter rejection before the boundary cannot be skipped', () {
    final result = RoutePartitioner.partition(
      samples: [
        _fix(0),
        _fix(20),
        _fix(40, filtered: true),
        _fix(60),
        _fix(100),
        _fix(120),
      ],
      exclusions: [_exclude(60, 100)],
    );
    expect(result.fragments.map((fragment) => fragment.samples.length), [2, 2]);
    expect(result.segments, hasLength(2));
  });

  test('an absent boundary is never interpolated', () {
    final fixes = [_fix(0), _fix(20), _fix(40), _fix(70), _fix(100), _fix(120)];
    final result = RoutePartitioner.partition(
      samples: fixes,
      exclusions: [_exclude(60, 100)],
    );
    expect(result.fragments.first.samples.length, 3);
    expect(
      result.fragments
          .expand((fragment) => fragment.samples)
          .every(fixes.contains),
      isTrue,
    );
    expect(result.segments, hasLength(3));
  });
}
