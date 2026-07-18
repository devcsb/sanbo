import '../../domain/models/location_sample.dart';
import '../../domain/models/tracking_mode.dart';

enum LocationPermissionState {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
  unknown,
}

/// Platform location adapter (TRD LocationEngine).
abstract class LocationEngine {
  /// Live sample stream. Must be listenable **before** [start] so no fix is lost.
  Stream<LocationSample> get samples;
  TrackingMode get mode;
  Future<void> setMode(TrackingMode mode);
  Future<LocationPermissionState> checkPermission();
  Future<LocationPermissionState> requestPermission();

  /// Opens OS app/location settings when permission is permanently denied.
  Future<bool> openSystemSettings() async => false;

  Future<void> start();
  Future<void> stop();
  Future<void> dispose() async {}
}
