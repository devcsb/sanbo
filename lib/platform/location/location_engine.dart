import '../../domain/models/location_sample.dart';
import '../../domain/models/tracking_mode.dart';

enum LocationFailureKind {
  permission,
  serviceDisabled,
  notification,
  backgroundLocation,
  timeout,
  streamEnded,
  generic,
}

/// Stable error vocabulary shared by platform adapters and the controller.
/// Native/plugin exceptions are still accepted at the boundary, but UI code
/// no longer has to parse their localized `toString()` output.
final class LocationEngineFailure implements Exception {
  const LocationEngineFailure(this.kind, {this.cause});

  final LocationFailureKind kind;
  final Object? cause;

  @override
  String toString() => 'location_${kind.name}';
}

LocationFailureKind classifyLocationFailure(Object error) {
  if (error is LocationEngineFailure) return error.kind;
  final value = error.toString().toLowerCase();
  if (value.contains('permission')) return LocationFailureKind.permission;
  if (value.contains('service') || value.contains('disabled')) {
    return LocationFailureKind.serviceDisabled;
  }
  if (value.contains('notification')) return LocationFailureKind.notification;
  if (value.contains('foreground')) {
    return LocationFailureKind.backgroundLocation;
  }
  if (value.contains('timeout') || value.contains('no_fix')) {
    return LocationFailureKind.timeout;
  }
  if (value.contains('stream_ended')) return LocationFailureKind.streamEnded;
  return LocationFailureKind.generic;
}

enum LocationPermissionState {
  granted,

  /// Foreground location is available, but iOS Always permission was denied.
  /// Tracking can continue while the app is visible.
  grantedForegroundOnly,
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

  /// Lets a platform engine defer provider restarts until Android allows a
  /// foreground-only location permission again. Implementations that do not
  /// need lifecycle coordination may keep the default no-op.
  Future<void> setAppForeground(bool foreground) async {}

  Future<LocationPermissionState> checkPermission();
  Future<LocationPermissionState> requestPermission();

  /// Opens OS app/location settings when permission is permanently denied.
  Future<bool> openSystemSettings() async => false;

  Future<void> start();
  Future<void> stop();
  Future<void> dispose() async {}
}
