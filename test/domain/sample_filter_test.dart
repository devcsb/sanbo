import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/pipeline/sample_filter.dart';

void main() {
  test('filters low accuracy samples', () {
    final t0 = DateTime(2026, 7, 12, 10, 0, 0);
    final raw = [
      LocationSample(
        timestamp: t0,
        latitude: 37.5,
        longitude: 127.0,
        accuracyM: 10,
      ),
      LocationSample(
        timestamp: t0.add(const Duration(seconds: 4)),
        latitude: 37.5001,
        longitude: 127.0,
        accuracyM: 120,
      ),
      LocationSample(
        timestamp: t0.add(const Duration(seconds: 8)),
        latitude: 37.5002,
        longitude: 127.0,
        accuracyM: 15,
      ),
    ];
    final out = SampleFilter().apply(raw);
    expect(out.length, 3);
    expect(out[0].isFilteredOut, isFalse);
    expect(out[1].isFilteredOut, isTrue);
    expect(out[2].isFilteredOut, isFalse);
  });

  test('filters GPS jump as impossible speed', () {
    final t0 = DateTime(2026, 7, 12, 10, 0, 0);
    final raw = [
      LocationSample(
        timestamp: t0,
        latitude: 37.5,
        longitude: 127.0,
        accuracyM: 5,
      ),
      // ~1 degree lon jump in 1s → hundreds of m/s
      LocationSample(
        timestamp: t0.add(const Duration(seconds: 1)),
        latitude: 37.5,
        longitude: 128.0,
        accuracyM: 5,
      ),
    ];
    final out = SampleFilter().apply(raw);
    expect(out[0].isFilteredOut, isFalse);
    expect(out[1].isFilteredOut, isTrue);
  });
}
