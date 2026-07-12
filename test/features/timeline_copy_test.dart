import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/features/session_detail/timeline_copy.dart';

void main() {
  test('timeline subtitle is human-readable without evidence codes', () {
    final w = MinuteWindow(
      windowStart: DateTime(2026, 7, 12, 14, 3),
      durationS: 60,
      partial: false,
      sampleCount: 12,
      rawSampleCount: 12,
      distanceM: 72,
      avgSpeedMps: 1.2,
      maxSpeedMps: 1.4,
      stationaryRatio: 0.05,
      quality: WindowQuality.high,
      hypothesisLabel: ActivityLabel.walkSteady,
      hypothesisConfidence: 0.75,
      evidence: const ['speed_band:1.2 m/s', 'stationary_ratio:0.05'],
    );
    final s = timelineWindowSubtitle(w);
    expect(s, contains('추정'));
    expect(s, contains('km/h'));
    expect(s, isNot(contains('speed_band')));
    expect(s, isNot(contains('high')));
    expect(s, isNot(contains('0.75')));
  });

  test('gap window uses friendly empty copy', () {
    final w = MinuteWindow(
      windowStart: DateTime(2026, 7, 12, 14, 4),
      durationS: 60,
      partial: false,
      sampleCount: 0,
      rawSampleCount: 0,
      distanceM: 0,
      avgSpeedMps: 0,
      maxSpeedMps: 0,
      stationaryRatio: 1,
      quality: WindowQuality.gap,
      gapReason: 'no_samples',
    );
    final s = timelineWindowSubtitle(w);
    expect(s, contains('비어'));
    expect(s, isNot(contains('no_samples')));
  });
}
