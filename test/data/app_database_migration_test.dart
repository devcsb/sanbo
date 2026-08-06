import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/data/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('schema v1 upgrades with places and place_id intact', () async {
    ensureSqfliteFfi();
    final path =
        '${Directory.systemTemp.path}/sanbo_migration_${DateTime.now().microsecondsSinceEpoch}.db';
    addTearDown(() => databaseFactory.deleteDatabase(path));

    final old = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE sessions (
  id TEXT PRIMARY KEY NOT NULL,
  started_at TEXT NOT NULL,
  status TEXT NOT NULL
)''');
        await db.execute('''
CREATE TABLE minute_windows (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  window_start TEXT NOT NULL
)''');
      },
    );
    await old.insert('minute_windows', {
      'session_id': 'legacy-session',
      'window_start': '2026-07-01T09:00:00.000',
    });
    await old.close();

    final upgraded = await openAppDatabase(path: path);
    addTearDown(upgraded.close);
    final columns = await upgraded.rawQuery(
      'PRAGMA table_info(minute_windows)',
    );
    expect(columns.map((row) => row['name']), contains('place_id'));

    final tables = await upgraded.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'table'",
    );
    expect(tables.map((row) => row['name']), contains('places'));
    final indexes = await upgraded.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'index' AND name = ?",
      whereArgs: ['idx_sessions_status_started_at'],
    );
    expect(indexes, hasLength(1));
    final preserved = await upgraded.query('minute_windows');
    expect(preserved, hasLength(1));
    expect(preserved.single['session_id'], 'legacy-session');
  });
}
