import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/walk_repository.dart';
import '../../domain/models/location_sample.dart';
import '../../domain/models/tracking_mode.dart';
import '../../domain/models/walk_session.dart';
import '../../domain/pipeline/geo.dart';
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
  StreamSubscription<LocationSample>? _sampleSub;
  final List<LocationSample> _sessionSamples = [];
  LocationSample? _lastSample;

  @override
  LiveSessionState build() {
    ref.onDispose(() {
      _ticker?.cancel();
      _ticker = null;
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

  Future<void> _restoreActive() async {
    try {
      final active = await _repo.getActiveSession();
      if (active == null) return;
      state = LiveSessionState(
        session: active,
        isTracking: false,
        needsRecovery: true,
        elapsed: DateTime.now().difference(active.startedAt),
        statusMessage: '이전에 끝내지 못한 산책이 있어요.',
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

  Future<void> start({TrackingMode mode = TrackingMode.balanced}) async {
    if (state.isBusy) return;
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
      session ??= await _repo.startSession(mode: mode);
      await _engine.setMode(mode);
      await _engine.start();
      _sessionSamples.clear();
      _lastSample = null;
      await _sampleSub?.cancel();
      _sampleSub = _engine.samples.listen(
        _onSample,
        onError: (Object e) {
          state = state.copyWith(
            errorMessage: '위치를 받는 중 문제가 생겼습니다. 잠시 후 다시 시도해 주세요.',
          );
        },
      );
      _startTicker(session.startedAt);
      state = LiveSessionState(
        session: session,
        isTracking: true,
        isBusy: false,
        needsRecovery: false,
        elapsed: DateTime.now().difference(session.startedAt),
        permissionState: perm,
        statusMessage: '기록 중',
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
    var dist = state.liveDistanceM;
    if (_lastSample != null) {
      dist += haversineMeters(
        lat1: _lastSample!.latitude,
        lon1: _lastSample!.longitude,
        lat2: sample.latitude,
        lon2: sample.longitude,
      );
    }
    _lastSample = sample;
    state = state.copyWith(
      sampleCount: _sessionSamples.length,
      liveSpeedMps: sample.speedMps ?? state.liveSpeedMps,
      liveDistanceM: dist,
    );
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
      await _sampleSub?.cancel();
      _sampleSub = null;
      await _engine.stop();

      if (_sessionSamples.isNotEmpty) {
        await _repo.insertSamples(session.id, _sessionSamples);
      }
      final raw = await _repo.getSamples(session.id);
      final endedAt = DateTime.now();
      final lastTs = raw.isEmpty
          ? endedAt
          : raw.map((s) => s.timestamp).reduce((a, b) => a.isAfter(b) ? a : b);
      final effectiveEnd =
          lastTs.isAfter(endedAt) ? lastTs.add(const Duration(seconds: 1)) : endedAt;

      final result = _pipeline.process(
        session: session,
        rawSamples: raw,
        endedAt: effectiveEnd,
      );

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
      state = const LiveSessionState(statusMessage: '기록이 저장되었습니다');
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
      await _engine.stop();
      await _repo.deleteSession(session.id);
      _sessionSamples.clear();
      state = const LiveSessionState();
    } catch (_) {
      state = state.copyWith(
        isBusy: false,
        errorMessage: '삭제에 실패했습니다. 다시 시도해 주세요.',
      );
    }
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, LiveSessionState>(SessionController.new);
