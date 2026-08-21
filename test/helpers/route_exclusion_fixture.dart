import 'dart:convert';

import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/pipeline/segment_merger.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_db.dart';

typedef CompletedRouteFixture = ({
  WalkSession session,
  List<LocationSample> samples,
  List<MinuteWindow> windows,
  List<ActivitySegment> segments,
});

Future<CompletedRouteFixture> seedCompletedTwoMinuteWalk(
  WalkRepository repo,
) async {
  final start = DateTime.utc(2026, 8, 21);
  final session = await repo.startSession(startedAt: start);
  final samples = <LocationSample>[
    for (var second = 0; second <= 120; second += 20)
      LocationSample(
        timestamp: start.add(Duration(seconds: second)),
        latitude: 37.5,
        longitude: 127 + second * 0.00001,
        accuracyM: 5,
        speedMps: 1,
      ),
  ];
  final pipeline = SessionPipeline();
  final result = pipeline.process(
    session: session,
    rawSamples: samples,
    endedAt: start.add(const Duration(minutes: 2)),
  );
  final completed = await repo.finalizeSession(
    session: session,
    samples: result.filteredSamples,
    windows: result.windows,
    endedAt: start.add(const Duration(minutes: 2)),
    totalDistanceM: result.metrics.totalDistanceM,
    durationS: result.metrics.durationS,
    movingTimeS: result.metrics.movingTimeS,
    stationaryTimeS: result.metrics.stationaryTimeS,
    avgSpeedMps: result.metrics.avgSpeedMps,
    validSampleCount: result.metrics.validSampleCount,
    medianAccuracyM: result.metrics.medianAccuracyM,
  );
  final persisted = await repo.getWindows(session.id);
  await repo.rememberPlaceForWindows(
    sessionId: session.id,
    windowStarts: [persisted.first.windowStart],
    latitude: 37.5,
    longitude: 127,
    name: '출발 장소',
  );
  await repo.updateWindowUserLabel(
    sessionId: session.id,
    windowStart: persisted.last.windowStart,
    userLabel: ActivityLabel.vehicle,
    note: '차량',
    confirmed: true,
  );
  final windows = await repo.getWindows(session.id);
  return (
    session: (await repo.getSession(session.id)) ?? completed,
    samples: await repo.getSamples(session.id),
    windows: windows,
    segments: pipeline.segmentMerger.merge(windows),
  );
}

Future<CompletedRouteFixture> seedCompletedVehicleWalk(WalkRepository repo) =>
    seedCompletedTwoMinuteWalk(repo);

Future<String> snapshotRouteEditTables(String path) async {
  ensureSqfliteFfi();
  final db = await databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  try {
    final snapshot = <String, List<Map<String, Object?>>>{};
    for (final entry in const <String, String>{
      'route_exclusions': 'id ASC',
      'minute_windows': 'id ASC',
      'sessions': 'id ASC',
      'location_samples': 'id ASC',
    }.entries) {
      snapshot[entry.key] = await db.query(entry.key, orderBy: entry.value);
    }
    return jsonEncode(snapshot);
  } finally {
    await db.close();
  }
}

Future<void> createV3Fixture(
  String path, {
  required String sessionId,
  required List<int> filteredFlags,
}) async {
  ensureSqfliteFfi();
  final db = await databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(version: 3),
  );
  try {
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
    await db.execute(
      'CREATE INDEX idx_sessions_status_started_at ON sessions(status, started_at DESC)',
    );
    await db.insert('sessions', {
      'id': sessionId,
      'started_at': '2026-08-21T00:00:00.000Z',
      'ended_at': '2026-08-21T00:01:00.000Z',
      'status': 'completed',
      'tracking_mode': 'balanced',
      'timezone': 'Asia/Seoul',
      'total_distance_m': 10.0,
      'duration_s': 60,
      'moving_time_s': 60,
      'stationary_time_s': 0,
      'avg_speed_mps': 1.0,
      'valid_sample_count': filteredFlags.length,
    });
    final placeId = await db.insert('places', {
      'lat': 37.5,
      'lon': 127.0,
      'name': '기존 장소',
      'updated_at': '2026-08-21T00:01:00.000Z',
    });
    for (var index = 0; index < filteredFlags.length; index++) {
      await db.insert('location_samples', {
        'session_id': sessionId,
        'ts':
            '2026-08-21T00:00:${(index * 20).toString().padLeft(2, '0')}.000Z',
        'lat': 37.5,
        'lon': 127.0 + index * 0.00001,
        'is_filtered_out': filteredFlags[index],
      });
    }
    await db.insert('minute_windows', {
      'session_id': sessionId,
      'window_start': '2026-08-21T00:00:00.000Z',
      'duration_s': 60,
      'partial': 0,
      'sample_count': 1,
      'raw_sample_count': 1,
      'distance_m': 10.0,
      'avg_speed_mps': 1.0,
      'max_speed_mps': 1.0,
      'stationary_ratio': 0.0,
      'quality': 'high',
      'hypothesis_label': 'walk_steady',
      'hypothesis_confidence': 0.8,
      'evidence_json': '[]',
      'place_id': placeId,
    });
  } finally {
    await db.close();
  }
}
