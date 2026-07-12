import '../models/location_sample.dart';
import '../models/walk_session.dart';
import 'geo.dart';

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

/// Session-level metrics from filtered path (not sum of windows) — TRD §4.7.
class SessionRollup {
  SessionRollup({this.stationarySpeedMps = 0.3});

  final double stationarySpeedMps;

  SessionRollupResult compute({
    required WalkSession session,
    required List<LocationSample> samples,
    required DateTime endedAt,
  }) {
    final valid = samples.where((s) => !s.isFilteredOut).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final durationS = endedAt.difference(session.startedAt).inSeconds.clamp(
      0,
      86400 * 7,
    );
    final distance = pathDistanceMeters(
      valid.map((s) => (lat: s.latitude, lon: s.longitude)),
    );

    var stationaryS = 0.0;
    for (var i = 1; i < valid.length; i++) {
      final prev = valid[i - 1];
      final s = valid[i];
      final dt = s.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
      if (dt <= 0) continue;
      final d = haversineMeters(
        lat1: prev.latitude,
        lon1: prev.longitude,
        lat2: s.latitude,
        lon2: s.longitude,
      );
      if (d / dt < stationarySpeedMps) stationaryS += dt;
    }

    final stationaryTimeS = stationaryS.round().clamp(0, durationS);
    final movingTimeS = (durationS - stationaryTimeS).clamp(0, durationS);
    final avgSpeed = movingTimeS > 0 ? distance / movingTimeS : 0.0;

    final acc = valid.map((s) => s.accuracyM).whereType<double>().toList()
      ..sort();
    final medianAcc = acc.isEmpty ? null : acc[acc.length ~/ 2];

    return SessionRollupResult(
      totalDistanceM: distance,
      durationS: durationS,
      movingTimeS: movingTimeS,
      stationaryTimeS: stationaryTimeS,
      avgSpeedMps: avgSpeed,
      validSampleCount: valid.length,
      medianAccuracyM: medianAcc,
    );
  }
}
