import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/services/live_speed_availability.dart';

void main() {
  test('availability separates waiting, zero speed and stale data', () {
    final t = DateTime.utc(2026, 10, 14);
    LiveSpeedAvailability at(Duration age, {bool evidence = true}) =>
        liveSpeedAvailability(
          lastUsableFixAt: t,
          now: t.add(age),
          hasSpeedEvidence: evidence,
          maxAge: const Duration(seconds: 30),
          maxFutureSkew: const Duration(seconds: 5),
        );
    expect(at(Duration.zero, evidence: false), LiveSpeedAvailability.waiting);
    expect(at(Duration.zero), LiveSpeedAvailability.available);
    expect(at(const Duration(seconds: 30)), LiveSpeedAvailability.available);
    expect(
      at(const Duration(milliseconds: 30001)),
      LiveSpeedAvailability.stale,
    );
    expect(at(const Duration(seconds: -5)), LiveSpeedAvailability.available);
    expect(
      at(const Duration(milliseconds: -5001)),
      LiveSpeedAvailability.stale,
    );
  });
  test('no usable fix is waiting even if a numeric value is retained', () {
    expect(
      liveSpeedAvailability(
        lastUsableFixAt: null,
        now: DateTime.utc(2026, 10, 14),
        hasSpeedEvidence: true,
        maxAge: const Duration(seconds: 30),
        maxFutureSkew: const Duration(seconds: 5),
      ),
      LiveSpeedAvailability.waiting,
    );
  });
}
