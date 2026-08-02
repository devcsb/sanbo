import 'package:flutter/services.dart';

abstract class SessionNotificationService {
  Future<void> showWarning({required String title, required String body});

  Future<void> showCompletion({required String title, required String body});

  Future<void> cancelWarning();
}

class PlatformSessionNotificationService implements SessionNotificationService {
  static const _channel = MethodChannel('sanbo/session_notifications');
  static const _warningId = 4101;
  static const _completionId = 4102;

  @override
  Future<void> showWarning({
    required String title,
    required String body,
  }) async {
    await _show(id: _warningId, title: title, body: body);
  }

  @override
  Future<void> showCompletion({
    required String title,
    required String body,
  }) async {
    await _show(id: _completionId, title: title, body: body);
  }

  @override
  Future<void> cancelWarning() async {
    try {
      await _channel.invokeMethod<void>('cancel', {'id': _warningId});
    } on MissingPluginException {
      // Non-Android targets and widget tests intentionally have no handler.
    } on PlatformException {
      // Notifications are a convenience; tracking must never fail with them.
    }
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod<void>('show', {
        'id': id,
        'title': title,
        'body': body,
      });
    } on MissingPluginException {
      // Non-Android targets and widget tests intentionally have no handler.
    } on PlatformException {
      // Permission may be revoked while a walk is running. The in-app message
      // remains the source of truth, so notification failure is non-fatal.
    }
  }
}
