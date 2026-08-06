import 'package:geolocator/geolocator.dart';

import '../../domain/models/tracking_mode.dart';

final class LocationRequestProfile {
  const LocationRequestProfile({
    required this.accuracy,
    required this.interval,
    required this.distanceFilterM,
    required this.keepCpuAwake,
  });

  final LocationAccuracy accuracy;
  final Duration interval;
  final int distanceFilterM;
  final bool keepCpuAwake;
}

LocationRequestProfile locationRequestProfile(TrackingMode mode) {
  return switch (mode) {
    TrackingMode.batterySaver => const LocationRequestProfile(
      accuracy: LocationAccuracy.medium,
      interval: Duration(seconds: 20),
      distanceFilterM: 10,
      keepCpuAwake: false,
    ),
    TrackingMode.balanced => const LocationRequestProfile(
      accuracy: LocationAccuracy.high,
      interval: Duration(seconds: 8),
      distanceFilterM: 5,
      keepCpuAwake: false,
    ),
    TrackingMode.highAccuracy => const LocationRequestProfile(
      accuracy: LocationAccuracy.bestForNavigation,
      interval: Duration(seconds: 4),
      distanceFilterM: 2,
      keepCpuAwake: true,
    ),
  };
}
