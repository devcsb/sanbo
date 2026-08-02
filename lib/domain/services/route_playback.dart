import '../models/location_sample.dart';

/// Pure helpers for replaying a recorded route without coupling playback
/// decisions to the detail-screen widgets.
abstract final class RoutePlayback {
  /// Only valid fixes participate in route playback, ordered by recorded time.
  static List<LocationSample> playableSamples(
    Iterable<LocationSample> samples,
  ) {
    final result = samples.where((sample) => !sample.isFilteredOut).toList();
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  /// Returns the recorded fix closest to [time].
  ///
  /// The binary search keeps segment selection fast even for long,
  /// high-frequency walks.
  static int nearestIndex(List<LocationSample> sortedSamples, DateTime time) {
    if (sortedSamples.isEmpty) return 0;
    if (!time.isAfter(sortedSamples.first.timestamp)) return 0;
    if (!time.isBefore(sortedSamples.last.timestamp)) {
      return sortedSamples.length - 1;
    }

    var low = 0;
    var high = sortedSamples.length - 1;
    while (low <= high) {
      final middle = low + ((high - low) ~/ 2);
      final timestamp = sortedSamples[middle].timestamp;
      if (timestamp == time) return middle;
      if (timestamp.isBefore(time)) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }

    final beforeDelta = time
        .difference(sortedSamples[high].timestamp)
        .inMilliseconds
        .abs();
    final afterDelta = sortedSamples[low].timestamp
        .difference(time)
        .inMilliseconds
        .abs();
    return beforeDelta <= afterDelta ? high : low;
  }

  /// Recorded fixes contained in a timeline segment.
  static List<LocationSample> samplesInRange(
    List<LocationSample> sortedSamples, {
    required DateTime start,
    required DateTime endExclusive,
  }) {
    return sortedSamples
        .where(
          (sample) =>
              !sample.timestamp.isBefore(start) &&
              sample.timestamp.isBefore(endExclusive),
        )
        .toList(growable: false);
  }

  /// Advances a route in at most ~50 animation ticks, keeping long walks
  /// responsive while short walks still move one recorded fix at a time.
  static int stepForSampleCount(int sampleCount) {
    if (sampleCount <= 1) return 1;
    return ((sampleCount - 1) / 50).ceil();
  }

  /// Keeps normal and long routes close to a 20-second replay.
  ///
  /// Very short traces are capped at one second per fix so playback does not
  /// feel artificially slow.
  static Duration intervalForSampleCount(int sampleCount) {
    if (sampleCount <= 1) return const Duration(milliseconds: 400);
    final step = stepForSampleCount(sampleCount);
    final tickCount = ((sampleCount - 1) / step).ceil();
    final milliseconds = (20000 / tickCount).round().clamp(250, 1000);
    return Duration(milliseconds: milliseconds);
  }
}
