import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/platform/session_timezone.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sanbo/session_notifications');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses the native IANA timezone for new sessions', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getTimezone');
          return 'America/New_York';
        });

    expect(await currentSessionTimezone(), 'America/New_York');
  });

  test('falls back when native timezone is unavailable', () async {
    expect(await currentSessionTimezone(), defaultSessionTimezone);
  });
}
