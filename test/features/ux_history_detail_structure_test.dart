import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/features/session_detail/timeline_copy.dart';

void main() {
  // Empty history CTA + delete routing: see ux_history_detail_widget_test.dart
  // (real HistoryScreen / SessionDetailScreen + go_router).

  test('history and detail ship stats notes export helpers', () {
    final history = File('lib/features/history/history_screen.dart').readAsStringSync();
    expect(history.contains('나의 흐름'), isTrue);
    expect(history.contains('WalkStats.fromSessions'), isTrue);

    final detail =
        File('lib/features/session_detail/session_detail_screen.dart')
            .readAsStringSync();
    expect(detail.contains('메모 저장'), isTrue);
    expect(detail.contains('_copySummary'), isTrue);
    expect(detail.contains('_exportSession'), isTrue);
    expect(detail.contains('SessionExport'), isTrue);

    final home = File('lib/features/home/home_screen.dart').readAsStringSync();
    expect(home.contains('_celebrateMilestones'), isTrue);
    expect(home.contains('HapticFeedback'), isTrue);
  });

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
    expect(s.contains('km/h'), isTrue);
    expect(s.contains('speed_band'), isFalse);
    expect(s.contains('추정'), isFalse); // chip on row title, not subtitle
  });
}
