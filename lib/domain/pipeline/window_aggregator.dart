import '../models/location_sample.dart';
import '../models/minute_window.dart';
import 'activity_inferencer.dart';
import 'geo.dart';

class WindowAggregatorConfig {
  const WindowAggregatorConfig({
    this.minSamplesPerWindow = 3,
    this.stationarySpeedMps = 0.3,
    this.medianAccuracyHighM = 25,
    this.medianAccuracyMediumM = 50,
  });

  final int minSamplesPerWindow;
  final double stationarySpeedMps;
  final double medianAccuracyHighM;
  final double medianAccuracyMediumM;
}

/// Buckets samples into wall-clock minute windows (TRD §4.3).
class WindowAggregator {
  WindowAggregator({
    this.config = const WindowAggregatorConfig(),
    ActivityInferencer? inferencer,
  }) : inferencer = inferencer ?? ActivityInferencer();

  final WindowAggregatorConfig config;
  final ActivityInferencer inferencer;

  /// Aggregate [samples] between [sessionStart] and optional [sessionEnd].
  ///
  /// Gap minutes with zero samples are emitted as [WindowQuality.gap].
  List<MinuteWindow> aggregate({
    required List<LocationSample> samples,
    required DateTime sessionStart,
    DateTime? sessionEnd,
  }) {
    // Absolute end for range checks (UTC/local instants compare correctly).
    final endAbs = sessionEnd ?? DateTime.now();
    if (endAbs.isBefore(sessionStart)) return const [];

    // Local bounds for wall-clock minute cursor keys (PRD: 분 경계).
    final startLocal = asLocal(sessionStart);
    final endLocal = asLocal(endAbs);

    final byMinute = <DateTime, List<LocationSample>>{};
    for (final s in samples) {
      if (s.timestamp.isBefore(sessionStart) || s.timestamp.isAfter(endAbs)) {
        continue;
      }
      final tsLocal = asLocal(s.timestamp);
      final key = floorToMinute(tsLocal);
      final normalized = s.timestamp.isUtc
          ? LocationSample(
              timestamp: tsLocal,
              latitude: s.latitude,
              longitude: s.longitude,
              accuracyM: s.accuracyM,
              speedMps: s.speedMps,
              altitudeM: s.altitudeM,
              isFilteredOut: s.isFilteredOut,
            )
          : s;
      byMinute.putIfAbsent(key, () => []).add(normalized);
    }

    final windows = <MinuteWindow>[];
    var cursor = floorToMinute(startLocal);
    final lastMinute = floorToMinute(endLocal);

    while (!cursor.isAfter(lastMinute)) {
      final bucket = byMinute[cursor] ?? const <LocationSample>[];
      windows.add(
        _buildWindow(
          windowStart: cursor,
          samples: bucket,
          sessionStart: startLocal,
          sessionEnd: endLocal,
        ),
      );
      cursor = cursor.add(const Duration(minutes: 1));
    }
    return windows;
  }

  MinuteWindow _buildWindow({
    required DateTime windowStart,
    required List<LocationSample> samples,
    required DateTime sessionStart,
    required DateTime sessionEnd,
  }) {
    final windowEnd = windowStart.add(const Duration(minutes: 1));
    final spanStart = sessionStart.isAfter(windowStart)
        ? sessionStart
        : windowStart;
    final spanEnd = sessionEnd.isBefore(windowEnd) ? sessionEnd : windowEnd;
    var durationS = spanEnd.difference(spanStart).inSeconds;
    if (durationS < 0) durationS = 0;
    if (durationS > 60) durationS = 60;
    final partial =
        durationS < 60 ||
        sessionStart.isAfter(windowStart) ||
        sessionEnd.isBefore(windowEnd);

    final rawCount = samples.length;
    final valid = samples.where((s) => !s.isFilteredOut).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (valid.isEmpty) {
      final gap = MinuteWindow(
        windowStart: windowStart,
        durationS: durationS == 0 ? 60 : durationS,
        partial: partial,
        sampleCount: 0,
        rawSampleCount: rawCount,
        distanceM: 0,
        avgSpeedMps: 0,
        maxSpeedMps: 0,
        stationaryRatio: 1,
        quality: WindowQuality.gap,
        gapReason: rawCount == 0 ? 'no_samples' : 'all_filtered',
      );
      final hyp = inferencer.infer(gap);
      return MinuteWindow(
        windowStart: gap.windowStart,
        durationS: gap.durationS,
        partial: gap.partial,
        sampleCount: gap.sampleCount,
        rawSampleCount: gap.rawSampleCount,
        distanceM: gap.distanceM,
        avgSpeedMps: gap.avgSpeedMps,
        maxSpeedMps: gap.maxSpeedMps,
        stationaryRatio: gap.stationaryRatio,
        quality: gap.quality,
        gapReason: gap.gapReason,
        hypothesisLabel: hyp.label,
        hypothesisConfidence: hyp.confidence,
        evidence: hyp.evidence,
      );
    }

    final distance = pathDistanceMeters(
      valid.map((s) => (lat: s.latitude, lon: s.longitude)),
    );

    var maxSpeed = 0.0;
    var stationaryTimeS = 0.0;
    for (var i = 0; i < valid.length; i++) {
      final s = valid[i];
      final spd = s.speedMps;
      if (spd != null && spd > maxSpeed) maxSpeed = spd;

      if (i > 0) {
        final prev = valid[i - 1];
        final dt = s.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
        if (dt <= 0) continue;
        final segDist = haversineMeters(
          lat1: prev.latitude,
          lon1: prev.longitude,
          lat2: s.latitude,
          lon2: s.longitude,
        );
        final inst = segDist / dt;
        if (inst > maxSpeed) maxSpeed = inst;
        if (inst < config.stationarySpeedMps) {
          stationaryTimeS += dt;
        }
      }
    }

    final movingDenom = mathMax(durationS - stationaryTimeS.round(), 1);
    final avgSpeed = distance / movingDenom;
    final stationaryRatio = durationS <= 0
        ? 1.0
        : (stationaryTimeS / durationS).clamp(0.0, 1.0);

    final accuracies =
        valid.map((s) => s.accuracyM).whereType<double>().toList()..sort();
    final medianAcc = accuracies.isEmpty
        ? null
        : accuracies[accuracies.length ~/ 2];

    final quality = _quality(
      sampleCount: valid.length,
      medianAccuracyM: medianAcc,
    );

    var latSum = 0.0;
    var lonSum = 0.0;
    for (final s in valid) {
      latSum += s.latitude;
      lonSum += s.longitude;
    }

    final draft = MinuteWindow(
      windowStart: windowStart,
      durationS: durationS == 0 ? 1 : durationS,
      partial: partial,
      sampleCount: valid.length,
      rawSampleCount: rawCount,
      distanceM: distance,
      avgSpeedMps: avgSpeed,
      maxSpeedMps: maxSpeed,
      stationaryRatio: stationaryRatio,
      quality: quality,
      centroidLat: latSum / valid.length,
      centroidLon: lonSum / valid.length,
      startLat: valid.first.latitude,
      startLon: valid.first.longitude,
      endLat: valid.last.latitude,
      endLon: valid.last.longitude,
    );

    final hyp = inferencer.infer(draft);
    return MinuteWindow(
      windowStart: draft.windowStart,
      durationS: draft.durationS,
      partial: draft.partial,
      sampleCount: draft.sampleCount,
      rawSampleCount: draft.rawSampleCount,
      distanceM: draft.distanceM,
      avgSpeedMps: draft.avgSpeedMps,
      maxSpeedMps: draft.maxSpeedMps,
      stationaryRatio: draft.stationaryRatio,
      quality: draft.quality,
      centroidLat: draft.centroidLat,
      centroidLon: draft.centroidLon,
      startLat: draft.startLat,
      startLon: draft.startLon,
      endLat: draft.endLat,
      endLon: draft.endLon,
      hypothesisLabel: hyp.label,
      hypothesisConfidence: hyp.confidence,
      evidence: hyp.evidence,
    );
  }

  WindowQuality _quality({
    required int sampleCount,
    required double? medianAccuracyM,
  }) {
    if (sampleCount < config.minSamplesPerWindow) return WindowQuality.low;
    if (medianAccuracyM == null) return WindowQuality.medium;
    if (medianAccuracyM <= config.medianAccuracyHighM) {
      return WindowQuality.high;
    }
    if (medianAccuracyM <= config.medianAccuracyMediumM) {
      return WindowQuality.medium;
    }
    return WindowQuality.low;
  }
}

double mathMax(num a, num b) => a > b ? a.toDouble() : b.toDouble();
