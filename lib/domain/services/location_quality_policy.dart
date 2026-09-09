import '../models/location_sample.dart';

enum LocationQualityRejection {
  invalidCoordinate,
  invalidTimestamp,
  staleTimestamp,
  futureTimestamp,
  excessiveAccuracy,
  beforeSession,
  outOfOrder,
}

class LocationQualityDecision {
  const LocationQualityDecision.accepted() : rejection = null;
  const LocationQualityDecision.rejected(this.rejection);

  final LocationQualityRejection? rejection;
  bool get accepted => rejection == null;
}

class LocationQualityPolicy {
  const LocationQualityPolicy({
    this.maxAge = const Duration(seconds: 30),
    this.maxFutureSkew = const Duration(seconds: 5),
    this.hardMaxAccuracyM = 500,
  });

  final Duration maxAge;
  final Duration maxFutureSkew;
  final double hardMaxAccuracyM;

  LocationQualityDecision evaluate({
    required LocationSample sample,
    required DateTime observedAt,
    DateTime? sessionStart,
    DateTime? previousAccepted,
  }) {
    final lat = sample.latitude;
    final lon = sample.longitude;
    if (!lat.isFinite ||
        !lon.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180) {
      return const LocationQualityDecision.rejected(
        LocationQualityRejection.invalidCoordinate,
      );
    }
    final accuracy = sample.accuracyM;
    if (accuracy != null &&
        (!accuracy.isFinite || accuracy < 0 || accuracy > hardMaxAccuracyM)) {
      return const LocationQualityDecision.rejected(
        LocationQualityRejection.excessiveAccuracy,
      );
    }

    final timestamp = sample.timestamp.toUtc();
    final observed = observedAt.toUtc();
    if (sessionStart != null && timestamp.isBefore(sessionStart.toUtc())) {
      return const LocationQualityDecision.rejected(
        LocationQualityRejection.beforeSession,
      );
    }
    if (timestamp.isBefore(observed.subtract(maxAge))) {
      return const LocationQualityDecision.rejected(
        LocationQualityRejection.staleTimestamp,
      );
    }
    if (timestamp.isAfter(observed.add(maxFutureSkew))) {
      return const LocationQualityDecision.rejected(
        LocationQualityRejection.futureTimestamp,
      );
    }
    if (previousAccepted != null &&
        !timestamp.isAfter(previousAccepted.toUtc())) {
      return const LocationQualityDecision.rejected(
        LocationQualityRejection.outOfOrder,
      );
    }
    return const LocationQualityDecision.accepted();
  }
}
