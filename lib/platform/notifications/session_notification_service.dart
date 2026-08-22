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
  var _nativeUnavailable = false;
  Future<void>? _readyAttempt;

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
    await _tryReady();
  }

  Future<void> _tryReady() {
    if (!_initialized || _readyAcknowledged || _nativeUnavailable) {
      return Future<void>.value();
    }
    final active = _readyAttempt;
    if (active != null) return active;
    final attempt = _sendReady();
    _readyAttempt = attempt;
    return attempt.whenComplete(() {
      if (identical(_readyAttempt, attempt)) _readyAttempt = null;
    });
  }

  Future<void> _sendReady() async {
    try {
      await _channel
          .invokeMethod<void>('ready')
          .timeout(const Duration(seconds: 2));
      _readyAcknowledged = true;
    } on MissingPluginException {
      _nativeUnavailable = true;
      // Desktop, web, and widget tests do not install a native handler.
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
    unawaited(_tryReady());
  }

  int _idFor(SessionWarningKind kind) => switch (kind) {
    SessionWarningKind.stationary || SessionWarningKind.duration => _warningId,
    SessionWarningKind.highSpeed => _highSpeedWarningId,
  };
}
