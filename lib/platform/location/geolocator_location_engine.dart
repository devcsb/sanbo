import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../domain/models/location_sample.dart';
import '../../domain/models/tracking_mode.dart';
import 'location_engine.dart';

/// Production Android/iOS location via geolocator + FGS notification on Android.
class GeolocatorLocationEngine implements LocationEngine {
  TrackingMode _mode = TrackingMode.balanced;
  StreamController<LocationSample>? _controller;
  StreamSubscription<Position>? _sub;

  @override
  Stream<LocationSample> get samples =>
      _controller?.stream ?? const Stream.empty();

  @override
  TrackingMode get mode => _mode;

  @override
  Future<void> setMode(TrackingMode mode) async {
    _mode = mode;
  }

  @override
  Future<LocationPermissionState> checkPermission() async {
    final service = await Geolocator.isLocationServiceEnabled();
    if (!service) return LocationPermissionState.serviceDisabled;
    final p = await Geolocator.checkPermission();
    return _mapPermission(p);
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    final service = await Geolocator.isLocationServiceEnabled();
    if (!service) return LocationPermissionState.serviceDisabled;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    return _mapPermission(p);
  }

  LocationPermissionState _mapPermission(LocationPermission p) {
    return switch (p) {
      LocationPermission.always || LocationPermission.whileInUse =>
        LocationPermissionState.granted,
      LocationPermission.denied => LocationPermissionState.denied,
      LocationPermission.deniedForever => LocationPermissionState.deniedForever,
      LocationPermission.unableToDetermine => LocationPermissionState.unknown,
    };
  }

  @override
  Future<void> start() async {
    await stop();
    _controller = StreamController<LocationSample>.broadcast();

    final accuracy = switch (_mode) {
      TrackingMode.highAccuracy => LocationAccuracy.best,
      TrackingMode.balanced => LocationAccuracy.high,
      TrackingMode.batterySaver => LocationAccuracy.medium,
    };
    final interval = Duration(seconds: _mode.targetIntervalSeconds);

    final LocationSettings locationSettings = AndroidSettings(
      accuracy: accuracy,
      distanceFilter: 0,
      intervalDuration: interval,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: '산보',
        notificationText: '산책 경로를 기록 중입니다',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    _sub = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen(
      (pos) {
        // Geolocator Position.timestamp is UTC (fromMap isUtc:true). Normalize to
        // local wall-clock so minute windows match session.startedAt (DateTime.now()).
        final ts = pos.timestamp.isUtc
            ? pos.timestamp.toLocal()
            : pos.timestamp;
        _controller?.add(
          LocationSample(
            timestamp: ts,
            latitude: pos.latitude,
            longitude: pos.longitude,
            accuracyM: pos.accuracy,
            speedMps: pos.speed.isNaN || pos.speed < 0 ? null : pos.speed,
            altitudeM: pos.altitude.isNaN ? null : pos.altitude,
          ),
        );
      },
      onError: (Object e, StackTrace st) {
        // Surface as stream error for controller to handle.
        _controller?.addError(e, st);
      },
    );
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _controller?.close();
    _controller = null;
  }

  @override
  Future<void> dispose() => stop();
}
