import '../../domain/models/location_sample.dart';
import 'session_maintenance_queue.dart';

typedef SessionSampleWriter =
    Future<void> Function(String sessionId, List<LocationSample> samples);

/// Narrow persistence boundary used by the session facade.
///
/// The controller still owns safety evaluation and the public lifecycle API,
/// while this coordinator owns the mutable pending batch and the one-way
/// retry semantics. [samples] is intentionally mutable: a failed write puts
/// the exact batch back at the front so no fix is silently lost.
final class SessionPersistenceCoordinator {
  SessionPersistenceCoordinator({
    required this.insertSamples,
    required this.isGenerationCurrent,
  });

  final SessionSampleWriter insertSamples;
  final bool Function(int generation) isGenerationCurrent;
  final SessionMaintenanceQueue queue = SessionMaintenanceQueue();
  final List<LocationSample> pendingSamples = [];

  Future<void> checkpoint({
    required String sessionId,
    required List<LocationSample> samples,
    required int generation,
  }) => _write(sessionId: sessionId, samples: samples, generation: generation);

  Future<void> flushForStop({
    required String sessionId,
    required List<LocationSample> samples,
    required int generation,
  }) => _write(sessionId: sessionId, samples: samples, generation: generation);

  Future<void> _write({
    required String sessionId,
    required List<LocationSample> samples,
    required int generation,
  }) async {
    if (samples.isEmpty || !isGenerationCurrent(generation)) return;
    final batch = List<LocationSample>.of(samples, growable: false);
    samples.clear();
    try {
      await insertSamples(sessionId, batch);
    } catch (_) {
      // Keep every item in order for the next checkpoint or final flush.
      samples.insertAll(0, batch);
    }
  }
}
