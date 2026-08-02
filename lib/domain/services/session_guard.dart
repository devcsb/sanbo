import 'dart:math' as math;

import '../models/location_sample.dart';
import '../pipeline/geo.dart';

enum SessionGuardEvent {
  none,
  stationaryWarning,
  stationaryLimit,
  durationWarning,
  durationLimit,
}

class SessionGuardPolicy {
  const SessionGuardPolicy({
    this.stationaryWarningAfter = const Duration(minutes: 20),
    this.stationaryLimit = const Duration(minutes: 30),
    this.durationWarningAfter = const Duration(hours: 2, minutes: 45),
    this.durationLimit = const Duration(hours: 3),
    this.stationaryRadiusM = 35,
    this.movingSpeedMps = 0.9,
    this.maxUsableAccuracyM = 80,
  });

  final Duration stationaryWarningAfter;
  final Duration stationaryLimit;
  final Duration durationWarningAfter;
  final Duration durationLimit;
  final double stationaryRadiusM;
  final double movingSpeedMps;
  final double maxUsableAccuracyM;
}

class SessionGuardDecision {
  const SessionGuardDecision(this.event, {this.remaining});

  static const none = SessionGuardDecision(SessionGuardEvent.none);

  final SessionGuardEvent event;
  final Duration? remaining;
}

/// Watches one explicitly started walk for forgotten tracking and long stays.
///
/// A generous, accuracy-aware radius avoids treating ordinary GPS drift as
/// movement. A reliable walking speed immediately resets the stationary clock,
/// which also protects people walking small loops in a park.
class SessionGuard {
  SessionGuard({this.policy = const SessionGuardPolicy()});

  final SessionGuardPolicy policy;

  LocationSample? _anchor;
  LocationSample? _lastUsableSample;
  DateTime? _stationarySince;
  bool _stationaryWarningIssued = false;
  bool _durationWarningIssued = false;

  DateTime? get stationarySince => _stationarySince;
  bool get stationaryWarningIssued => _stationaryWarningIssued;

  void reset() {
    _anchor = null;
    _lastUsableSample = null;
    _stationarySince = null;
    _stationaryWarningIssued = false;
    _durationWarningIssued = false;
  }

  /// Returns true when meaningful movement clears an outstanding stay warning.
  ///
  /// [observedAt] is the app's receipt time. Platform location timestamps can
  /// occasionally be cached or delayed, so safety timers must not be anchored
  /// to them. Domain-only callers may omit it to use the sample timestamp.
  bool observe(LocationSample sample, {DateTime? observedAt}) {
    final receivedAt = observedAt ?? sample.timestamp;
    final accuracy = sample.accuracyM;
    if (accuracy != null &&
        accuracy.isFinite &&
        accuracy > policy.maxUsableAccuracyM) {
      return false;
    }

    _lastUsableSample = sample;
    final anchor = _anchor;
    if (anchor == null) {
      _startStationaryWindow(sample, receivedAt);
      return false;
    }

    final radius = math.max(
      policy.stationaryRadiusM,
      math.max(_accuracyRadius(anchor.accuracyM), _accuracyRadius(accuracy)),
    );
    final distance = haversineMeters(
      lat1: anchor.latitude,
      lon1: anchor.longitude,
      lat2: sample.latitude,
      lon2: sample.longitude,
    );
    final speed = sample.speedMps;
    final movingAtWalkingSpeed =
        speed != null && speed.isFinite && speed >= policy.movingSpeedMps;

    if (distance > radius || movingAtWalkingSpeed) {
      final clearedWarning = _stationaryWarningIssued;
      _startStationaryWindow(sample, receivedAt);
      return clearedWarning;
    }
    return false;
  }

  SessionGuardDecision evaluate({
    required DateTime startedAt,
    required DateTime now,
  }) {
    final sessionAge = _nonNegative(now.difference(startedAt));
    if (sessionAge >= policy.durationLimit) {
      return const SessionGuardDecision(SessionGuardEvent.durationLimit);
    }

    final stationarySince = _stationarySince;
    if (stationarySince != null) {
      final stationaryAge = _nonNegative(now.difference(stationarySince));
      if (stationaryAge >= policy.stationaryLimit) {
        return const SessionGuardDecision(SessionGuardEvent.stationaryLimit);
      }
    }

    if (!_durationWarningIssued && sessionAge >= policy.durationWarningAfter) {
      _durationWarningIssued = true;
      return SessionGuardDecision(
        SessionGuardEvent.durationWarning,
        remaining: policy.durationLimit - sessionAge,
      );
    }

    if (stationarySince != null && !_stationaryWarningIssued) {
      final stationaryAge = _nonNegative(now.difference(stationarySince));
      if (stationaryAge >= policy.stationaryWarningAfter) {
        _stationaryWarningIssued = true;
        return SessionGuardDecision(
          SessionGuardEvent.stationaryWarning,
          remaining: policy.stationaryLimit - stationaryAge,
        );
      }
    }

    return SessionGuardDecision.none;
  }

  /// User explicitly chose to keep recording while staying in the same place.
  void continueStationaryTracking(DateTime now) {
    final last = _lastUsableSample;
    if (last != null) {
      _anchor = last;
    }
    _stationarySince = now;
    _stationaryWarningIssued = false;
  }

  void _startStationaryWindow(LocationSample sample, DateTime at) {
    _anchor = sample;
    _stationarySince = at;
    _stationaryWarningIssued = false;
  }

  double _accuracyRadius(double? accuracyM) {
    if (accuracyM == null || !accuracyM.isFinite || accuracyM < 0) {
      return 0;
    }
    return accuracyM * 1.5;
  }

  Duration _nonNegative(Duration value) =>
      value.isNegative ? Duration.zero : value;
}
