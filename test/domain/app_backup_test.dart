import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/services/app_backup.dart';

void main() {
  const emptyTables = <String, List<Map<String, Object?>>>{
    'sessions': [],
    'location_samples': [],
    'minute_windows': [],
    'places': [],
  };

  test('versioned backup codec round-trips required tables', () {
    final exportedAt = DateTime.utc(2026, 8, 1, 3, 4);
    final raw = AppBackupCodec.encode(
      databaseSchemaVersion: 2,
      tables: emptyTables,
      exportedAt: exportedAt,
    );

    final decoded = AppBackupCodec.decode(raw);
    expect(decoded.databaseSchemaVersion, 2);
    expect(decoded.exportedAt, exportedAt);
    expect(decoded.tables.keys, containsAll(AppBackupCodec.requiredTables));
  });

  test('rejects a similarly-shaped JSON file that is not a Sanbo backup', () {
    final raw = jsonEncode({
      'export_kind': 'other_app',
      'backup_schema_version': appBackupSchemaVersion,
      'database_schema_version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'tables': emptyTables,
    });

    expect(() => AppBackupCodec.decode(raw), throwsFormatException);
  });

  test('rejects missing tables and invalid UTF-8', () {
    final missingTable = jsonEncode({
      'export_kind': 'sanbo_backup',
      'backup_schema_version': appBackupSchemaVersion,
      'database_schema_version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'tables': const <String, Object?>{},
    });
    expect(() => AppBackupCodec.decode(missingTable), throwsFormatException);
    expect(
      () => AppBackupCodec.decodeBytes(Uint8List.fromList([0xC3, 0x28])),
      throwsFormatException,
    );
  });
}
