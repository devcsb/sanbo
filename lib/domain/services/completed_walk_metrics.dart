/// Returns the canonical average movement speed for a completed walk.
///
/// Completed summaries must use trusted route distance and observed moving
/// time, never the provider's last instantaneous speed.
double? completedAverageSpeedMps({
  required double? totalDistanceM,
  required int? movingTimeS,
}) {
  if (totalDistanceM == null ||
      movingTimeS == null ||
      !totalDistanceM.isFinite ||
      totalDistanceM <= 0 ||
      movingTimeS <= 0) {
    return null;
  }
  final average = totalDistanceM / movingTimeS;
  return average.isFinite && average > 0 ? average : null;
}
