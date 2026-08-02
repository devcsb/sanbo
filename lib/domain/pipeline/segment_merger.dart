import '../models/activity_label.dart';
import '../models/minute_window.dart';
import 'geo.dart';

/// Collapsed consecutive minute windows for readable timeline (PRD FR-13 / TRD §4.8).
class ActivitySegment {
  const ActivitySegment({
    required this.start,
    required this.endInclusive,
    required this.label,
    required this.confidenceMin,
    required this.distanceM,
    required this.sampleCount,
    required this.durationS,
    required this.userConfirmed,
    required this.windows,
    this.avgSpeedMps = 0,
    this.quality = WindowQuality.medium,
  });

  /// First minute boundary in the segment.
  final DateTime start;

  /// Last minute boundary (inclusive) in the segment.
  final DateTime endInclusive;

  final ActivityLabel label;
  final double confidenceMin;
  final double distanceM;
  final int sampleCount;
  final int durationS;
  final bool userConfirmed;
  final double avgSpeedMps;
  final WindowQuality quality;

  /// Underlying minute windows (ordered).
  final List<MinuteWindow> windows;

  int get minuteCount => windows.length;

  /// Exclusive end of the last minute (or partial span).
  DateTime get endExclusive => endInclusive.add(
    Duration(
      seconds: windows.isEmpty ? 60 : windows.last.durationS.clamp(1, 60),
    ),
  );

  /// True when this segment spans more than one wall-clock minute.
  bool get isMultiMinute => minuteCount > 1;
}

/// Merges adjacent minute windows with the same display label (TRD §4.8).
class SegmentMerger {
  SegmentMerger({this.minConfidence = 0.4});

  final double minConfidence;

  List<ActivitySegment> merge(List<MinuteWindow> windows) {
    if (windows.isEmpty) return const [];

    final sorted = [...windows]
      ..sort((a, b) => a.windowStart.compareTo(b.windowStart));

    final segments = <ActivitySegment>[];
    var bucket = <MinuteWindow>[sorted.first];

    for (var i = 1; i < sorted.length; i++) {
      final prev = bucket.last;
      final cur = sorted[i];
      if (_canMerge(prev, cur)) {
        bucket.add(cur);
      } else {
        segments.add(_toSegment(bucket));
        bucket = [cur];
      }
    }
    segments.add(_toSegment(bucket));
    return segments;
  }

  bool _canMerge(MinuteWindow a, MinuteWindow b) {
    // Keep gap minutes separate unless both are gaps with no samples.
    if (a.quality == WindowQuality.gap && b.quality == WindowQuality.gap) {
      return a.displayLabel == b.displayLabel;
    }
    if (a.quality == WindowQuality.gap || b.quality == WindowQuality.gap) {
      return false;
    }

    final labelA = a.displayLabel;
    final labelB = b.displayLabel;
    if (labelA != labelB) return false;

    // Once places are known, do not collapse adjacent stays at different
    // places into one misleading timeline segment.
    if (a.placeId != null && b.placeId != null && a.placeId != b.placeId) {
      return false;
    }

    // Identically classified stays can still be different real-world places.
    // Preserve that boundary before place names are known.
    if (_isStayLabel(labelA) &&
        a.centroidLat != null &&
        a.centroidLon != null &&
        b.centroidLat != null &&
        b.centroidLon != null) {
      final centroidDistance = haversineMeters(
        lat1: a.centroidLat!,
        lon1: a.centroidLon!,
        lat2: b.centroidLat!,
        lon2: b.centroidLon!,
      );
      if (centroidDistance > 50) return false;
    }

    // Unknown alone stays split unless user confirmed both the same.
    if (labelA == ActivityLabel.unknown) {
      return a.userConfirmed && b.userConfirmed;
    }

    final confAOk = a.userConfirmed || a.hypothesisConfidence >= minConfidence;
    final confBOk = b.userConfirmed || b.hypothesisConfidence >= minConfidence;
    if (!confAOk || !confBOk) return false;

    // Only merge contiguous wall-clock minutes (allow 1-min step).
    final expected = a.windowStart.add(const Duration(minutes: 1));
    if (b.windowStart != expected) return false;

    return true;
  }

  bool _isStayLabel(ActivityLabel label) {
    return switch (label) {
      ActivityLabel.stationary ||
      ActivityLabel.placeStay ||
      ActivityLabel.cafeOrShop => true,
      _ => false,
    };
  }

  ActivitySegment _toSegment(List<MinuteWindow> bucket) {
    assert(bucket.isNotEmpty);
    final first = bucket.first;
    final last = bucket.last;
    var distance = 0.0;
    var samples = 0;
    var durationS = 0;
    var confMin = double.infinity;
    var confirmed = true;
    var speedWeighted = 0.0;
    var worstQuality = WindowQuality.high;

    for (final w in bucket) {
      distance += w.distanceM;
      samples += w.sampleCount;
      durationS += w.durationS;
      confMin = confMin < w.hypothesisConfidence
          ? confMin
          : w.hypothesisConfidence;
      if (!w.userConfirmed) confirmed = false;
      speedWeighted += w.avgSpeedMps * w.durationS;
      worstQuality = _worseQuality(worstQuality, w.quality);
    }

    final avgSpeed = durationS > 0 ? speedWeighted / durationS : 0.0;

    return ActivitySegment(
      start: first.windowStart,
      endInclusive: last.windowStart,
      label: first.displayLabel,
      confidenceMin: confMin.isFinite ? confMin : 0,
      distanceM: distance,
      sampleCount: samples,
      durationS: durationS,
      userConfirmed: confirmed && bucket.every((w) => w.userConfirmed),
      avgSpeedMps: avgSpeed,
      quality: worstQuality,
      windows: List.unmodifiable(bucket),
    );
  }

  WindowQuality _worseQuality(WindowQuality a, WindowQuality b) {
    int rank(WindowQuality q) => switch (q) {
      WindowQuality.high => 0,
      WindowQuality.medium => 1,
      WindowQuality.low => 2,
      WindowQuality.gap => 3,
    };
    return rank(a) >= rank(b) ? a : b;
  }
}
