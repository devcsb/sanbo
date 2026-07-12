import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

const schemaVersion = 1;

/// Opens the on-device SQLite DB (TRD §3).
Future<Database> openAppDatabase({String? path}) async {
  final dbPath = path ?? await _defaultPath();
  return openDatabase(
    dbPath,
    version: schemaVersion,
    onCreate: (db, version) async {
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
  notes TEXT
)''');
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
  UNIQUE(session_id, window_start),
  FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
)''');
      await db.execute(
        'CREATE INDEX idx_windows_session ON minute_windows(session_id, window_start)',
      );
    },
  );
}

Future<String> _defaultPath() async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, 'sanbo.db');
}
