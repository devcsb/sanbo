import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/fixtures/synthetic_trace.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';

void main() {
  test('pipeline produces non-zero distance and activity hypotheses', () {
    final start = DateTime(2026, 7, 12, 8, 0, 0);
    final samples = buildWalkTrace(
      start: start,
      duration: const Duration(minutes: 4),
    );
    final session = WalkSession(
      id: 'test',
      startedAt: start,
      timezone: 'Asia/Seoul',
      trackingMode: TrackingMode.balanced,
    );
    final endedAt = start.add(const Duration(minutes: 4, seconds: 5));
    final result = SessionPipeline().process(
      session: session,
      rawSamples: samples,
      endedAt: endedAt,
    );

    expect(result.metrics.totalDistanceM, greaterThan(100));
    expect(result.metrics.validSampleCount, samples.length);
    expect(result.windows.length, greaterThanOrEqualTo(4));
    final moving = result.windows.where((w) => w.sampleCount >= 3);
    expect(moving, isNotEmpty);
    expect(
      moving.any(
        (w) =>
            w.hypothesisLabel == ActivityLabel.walkSteady ||
            w.hypothesisLabel == ActivityLabel.walkBrisk ||
            w.hypothesisLabel == ActivityLabel.strollSlow,
      ),
      isTrue,
    );
  });
}
