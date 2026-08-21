import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/pipeline/geo.dart';
import 'package:sanbo/domain/pipeline/route_partitioner.dart';
import 'package:sanbo/domain/pipeline/window_aggregator.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';

/// Regression: geolocator emits UTC timestamps; session bounds are local.
void main() {
  test('floorToMinute converts UTC to local wall-clock minute', () {
    final local = DateTime(2026, 7, 12, 14, 3, 45);
    final utc = local.toUtc();
    expect(utc.isUtc, isTrue);
    // Without toLocal(), floor would use UTC hour/minute fields.
    final floored = floorToMinute(utc);
    expect(floored.isUtc, isFalse);
    expect(floored, DateTime(2026, 7, 12, 14, 3));
    expect(floored, floorToMinute(local));
  });

  test('UTC GPS samples fill local minute windows (not all gaps)', () {
    // Local session start (same shape as DateTime.now() in production).
    final sessionStart = DateTime(2026, 7, 12, 14, 0, 0);
    expect(sessionStart.isUtc, isFalse);

    // Production-shaped samples: UTC timestamps (geolocator isUtc:true path).
    const degPerMeter = 1 / 111320.0;
    final samples = <LocationSample>[];
    for (var i = 0; i < 30; i++) {
      final localTs = sessionStart.add(Duration(seconds: 5 + i * 4));
      final utcTs = localTs.toUtc();
      expect(utcTs.isUtc, isTrue);
      samples.add(
        LocationSample(
          timestamp: utcTs,
          latitude: 37.5665 + i * 4 * 1.2 * degPerMeter,
          longitude: 126.9780,
          accuracyM: 6,
          speedMps: 1.2,
        ),
      );
    }

    final endedAt = sessionStart.add(const Duration(minutes: 3));
    final partition = RoutePartitioner.partition(
      samples: samples,
      exclusions: const [],
    );
    final windows = WindowAggregator().aggregate(
      partition: partition,
      rawSamples: samples,
      exclusions: const [],
      sessionStart: sessionStart,
      sessionEnd: endedAt,
    );

    expect(windows, isNotEmpty);
    final withSamples = windows.where((w) => w.sampleCount > 0).toList();
    expect(
      withSamples,
      isNotEmpty,
      reason: 'UTC samples must land in local minute buckets, not only gaps',
    );
    expect(withSamples.first.quality, isNot(WindowQuality.gap));
    expect(withSamples.first.distanceM, greaterThan(0));
  });

  test('SessionPipeline with UTC samples yields non-gap activity windows', () {
    final sessionStart = DateTime(2026, 7, 12, 10, 0, 0);
    final samples = <LocationSample>[];
    const degPerMeter = 1 / 111320.0;
    for (var i = 0; i < 40; i++) {
      samples.add(
        LocationSample(
          timestamp: sessionStart.add(Duration(seconds: i * 3)).toUtc(),
          latitude: 37.5 + i * 3 * 1.3 * degPerMeter,
          longitude: 127.0,
          accuracyM: 5,
          speedMps: 1.3,
        ),
      );
    }
    expect(samples.every((s) => s.timestamp.isUtc), isTrue);

    final session = WalkSession(
      id: 'utc-reg',
      startedAt: sessionStart,
      timezone: 'Asia/Seoul',
      trackingMode: TrackingMode.balanced,
    );
    final result = SessionPipeline().process(
      session: session,
      rawSamples: samples,
      endedAt: sessionStart.add(const Duration(minutes: 3)),
    );

    expect(result.metrics.totalDistanceM, greaterThan(50));
    final filled = result.windows.where((w) => w.sampleCount >= 3);
    expect(filled, isNotEmpty);
    expect(
      filled.any((w) => w.hypothesisLabel.name != 'unknown' || w.distanceM > 0),
      isTrue,
    );
  });
}
