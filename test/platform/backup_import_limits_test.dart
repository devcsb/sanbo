import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/platform/backup/backup_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'stream stops on actual bytes despite small or missing metadata',
    () async {
      var closed = false;
      final stream = StreamController<List<int>>(onCancel: () => closed = true);
      final result = readLimitedBackup(stream.stream, maxBytes: 4);
      stream.add([1, 2, 3]);
      stream.add([4, 5]);
      await expectLater(result, throwsFormatException);
      expect(closed, isTrue);
    },
  );
  test('whole read timeout closes the source', () async {
    var closed = false;
    final stream = StreamController<List<int>>(onCancel: () => closed = true);
    await expectLater(
      readLimitedBackup(
        stream.stream,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(closed, isTrue);
  });
  test('provider I/O failure closes the source', () async {
    var closed = false;
    final stream = StreamController<List<int>>(onCancel: () => closed = true);
    final result = readLimitedBackup(stream.stream);
    stream.add([1]);
    stream.addError(const FileSystemException('provider unavailable'));
    await expectLater(result, throwsA(isA<FileSystemException>()));
    expect(closed, isTrue);
  });
  test(
    'cancellation closes the source before waiting for more bytes',
    () async {
      var closed = false;
      final cancel = Completer<void>();
      final stream = StreamController<List<int>>(onCancel: () => closed = true);
      final result = readLimitedBackup(stream.stream, cancelled: cancel.future);
      cancel.complete();
      await expectLater(result, throwsA(isA<PlatformException>()));
      expect(closed, isTrue);
    },
  );
  test(
    'Android reads only its native cache and releases the operation',
    () async {
      final temp = await Directory.systemTemp.createTemp('sanbo-import-test-');
      addTearDown(() => temp.delete(recursive: true));
      final root = await Directory('${temp.path}/sanbo_imports').create();
      final source = await File(
        '${root.path}/import-owned.sanbo',
      ).writeAsString('{}');
      const channel = MethodChannel('sanbo/backup_import');
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            if (call.method == 'pick') {
              return {
                'sourcePath': source.path,
                'fileName': 'test.sanbo',
                'operationId': (call.arguments as Map)['operationId'],
              };
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = PlatformBackupFileService(
        platform: TargetPlatform.android,
        temporaryDirectory: () async => temp,
        importChannel: channel,
      );
      expect((await service.pick())!.bytes, [123, 125]);
      expect(methods, ['pick', 'release']);
    },
  );
  for (final invalid in ['outside', 'symlink', 'wrong-token']) {
    test('Android rejects $invalid and releases only its own token', () async {
      final temp = await Directory.systemTemp.createTemp('sanbo-import-test-');
      addTearDown(() => temp.delete(recursive: true));
      final root = await Directory('${temp.path}/sanbo_imports').create();
      final outside = await File(
        '${temp.path}/outside.sanbo',
      ).writeAsString('{}');
      final source = invalid == 'symlink'
          ? (await Link(
              '${root.path}/import-link.sanbo',
            ).create(outside.path)).path
          : outside.path;
      const channel = MethodChannel('sanbo/test-invalid-import');
      String? ownToken;
      String? releasedToken;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final id = (call.arguments as Map)['operationId'] as String;
            if (call.method == 'release') {
              releasedToken = id;
              return null;
            }
            ownToken = id;
            return {
              'sourcePath': source,
              'fileName': 'test.sanbo',
              'operationId': invalid == 'wrong-token'
                  ? 'another-operation'
                  : id,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = PlatformBackupFileService(
        platform: TargetPlatform.android,
        temporaryDirectory: () async => temp,
        importChannel: channel,
      );
      await expectLater(service.pick(), throwsFormatException);
      expect(releasedToken, ownToken);
      expect(await outside.readAsString(), '{}');
    });
  }
  test(
    'cancelled read ignores a late result and a busy caller owns no lease',
    () async {
      final temp = await Directory.systemTemp.createTemp('sanbo-import-test-');
      addTearDown(() => temp.delete(recursive: true));
      final root = await Directory('${temp.path}/sanbo_imports').create();
      final source = await File(
        '${root.path}/import-late.sanbo',
      ).writeAsString('{}');
      final reply = Completer<Map<String, Object>>();
      final started = Completer<String>();
      const channel = MethodChannel('sanbo/test-late-import');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final id = (call.arguments as Map)['operationId'] as String;
            calls.add('${call.method}:$id');
            if (call.method == 'pick') {
              started.complete(id);
              return reply.future;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = PlatformBackupFileService(
        platform: TargetPlatform.android,
        temporaryDirectory: () async => temp,
        importChannel: channel,
      );
      final result = service.pick();
      final id = await started.future;
      await expectLater(service.pick(), throwsA(isA<PlatformException>()));
      await service.cancelPick();
      reply.complete({
        'sourcePath': source.path,
        'fileName': 'late.sanbo',
        'operationId': id,
      });
      expect(await result, isNull);
      expect(calls, ['pick:$id', 'cancel:$id', 'release:$id']);
    },
  );
}
