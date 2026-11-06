import '../models/location_sample.dart';
import '../models/route_exclusion.dart';
import 'geo.dart';

class RouteSegment {
  const RouteSegment({
    required this.start,
    required this.end,
    required this.distanceM,
  });

  final LocationSample start;
  final LocationSample end;
  final double distanceM;

  Duration get duration => end.timestamp.difference(start.timestamp);
  double get speedMps =>
      distanceM / (duration.inMicroseconds / Duration.microsecondsPerSecond);
}

class RouteFragment {
  const RouteFragment(this.samples);

  /// May end at an excluded interval's actual start fix, solely to close the
  /// preceding included edge. That fix is not owned by includedSamples.
  final List<LocationSample> samples;
}

class RoutePartitionResult {
  const RoutePartitionResult({
    required this.fragments,
    required this.includedSamples,
    required this.segments,
  });

  final List<RouteFragment> fragments;
  final List<LocationSample> includedSamples;
  final List<RouteSegment> segments;
}

abstract final class RoutePartitioner {
  static RoutePartitionResult partition({
    required List<LocationSample> samples,
    required List<RouteExclusion> exclusions,
    Duration maxGap = trustedLocationGap,
    DateTime? sessionStart,
    DateTime? sessionEnd,
    bool preserveExclusionStartEndpoint = true,
  }) {
    final startUtc = sessionStart?.toUtc();
    final endUtc = sessionEnd?.toUtc();
    if (startUtc != null && endUtc != null && startUtc.isAfter(endUtc)) {
      throw ArgumentError('세션 시작은 종료보다 빨라야 합니다');
    }
    final boundedSamples = samples.where((sample) {
      final timestamp = sample.timestamp.toUtc();
      return (startUtc == null || !timestamp.isBefore(startUtc)) &&
          (endUtc == null || !timestamp.isAfter(endUtc));
    });
    final orderedSamples = [...boundedSamples]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final orderedExclusions = [...exclusions]
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    for (var index = 1; index < orderedExclusions.length; index++) {
      if (orderedExclusions[index].startAt.isBefore(
        orderedExclusions[index - 1].endAt,
      )) {
        throw ArgumentError('겹치는 제외 범위가 있습니다');
      }
    }

    final included = <LocationSample>[];
    final fragments = <RouteFragment>[];
    final segments = <RouteSegment>[];
    var current = <LocationSample>[];
    var pointExclusionIndex = 0;
    var edgeExclusionIndex = 0;

    void flush() {
      if (current.isEmpty) return;
      fragments.add(RouteFragment(List.unmodifiable(current)));
      current = <LocationSample>[];
    }

    for (final sample in orderedSamples) {
      // Disjoint intervals and sorted samples let both cursors move only forward:
      // O(samples + exclusions) after sorting, even for dense edited backups.
      while (pointExclusionIndex < orderedExclusions.length &&
          !orderedExclusions[pointExclusionIndex].endAt.isAfter(
            sample.timestamp,
          )) {
        pointExclusionIndex++;
      }
      final pointExclusion = pointExclusionIndex < orderedExclusions.length
          ? orderedExclusions[pointExclusionIndex]
          : null;
      final excluded = pointExclusion?.contains(sample.timestamp) ?? false;
      final closesIncludedFragment =
          excluded &&
          preserveExclusionStartEndpoint &&
          current.isNotEmpty &&
          pointExclusion!.startAt.isAtSameMomentAs(sample.timestamp);
      if (sample.isFilteredOut ||
          !_validFix(sample) ||
          (excluded && !closesIncludedFragment)) {
        flush();
        continue;
      }

      if (!excluded) included.add(sample);
      if (current.isEmpty) {
        current = [sample];
        continue;
      }

      final previous = current.last;
      final duration = sample.timestamp.difference(previous.timestamp);
      while (edgeExclusionIndex < orderedExclusions.length &&
          !orderedExclusions[edgeExclusionIndex].endAt.isAfter(
            previous.timestamp,
          )) {
        edgeExclusionIndex++;
      }
      final crossesExclusion =
          edgeExclusionIndex < orderedExclusions.length &&
          orderedExclusions[edgeExclusionIndex].overlaps(
            previous.timestamp,
            sample.timestamp,
          );
      final distance = haversineMeters(
        lat1: previous.latitude,
        lon1: previous.longitude,
        lat2: sample.latitude,
        lon2: sample.longitude,
      );
      final speed =
          distance / (duration.inMicroseconds / Duration.microsecondsPerSecond);
      final connect =
          duration > Duration.zero &&
          duration <= maxGap &&
          !crossesExclusion &&
          distance.isFinite &&
          speed.isFinite;
      if (!connect) {
        flush();
        if (!excluded) current = [sample];
        continue;
      }

      current.add(sample);
      segments.add(
        RouteSegment(start: previous, end: sample, distanceM: distance),
      );
      if (closesIncludedFragment) flush();
    }
    flush();

    return RoutePartitionResult(
      fragments: List.unmodifiable(fragments),
      includedSamples: List.unmodifiable(included),
      segments: List.unmodifiable(segments),
    );
  }

  static bool _validFix(LocationSample sample) {
    return sample.timestamp.microsecondsSinceEpoch > 0 &&
        sample.latitude.isFinite &&
        sample.longitude.isFinite &&
        sample.latitude >= -90 &&
        sample.latitude <= 90 &&
        sample.longitude >= -180 &&
        sample.longitude <= 180;
  }
}
