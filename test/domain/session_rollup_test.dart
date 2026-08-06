import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/pipeline/session_rollup.dart';

void main() {
  test('unobserved time and long GPS gaps are not counted as movement', () {
    final startedAt = DateTime(2026, 8, 7, 9);
    final session = WalkSession(
      id: 'gap',
      startedAt: startedAt,
      timezone: 'Asia/Seoul',
      trackingMode: TrackingMode.balanced,
    );
    final result = SessionRollup().compute(
      session: session,
      samples: [
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
      ],
      endedAt: startedAt.add(const Duration(minutes: 20)),
    );

    expect(result.durationS, 1200);
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
    final result = SessionRollup().compute(
      session: session,
      samples: [
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
      ],
      endedAt: startedAt.add(const Duration(seconds: 30)),
    );

    expect(result.stationaryTimeS, 10);
    expect(result.movingTimeS, 10);
  });
}
