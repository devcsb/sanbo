import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import '../../domain/models/session_warning.dart';

enum NotificationPermissionResult { granted, denied, unsupported, failed }

class SessionNotificationTap {
  const SessionNotificationTap(this.kind, {this.sessionId});

  final SessionWarningKind kind;
  final String? sessionId;
}

abstract class SessionNotificationService {
  Future<void> initialize();

  Future<NotificationPermissionResult> requestPermission();

  Stream<SessionNotificationTap> get taps;

  Future<void> showWarning(SessionWarning warning, {String? sessionId});

  Future<void> showCompletion({required String title, required String body});

  Future<void> cancel({required SessionWarningKind kind});

  Future<void> cancelAllWarnings();
}

class PlatformSessionNotificationService implements SessionNotificationService {
  static const _channel = MethodChannel('sanbo/session_notifications');
  static const _warningId = 4101;
  static const _completionId = 4102;
  static const _highSpeedWarningId = 4103;

  late final StreamController<SessionNotificationTap> _tapController =
      StreamController<SessionNotificationTap>.broadcast(
        onListen: _onTapListen,
      );
  SessionNotificationTap? _pendingTap;
  var _initialized = false;
  var _readyAcknowledged = false;
  Future<void>? _readyAttempt;
  Timer? _readinessRetryTimer;
  var _readinessRetryCount = 0;

  static const _readinessRetryDelay = Duration(milliseconds: 100);
  static const _maxReadinessRetries = 20;

  @override
  Stream<SessionNotificationTap> get taps => _tapController.stream;

  @override
  Future<void> initialize() async {
    if (!_initialized) {
      _initialized = true;
      _channel.setMethodCallHandler(_handleMethodCall);
    }
    // Native may receive a cold-start notification before Dart has attached
    // the session controller. Explicitly acknowledge readiness so Android and
    // iOS can flush their own pre-engine tap buffers only after this handler
    // is installed. A transient failure remains retryable from the first tap
    // listener or a later initialize call.
    // Refresh the acknowledgement on every initialization. Native engines
    // can be recreated while the Dart service survives, which resets the
    // native readiness state and otherwise strands cold-start taps in its
    // pending buffer.
    await _tryReady(force: true);
    if (!_readyAcknowledged && _tapController.hasListener) {
      _scheduleReadinessRetry();
    }
  }

  Future<void> _tryReady({bool force = false}) async {
    if (!_initialized) return;
    final active = _readyAttempt;
    if (active != null) {
      await active;
      // A native engine can be recreated while the previous ready call is
      // still in flight. The old Future may complete successfully for the
      // old messenger, so a forced refresh must enqueue a second call after
      // that in-flight operation rather than reusing its result.
      if (force && _initialized) {
        await _tryReady(force: true);
      }
      return;
    }
    if (!force && _readyAcknowledged) return;
    final attempt = _sendReady();
    late final Future<void> trackedAttempt;
    trackedAttempt = attempt.whenComplete(() {
      if (identical(_readyAttempt, trackedAttempt)) {
        _readyAttempt = null;
      }
    });
    _readyAttempt = trackedAttempt;
    await trackedAttempt;
  }

  Future<void> _sendReady() async {
    // A refresh can fail after an earlier engine acknowledged readiness. Clear
    // that old state so listener-driven retries are not suppressed.
    _readyAcknowledged = false;
    try {
      await _channel
          .invokeMethod<void>('ready')
          .timeout(const Duration(seconds: 2));
      _readyAcknowledged = true;
      _readinessRetryCount = 0;
      _readinessRetryTimer?.cancel();
      _readinessRetryTimer = null;
    } on MissingPluginException {
      // The native engine can register this channel after Dart bootstrap,
      // especially on iOS implicit engines. Keep the handshake retryable;
      // unsupported desktop and web targets simply fail this best-effort call.
    } on PlatformException {
      // Notification readiness must never block location recording. Keep this
      // retryable because the native engine may not be ready yet.
    } catch (e, st) {
      _logChannelFailure('ready', e, st);
    }
  }

  @override
  Future<NotificationPermissionResult> requestPermission() async {
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermission');
      return granted == true
          ? NotificationPermissionResult.granted
          : NotificationPermissionResult.denied;
    } on MissingPluginException {
      return NotificationPermissionResult.unsupported;
    } on PlatformException {
      return NotificationPermissionResult.failed;
    } catch (e, st) {
      _logChannelFailure('requestPermission', e, st);
      return NotificationPermissionResult.failed;
    }
  }

  @override
  Future<void> showWarning(SessionWarning warning, {String? sessionId}) {
    return _show(
      id: _idFor(warning.kind),
      kind: warning.kind,
      title: warning.title,
      body: warning.message,
      sessionId: sessionId,
    );
  }

  @override
  Future<void> showCompletion({required String title, required String body}) {
    return _show(id: _completionId, title: title, body: body);
  }

  @override
  Future<void> cancel({required SessionWarningKind kind}) async {
    try {
      await _channel.invokeMethod<void>('cancel', {'id': _idFor(kind)});
    } on MissingPluginException {
      // Desktop, web, and widget tests do not install a native handler.
    } on PlatformException {
      // Notification failures must never interrupt an active walk.
    } catch (e, st) {
      _logChannelFailure('cancel', e, st);
    }
  }

  @override
  Future<void> cancelAllWarnings() async {
    for (final id in const {_warningId, _highSpeedWarningId}) {
      try {
        await _channel.invokeMethod<void>('cancel', {'id': id});
      } on MissingPluginException {
        // Desktop, web, and widget tests do not install a native handler.
      } on PlatformException {
        // Notification failures must never interrupt session cleanup.
      } catch (e, st) {
        _logChannelFailure('cancelAllWarnings', e, st);
      }
    }
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    SessionWarningKind? kind,
    String? sessionId,
  }) async {
    try {
      await _channel.invokeMethod<void>('show', {
        'id': id,
        'title': title,
        'body': body,
        if (kind != null) 'kind': kind.name,
        'sessionId': sessionId,
      });
    } on MissingPluginException {
      // Desktop, web, and widget tests do not install a native handler.
    } on PlatformException {
      // A user can revoke notification permission during a walk.
    } catch (e, st) {
      _logChannelFailure('show', e, st);
    }
  }

  void _logChannelFailure(String method, Object error, StackTrace stack) {
    developer.log(
      'Notification channel call failed: $method',
      name: 'sanbo.notifications',
      error: error,
      stackTrace: stack,
    );
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method != 'notificationTapped') return null;
    final arguments = call.arguments;
    if (arguments is! Map || arguments['kind'] != 'highSpeed') return null;
    final sessionId = arguments['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) return null;
    final tap = SessionNotificationTap(
      SessionWarningKind.highSpeed,
      sessionId: sessionId,
    );
    if (_tapController.hasListener) {
      _tapController.add(tap);
    } else {
      _pendingTap = tap;
    }
  }

  void _flushPendingTap() {
    final tap = _pendingTap;
    _pendingTap = null;
    if (tap != null) _tapController.add(tap);
  }

  void _onTapListen() {
    _flushPendingTap();
    unawaited(_retryReadinessAfterListener());
  }

  Future<void> _retryReadinessAfterListener() async {
    await _tryReady();
    // If the listener joined while the first native handshake was still in
    // flight, that attempt may fail after bootstrap has already returned. A
    // second attempt here closes that race without retrying indefinitely when
    // notifications are unsupported.
    if (!_readyAcknowledged && _tapController.hasListener) {
      await _tryReady();
      if (!_readyAcknowledged) _scheduleReadinessRetry();
    }
  }

  void _scheduleReadinessRetry() {
    if (!_initialized ||
        _readyAcknowledged ||
        !_tapController.hasListener ||
        _readinessRetryTimer != null ||
        _readinessRetryCount >= _maxReadinessRetries) {
      return;
    }
    _readinessRetryTimer = Timer(_readinessRetryDelay, () {
      _readinessRetryTimer = null;
      if (!_initialized || _readyAcknowledged || !_tapController.hasListener) {
        return;
      }
      _readinessRetryCount++;
      unawaited(
        _tryReady().whenComplete(() {
          if (!_readyAcknowledged) _scheduleReadinessRetry();
        }),
      );
    });
  }

  int _idFor(SessionWarningKind kind) => switch (kind) {
    SessionWarningKind.stationary || SessionWarningKind.duration => _warningId,
    SessionWarningKind.highSpeed => _highSpeedWarningId,
  };
}
