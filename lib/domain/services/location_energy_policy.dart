import '../models/tracking_mode.dart';

/// User-controlled, low-battery guidance for an active recording.
///
/// A suggestion is deliberately one step lower than the current profile. The
/// policy never mutates [TrackingMode] by itself; the presentation layer must
/// show the reason and wait for an explicit confirmation.
abstract final class LocationEnergyPolicy {
  static const lowBatteryThreshold = 15;

  static TrackingMode? suggestedMode({
    required TrackingMode current,
    required int? batteryPercent,
    required bool userEnabled,
  }) {
    if (!userEnabled || batteryPercent == null) return null;
    if (batteryPercent > lowBatteryThreshold) return null;
    return switch (current) {
      TrackingMode.highAccuracy => TrackingMode.balanced,
      TrackingMode.balanced => TrackingMode.batterySaver,
      TrackingMode.batterySaver => null,
    };
  }
}
