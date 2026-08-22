import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/walk_repository.dart';
import '../../domain/models/location_sample.dart';
import '../../domain/models/session_warning.dart';
import '../../domain/models/tracking_mode.dart';
import '../../domain/models/walk_session.dart';
import '../../domain/pipeline/geo.dart';
import '../../domain/pipeline/sample_filter.dart';
import '../../domain/services/session_guard.dart';
import '../../domain/services/session_pipeline.dart';
import '../../platform/location/location_engine.dart';
import '../../platform/notifications/session_notification_service.dart';
import '../../platform/session_timezone.dart';
import '../history/history_providers.dart';
import 'session_maintenance_queue.dart';

const _highSpeedWarning = SessionWarning(
  kind: SessionWarningKind.highSpeed,
  title: '산책 기록을 계속할까요?',
  message: '이동 속도가 매우 빨라요. 산책을 마쳤다면 기록을 종료해 주세요.',
  actions: {
    SessionWarningAction.stopRecording,
    SessionWarningAction.continueRecording,
  },
);

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
    this.notice,
    this.activeWarning,
    this.needsRecovery = false,
    this.canRetryRecovery = false,
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

  /// Calm neutral note shown on the idle home (e.g. a benign "walk not saved"
  /// outcome). Distinct from [errorMessage], which renders as a red banner.
  final String? notice;

  /// A time-sensitive warning shown while a walk is still recording.
  final SessionWarning? activeWarning;

  /// Incomplete session recovered from disk (UX-H04).
  final bool needsRecovery;

  /// The last recovery lookup failed; retry must not start a new walk.
  final bool canRetryRecovery;

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
    String? notice,
    SessionWarning? activeWarning,
    bool? needsRecovery,
    bool? canRetryRecovery,
    bool clearError = false,
    bool clearSession = false,
    bool clearNotice = false,
    bool clearActiveWarning = false,
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
      notice: clearNotice ? null : (notice ?? this.notice),
      activeWarning: clearActiveWarning
          ? null
          : (activeWarning ?? this.activeWarning),
      needsRecovery: needsRecovery ?? this.needsRecovery,
      canRetryRecovery: canRetryRecovery ?? this.canRetryRecovery,
    );
  }
}

final locationEngineProvider = Provider<LocationEngine>((ref) {
  throw UnimplementedError('LocationEngine must be overridden at bootstrap');
});

final sessionPipelineProvider = Provider<SessionPipeline>((ref) {
  return SessionPipeline();
});

final sessionNotificationServiceProvider = Provider<SessionNotificationService>(
  (ref) {
    return PlatformSessionNotificationService();
  },
);

final sessionGuardPolicyProvider = Provider<SessionGuardPolicy>((ref) {
  return const SessionGuardPolicy();
});

final sessionClockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

final sessionTimezoneProvider = Provider<Future<String> Function()>((ref) {
  return currentSessionTimezone;
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
  double _liveSpeedMps = 0;
  double? _lastAccuracyM;
  int _validSampleCount = 0;

  final SampleFilter _liveFilter = SampleFilter();
  late SessionGuard _sessionGuard;
  late SessionNotificationService _notifications;
  late DateTime Function() _clock;
  late Future<String> Function() _timezone;
  final _maintenanceQueue = SessionMaintenanceQueue();
  var _sessionGeneration = 0;
  var _endingSession = false;
  bool _autoStopInProgress = false;
  bool _highSpeedWarningPublished = false;
  bool _appForeground = true;
  bool _appInactive = false;
  bool _locationStreamFailed = false;
  bool _streamEndedDuringStart = false;
  bool _restorationComplete = false;
  bool _restoring = false;
  Future<void>? _restoreOperation;
  Future<void>? _locationFailureCleanup;
  SessionNotificationTap? _pendingNotificationTap;

  static const _checkpointEvery = Duration(seconds: 30);
  static const _maxObservedLiveGap = trustedLocationGap;
  static const _minLiveSegmentDistanceM = minMeaningfulSegmentDistanceM;

  @override
  LiveSessionState build() {
    _sessionGuard = SessionGuard(policy: ref.read(sessionGuardPolicyProvider));
    _notifications = ref.read(sessionNotificationServiceProvider);
    _clock = ref.read(sessionClockProvider);
    _timezone = ref.read(sessionTimezoneProvider);
    ref.onDispose(() {
      _ticker?.cancel();
      _ticker = null;
      _checkpointTimer?.cancel();
      _checkpointTimer = null;
      _firstFixTimer?.cancel();
      _firstFixTimer = null;
      unawaited(_maintenanceQueue.close());
      unawaited(_notifications.cancelAllWarnings());
      unawaited(_sampleSub?.cancel() ?? Future<void>.value());
      _sampleSub = null;
    });
    return const LiveSessionState();
  }

  /// Call after app start (bootstrap) to recover incomplete sessions.
  Future<void> restoreIfNeeded() {
    final ongoing = _restoreOperation;
    if (ongoing != null) return ongoing;

    final operation = _restoreIfNeeded();
    _restoreOperation = operation;
    unawaited(
      operation.then<void>(
        (_) {
          if (identical(_restoreOperation, operation)) {
            _restoreOperation = null;
          }
        },
        onError: (Object _, StackTrace _) {
          if (identical(_restoreOperation, operation)) {
            _restoreOperation = null;
          }
        },
      ),
    );
    return operation;
  }

  Future<void> _restoreIfNeeded() async {
    if (_restoring) return;
    _restoring = true;
    try {
      await _restoreActive();
    } finally {
      _restoring = false;
      _restorationComplete = true;
      await restorePendingNotificationTap();
    }
  }

  /// Retries a failed recovery lookup without starting a new walk.
  Future<void> retryRecovery() async {
    if (state.isBusy || !state.canRetryRecovery) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await restoreIfNeeded();
    } finally {
      if (state.isBusy) {
        state = state.copyWith(isBusy: false);
      }
    }
  }

  WalkRepository get _repo => ref.read(walkRepositoryProvider);
  LocationEngine get _engine => ref.read(locationEngineProvider);
  SessionPipeline get _pipeline => ref.read(sessionPipelineProvider);

  void _recomputeLiveMetricsFromBuffer() {
    final filtered = _liveFilter.apply(_sessionSamples);
    final valid = filtered.where((s) => !s.isFilteredOut).toList();
    _lastValidSample = valid.isEmpty ? null : valid.last;
    _validSampleCount = valid.length;
    _liveSpeedMps = _liveSpeedFromSamples(valid);
    _lastAccuracyM = _sessionSamples.isEmpty
        ? null
        : _sessionSamples.last.accuracyM;
    _liveDistanceM = _trustedLiveDistance(valid);
  }

  double _trustedLiveDistance(List<LocationSample> valid) {
    var total = 0.0;
    for (var i = 1; i < valid.length; i++) {
      final previous = valid[i - 1];
      final current = valid[i];
      final dt = current.timestamp.difference(previous.timestamp);
      if (dt <= Duration.zero || dt > _maxObservedLiveGap) continue;
      final distance = haversineMeters(
        lat1: previous.latitude,
        lon1: previous.longitude,
        lat2: current.latitude,
        lon2: current.longitude,
      );
      if (distance >= _minLiveSegmentDistanceM) total += distance;
    }
    return total;
  }

  double _liveSpeedFromSamples(List<LocationSample> valid) {
    if (valid.isEmpty) return 0;
    if (valid.length >= 2) {
      final previous = valid[valid.length - 2];
      final current = valid.last;
      final dt = current.timestamp.difference(previous.timestamp);
      if (dt > Duration.zero && dt <= _maxObservedLiveGap) {
        final distance = haversineMeters(
          lat1: previous.latitude,
          lon1: previous.longitude,
          lat2: current.latitude,
          lon2: current.longitude,
        );
        if (distance >= _minLiveSegmentDistanceM) {
          return distance /
              (dt.inMicroseconds / Duration.microsecondsPerSecond);
        }
      }
    }
    final providerSpeed = valid.last.speedMps;
    return providerSpeed != null && providerSpeed.isFinite && providerSpeed > 0
        ? providerSpeed
        : 0;
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
      _sessionGuard.rebuildHighSpeedState(
        samples: _liveFilter.apply(existing),
        observedAt: _clock(),
      );
      state = LiveSessionState(
        session: active,
        isTracking: false,
        needsRecovery: true,
        elapsed: _elapsedSince(active.startedAt),
        sampleCount: _sessionSamples.length,
        validSampleCount: _validSampleCount,
        liveDistanceM: _liveDistanceM,
        statusMessage: existing.isEmpty
            ? '이전에 끝내지 못한 산책이 있어요.'
            : '이전에 끝내지 못한 산책이 있어요. 위치 ${existing.length}개가 저장되어 있습니다.',
      );
    } catch (_) {
      // A storage failure must be visible: silently treating it as "no active
      // session" can make a user believe an in-progress walk disappeared.
      state = state.copyWith(
        errorMessage: '이전 기록을 확인하지 못했어요. 저장 공간을 확인한 뒤 다시 시도해 주세요.',
        statusMessage: '복구할 기록을 확인하지 못했어요.',
        canRetryRecovery: true,
      );
    }
  }

  void clearError() {
    state = state.copyWith(
      clearError: true,
      statusMessage: state.statusMessage,
    );
  }

  void clearNotice() {
    state = state.copyWith(
      clearNotice: true,
      statusMessage: state.statusMessage,
    );
  }

  /// Applies one cold-start notification tap only after persisted session
  /// recovery determines whether that session still exists.
  Future<void> restorePendingNotificationTap() async {
    final tap = _pendingNotificationTap;
    _pendingNotificationTap = null;
    if (tap == null || tap.sessionId != state.session?.id) return;
    _presentNotificationTap(tap);
  }

  void handleNotificationTap(SessionNotificationTap tap) {
    if (tap.kind != SessionWarningKind.highSpeed) return;
    if (!_restorationComplete || _restoring) {
      _pendingNotificationTap = tap;
      return;
    }
    if (tap.sessionId == null || tap.sessionId != state.session?.id) return;
    _presentNotificationTap(tap);
  }

  void _presentNotificationTap(SessionNotificationTap tap) {
    switch (tap.kind) {
      case SessionWarningKind.highSpeed:
        state = state.copyWith(
          activeWarning: _highSpeedWarning,
          statusMessage: '기록 종료 확인 중',
        );
        return;
      case SessionWarningKind.stationary:
      case SessionWarningKind.duration:
        return;
    }
  }

  void _startTicker(DateTime startedAt) {
    _ticker?.cancel();
    if (!_appForeground) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!state.isTracking || !_appForeground) return;
      state = state.copyWith(elapsed: _elapsedSince(startedAt));
    });
  }

  void _startCheckpointTimer() {
    _checkpointTimer?.cancel();
    _checkpointTimer = Timer.periodic(_checkpointEvery, (_) {
      unawaited(_runMaintenance());
    });
  }

  void _startSessionGuard() {
    unawaited(_evaluateSessionGuard(_clock()));
  }

  void _cancelSessionGuard() {
    _sessionGuard.reset();
    _highSpeedWarningPublished = false;
    unawaited(_notifications.cancelAllWarnings());
  }

  Future<void> _runMaintenance() async {
    final generation = _sessionGeneration;
    await _maintenanceQueue.enqueue(() async {
      if (_endingSession || generation != _sessionGeneration) return;
      await _flushPendingSamples(generation: generation);
      if (_endingSession || generation != _sessionGeneration) return;
      await _evaluateSessionGuard(
        _clock(),
        generation: generation,
        deferAutoStop: true,
      );
    });
  }

  int get _checkpointBatchSize => switch (_engine.mode) {
    TrackingMode.batterySaver => 2,
    TrackingMode.balanced => 4,
    TrackingMode.highAccuracy => 8,
  };

  Future<void> _flushPendingSamples({
    required int generation,
    bool allowEnding = false,
  }) async {
    final session = state.session;
    if (session == null ||
        _pendingPersist.isEmpty ||
        generation != _sessionGeneration ||
        (_endingSession && !allowEnding)) {
      return;
    }
    final batch = List<LocationSample>.of(_pendingPersist);
    _pendingPersist.clear();
    try {
      await _repo.insertSamples(session.id, batch);
    } catch (_) {
      // Keep samples in memory; retry on next checkpoint / stop.
      _pendingPersist.insertAll(0, batch);
    }
  }

  Future<void> start({TrackingMode mode = TrackingMode.balanced}) async {
    final restoreOperation = _restoreOperation;
    if (restoreOperation != null) {
      await restoreOperation;
    }
    final failureCleanup = _locationFailureCleanup;
    if (failureCleanup != null) {
      await failureCleanup;
    }
    if (state.isBusy || state.isTracking) return;
    state = state.copyWith(
      isBusy: true,
      clearError: true,
      clearNotice: true,
      canRetryRecovery: false,
      statusMessage: state.needsRecovery ? state.statusMessage : null,
    );
    final LocationPermissionState perm;
    try {
      perm = await _engine.requestPermission();
    } catch (e) {
      state = state.copyWith(
        isBusy: false,
        errorMessage: _locationErrorMessage(e),
      );
      return;
    }
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
    if (perm != LocationPermissionState.granted) {
      state = state.copyWith(
        isBusy: false,
        errorMessage: '위치 권한 상태를 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.',
      );
      return;
    }
    // Request the Android notification permission only after the location
    // dialog has completed. The controller is the single owner of this UX,
    // so the location adapter must remain focused on location permission.
    unawaited(_notifications.requestPermission());

    _endingSession = false;
    _locationStreamFailed = false;
    _streamEndedDuringStart = false;
    _highSpeedWarningPublished = false;
    _sessionGeneration++;
    _maintenanceQueue.reopen();

    WalkSession? session;
    try {
      session = await _repo.getActiveSession();
      final resuming = session != null;
      session ??= await _repo.startSession(
        mode: mode,
        startedAt: _clock(),
        timezone: await _timezone(),
      );

      if (resuming) {
        // Reconcile persisted and memory-only samples. A failed finalization
        // can leave valid fixes only in memory; keep those in the pending
        // queue so the resumed session checkpoints them again before another
        // process death can lose them.
        final existing = await _repo.getSamples(session.id);
        final recovered = _mergeSamples(existing, _sessionSamples);
        _sessionSamples
          ..clear()
          ..addAll(recovered);
        _pendingPersist
          ..clear()
          ..addAll(_missingSamples(existing, recovered));
        _sessionGuard.rebuildHighSpeedState(
          samples: _liveFilter.apply(recovered),
          observedAt: _clock(),
        );
      } else {
        _sessionSamples.clear();
        _pendingPersist.clear();
        _lastValidSample = null;
        _liveDistanceM = 0;
        _liveSpeedMps = 0;
        _lastAccuracyM = null;
        _validSampleCount = 0;
      }

      // Rebuild live metrics from memory buffer.
      _recomputeLiveMetricsFromBuffer();

      await _engine.setMode(mode);
      if (!resuming) {
        _sessionGuard.reset();
      }
      // Listen BEFORE start so seed/first GPS fixes are not dropped on the
      // broadcast stream (real-device cold start race).
      await _sampleSub?.cancel();
      final generation = _sessionGeneration;
      _sampleSub = _engine.samples.listen(
        _onSample,
        onError: (Object e) {
          _handleLocationStreamError(e, generation);
        },
        onDone: () {
          _handleLocationStreamDone(generation);
        },
      );
      try {
        await _engine.start();
        if (_streamEndedDuringStart) {
          throw StateError('location_stream_ended');
        }
      } catch (e) {
        await _sampleSub?.cancel();
        _sampleSub = null;
        try {
          await _engine.stop();
        } catch (_) {
          // Preserve the actionable start error below.
        }
        state = state.copyWith(
          session: session,
          isBusy: false,
          isTracking: false,
          needsRecovery: true,
          errorMessage: _locationErrorMessage(e),
        );
        return;
      }
      _startTicker(session.startedAt);
      _startCheckpointTimer();
      // Stall detector: if still zero samples after 20s, surface actionable help.
      _armFirstFixWatchdog();
      // A real engine can synchronously deliver its first fix before start()
      // returns. Read the live accumulators now rather than using stale values
      // captured before the engine was started.
      final liveDistance = _liveDistanceM;
      final liveValid = _validSampleCount;
      state = LiveSessionState(
        session: session,
        isTracking: true,
        isBusy: false,
        needsRecovery: false,
        elapsed: _elapsedSince(session.startedAt),
        sampleCount: _sessionSamples.length,
        validSampleCount: liveValid,
        liveDistanceM: liveDistance,
        permissionState: perm,
        statusMessage: liveValid > 0 ? '기록 중' : 'GPS 잡는 중',
      );
      _startSessionGuard();
    } catch (e) {
      await _sampleSub?.cancel();
      _sampleSub = null;
      try {
        await _engine.stop();
      } catch (_) {
        // Preserve the primary start failure.
      }
      state = state.copyWith(
        session: session,
        isBusy: false,
        isTracking: false,
        needsRecovery: session != null || state.needsRecovery,
        errorMessage: '시작할 수 없습니다. 잠시 후 다시 시도해 주세요.',
      );
    }
  }

  void _handleLocationStreamError(Object error, int generation) {
    if (!_isTerminalLocationStreamError(error)) {
      if (generation == _sessionGeneration && !_endingSession) {
        state = state.copyWith(
          errorMessage: _locationErrorMessage(error),
          statusMessage: state.isTracking ? state.statusMessage : null,
        );
      }
      return;
    }
    if (generation != _sessionGeneration ||
        _endingSession ||
        _locationStreamFailed) {
      return;
    }
    if (!state.isTracking) {
      if (state.isBusy) _streamEndedDuringStart = true;
      return;
    }
    _locationStreamFailed = true;
    _endingSession = true;
    _sessionGeneration++;
    _cancelSessionGuard();
    _ticker?.cancel();
    _ticker = null;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    _firstFixTimer?.cancel();
    _firstFixTimer = null;
    state = state.copyWith(
      isTracking: false,
      isBusy: false,
      needsRecovery: true,
      clearActiveWarning: true,
      errorMessage: _locationErrorMessage(error),
      statusMessage: '기록은 기기에 남아 있습니다.',
    );
    final cleanup = _cleanupAfterLocationStreamError();
    _locationFailureCleanup = cleanup;
    unawaited(
      cleanup.whenComplete(() {
        if (identical(_locationFailureCleanup, cleanup)) {
          _locationFailureCleanup = null;
        }
      }),
    );
  }

  bool _isTerminalLocationStreamError(Object error) {
    return error.toString().contains('location_stream_ended');
  }

  void _handleLocationStreamDone(int generation) {
    _handleLocationStreamError(StateError('location_stream_ended'), generation);
  }

  Future<void> _cleanupAfterLocationStreamError() async {
    final subscription = _sampleSub;
    _sampleSub = null;
    await subscription?.cancel();
    try {
      await _engine.stop();
    } catch (_) {
      // The stream has already failed. Keep the recoverable state visible even
      // if the platform adapter also rejects its cleanup call.
    }
    await _maintenanceQueue.close();
    final session = state.session;
    if (session == null || _pendingPersist.isEmpty) return;
    final batch = List<LocationSample>.of(_pendingPersist);
    _pendingPersist.clear();
    try {
      await _repo.insertSamples(session.id, batch);
    } catch (_) {
      _pendingPersist.insertAll(0, batch);
    }
  }

  void _onSample(LocationSample rawSample) {
    if (_endingSession) return;
    final sample = rawSample.normalizedMetadata();
    _sessionSamples.add(sample);
    _pendingPersist.add(sample);

    // Incremental filter vs last accepted sample (avoids O(n^2) on long walks).
    final prev = _lastValidSample;
    // Guard against out-of-order fixes (clock adjust / provider reordering):
    // the filter sorts ascending, so an older-than-prev sample would otherwise
    // re-accept `prev`, spuriously bumping the valid count and rewinding
    // _lastValidSample. Skip the incremental step; stop() reprocesses the full
    // sorted set anyway.
    final ordered = prev == null || sample.timestamp.isAfter(prev.timestamp);
    final probe = prev == null ? [sample] : [prev, sample];
    final marked = _liveFilter.apply(probe).last;
    double? segmentSpeed;
    SessionGuardObservation? observation;
    var acceptedByIncrementalFilter = false;
    if (ordered && !marked.isFilteredOut) {
      acceptedByIncrementalFilter = true;
      if (prev != null) {
        final dtUs = marked.timestamp.difference(prev.timestamp).inMicroseconds;
        if (dtUs > 0) {
          final d = haversineMeters(
            lat1: prev.latitude,
            lon1: prev.longitude,
            lat2: marked.latitude,
            lon2: marked.longitude,
          );
          // Match pathDistanceMeters jitter floor (1.5 m).
          if (dtUs <= _maxObservedLiveGap.inMicroseconds &&
              d >= _minLiveSegmentDistanceM) {
            _liveDistanceM += d;
            segmentSpeed = d / (dtUs / Duration.microsecondsPerSecond);
          }
        }
      }
      _lastValidSample = marked;
      _validSampleCount += 1;
      observation = _sessionGuard.observe(marked, observedAt: _clock());
    } else {
      _sessionGuard.interruptHighSpeedContinuity();
    }

    final providerSpeed = sample.speedMps;
    if (segmentSpeed != null) {
      // Android fused fixes frequently report 0 m/s while the coordinates
      // are moving. Prefer the measured segment whenever it is trustworthy.
      _liveSpeedMps = segmentSpeed;
    } else if (ordered &&
        !marked.isFilteredOut &&
        providerSpeed != null &&
        providerSpeed.isFinite &&
        providerSpeed > 0) {
      _liveSpeedMps = providerSpeed;
    } else if (ordered && !marked.isFilteredOut && prev != null) {
      // A valid stationary/duplicate fix should not leave the previous
      // walking speed on screen indefinitely.
      _liveSpeedMps = 0;
    }
    _lastAccuracyM = sample.accuracyM ?? _lastAccuracyM;

    if (_sessionSamples.isNotEmpty) {
      _firstFixTimer?.cancel();
      _firstFixTimer = null;
    }
    final clearVisibleStationaryWarning =
        observation?.clearedStationaryWarning == true &&
        state.activeWarning?.kind == SessionWarningKind.stationary;
    // Native location recording continues in the background, but rebuilding
    // the Riverpod/UI tree for every GPS fix does not. The latest aggregates
    // are published once when the app returns to the foreground.
    if (!_appInactive && (_appForeground || clearVisibleStationaryWarning)) {
      state = state.copyWith(
        sampleCount: _sessionSamples.length,
        validSampleCount: _validSampleCount,
        liveSpeedMps: _liveSpeedMps,
        liveDistanceM: _liveDistanceM,
        lastAccuracyM: _lastAccuracyM,
        statusMessage: _validSampleCount == 0 ? 'GPS 보정 중' : '기록 중',
        clearError: true,
        clearActiveWarning: clearVisibleStationaryWarning,
      );
    }
    if (clearVisibleStationaryWarning) {
      unawaited(_notifications.cancel(kind: SessionWarningKind.stationary));
    }
    if (acceptedByIncrementalFilter) {
      unawaited(
        _evaluateSessionGuard(_clock(), generation: _sessionGeneration),
      );
    }
    // Sample-count checkpoints keep persistence and safety limits moving even
    // when periodic Dart timers are throttled by Android/iOS power management.
    if (_pendingPersist.length >= _checkpointBatchSize) {
      unawaited(_runMaintenance());
    }
  }

  Future<void> _evaluateSessionGuard(
    DateTime now, {
    int? generation,
    bool deferAutoStop = false,
  }) async {
    final expectedGeneration = generation ?? _sessionGeneration;
    final session = state.session;
    if (session == null ||
        !state.isTracking ||
        state.isBusy ||
        _endingSession ||
        expectedGeneration != _sessionGeneration ||
        _autoStopInProgress) {
      return;
    }
    final decision = _sessionGuard.evaluate(
      startedAt: session.startedAt,
      now: now,
    );
    switch (decision.event) {
      case SessionGuardEvent.none:
        return;
      case SessionGuardEvent.stationaryWarning:
        const warning = SessionWarning(
          kind: SessionWarningKind.stationary,
          title: '산책을 계속 기록할까요?',
          message: '한곳에 20분 이상 머물고 있어요. 정지 상태가 30분 이어지면 자동으로 저장하고 종료합니다.',
          actions: {SessionWarningAction.continueRecording},
        );
        state = state.copyWith(
          activeWarning: warning,
          statusMessage: '정지 상태 확인 중',
        );
        await _notifications.showWarning(warning, sessionId: session.id);
        return;
      case SessionGuardEvent.stationaryLimit:
        if (deferAutoStop) {
          unawaited(
            _autoStop(completionNotice: '한곳에 30분 머물러 산책을 자동으로 저장하고 종료했어요.'),
          );
        } else {
          await _autoStop(completionNotice: '한곳에 30분 머물러 산책을 자동으로 저장하고 종료했어요.');
        }
        return;
      case SessionGuardEvent.durationWarning:
        const warning = SessionWarning(
          kind: SessionWarningKind.duration,
          title: '산책 기록이 곧 종료돼요',
          message: '산책 기록이 4시간 45분을 넘었어요. 총 5시간이 되면 자동으로 저장하고 종료합니다.',
          actions: {},
        );
        state = state.copyWith(
          activeWarning: warning,
          statusMessage: '자동 종료 예정',
        );
        await _notifications.showWarning(warning, sessionId: session.id);
        return;
      case SessionGuardEvent.durationLimit:
        if (deferAutoStop) {
          unawaited(
            _autoStop(completionNotice: '5시간이 지나 산책을 자동으로 저장하고 종료했어요.'),
          );
        } else {
          await _autoStop(completionNotice: '5시간이 지나 산책을 자동으로 저장하고 종료했어요.');
        }
        return;
      case SessionGuardEvent.highSpeedWarning:
        const warning = _highSpeedWarning;
        state = state.copyWith(
          activeWarning: warning,
          statusMessage: '기록 종료 확인 중',
        );
        if (!_appForeground) {
          await _notifications.showWarning(warning, sessionId: session.id);
          _highSpeedWarningPublished = true;
        }
        return;
    }
  }

  Future<void> continueAfterWarning() async {
    final warning = state.activeWarning;
    if (warning == null) return;
    if (warning.kind == SessionWarningKind.highSpeed &&
        !state.isTracking &&
        state.needsRecovery &&
        state.session != null) {
      await start(mode: state.session!.trackingMode);
      if (state.isTracking) {
        // A cold recovery rebuilds the guard from persisted fixes. Continuing
        // is an explicit dismissal of the recovered warning, so clear the
        // pending high-speed state after the engine is armed.
        _sessionGuard.dismissHighSpeedWarning();
        _highSpeedWarningPublished = false;
        state = state.copyWith(clearActiveWarning: true, statusMessage: '기록 중');
        await _notifications.cancel(kind: warning.kind);
      }
      return;
    }
    if (!state.isTracking) return;
    switch (warning.kind) {
      case SessionWarningKind.stationary:
        _sessionGuard.continueStationaryTracking(_clock());
        break;
      case SessionWarningKind.highSpeed:
        _sessionGuard.dismissHighSpeedWarning();
        _highSpeedWarningPublished = false;
        break;
      case SessionWarningKind.duration:
        return;
    }
    state = state.copyWith(clearActiveWarning: true, statusMessage: '기록 중');
    await _notifications.cancel(kind: warning.kind);
  }

  /// Resumes from the recovery card. A recovered high-speed trace is already
  /// a user-visible decision point, so starting it must dismiss the pending
  /// guard event just like the notification's "계속 기록" action does.
  Future<void> resumeRecoveredSession({TrackingMode? mode}) async {
    final recovering =
        state.needsRecovery && state.session != null && !state.isTracking;
    await start(
      mode: mode ?? state.session?.trackingMode ?? TrackingMode.balanced,
    );
    if (!recovering || !state.isTracking) return;
    _sessionGuard.dismissHighSpeedWarning();
    _highSpeedWarningPublished = false;
    if (state.activeWarning?.kind == SessionWarningKind.highSpeed) {
      state = state.copyWith(clearActiveWarning: true, statusMessage: '기록 중');
      await _notifications.cancel(kind: SessionWarningKind.highSpeed);
    }
  }

  Future<WalkSession?> stopFromHighSpeedWarning() async {
    if (state.activeWarning?.kind != SessionWarningKind.highSpeed) return null;
    state = state.copyWith(clearActiveWarning: true);
    await _notifications.cancel(kind: SessionWarningKind.highSpeed);
    return stop();
  }

  Future<void> _autoStop({required String completionNotice}) async {
    if (_autoStopInProgress) return;
    _autoStopInProgress = true;
    try {
      final ended = await stop(completionNotice: completionNotice);
      if (ended != null) {
        ref.read(historyTickProvider.notifier).state++;
        await _notifications.showCompletion(
          title: '산책 기록을 종료했어요',
          body: completionNotice,
        );
        return;
      }

      if (state.needsRecovery && state.errorMessage != null) {
        await _notifications.showWarning(
          const SessionWarning(
            kind: SessionWarningKind.stationary,
            title: '산책 저장을 마치지 못했어요',
            message: '앱을 열어 ‘저장하고 종료’를 다시 눌러 주세요. 기록은 기기에 남아 있습니다.',
            actions: {},
          ),
          sessionId: state.session?.id,
        );
        return;
      }

      await _notifications.showCompletion(
        title: '산책 기록을 종료했어요',
        body: state.notice ?? completionNotice,
      );
    } finally {
      _autoStopInProgress = false;
    }
  }

  void _armFirstFixWatchdog() {
    _firstFixTimer?.cancel();
    final generation = _sessionGeneration;
    _firstFixTimer = Timer(const Duration(seconds: 20), () {
      if (!state.isTracking ||
          _endingSession ||
          generation != _sessionGeneration) {
        return;
      }
      if (state.sampleCount > 0) return;
      state = state.copyWith(
        errorMessage:
            '위치를 아직 받지 못했어요. 기기 위치 서비스와 정확한 위치 권한을 확인하고, '
            '하늘이 보이는 곳에서 잠시 기다려 주세요.',
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
      return 'GPS 신호를 받지 못했어요. 하늘이 보이는 곳에서 다시 시도하고 정확한 위치 권한을 확인해 주세요.';
    }
    if (s.contains('notification') || s.contains('foreground')) {
      return '백그라운드 위치 기록을 시작하지 못했어요. 앱 화면에서 다시 시작하고 위치 권한을 확인해 주세요.';
    }
    return '위치를 받는 중 문제가 생겼습니다. 잠시 후 다시 시도해 주세요.';
  }

  /// Test / recovery helper: inject samples into the live session path.
  void debugIngestSamples(List<LocationSample> samples) {
    for (final s in samples) {
      _onSample(s);
    }
  }

  /// Test helper for deterministic guard boundary checks.
  Future<void> debugEvaluateSessionGuard([DateTime? now]) {
    return _evaluateSessionGuard(now ?? _clock());
  }

  /// Suppress high-frequency presentation work while native GPS collection
  /// continues in the background, then publish one caught-up snapshot.
  /// iOS may emit `inactive` while the app is still visible (for example when
  /// a notification is presented). That transient state must not publish a
  /// background warning or latch it as delivered.
  void setAppInactive() {
    if (_appInactive) return;
    _appInactive = true;
    _ticker?.cancel();
    _ticker = null;
  }

  /// Suppress high-frequency presentation work while native GPS collection
  /// continues in the background, then publish one caught-up snapshot.
  void setAppForeground(bool foreground) {
    final wasInactive = _appInactive;
    _appInactive = false;
    if (_appForeground == foreground && !(foreground && wasInactive)) return;
    _appForeground = foreground;
    if (!foreground) {
      _ticker?.cancel();
      _ticker = null;
      final warning = state.activeWarning;
      final session = state.session;
      if (state.isTracking &&
          session != null &&
          warning?.kind == SessionWarningKind.highSpeed &&
          !_highSpeedWarningPublished) {
        _highSpeedWarningPublished = true;
        unawaited(_notifications.showWarning(warning!, sessionId: session.id));
      }
      unawaited(_runMaintenance());
      return;
    }

    final session = state.session;
    if (session != null && state.isTracking) {
      state = state.copyWith(
        elapsed: _elapsedSince(session.startedAt),
        sampleCount: _sessionSamples.length,
        validSampleCount: _validSampleCount,
        liveSpeedMps: _liveSpeedMps,
        liveDistanceM: _liveDistanceM,
        lastAccuracyM: _lastAccuracyM,
        statusMessage: state.activeWarning == null
            ? (_validSampleCount == 0 ? 'GPS 보정 중' : '기록 중')
            : state.statusMessage,
      );
      _startTicker(session.startedAt);
    }
    unawaited(_runMaintenance());
  }

  Future<WalkSession?> stop({String? completionNotice}) async {
    final session = state.session;
    if (session == null || state.isBusy) return null;
    final generation = ++_sessionGeneration;
    _endingSession = true;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _maintenanceQueue.close();
      _cancelSessionGuard();
      _ticker?.cancel();
      _checkpointTimer?.cancel();
      _firstFixTimer?.cancel();
      _firstFixTimer = null;
      await _sampleSub?.cancel();
      _sampleSub = null;
      final failureCleanup = _locationFailureCleanup;
      if (failureCleanup != null) {
        await failureCleanup;
      } else if (!_locationStreamFailed) {
        await _engine.stop();
      }

      // Flush remaining in-memory samples before rollup.
      await _flushPendingSamples(generation: generation, allowEnding: true);
      // If flush failed and pending still has items, force-insert once more.
      if (_pendingPersist.isNotEmpty) {
        final leftover = List<LocationSample>.of(_pendingPersist);
        try {
          await _repo.insertSamples(session.id, leftover);
          _pendingPersist.clear();
        } catch (_) {
          // Preserve memory-only samples for a retry/resume checkpoint. The
          // in-memory union below can still finalize them in this attempt.
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

      final now = _clock();
      final nowUtc = now.toUtc();
      final maxFutureEnd = nowUtc.add(_sessionGuard.policy.maxSampleFutureSkew);
      final lastTs = raw.isEmpty
          ? now
          : raw.map((s) => s.timestamp).reduce((a, b) => a.isAfter(b) ? a : b);
      final lastUsableTs = raw
          .map((sample) => sample.timestamp.toUtc())
          .where((timestamp) => !timestamp.isAfter(maxFutureEnd))
          .fold<DateTime?>(
            null,
            (latest, timestamp) => latest == null || timestamp.isAfter(latest)
                ? timestamp
                : latest,
          );
      // On recovery (not actively tracking) the app was killed for an unknown
      // gap, so `now` is far past the real end. Cap at the last real sample —
      // otherwise duration/moving-time absorb the dead gap (pace goes wild) and
      // the aggregator emits a gap-window for every dead minute.
      final DateTime effectiveEnd;
      if (!state.isTracking) {
        final candidate = raw.isEmpty ? nowUtc : (lastUsableTs ?? nowUtc);
        effectiveEnd = candidate.isBefore(session.startedAt.toUtc())
            ? session.startedAt
            : candidate;
      } else {
        // Live stop: keep the future-date guard for GPS clocks running ahead
        // (compare on the absolute timeline, UTC GPS vs local wall clock).
        effectiveEnd = lastTs.toUtc().isAfter(nowUtc)
            ? (lastTs.toUtc().isAfter(maxFutureEnd) ? maxFutureEnd : lastTs)
            : now;
      }

      // Empty walk: discard quietly instead of saving a 0 km ghost session.
      if (raw.isEmpty) {
        await _repo.deleteSession(session.id);
        _sessionSamples.clear();
        _pendingPersist.clear();
        _lastValidSample = null;
        _liveDistanceM = 0;
        _liveSpeedMps = 0;
        _lastAccuracyM = null;
        _validSampleCount = 0;
        state = const LiveSessionState(
          notice: 'GPS를 받지 못해 저장할 경로가 없어요. 야외에서 다시 시작해 주세요.',
        );
        return null;
      }

      // Keep provider fixes for audit/debugging, but make the receipt-time
      // boundary explicit before the shared pipeline re-runs its filter. A
      // far-future fix must never become an unfiltered recovery anchor after
      // this stop fails and the session is resumed.
      final pipelineRaw = [
        for (final sample in raw)
          sample.timestamp.toUtc().isBefore(session.startedAt.toUtc()) ||
                  sample.timestamp.toUtc().isAfter(effectiveEnd.toUtc())
              ? sample.copyWith(isFilteredOut: true)
              : sample,
      ];

      final result = _pipeline.process(
        session: session,
        rawSamples: pipelineRaw,
        endedAt: effectiveEnd,
      );

      // Too short / no real movement — don't pollute history with noise.
      final tooShort =
          result.metrics.durationS < 20 &&
          result.metrics.totalDistanceM < 15 &&
          result.metrics.validSampleCount < 5;
      if (tooShort) {
        await _repo.deleteSession(session.id);
        _sessionSamples.clear();
        _pendingPersist.clear();
        _lastValidSample = null;
        _liveDistanceM = 0;
        _liveSpeedMps = 0;
        _lastAccuracyM = null;
        _validSampleCount = 0;
        state = const LiveSessionState(
          notice: '너무 짧아 산책을 저장하지 않았어요. 조금 더 걸은 뒤 종료해 주세요.',
        );
        return null;
      }

      // Persist filter flags (map/detail omit GPS jumps) + windows + completion
      // atomically so a crash mid-finalize can't leave inconsistent state.
      final ended = await _repo.finalizeSession(
        session: session,
        samples: result.filteredSamples,
        windows: result.windows,
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
      _liveSpeedMps = 0;
      _lastAccuracyM = null;
      _validSampleCount = 0;

      final weakGps =
          result.metrics.validSampleCount < 3 ||
          result.metrics.totalDistanceM < 5;
      state = LiveSessionState(
        statusMessage: weakGps ? '기록은 저장됐지만 GPS가 약했어요' : '기록을 저장했어요',
        notice: completionNotice,
      );
      return ended;
    } catch (e) {
      state = state.copyWith(
        isBusy: false,
        isTracking: false,
        needsRecovery: true,
        clearActiveWarning: true,
        errorMessage: '저장에 실패했습니다. 아래 ‘저장하고 종료’를 다시 눌러 주세요.',
        statusMessage: '기록은 기기에 남아 있습니다.',
      );
      return null;
    }
  }

  Future<void> discardActive() async {
    final session = state.session;
    if (session == null || state.isBusy) return;
    ++_sessionGeneration;
    _endingSession = true;
    state = state.copyWith(isBusy: true);
    try {
      await _maintenanceQueue.close();
      _cancelSessionGuard();
      _ticker?.cancel();
      _checkpointTimer?.cancel();
      _firstFixTimer?.cancel();
      _firstFixTimer = null;
      await _sampleSub?.cancel();
      _sampleSub = null;
      final failureCleanup = _locationFailureCleanup;
      if (failureCleanup != null) {
        await failureCleanup;
      } else if (!_locationStreamFailed) {
        await _engine.stop();
      }
      await _repo.deleteSession(session.id);
      _sessionSamples.clear();
      _pendingPersist.clear();
      _lastValidSample = null;
      _liveDistanceM = 0;
      _liveSpeedMps = 0;
      _lastAccuracyM = null;
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

  Duration _elapsedSince(DateTime startedAt) {
    final elapsed = _clock().difference(startedAt);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, LiveSessionState>(
      SessionController.new,
    );
