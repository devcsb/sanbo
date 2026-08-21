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
  double get speedMps => distanceM / (duration.inMilliseconds / 1000);
}

class RouteFragment {
  const RouteFragment(this.samples);

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
  }) {
    final orderedSamples = [...samples]
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
      if (sample.isFilteredOut || !_validFix(sample) || excluded) {
        flush();
        continue;
      }

      included.add(sample);
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
      final connect =
          duration > Duration.zero &&
          duration <= maxGap &&
          !crossesExclusion &&
          distance.isFinite;
      if (!connect) {
        flush();
        current = [sample];
        continue;
      }

      current.add(sample);
      segments.add(
        RouteSegment(start: previous, end: sample, distanceM: distance),
      );
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
