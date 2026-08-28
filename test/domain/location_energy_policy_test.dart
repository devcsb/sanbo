import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/services/location_energy_policy.dart';

void main() {
  test('low battery never silently changes a mode', () {
    expect(
      LocationEnergyPolicy.suggestedMode(
        current: TrackingMode.highAccuracy,
        batteryPercent: 10,
        userEnabled: false,
      ),
      isNull,
    );
  });

  test('opted-in suggestion lowers one profile', () {
    expect(
      LocationEnergyPolicy.suggestedMode(
        current: TrackingMode.highAccuracy,
        batteryPercent: 10,
        userEnabled: true,
      ),
      TrackingMode.balanced,
    );
    expect(
      LocationEnergyPolicy.suggestedMode(
        current: TrackingMode.balanced,
        batteryPercent: 10,
        userEnabled: true,
      ),
      TrackingMode.batterySaver,
    );
  });

  test(
    'does not suggest when battery is unknown, healthy, or already lowest',
    () {
      for (final percent in <int?>[null, 16, 100]) {
        expect(
          LocationEnergyPolicy.suggestedMode(
            current: TrackingMode.highAccuracy,
            batteryPercent: percent,
            userEnabled: true,
          ),
          isNull,
        );
      }
      expect(
        LocationEnergyPolicy.suggestedMode(
          current: TrackingMode.batterySaver,
          batteryPercent: 10,
          userEnabled: true,
        ),
        isNull,
      );
    },
  );
}
