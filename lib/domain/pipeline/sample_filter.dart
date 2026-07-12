import '../models/location_sample.dart';
import 'geo.dart';

class SampleFilterConfig {
  const SampleFilterConfig({
    this.maxAccuracyM = 80,
    this.maxJumpSpeedMps = 40,
    this.minTimeDeltaMs = 500,
  });

  final double maxAccuracyM;
  final double maxJumpSpeedMps;
  final int minTimeDeltaMs;
}

/// Marks outliers; keeps originals with [LocationSample.isFilteredOut].
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
      if (acc != null && acc > config.maxAccuracyM) {
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

      final marked = s.copyWith(isFilteredOut: filtered);
      out.add(marked);
      if (!filtered) lastValid = marked;
    }
    return out;
  }
}
