import 'package:flutter/services.dart';

class HealthConnectSettingsBridge {
  const HealthConnectSettingsBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('sanbo/health_connect');

  final MethodChannel _channel;

  Future<bool> openSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
