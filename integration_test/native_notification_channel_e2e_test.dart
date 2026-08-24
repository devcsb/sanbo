import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'integration: iOS notification channel responds to a native cancel call',
    (tester) async {
      // The app's implicit Flutter engine owns the channel. Give its Dart
      // bootstrap a turn, then call the native method directly so a missing
      // channel cannot be hidden by PlatformSessionNotificationService's
      // best-effort error handling.
      await tester.pump(const Duration(milliseconds: 300));

      const channel = MethodChannel('sanbo/session_notifications');
      await channel.invokeMethod<void>('cancel', {'id': 4103});
    },
  );
}
