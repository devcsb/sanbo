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

    for (final s in sorted) {
      var filtered = false;

      final acc = s.accuracyM;
      if (acc != null && acc > config.hardMaxAccuracyM) {
        filtered = true;
      } else if (acc != null &&
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
          }
        }
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
      if (!filtered) lastValid = marked;
    }
    return out;
  }
}
