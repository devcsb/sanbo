import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/pipeline/segment_merger.dart';

MinuteWindow _w({
  required DateTime start,
  required ActivityLabel label,
  double conf = 0.7,
  double distance = 60,
  int samples = 10,
  WindowQuality quality = WindowQuality.high,
  bool userConfirmed = false,
  ActivityLabel? userLabel,
}) {
  return MinuteWindow(
    windowStart: start,
    durationS: 60,
    partial: false,
    sampleCount: samples,
    rawSampleCount: samples,
    distanceM: distance,
    avgSpeedMps: 1.2,
    maxSpeedMps: 1.4,
    stationaryRatio: 0.05,
    quality: quality,
    hypothesisLabel: label,
    hypothesisConfidence: conf,
    userLabel: userLabel,
    userConfirmed: userConfirmed,
  );
}

void main() {
  test('merges consecutive same-label walk minutes into one segment', () {
    final t0 = DateTime(2026, 7, 12, 14, 0);
    final windows = [
      _w(start: t0, label: ActivityLabel.walkSteady),
      _w(start: t0.add(const Duration(minutes: 1)), label: ActivityLabel.walkSteady),
      _w(start: t0.add(const Duration(minutes: 2)), label: ActivityLabel.walkSteady),
      _w(
        start: t0.add(const Duration(minutes: 3)),
        label: ActivityLabel.placeStay,
        conf: 0.55,
        distance: 5,
      ),
    ];
    final segments = SegmentMerger().merge(windows);
    expect(segments.length, 2);
    expect(segments[0].minuteCount, 3);
    expect(segments[0].label, ActivityLabel.walkSteady);
    expect(segments[0].distanceM, closeTo(180, 0.01));
    expect(segments[0].isMultiMinute, isTrue);
    expect(segments[1].label, ActivityLabel.placeStay);
    expect(segments[1].minuteCount, 1);
  });

  test('does not merge unknown minutes without user confirm', () {
    final t0 = DateTime(2026, 7, 12, 15, 0);
    final windows = [
      _w(start: t0, label: ActivityLabel.unknown, conf: 0.2, samples: 1),
      _w(
        start: t0.add(const Duration(minutes: 1)),
        label: ActivityLabel.unknown,
        conf: 0.2,
        samples: 1,
      ),
    ];
    final segments = SegmentMerger().merge(windows);
    expect(segments.length, 2);
  });

  test('merges gap minutes together', () {
    final t0 = DateTime(2026, 7, 12, 16, 0);
    final windows = [
      _w(
        start: t0,
        label: ActivityLabel.unknown,
        quality: WindowQuality.gap,
        samples: 0,
        distance: 0,
        conf: 0,
      ),
      _w(
        start: t0.add(const Duration(minutes: 1)),
        label: ActivityLabel.unknown,
        quality: WindowQuality.gap,
        samples: 0,
        distance: 0,
        conf: 0,
      ),
    ];
    final segments = SegmentMerger().merge(windows);
    expect(segments.length, 1);
    expect(segments.first.minuteCount, 2);
  });

  test('user label drives merge key', () {
    final t0 = DateTime(2026, 7, 12, 17, 0);
    final windows = [
      _w(
        start: t0,
        label: ActivityLabel.walkSteady,
        userLabel: ActivityLabel.cafeOrShop,
        userConfirmed: true,
      ),
      _w(
        start: t0.add(const Duration(minutes: 1)),
        label: ActivityLabel.strollSlow,
        userLabel: ActivityLabel.cafeOrShop,
        userConfirmed: true,
      ),
    ];
    final segments = SegmentMerger().merge(windows);
    expect(segments.length, 1);
    expect(segments.first.label, ActivityLabel.cafeOrShop);
  });
}
