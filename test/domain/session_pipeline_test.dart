import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/fixtures/synthetic_trace.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/models/route_exclusion.dart';
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

  test(
    'completed recalculation preserves stored filter and minute metadata',
    () {
      final start = DateTime.utc(2026, 8, 21, 0);
      final session = WalkSession(
        id: 'walk-1',
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 2)),
        timezone: 'Asia/Seoul',
        trackingMode: TrackingMode.balanced,
        status: SessionStatus.completed,
      );
      final stored = [
        LocationSample(
          timestamp: start,
          latitude: 37.5,
          longitude: 127,
          accuracyM: 5,
        ),
        LocationSample(
          timestamp: start.add(const Duration(seconds: 30)),
          latitude: 37.5003,
          longitude: 127,
          accuracyM: 5,
        ),
        LocationSample(
          timestamp: start.add(const Duration(seconds: 60)),
          latitude: 37.5006,
          longitude: 127,
          accuracyM: 5,
          isFilteredOut: true,
        ),
        LocationSample(
          timestamp: start.add(const Duration(seconds: 90)),
          latitude: 37.5009,
          longitude: 127,
          accuracyM: 5,
        ),
      ];
      final previous = [
        MinuteWindow(
          windowStart: start,
          durationS: 60,
          partial: false,
          sampleCount: 2,
          rawSampleCount: 2,
          distanceM: 30,
          avgSpeedMps: 1,
          maxSpeedMps: 1,
          stationaryRatio: 0,
          quality: WindowQuality.high,
          userLabel: ActivityLabel.walkBrisk,
          userNote: '강변',
          userConfirmed: true,
          placeId: 7,
        ),
      ];
      final exclusion = RouteExclusion(
        id: 'vehicle-1',
        sessionId: session.id,
        startAt: start,
        endAt: start.add(const Duration(minutes: 1)),
        reason: RouteExclusionReason.vehicle,
        createdAt: start,
      );

      final result = SessionPipeline().recalculateCompleted(
        session: session,
        storedSamples: stored,
        exclusions: [exclusion],
        previousWindows: previous,
      );

      expect(stored[2].isFilteredOut, isTrue);
      expect(result.windows.first.userExclusionId, exclusion.id);
      expect(result.windows.first.gapReason, 'user_excluded');
      expect(result.windows.first.rawSampleCount, 2);
      expect(result.windows.first.userLabel, ActivityLabel.walkBrisk);
      expect(result.windows.first.userNote, '강변');
      expect(result.windows.first.placeId, 7);
      expect(result.metrics.durationS, 60);
      expect(result.metrics.totalDistanceM, 0);
      expect(result.metrics.avgSpeedMps.isFinite, isTrue);
    },
  );

  test('live processing preserves the automatic-filter boundary', () {
    final start = DateTime.utc(2026, 8, 21);
    final raw = [
      LocationSample(
        timestamp: start,
        latitude: 37.5,
        longitude: 127,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: start.add(const Duration(seconds: 10)),
        latitude: 38.5,
        longitude: 127,
        accuracyM: 5,
      ),
      LocationSample(
        timestamp: start.add(const Duration(seconds: 20)),
        latitude: 37.5001,
        longitude: 127,
        accuracyM: 5,
      ),
    ];
    final session = WalkSession(
      id: 'live-1',
      startedAt: start,
      timezone: 'Asia/Seoul',
      trackingMode: TrackingMode.balanced,
    );
    final result = SessionPipeline().process(
      session: session,
      rawSamples: raw,
      endedAt: start.add(const Duration(seconds: 20)),
    );
    expect(result.filteredSamples.map((sample) => sample.isFilteredOut), [
      false,
      true,
      false,
    ]);
    expect(result.fragments.map((fragment) => fragment.samples.length), [1, 1]);
    expect(result.metrics.totalDistanceM, 0);
  });
}
