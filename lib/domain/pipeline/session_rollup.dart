import '../models/route_exclusion.dart';
import '../models/walk_session.dart';
import 'geo.dart';
import 'route_partitioner.dart';

class SessionRollupResult {
  const SessionRollupResult({
    required this.totalDistanceM,
    required this.durationS,
    required this.movingTimeS,
    required this.stationaryTimeS,
    required this.avgSpeedMps,
    required this.validSampleCount,
    this.medianAccuracyM,
  });

  final double totalDistanceM;
  final int durationS;
  final int movingTimeS;
  final int stationaryTimeS;
  final double avgSpeedMps;
  final int validSampleCount;
  final double? medianAccuracyM;
}

/// Session metrics calculated only from shared trusted route segments.
class SessionRollup {
  SessionRollup({this.stationarySpeedMps = 0.3});

  final double stationarySpeedMps;

  SessionRollupResult compute({
    required WalkSession session,
    required RoutePartitionResult partition,
    required List<RouteExclusion> exclusions,
    required DateTime endedAt,
  }) {
    final sessionStart = session.startedAt.toUtc();
    final sessionEnd = endedAt.toUtc();
    if (sessionEnd.isBefore(sessionStart)) {
      throw StateError('종료 시각이 시작 시각보다 빠릅니다');
    }
    final ordered = [...exclusions]
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    for (var index = 0; index < ordered.length; index++) {
      final exclusion = ordered[index];
      if (exclusion.sessionId != session.id ||
          exclusion.startAt.isBefore(sessionStart) ||
          exclusion.endAt.isAfter(sessionEnd)) {
        throw StateError('세션 범위를 벗어난 제외 구간이 있습니다');
      }
      if (index > 0 && exclusion.startAt.isBefore(ordered[index - 1].endAt)) {
        throw StateError('겹치는 제외 구간이 있습니다');
      }
    }
    final fullDurationUs = sessionEnd.difference(sessionStart).inMicroseconds;
    final excludedDurationUs = exclusions.fold<int>(
      0,
      (sum, exclusion) =>
          sum + exclusion.endAt.difference(exclusion.startAt).inMicroseconds,
    );
    if (excludedDurationUs < 0 || excludedDurationUs > fullDurationUs) {
      throw StateError('제외 시간이 전체 기록 시간을 벗어납니다');
    }
    final durationS = positiveDurationSeconds(
      sessionStart,
      sessionEnd.subtract(Duration(microseconds: excludedDurationUs)),
    );

    var distance = 0.0;
    var movingSeconds = 0.0;
    var stationarySeconds = 0.0;
    for (final segment in partition.segments) {
      if (!segment.distanceM.isFinite || !segment.speedMps.isFinite) {
        throw StateError('유효하지 않은 경로 선분이 있습니다');
      }
      if (segment.distanceM >= minMeaningfulSegmentDistanceM) {
        distance += segment.distanceM;
      }
      final seconds =
          segment.duration.inMicroseconds / Duration.microsecondsPerSecond;
      if (segment.speedMps < stationarySpeedMps) {
        stationarySeconds += seconds;
      } else {
        movingSeconds += seconds;
      }
    }

    final accuracies =
        partition.includedSamples
            .map((sample) => sample.accuracyM)
            .whereType<double>()
            .where((accuracy) => accuracy.isFinite)
            .toList()
          ..sort();
    final medianAccuracy = accuracies.isEmpty
        ? null
        : accuracies[accuracies.length ~/ 2];
    final movingTimeS = movingSeconds.round();
    final stationaryTimeS = stationarySeconds.round();
    final avgSpeed = movingTimeS > 0 ? distance / movingTimeS : 0.0;

    return SessionRollupResult(
      totalDistanceM: distance,
      durationS: durationS,
      movingTimeS: movingTimeS,
      stationaryTimeS: stationaryTimeS,
      avgSpeedMps: avgSpeed,
      validSampleCount: partition.includedSamples.length,
      medianAccuracyM: medianAccuracy,
    );
  }
}
