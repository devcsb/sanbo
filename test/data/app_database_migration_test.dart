import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/data/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_db.dart';
import '../helpers/route_exclusion_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh v5 database passes quick, foreign key, and safety index checks', () async {
    ensureSqfliteFfi();
    final path =
        '${Directory.systemTemp.path}/sanbo_v4_fresh_${DateTime.now().microsecondsSinceEpoch}.db';
    addTearDown(() => databaseFactory.deleteDatabase(path));

    final db = await openAppDatabase(path: path);
    addTearDown(db.close);

    expect(await db.rawQuery('PRAGMA quick_check(1)'), [
      {'quick_check': 'ok'},
    ]);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name IN "
      "('idx_sessions_single_active', 'idx_samples_idempotency')",
    );
    expect(
      indexes.map((row) => row['name']),
      containsAll(['idx_sessions_single_active', 'idx_samples_idempotency']),
    );
  });

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
    final queryPlan = await upgraded.rawQuery(
      'EXPLAIN QUERY PLAN '
      'SELECT id FROM sessions WHERE status = ? '
      'ORDER BY started_at DESC, id DESC LIMIT 50',
      ['completed'],
    );
    expect(
      queryPlan.any(
        (row) => row.values.any(
          (value) =>
              value.toString().contains('idx_sessions_status_started_at'),
        ),
      ),
      isTrue,
    );
    final preserved = await upgraded.query('minute_windows');
    expect(preserved, hasLength(1));
    expect(preserved.single['session_id'], 'legacy-session');
  });

  test(
    'realistic schema v2 data survives the v3 history-index upgrade',
    () async {
      ensureSqfliteFfi();
      final path =
          '${Directory.systemTemp.path}/sanbo_v2_migration_${DateTime.now().microsecondsSinceEpoch}.db';
      addTearDown(() => databaseFactory.deleteDatabase(path));

      final old = await openDatabase(
        path,
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
CREATE TABLE sessions (
  id TEXT PRIMARY KEY NOT NULL, started_at TEXT NOT NULL, ended_at TEXT,
  status TEXT NOT NULL, tracking_mode TEXT NOT NULL, timezone TEXT NOT NULL,
  total_distance_m REAL, duration_s INTEGER, moving_time_s INTEGER,
  stationary_time_s INTEGER, avg_speed_mps REAL, valid_sample_count INTEGER,
  median_accuracy_m REAL, notes TEXT
)''');
          await db.execute('''
CREATE TABLE places (
  id INTEGER PRIMARY KEY AUTOINCREMENT, lat REAL NOT NULL, lon REAL NOT NULL,
  name TEXT NOT NULL, address TEXT, updated_at TEXT NOT NULL
)''');
          await db.execute('''
CREATE TABLE location_samples (
  id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL, ts TEXT NOT NULL,
  lat REAL NOT NULL, lon REAL NOT NULL, accuracy_m REAL, speed_mps REAL,
  altitude_m REAL, is_filtered_out INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
)''');
          await db.execute('''
CREATE TABLE minute_windows (
  id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
  window_start TEXT NOT NULL, duration_s INTEGER NOT NULL, partial INTEGER NOT NULL,
  sample_count INTEGER NOT NULL, raw_sample_count INTEGER NOT NULL,
  distance_m REAL NOT NULL, avg_speed_mps REAL NOT NULL, max_speed_mps REAL NOT NULL,
  stationary_ratio REAL NOT NULL, quality TEXT NOT NULL, gap_reason TEXT,
  centroid_lat REAL, centroid_lon REAL, start_lat REAL, start_lon REAL,
  end_lat REAL, end_lon REAL, hypothesis_label TEXT NOT NULL,
  hypothesis_confidence REAL NOT NULL, evidence_json TEXT NOT NULL,
  user_label TEXT, user_note TEXT, user_confirmed INTEGER NOT NULL DEFAULT 0,
  place_id INTEGER, UNIQUE(session_id, window_start),
  FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
  FOREIGN KEY(place_id) REFERENCES places(id) ON DELETE SET NULL
)''');
        },
      );
      await old.insert('sessions', {
        'id': 'v2-session',
        'started_at': '2026-08-01T09:00:00.000',
        'ended_at': '2026-08-01T09:01:00.000',
        'status': 'completed',
        'tracking_mode': 'balanced',
        'timezone': 'Asia/Seoul',
        'total_distance_m': 42.0,
        'duration_s': 60,
        'moving_time_s': 48,
        'stationary_time_s': 12,
        'avg_speed_mps': 0.875,
        'valid_sample_count': 2,
        'median_accuracy_m': 6.0,
        'notes': 'v2 메모',
      });
      final placeId = await old.insert('places', {
        'lat': 37.5,
        'lon': 127.0,
        'name': 'v2 장소',
        'address': '서울',
        'updated_at': '2026-08-01T09:01:00.000',
      });
      await old.insert('location_samples', {
        'session_id': 'v2-session',
        'ts': '2026-08-01T09:00:00.000',
        'lat': 37.5,
        'lon': 127.0,
        'accuracy_m': 6.0,
        'speed_mps': 1.0,
        'altitude_m': 20.0,
        'is_filtered_out': 0,
      });
      await old.insert('minute_windows', {
        'session_id': 'v2-session',
        'window_start': '2026-08-01T09:00:00.000',
        'duration_s': 60,
        'partial': 0,
        'sample_count': 1,
        'raw_sample_count': 1,
        'distance_m': 42.0,
        'avg_speed_mps': 0.7,
        'max_speed_mps': 1.0,
        'stationary_ratio': 0.2,
        'quality': 'high',
        'hypothesis_label': 'walk_steady',
        'hypothesis_confidence': 0.8,
        'evidence_json': '["v2"]',
        'user_label': 'cafe_or_shop',
        'user_note': 'v2 수정',
        'user_confirmed': 1,
        'place_id': placeId,
      });
      await old.close();

      final upgraded = await openAppDatabase(path: path);
      addTearDown(upgraded.close);
      expect((await upgraded.query('sessions')).single['notes'], 'v2 메모');
      expect(await upgraded.query('location_samples'), hasLength(1));
      expect(
        (await upgraded.query('minute_windows')).single['user_note'],
        'v2 수정',
      );
      expect((await upgraded.query('places')).single['name'], 'v2 장소');
      expect(
        await upgraded.query(
          'sqlite_master',
          where: "type = 'index' AND name = ?",
          whereArgs: ['idx_sessions_status_started_at'],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'v3 upgrades to v4 without changing samples or existing aggregates',
    () async {
      ensureSqfliteFfi();
      final path =
          '${Directory.systemTemp.path}/sanbo_v3_to_v4_${DateTime.now().microsecondsSinceEpoch}.db';
      addTearDown(() => databaseFactory.deleteDatabase(path));
      await createV3Fixture(path, sessionId: 'walk-1', filteredFlags: [0, 1]);

      final db = await openAppDatabase(path: path);
      addTearDown(db.close);
      expect(await db.query('route_exclusions'), isEmpty);
      final columns = await db.rawQuery('PRAGMA table_info(minute_windows)');
      expect(columns.map((row) => row['name']), contains('user_exclusion_id'));
      expect(
        (await db.query('minute_windows')).single['user_exclusion_id'],
        isNull,
      );
      expect(
        (await db.query(
          'location_samples',
        )).map((row) => row['is_filtered_out']),
        [0, 1],
      );
      expect(await db.rawQuery('PRAGMA quick_check(1)'), [
        {'quick_check': 'ok'},
      ]);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        await db.query(
          'sqlite_master',
          where: "type = 'index' AND name IN (?, ?)",
          whereArgs: [
            'idx_sessions_single_active',
            'idx_samples_idempotency',
          ],
        ),
        hasLength(2),
      );
    },
  );
}
