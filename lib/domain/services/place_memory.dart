import '../models/activity_label.dart';
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
