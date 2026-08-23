import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/session_warning.dart';
import 'package:sanbo/platform/notifications/session_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sanbo/session_notifications');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('high-speed show and cancel send isolated kind and id', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    final service = PlatformSessionNotificationService();
    await service.initialize();

    await service.showWarning(
      const SessionWarning(
        kind: SessionWarningKind.highSpeed,
        title: '산책 기록을 계속할까요?',
        message: '이동 속도가 매우 빨라요. 산책을 마쳤다면 기록을 종료해 주세요.',
        actions: {
          SessionWarningAction.stopRecording,
          SessionWarningAction.continueRecording,
        },
      ),
      sessionId: 'session-1',
    );
    await service.cancel(kind: SessionWarningKind.highSpeed);

    final notificationCalls = calls
        .where((call) => call.method != 'ready')
        .toList();
    expect(notificationCalls[0].arguments, containsPair('kind', 'highSpeed'));
    expect(notificationCalls[0].arguments, containsPair('id', 4103));
    expect(
      notificationCalls[0].arguments,
      containsPair('sessionId', 'session-1'),
    );
    expect(notificationCalls[1].arguments, containsPair('id', 4103));
  });

  test('initialize sends the native readiness handshake once', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    final service = PlatformSessionNotificationService();

    await service.initialize();
    await service.initialize();

    expect(calls.map((call) => call.method), ['ready']);
  });

  test(
    'readiness handshake retries after a transient native failure',
    () async {
      var readyAttempts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'ready') {
              readyAttempts++;
              if (readyAttempts == 1) {
                throw PlatformException(code: 'engine_not_ready');
              }
            }
            return null;
          });
      final service = PlatformSessionNotificationService();

      await service.initialize();
      final subscription = service.taps.listen((_) {});
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      expect(readyAttempts, 2);
    },
  );

  test(
    'readiness handshake retries when the native channel is registered late',
    () async {
      var readyAttempts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'ready') {
              readyAttempts++;
              if (readyAttempts == 1) throw MissingPluginException();
            }
            return null;
          });
      final service = PlatformSessionNotificationService();

      await service.initialize();
      final subscription = service.taps.listen((_) {});
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      expect(readyAttempts, 2);
    },
  );

  test(
    'readiness handshake retries after a listener joins an in-flight failure',
    () async {
      var readyAttempts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'ready') {
              readyAttempts++;
              if (readyAttempts == 1) {
                await Future<void>.delayed(const Duration(milliseconds: 10));
                throw PlatformException(code: 'engine_not_ready');
              }
            }
            return null;
          });
      final service = PlatformSessionNotificationService();

      final initialized = service.initialize();
      final subscription = service.taps.listen((_) {});
      addTearDown(subscription.cancel);
      await initialized;
      await pumpEventQueue();

      expect(readyAttempts, 2);
    },
  );

  test(
    'readiness handshake keeps retrying while a late native channel registers',
    () async {
      var readyAttempts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'ready') {
              readyAttempts++;
              if (readyAttempts <= 3) throw MissingPluginException();
            }
            return null;
          });
      final service = PlatformSessionNotificationService();

      await service.initialize();
      final subscription = service.taps.listen((_) {});
      addTearDown(subscription.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(readyAttempts, greaterThanOrEqualTo(4));
    },
  );

  test('cancel all warnings clears every distinct warning id', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    final service = PlatformSessionNotificationService();
    await service.initialize();

    await service.cancelAllWarnings();

    final notificationCalls = calls.where((call) => call.method != 'ready');
    expect(notificationCalls.map((call) => call.method), ['cancel', 'cancel']);
    expect(notificationCalls.map((call) => call.arguments), [
      {'id': 4101},
      {'id': 4103},
    ]);
  });

  test('notificationTapped is emitted exactly once', () async {
    final service = PlatformSessionNotificationService();
    await service.initialize();
    final received = <SessionNotificationTap>[];
    final subscription = service.taps.listen(received.add);
    addTearDown(subscription.cancel);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            const MethodCall('notificationTapped', {
              'kind': 'highSpeed',
              'sessionId': 'session-1',
            }),
          ),
          (_) {},
        );
    await pumpEventQueue();

    expect(received.map((event) => event.kind), [SessionWarningKind.highSpeed]);
    expect(received.single.sessionId, 'session-1');
  });

  test(
    'a tap received before subscription is delivered once to the first listener',
    () async {
      final service = PlatformSessionNotificationService();
      await service.initialize();

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(
              const MethodCall('notificationTapped', {
                'kind': 'highSpeed',
                'sessionId': 'session-1',
              }),
            ),
            (_) {},
          );

      final received = <SessionNotificationTap>[];
      final subscription = service.taps.listen(received.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      expect(received.map((event) => event.kind), [
        SessionWarningKind.highSpeed,
      ]);
      expect(received.single.sessionId, 'session-1');
    },
  );

  test('notificationTapped without a session id is ignored', () async {
    final service = PlatformSessionNotificationService();
    await service.initialize();
    final received = <SessionNotificationTap>[];
    final subscription = service.taps.listen(received.add);
    addTearDown(subscription.cancel);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            const MethodCall('notificationTapped', {'kind': 'highSpeed'}),
          ),
          (_) {},
        );
    await pumpEventQueue();

    expect(received, isEmpty);
  });

  test('permission and display failures remain nonfatal', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'denied');
        });
    final service = PlatformSessionNotificationService();
    await service.initialize();

    expect(
      await service.requestPermission(),
      NotificationPermissionResult.failed,
    );
    await service.showWarning(
      const SessionWarning(
        kind: SessionWarningKind.highSpeed,
        title: '제목',
        message: '내용',
        actions: {},
      ),
    );
    await service.cancel(kind: SessionWarningKind.highSpeed);
  });

  test('generic native channel failures remain nonfatal', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw StateError('native channel unavailable');
        });
    final service = PlatformSessionNotificationService();

    await service.initialize();
    expect(
      await service.requestPermission(),
      NotificationPermissionResult.failed,
    );
    await service.showCompletion(title: '제목', body: '내용');
    await service.cancelAllWarnings();
  });
}
