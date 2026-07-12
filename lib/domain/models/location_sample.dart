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
