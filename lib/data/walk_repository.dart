import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/models/activity_label.dart';
import '../domain/models/location_sample.dart';
import '../domain/models/minute_window.dart';
import '../domain/models/tracking_mode.dart';
import '../domain/models/walk_session.dart';
import 'app_database.dart';

/// Persistent walk store (sessions + samples + minute windows).
class WalkRepository {
  WalkRepository(this._db);

  final Database _db;
  final _uuid = const Uuid();

  static Future<WalkRepository> open({String? path}) async {
    final db = await openAppDatabase(path: path);
    // Ensure FK cascade works on SQLite.
    await db.execute('PRAGMA foreign_keys = ON');
    return WalkRepository(db);
  }

  Future<void> close() => _db.close();

  Future<WalkSession?> getActiveSession() async {
    final rows = await _db.query(
      'sessions',
      where: "status = ?",
      whereArgs: [SessionStatus.active.name],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _sessionFromRow(rows.first);
  }

  Future<List<WalkSession>> listCompleted() async {
    final rows = await _db.query(
      'sessions',
      where: "status = ?",
      whereArgs: [SessionStatus.completed.name],
      orderBy: 'started_at DESC',
    );
    return rows.map(_sessionFromRow).toList();
  }

  Future<WalkSession?> getSession(String id) async {
    final rows = await _db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _sessionFromRow(rows.first);
  }

  Future<WalkSession> startSession({
    TrackingMode mode = TrackingMode.balanced,
    String timezone = 'Asia/Seoul',
    DateTime? startedAt,
  }) async {
    final existing = await getActiveSession();
    if (existing != null) {
      throw StateError('이미 진행 중인 산책이 있습니다');
    }
    final session = WalkSession(
      id: _uuid.v4(),
      startedAt: startedAt ?? DateTime.now(),
      timezone: timezone,
      trackingMode: mode,
      status: SessionStatus.active,
    );
    await _db.insert('sessions', _sessionToRow(session));
    return session;
  }

  Future<void> insertSamples(String sessionId, List<LocationSample> samples) async {
    if (samples.isEmpty) return;
    final batch = _db.batch();
    for (final s in samples) {
      batch.insert('location_samples', {
        'session_id': sessionId,
        'ts': s.timestamp.toIso8601String(),
        'lat': s.latitude,
        'lon': s.longitude,
        'accuracy_m': s.accuracyM,
        'speed_mps': s.speedMps,
        'altitude_m': s.altitudeM,
        'is_filtered_out': s.isFilteredOut ? 1 : 0,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<LocationSample>> getSamples(String sessionId) async {
    final rows = await _db.query(
      'location_samples',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'ts ASC',
    );
    return rows.map(_sampleFromRow).toList();
  }

  Future<void> replaceWindows(String sessionId, List<MinuteWindow> windows) async {
    await _db.delete(
      'minute_windows',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    final batch = _db.batch();
    for (final w in windows) {
      batch.insert('minute_windows', _windowToRow(sessionId, w));
    }
    await batch.commit(noResult: true);
  }

  Future<List<MinuteWindow>> getWindows(String sessionId) async {
    final rows = await _db.query(
      'minute_windows',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'window_start ASC',
    );
    return rows.map(_windowFromRow).toList();
  }

  Future<WalkSession> completeSession({
    required String sessionId,
    required DateTime endedAt,
    required double totalDistanceM,
    required int durationS,
    required int movingTimeS,
    required int stationaryTimeS,
    required double avgSpeedMps,
    required int validSampleCount,
    double? medianAccuracyM,
  }) async {
    final current = await getSession(sessionId);
    if (current == null) {
      throw StateError('세션을 찾을 수 없습니다');
    }
    final ended = current.copyWith(
      endedAt: endedAt,
      status: SessionStatus.completed,
      totalDistanceM: totalDistanceM,
      durationS: durationS,
      movingTimeS: movingTimeS,
      stationaryTimeS: stationaryTimeS,
      avgSpeedMps: avgSpeedMps,
      validSampleCount: validSampleCount,
      medianAccuracyM: medianAccuracyM,
    );
    await _db.update(
      'sessions',
      _sessionToRow(ended),
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    return ended;
  }

  Future<void> updateWindowUserLabel({
    required String sessionId,
    required DateTime windowStart,
    required ActivityLabel userLabel,
    String? note,
    bool confirmed = true,
  }) async {
    await _db.update(
      'minute_windows',
      {
        'user_label': userLabel.storageKey,
        'user_note': note,
        'user_confirmed': confirmed ? 1 : 0,
      },
      where: 'session_id = ? AND window_start = ?',
      whereArgs: [sessionId, windowStart.toIso8601String()],
    );
  }

  Future<void> deleteSession(String id) async {
    await _db.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    await _db.delete('minute_windows');
    await _db.delete('location_samples');
    await _db.delete('sessions');
  }

  // ── mapping ────────────────────────────────────────────────────

  Map<String, Object?> _sessionToRow(WalkSession s) => {
        'id': s.id,
        'started_at': s.startedAt.toIso8601String(),
        'ended_at': s.endedAt?.toIso8601String(),
        'status': s.status.name,
        'tracking_mode': s.trackingMode.name,
        'timezone': s.timezone,
        'total_distance_m': s.totalDistanceM,
        'duration_s': s.durationS,
        'moving_time_s': s.movingTimeS,
        'stationary_time_s': s.stationaryTimeS,
        'avg_speed_mps': s.avgSpeedMps,
        'valid_sample_count': s.validSampleCount,
        'median_accuracy_m': s.medianAccuracyM,
        'notes': s.notes,
      };

  WalkSession _sessionFromRow(Map<String, Object?> r) {
    return WalkSession(
      id: r['id']! as String,
      startedAt: DateTime.parse(r['started_at']! as String),
      endedAt: r['ended_at'] == null
          ? null
          : DateTime.parse(r['ended_at']! as String),
      status: SessionStatus.values.byName(r['status']! as String),
      trackingMode: TrackingMode.values.byName(r['tracking_mode']! as String),
      timezone: r['timezone']! as String,
      totalDistanceM: (r['total_distance_m'] as num?)?.toDouble(),
      durationS: r['duration_s'] as int?,
      movingTimeS: r['moving_time_s'] as int?,
      stationaryTimeS: r['stationary_time_s'] as int?,
      avgSpeedMps: (r['avg_speed_mps'] as num?)?.toDouble(),
      validSampleCount: r['valid_sample_count'] as int?,
      medianAccuracyM: (r['median_accuracy_m'] as num?)?.toDouble(),
      notes: r['notes'] as String?,
    );
  }

  LocationSample _sampleFromRow(Map<String, Object?> r) {
    return LocationSample(
      timestamp: DateTime.parse(r['ts']! as String),
      latitude: (r['lat']! as num).toDouble(),
      longitude: (r['lon']! as num).toDouble(),
      accuracyM: (r['accuracy_m'] as num?)?.toDouble(),
      speedMps: (r['speed_mps'] as num?)?.toDouble(),
      altitudeM: (r['altitude_m'] as num?)?.toDouble(),
      isFilteredOut: (r['is_filtered_out'] as int? ?? 0) == 1,
    );
  }

  Map<String, Object?> _windowToRow(String sessionId, MinuteWindow w) => {
        'session_id': sessionId,
        'window_start': w.windowStart.toIso8601String(),
        'duration_s': w.durationS,
        'partial': w.partial ? 1 : 0,
        'sample_count': w.sampleCount,
        'raw_sample_count': w.rawSampleCount,
        'distance_m': w.distanceM,
        'avg_speed_mps': w.avgSpeedMps,
        'max_speed_mps': w.maxSpeedMps,
        'stationary_ratio': w.stationaryRatio,
        'quality': w.quality.name,
        'gap_reason': w.gapReason,
        'centroid_lat': w.centroidLat,
        'centroid_lon': w.centroidLon,
        'start_lat': w.startLat,
        'start_lon': w.startLon,
        'end_lat': w.endLat,
        'end_lon': w.endLon,
        'hypothesis_label': w.hypothesisLabel.storageKey,
        'hypothesis_confidence': w.hypothesisConfidence,
        'evidence_json': jsonEncode(w.evidence),
        'user_label': w.userLabel?.storageKey,
        'user_note': w.userNote,
        'user_confirmed': w.userConfirmed ? 1 : 0,
      };

  MinuteWindow _windowFromRow(Map<String, Object?> r) {
    final evidenceRaw = r['evidence_json'] as String? ?? '[]';
    final evidence = (jsonDecode(evidenceRaw) as List<dynamic>)
        .map((e) => e.toString())
        .toList();
    return MinuteWindow(
      windowStart: DateTime.parse(r['window_start']! as String),
      durationS: r['duration_s']! as int,
      partial: (r['partial'] as int) == 1,
      sampleCount: r['sample_count']! as int,
      rawSampleCount: r['raw_sample_count']! as int,
      distanceM: (r['distance_m']! as num).toDouble(),
      avgSpeedMps: (r['avg_speed_mps']! as num).toDouble(),
      maxSpeedMps: (r['max_speed_mps']! as num).toDouble(),
      stationaryRatio: (r['stationary_ratio']! as num).toDouble(),
      quality: WindowQuality.values.byName(r['quality']! as String),
      gapReason: r['gap_reason'] as String?,
      centroidLat: (r['centroid_lat'] as num?)?.toDouble(),
      centroidLon: (r['centroid_lon'] as num?)?.toDouble(),
      startLat: (r['start_lat'] as num?)?.toDouble(),
      startLon: (r['start_lon'] as num?)?.toDouble(),
      endLat: (r['end_lat'] as num?)?.toDouble(),
      endLon: (r['end_lon'] as num?)?.toDouble(),
      hypothesisLabel: ActivityLabelX.fromStorage(r['hypothesis_label'] as String?),
      hypothesisConfidence: (r['hypothesis_confidence'] as num).toDouble(),
      evidence: evidence,
      userLabel: r['user_label'] == null
          ? null
          : ActivityLabelX.fromStorage(r['user_label'] as String?),
      userNote: r['user_note'] as String?,
      userConfirmed: (r['user_confirmed'] as int? ?? 0) == 1,
    );
  }
}

/// Overridden in bootstrap with real DB; tests inject via ProviderScope.
final walkRepositoryProvider = Provider<WalkRepository>((ref) {
  throw UnimplementedError('WalkRepository must be overridden at bootstrap');
});
