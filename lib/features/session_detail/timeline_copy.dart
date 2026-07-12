import '../../domain/models/minute_window.dart';

/// User-facing timeline subtitle — no raw quality enum / evidence codes (UX-D01).
String timelineWindowSubtitle(MinuteWindow w) {
  if (w.quality == WindowQuality.gap || w.sampleCount == 0) {
    return '위치 기록 없음';
  }
  final meters = w.distanceM < 1
      ? '${(w.distanceM * 100).round() / 100} m'
      : '${w.distanceM.round()} m';
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

