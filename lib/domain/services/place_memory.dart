import '../models/activity_label.dart';
import '../models/place_memory.dart';
import '../pipeline/geo.dart';
import '../pipeline/segment_merger.dart';

/// Only meaningful stay-like segments may become reusable place memories.
bool canRememberPlace(ActivitySegment segment) {
  if (segment.sampleCount == 0) return false;
  return switch (segment.label) {
    ActivityLabel.placeStay ||
    ActivityLabel.cafeOrShop ||
    ActivityLabel.parkLinger => true,
    // A single stationary minute is often a traffic light. Require a more
    // deliberate pause before offering place naming.
    ActivityLabel.stationary => segment.durationS >= 120,
    _ => false,
  };
}

/// Sample-weighted centroid of the segment's valid minute windows.
({double latitude, double longitude})? placeCoordinate(
  ActivitySegment segment,
) {
  var latitudeSum = 0.0;
  var longitudeSum = 0.0;
  var weightSum = 0.0;

  for (final window in segment.windows) {
    final latitude = window.centroidLat;
    final longitude = window.centroidLon;
    if (latitude == null || longitude == null) continue;
    final weight = window.sampleCount > 0 ? window.sampleCount.toDouble() : 1.0;
    latitudeSum += latitude * weight;
    longitudeSum += longitude * weight;
    weightSum += weight;
  }

  if (weightSum == 0) return null;
  return (
    latitude: latitudeSum / weightSum,
    longitude: longitudeSum / weightSum,
  );
}

int? segmentPlaceId(ActivitySegment segment) {
  for (final window in segment.windows) {
    if (window.placeId != null) return window.placeId;
  }
  return null;
}

/// Finds a remembered place near a coordinate using only in-memory data.
///
/// Keeping this calculation outside the repository lets detail screens load
/// the small place table once instead of issuing one SQL query per segment.
PlaceMemory? nearestPlaceMemory(
  Iterable<PlaceMemory> places, {
  required double latitude,
  required double longitude,
  double radiusM = 35,
}) {
  if (!latitude.isFinite || !longitude.isFinite || radiusM < 0) return null;
  PlaceMemory? nearest;
  var nearestDistance = double.infinity;
  for (final place in places) {
    final distance = haversineMeters(
      lat1: latitude,
      lon1: longitude,
      lat2: place.latitude,
      lon2: place.longitude,
    );
    if (distance <= radiusM && distance < nearestDistance) {
      nearest = place;
      nearestDistance = distance;
    }
  }
  return nearest;
}

String? segmentPlaceName(ActivitySegment segment) {
  for (final window in segment.windows) {
    final name = window.placeName?.trim();
    if (name != null && name.isNotEmpty) return name;
  }
  return null;
}

String? segmentPlaceAddress(ActivitySegment segment) {
  for (final window in segment.windows) {
    final address = window.placeAddress?.trim();
    if (address != null && address.isNotEmpty) return address;
  }
  return null;
}
