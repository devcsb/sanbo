import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
