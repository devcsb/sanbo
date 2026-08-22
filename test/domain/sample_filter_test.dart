import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/pipeline/sample_filter.dart';

void main() {
  test('filters low accuracy samples after a good anchor exists', () {
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
        accuracyM: 200,
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

  test('keeps first cold-start fix even when accuracy is soft-poor', () {
    final t0 = DateTime(2026, 7, 12, 10, 0, 0);
    final raw = [
      LocationSample(
        timestamp: t0,
        latitude: 37.5,
        longitude: 127.0,
        accuracyM: 120,
      ),
      LocationSample(
        timestamp: t0.add(const Duration(seconds: 4)),
        latitude: 37.5001,
        longitude: 127.0,
        accuracyM: 25,
      ),
    ];
    final out = SampleFilter().apply(raw);
    expect(out[0].isFilteredOut, isFalse, reason: 'cold-start anchor must stay');
    expect(out[1].isFilteredOut, isFalse);
  });

  test('hard-rejects accuracy worse than 500 m', () {
    final t0 = DateTime(2026, 7, 12, 10, 0, 0);
    final raw = [
      LocationSample(
        timestamp: t0,
        latitude: 37.5,
        longitude: 127.0,
        accuracyM: 800,
      ),
    ];
    final out = SampleFilter().apply(raw);
    expect(out.single.isFilteredOut, isTrue);
  });

  test('rejects non-finite and out-of-range coordinates', () {
    final filtered = SampleFilter().apply([
      LocationSample(
        timestamp: DateTime(2026, 1, 1),
        latitude: double.nan,
        longitude: 126.9,
      ),
      LocationSample(
        timestamp: DateTime(2026, 1, 1).add(const Duration(seconds: 8)),
        latitude: 91,
        longitude: 126.9,
      ),
      LocationSample(
        timestamp: DateTime(2026, 1, 1).add(const Duration(seconds: 16)),
        latitude: 37.5,
        longitude: 181,
      ),
    ]);

    expect(filtered, everyElement(isA<LocationSample>()));
    expect(filtered, everyElement(predicate<LocationSample>((s) => s.isFilteredOut)));
  });

  test('rejects invalid accuracy metadata instead of trusting it', () {
    final filtered = SampleFilter().apply([
      LocationSample(
        timestamp: DateTime(2026, 1, 1),
        latitude: 37.5,
        longitude: 126.9,
        accuracyM: double.nan,
      ),
      LocationSample(
        timestamp: DateTime(2026, 1, 1).add(const Duration(seconds: 8)),
        latitude: 37.5,
        longitude: 126.9,
        accuracyM: -1,
      ),
    ]);

    expect(filtered, everyElement(predicate<LocationSample>((s) => s.isFilteredOut)));
  });

  test('preserves an explicit filtered boundary across reprocessing', () {
    final filtered = SampleFilter().apply([
      LocationSample(
        timestamp: DateTime(2026, 1, 1),
        latitude: 37.5,
        longitude: 126.9,
        accuracyM: 5,
        isFilteredOut: true,
      ),
      LocationSample(
        timestamp: DateTime(2026, 1, 1).add(const Duration(seconds: 8)),
        latitude: 37.5001,
        longitude: 126.9,
        accuracyM: 5,
      ),
    ]);

    expect(filtered.first.isFilteredOut, isTrue);
    expect(filtered.last.isFilteredOut, isFalse);
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
