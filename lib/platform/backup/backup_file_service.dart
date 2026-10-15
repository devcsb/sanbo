import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
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
}

class PlatformBackupFileService implements BackupFileService {
  PlatformBackupFileService({
    this._platform,
    Future<Directory> Function()? temporaryDirectory,
    MethodChannel? channel,
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _channel = channel ?? const MethodChannel('sanbo/backup_export');

  final TargetPlatform? _platform;
  final Future<Directory> Function() _temporaryDirectory;
  final MethodChannel _channel;
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
      acceptedTypeGroups: _backupTypes,
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
  Future<PickedBackupFile?> pick() async {
    final file = await openFile(
      acceptedTypeGroups: _backupTypes,
      confirmButtonText: '선택',
    );
    if (file == null) return null;
    final length = await file.length();
    if (length > maxBackupBytes) {
      throw const FormatException('백업 파일이 50MB 제한을 초과합니다');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBackupBytes) {
      throw const FormatException('백업 파일이 50MB 제한을 초과합니다');
    }
    return PickedBackupFile(name: file.name, bytes: bytes);
  }
}

final backupFileServiceProvider = Provider<BackupFileService>((ref) {
  return PlatformBackupFileService();
});
