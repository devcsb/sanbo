/// Small, local-only performance counters for one active recording.
///
/// The recorder keeps aggregate counts and durations only. It never stores
/// coordinates, health values, or an unbounded event history, and callers can
/// expose [snapshot] only from a debug/settings surface.
final class SessionDiagnosticsSnapshot {
  const SessionDiagnosticsSnapshot({
    required this.callbackCount,
    required this.flushCount,
    required this.averageCallbackInterval,
    required this.lastFlushDuration,
  });

  final int callbackCount;
  final int flushCount;
  final Duration? averageCallbackInterval;
  final Duration? lastFlushDuration;
}

final class SessionDiagnostics {
  int callbackCount = 0;
  int flushCount = 0;
  DateTime? _lastCallbackAt;
  int _intervalCount = 0;
  int _intervalTotalUs = 0;
  Duration? _lastFlushDuration;

  void reset() {
    callbackCount = 0;
    flushCount = 0;
    _lastCallbackAt = null;
    _intervalCount = 0;
    _intervalTotalUs = 0;
    _lastFlushDuration = null;
  }

  void recordCallback(DateTime observedAt) {
    callbackCount++;
    final previous = _lastCallbackAt;
    if (previous != null) {
      final interval = observedAt.difference(previous);
      if (!interval.isNegative) {
        _intervalCount++;
        _intervalTotalUs += interval.inMicroseconds;
      }
    }
    _lastCallbackAt = observedAt;
  }

  Future<void> measureFlush(Future<void> Function() operation) async {
    final stopwatch = Stopwatch()..start();
    try {
      await operation();
    } finally {
      stopwatch.stop();
      flushCount++;
      _lastFlushDuration = Duration(
        microseconds: stopwatch.elapsedMicroseconds,
      );
    }
  }

  SessionDiagnosticsSnapshot snapshot() {
    return SessionDiagnosticsSnapshot(
      callbackCount: callbackCount,
      flushCount: flushCount,
      averageCallbackInterval: _intervalCount == 0
          ? null
          : Duration(microseconds: _intervalTotalUs ~/ _intervalCount),
      lastFlushDuration: _lastFlushDuration,
    );
  }
}
