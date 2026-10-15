enum LiveSpeedAvailability { waiting, available, stale }

LiveSpeedAvailability liveSpeedAvailability({
  DateTime? lastUsableFixAt,
  required DateTime now,
  required bool hasSpeedEvidence,
  required Duration maxAge,
  required Duration maxFutureSkew,
}) {
  if (lastUsableFixAt == null) return LiveSpeedAvailability.waiting;
  final age = now.toUtc().difference(lastUsableFixAt.toUtc());
  if (age > maxAge || age < -maxFutureSkew) return LiveSpeedAvailability.stale;
  return hasSpeedEvidence
      ? LiveSpeedAvailability.available
      : LiveSpeedAvailability.waiting;
}
