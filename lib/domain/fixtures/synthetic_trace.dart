import '../models/location_sample.dart';
import '../pipeline/geo.dart';

/// Builds a synthetic walk trace near Seoul for tests and e2e.
///
/// Points move north ~1.2 m/s over [duration] so distance and speed are non-zero.
List<LocationSample> buildWalkTrace({
  required DateTime start,
  Duration duration = const Duration(minutes: 3),
  double startLat = 37.5665,
  double startLon = 126.9780,
  double speedMps = 1.2,
  double accuracyM = 6,
  Duration step = const Duration(seconds: 4),
}) {
  final samples = <LocationSample>[];
  final steps = duration.inMilliseconds ~/ step.inMilliseconds;
  // Approx degrees lat per meter.
  const degPerMeter = 1 / 111320.0;
  for (var i = 0; i <= steps; i++) {
    final t = start.add(step * i);
    final dist = speedMps * step.inSeconds * i;
    samples.add(
      LocationSample(
        timestamp: t,
        latitude: startLat + dist * degPerMeter,
        longitude: startLon,
        accuracyM: accuracyM,
        speedMps: speedMps,
      ),
    );
  }
  return samples;
}

/// Expected path distance for [buildWalkTrace] (uses same Haversine as production).
double expectedTraceDistanceM(List<LocationSample> samples) {
  return pathDistanceMeters(
    samples.map((s) => (lat: s.latitude, lon: s.longitude)),
  );
}
