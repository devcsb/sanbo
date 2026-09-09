import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/services/location_quality_policy.dart';

void main() {
  const policy = LocationQualityPolicy();
  final now = DateTime.utc(2026, 9, 9, 12);

  LocationSample make(DateTime time, {double lat = 37.5, double acc = 10}) =>
      LocationSample(
        timestamp: time,
        latitude: lat,
        longitude: 127,
        accuracyM: acc,
      );

  test('accepts a fresh cold fix', () {
    final result = policy.evaluate(sample: make(now), observedAt: now);
    expect(result.accepted, isTrue);
  });

  test('rejects malformed, stale, future, and inaccurate fixes', () {
    expect(
      policy
          .evaluate(
            sample: make(now, lat: double.nan),
            observedAt: now,
          )
          .rejection,
      LocationQualityRejection.invalidCoordinate,
    );
    expect(
      policy.evaluate(sample: make(now, acc: 500.1), observedAt: now).rejection,
      LocationQualityRejection.excessiveAccuracy,
    );
    expect(
      policy
          .evaluate(
            sample: make(now.subtract(const Duration(seconds: 31))),
            observedAt: now,
          )
          .rejection,
      LocationQualityRejection.staleTimestamp,
    );
    expect(
      policy
          .evaluate(
            sample: make(now.add(const Duration(seconds: 6))),
            observedAt: now,
          )
          .rejection,
      LocationQualityRejection.futureTimestamp,
    );
  });

  test('rejects pre-session and out-of-order samples', () {
    final start = now.subtract(const Duration(seconds: 10));
    expect(
      policy
          .evaluate(
            sample: make(start.subtract(const Duration(milliseconds: 1))),
            observedAt: now,
            sessionStart: start,
          )
          .rejection,
      LocationQualityRejection.beforeSession,
    );
    expect(
      policy
          .evaluate(
            sample: make(now.subtract(const Duration(seconds: 1))),
            observedAt: now,
            previousAccepted: now,
          )
          .rejection,
      LocationQualityRejection.outOfOrder,
    );
  });
}
