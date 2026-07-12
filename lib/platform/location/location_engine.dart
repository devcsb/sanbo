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
  Stream<LocationSample> get samples;
  TrackingMode get mode;
  Future<void> setMode(TrackingMode mode);
  Future<LocationPermissionState> checkPermission();
  Future<LocationPermissionState> requestPermission();
  Future<void> start();
  Future<void> stop();
  Future<void> dispose() async {}
}
