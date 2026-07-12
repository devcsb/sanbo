import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/features/session_detail/timeline_copy.dart';

void main() {
  // Empty history CTA + delete routing: see ux_history_detail_widget_test.dart
  // (real HistoryScreen / SessionDetailScreen + go_router).

  test('timeline copy uses shipped helper without tech dump', () {
    final w = MinuteWindow(
      windowStart: DateTime(2026, 7, 12, 15, 0),
      durationS: 60,
      partial: false,
      sampleCount: 10,
      rawSampleCount: 10,
      distanceM: 80,
      avgSpeedMps: 1.1,
      maxSpeedMps: 1.3,
      stationaryRatio: 0.1,
      quality: WindowQuality.high,
      hypothesisLabel: ActivityLabel.walkSteady,
      hypothesisConfidence: 0.7,
      evidence: const ['speed_band:1.1'],
    );
    final s = timelineWindowSubtitle(w);
    expect(s.contains('추정'), isTrue);
    expect(s.contains('speed_band'), isFalse);
  });
}
