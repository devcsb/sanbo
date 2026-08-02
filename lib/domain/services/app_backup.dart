import 'dart:convert';
import 'dart:typed_data';

const maxBackupBytes = 50 * 1024 * 1024;
const appBackupSchemaVersion = 1;

class AppBackupArchive {
  const AppBackupArchive({
    required this.databaseSchemaVersion,
    required this.exportedAt,
    required this.tables,
  });

  final int databaseSchemaVersion;
  final DateTime exportedAt;
  final Map<String, List<Map<String, Object?>>> tables;

  List<Map<String, Object?>> table(String name) => tables[name] ?? const [];
}

class BackupImportResult {
  const BackupImportResult({
    required this.importedSessions,
    required this.skippedSessions,
    required this.importedSamples,
    required this.importedWindows,
  });

  final int importedSessions;
  final int skippedSessions;
  final int importedSamples;
  final int importedWindows;
}

/// Versioned, bounded JSON codec for a complete local Sanbo backup.
abstract final class AppBackupCodec {
  static const requiredTables = {
    'sessions',
    'location_samples',
    'minute_windows',
    'places',
  };

  static String encode({
    required int databaseSchemaVersion,
    required Map<String, List<Map<String, Object?>>> tables,
    DateTime? exportedAt,
  }) {
    final encoded = jsonEncode({
      'export_kind': 'sanbo_backup',
      'backup_schema_version': appBackupSchemaVersion,
      'database_schema_version': databaseSchemaVersion,
      'exported_at': (exportedAt ?? DateTime.now()).toIso8601String(),
      'tables': tables,
    });
    if (utf8.encode(encoded).length > maxBackupBytes) {
      throw const FormatException('백업 파일이 50MB 제한을 초과합니다');
    }
    return encoded;
  }

  static AppBackupArchive decodeBytes(Uint8List bytes) {
    if (bytes.length > maxBackupBytes) {
      throw const FormatException('백업 파일이 50MB 제한을 초과합니다');
    }
    return decode(utf8.decode(bytes, allowMalformed: false));
  }

  static AppBackupArchive decode(String raw) {
    if (utf8.encode(raw).length > maxBackupBytes) {
      throw const FormatException('백업 파일이 50MB 제한을 초과합니다');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('백업 최상위 형식이 올바르지 않습니다');
    }
    if (decoded['export_kind'] != 'sanbo_backup') {
      throw const FormatException('산보 전체 백업 파일이 아닙니다');
    }
    if (decoded['backup_schema_version'] != appBackupSchemaVersion) {
      throw const FormatException('지원하지 않는 백업 버전입니다');
    }
    final databaseVersion = decoded['database_schema_version'];
    if (databaseVersion is! int || databaseVersion < 1) {
      throw const FormatException('데이터베이스 버전이 올바르지 않습니다');
    }
    final exportedAt = DateTime.tryParse(
      decoded['exported_at']?.toString() ?? '',
    );
    if (exportedAt == null) {
      throw const FormatException('백업 생성 시각이 올바르지 않습니다');
    }
    final rawTables = decoded['tables'];
    if (rawTables is! Map<String, dynamic>) {
      throw const FormatException('백업 테이블 형식이 올바르지 않습니다');
    }

    final tables = <String, List<Map<String, Object?>>>{};
    for (final name in requiredTables) {
      final rawRows = rawTables[name];
      if (rawRows is! List<dynamic>) {
        throw FormatException('$name 데이터가 없습니다');
      }
      if (rawRows.length > 500000) {
        throw FormatException('$name 행이 안전 제한을 초과합니다');
      }
      tables[name] = [
        for (final row in rawRows)
          if (row is Map<String, dynamic>)
            Map<String, Object?>.from(row)
          else
            throw FormatException('$name 행 형식이 올바르지 않습니다'),
      ];
    }

    return AppBackupArchive(
      databaseSchemaVersion: databaseVersion,
      exportedAt: exportedAt,
      tables: Map.unmodifiable(tables),
    );
  }
}
