import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/pipeline/activity_inferencer.dart';

MinuteWindow _w({
  double avg = 1.2,
  double dist = 70,
  double stat = 0.05,
  WindowQuality q = WindowQuality.high,
  int samples = 12,
}) {
  return MinuteWindow(
    windowStart: DateTime(2026, 7, 12, 10, 0),
    durationS: 60,
    partial: false,
    sampleCount: samples,
    rawSampleCount: samples,
    distanceM: dist,
    avgSpeedMps: avg,
    maxSpeedMps: avg * 1.2,
    stationaryRatio: stat,
    quality: q,
  );
}

void main() {
  final inf = ActivityInferencer();

  test('walk_steady for moderate pace', () {
    final h = inf.infer(_w());
    expect(h.label, ActivityLabel.walkSteady);
    expect(h.confidence, greaterThan(0.5));
    expect(h.evidence, isNotEmpty);
  });

  test('unknown for gap', () {
    final h = inf.infer(
      _w(q: WindowQuality.gap, samples: 0, avg: 0, dist: 0, stat: 1),
    );
    expect(h.label, ActivityLabel.unknown);
  });

  test('vehicle for high speed', () {
    final h = inf.infer(_w(avg: 12, dist: 500, stat: 0.0));
    expect(h.label, ActivityLabel.vehicle);
  });

  test('cafe when stay + place category', () {
    final h = inf.infer(
      _w(avg: 0.05, dist: 5, stat: 0.9),
      placeCategory: 'cafe',
    );
    expect(h.label, ActivityLabel.cafeOrShop);
  });
}
