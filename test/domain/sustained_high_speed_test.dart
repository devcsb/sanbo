import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/services/automatic_route_exclusion.dart';

final _start = DateTime.utc(2026, 10, 16, 9);

MinuteWindow _minute(int index) => MinuteWindow(
  windowStart: _start.add(Duration(minutes: index)),
  durationS: 60,
  partial: false,
  sampleCount: 10,
  rawSampleCount: 10,
  distanceM: 0,
  avgSpeedMps: 0,
  maxSpeedMps: 0, // A derived maximum is deliberately not speed evidence.
  stationaryRatio: 0,
  quality: WindowQuality.high,
  hypothesisLabel: ActivityLabel.vehicle,
);

List<LocationSample> _fixes({
  int count = 7,
  int intervalUs = 10000000,
  double accuracy = 5,
  double speed = 3,
}) => [
  for (var i = 0; i < count; i++)
    LocationSample(
      timestamp: _start.add(Duration(microseconds: i * intervalUs)),
      latitude: speed * i * intervalUs / 1000000 / 111194.92664455874,
      longitude: 0,
      accuracyM: accuracy,
    ),
];

void main() {
  const policy = AutomaticRouteExclusionPolicy();

  for (final fixture in [
    (
      name: 'exactly thirty seconds and four fixes',
      count: 4,
      interval: 10000000,
      accuracy: 5.0,
      speed: 3.0,
      excluded: true,
    ),
    (
      name: 'one millisecond short',
      count: 4,
      interval: 9999666,
      accuracy: 5.0,
      speed: 3.0,
      excluded: false,
    ),
    (
      name: 'exactly 25-metre accuracy',
      count: 7,
      interval: 10000000,
      accuracy: 25.0,
      speed: 3.0,
      excluded: true,
    ),
    (
      name: 'accuracy just beyond 25 metres',
      count: 7,
      interval: 10000000,
      accuracy: 25.001,
      speed: 3.0,
      excluded: false,
    ),
    (
      name: 'exactly thirty-second gaps',
      count: 4,
      interval: 30000000,
      accuracy: 5.0,
      speed: 3.0,
      excluded: true,
    ),
    (
      name: 'gap just beyond thirty seconds',
      count: 4,
      interval: 30000001,
      accuracy: 5.0,
      speed: 3.0,
      excluded: false,
    ),
    (
      name: 'exactly ten kilometres per hour',
      count: 7,
      interval: 10000000,
      accuracy: 5.0,
      speed: 10 / 3.6,
      excluded: true,
    ),
    (
      name: 'below ten kilometres per hour',
      count: 7,
      interval: 10000000,
      accuracy: 5.0,
      speed: 10 / 3.6 - 0.001,
      excluded: false,
    ),
  ]) {
    test(fixture.name, () {
      final samples = _fixes(
        count: fixture.count,
        intervalUs: fixture.interval,
        accuracy: fixture.accuracy,
        speed: fixture.speed,
      );
      final candidates = policy.detect(
        windows: [_minute(0), _minute(1)],
        samples: samples,
        sessionStart: _start,
        sessionEnd: samples.last.timestamp,
      );
      expect(candidates, hasLength(fixture.excluded ? 1 : 0));
      if (fixture.excluded) {
        expect(candidates.single.startAt, _start);
        expect(candidates.single.endAt, samples.last.timestamp);
      }
    });
  }

  for (final accuracy in [double.nan, double.infinity, -1.0]) {
    test('invalid accuracy $accuracy cannot supply speed evidence', () {
      expect(
        policy.detect(
          windows: [_minute(0)],
          samples: _fixes(accuracy: accuracy),
          sessionStart: _start,
          sessionEnd: _start.add(const Duration(minutes: 1)),
        ),
        isEmpty,
      );
    });
  }

  test(
    'a filter rejection breaks proof even when adjacent speeds stay high',
    () {
      final samples = _fixes();
      samples[3] = samples[3].copyWith(isFilteredOut: true);
      expect(
        policy.detect(
          windows: [_minute(0)],
          samples: samples,
          sessionStart: _start,
          sessionEnd: samples.last.timestamp,
        ),
        isEmpty,
      );
    },
  );

  test('invalid coordinates break proof without bridging the missing fix', () {
    final samples = _fixes();
    samples[3] = LocationSample(
      timestamp: samples[3].timestamp,
      latitude: 91,
      longitude: 0,
      accuracyM: 5,
    );
    expect(
      policy.detect(
        windows: [_minute(0)],
        samples: samples,
        sessionStart: _start,
        sessionEnd: samples.last.timestamp,
      ),
      isEmpty,
    );
  });

  test('provider speed cannot replace observed displacement', () {
    final samples = [
      for (final fix in _fixes(speed: 1))
        LocationSample(
          timestamp: fix.timestamp,
          latitude: fix.latitude,
          longitude: fix.longitude,
          accuracyM: 5,
          speedMps: 30,
        ),
    ];
    expect(
      policy.detect(
        windows: [_minute(0)],
        samples: samples,
        sessionStart: _start,
        sessionEnd: samples.last.timestamp,
      ),
      isEmpty,
    );
  });

  test('unobserved time at the end of a walk remains included', () {
    final samples = _fixes(count: 12);
    final candidates = policy.detect(
      windows: [_minute(0), _minute(1)],
      samples: samples,
      sessionStart: _start,
      sessionEnd: _start.add(const Duration(minutes: 2)),
    );
    expect(candidates, hasLength(1));
    expect(candidates.single.startAt, _start);
    expect(candidates.single.endAt, _start.add(const Duration(minutes: 1)));
  });

  test('a partial first minute uses the real session bounds', () {
    final samples = _fixes(count: 9)
        .map(
          (fix) => LocationSample(
            timestamp: fix.timestamp.add(const Duration(seconds: 20)),
            latitude: fix.latitude,
            longitude: 0,
            accuracyM: 5,
          ),
        )
        .toList();
    final candidates = policy.detect(
      windows: [_minute(0), _minute(1)],
      samples: samples,
      sessionStart: samples.first.timestamp,
      sessionEnd: samples.last.timestamp,
    );
    expect(candidates, hasLength(1));
    expect(candidates.single.startAt, _start.add(const Duration(seconds: 20)));
    expect(candidates.single.endAt, _start.add(const Duration(seconds: 100)));
  });

  test('a corner with sustained forward progress remains detectable', () {
    final samples = [
      for (var t = 0; t <= 60; t += 10)
        LocationSample(
          timestamp: _start.add(Duration(seconds: t)),
          latitude: (t <= 30 ? t * 3 : 90) / 111194.92664455874,
          longitude: (t <= 30 ? 0 : (t - 30) * 3) / 111194.92664455874,
          accuracyM: 5,
        ),
    ];
    expect(
      policy.detect(
        windows: [_minute(0)],
        samples: samples,
        sessionStart: _start,
        sessionEnd: samples.last.timestamp,
      ),
      hasLength(1),
    );
  });
}
