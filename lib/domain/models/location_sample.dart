/// Single GPS (or fused) fix. Pure domain — no Flutter imports.
class LocationSample {
  const LocationSample({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.accuracyM,
    this.speedMps,
    this.altitudeM,
    this.isFilteredOut = false,
  });

  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final double? speedMps;
  final double? altitudeM;
  final bool isFilteredOut;

  /// Removes malformed optional provider metadata while preserving a valid
  /// coordinate fix. Platform channels should normally sanitize these values,
  /// but this domain boundary keeps synthetic/custom engines from persisting
  /// infinities that SQLite accepts and JSON cannot encode.
  LocationSample normalizedMetadata() {
    final normalizedAccuracy =
        accuracyM != null && accuracyM!.isFinite && accuracyM! >= 0
        ? accuracyM
        : null;
    final normalizedSpeed =
        speedMps != null && speedMps!.isFinite && speedMps! >= 0
        ? speedMps
        : null;
    final normalizedAltitude = altitudeM != null && altitudeM!.isFinite
        ? altitudeM
        : null;
    if (normalizedAccuracy == accuracyM &&
        normalizedSpeed == speedMps &&
        normalizedAltitude == altitudeM) {
      return this;
    }
    return LocationSample(
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      accuracyM: normalizedAccuracy,
      speedMps: normalizedSpeed,
      altitudeM: normalizedAltitude,
      isFilteredOut: isFilteredOut,
    );
  }

  LocationSample copyWith({bool? isFilteredOut}) {
    return LocationSample(
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      accuracyM: accuracyM,
      speedMps: speedMps,
      altitudeM: altitudeM,
      isFilteredOut: isFilteredOut ?? this.isFilteredOut,
    );
  }
}
