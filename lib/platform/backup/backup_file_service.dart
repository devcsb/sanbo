import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/services/app_backup.dart';

class PickedBackupFile {
  const PickedBackupFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

abstract interface class BackupFileService {
  Future<String?> save({required String fileName, required Uint8List bytes});

  Future<PickedBackupFile?> pick();

  Future<void> cancelPick();
}

class PlatformBackupFileService implements BackupFileService {
  PlatformBackupFileService({
    this._platform,
    Future<Directory> Function()? temporaryDirectory,
    MethodChannel? channel,
    MethodChannel? importChannel,
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _channel = channel ?? const MethodChannel('sanbo/backup_export'),
       _importChannel =
           importChannel ?? const MethodChannel('sanbo/backup_import');

  final TargetPlatform? _platform;
  final Future<Directory> Function() _temporaryDirectory;
  final MethodChannel _channel;
  final MethodChannel _importChannel;
  Completer<void>? _pickCancellation;
  String? _pickOperationId;
  bool get _usesAndroidImport =>
      _platform == TargetPlatform.android ||
      (_platform == null && !kIsWeb && Platform.isAndroid);
  static final _activeExports = <String>{};

  bool get _usesNativeExport {
    final platform = _platform;
    if (platform != null) {
      return platform == TargetPlatform.android ||
          platform == TargetPlatform.iOS;
    }
    return !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  }

  static const _backupTypes = <XTypeGroup>[
    XTypeGroup(
      label: '산보 백업',
      extensions: <String>['sanbo', 'json'],
      mimeTypes: <String>['application/json', 'application/octet-stream'],
      uniformTypeIdentifiers: <String>['public.json', 'public.data'],
    ),
  ];

  @override
  Future<String?> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (fileName.trim().isEmpty ||
        fileName == '.' ||
        fileName == '..' ||
        fileName.contains('/') ||
        fileName.contains('\\') ||
        fileName.contains('\u0000')) {
      throw const FormatException('백업 파일 이름이 올바르지 않습니다');
    }
    if (bytes.isEmpty) throw const FormatException('백업 파일이 비어 있습니다');
    if (bytes.length > maxBackupBytes) {
      throw const FormatException('백업 파일이 50MB 제한을 초과합니다');
    }
    if (_usesNativeExport) return _saveNative(fileName, bytes);
    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: fileName.toLowerCase().endsWith('.ndjson')
          ? const [
              XTypeGroup(
                label: '산책 원본 NDJSON',
                extensions: ['ndjson'],
                mimeTypes: ['application/x-ndjson'],
                uniformTypeIdentifiers: ['public.data'],
              ),
            ]
          : _backupTypes,
      confirmButtonText: '저장',
    );
    if (location == null) return null;
    final backup = XFile.fromData(
      bytes,
      mimeType: 'application/json',
      name: fileName,
    );
    await backup.saveTo(location.path);
    return location.path;
  }

  Future<String?> _saveNative(String fileName, Uint8List bytes) async {
    final cache = await _temporaryDirectory();
    final root = await Directory(
      p.join(cache.path, 'sanbo_exports'),
    ).create(recursive: true);
    await _reclaimStaleExports(root);
    final operation = await root.createTemp('export-');
    _activeExports.add(operation.path);
    try {
      final source = File(p.join(operation.path, fileName));
      await source.writeAsBytes(bytes, flush: true);
      final destination = await _channel.invokeMethod<String>('save', {
        'sourcePath': source.path,
        'fileName': fileName,
      });
      if (destination != null && destination.trim().isEmpty) {
        throw PlatformException(code: 'export_failed');
      }
      return destination;
    } finally {
      _activeExports.remove(operation.path);
      try {
        if (await operation.exists()) await operation.delete(recursive: true);
      } on FileSystemException {
        // Preserve the native outcome; a later export reclaims stale cache.
      }
    }
  }

  Future<void> _reclaimStaleExports(Directory root) async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    try {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory ||
            !p.basename(entity.path).startsWith('export-') ||
            _activeExports.contains(entity.path)) {
          continue;
        }
        try {
          if ((await entity.stat()).modified.isBefore(cutoff)) {
            await entity.delete(recursive: true);
          }
        } on FileSystemException {
          // OS cache reclamation can race this bounded housekeeping pass.
        }
      }
    } on FileSystemException {
      // Preparing the new file still reports any actual cache write failure.
    }
  }

  @override
  Future<void> cancelPick() async {
    final cancellation = _pickCancellation;
    if (cancellation == null) return;
    if (!cancellation.isCompleted) cancellation.complete();
    if (_usesAndroidImport) {
      await _importChannel.invokeMethod<void>('cancel', {
        'operationId': _pickOperationId,
      });
    }
  }

  @override
  Future<PickedBackupFile?> pick() async {
    if (_pickCancellation != null) throw PlatformException(code: 'import_busy');
    final cancellation = Completer<void>();
    _pickCancellation = cancellation;
    final operationId = const Uuid().v4();
    _pickOperationId = operationId;
    try {
      if (_usesAndroidImport) {
        final picked = await _importChannel.invokeMapMethod<String, dynamic>(
          'pick',
          {'operationId': operationId},
        );
        if (picked == null) return null;
        final token = picked['operationId'];
        if (token != operationId) {
          throw const FormatException('가져오기 작업을 확인할 수 없어요');
        }
        final source = picked['sourcePath'];
        final name = picked['fileName'];
        if (source is! String || name is! String) {
          throw const FormatException('백업 파일을 확인할 수 없어요');
        }
        final cache = await _temporaryDirectory();
        final root = await Directory(
          p.join(cache.path, 'sanbo_imports'),
        ).resolveSymbolicLinks();
        final canonical = await File(source).resolveSymbolicLinks();
        if (!p.isWithin(root, canonical)) {
          throw const FormatException('백업 임시 파일의 위치가 올바르지 않아요');
        }
        final bytes = await readLimitedBackup(
          File(canonical).openRead(),
          cancelled: cancellation.future,
        );
        return PickedBackupFile(name: name, bytes: bytes);
      }
      final file = await openFile(
        acceptedTypeGroups: _backupTypes,
        confirmButtonText: '선택',
      );
      if (file == null || cancellation.isCompleted) return null;
      if (await file.length() > maxBackupBytes) {
        throw const FormatException('백업 파일이 50MiB 제한을 초과해요');
      }
      return PickedBackupFile(
        name: file.name,
        bytes: await readLimitedBackup(
          file.openRead(),
          cancelled: cancellation.future,
        ),
      );
    } on PlatformException catch (error) {
      if (error.code == 'import_cancelled') return null;
      if (error.code == 'import_too_large') {
        throw const FormatException('백업 파일이 50MiB 제한을 초과해요');
      }
      if (error.code == 'import_timeout') {
        throw const FormatException(
          '파일 읽기에 시간이 오래 걸려 중단했어요. 파일을 기기에 저장한 뒤 다시 시도해 주세요.',
        );
      }
      rethrow;
    } finally {
      if (_usesAndroidImport) {
        try {
          await _importChannel.invokeMethod<void>('release', {
            'operationId': operationId,
          });
        } on Object {
          /* Activity teardown may remove the channel; native owns stale cleanup. */
        }
      }
      _pickCancellation = null;
      _pickOperationId = null;
    }
  }
}

final backupFileServiceProvider = Provider<BackupFileService>((ref) {
  return PlatformBackupFileService();
});

/// Bounded input boundary shared by platform adapters; closes the actual stream.
Future<Uint8List> readLimitedBackup(
  Stream<List<int>> stream, {
  int maxBytes = maxBackupBytes,
  Duration timeout = const Duration(seconds: 30),
  Future<void>? cancelled,
}) async {
  final iterator = StreamIterator(stream);
  final output = BytesBuilder(copy: false);
  final watch = Stopwatch()..start();
  var stopped = false;
  final stop = cancelled?.then((_) {
    stopped = true;
    return false;
  });
  try {
    while (true) {
      final remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('백업 파일 읽기 시간이 초과됐어요');
      }
      final next = await Future.any<bool>([
        iterator.moveNext(),
        ?stop,
      ]).timeout(remaining);
      if (stopped) throw PlatformException(code: 'import_cancelled');
      if (!next) break;
      final chunk = iterator.current;
      if (chunk.length > maxBytes - output.length) {
        throw const FormatException('백업 파일이 50MiB 제한을 초과해요');
      }
      output.add(chunk);
    }
    return output.takeBytes();
  } finally {
    await iterator.cancel();
  }
}
