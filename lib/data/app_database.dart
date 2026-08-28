import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

const schemaVersion = 6;

const routeExclusionsTableSql = '''
CREATE TABLE route_exclusions (
  id TEXT PRIMARY KEY NOT NULL,
  session_id TEXT NOT NULL,
  start_at TEXT NOT NULL,
  end_at TEXT NOT NULL,
  reason TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
)''';

/// Opens the on-device SQLite DB (TRD §3).
Future<Database> openAppDatabase({String? path}) async {
  final dbPath = path ?? await _defaultPath();
  return openDatabase(
    dbPath,
    version: schemaVersion,
    onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys = ON');
    },
    onCreate: (db, version) async {
      await _createSchema(db);
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute('''
CREATE TABLE places (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  name TEXT NOT NULL,
  address TEXT,
  updated_at TEXT NOT NULL
)''');
        await db.execute(
          'CREATE INDEX idx_places_coordinate ON places(lat, lon)',
        );
        await db.execute(
          'ALTER TABLE minute_windows ADD COLUMN place_id INTEGER REFERENCES places(id) ON DELETE SET NULL',
        );
        await db.execute(
          'CREATE INDEX idx_windows_place ON minute_windows(place_id)',
        );
      }
      if (oldVersion < 3) {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sessions_status_started_at '
          'ON sessions(status, started_at DESC)',
        );
      }
      if (oldVersion < 4) {
        await db.execute(routeExclusionsTableSql);
        await db.execute(
          'CREATE INDEX idx_route_exclusions_session_range '
          'ON route_exclusions(session_id, start_at, end_at)',
        );
        await db.execute(
          'ALTER TABLE minute_windows ADD COLUMN user_exclusion_id TEXT '
          'REFERENCES route_exclusions(id) ON DELETE SET NULL',
        );
        await db.execute(
          'CREATE INDEX idx_windows_user_exclusion ON minute_windows(user_exclusion_id)',
        );
      }
      if (oldVersion < 5) {
        // Preserve every historical session while resolving any duplicate
        // active rows created before the database-level invariant existed.
        final activeRows = await db.query(
          'sessions',
          columns: const ['id'],
          where: 'status = ?',
          whereArgs: ['active'],
          orderBy: 'started_at ASC, id ASC',
        );
        for (final row in activeRows.skip(1)) {
          await db.update(
            'sessions',
            {'status': 'crashedRecovered', 'ended_at': row['ended_at']},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
        // A retry after an interrupted commit can leave byte-identical fixes
        // in legacy databases. Keep the first row for each logical fix. Very
        // old v1 fixtures did not have a samples table yet, so skip it there.
        final sampleTable = await db.query(
          'sqlite_master',
          columns: const ['name'],
          where: "type = 'table' AND name = 'location_samples'",
        );
        if (sampleTable.isNotEmpty) {
          await db.execute('''
DELETE FROM location_samples
WHERE id NOT IN (
  SELECT MIN(id)
  FROM location_samples
  GROUP BY session_id, ts, lat, lon
)''');
        }
        await db.execute('''
CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_single_active
ON sessions(status) WHERE status = 'active'
''');
        if (sampleTable.isNotEmpty) {
          await db.execute('''
CREATE UNIQUE INDEX IF NOT EXISTS idx_samples_idempotency
ON location_samples(session_id, ts, lat, lon)
''');
        }
      }
      if (oldVersion < 6) {
        for (final column in const [
          'stationary_warning_at',
          'stationary_limit_at',
          'duration_warning_at',
          'duration_limit_at',
        ]) {
          await db.execute('ALTER TABLE sessions ADD COLUMN $column TEXT');
        }
        // Existing active rows retain their original start time while gaining
        // the durable five-hour boundary. Stationary deadlines are derived
        // only after a trusted stationary anchor is observed by the guard.
        await db.execute('''
UPDATE sessions
SET duration_warning_at = strftime('%Y-%m-%dT%H:%M:%fZ', started_at, '+4 hours 45 minutes'),
    duration_limit_at = strftime('%Y-%m-%dT%H:%M:%fZ', started_at, '+5 hours')
WHERE duration_warning_at IS NULL
  AND status = 'active'
''');
      }
    },
    onOpen: (db) async {
      final check = await db.rawQuery('PRAGMA quick_check(1)');
      if (check.isEmpty || check.first.values.first != 'ok') {
        throw StateError('산보 데이터베이스 무결성 확인에 실패했습니다');
      }
    },
  );
}

Future<void> _createSchema(Database db) async {
  await db.execute('''
CREATE TABLE sessions (
  id TEXT PRIMARY KEY NOT NULL,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  status TEXT NOT NULL,
  tracking_mode TEXT NOT NULL,
  timezone TEXT NOT NULL,
  total_distance_m REAL,
  duration_s INTEGER,
  moving_time_s INTEGER,
  stationary_time_s INTEGER,
  avg_speed_mps REAL,
  valid_sample_count INTEGER,
  median_accuracy_m REAL,
  stationary_warning_at TEXT,
  stationary_limit_at TEXT,
  duration_warning_at TEXT,
  duration_limit_at TEXT,
  notes TEXT
)''');
  await db.execute(
    'CREATE INDEX idx_sessions_status_started_at '
    'ON sessions(status, started_at DESC)',
  );
  await db.execute('''
CREATE TABLE places (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  name TEXT NOT NULL,
  address TEXT,
  updated_at TEXT NOT NULL
)''');
  await db.execute('CREATE INDEX idx_places_coordinate ON places(lat, lon)');
  await db.execute('''
CREATE TABLE location_samples (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  ts TEXT NOT NULL,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  accuracy_m REAL,
  speed_mps REAL,
  altitude_m REAL,
  is_filtered_out INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
)''');
  await db.execute(
    'CREATE INDEX idx_samples_session ON location_samples(session_id, ts)',
  );
  await db.execute('''
CREATE UNIQUE INDEX idx_samples_idempotency
ON location_samples(session_id, ts, lat, lon)
''');
  await db.execute(routeExclusionsTableSql);
  await db.execute(
    'CREATE INDEX idx_route_exclusions_session_range '
    'ON route_exclusions(session_id, start_at, end_at)',
  );
  await db.execute('''
CREATE TABLE minute_windows (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  window_start TEXT NOT NULL,
  duration_s INTEGER NOT NULL,
  partial INTEGER NOT NULL,
  sample_count INTEGER NOT NULL,
  raw_sample_count INTEGER NOT NULL,
  distance_m REAL NOT NULL,
  avg_speed_mps REAL NOT NULL,
  max_speed_mps REAL NOT NULL,
  stationary_ratio REAL NOT NULL,
  quality TEXT NOT NULL,
  gap_reason TEXT,
  centroid_lat REAL,
  centroid_lon REAL,
  start_lat REAL,
  start_lon REAL,
  end_lat REAL,
  end_lon REAL,
  hypothesis_label TEXT NOT NULL,
  hypothesis_confidence REAL NOT NULL,
  evidence_json TEXT NOT NULL,
  user_label TEXT,
  user_note TEXT,
  user_confirmed INTEGER NOT NULL DEFAULT 0,
  place_id INTEGER,
  user_exclusion_id TEXT REFERENCES route_exclusions(id) ON DELETE SET NULL,
  UNIQUE(session_id, window_start),
  FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
  FOREIGN KEY(place_id) REFERENCES places(id) ON DELETE SET NULL
)''');
  await db.execute(
    'CREATE INDEX idx_windows_session ON minute_windows(session_id, window_start)',
  );
  await db.execute(
    'CREATE INDEX idx_windows_place ON minute_windows(place_id)',
  );
  await db.execute(
    'CREATE INDEX idx_windows_user_exclusion ON minute_windows(user_exclusion_id)',
  );
  await db.execute('''
CREATE UNIQUE INDEX idx_sessions_single_active
ON sessions(status) WHERE status = 'active'
''');
}

Future<String> _defaultPath() async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, 'sanbo.db');
}
