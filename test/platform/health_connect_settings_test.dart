import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/platform/activity/health_connect_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bridge returns native boolean result', () async {
    const channel = MethodChannel('sanbo/health_connect');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    expect(await const HealthConnectSettingsBridge().openSettings(), isTrue);
  });

  test(
    'bridge converts native failures into a recoverable false result',
    () async {
      const channel = MethodChannel('sanbo/health_connect');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) => throw PlatformException(code: 'settings_unavailable'),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      expect(await const HealthConnectSettingsBridge().openSettings(), isFalse);
    },
  );
}
