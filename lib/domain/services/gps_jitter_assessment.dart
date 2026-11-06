import 'dart:math' as math;

import '../models/location_sample.dart';
import '../pipeline/geo.dart';

/// Advisory only: GPS alone cannot distinguish noise from a real short walk.
/// The caller supplies one continuous, time-ordered minute of included fixes.
bool hasSuspectedGpsJitter(List<LocationSample> samples) {
  if (samples.length < 5 ||
      samples.last.timestamp.difference(samples.first.timestamp) <
          const Duration(seconds: 30)) {
    return false;
  }
  final accuracies = <double>[];
  for (final sample in samples) {
    final accuracy = sample.accuracyM;
    if (sample.isFilteredOut ||
        !sample.latitude.isFinite ||
        !sample.longitude.isFinite ||
        sample.latitude.abs() > 90 ||
        sample.longitude.abs() > 180 ||
        accuracy == null ||
        !accuracy.isFinite ||
        accuracy <= 0 ||
        accuracy > 150) {
      return false;
    }
    final speed = sample.speedMps;
    if (speed != null && speed.isFinite && speed >= 0.5) return false;
    accuracies.add(accuracy);
  }
  accuracies.sort();
  final radius = accuracies[accuracies.length ~/ 2];
  double distance(LocationSample a, LocationSample b) => haversineMeters(
    lat1: a.latitude,
    lon1: a.longitude,
    lat2: b.latitude,
    lon2: b.longitude,
  );
  var path = 0.0;
  var reversals = 0;
  ({double x, double y})? lastDirection;
  for (var i = 1; i < samples.length; i++) {
    final previous = samples[i - 1];
    final current = samples[i];
    final gap = current.timestamp.difference(previous.timestamp);
    if (gap <= Duration.zero || gap > const Duration(seconds: 30)) return false;
    final edge = distance(previous, current);
    if (edge > radius || distance(samples.first, current) > radius) {
      return false;
    }
    if (edge < minMeaningfulSegmentDistanceM) continue;
    path += edge;
    // Normalize the antimeridian before measuring a reversal in the local plane.
    final longitude =
        (current.longitude - previous.longitude + 180) % 360 - 180;
    final direction = (
      x:
          longitude *
          math.cos((current.latitude + previous.latitude) * math.pi / 360),
      y: current.latitude - previous.latitude,
    );
    if (lastDirection case final last?) {
      final dot = last.x * direction.x + last.y * direction.y;
      final lengths = math.sqrt(
        (last.x * last.x + last.y * last.y) *
            (direction.x * direction.x + direction.y * direction.y),
      );
      if (lengths > 0 && dot / lengths <= -0.5) reversals++;
    }
    lastDirection = direction;
  }
  return path >= 10 &&
      reversals >= 2 &&
      distance(samples.first, samples.last) / path <= 0.25;
}
