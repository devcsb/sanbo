import '../../domain/models/minute_window.dart';

/// User-facing timeline subtitle — no raw quality enum / evidence codes (UX-D01).
String timelineWindowSubtitle(MinuteWindow w) {
  if (w.quality == WindowQuality.gap || w.sampleCount == 0) {
    return '이 구간은 위치 기록이 비어 있어요';
  }
  final meters = w.distanceM < 1
      ? '${(w.distanceM * 100).round() / 100} m'
      : '${w.distanceM.round()} m';
  final kmh = (w.avgSpeedMps * 3.6).toStringAsFixed(1);
  final conf = w.userConfirmed
      ? '확정'
      : w.hypothesisConfidence >= 0.55
          ? '추정'
          : '추정 (불확실)';
  final qualityNote = switch (w.quality) {
    WindowQuality.low => ' · 위치 정확도 낮음',
    WindowQuality.medium => '',
    WindowQuality.high => '',
    WindowQuality.gap => '',
  };
  return '$meters · $kmh km/h · $conf$qualityNote';
}
