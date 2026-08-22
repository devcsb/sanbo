import '../models/location_sample.dart';
import 'geo.dart';

class SampleFilterConfig {
  const SampleFilterConfig({
    /// Horizontal accuracy soft ceiling. Galaxy/urban cold fixes often land
    /// between 80–150 m; hard-dropping them zeroed entire walks.
    this.maxAccuracyM = 150,

    /// Absolute ceiling — beyond this, the fix is useless for a walk path.
    this.hardMaxAccuracyM = 500,
    this.maxJumpSpeedMps = 40,
    this.minTimeDeltaMs = 500,

    /// Below this displacement, treat as GPS jitter (not real movement).
    this.minSegmentDistanceM = 1.5,
  });

  final double maxAccuracyM;
  final double hardMaxAccuracyM;
  final double maxJumpSpeedMps;
  final int minTimeDeltaMs;
  final double minSegmentDistanceM;
}

/// Marks outliers; keeps originals with [LocationSample.isFilteredOut].
///
/// Distance uses only non-filtered samples. Soft accuracy threshold demotes
/// fixes but still allows them when no better anchor exists yet (cold start).
class SampleFilter {
  SampleFilter({this.config = const SampleFilterConfig()});

  final SampleFilterConfig config;

  List<LocationSample> apply(List<LocationSample> raw) {
    if (raw.isEmpty) return const [];
    final sorted = [...raw]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final out = <LocationSample>[];
    LocationSample? lastValid;
    LocationSample? lastJumpRejected;

    for (final s in sorted) {
      // Preserve an explicit boundary decision made by the caller, such as a
      // GPS fix beyond the receipt-time future skew. Re-running the filter
      // must not silently turn that sample back into a route anchor.
      var filtered = s.isFilteredOut;
      var jumpRejected = false;

      // A malformed provider fix must never become the path anchor. Without
      // this guard, NaN coordinates make distance comparisons false and can
      // poison live distance/stationary calculations for the rest of a walk.
      if (!s.latitude.isFinite ||
          !s.longitude.isFinite ||
          s.latitude < -90 ||
          s.latitude > 90 ||
          s.longitude < -180 ||
          s.longitude > 180) {
        filtered = true;
      }

      final acc = s.accuracyM;
      if (!filtered && acc != null && (!acc.isFinite || acc < 0)) {
        filtered = true;
      }
      if (!filtered && acc != null && acc > config.hardMaxAccuracyM) {
        filtered = true;
      } else if (!filtered &&
          acc != null &&
          acc > config.maxAccuracyM &&
          lastValid != null) {
        // Soft reject only once we already have a usable path anchor.
        filtered = true;
      }

      if (!filtered && lastValid != null) {
        final dtMs = s.timestamp.difference(lastValid.timestamp).inMilliseconds;
        if (dtMs < config.minTimeDeltaMs) {
          filtered = true;
        } else if (dtMs > 0) {
          final dist = haversineMeters(
            lat1: lastValid.latitude,
            lon1: lastValid.longitude,
            lat2: s.latitude,
            lon2: s.longitude,
          );
          final speed = dist / (dtMs / 1000.0);
          if (speed > config.maxJumpSpeedMps) {
            filtered = true;
            jumpRejected = true;
          }
        }
      }

      // A cached fix can become the route anchor just before live movement
      // starts. Once a second valid point follows the rejected jump at a
      // plausible speed, start a new route fragment there. A single spike
      // remains filtered because it has no follow-up point to confirm it.
      if (jumpRejected &&
          lastJumpRejected != null &&
          _canFollowRejectedJump(lastJumpRejected, s)) {
        filtered = false;
        jumpRejected = false;
      }

      // Reject exact duplicate coordinates that add no path value when we
      // already have a point (still keep the first fix as the anchor).
      if (!filtered && lastValid != null) {
        final dist = haversineMeters(
          lat1: lastValid.latitude,
          lon1: lastValid.longitude,
          lat2: s.latitude,
          lon2: s.longitude,
        );
        // Keep the sample for map density, but tiny jitter is handled in
        // distance via pathDistanceMeters itself; no filter here.
        if (dist.isNaN) filtered = true;
      }

      final marked = s.copyWith(isFilteredOut: filtered);
      out.add(marked);
      if (jumpRejected) {
        lastJumpRejected = s;
      } else if (!filtered) {
        lastValid = marked;
        lastJumpRejected = null;
      } else {
        lastJumpRejected = null;
      }
    }
    return out;
  }

  bool _canFollowRejectedJump(LocationSample previous, LocationSample current) {
    if (!_validFix(previous) || !_validFix(current)) return false;
    final dtMs = current.timestamp
        .difference(previous.timestamp)
        .inMilliseconds;
    if (dtMs < config.minTimeDeltaMs ||
        dtMs > trustedLocationGap.inMilliseconds) {
      return false;
    }
    final distance = haversineMeters(
      lat1: previous.latitude,
      lon1: previous.longitude,
      lat2: current.latitude,
      lon2: current.longitude,
    );
    final speed = distance / (dtMs / 1000.0);
    return distance >= config.minSegmentDistanceM &&
        speed.isFinite &&
        speed <= config.maxJumpSpeedMps;
  }

  bool _validFix(LocationSample sample) {
    final accuracy = sample.accuracyM;
    return sample.latitude.isFinite &&
        sample.longitude.isFinite &&
        sample.latitude >= -90 &&
        sample.latitude <= 90 &&
        sample.longitude >= -180 &&
        sample.longitude <= 180 &&
        (accuracy == null ||
            (accuracy.isFinite &&
                accuracy >= 0 &&
                accuracy <= config.hardMaxAccuracyM));
  }
}
