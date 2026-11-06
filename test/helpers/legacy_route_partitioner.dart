import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/route_exclusion.dart';
import 'package:sanbo/domain/pipeline/geo.dart';
import 'package:sanbo/domain/pipeline/route_partitioner.dart';

/// Frozen pre-optimization behavior for bounded equivalence tests only.
abstract final class LegacyRoutePartitioner {
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

    void flush() {
      if (current.isEmpty) return;
      fragments.add(RouteFragment(List.unmodifiable(current)));
      current = <LocationSample>[];
    }

    for (final sample in orderedSamples) {
      final excluded = orderedExclusions.any(
        (exclusion) => exclusion.contains(sample.timestamp),
      );
      final closesIncludedFragment =
          excluded &&
          preserveExclusionStartEndpoint &&
          current.isNotEmpty &&
          orderedExclusions.any(
            (exclusion) => exclusion.startAt.isAtSameMomentAs(sample.timestamp),
          );
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
      final crossesExclusion = orderedExclusions.any(
        (exclusion) => exclusion.overlaps(previous.timestamp, sample.timestamp),
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
