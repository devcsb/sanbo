import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/application/session/session_persistence_coordinator.dart';
import 'package:sanbo/domain/models/location_sample.dart';

void main() {
  test(
    'checkpoint failure retains the complete pending batch for retry',
    () async {
      var failNextInsert = false;
      final inserted = <LocationSample>[];
      const generation = 1;
      final coordinator = SessionPersistenceCoordinator(
        insertSamples: (sessionId, samples) async {
          if (failNextInsert) {
            failNextInsert = false;
            throw StateError('temporary write failure');
          }
          inserted.addAll(samples);
        },
        isGenerationCurrent: (value) => value == generation,
      );
      final samples = [_sample(0), _sample(1), _sample(2)];

      failNextInsert = true;
      await coordinator.checkpoint(
        sessionId: 'session',
        samples: samples,
        generation: generation,
      );
      expect(samples, hasLength(3));
      expect(inserted, isEmpty);

      await coordinator.checkpoint(
        sessionId: 'session',
        samples: samples,
        generation: generation,
      );
      expect(samples, isEmpty);
      expect(inserted, hasLength(3));
    },
  );

  test('stale generation cannot write after a new session starts', () async {
    final inserted = <LocationSample>[];
    var generation = 1;
    final coordinator = SessionPersistenceCoordinator(
      insertSamples: (sessionId, samples) async => inserted.addAll(samples),
      isGenerationCurrent: (value) => value == generation,
    );
    final samples = [_sample(0)];

    generation = 2;
    await coordinator.checkpoint(
      sessionId: 'session',
      samples: samples,
      generation: 1,
    );

    expect(samples, hasLength(1));
    expect(inserted, isEmpty);
  });
}

LocationSample _sample(int offset) {
  return LocationSample(
    timestamp: DateTime(2026, 8, 29, 10, 0, offset),
    latitude: 37.5 + offset / 10000,
    longitude: 127.0,
    accuracyM: 5,
  );
}
