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
    'route_exclusions': [],
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

  test('v1 archive is retained and normalized without route exclusions', () {
    final raw = jsonEncode({
      'export_kind': 'sanbo_backup',
      'backup_schema_version': 1,
      'database_schema_version': 3,
      'exported_at': DateTime.utc(2026, 8, 21).toIso8601String(),
      'tables': {
        'sessions': <Object?>[],
        'location_samples': <Object?>[],
        'minute_windows': <Object?>[
          {
            'session_id': 'legacy',
            'window_start': DateTime.utc(2026, 8, 21).toIso8601String(),
          },
        ],
        'places': <Object?>[],
      },
    });

    final archive = AppBackupCodec.decode(raw);

    expect(archive.backupSchemaVersion, 1);
    expect(archive.table('route_exclusions'), isEmpty);
    expect(archive.table('minute_windows').single['user_exclusion_id'], isNull);
  });

  test('v2 requires route exclusions and minute exclusion keys', () {
    final raw = AppBackupCodec.encode(
      databaseSchemaVersion: 4,
      tables: emptyTables,
      exportedAt: DateTime.utc(2026, 8, 21),
    );

    final archive = AppBackupCodec.decode(raw);

    expect(archive.backupSchemaVersion, 2);
    expect(archive.tables.keys, contains('route_exclusions'));

    final missingKey = jsonDecode(raw) as Map<String, dynamic>;
    (missingKey['tables'] as Map<String, dynamic>)['minute_windows'] = [
      <String, Object?>{},
    ];
    expect(
      () => AppBackupCodec.decode(jsonEncode(missingKey)),
      throwsFormatException,
    );
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
