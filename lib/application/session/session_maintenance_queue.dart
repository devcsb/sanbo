typedef SessionMaintenanceTask = Future<void> Function();

/// Serializes checkpoint/safety work for one tracking session.
///
/// Location samples can arrive while a SQLite batch is being written. Keeping
/// one latest pending task is enough to catch up without starting an
/// unbounded number of overlapping writes. Closing the queue waits for the
/// active write but drops work that has not started yet.
final class SessionMaintenanceQueue {
  Future<void>? _active;
  SessionMaintenanceTask? _pendingTask;
  var _closed = false;

  bool get isClosed => _closed;

  Future<void> enqueue(SessionMaintenanceTask task) {
    if (_closed) return Future<void>.value();
    _pendingTask = task;
    final active = _active;
    if (active != null) return active;

    final drain = _drain();
    _active = drain;
    return drain;
  }

  Future<void> _drain() async {
    try {
      while (!_closed && _pendingTask != null) {
        final task = _pendingTask!;
        _pendingTask = null;
        await task();
      }
    } finally {
      _pendingTask = null;
      _active = null;
    }
  }

  /// Prevents queued work from starting and waits for the current task.
  Future<void> close() async {
    _closed = true;
    _pendingTask = null;
    final active = _active;
    if (active != null) await active;
  }

  /// Reopens the queue for a new or resumed tracking session.
  void reopen() {
    if (_active != null) {
      throw StateError('유지보수 작업이 끝나기 전에 큐를 다시 열 수 없습니다');
    }
    _closed = false;
  }
}
