import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/walk_repository.dart';
import '../../domain/models/location_sample.dart';
import '../../domain/models/tracking_mode.dart';
import '../../domain/models/walk_session.dart';
import '../../domain/pipeline/geo.dart';
import '../../domain/pipeline/sample_filter.dart';
import '../../domain/services/session_pipeline.dart';
import '../../platform/location/location_engine.dart';

class LiveSessionState {
  const LiveSessionState({
    this.session,
    this.elapsed = Duration.zero,
    this.isTracking = false,
    this.isBusy = false,
    this.liveDistanceM = 0,
    this.liveSpeedMps = 0,
    this.sampleCount = 0,
    this.validSampleCount = 0,
    this.lastAccuracyM,
    this.permissionState = LocationPermissionState.unknown,
    this.errorMessage,
    this.statusMessage,
    this.needsRecovery = false,
  });

  final WalkSession? session;
  final Duration elapsed;
  final bool isTracking;
  /// Prevents double-tap on start/stop (UX-H03).
  final bool isBusy;
  final double liveDistanceM;
  final double liveSpeedMps;
  final int sampleCount;
  /// Samples that pass the soft filter (used for path distance).
  final int validSampleCount;
  final double? lastAccuracyM;
  final LocationPermissionState permissionState;
  final String? errorMessage;
  final String? statusMessage;
  /// Incomplete session recovered from disk (UX-H04).
  final bool needsRecovery;

  LiveSessionState copyWith({
    WalkSession? session,
    Duration? elapsed,
    bool? isTracking,
    bool? isBusy,
    double? liveDistanceM,
    double? liveSpeedMps,
    int? sampleCount,
    int? validSampleCount,
    double? lastAccuracyM,
    LocationPermissionState? permissionState,
    String? errorMessage,
    String? statusMessage,
    bool? needsRecovery,
    bool clearError = false,
    bool clearSession = false,
  }) {
    return LiveSessionState(
      session: clearSession ? null : (session ?? this.session),
      elapsed: elapsed ?? this.elapsed,
      isTracking: isTracking ?? this.isTracking,
      isBusy: isBusy ?? this.isBusy,
      liveDistanceM: liveDistanceM ?? this.liveDistanceM,
      liveSpeedMps: liveSpeedMps ?? this.liveSpeedMps,
      sampleCount: sampleCount ?? this.sampleCount,
      validSampleCount: validSampleCount ?? this.validSampleCount,
      lastAccuracyM: lastAccuracyM ?? this.lastAccuracyM,
      permissionState: permissionState ?? this.permissionState,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      statusMessage: statusMessage,
      needsRecovery: needsRecovery ?? this.needsRecovery,
    );
  }
}

final locationEngineProvider = Provider<LocationEngine>((ref) {
  throw UnimplementedError('LocationEngine must be overridden at bootstrap');
});

final sessionPipelineProvider = Provider<SessionPipeline>((ref) {
  return SessionPipeline();
});

class SessionController extends Notifier<LiveSessionState> {
  Timer? _ticker;
  Timer? _checkpointTimer;
  Timer? _firstFixTimer;
  StreamSubscription<LocationSample>? _sampleSub;
  final List<LocationSample> _sessionSamples = [];
  /// Samples not yet flushed to SQLite.
  final List<LocationSample> _pendingPersist = [];
  /// Last filter-accepted sample for O(1) live distance updates.
  LocationSample? _lastValidSample;
  double _liveDistanceM = 0;
  int _validSampleCount = 0;

  final SampleFilter _liveFilter = SampleFilter();
  bool _flushing = false;

  static const _checkpointEvery = Duration(seconds: 15);

  @override
  LiveSessionState build() {
    ref.onDispose(() {
      _ticker?.cancel();
      _ticker = null;
      _checkpointTimer?.cancel();
      _checkpointTimer = null;
      _firstFixTimer?.cancel();
      _firstFixTimer = null;
      unawaited(_sampleSub?.cancel() ?? Future<void>.value());
      _sampleSub = null;
    });
    return const LiveSessionState();
  }

  /// Call after app start (bootstrap) to recover incomplete sessions.
  Future<void> restoreIfNeeded() => _restoreActive();

  WalkRepository get _repo => ref.read(walkRepositoryProvider);
  LocationEngine get _engine => ref.read(locationEngineProvider);
  SessionPipeline get _pipeline => ref.read(sessionPipelineProvider);


  void _recomputeLiveMetricsFromBuffer() {
    final filtered = _liveFilter.apply(_sessionSamples);
    final valid = filtered.where((s) => !s.isFilteredOut).toList();
    _lastValidSample = valid.isEmpty ? null : valid.last;
    _validSampleCount = valid.length;
    _liveDistanceM = pathDistanceMeters(
      valid.map((s) => (lat: s.latitude, lon: s.longitude)),
    );
  }

  Future<void> _restoreActive() async {
    try {
      final active = await _repo.getActiveSession();
      if (active == null) return;
      final existing = await _repo.getSamples(active.id);
      _sessionSamples
        ..clear()
        ..addAll(existing);
      _pendingPersist.clear();

      _recomputeLiveMetricsFromBuffer();
      state = LiveSessionState(
        session: active,
        isTracking: false,
        needsRecovery: true,
        elapsed: DateTime.now().difference(active.startedAt),
        sampleCount: _sessionSamples.length,
        validSampleCount: _validSampleCount,
        liveDistanceM: _liveDistanceM,
        statusMessage: existing.isEmpty
            ? '이전에 끝내지 못한 산책이 있어요.'
            : '이전에 끝내지 못한 산책이 있어요. 위치 ${existing.length}개가 저장되어 있습니다.',
      );
    } catch (_) {}
  }

  void clearError() {
    state = state.copyWith(clearError: true, statusMessage: state.statusMessage);
  }

  void _startTicker(DateTime startedAt) {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!state.isTracking) return;
      state = state.copyWith(elapsed: DateTime.now().difference(startedAt));
    });
  }

  void _startCheckpointTimer() {
    _checkpointTimer?.cancel();
    _checkpointTimer = Timer.periodic(_checkpointEvery, (_) {
      unawaited(_flushPendingSamples());
    });
  }

  Future<void> _flushPendingSamples() async {
    final session = state.session;
    if (session == null || _pendingPersist.isEmpty || _flushing) return;
    _flushing = true;
    final batch = List<LocationSample>.of(_pendingPersist);
    _pendingPersist.clear();
    try {
      await _repo.insertSamples(session.id, batch);
    } catch (_) {
      // Keep samples in memory; retry on next checkpoint / stop.
      _pendingPersist.insertAll(0, batch);
    } finally {
      _flushing = false;
    }
  }

  Future<void> start({TrackingMode mode = TrackingMode.balanced}) async {
    if (state.isBusy || state.isTracking) return;
    state = state.copyWith(
      isBusy: true,
      clearError: true,
      statusMessage: state.needsRecovery ? state.statusMessage : null,
    );
    final perm = await _engine.requestPermission();
    state = state.copyWith(permissionState: perm);
    if (perm == LocationPermissionState.serviceDisabled) {
      state = state.copyWith(
        isBusy: false,
        errorMessage: '위치 서비스가 꺼져 있습니다. 기기 설정에서 위치를 켠 뒤 다시 시도해 주세요.',
      );
      return;
    }
    if (perm == LocationPermissionState.denied ||
        perm == LocationPermissionState.deniedForever) {
      state = state.copyWith(
        isBusy: false,
        errorMessage: perm == LocationPermissionState.deniedForever
            ? '위치 권한이 꺼져 있습니다. 설정 앱에서 산보에 위치 권한을 허용해 주세요.'
            : '산책을 기록하려면 위치 권한이 필요합니다. 허용을 선택한 뒤 다시 시작해 주세요.',
      );
      return;
    }

    try {
      var session = await _repo.getActiveSession();
      final resuming = session != null;
      session ??= await _repo.startSession(mode: mode);

      if (resuming) {
        // Reload any samples already checkpointed (recovery continue).
        final existing = await _repo.getSamples(session.id);
        if (existing.isNotEmpty && _sessionSamples.isEmpty) {
          _sessionSamples.addAll(existing);
        }
      } else {
        _sessionSamples.clear();
        _lastValidSample = null;
        _liveDistanceM = 0;
        _validSampleCount = 0;
      }
      _pendingPersist.clear();

      // Rebuild live metrics from memory buffer.
      _recomputeLiveMetricsFromBuffer();
      final seedDistance = _liveDistanceM;
      final seedValid = _validSampleCount;

      await _engine.setMode(mode);
      // Listen BEFORE start so seed/first GPS fixes are not dropped on the
      // broadcast stream (real-device cold start race).
      await _sampleSub?.cancel();
      _sampleSub = _engine.samples.listen(
        _onSample,
        onError: (Object e) {
          final msg = _locationErrorMessage(e);
          state = state.copyWith(
            errorMessage: msg,
            statusMessage: state.isTracking ? state.statusMessage : null,
          );
        },
      );
      try {
        await _engine.start();
      } catch (e) {
        await _sampleSub?.cancel();
        _sampleSub = null;
        state = state.copyWith(
          isBusy: false,
          errorMessage: _locationErrorMessage(e),
        );
        return;
      }
      _startTicker(session.startedAt);
      _startCheckpointTimer();
      // Stall detector: if still zero samples after 20s, surface actionable help.
      _armFirstFixWatchdog();
      state = LiveSessionState(
        session: session,
        isTracking: true,
        isBusy: false,
        needsRecovery: false,
        elapsed: DateTime.now().difference(session.startedAt),
        sampleCount: _sessionSamples.length,
        validSampleCount: seedValid,
        liveDistanceM: seedDistance,
        permissionState: perm,
        statusMessage: seedValid > 0 ? '기록 중' : 'GPS 잡는 중',
      );
    } catch (e) {
      state = state.copyWith(
        isBusy: false,
        errorMessage: '시작할 수 없습니다. 잠시 후 다시 시도해 주세요.',
      );
    }
  }

  void _onSample(LocationSample sample) {
    _sessionSamples.add(sample);
    _pendingPersist.add(sample);

    // Incremental filter vs last accepted sample (avoids O(n^2) on long walks).
    final prev = _lastValidSample;
    final probe = prev == null ? [sample] : [prev, sample];
    final marked = _liveFilter.apply(probe).last;
    double? segmentSpeed;
    if (!marked.isFilteredOut) {
      if (prev != null) {
        final dtMs =
            marked.timestamp.difference(prev.timestamp).inMilliseconds;
        if (dtMs > 0) {
          final d = haversineMeters(
            lat1: prev.latitude,
            lon1: prev.longitude,
            lat2: marked.latitude,
            lon2: marked.longitude,
          );
          // Match pathDistanceMeters jitter floor (1.5 m).
          if (d >= 1.5) {
            _liveDistanceM += d;
            segmentSpeed = d / (dtMs / 1000.0);
          }
        }
      }
      _lastValidSample = marked;
      _validSampleCount += 1;
    }

    double? speed = sample.speedMps;
    if (speed == null || speed.isNaN || speed < 0) {
      speed = segmentSpeed;
    }

    if (_sessionSamples.isNotEmpty) {
      _firstFixTimer?.cancel();
      _firstFixTimer = null;
    }
    state = state.copyWith(
      sampleCount: _sessionSamples.length,
      validSampleCount: _validSampleCount,
      liveSpeedMps: speed ?? state.liveSpeedMps,
      liveDistanceM: _liveDistanceM,
      lastAccuracyM: sample.accuracyM ?? state.lastAccuracyM,
      statusMessage: _validSampleCount == 0 ? 'GPS 보정 중' : '기록 중',
      clearError: true,
    );
  }

  void _armFirstFixWatchdog() {
    _firstFixTimer?.cancel();
    _firstFixTimer = Timer(const Duration(seconds: 20), () {
      if (!state.isTracking) return;
      if (state.sampleCount > 0) return;
      state = state.copyWith(
        errorMessage:
            '위치를 아직 받지 못했어요. 알림·위치 권한이 허용돼 있는지 확인하고, '
            '야외에서 다시 시작해 주세요. 설정 앱에서 산보 알림/정확한 위치를 켜 주세요.',
        statusMessage: 'GPS 대기 중',
      );
    });
  }

  String _locationErrorMessage(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('permission')) {
      return '위치 권한이 필요합니다. 허용 후 다시 시작해 주세요.';
    }
    if (s.contains('service') || s.contains('disabled')) {
      return '위치 서비스가 꺼져 있습니다. 기기 설정에서 위치를 켜 주세요.';
    }
    if (s.contains('timeout') || s.contains('no_fix')) {
      return 'GPS 신호를 받지 못했어요. 야외에서 다시 시도하거나 설정에서 위치·알림 권한을 확인해 주세요.';
    }
    if (s.contains('notification') || s.contains('foreground')) {
      return '알림 권한이 없어 위치 기록을 유지할 수 없어요. 설정에서 산보 알림을 허용해 주세요.';
    }
    return '위치를 받는 중 문제가 생겼습니다. 잠시 후 다시 시도해 주세요.';
  }

  /// Test / recovery helper: inject samples into the live session path.
  void debugIngestSamples(List<LocationSample> samples) {
    for (final s in samples) {
      _onSample(s);
    }
  }

  Future<WalkSession?> stop() async {
    final session = state.session;
    if (session == null || state.isBusy) return null;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      _ticker?.cancel();
      _checkpointTimer?.cancel();
      _firstFixTimer?.cancel();
      _firstFixTimer = null;
      await _sampleSub?.cancel();
      _sampleSub = null;
      await _engine.stop();

      // Flush remaining in-memory samples before rollup.
      await _flushPendingSamples();
      // If flush failed and pending still has items, force-insert once more.
      if (_pendingPersist.isNotEmpty) {
        final leftover = List<LocationSample>.of(_pendingPersist);
        _pendingPersist.clear();
        try {
          await _repo.insertSamples(session.id, leftover);
        } catch (_) {
          // Fall back to processing the in-memory union below.
        }
      }

      final fromDb = await _repo.getSamples(session.id);
      // Prefer the union of DB + any still-memory-only samples (dedupe by ts+lat+lon).
      final raw = _mergeSamples(fromDb, _sessionSamples);
      if (fromDb.length < raw.length) {
        // Persist anything missing so history/map survive restart.
        final missing = _missingSamples(fromDb, raw);
        if (missing.isNotEmpty) {
          try {
            await _repo.insertSamples(session.id, missing);
          } catch (_) {}
        }
      }

      final endedAt = DateTime.now();
      final lastTs = raw.isEmpty
          ? endedAt
          : raw.map((s) => s.timestamp).reduce((a, b) => a.isAfter(b) ? a : b);
      // Compare on absolute timeline (handles UTC GPS vs local wall clock).
      final effectiveEnd = lastTs.toUtc().isAfter(endedAt.toUtc())
          ? lastTs.toLocal().add(const Duration(seconds: 1))
          : endedAt;

      // Empty walk: discard quietly instead of saving a 0 km ghost session.
      if (raw.isEmpty) {
        await _repo.deleteSession(session.id);
        _sessionSamples.clear();
        _pendingPersist.clear();
        _lastValidSample = null;
        _liveDistanceM = 0;
        _validSampleCount = 0;
        state = const LiveSessionState(
          statusMessage: '위치 기록이 없어 산책을 저장하지 않았어요',
          errorMessage:
              'GPS를 받지 못해 저장할 경로가 없어요. 야외에서 다시 시작해 주세요.',
        );
        return null;
      }

      final result = _pipeline.process(
        session: session,
        rawSamples: raw,
        endedAt: effectiveEnd,
      );

      // Too short / no real movement — don't pollute history with noise.
      final tooShort = result.metrics.durationS < 20 &&
          result.metrics.totalDistanceM < 15 &&
          result.metrics.validSampleCount < 5;
      if (tooShort) {
        await _repo.deleteSession(session.id);
        _sessionSamples.clear();
        _pendingPersist.clear();
        _lastValidSample = null;
        _liveDistanceM = 0;
        _validSampleCount = 0;
        state = const LiveSessionState(
          statusMessage: '너무 짧아 산책을 저장하지 않았어요',
          errorMessage: '조금 더 걸은 뒤 종료해 주세요. 짧은 기록은 남기지 않아요.',
        );
        return null;
      }

      // Persist filter flags so map/detail omit GPS jumps.
      await _repo.replaceSamples(session.id, result.filteredSamples);
      await _repo.replaceWindows(session.id, result.windows);
      final ended = await _repo.completeSession(
        sessionId: session.id,
        endedAt: effectiveEnd,
        totalDistanceM: result.metrics.totalDistanceM,
        durationS: result.metrics.durationS,
        movingTimeS: result.metrics.movingTimeS,
        stationaryTimeS: result.metrics.stationaryTimeS,
        avgSpeedMps: result.metrics.avgSpeedMps,
        validSampleCount: result.metrics.validSampleCount,
        medianAccuracyM: result.metrics.medianAccuracyM,
      );

      _sessionSamples.clear();
      _pendingPersist.clear();
      _lastValidSample = null;
      _liveDistanceM = 0;
      _validSampleCount = 0;

      final weakGps = result.metrics.validSampleCount < 3 ||
          result.metrics.totalDistanceM < 5;
      state = LiveSessionState(
        statusMessage: weakGps
            ? '기록은 저장됐지만 GPS가 약했어요'
            : '기록이 저장되었습니다',
      );
      return ended;
    } catch (e) {
      state = state.copyWith(
        isBusy: false,
        isTracking: false,
        errorMessage: '저장에 실패했습니다. 다시 종료를 눌러 주세요.',
      );
      return null;
    }
  }

  Future<void> discardActive() async {
    final session = state.session;
    if (session == null || state.isBusy) return;
    state = state.copyWith(isBusy: true);
    try {
      _ticker?.cancel();
      _checkpointTimer?.cancel();
      _firstFixTimer?.cancel();
      _firstFixTimer = null;
      await _sampleSub?.cancel();
      _sampleSub = null;
      await _engine.stop();
      await _repo.deleteSession(session.id);
      _sessionSamples.clear();
      _pendingPersist.clear();
      _lastValidSample = null;
      _liveDistanceM = 0;
      _validSampleCount = 0;
      state = const LiveSessionState();
    } catch (_) {
      state = state.copyWith(
        isBusy: false,
        errorMessage: '삭제에 실패했습니다. 다시 시도해 주세요.',
      );
    }
  }

  List<LocationSample> _mergeSamples(
    List<LocationSample> a,
    List<LocationSample> b,
  ) {
    if (a.isEmpty) return List.of(b);
    if (b.isEmpty) return List.of(a);
    final keys = <String>{};
    final out = <LocationSample>[];
    for (final s in [...a, ...b]) {
      final k = _sampleKey(s);
      if (keys.add(k)) out.add(s);
    }
    out.sort((x, y) => x.timestamp.compareTo(y.timestamp));
    return out;
  }

  List<LocationSample> _missingSamples(
    List<LocationSample> existing,
    List<LocationSample> all,
  ) {
    final keys = existing.map(_sampleKey).toSet();
    return all.where((s) => !keys.contains(_sampleKey(s))).toList();
  }

  String _sampleKey(LocationSample s) =>
      '${s.timestamp.toUtc().millisecondsSinceEpoch}|'
      '${s.latitude.toStringAsFixed(6)}|${s.longitude.toStringAsFixed(6)}';
}

final sessionControllerProvider =
    NotifierProvider<SessionController, LiveSessionState>(SessionController.new);
