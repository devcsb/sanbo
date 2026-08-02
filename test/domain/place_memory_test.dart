import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/pipeline/segment_merger.dart';
import 'package:sanbo/domain/services/place_memory.dart';

void main() {
  MinuteWindow window({
    required DateTime start,
    required ActivityLabel label,
    required double latitude,
    required double longitude,
    int samples = 5,
  }) {
    return MinuteWindow(
      windowStart: start,
      durationS: 60,
      partial: false,
      sampleCount: samples,
      rawSampleCount: samples,
      distanceM: 1,
      avgSpeedMps: 0.05,
      maxSpeedMps: 0.1,
      stationaryRatio: 0.95,
      quality: WindowQuality.high,
      centroidLat: latitude,
      centroidLon: longitude,
      hypothesisLabel: label,
      hypothesisConfidence: 0.7,
    );
  }

  test('stay segment exposes weighted place coordinate', () {
    final start = DateTime(2026, 7, 20, 12);
    final windows = [
      window(
        start: start,
        label: ActivityLabel.placeStay,
        latitude: 37,
        longitude: 127,
        samples: 2,
      ),
      window(
        start: start.add(const Duration(minutes: 1)),
        label: ActivityLabel.placeStay,
        latitude: 37.0001,
        longitude: 127.0001,
        samples: 6,
      ),
    ];
    final segment = SegmentMerger().merge(windows).single;
    expect(canRememberPlace(segment), isTrue);
    final coordinate = placeCoordinate(segment);
    expect(coordinate?.latitude, closeTo(37.000075, 0.000001));
    expect(coordinate?.longitude, closeTo(127.000075, 0.000001));
  });

  test('brief stationary minute is not offered as a place', () {
    final segment = SegmentMerger().merge([
      window(
        start: DateTime(2026, 7, 20, 12),
        label: ActivityLabel.stationary,
        latitude: 37,
        longitude: 127,
      ),
    ]).single;
    expect(canRememberPlace(segment), isFalse);
  });
}
