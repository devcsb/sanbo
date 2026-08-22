import 'dart:async';

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
        onListen: _flushPendingTap,
      );
  SessionNotificationTap? _pendingTap;
  var _initialized = false;

  @override
  Stream<SessionNotificationTap> get taps => _tapController.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
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
    }
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

  int _idFor(SessionWarningKind kind) => switch (kind) {
    SessionWarningKind.stationary || SessionWarningKind.duration => _warningId,
    SessionWarningKind.highSpeed => _highSpeedWarningId,
  };
}
