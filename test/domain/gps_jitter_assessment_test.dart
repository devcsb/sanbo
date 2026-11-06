import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/services/gps_jitter_assessment.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';

List<LocationSample> fixes(
  List<double> meters, {
  double? accuracy = 30,
  double? speed = 0,
  int cadence = 10,
  double longitude = 0,
}) => [
  for (var i = 0; i < meters.length; i++)
    LocationSample(
      timestamp: DateTime.utc(2026, 11, 7).add(Duration(seconds: i * cadence)),
      latitude: meters[i] / 111194.92664455874,
      longitude: longitude,
      accuracyM: accuracy,
      speedMps: speed,
    ),
];
void main() {
  test(
    'ordinary circular walking and one reversal are not jitter evidence',
    () {
      final circle = [
        for (var i = 0; i <= 16; i++)
          LocationSample(
            timestamp: DateTime.utc(2026, 11, 7).add(Duration(seconds: i * 3)),
            latitude: 8 * math.sin(i * math.pi / 8) / 111194.92664455874,
            longitude: 8 * math.cos(i * math.pi / 8) / 111194.92664455874,
            accuracyM: 30,
            speedMps: 0,
          ),
      ];
      expect(hasSuspectedGpsJitter(circle), isFalse);
      expect(hasSuspectedGpsJitter(fixes([0, 5, 10, 5, 0])), isFalse);
    },
  );
  test(
    'antimeridian wrapping and invalid or duplicate fixes are handled safely',
    () {
      final boundary = [
        for (var i = 0; i < 5; i++)
          LocationSample(
            timestamp: DateTime.utc(2026, 11, 7).add(Duration(seconds: i * 10)),
            latitude: 0,
            longitude: i.isEven ? 179.99995 : -179.99995,
            accuracyM: 30,
          ),
      ];
      expect(hasSuspectedGpsJitter(boundary), isTrue);
      final invalid = fixes([0, 20, 0, 20, 0]);
      invalid[2] = LocationSample(
        timestamp: invalid[1].timestamp,
        latitude: 0,
        longitude: 0,
        accuracyM: 30,
      );
      expect(hasSuspectedGpsJitter(invalid), isFalse);
      invalid[2] = LocationSample(
        timestamp: invalid[2].timestamp,
        latitude: double.nan,
        longitude: 0,
        accuracyM: 30,
      );
      expect(hasSuspectedGpsJitter(invalid), isFalse);
    },
  );
  test('a filtered fix inside the minute prevents cross-boundary evidence', () {
    final samples = fixes([0, 20, 0, 20, 0, 20, 0]);
    samples[3] = samples[3].copyWith(isFilteredOut: true);
    final result = SessionPipeline().process(
      session: WalkSession(
        id: 'boundary',
        startedAt: samples.first.timestamp,
        timezone: 'UTC',
        trackingMode: TrackingMode.balanced,
        status: SessionStatus.active,
      ),
      rawSamples: samples,
      endedAt: samples.last.timestamp,
    );
    expect(
      result.windows.single.evidence,
      isNot(contains(MinuteWindow.gpsJitterEvidence)),
    );
    expect(result.filteredSamples, hasLength(7));
  });
  test(
    'repeated round trips inside accuracy need review, not silent removal',
    () {
      final samples = fixes([0, 20, 0, 20, 0, 20]);
      expect(hasSuspectedGpsJitter(samples), isTrue);
      final result = SessionPipeline().process(
        session: WalkSession(
          id: 'jitter',
          startedAt: samples.first.timestamp,
          timezone: 'UTC',
          trackingMode: TrackingMode.balanced,
          status: SessionStatus.active,
        ),
        rawSamples: samples,
        endedAt: samples.last.timestamp,
      );
      expect(result.filteredSamples, hasLength(samples.length));
      expect(result.filteredSamples.every((s) => !s.isFilteredOut), isTrue);
      expect(result.metrics.totalDistanceM, closeTo(100, .1));
      expect(result.metrics.movingTimeS, 50);
      expect(
        result.windows.single.evidence,
        contains(MinuteWindow.gpsJitterEvidence),
      );
      expect(result.windows.single.hypothesisLabel, ActivityLabel.unknown);
      expect(result.windows.single.hypothesisConfidence, lessThan(.4));
      expect(result.windows.single.needsGpsReview, isTrue);
    },
  );
  test(
    'straight slow walking remains unflagged even with zero or missing speed',
    () {
      for (final speed in [null, 0.0, .35]) {
        expect(
          hasSuspectedGpsJitter(fixes([0, 2, 4, 6, 8, 10], speed: speed)),
          isFalse,
        );
      }
    },
  );
  test(
    'positive provider movement and precise actual round trips remain unflagged',
    () {
      expect(
        hasSuspectedGpsJitter(fixes([0, 20, 0, 20, 0], speed: .5)),
        isFalse,
      );
      expect(
        hasSuspectedGpsJitter(fixes([0, 20, 0, 20, 0], accuracy: 5)),
        isFalse,
      );
    },
  );
  test(
    'few fixes, short spans, gaps, poor or unknown accuracy need no confident claim',
    () {
      for (final samples in [
        fixes([0, 20, 0, 20]),
        fixes([0, 20, 0, 20, 0], cadence: 4),
        fixes([0, 20, 0, 20, 0], cadence: 31),
        fixes([0, 20, 0, 20, 0], accuracy: null),
        fixes([0, 20, 0, 20, 0], accuracy: double.nan),
        fixes([0, 20, 0, 20, 0], accuracy: 0),
        fixes([0, 20, 0, 20, 0], accuracy: 151),
        fixes([0, 1, 0, 1, 0]),
      ]) {
        expect(hasSuspectedGpsJitter(samples), isFalse);
      }
      final samples = fixes([0, 20, 0, 20, 0]);
      samples[2] = samples[2].copyWith(isFilteredOut: true);
      expect(hasSuspectedGpsJitter(samples), isFalse);
    },
  );
  test('identical GPS cannot distinguish an actual short walk from jitter', () {
    // Warning is deliberately reversible: never turn this into an auto-delete assertion.
    final actualWalkWithMissingSpeed = fixes([0, 20, 0, 20, 0], speed: null);
    expect(hasSuspectedGpsJitter(actualWalkWithMissingSpeed), isTrue);
    expect(actualWalkWithMissingSpeed.every((s) => !s.isFilteredOut), isTrue);
  });
  test('user-confirmed and excluded windows do not repeat the warning', () {
    MinuteWindow window({bool confirmed = false, String? exclusion}) =>
        MinuteWindow(
          windowStart: DateTime.utc(2026),
          durationS: 60,
          partial: false,
          sampleCount: 6,
          rawSampleCount: 6,
          distanceM: 100,
          avgSpeedMps: 2,
          maxSpeedMps: 2,
          stationaryRatio: 0,
          quality: WindowQuality.medium,
          evidence: const [MinuteWindow.gpsJitterEvidence],
          userConfirmed: confirmed,
          userExclusionId: exclusion,
        );
    expect(window().needsGpsReview, isTrue);
    expect(window(confirmed: true).needsGpsReview, isFalse);
    expect(window(exclusion: 'excluded').needsGpsReview, isFalse);
  });
}
