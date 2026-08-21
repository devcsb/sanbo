import 'dart:collection';
import 'dart:math' as math;

import '../models/location_sample.dart';
import '../pipeline/geo.dart';

enum SessionGuardEvent {
  none,
  stationaryWarning,
  stationaryLimit,
  durationWarning,
  durationLimit,
  highSpeedWarning,
}

class SessionGuardPolicy {
  const SessionGuardPolicy({
    this.stationaryWarningAfter = const Duration(minutes: 20),
    this.stationaryLimit = const Duration(minutes: 30),
    this.durationWarningAfter = const Duration(hours: 4, minutes: 45),
    this.durationLimit = const Duration(hours: 5),
    this.stationaryRadiusM = 35,
    this.movingSpeedMps = 0.9,
    this.maxUsableAccuracyM = 80,
    this.highSpeedThresholdMps = 8.0,
    this.highSpeedWindow = const Duration(seconds: 120),
    this.highSpeedWarningAfter = const Duration(seconds: 60),
    this.lowSpeedRecoveryMps = 4.0,
    this.lowSpeedRecoveryAfter = const Duration(seconds: 30),
    this.highSpeedMaxAccuracyM = 80,
    this.maxSampleAge = const Duration(seconds: 30),
    this.maxSampleFutureSkew = const Duration(seconds: 5),
  });

  final Duration stationaryWarningAfter;
  final Duration stationaryLimit;
  final Duration durationWarningAfter;
  final Duration durationLimit;
  final double stationaryRadiusM;
  final double movingSpeedMps;
  final double maxUsableAccuracyM;
  final double highSpeedThresholdMps;
  final Duration highSpeedWindow;
  final Duration highSpeedWarningAfter;
  final double lowSpeedRecoveryMps;
  final Duration lowSpeedRecoveryAfter;
  final double highSpeedMaxAccuracyM;
  final Duration maxSampleAge;
  final Duration maxSampleFutureSkew;
}

class SessionGuardDecision {
  const SessionGuardDecision(this.event, {this.remaining});

  static const none = SessionGuardDecision(SessionGuardEvent.none);

  final SessionGuardEvent event;
  final Duration? remaining;
}

class SessionGuardObservation {
  const SessionGuardObservation({
    this.acceptedForHighSpeed = false,
    this.clearedStationaryWarning = false,
  });

  final bool acceptedForHighSpeed;
  final bool clearedStationaryWarning;
}

class _TrustedSpeedSpan {
  const _TrustedSpeedSpan({
    required this.startAt,
    required this.endAt,
    required this.speedMps,
  });

  final DateTime startAt;
  final DateTime endAt;
  final double speedMps;
}

/// Watches one explicitly started walk for forgotten tracking and long stays.
class SessionGuard {
  SessionGuard({this.policy = const SessionGuardPolicy()});

  final SessionGuardPolicy policy;

  final _speedSpans = ListQueue<_TrustedSpeedSpan>();
  LocationSample? _anchor;
  LocationSample? _lastUsableSample;
  LocationSample? _lastHighSpeedSample;
  DateTime? _lastObservedAt;
  DateTime? _stationarySince;
  DateTime? _lowSpeedSince;
  DateTime? _highSpeedPendingAt;
  bool _stationaryWarningIssued = false;
  bool _durationWarningIssued = false;
  bool _highSpeedWarningIssued = false;
  bool _highSpeedPending = false;

  DateTime? get stationarySince => _stationarySince;
  bool get stationaryWarningIssued => _stationaryWarningIssued;
  bool get highSpeedArmed => !_highSpeedWarningIssued;

  void reset() {
    _speedSpans.clear();
    _anchor = null;
    _lastUsableSample = null;
    _lastHighSpeedSample = null;
    _lastObservedAt = null;
    _stationarySince = null;
    _lowSpeedSince = null;
    _highSpeedPendingAt = null;
    _stationaryWarningIssued = false;
    _durationWarningIssued = false;
    _highSpeedWarningIssued = false;
    _highSpeedPending = false;
  }

  /// [observedAt] is the app receipt time, not a possibly cached platform time.
  SessionGuardObservation observe(
    LocationSample sample, {
    required DateTime observedAt,
  }) {
    final receivedAt = observedAt;
    final receivedUtc = receivedAt.toUtc();
    final previousObservedAt = _lastObservedAt;
    if (previousObservedAt != null &&
        receivedUtc.isBefore(previousObservedAt)) {
      _interruptHighSpeedContinuity();
      return const SessionGuardObservation();
    }
    _lastObservedAt = receivedUtc;

    final acceptedForHighSpeed =
        _freshAtReceipt(sample, receivedUtc) && _trustedForHighSpeed(sample);
    if (acceptedForHighSpeed) {
      _observeHighSpeed(sample, receivedUtc);
    } else {
      _interruptHighSpeedContinuity();
    }

    return SessionGuardObservation(
      acceptedForHighSpeed: acceptedForHighSpeed,
      clearedStationaryWarning: _observeStationary(sample, receivedAt),
    );
  }

  void rebuildHighSpeedState({
    required Iterable<LocationSample> samples,
    required DateTime observedAt,
  }) {
    reset();
    final receivedUtc = observedAt.toUtc();
    final windowStart = receivedUtc.subtract(policy.highSpeedWindow);
    final recentSamples =
        samples.where((sample) {
            final timestamp = sample.timestamp.toUtc();
            return !timestamp.isBefore(windowStart) &&
                !timestamp.isAfter(receivedUtc);
          }).toList()
          ..sort((a, b) => a.timestamp.toUtc().compareTo(b.timestamp.toUtc()));
    final lastTrustedIndex = recentSamples.lastIndexWhere(_trustedForHighSpeed);
    if (lastTrustedIndex == -1 ||
        !_freshAtReceipt(recentSamples[lastTrustedIndex], receivedUtc)) {
      return;
    }

    // Recovery receives saved timestamps rather than their original receipt
    // times. Verify the last trusted fix against the real recovery time, then
    // shift every prior receipt time by that same gap so interval durations
    // remain intact without treating a stale trace as fresh.
    final receiptOffset = receivedUtc.difference(
      recentSamples[lastTrustedIndex].timestamp.toUtc(),
    );
    for (final sample in recentSamples.take(lastTrustedIndex + 1)) {
      observe(sample, observedAt: sample.timestamp.toUtc().add(receiptOffset));
    }
  }

  void dismissHighSpeedWarning() {
    _highSpeedPending = false;
    _highSpeedPendingAt = null;
  }

  /// Breaks speed accumulation when the caller rejects a provider fix before
  /// it reaches [observe]. The next trusted fix becomes a fresh anchor.
  void interruptHighSpeedContinuity() {
    _interruptHighSpeedContinuity();
  }

  bool _freshAtReceipt(LocationSample sample, DateTime observedAt) {
    final age = observedAt.difference(sample.timestamp.toUtc());
    return age <= policy.maxSampleAge && age >= -policy.maxSampleFutureSkew;
  }

  bool _trustedForHighSpeed(LocationSample sample) {
    final accuracy = sample.accuracyM;
    return accuracy != null &&
        accuracy.isFinite &&
        accuracy >= 0 &&
        accuracy <= policy.highSpeedMaxAccuracyM &&
        !sample.isFilteredOut &&
        sample.latitude.isFinite &&
        sample.longitude.isFinite &&
        sample.latitude >= -90 &&
        sample.latitude <= 90 &&
        sample.longitude >= -180 &&
        sample.longitude <= 180;
  }

  void _observeHighSpeed(LocationSample sample, DateTime observedAt) {
    final previous = _lastHighSpeedSample;
    if (previous == null) {
      _lastHighSpeedSample = sample;
      return;
    }

    final startAt = previous.timestamp.toUtc();
    final endAt = sample.timestamp.toUtc();
    final interval = endAt.difference(startAt);
    if (interval <= Duration.zero || interval > trustedLocationGap) {
      _interruptHighSpeedContinuity();
      return;
    }
    _lastHighSpeedSample = sample;

    final distance = haversineMeters(
      lat1: previous.latitude,
      lon1: previous.longitude,
      lat2: sample.latitude,
      lon2: sample.longitude,
    );
    final speed =
        distance / (interval.inMicroseconds / Duration.microsecondsPerSecond);
    if (!speed.isFinite) {
      _interruptHighSpeedContinuity();
      return;
    }

    _speedSpans.add(
      _TrustedSpeedSpan(startAt: startAt, endAt: endAt, speedMps: speed),
    );
    _trimHighSpeedWindow(observedAt);
    if (!_highSpeedWarningIssued &&
        _highSpeedDuration(observedAt) >= policy.highSpeedWarningAfter) {
      _highSpeedWarningIssued = true;
      _highSpeedPending = true;
      _highSpeedPendingAt = observedAt;
    }
    if (_highSpeedWarningIssued) {
      _updateLowSpeedRecovery(speed, startAt, endAt);
    }
  }

  void _trimHighSpeedWindow(DateTime observedAt) {
    final windowStart = observedAt.subtract(policy.highSpeedWindow);
    while (_speedSpans.isNotEmpty &&
        !_speedSpans.first.endAt.isAfter(windowStart)) {
      _speedSpans.removeFirst();
    }
  }

  Duration _highSpeedDuration(DateTime observedAt) {
    final windowStart = observedAt.subtract(policy.highSpeedWindow);
    var total = Duration.zero;
    for (final span in _speedSpans) {
      // Haversine calculations at an exact geographic threshold can land a
      // few ulps below it, so preserve the inclusive policy boundary.
      if (span.speedMps + 1e-9 < policy.highSpeedThresholdMps) continue;
      final startAt = span.startAt.isAfter(windowStart)
          ? span.startAt
          : windowStart;
      final endAt = span.endAt.isBefore(observedAt) ? span.endAt : observedAt;
      if (endAt.isAfter(startAt)) {
        total += endAt.difference(startAt);
      }
    }
    return total;
  }

  void _updateLowSpeedRecovery(double speed, DateTime startAt, DateTime endAt) {
    if (speed > policy.lowSpeedRecoveryMps) {
      _lowSpeedSince = null;
      return;
    }
    final recoveryStart = _lowSpeedSince ?? startAt;
    _lowSpeedSince = recoveryStart;
    if (endAt.difference(recoveryStart) >= policy.lowSpeedRecoveryAfter) {
      _speedSpans.clear();
      _lowSpeedSince = null;
      _highSpeedWarningIssued = false;
      _highSpeedPending = false;
      _highSpeedPendingAt = null;
    }
  }

  void _interruptHighSpeedContinuity() {
    _speedSpans.clear();
    _lastHighSpeedSample = null;
    _lowSpeedSince = null;
  }

  bool _observeStationary(LocationSample sample, DateTime receivedAt) {
    final accuracy = sample.accuracyM;
    if (accuracy != null &&
        accuracy.isFinite &&
        accuracy > policy.maxUsableAccuracyM) {
      return false;
    }

    final previous = _lastUsableSample;
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
    final segmentSpeed = _segmentSpeedMps(previous, sample);
    final movingAtWalkingSpeed =
        (speed != null && speed.isFinite && speed >= policy.movingSpeedMps) ||
        (segmentSpeed != null && segmentSpeed >= policy.movingSpeedMps);

    if (distance > radius || movingAtWalkingSpeed) {
      final clearedWarning = _stationaryWarningIssued;
      _startStationaryWindow(sample, receivedAt);
      return clearedWarning;
    }
    return false;
  }

  double? _segmentSpeedMps(LocationSample? previous, LocationSample current) {
    if (previous == null) return null;
    final dt = current.timestamp.difference(previous.timestamp);
    if (dt <= Duration.zero || dt > trustedLocationGap) return null;
    final distance = haversineMeters(
      lat1: previous.latitude,
      lon1: previous.longitude,
      lat2: current.latitude,
      lon2: current.longitude,
    );
    return distance / (dt.inMicroseconds / Duration.microsecondsPerSecond);
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

    if (_highSpeedPending &&
        (_highSpeedPendingAt == null || !now.isBefore(_highSpeedPendingAt!))) {
      _highSpeedPending = false;
      _highSpeedPendingAt = null;
      return const SessionGuardDecision(SessionGuardEvent.highSpeedWarning);
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
