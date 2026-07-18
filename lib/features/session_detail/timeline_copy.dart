import '../../domain/models/minute_window.dart';
import '../../domain/pipeline/segment_merger.dart';

/// User-facing timeline subtitle — no raw quality enum / evidence codes (UX-D01).
String timelineWindowSubtitle(MinuteWindow w) {
  if (w.quality == WindowQuality.gap || w.sampleCount == 0) {
    return '위치 기록 없음';
  }
  final meters = _formatMeters(w.distanceM);
  final kmh = (w.avgSpeedMps * 3.6).toStringAsFixed(1);
  final qualityNote = switch (w.quality) {
    WindowQuality.low => ' · GPS 약함',
    WindowQuality.medium => '',
    WindowQuality.high => '',
    WindowQuality.gap => '',
  };
  // Confidence is shown as the 추정 chip on the row title — keep subtitle lean.
  return '$meters · $kmh km/h$qualityNote';
}

/// Subtitle for a merged activity segment (readable multi-minute range).
String timelineSegmentSubtitle(ActivitySegment segment) {
  if (segment.quality == WindowQuality.gap || segment.sampleCount == 0) {
    return segment.isMultiMinute
        ? '${segment.minuteCount}분 · 위치 기록 없음'
        : '위치 기록 없음';
  }
  final meters = _formatMeters(segment.distanceM);
  final kmh = (segment.avgSpeedMps * 3.6).toStringAsFixed(1);
  final qualityNote = switch (segment.quality) {
    WindowQuality.low => ' · GPS 약함',
    WindowQuality.medium => '',
    WindowQuality.high => '',
    WindowQuality.gap => '',
  };
  if (segment.isMultiMinute) {
    return '${segment.minuteCount}분 · $meters · $kmh km/h$qualityNote';
  }
  return '$meters · $kmh km/h$qualityNote';
}

String _formatMeters(double distanceM) {
  if (distanceM < 1) {
    return '${(distanceM * 100).round() / 100} m';
  }
  if (distanceM < 1000) {
    return '${distanceM.round()} m';
  }
  return '${(distanceM / 1000).toStringAsFixed(2)} km';
}
