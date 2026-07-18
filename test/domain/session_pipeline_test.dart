import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/fixtures/synthetic_trace.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
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
    // Same continuous walk should collapse into fewer segments than minutes.
    expect(result.segments, isNotEmpty);
    expect(result.segments.length, lessThan(result.windows.length));
    expect(
      result.segments.any(
        (s) =>
            s.label == ActivityLabel.walkSteady ||
            s.label == ActivityLabel.walkBrisk ||
            s.label == ActivityLabel.strollSlow,
      ),
      isTrue,
    );
  });

  test('urban-poor accuracy still yields distance (Galaxy cold start)', () {
    final start = DateTime(2026, 7, 12, 9, 0, 0);
    const degPerMeter = 1 / 111320.0;
    final list = <LocationSample>[
      for (var i = 0; i < 30; i++)
        LocationSample(
          timestamp: start.add(Duration(seconds: i * 4)),
          latitude: 37.5 + i * 4 * 1.2 * degPerMeter,
          longitude: 127.0,
          // First few fixes soft-poor (Galaxy cold start), then good.
          accuracyM: i < 5 ? 120 : 10,
          speedMps: 1.2,
        ),
    ];

    final session = WalkSession(
      id: 'urban',
      startedAt: start,
      timezone: 'Asia/Seoul',
      trackingMode: TrackingMode.balanced,
    );
    final result = SessionPipeline().process(
      session: session,
      rawSamples: list,
      endedAt: start.add(const Duration(minutes: 3)),
    );
    expect(result.metrics.totalDistanceM, greaterThan(50));
    expect(result.metrics.validSampleCount, greaterThan(10));
  });
}
