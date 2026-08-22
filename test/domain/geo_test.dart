import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/pipeline/geo.dart';

void main() {
  group('haversineMeters', () {
    test('same point is zero', () {
      expect(
        haversineMeters(lat1: 37.5, lon1: 127.0, lat2: 37.5, lon2: 127.0),
        0,
      );
    });

    test('~111m north at equator-ish scale for 0.001 deg lat', () {
      // 1 degree lat ≈ 111 km → 0.001 deg ≈ 111 m
      final d = haversineMeters(
        lat1: 37.0,
        lon1: 127.0,
        lat2: 37.001,
        lon2: 127.0,
      );
      expect(d, greaterThan(100));
      expect(d, lessThan(120));
    });
  });

  group('floorToMinute', () {
    test('floors seconds and ms', () {
      final ts = DateTime(2026, 7, 12, 14, 3, 45, 123);
      final floor = floorToMinute(ts);
      expect(floor, DateTime(2026, 7, 12, 14, 3));
    });

    test('uses the persisted IANA timezone including DST boundaries', () {
      final beforeFallback = DateTime.utc(2026, 11, 1, 5, 30, 45);
      final afterFallback = DateTime.utc(2026, 11, 1, 6, 30, 45);

      expect(
        floorToMinute(beforeFallback, timezone: 'America/New_York').toUtc(),
        DateTime.utc(2026, 11, 1, 5, 30),
      );
      expect(
        floorToMinute(afterFallback, timezone: 'America/New_York').toUtc(),
        DateTime.utc(2026, 11, 1, 6, 30),
      );
    });

    test('returns a session-local minute while preserving the instant', () {
      final floored = floorToMinute(
        DateTime.utc(2026, 8, 21, 15, 3, 45),
        timezone: 'Asia/Seoul',
      );

      expect(floored.isUtc, isFalse);
      expect(floored.year, 2026);
      expect(floored.month, 8);
      expect(floored.day, 22);
      expect(floored.hour, 0);
      expect(floored.minute, 3);
      expect(floored.toUtc(), DateTime.utc(2026, 8, 21, 15, 3));
    });
  });

  group('pathDistanceMeters', () {
    test('sums segments', () {
      final d = pathDistanceMeters([
        (lat: 37.0, lon: 127.0),
        (lat: 37.001, lon: 127.0),
        (lat: 37.002, lon: 127.0),
      ]);
      expect(d, greaterThan(200));
      expect(d, lessThan(240));
    });
  });
}
