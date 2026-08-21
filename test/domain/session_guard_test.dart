import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/pipeline/geo.dart';
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

  LocationSample movingFix(
    DateTime at,
    double meters, {
    double accuracy = 5,
    double? providerSpeed,
    bool isFilteredOut = false,
  }) {
    return LocationSample(
      timestamp: at,
      latitude: 37.5665,
      longitude:
          126.9780 +
          meters /
              (6371000 * math.cos(37.5665 * math.pi / 180)) *
              180 /
              math.pi,
      accuracyM: accuracy,
      speedMps: providerSpeed,
      isFilteredOut: isFilteredOut,
    );
  }

  SessionGuard warnedGuard(DateTime at) {
    final guard = SessionGuard();
    guard.observe(movingFix(at, 0), observedAt: at);
    for (var second = 10; second <= 60; second += 10) {
      final now = at.add(Duration(seconds: second));
      guard.observe(movingFix(now, second * 8.0), observedAt: now);
    }
    expect(
      guard
          .evaluate(startedAt: at, now: at.add(const Duration(seconds: 60)))
          .event,
      SessionGuardEvent.highSpeedWarning,
    );
    return guard;
  }

  test('warns after 20 stationary minutes and limits at 30 minutes', () {
    final guard = SessionGuard();
    guard.observe(sample(at: start), observedAt: start);

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
      guard.observe(sample(at: start), observedAt: start);
      guard.evaluate(
        startedAt: start,
        now: start.add(const Duration(minutes: 20)),
      );

      final movedAt = start.add(const Duration(minutes: 21));
      final cleared = guard.observe(
        sample(at: movedAt, latitude: 37.5670, speedMps: 1.2),
        observedAt: movedAt,
      );
      expect(cleared.clearedStationaryWarning, isTrue);
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
    guard.observe(sample(at: start), observedAt: start);
    guard.evaluate(
      startedAt: start,
      now: start.add(const Duration(minutes: 20)),
    );

    // Keep an adjacent fix so the controller can derive speed from GPS
    // displacement even though Android reports speed=0.0.
    guard.observe(
      sample(at: start.add(const Duration(minutes: 20))),
      observedAt: start.add(const Duration(minutes: 20)),
    );
    final cleared = guard.observe(
      sample(
        at: start.add(const Duration(minutes: 20, seconds: 8)),
        latitude: 37.566608,
      ),
      observedAt: start.add(const Duration(minutes: 20, seconds: 8)),
    );

    expect(cleared.clearedStationaryWarning, isTrue);
  });

  test('continue action gives a fresh 20-minute stationary window', () {
    final guard = SessionGuard();
    guard.observe(sample(at: start), observedAt: start);
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
    guard.observe(sample(at: start, accuracyM: 60), observedAt: start);
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
      observedAt: start.add(const Duration(minutes: 21)),
    );

    expect(cleared.clearedStationaryWarning, isFalse);
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

  test('warns at 4h45 and limits every session at 5h', () {
    final guard = SessionGuard();

    final warning = guard.evaluate(
      startedAt: start,
      now: start.add(const Duration(hours: 4, minutes: 45)),
    );
    expect(warning.event, SessionGuardEvent.durationWarning);
    expect(warning.remaining, const Duration(minutes: 15));

    expect(
      guard
          .evaluate(startedAt: start, now: start.add(const Duration(hours: 5)))
          .event,
      SessionGuardEvent.durationLimit,
    );
  });

  test(
    'warns once at sixty accumulated high-speed seconds in a two-minute window',
    () {
      final guard = SessionGuard();
      guard.observe(movingFix(start, 0), observedAt: start);
      for (var second = 10; second <= 60; second += 10) {
        final now = start.add(Duration(seconds: second));
        guard.observe(movingFix(now, second * 8.0), observedAt: now);
      }

      expect(
        guard
            .evaluate(
              startedAt: start,
              now: start.add(const Duration(seconds: 59)),
            )
            .event,
        SessionGuardEvent.none,
      );
      expect(
        guard
            .evaluate(
              startedAt: start,
              now: start.add(const Duration(seconds: 60)),
            )
            .event,
        SessionGuardEvent.highSpeedWarning,
      );
      expect(
        guard
            .evaluate(
              startedAt: start,
              now: start.add(const Duration(seconds: 70)),
            )
            .event,
        SessionGuardEvent.none,
      );
    },
  );

  test(
    'uses overlap with observedAt window and rejects stale bundled fixes',
    () {
      final guard = SessionGuard();
      final received = start.add(const Duration(minutes: 10));
      for (var second = 0; second <= 90; second += 10) {
        guard.observe(
          movingFix(start.add(Duration(seconds: second)), second * 10),
          observedAt: received.add(Duration(milliseconds: second)),
        );
      }

      expect(
        guard.evaluate(startedAt: start, now: received).event,
        SessionGuardEvent.none,
      );
    },
  );

  test('provider speed cannot create a high-speed warning', () {
    final guard = SessionGuard();
    for (var second = 0; second <= 70; second += 10) {
      final now = start.add(Duration(seconds: second));
      guard.observe(movingFix(now, 0, providerSpeed: 40), observedAt: now);
    }

    expect(
      guard
          .evaluate(
            startedAt: start,
            now: start.add(const Duration(seconds: 70)),
          )
          .event,
      SessionGuardEvent.none,
    );
  });

  test('uses exactly eight meters per second but not 7.99', () {
    final under = SessionGuard();
    under.observe(movingFix(start, 0), observedAt: start);
    for (var second = 10; second <= 70; second += 10) {
      final now = start.add(Duration(seconds: second));
      under.observe(movingFix(now, second * 7.99), observedAt: now);
    }
    expect(
      under
          .evaluate(
            startedAt: start,
            now: start.add(const Duration(seconds: 70)),
          )
          .event,
      SessionGuardEvent.none,
    );

    final exact = SessionGuard();
    exact.observe(movingFix(start, 0), observedAt: start);
    for (var second = 10; second <= 60; second += 10) {
      final now = start.add(Duration(seconds: second));
      exact.observe(movingFix(now, second * 8.0), observedAt: now);
    }
    expect(
      exact
          .evaluate(
            startedAt: start,
            now: start.add(const Duration(seconds: 60)),
          )
          .event,
      SessionGuardEvent.highSpeedWarning,
    );
  });

  test(
    'accumulates separate high-speed spans and trims partial window overlap',
    () {
      final guard = SessionGuard(
        policy: const SessionGuardPolicy(
          highSpeedWindow: Duration(seconds: 120),
          highSpeedWarningAfter: Duration(seconds: 60),
        ),
      );
      guard.observe(movingFix(start, 0), observedAt: start);
      guard.observe(
        movingFix(start.add(const Duration(seconds: 40)), 320),
        observedAt: start.add(const Duration(seconds: 40)),
      );
      guard.observe(
        movingFix(start.add(const Duration(seconds: 50)), 320),
        observedAt: start.add(const Duration(seconds: 50)),
      );
      guard.observe(
        movingFix(start.add(const Duration(seconds: 70)), 480),
        observedAt: start.add(const Duration(seconds: 70)),
      );
      guard.observe(
        movingFix(start.add(const Duration(seconds: 190)), 1440),
        observedAt: start.add(const Duration(seconds: 190)),
      );

      expect(
        guard
            .evaluate(
              startedAt: start,
              now: start.add(const Duration(seconds: 190)),
            )
            .event,
        SessionGuardEvent.highSpeedWarning,
      );

      final partial = SessionGuard(
        policy: const SessionGuardPolicy(
          highSpeedWarningAfter: Duration(seconds: 90),
        ),
      );
      partial.observe(movingFix(start, 0), observedAt: start);
      partial.observe(
        movingFix(start.add(const Duration(seconds: 80)), 640),
        observedAt: start.add(const Duration(seconds: 80)),
      );
      partial.observe(
        movingFix(start.add(const Duration(seconds: 160)), 640),
        observedAt: start.add(const Duration(seconds: 160)),
      );
      partial.observe(
        movingFix(start.add(const Duration(seconds: 170)), 720),
        observedAt: start.add(const Duration(seconds: 170)),
      );
      expect(
        partial
            .evaluate(
              startedAt: start,
              now: start.add(const Duration(seconds: 170)),
            )
            .event,
        SessionGuardEvent.none,
      );
    },
  );

  test(
    'rejects untrusted, invalid, out-of-order, zero, and gapped high-speed samples',
    () {
      final guard = SessionGuard();
      guard.observe(movingFix(start, 0), observedAt: start);
      guard.observe(
        movingFix(start.add(const Duration(seconds: 10)), 80, accuracy: 81),
        observedAt: start.add(const Duration(seconds: 10)),
      );
      guard.observe(
        movingFix(
          start.add(const Duration(seconds: 20)),
          160,
          isFilteredOut: true,
        ),
        observedAt: start.add(const Duration(seconds: 20)),
      );
      guard.observe(
        movingFix(start.add(const Duration(seconds: 30)), 240),
        observedAt: start.add(const Duration(seconds: 30)),
      );
      guard.observe(
        movingFix(start.add(const Duration(seconds: 25)), 280),
        observedAt: start.add(const Duration(seconds: 31)),
      );
      guard.observe(
        movingFix(start.add(const Duration(seconds: 30)), 320),
        observedAt: start.add(const Duration(seconds: 32)),
      );
      guard.observe(
        movingFix(start.add(const Duration(seconds: 90, milliseconds: 1)), 800),
        observedAt: start.add(const Duration(seconds: 90, milliseconds: 1)),
      );

      expect(
        guard
            .evaluate(
              startedAt: start,
              now: start.add(const Duration(seconds: 91)),
            )
            .event,
        SessionGuardEvent.none,
      );
    },
  );

  test(
    'rejects future fixes and observedAt regressions for high-speed state',
    () {
      final guard = SessionGuard();
      guard.observe(movingFix(start, 0), observedAt: start);
      guard.observe(
        movingFix(start.add(const Duration(seconds: 16)), 128),
        observedAt: start.add(const Duration(seconds: 10)),
      );
      guard.observe(
        movingFix(start.add(const Duration(seconds: 20)), 160),
        observedAt: start.add(const Duration(seconds: 20)),
      );
      guard.observe(
        movingFix(start.add(const Duration(seconds: 30)), 240),
        observedAt: start.add(const Duration(seconds: 19)),
      );

      expect(
        guard
            .evaluate(
              startedAt: start,
              now: start.add(const Duration(seconds: 30)),
            )
            .event,
        SessionGuardEvent.none,
      );
    },
  );

  test('thirty continuous low-speed seconds rearms but twenty-nine do not', () {
    final guard = warnedGuard(start);
    guard.dismissHighSpeedWarning();
    guard.observe(
      movingFix(start.add(const Duration(seconds: 70)), 560),
      observedAt: start.add(const Duration(seconds: 70)),
    );
    guard.observe(
      movingFix(start.add(const Duration(seconds: 99)), 589),
      observedAt: start.add(const Duration(seconds: 99)),
    );
    expect(guard.highSpeedArmed, isFalse);
    guard.observe(
      movingFix(start.add(const Duration(seconds: 100)), 590),
      observedAt: start.add(const Duration(seconds: 100)),
    );
    expect(guard.highSpeedArmed, isTrue);
  });

  test('medium-speed and GPS gaps reset low-speed recovery', () {
    final guard = warnedGuard(start);
    guard.observe(
      movingFix(start.add(const Duration(seconds: 70)), 560),
      observedAt: start.add(const Duration(seconds: 70)),
    );
    guard.observe(
      movingFix(start.add(const Duration(seconds: 90)), 580),
      observedAt: start.add(const Duration(seconds: 90)),
    );
    guard.observe(
      movingFix(start.add(const Duration(seconds: 100)), 630),
      observedAt: start.add(const Duration(seconds: 100)),
    );
    guard.observe(
      movingFix(start.add(const Duration(seconds: 129)), 659),
      observedAt: start.add(const Duration(seconds: 129)),
    );
    expect(guard.highSpeedArmed, isFalse);

    final gapped = warnedGuard(start);
    gapped.observe(
      movingFix(start.add(const Duration(seconds: 70)), 560),
      observedAt: start.add(const Duration(seconds: 70)),
    );
    gapped.observe(
      movingFix(start.add(const Duration(seconds: 90)), 580),
      observedAt: start.add(const Duration(seconds: 90)),
    );
    gapped.observe(
      movingFix(start.add(const Duration(seconds: 151)), 610),
      observedAt: start.add(const Duration(seconds: 151)),
    );
    expect(gapped.highSpeedArmed, isFalse);
  });

  test('every invalid high-speed input restarts low-speed recovery', () {
    final invalidInputs =
        <
          ({
            String name,
            LocationSample sample,
            DateTime observedAt,
            DateTime nextAt,
          })
        >[
          (
            name: 'stale fix',
            sample: movingFix(start.add(const Duration(seconds: 60)), 480),
            observedAt: start.add(const Duration(seconds: 91)),
            nextAt: start.add(const Duration(seconds: 100)),
          ),
          (
            name: 'future fix',
            sample: movingFix(start.add(const Duration(seconds: 97)), 600),
            observedAt: start.add(const Duration(seconds: 91)),
            nextAt: start.add(const Duration(seconds: 100)),
          ),
          (
            name: 'filtered fix',
            sample: movingFix(
              start.add(const Duration(seconds: 91)),
              581,
              isFilteredOut: true,
            ),
            observedAt: start.add(const Duration(seconds: 91)),
            nextAt: start.add(const Duration(seconds: 100)),
          ),
          (
            name: 'inaccurate fix',
            sample: movingFix(
              start.add(const Duration(seconds: 91)),
              581,
              accuracy: 81,
            ),
            observedAt: start.add(const Duration(seconds: 91)),
            nextAt: start.add(const Duration(seconds: 100)),
          ),
          (
            name: 'invalid coordinate',
            sample: LocationSample(
              timestamp: start.add(const Duration(seconds: 91)),
              latitude: 91,
              longitude: 126.9780,
              accuracyM: 5,
            ),
            observedAt: start.add(const Duration(seconds: 91)),
            nextAt: start.add(const Duration(seconds: 100)),
          ),
          (
            name: 'timestamp regression',
            sample: movingFix(start.add(const Duration(seconds: 85)), 575),
            observedAt: start.add(const Duration(seconds: 91)),
            nextAt: start.add(const Duration(seconds: 100)),
          ),
          (
            name: 'zero interval',
            sample: movingFix(start.add(const Duration(seconds: 90)), 580),
            observedAt: start.add(const Duration(seconds: 91)),
            nextAt: start.add(const Duration(seconds: 100)),
          ),
          (
            name: 'observedAt regression',
            sample: movingFix(start.add(const Duration(seconds: 91)), 581),
            observedAt: start.add(const Duration(seconds: 89)),
            nextAt: start.add(const Duration(seconds: 100)),
          ),
          (
            name: 'untrusted GPS gap',
            sample: movingFix(start.add(const Duration(seconds: 151)), 591),
            observedAt: start.add(const Duration(seconds: 151)),
            nextAt: start.add(const Duration(seconds: 160)),
          ),
        ];

    for (final invalid in invalidInputs) {
      final guard = warnedGuard(start);
      guard.dismissHighSpeedWarning();
      guard.observe(
        movingFix(start.add(const Duration(seconds: 70)), 560),
        observedAt: start.add(const Duration(seconds: 70)),
      );
      guard.observe(
        movingFix(start.add(const Duration(seconds: 90)), 580),
        observedAt: start.add(const Duration(seconds: 90)),
      );
      guard.observe(invalid.sample, observedAt: invalid.observedAt);

      guard.observe(movingFix(invalid.nextAt, 600), observedAt: invalid.nextAt);
      guard.observe(
        movingFix(invalid.nextAt.add(const Duration(seconds: 29)), 629),
        observedAt: invalid.nextAt.add(const Duration(seconds: 29)),
      );
      expect(guard.highSpeedArmed, isFalse, reason: invalid.name);

      guard.observe(
        movingFix(invalid.nextAt.add(const Duration(seconds: 30)), 630),
        observedAt: invalid.nextAt.add(const Duration(seconds: 30)),
      );
      expect(guard.highSpeedArmed, isTrue, reason: invalid.name);
    }
  });

  test('an invalid input discards speed spans on both sides of its gap', () {
    final guard = SessionGuard();
    guard.observe(movingFix(start, 0), observedAt: start);
    guard.observe(
      movingFix(start.add(const Duration(seconds: 30)), 240),
      observedAt: start.add(const Duration(seconds: 30)),
    );
    guard.observe(
      movingFix(
        start.add(const Duration(seconds: 31)),
        248,
        isFilteredOut: true,
      ),
      observedAt: start.add(const Duration(seconds: 31)),
    );
    guard.observe(
      movingFix(start.add(const Duration(seconds: 60)), 480),
      observedAt: start.add(const Duration(seconds: 60)),
    );
    guard.observe(
      movingFix(start.add(const Duration(seconds: 90)), 720),
      observedAt: start.add(const Duration(seconds: 90)),
    );

    expect(
      guard
          .evaluate(
            startedAt: start,
            now: start.add(const Duration(seconds: 90)),
          )
          .event,
      SessionGuardEvent.none,
    );

    guard.observe(
      movingFix(start.add(const Duration(seconds: 120)), 960),
      observedAt: start.add(const Duration(seconds: 120)),
    );
    expect(
      guard
          .evaluate(
            startedAt: start,
            now: start.add(const Duration(seconds: 120)),
          )
          .event,
      SessionGuardEvent.highSpeedWarning,
    );
  });

  test('reset starts a new high-speed warning state machine', () {
    final guard = warnedGuard(start);
    guard.reset();
    expect(guard.highSpeedArmed, isTrue);
    guard.observe(
      movingFix(start.add(const Duration(seconds: 70)), 0),
      observedAt: start.add(const Duration(seconds: 70)),
    );
    expect(
      guard
          .evaluate(
            startedAt: start,
            now: start.add(const Duration(seconds: 70)),
          )
          .event,
      SessionGuardEvent.none,
    );
  });

  test('rebuild uses only fresh recent samples', () {
    final guard = SessionGuard();
    final observedAt = start.add(const Duration(minutes: 10));
    final samples = <LocationSample>[
      for (var second = 0; second <= 60; second += 10)
        movingFix(start.add(Duration(seconds: second)), second * 8.0),
      for (var second = 0; second <= 60; second += 10)
        movingFix(
          observedAt
              .subtract(const Duration(seconds: 30))
              .add(Duration(seconds: second)),
          second * 8.0,
        ),
    ];

    guard.rebuildHighSpeedState(
      samples: samples.reversed,
      observedAt: observedAt,
    );

    expect(
      guard.evaluate(startedAt: start, now: observedAt).event,
      SessionGuardEvent.none,
    );
  });

  test(
    'returns events in duration, stationary, warning, then high-speed priority',
    () {
      final allLimits = SessionGuard(
        policy: const SessionGuardPolicy(
          durationLimit: Duration.zero,
          stationaryLimit: Duration.zero,
          durationWarningAfter: Duration.zero,
          stationaryWarningAfter: Duration.zero,
        ),
      );
      allLimits.observe(movingFix(start, 0), observedAt: start);
      expect(
        allLimits.evaluate(startedAt: start, now: start).event,
        SessionGuardEvent.durationLimit,
      );

      final stationaryLimit = SessionGuard(
        policy: const SessionGuardPolicy(
          durationLimit: Duration(days: 1),
          stationaryLimit: Duration.zero,
          durationWarningAfter: Duration(days: 1),
          stationaryWarningAfter: Duration.zero,
        ),
      );
      stationaryLimit.observe(movingFix(start, 0), observedAt: start);
      expect(
        stationaryLimit.evaluate(startedAt: start, now: start).event,
        SessionGuardEvent.stationaryLimit,
      );

      final deferredHighSpeed = SessionGuard(
        policy: const SessionGuardPolicy(
          durationLimit: Duration(days: 1),
          stationaryLimit: Duration(days: 1),
          durationWarningAfter: Duration.zero,
          stationaryWarningAfter: Duration.zero,
        ),
      );
      deferredHighSpeed.observe(movingFix(start, 0), observedAt: start);
      for (var second = 10; second <= 60; second += 10) {
        final now = start.add(Duration(seconds: second));
        deferredHighSpeed.observe(
          movingFix(now, second * 8.0),
          observedAt: now,
        );
      }
      expect(
        deferredHighSpeed
            .evaluate(
              startedAt: start,
              now: start.add(const Duration(seconds: 60)),
            )
            .event,
        SessionGuardEvent.durationWarning,
      );
      expect(
        deferredHighSpeed
            .evaluate(
              startedAt: start,
              now: start.add(const Duration(seconds: 60)),
            )
            .event,
        SessionGuardEvent.stationaryWarning,
      );
      expect(
        deferredHighSpeed
            .evaluate(
              startedAt: start,
              now: start.add(const Duration(seconds: 60)),
            )
            .event,
        SessionGuardEvent.highSpeedWarning,
      );
    },
  );
}
