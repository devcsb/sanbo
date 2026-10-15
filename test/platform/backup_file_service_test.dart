import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/services/app_backup.dart';
import 'package:sanbo/platform/backup/backup_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sanbo/backup_export');
  late Directory temp;
  final bytes = Uint8List.fromList([123, 125]);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sanbo-save-test-');
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await temp.delete(recursive: true);
  });

  PlatformBackupFileService service(TargetPlatform platform) =>
      PlatformBackupFileService(
        platform: platform,
        temporaryDirectory: () async => temp,
        channel: channel,
      );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      'mobile $platform hands a real file to native and cleans it after copying',
      () async {
        String? source;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'save');
              final args = call.arguments as Map;
              source = args['sourcePath'] as String;
              expect(args['fileName'], 'audit.sanbo');
              expect(args.values.whereType<Uint8List>(), isEmpty);
              expect(await File(source!).readAsBytes(), [123, 125]);
              return 'content://test/saved-backup';
            });
        expect(
          await service(platform).save(fileName: 'audit.sanbo', bytes: bytes),
          'content://test/saved-backup',
        );
        expect(await File(source!).exists(), isFalse);
      },
    );
  }

  for (final response in <Object?>[
    null,
    '',
    PlatformException(code: 'export_failed'),
  ]) {
    test('cancel or failure $response cleans only owned files', () async {
      final other = File('${temp.path}/unrelated.txt');
      await other.writeAsString('keep');
      String? source;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            source = (call.arguments as Map)['sourcePath'] as String;
            if (response is PlatformException) throw response;
            return response;
          });
      final result = service(
        TargetPlatform.android,
      ).save(fileName: 'audit.sanbo', bytes: bytes);
      if (response == null) {
        expect(await result, isNull);
      } else {
        await expectLater(result, throwsA(isA<PlatformException>()));
      }
      expect(await File(source!).exists(), isFalse);
      expect(await other.readAsString(), 'keep');
    });
  }

  test(
    'a pending copy retains its source even during a second export',
    () async {
      final firstSeen = Completer<String>();
      final native = Completer<String>();
      var calls = 0;
      String? secondPath;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final source = (call.arguments as Map)['sourcePath'] as String;
            if (calls++ == 0) {
              firstSeen.complete(source);
              return native.future;
            }
            secondPath = source;
            throw PlatformException(code: 'export_busy');
          });
      final adapter = service(TargetPlatform.android);
      final first = adapter.save(fileName: 'audit.sanbo', bytes: bytes);
      final firstPath = await firstSeen.future;
      await _ageDirectory(File(firstPath).parent);
      await expectLater(
        adapter.save(fileName: 'audit.sanbo', bytes: bytes),
        throwsA(isA<PlatformException>()),
      );
      expect(secondPath, isNot(firstPath));
      expect(await File(firstPath).readAsBytes(), [123, 125]);
      expect(await File(secondPath!).exists(), isFalse);
      native.complete('content://test/first');
      expect(await first, 'content://test/first');
      expect(await File(firstPath).exists(), isFalse);
    },
  );

  test('only stale owned operation directories are reclaimed', () async {
    final root = await Directory('${temp.path}/sanbo_exports').create();
    final stale = await Directory('${root.path}/export-old').create();
    await File('${stale.path}/audit.sanbo').writeAsBytes(bytes);
    await _ageDirectory(stale);
    final recent = await Directory('${root.path}/export-recent').create();
    final other = await Directory('${root.path}/unrelated').create();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    await service(
      TargetPlatform.iOS,
    ).save(fileName: 'audit.sanbo', bytes: bytes);
    expect(await stale.exists(), isFalse);
    expect(await recent.exists(), isTrue);
    expect(await other.exists(), isTrue);
  });

  test(
    'invalid names and oversized bytes never create an export file',
    () async {
      final adapter = service(TargetPlatform.android);
      for (final name in [
        '',
        '.',
        '..',
        '../a.sanbo',
        'a/b',
        'a\\b',
        'a\u0000b',
      ]) {
        await expectLater(
          adapter.save(fileName: name, bytes: bytes),
          throwsA(isA<FormatException>()),
        );
      }
      await expectLater(
        adapter.save(
          fileName: 'audit.sanbo',
          bytes: Uint8List(maxBackupBytes + 1),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(await Directory('${temp.path}/sanbo_exports').exists(), isFalse);
    },
  );
}

Future<void> _ageDirectory(Directory directory) async {
  final result = await Process.run('touch', [
    '-t',
    '202001010000',
    directory.path,
  ]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
}
