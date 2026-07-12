import 'dart:async';

import '../../domain/models/location_sample.dart';
import '../../domain/models/tracking_mode.dart';
import 'location_engine.dart';

/// Injectable location stream for tests and controlled e2e.
class SyntheticLocationEngine implements LocationEngine {
  SyntheticLocationEngine({
    List<LocationSample>? initialTrace,
    this.permission = LocationPermissionState.granted,
    this.autoPlay = false,
    this.playInterval = const Duration(milliseconds: 20),
  }) : _trace = List.of(initialTrace ?? const []);

  final List<LocationSample> _trace;
  final bool autoPlay;
  final Duration playInterval;
  LocationPermissionState permission;
  TrackingMode _mode = TrackingMode.balanced;
  StreamController<LocationSample>? _controller;
  bool _running = false;
  int _index = 0;

  void setTrace(List<LocationSample> samples) {
    _trace
      ..clear()
      ..addAll(samples);
    _index = 0;
  }

  /// Push one sample while running (tests / live injection).
  void emit(LocationSample sample) {
    if (_running) {
      _controller?.add(sample);
    }
  }

  @override
  Stream<LocationSample> get samples =>
      _controller?.stream ?? const Stream.empty();

  @override
  TrackingMode get mode => _mode;

  @override
  Future<void> setMode(TrackingMode mode) async {
    _mode = mode;
  }

  @override
  Future<LocationPermissionState> checkPermission() async => permission;

  @override
  Future<LocationPermissionState> requestPermission() async => permission;

  @override
  Future<void> start() async {
    await stop();
    _controller = StreamController<LocationSample>.broadcast();
    _running = true;
    _index = 0;
    if (autoPlay && _trace.isNotEmpty) {
      // ignore: unawaited_futures
      _playTrace();
    }
  }

  Future<void> _playTrace() async {
    while (_running && _index < _trace.length) {
      _controller?.add(_trace[_index]);
      _index++;
      await Future<void>.delayed(playInterval);
    }
  }

  /// Emit entire remaining trace immediately (deterministic tests).
  Future<void> emitAllPending() async {
    if (!_running) return;
    while (_index < _trace.length) {
      _controller?.add(_trace[_index]);
      _index++;
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _controller?.close();
    _controller = null;
  }

  @override
  Future<void> dispose() => stop();
}
