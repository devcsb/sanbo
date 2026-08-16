import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/services/session_guard.dart';

void main() {
  final start = DateTime(2026, 7, 29, 9);

  LocationSample sample({
    required DateTime at,
    double latitude = 37.5665,
    double speedMps = 0,
    double accuracyM = 6,
  }) {
    return LocationSample(
      timestamp: at,
      latitude: latitude,
      longitude: 126.9780,
      accuracyM: accuracyM,
      speedMps: speedMps,
    );
  }

  test('warns after 20 stationary minutes and limits at 30 minutes', () {
    final guard = SessionGuard();
    guard.observe(sample(at: start));

    expect(
      guard
          .evaluate(
            startedAt: start,
            now: start.add(const Duration(minutes: 19)),
          )
          .event,
      SessionGuardEvent.none,
    );

    final warning = guard.evaluate(
      startedAt: start,
      now: start.add(const Duration(minutes: 20)),
    );
    expect(warning.event, SessionGuardEvent.stationaryWarning);
    expect(warning.remaining, const Duration(minutes: 10));

    expect(
      guard
          .evaluate(
            startedAt: start,
            now: start.add(const Duration(minutes: 30)),
          )
          .event,
      SessionGuardEvent.stationaryLimit,
    );
  });

  test(
    'meaningful movement clears the stay warning and restarts its clock',
    () {
      final guard = SessionGuard();
      guard.observe(sample(at: start));
      guard.evaluate(
        startedAt: start,
        now: start.add(const Duration(minutes: 20)),
      );

      final movedAt = start.add(const Duration(minutes: 21));
      final cleared = guard.observe(
        sample(at: movedAt, latitude: 37.5670, speedMps: 1.2),
      );
      expect(cleared, isTrue);
      expect(
        guard
            .evaluate(
              startedAt: start,
              now: start.add(const Duration(minutes: 40)),
            )
            .event,
        SessionGuardEvent.none,
      );
    },
  );

  test('derives walking speed when provider reports zero', () {
    final guard = SessionGuard();
    guard.observe(sample(at: start));
    guard.evaluate(
      startedAt: start,
      now: start.add(const Duration(minutes: 20)),
    );

    // Keep an adjacent fix so the controller can derive speed from GPS
    // displacement even though Android reports speed=0.0.
    guard.observe(sample(at: start.add(const Duration(minutes: 20))));
    final cleared = guard.observe(
      sample(
        at: start.add(const Duration(minutes: 20, seconds: 8)),
        latitude: 37.566608,
      ),
    );

    expect(cleared, isTrue);
  });

  test('continue action gives a fresh 20-minute stationary window', () {
    final guard = SessionGuard();
    guard.observe(sample(at: start));
    final continuedAt = start.add(const Duration(minutes: 20));
    guard.evaluate(startedAt: start, now: continuedAt);
    guard.continueStationaryTracking(continuedAt);

    expect(
      guard
          .evaluate(
            startedAt: start,
            now: continuedAt.add(const Duration(minutes: 19)),
          )
          .event,
      SessionGuardEvent.none,
    );
    expect(
      guard
          .evaluate(
            startedAt: start,
            now: continuedAt.add(const Duration(minutes: 20)),
          )
          .event,
      SessionGuardEvent.stationaryWarning,
    );
  });

  test('uses receipt time instead of a stale platform timestamp', () {
    final guard = SessionGuard();
    guard.observe(
      sample(at: start.subtract(const Duration(hours: 1))),
      observedAt: start,
    );

    expect(
      guard
          .evaluate(
            startedAt: start,
            now: start.add(const Duration(minutes: 19)),
          )
          .event,
      SessionGuardEvent.none,
    );
    expect(
      guard
          .evaluate(
            startedAt: start,
            now: start.add(const Duration(minutes: 20)),
          )
          .event,
      SessionGuardEvent.stationaryWarning,
    );
  });

  test('anchor accuracy also protects against ordinary GPS drift', () {
    final guard = SessionGuard();
    guard.observe(sample(at: start, accuracyM: 60));
    guard.evaluate(
      startedAt: start,
      now: start.add(const Duration(minutes: 20)),
    );

    final cleared = guard.observe(
      sample(
        at: start.add(const Duration(minutes: 21)),
        latitude: 37.56695,
        accuracyM: 5,
      ),
    );

    expect(cleared, isFalse);
    expect(
      guard
          .evaluate(
            startedAt: start,
            now: start.add(const Duration(minutes: 30)),
          )
          .event,
      SessionGuardEvent.stationaryLimit,
    );
  });

  test('warns at 2h45 and limits every session at 3h', () {
    final guard = SessionGuard();

    final warning = guard.evaluate(
      startedAt: start,
      now: start.add(const Duration(hours: 2, minutes: 45)),
    );
    expect(warning.event, SessionGuardEvent.durationWarning);
    expect(warning.remaining, const Duration(minutes: 15));

    expect(
      guard
          .evaluate(startedAt: start, now: start.add(const Duration(hours: 3)))
          .event,
      SessionGuardEvent.durationLimit,
    );
  });
}
