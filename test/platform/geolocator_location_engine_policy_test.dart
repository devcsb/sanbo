import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/platform/location/geolocator_location_engine.dart';
import 'package:sanbo/platform/location/location_request_policy.dart';

void main() {
  test('ended fallback stream reports termination during fused recovery', () {
    expect(
      GeolocatorLocationEngine.endedStreamAction(
        running: true,
        usingLocationManagerFallback: true,
        recoveryInFlight: true,
        supportsLocationManagerFallback: true,
      ),
      LocationStreamEndAction.report,
    );
  });

  test('ended stream retries once only while tracking with fused location', () {
    expect(
      GeolocatorLocationEngine.shouldRecoverEndedStream(
        running: true,
        usingLocationManagerFallback: false,
        supportsLocationManagerFallback: true,
      ),
      isTrue,
    );
    expect(
      GeolocatorLocationEngine.shouldRecoverEndedStream(
        running: true,
        usingLocationManagerFallback: true,
        supportsLocationManagerFallback: true,
      ),
      isFalse,
    );
    expect(
      GeolocatorLocationEngine.shouldRecoverEndedStream(
        running: false,
        usingLocationManagerFallback: false,
        supportsLocationManagerFallback: true,
      ),
      isFalse,
    );
  });

  test(
    'stalled stream waits for the mode-specific timeout before recovery',
    () {
      final now = DateTime(2026, 8, 22, 12, 0);

      expect(
        GeolocatorLocationEngine.stalledStreamAction(
          running: true,
          usingLocationManagerFallback: false,
          recoveryInFlight: false,
          lastEmitAt: now.subtract(const Duration(seconds: 15)),
          now: now,
          timeout: const Duration(seconds: 16),
          supportsLocationManagerFallback: true,
        ),
        LocationStreamEndAction.ignore,
      );
      expect(
        GeolocatorLocationEngine.stalledStreamAction(
          running: true,
          usingLocationManagerFallback: false,
          recoveryInFlight: false,
          lastEmitAt: now.subtract(const Duration(seconds: 16)),
          now: now,
          timeout: const Duration(seconds: 16),
          supportsLocationManagerFallback: true,
        ),
        LocationStreamEndAction.recover,
      );
    },
  );

  test('stalled fallback stream stays alive during a GPS gap', () {
    final now = DateTime(2026, 8, 22, 12, 0);

    expect(
      GeolocatorLocationEngine.stalledStreamAction(
        running: true,
        usingLocationManagerFallback: true,
        recoveryInFlight: false,
        lastEmitAt: now.subtract(const Duration(seconds: 28)),
        now: now,
        timeout: const Duration(seconds: 28),
        supportsLocationManagerFallback: true,
      ),
      LocationStreamEndAction.ignore,
    );
  });

  test('stalled watchdog stays disabled on platforms without a fallback', () {
    final now = DateTime(2026, 8, 22, 12, 0);

    expect(
      GeolocatorLocationEngine.stalledStreamAction(
        running: true,
        usingLocationManagerFallback: false,
        recoveryInFlight: false,
        lastEmitAt: now.subtract(const Duration(seconds: 30)),
        now: now,
        timeout: const Duration(seconds: 16),
        supportsLocationManagerFallback: false,
      ),
      LocationStreamEndAction.ignore,
    );
  });

  test('stale stream events are ignored after a new stream is armed', () {
    expect(
      GeolocatorLocationEngine.shouldHandleStreamEvent(
        currentGeneration: 2,
        eventGeneration: 1,
      ),
      isFalse,
    );
    expect(
      GeolocatorLocationEngine.shouldHandleStreamEvent(
        currentGeneration: 2,
        eventGeneration: 2,
      ),
      isTrue,
    );
  });

  test('tracking modes map to deliberate battery request profiles', () {
    final saver = locationRequestProfile(TrackingMode.batterySaver);
    expect(saver.accuracy, LocationAccuracy.medium);
    expect(saver.interval, const Duration(seconds: 20));
    expect(saver.distanceFilterM, 10);
    expect(saver.keepCpuAwake, isFalse);

    final balanced = locationRequestProfile(TrackingMode.balanced);
    expect(balanced.accuracy, LocationAccuracy.high);
    expect(balanced.interval, const Duration(seconds: 8));
    expect(balanced.distanceFilterM, 5);
    expect(balanced.keepCpuAwake, isFalse);

    final precise = locationRequestProfile(TrackingMode.highAccuracy);
    expect(precise.accuracy, LocationAccuracy.bestForNavigation);
    expect(precise.interval, const Duration(seconds: 4));
    expect(precise.distanceFilterM, 2);
    expect(precise.keepCpuAwake, isTrue);
  });
}
