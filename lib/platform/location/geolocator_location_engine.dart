import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../domain/models/location_sample.dart';
import '../../domain/models/tracking_mode.dart';
import 'location_engine.dart';
import 'location_request_policy.dart';

/// Production Android/iOS location via geolocator + FGS notification on Android.
///
/// Real-device failure modes this implementation defends against:
/// - Android 13+ notification permission controls drawer visibility for the FGS
/// - Broadcast stream without a listener drops seed / first fixes
/// - Samsung Fused Location can hang; we fall back to LocationManager
/// - Silent catch of permission/stream errors left the UI stuck at 0 samples
class GeolocatorLocationEngine implements LocationEngine {
  GeolocatorLocationEngine() {
    _controller = StreamController<LocationSample>.broadcast();
  }

  TrackingMode _mode = TrackingMode.balanced;
  late final StreamController<LocationSample> _controller;
  StreamSubscription<Position>? _sub;
  bool _running = false;
  bool _usingLocationManagerFallback = false;
  Timer? _stallWatchdog;
  int _emitCount = 0;

  static const _logName = 'sanbo.location';

  @override
  Stream<LocationSample> get samples => _controller.stream;

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
    // A second request helps when the first dialog only granted approximate
    // location on Android 12+ (user can still refuse precise).
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    final mapped = _mapPermission(p);
    // Ask only after the location purpose has been accepted. Notification
    // denial is non-fatal; GPS recording can still continue.
    if (mapped == LocationPermissionState.granted && Platform.isAndroid) {
      await _requestNotificationPermission();
    }
    return mapped;
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final status = await ph.Permission.notification.status;
      if (status.isGranted || status.isLimited) return;
      if (status.isPermanentlyDenied) {
        developer.log(
          'Notification permission permanently denied — FGS may fail on API 33+',
          name: _logName,
        );
        return;
      }
      final result = await ph.Permission.notification.request();
      developer.log('Notification permission: $result', name: _logName);
    } catch (e, st) {
      developer.log(
        'Notification permission request failed',
        name: _logName,
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  Future<bool> openSystemSettings() async {
    final service = await Geolocator.isLocationServiceEnabled();
    if (!service) {
      return Geolocator.openLocationSettings();
    }
    return Geolocator.openAppSettings();
  }

  LocationPermissionState _mapPermission(LocationPermission p) {
    return switch (p) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationPermissionState.granted,
      LocationPermission.denied => LocationPermissionState.denied,
      LocationPermission.deniedForever => LocationPermissionState.deniedForever,
      LocationPermission.unableToDetermine => LocationPermissionState.unknown,
    };
  }

  LocationRequestProfile get _profile => locationRequestProfile(_mode);

  LocationAccuracy get _accuracy => _profile.accuracy;

  Duration get _interval => _profile.interval;

  int get _distanceFilterM => _profile.distanceFilterM;

  bool get _keepCpuAwake => _profile.keepCpuAwake;

  @override
  Future<void> start() async {
    await _stopTrackingOnly();
    _running = true;
    _usingLocationManagerFallback = false;
    _emitCount = 0;

    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      final error = StateError('location_permission_denied');
      _controller.addError(error, StackTrace.current);
      _running = false;
      throw error;
    }

    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      final error = StateError('location_service_disabled');
      _controller.addError(error, StackTrace.current);
      _running = false;
      throw error;
    }

    try {
      await _startStream(forceLocationManager: false);
    } catch (e, st) {
      developer.log(
        'Fused location stream failed, retrying LocationManager',
        name: _logName,
        error: e,
        stackTrace: st,
      );
      try {
        await _startStream(forceLocationManager: true);
        _usingLocationManagerFallback = true;
      } catch (e2, st2) {
        developer.log(
          'LocationManager stream also failed',
          name: _logName,
          error: e2,
          stackTrace: st2,
        );
        if (!_controller.isClosed) {
          _controller.addError(e2, st2);
        }
        await _stopTrackingOnly();
        Error.throwWithStackTrace(e2, st2);
      }
    }

    // Seed after stream is armed. Listener is expected to already be attached
    // by SessionController (listen → then start).
    unawaited(_emitCurrentPosition(retries: 3));
    _armStallWatchdog();
  }

  Future<void> _startStream({required bool forceLocationManager}) async {
    await _sub?.cancel();
    _sub = null;

    final LocationSettings locationSettings;
    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: _accuracy,
        distanceFilter: _distanceFilterM,
        intervalDuration: _interval,
        forceLocationManager: forceLocationManager,
        // timeLimit on stream is not used — we use our own stall watchdog.
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: '산보',
          notificationText: '산책 경로를 기록하고 있어요',
          notificationChannelName: '산보 위치 기록',
          enableWakeLock: _keepCpuAwake,
          setOngoing: true,
        ),
      );
    } else if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: _accuracy,
        distanceFilter: _distanceFilterM,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      locationSettings = LocationSettings(
        accuracy: _accuracy,
        distanceFilter: _distanceFilterM,
      );
    }

    final stream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    );
    // Attach immediately so the first native fix is not dropped.
    final ready = Completer<void>();
    _sub = stream.listen(
      (pos) {
        if (!ready.isCompleted) ready.complete();
        _emitPosition(pos);
      },
      onError: (Object e, StackTrace st) {
        developer.log(
          'Position stream error',
          name: _logName,
          error: e,
          stackTrace: st,
        );
        if (!ready.isCompleted) {
          ready.completeError(e, st);
        }
        if (!_controller.isClosed) {
          _controller.addError(e, st);
        }
      },
      onDone: () {
        developer.log('Position stream done', name: _logName);
      },
      cancelOnError: false,
    );

    // Wait briefly for subscription to be accepted by the platform channel.
    // If it errors immediately (e.g. missing notification / FGS), surface it.
    try {
      await ready.future.timeout(const Duration(milliseconds: 400));
    } on TimeoutException {
      // No fix yet is normal; subscription itself is fine.
    }
  }

  void _armStallWatchdog() {
    _stallWatchdog?.cancel();
    // If nothing arrives in 12s, try LocationManager fallback once.
    _stallWatchdog = Timer(const Duration(seconds: 12), () async {
      if (!_running || _emitCount > 0 || _usingLocationManagerFallback) return;
      if (!Platform.isAndroid) return;
      developer.log(
        'No GPS fix in 12s — switching to LocationManager fallback',
        name: _logName,
      );
      try {
        await _startStream(forceLocationManager: true);
        _usingLocationManagerFallback = true;
        unawaited(_emitCurrentPosition(retries: 2, forceLocationManager: true));
      } catch (e, st) {
        developer.log(
          'Fallback stream failed',
          name: _logName,
          error: e,
          stackTrace: st,
        );
        if (!_controller.isClosed) {
          _controller.addError(StateError('location_timeout_no_fix'), st);
        }
      }
    });
  }

  LocationSettings _oneShotSettings({
    required bool forceLocationManager,
    required Duration timeLimit,
  }) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: _accuracy,
        distanceFilter: _distanceFilterM,
        intervalDuration: _interval,
        forceLocationManager: forceLocationManager,
        timeLimit: timeLimit,
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: _accuracy,
        distanceFilter: _distanceFilterM,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
        timeLimit: timeLimit,
      );
    }
    return LocationSettings(
      accuracy: _accuracy,
      distanceFilter: _distanceFilterM,
      timeLimit: timeLimit,
    );
  }

  Future<void> _emitCurrentPosition({
    int retries = 1,
    bool forceLocationManager = false,
  }) async {
    for (var attempt = 0; attempt < retries; attempt++) {
      if (!_running) return;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: _oneShotSettings(
            forceLocationManager: forceLocationManager,
            timeLimit: Duration(seconds: 8 + attempt * 4),
          ),
        );
        if (!_running) return;
        _emitPosition(pos);
        return;
      } catch (e, st) {
        developer.log(
          'getCurrentPosition attempt ${attempt + 1}/$retries failed',
          name: _logName,
          error: e,
          stackTrace: st,
        );
        if (attempt + 1 < retries) {
          await Future<void>.delayed(
            Duration(milliseconds: 600 * (attempt + 1)),
          );
        }
      }
    }
  }

  void _emitPosition(Position pos) {
    if (!_running || _controller.isClosed) return;
    // Geolocator Position.timestamp is UTC (fromMap isUtc:true). Normalize to
    // local wall-clock so minute windows match session.startedAt (DateTime.now()).
    final ts = pos.timestamp.isUtc ? pos.timestamp.toLocal() : pos.timestamp;
    final accuracy = pos.accuracy.isFinite && pos.accuracy >= 0
        ? pos.accuracy
        : null;
    final speed = pos.speed.isFinite && pos.speed >= 0 ? pos.speed : null;
    final altitude = pos.altitude.isFinite ? pos.altitude : null;
    _emitCount++;
    if (kDebugMode && _emitCount <= 3) {
      developer.log(
        'fix #$_emitCount lat=${pos.latitude.toStringAsFixed(5)} '
        'lon=${pos.longitude.toStringAsFixed(5)} acc=$accuracy',
        name: _logName,
      );
    }
    _controller.add(
      LocationSample(
        timestamp: ts,
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyM: accuracy,
        speedMps: speed,
        altitudeM: altitude,
      ),
    );
  }

  Future<void> _stopTrackingOnly() async {
    _stallWatchdog?.cancel();
    _stallWatchdog = null;
    _running = false;
    await _sub?.cancel();
    _sub = null;
  }

  @override
  Future<void> stop() async {
    await _stopTrackingOnly();
    // Keep the broadcast controller open so callers can re-listen across sessions.
  }

  @override
  Future<void> dispose() async {
    await _stopTrackingOnly();
    await _controller.close();
  }
}
