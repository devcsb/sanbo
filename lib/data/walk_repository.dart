import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/models/activity_label.dart';
import '../domain/models/location_sample.dart';
import '../domain/models/minute_window.dart';
import '../domain/models/place_memory.dart';
import '../domain/models/route_exclusion.dart';
import '../domain/models/tracking_mode.dart';
import '../domain/models/walk_session.dart';
import '../domain/pipeline/geo.dart';
import '../domain/pipeline/segment_merger.dart';
import '../domain/pipeline/session_rollup.dart';
import '../domain/services/app_backup.dart';
import '../domain/services/daily_walk_stats.dart';
import '../domain/services/session_deadline.dart';
import '../domain/services/session_guard.dart';
import '../domain/services/session_pipeline.dart';
import '../domain/services/walk_stats.dart';
import 'app_database.dart';

/// Persistent walk store (sessions + samples + minute windows).
class WalkRepository {
  WalkRepository(this._db);

  final Database _db;
  final _uuid = const Uuid();
  final _pipeline = SessionPipeline();
  var _completedTimestampsCanonical = false;

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

  Future<List<WalkSession>> listCompleted({int? limit, int offset = 0}) async {
    if (limit != null && limit <= 0) return const [];
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'must not be negative');
    }

    if (!_completedTimestampsCanonical) {
      // Current rows use fixed-width UTC ISO-8601 strings, so SQLite can page
      // them with its index. Older databases may contain local or offset
      // strings. Normalize those rows once, then every later page stays in
      // the indexed SQL path instead of materializing the full history.
      final legacyRows = await _db.rawQuery(
        '''
SELECT 1
FROM sessions
WHERE status = ?
  AND NOT (started_at GLOB ?)
LIMIT 1
''',
        [
          SessionStatus.completed.name,
          '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T'
              '[0-9][0-9]:[0-9][0-9]:[0-9][0-9][.]'
              '[0-9][0-9][0-9][0-9][0-9][0-9]Z',
        ],
      );
      if (legacyRows.isNotEmpty) {
        final normalized = await _normalizeCompletedTimestamps();
        if (!normalized) return _listCompletedParsed(limit, offset);
      }
      _completedTimestampsCanonical = true;
    }

    final rows = await _db.query(
      'sessions',
      where: 'status = ?',
      whereArgs: [SessionStatus.completed.name],
      orderBy: 'started_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_sessionFromRow).toList();
  }

  Future<List<WalkSession>> _listCompletedParsed(int? limit, int offset) async {
    final rows = await _db.query(
      'sessions',
      where: 'status = ?',
      whereArgs: [SessionStatus.completed.name],
    );
    final sessions = rows.map(_sessionFromRow).toList()
      ..sort((a, b) {
        final byStarted = b.startedAt.toUtc().compareTo(a.startedAt.toUtc());
        return byStarted != 0 ? byStarted : b.id.compareTo(a.id);
      });
    if (offset >= sessions.length) return const [];
    final end = limit == null
        ? sessions.length
        : math.min(offset + limit, sessions.length);
    return sessions.sublist(offset, end);
  }

  Future<bool> _normalizeCompletedTimestamps() async {
    try {
      return await _db.transaction((txn) async {
        final rows = await txn.query(
          'sessions',
          columns: const ['id', 'started_at', 'ended_at', 'timezone'],
          where: 'status = ?',
          whereArgs: [SessionStatus.completed.name],
        );
        for (final row in rows) {
          final timezone = row['timezone']! as String;
          final startedAt = parseStoredInstant(
            row['started_at']! as String,
            timezone: timezone,
          ).toUtc();
          final endedRaw = row['ended_at'] as String?;
          final endedAt = endedRaw == null
              ? null
              : parseStoredInstant(endedRaw, timezone: timezone).toUtc();
          await txn.update(
            'sessions',
            {
              'started_at': _canonicalUtcInstant(startedAt),
              'ended_at': endedAt == null
                  ? null
                  : _canonicalUtcInstant(endedAt),
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
        return true;
      });
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  /// Computes history summary in SQLite without loading every session into
  /// Dart. The history screen can therefore render a small page while keeping
  /// totals correct for long-lived users.
  Future<WalkStats> completedStats() async {
    final rows = await _db.rawQuery(
      '''
SELECT COUNT(*) AS walk_count,
       COALESCE(SUM(total_distance_m), 0) AS total_distance_m,
       COALESCE(SUM(duration_s), 0) AS total_duration_s,
       COALESCE(MAX(duration_s), 0) AS longest_duration_s,
       COALESCE(MAX(total_distance_m), 0) AS longest_distance_m
FROM sessions
WHERE status = ?
''',
      [SessionStatus.completed.name],
    );
    final row = rows.single;
    return WalkStats(
      walkCount: (row['walk_count'] as num?)?.toInt() ?? 0,
      totalDistanceM: (row['total_distance_m'] as num?)?.toDouble() ?? 0,
      totalDurationS: (row['total_duration_s'] as num?)?.toInt() ?? 0,
      longestDurationS: (row['longest_duration_s'] as num?)?.toInt() ?? 0,
      longestDistanceM: (row['longest_distance_m'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Returns one aggregate row for every local calendar day in the half-open
  /// range. A completed session belongs entirely to its start date, even when
  /// it ends after midnight.
  Future<List<DailyWalkStats>> dailyStats({
    required DateTime startDate,
    required DateTime endDateExclusive,
  }) async {
    final start = _localDateOnly(startDate);
    final end = _localDateOnly(endDateExclusive);
    if (!start.isBefore(end)) {
      throw ArgumentError.value(
        endDateExclusive,
        'endDateExclusive',
        'must be after startDate',
      );
    }

    // New rows store UTC instants while older databases may contain local
    // wall-clock strings. Read a small UTC guard band, then group by the
    // device-local date after parsing with each session's saved timezone.
    final rows = await _db.query(
      'sessions',
      columns: const [
        'started_at',
        'timezone',
        'total_distance_m',
        'duration_s',
      ],
      where: 'status = ? AND started_at >= ? AND started_at < ?',
      whereArgs: [
        SessionStatus.completed.name,
        start.toUtc().subtract(const Duration(days: 1)).toIso8601String(),
        end.toUtc().add(const Duration(days: 1)).toIso8601String(),
      ],
      orderBy: 'started_at ASC',
    );
    final aggregates = <String, ({int count, double distance, int duration})>{};
    for (final row in rows) {
      final timezone = row['timezone']! as String;
      final startedAt = parseStoredInstant(
        row['started_at']! as String,
        timezone: timezone,
      ).toLocal();
      final day = DateTime(startedAt.year, startedAt.month, startedAt.day);
      if (day.isBefore(start) || !day.isBefore(end)) continue;
      final key = _dateKey(day);
      final previous = aggregates[key];
      aggregates[key] = (
        count: (previous?.count ?? 0) + 1,
        distance:
            (previous?.distance ?? 0) +
            _nonNegativeDouble(row['total_distance_m']),
        duration:
            (previous?.duration ?? 0) + _nonNegativeInt(row['duration_s']),
      );
    }
    final grouped = <String, DailyWalkStats>{
      for (final entry in aggregates.entries)
        entry.key: DailyWalkStats(
          date: _dateFromKey(entry.key),
          walkCount: entry.value.count,
          totalDistanceM: entry.value.distance,
          totalDurationS: entry.value.duration,
        ),
    };

    final days = <DailyWalkStats>[];
    for (
      var day = start;
      day.isBefore(end);
      day = day.add(const Duration(days: 1))
    ) {
      days.add(grouped[_dateKey(day)] ?? DailyWalkStats.zero(day));
    }
    return days;
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
    final deadlines = SessionDeadlinePolicy.calculate(
      session.startedAt,
      const SessionGuardPolicy(),
    );
    final persisted = session.copyWith(
      durationWarningAt: deadlines.durationWarningAt,
      durationLimitAt: deadlines.durationLimitAt,
    );
    try {
      await _db.insert('sessions', _sessionToRow(persisted));
    } on DatabaseException catch (error) {
      final message = error.toString();
      if (message.contains('idx_sessions_single_active') ||
          message.contains('sessions.status')) {
        throw StateError('이미 진행 중인 산책이 있습니다');
      }
      rethrow;
    }
    return persisted;
  }

  Future<void> insertSamples(
    String sessionId,
    List<LocationSample> samples,
  ) async {
    final persistable = samples
        .where(_isPersistableSample)
        .map((sample) => sample.normalizedMetadata())
        .toList(growable: false);
    if (persistable.isEmpty) return;
    final batch = _db.batch();
    for (final s in persistable) {
      batch.insert(
        'location_samples',
        _sampleToRow(sessionId, s),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Map<String, Object?> _sampleToRow(String sessionId, LocationSample sample) {
    final s = sample.normalizedMetadata();
    return {
      'session_id': sessionId,
      'ts': s.timestamp.toUtc().toIso8601String(),
      'lat': s.latitude,
      'lon': s.longitude,
      'accuracy_m': s.accuracyM,
      'speed_mps': s.speedMps,
      'altitude_m': s.altitudeM,
      'is_filtered_out': s.isFilteredOut ? 1 : 0,
    };
  }

  bool _isPersistableSample(LocationSample sample) {
    return sample.latitude.isFinite &&
        sample.latitude >= -90 &&
        sample.latitude <= 90 &&
        sample.longitude.isFinite &&
        sample.longitude >= -180 &&
        sample.longitude <= 180;
  }

  /// Mark a session discarded while retaining its raw audit samples. A
  /// discarded session is intentionally excluded from history and backups,
  /// but its filtered fixes remain available for diagnostics and reprocessing.
  Future<WalkSession> finalizeDiscardedSession({
    required WalkSession session,
    required List<LocationSample> samples,
    required List<MinuteWindow> windows,
    required DateTime endedAt,
  }) async {
    final discarded = session.copyWith(
      endedAt: endedAt,
      status: SessionStatus.discarded,
    );
    await _db.transaction((txn) async {
      await txn.delete(
        'location_samples',
        where: 'session_id = ?',
        whereArgs: [session.id],
      );
      final sampleBatch = txn.batch();
      for (final sample in samples.where(_isPersistableSample)) {
        sampleBatch.insert(
          'location_samples',
          _sampleToRow(session.id, sample),
        );
      }
      await sampleBatch.commit(noResult: true);

      await txn.delete(
        'minute_windows',
        where: 'session_id = ?',
        whereArgs: [session.id],
      );
      final windowBatch = txn.batch();
      for (final window in windows) {
        windowBatch.insert('minute_windows', _windowToRow(session.id, window));
      }
      await windowBatch.commit(noResult: true);

      final updated = await txn.update(
        'sessions',
        _sessionToRow(discarded),
        where: 'id = ?',
        whereArgs: [session.id],
      );
      if (updated != 1) throw StateError('산책 폐기 상태를 저장하지 못했습니다');
    });
    return discarded;
  }

  /// Atomically persist a finalized walk: replace samples, replace windows,
  /// and mark the session completed in a single transaction. Prevents a crash
  /// mid-finalize from leaving samples deleted-but-not-reinserted or the
  /// session stuck `active` with already-rewritten data.
  Future<WalkSession> finalizeSession({
    required WalkSession session,
    required List<LocationSample> samples,
    required List<MinuteWindow> windows,
    required DateTime endedAt,
    required double totalDistanceM,
    required int durationS,
    required int movingTimeS,
    required int stationaryTimeS,
    required double avgSpeedMps,
    required int validSampleCount,
    double? medianAccuracyM,
  }) async {
    final ended = session.copyWith(
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
    await _db.transaction((txn) async {
      await txn.delete(
        'location_samples',
        where: 'session_id = ?',
        whereArgs: [session.id],
      );
      final sampleBatch = txn.batch();
      for (final s in samples.where(_isPersistableSample)) {
        sampleBatch.insert(
          'location_samples',
          _sampleToRow(session.id, s),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await sampleBatch.commit(noResult: true);

      await txn.delete(
        'minute_windows',
        where: 'session_id = ?',
        whereArgs: [session.id],
      );
      final windowBatch = txn.batch();
      for (final w in windows) {
        windowBatch.insert('minute_windows', _windowToRow(session.id, w));
      }
      await windowBatch.commit(noResult: true);

      final updated = await txn.update(
        'sessions',
        _sessionToRow(ended),
        where: 'id = ?',
        whereArgs: [session.id],
      );
      if (updated != 1) {
        throw StateError('산책 완료 상태를 저장하지 못했습니다');
      }
    });
    return ended;
  }

  /// Replace all samples for a session (after filter flags are known).
  Future<void> replaceSamples(
    String sessionId,
    List<LocationSample> samples,
  ) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'location_samples',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      final persistable = samples
          .where(_isPersistableSample)
          .map((sample) => sample.normalizedMetadata())
          .toList(growable: false);
      final batch = txn.batch();
      for (final sample in persistable) {
        batch.insert(
          'location_samples',
          _sampleToRow(sessionId, sample),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<LocationSample>> getSamples(String sessionId) async {
    final sessionRows = await _db.query(
      'sessions',
      columns: const ['timezone'],
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (sessionRows.isEmpty) return const [];
    final timezone = sessionRows.single['timezone']! as String;
    final rows = await _db.query(
      'location_samples',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'ts ASC',
    );
    final samples = rows
        .map((row) => _sampleFromRow(row, timezone: timezone))
        .toList();
    samples.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return samples;
  }

  Future<void> replaceWindows(
    String sessionId,
    List<MinuteWindow> windows,
  ) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'minute_windows',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      final batch = txn.batch();
      for (final w in windows) {
        batch.insert('minute_windows', _windowToRow(sessionId, w));
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<MinuteWindow>> getWindows(String sessionId) async {
    final sessionRows = await _db.query(
      'sessions',
      columns: const ['timezone'],
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (sessionRows.isEmpty) return const [];
    return _getWindowsIn(
      _db,
      sessionId,
      timezone: sessionRows.single['timezone']! as String,
    );
  }

  Future<List<RouteExclusion>> getRouteExclusions(String sessionId) async {
    final sessionRows = await _db.query(
      'sessions',
      columns: const ['timezone'],
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (sessionRows.isEmpty) return const [];
    final timezone = sessionRows.single['timezone']! as String;
    final rows = await _db.query(
      'route_exclusions',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    final exclusions = rows
        .map((row) => _exclusionFromRow(row, timezone: timezone))
        .toList();
    return exclusions..sort((a, b) {
      final byStart = a.startAt.compareTo(b.startAt);
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });
  }

  /// Saves one user-selected route exclusion and every derived aggregate in
  /// the same SQLite transaction. Source samples remain immutable.
  Future<RouteExclusion> excludeRouteSegment({
    required String sessionId,
    required ActivitySegment segment,
    RouteExclusionReason reason = RouteExclusionReason.vehicle,
    DateTime? createdAt,
  }) {
    return _db.transaction((txn) async {
      final snapshot = await _loadRouteEditSnapshot(txn, sessionId);
      if (segment.sessionId != sessionId) {
        throw StateError('다른 산책의 구간은 제외할 수 없습니다');
      }
      if (segment.durationS <= 0 ||
          segment.windows.any((window) => window.durationS <= 0)) {
        throw StateError('제외할 구간 길이가 올바르지 않습니다');
      }
      final authoritative = SegmentMerger().merge(
        snapshot.windows,
        sessionId: sessionId,
        sessionStart: snapshot.session.startedAt,
        sessionEnd: snapshot.session.endedAt,
      );
      final matches = authoritative.where(
        (candidate) => _sameSegmentSelection(candidate, segment),
      );
      if (matches.length != 1) {
        throw StateError('현재 산책에서 제외할 수 있는 구간을 찾지 못했습니다');
      }
      final selected = matches.single;
      final candidate = RouteExclusion(
        id: _uuid.v4(),
        sessionId: sessionId,
        startAt: selected.startAt,
        endAt: selected.endExclusive,
        reason: reason,
        createdAt: createdAt ?? DateTime.now(),
      );
      if (snapshot.exclusions.any(
        (existing) => existing.overlaps(candidate.startAt, candidate.endAt),
      )) {
        throw StateError('이미 제외한 범위와 겹칩니다');
      }
      final next = [...snapshot.exclusions, candidate]
        ..sort((a, b) => a.startAt.compareTo(b.startAt));
      final result = _pipeline.recalculateCompleted(
        session: snapshot.session,
        storedSamples: snapshot.samples,
        exclusions: next,
        previousWindows: snapshot.windows,
      );
      await txn.insert('route_exclusions', _exclusionToRow(candidate));
      await _replaceWindowsIn(
        txn,
        sessionId,
        result.windows,
        expectedExistingCount: snapshot.windows.length,
      );
      await _updateRollupIn(txn, snapshot.session, result.metrics);
      return candidate;
    });
  }

  bool _sameSegmentSelection(
    ActivitySegment authoritative,
    ActivitySegment requested,
  ) {
    if (requested.sessionId != authoritative.sessionId ||
        requested.label != authoritative.label ||
        requested.sampleCount != authoritative.sampleCount ||
        requested.userConfirmed != authoritative.userConfirmed ||
        requested.quality != authoritative.quality ||
        !_sameDouble(requested.confidenceMin, authoritative.confidenceMin) ||
        !_sameDouble(requested.distanceM, authoritative.distanceM) ||
        !_sameDouble(requested.avgSpeedMps, authoritative.avgSpeedMps) ||
        requested.durationS != authoritative.durationS ||
        !requested.start.isAtSameMomentAs(authoritative.start) ||
        !requested.endInclusive.isAtSameMomentAs(authoritative.endInclusive) ||
        !requested.startAt.isAtSameMomentAs(authoritative.startAt) ||
        !requested.endExclusive.isAtSameMomentAs(authoritative.endExclusive) ||
        requested.windows.length != authoritative.windows.length) {
      return false;
    }
    for (var index = 0; index < requested.windows.length; index++) {
      final left = requested.windows[index];
      final right = authoritative.windows[index];
      if (!left.windowStart.isAtSameMomentAs(right.windowStart) ||
          left.durationS != right.durationS ||
          left.partial != right.partial ||
          left.sampleCount != right.sampleCount ||
          left.rawSampleCount != right.rawSampleCount ||
          !_sameDouble(left.distanceM, right.distanceM) ||
          !_sameDouble(left.avgSpeedMps, right.avgSpeedMps) ||
          !_sameDouble(left.maxSpeedMps, right.maxSpeedMps) ||
          !_sameDouble(left.stationaryRatio, right.stationaryRatio) ||
          left.quality != right.quality ||
          left.hypothesisLabel != right.hypothesisLabel ||
          !_sameDouble(left.hypothesisConfidence, right.hypothesisConfidence) ||
          left.evidence.join('\u0000') != right.evidence.join('\u0000') ||
          left.displayLabel != right.displayLabel ||
          left.userExclusionId != right.userExclusionId) {
        return false;
      }
    }
    return true;
  }

  bool _sameDouble(double left, double right) {
    return (left - right).abs() <= 1e-6;
  }

  /// Removes one exclusion after reconstructing the completed route without
  /// it. Deletion is deliberately last so any failed rewrite rolls back it.
  Future<void> restoreRouteExclusion({
    required String sessionId,
    required String exclusionId,
  }) {
    return _db.transaction((txn) async {
      final snapshot = await _loadRouteEditSnapshot(txn, sessionId);
      final target = snapshot.exclusions.where(
        (item) => item.id == exclusionId,
      );
      if (target.length != 1) {
        throw StateError('복원할 제외 구간을 찾을 수 없습니다');
      }
      final next = snapshot.exclusions
          .where((item) => item.id != exclusionId)
          .toList(growable: false);
      final result = _pipeline.recalculateCompleted(
        session: snapshot.session,
        storedSamples: snapshot.samples,
        exclusions: next,
        previousWindows: snapshot.windows,
      );
      await _replaceWindowsIn(
        txn,
        sessionId,
        result.windows,
        expectedExistingCount: snapshot.windows.length,
      );
      await _updateRollupIn(txn, snapshot.session, result.metrics);
      final deleted = await txn.delete(
        'route_exclusions',
        where: 'id = ? AND session_id = ?',
        whereArgs: [exclusionId, sessionId],
      );
      if (deleted != 1) throw StateError('제외 구간을 복원하지 못했습니다');
    });
  }

  Future<List<MinuteWindow>> _getWindowsIn(
    DatabaseExecutor executor,
    String sessionId, {
    required String timezone,
  }) async {
    final rows = await executor.rawQuery(
      '''
SELECT w.*,
       p.name AS place_name,
       p.address AS place_address
FROM minute_windows AS w
LEFT JOIN places AS p ON p.id = w.place_id
WHERE w.session_id = ?
''',
      [sessionId],
    );
    final windows = rows
        .map((row) => _windowFromRow(row, timezone: timezone))
        .toList();
    windows.sort((a, b) => a.windowStart.compareTo(b.windowStart));
    return windows;
  }

  Future<_RouteEditSnapshot> _loadRouteEditSnapshot(
    DatabaseExecutor executor,
    String sessionId,
  ) async {
    final sessionRows = await executor.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (sessionRows.isEmpty) throw StateError('세션을 찾을 수 없습니다');
    final session = _sessionFromRow(sessionRows.single);
    if (session.status != SessionStatus.completed || session.endedAt == null) {
      throw StateError('완료된 산책만 경로를 제외할 수 있습니다');
    }
    final samples =
        (await executor.query(
              'location_samples',
              where: 'session_id = ?',
              whereArgs: [sessionId],
              orderBy: 'ts ASC',
            ))
            .map((row) => _sampleFromRow(row, timezone: session.timezone))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final windows = await _getWindowsIn(
      executor,
      sessionId,
      timezone: session.timezone,
    );
    final exclusions =
        (await executor.query(
              'route_exclusions',
              where: 'session_id = ?',
              whereArgs: [sessionId],
            ))
            .map((row) => _exclusionFromRow(row, timezone: session.timezone))
            .toList()
          ..sort((a, b) {
            final byStart = a.startAt.compareTo(b.startAt);
            return byStart != 0 ? byStart : a.id.compareTo(b.id);
          });
    return _RouteEditSnapshot(
      session: session,
      samples: samples,
      windows: windows,
      exclusions: exclusions,
    );
  }

  Future<void> _replaceWindowsIn(
    DatabaseExecutor executor,
    String sessionId,
    List<MinuteWindow> windows, {
    required int expectedExistingCount,
  }) async {
    final existingPlaceIds = windows
        .map((window) => window.placeId)
        .whereType<int>()
        .toSet();
    for (final placeId in existingPlaceIds) {
      final rows = await executor.query(
        'places',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [placeId],
        limit: 1,
      );
      if (rows.length != 1) {
        throw StateError('연결된 장소를 찾을 수 없습니다');
      }
    }
    final deleted = await executor.delete(
      'minute_windows',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    if (deleted != expectedExistingCount) {
      throw StateError('기존 시간 구간 수가 일치하지 않습니다');
    }
    var inserted = 0;
    for (final window in windows) {
      await executor.insert('minute_windows', _windowToRow(sessionId, window));
      inserted++;
    }
    if (inserted != windows.length) {
      throw StateError('시간 구간을 모두 저장하지 못했습니다');
    }
  }

  Future<void> _updateRollupIn(
    DatabaseExecutor executor,
    WalkSession session,
    SessionRollupResult metrics,
  ) async {
    final updated = await executor.update(
      'sessions',
      {
        'total_distance_m': metrics.totalDistanceM,
        'duration_s': metrics.durationS,
        'moving_time_s': metrics.movingTimeS,
        'stationary_time_s': metrics.stationaryTimeS,
        'avg_speed_mps': metrics.avgSpeedMps,
        'valid_sample_count': metrics.validSampleCount,
        'median_accuracy_m': metrics.medianAccuracyM,
      },
      where: 'id = ?',
      whereArgs: [session.id],
    );
    if (updated != 1) throw StateError('산책 집계를 갱신하지 못했습니다');
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
    await _db.transaction((txn) async {
      final updated = await txn.update(
        'sessions',
        _sessionToRow(ended),
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      if (updated != 1) {
        throw StateError('산책 완료 상태를 저장하지 못했습니다');
      }
    });
    return ended;
  }

  Future<void> updateWindowUserLabel({
    required String sessionId,
    required DateTime windowStart,
    required ActivityLabel userLabel,
    String? note,
    bool confirmed = true,
  }) async {
    final payload = <String, Object?>{
      'user_label': userLabel.storageKey,
      'user_note': note,
      'user_confirmed': confirmed ? 1 : 0,
    };
    final keys = _windowStartKeys(windowStart);
    var updated = 0;
    for (final key in keys) {
      updated = await _db.update(
        'minute_windows',
        payload,
        where: 'session_id = ? AND window_start = ?',
        whereArgs: [sessionId, key],
      );
      if (updated > 0) return;
    }
    // Last resort: match any row whose parsed window_start equals target minute.
    final rows = await _db.query(
      'minute_windows',
      columns: ['window_start'],
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    final targetInstant = windowStart.toUtc();
    final targetWall = DateTime(
      windowStart.year,
      windowStart.month,
      windowStart.day,
      windowStart.hour,
      windowStart.minute,
    );
    for (final row in rows) {
      final raw = row['window_start'] as String?;
      if (raw == null) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) continue;
      final sameInstant = parsed.toUtc().isAtSameMomentAs(targetInstant);
      final sameWallMinute =
          parsed.year == targetWall.year &&
          parsed.month == targetWall.month &&
          parsed.day == targetWall.day &&
          parsed.hour == targetWall.hour &&
          parsed.minute == targetWall.minute;
      if (!sameInstant && !sameWallMinute) continue;
      await _db.update(
        'minute_windows',
        payload,
        where: 'session_id = ? AND window_start = ?',
        whereArgs: [sessionId, raw],
      );
      return;
    }
  }

  /// Apply the same user label to every minute in [windowStarts] (segment edit).
  Future<void> updateWindowsUserLabel({
    required String sessionId,
    required List<DateTime> windowStarts,
    required ActivityLabel userLabel,
    String? note,
    bool confirmed = true,
  }) async {
    if (windowStarts.isEmpty) return;
    for (final start in windowStarts) {
      await updateWindowUserLabel(
        sessionId: sessionId,
        windowStart: start,
        userLabel: userLabel,
        note: note,
        confirmed: confirmed,
      );
    }
  }

  /// Find a previously user-confirmed place close enough to reuse.
  Future<PlaceMemory?> findNearestPlace({
    required double latitude,
    required double longitude,
    double radiusM = 35,
  }) async {
    final latitudeDelta = radiusM / 111320;
    final longitudeScale = math.cos(latitude * math.pi / 180).abs();
    final longitudeDelta = radiusM / (111320 * math.max(longitudeScale, 0.01));
    final rows = await _db.query(
      'places',
      where: 'lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?',
      whereArgs: [
        latitude - latitudeDelta,
        latitude + latitudeDelta,
        longitude - longitudeDelta,
        longitude + longitudeDelta,
      ],
    );
    PlaceMemory? nearest;
    var nearestDistance = double.infinity;
    for (final row in rows) {
      final place = _placeFromRow(row);
      final distance = haversineMeters(
        lat1: latitude,
        lon1: longitude,
        lat2: place.latitude,
        lon2: place.longitude,
      );
      if (distance <= radiusM && distance < nearestDistance) {
        nearest = place;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  /// Create or update a local place memory, then link it to every minute in
  /// the edited stay segment.
  Future<PlaceMemory> rememberPlaceForWindows({
    required String sessionId,
    required List<DateTime> windowStarts,
    required double latitude,
    required double longitude,
    required String name,
    String? address,
    int? existingPlaceId,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', '장소 이름은 비워 둘 수 없습니다');
    }
    if (windowStarts.isEmpty) {
      throw ArgumentError.value(
        windowStarts,
        'windowStarts',
        '연결할 시간 구간이 없습니다',
      );
    }
    final trimmedAddress = address?.trim();
    final now = DateTime.now();

    return _db.transaction((txn) async {
      var placeId = existingPlaceId;
      if (placeId != null) {
        final updated = await txn.update(
          'places',
          {
            'lat': latitude,
            'lon': longitude,
            'name': trimmedName,
            'address': (trimmedAddress == null || trimmedAddress.isEmpty)
                ? null
                : trimmedAddress,
            'updated_at': now.toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [placeId],
        );
        if (updated == 0) placeId = null;
      }

      placeId ??= await txn.insert('places', {
        'lat': latitude,
        'lon': longitude,
        'name': trimmedName,
        'address': (trimmedAddress == null || trimmedAddress.isEmpty)
            ? null
            : trimmedAddress,
        'updated_at': now.toUtc().toIso8601String(),
      });

      await _attachPlaceToWindows(
        txn,
        sessionId: sessionId,
        windowStarts: windowStarts,
        placeId: placeId,
      );

      return PlaceMemory(
        id: placeId,
        latitude: latitude,
        longitude: longitude,
        name: trimmedName,
        address: (trimmedAddress == null || trimmedAddress.isEmpty)
            ? null
            : trimmedAddress,
        updatedAt: now,
      );
    });
  }

  Future<void> attachPlaceToWindows({
    required String sessionId,
    required List<DateTime> windowStarts,
    required int placeId,
  }) {
    return _db.transaction(
      (txn) => _attachPlaceToWindows(
        txn,
        sessionId: sessionId,
        windowStarts: windowStarts,
        placeId: placeId,
      ),
    );
  }

  Future<void> _attachPlaceToWindows(
    DatabaseExecutor executor, {
    required String sessionId,
    required List<DateTime> windowStarts,
    required int placeId,
  }) async {
    for (final start in windowStarts) {
      var updated = 0;
      for (final key in _windowStartKeys(start)) {
        updated = await executor.update(
          'minute_windows',
          {'place_id': placeId},
          where: 'session_id = ? AND window_start = ?',
          whereArgs: [sessionId, key],
        );
        if (updated > 0) break;
      }
      if (updated == 0) {
        throw StateError('장소를 연결할 시간 구간을 찾지 못했습니다');
      }
    }
  }

  /// Removing a place memory unlinks it from every session through the FK.
  Future<void> deletePlace(int placeId) async {
    await _db.delete('places', where: 'id = ?', whereArgs: [placeId]);
  }

  /// Candidate ISO forms for a wall-clock minute key.
  List<String> _windowStartKeys(DateTime windowStart) {
    final wallClock = DateTime(
      windowStart.year,
      windowStart.month,
      windowStart.day,
      windowStart.hour,
      windowStart.minute,
    );
    final deviceLocal = windowStart.toLocal();
    final deviceWallClock = DateTime(
      deviceLocal.year,
      deviceLocal.month,
      deviceLocal.day,
      deviceLocal.hour,
      deviceLocal.minute,
    );
    final keys = <String>{
      _stableWindowStart(windowStart),
      windowStart.toIso8601String(),
      wallClock.toIso8601String(),
      deviceWallClock.toIso8601String(),
      deviceWallClock.toUtc().toIso8601String(),
    };
    return keys.toList();
  }

  Future<void> updateSessionNotes(String sessionId, String? notes) async {
    final trimmed = notes?.trim();
    await _db.update(
      'sessions',
      {'notes': (trimmed == null || trimmed.isEmpty) ? null : trimmed},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<WalkSession> updateSessionDeadlines(
    String sessionId,
    SessionDeadlines deadlines,
  ) async {
    final updated = await _db.update(
      'sessions',
      {
        'stationary_warning_at': deadlines.stationaryWarningAt
            ?.toUtc()
            .toIso8601String(),
        'stationary_limit_at': deadlines.stationaryLimitAt
            ?.toUtc()
            .toIso8601String(),
        'duration_warning_at': deadlines.durationWarningAt
            .toUtc()
            .toIso8601String(),
        'duration_limit_at': deadlines.durationLimitAt
            .toUtc()
            .toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    if (updated != 1) {
      throw StateError('산책 안전 종료 시점을 저장하지 못했습니다');
    }
    final session = await getSession(sessionId);
    if (session == null) throw StateError('세션을 찾을 수 없습니다');
    return session;
  }

  Future<void> deleteSession(String id) async {
    await _db.delete('sessions', where: 'id = ?', whereArgs: [id]);
    await _deleteOrphanPlaces();
  }

  Future<void> deleteAll() async {
    await _db.transaction((txn) async {
      await txn.delete('minute_windows');
      await txn.delete('location_samples');
      await txn.delete('sessions');
      await txn.delete('places');
    });
  }

  /// Full, versioned local backup. Only completed walks are included, so an
  /// in-progress checkpoint can never be restored as a second active session.
  Future<String> createBackupJson({DateTime? exportedAt}) async {
    final tables = await _db.transaction((txn) async {
      final sessions = await txn.query(
        'sessions',
        where: 'status = ?',
        whereArgs: [SessionStatus.completed.name],
        orderBy: 'started_at ASC',
      );
      final sessionIds = sessions.map((row) => row['id']! as String).toSet();
      final allExclusions = await txn.query(
        'route_exclusions',
        orderBy: 'session_id ASC, start_at ASC, id ASC',
      );
      final exclusions = <Map<String, Object?>>[
        for (final row in allExclusions)
          if (sessionIds.contains(row['session_id'])) Map.from(row),
      ];
      final exclusionsById = {
        for (final row in exclusions) row['id']! as String: row,
      };
      final allSamples = await txn.query(
        'location_samples',
        orderBy: 'session_id ASC, ts ASC',
      );
      final samples = <Map<String, Object?>>[
        for (final row in allSamples)
          if (sessionIds.contains(row['session_id']))
            ?_sanitizedSampleBackupRow(row),
      ];
      final allWindows = await txn.query(
        'minute_windows',
        orderBy: 'session_id ASC, window_start ASC',
      );
      final candidateWindows = allWindows
          .where((row) => sessionIds.contains(row['session_id']))
          .toList(growable: false);
      for (final window in candidateWindows) {
        final exclusionId = window['user_exclusion_id'] as String?;
        if (exclusionId == null) continue;
        final exclusion = exclusionsById[exclusionId];
        if (exclusion == null ||
            exclusion['session_id'] != window['session_id']) {
          throw StateError('백업할 제외 구간 참조가 올바르지 않습니다');
        }
      }
      final referencedPlaceIds = candidateWindows
          .map((row) => row['place_id'])
          .whereType<int>()
          .toSet();
      final allPlaces = await txn.query('places', orderBy: 'id ASC');
      final places = <Map<String, Object?>>[
        for (final row in allPlaces)
          if (referencedPlaceIds.contains(row['id']))
            ?_sanitizedPlaceBackupRow(row),
      ];
      final validPlaceIds = places
          .map((row) => row['id'])
          .whereType<int>()
          .toSet();
      final windows = candidateWindows
          .map((row) => _sanitizedWindowBackupRow(row, validPlaceIds))
          .toList(growable: false);
      return <String, List<Map<String, Object?>>>{
        'sessions': sessions
            .map(_sanitizedSessionBackupRow)
            .toList(growable: false),
        'route_exclusions': exclusions,
        'location_samples': samples,
        'minute_windows': windows,
        'places': places,
      };
    });
    return AppBackupCodec.encode(
      databaseSchemaVersion: schemaVersion,
      tables: tables,
      exportedAt: exportedAt,
    );
  }

  /// Atomically merges a full backup. Existing session IDs are left untouched;
  /// all rows belonging to a new session either import together or not at all.
  Future<BackupImportResult> importBackupJson(String raw) {
    return importBackup(AppBackupCodec.decode(raw));
  }

  /// Imports an archive that has already been decoded and validated.
  ///
  /// File-based UI can parse once on a background isolate, show the preview,
  /// and pass the same immutable archive here instead of decoding a large JSON
  /// document twice on the UI isolate.
  Future<BackupImportResult> importBackup(AppBackupArchive archive) async {
    if (archive.databaseSchemaVersion > schemaVersion) {
      throw const FormatException('더 새로운 산보 버전에서 만든 백업입니다');
    }

    return _db.transaction((txn) async {
      final existingRows = await txn.query('sessions', columns: ['id']);
      final existingIds = existingRows
          .map((row) => row['id']! as String)
          .toSet();
      final importedSessionRows = <String, Map<String, Object?>>{};
      var skippedSessions = 0;

      for (final rawSession in archive.table('sessions')) {
        final row = _validatedSessionRow(rawSession);
        final id = row['id']! as String;
        if (importedSessionRows.containsKey(id)) {
          throw const FormatException('백업에 중복된 산책 ID가 있습니다');
        }
        importedSessionRows[id] = row;
      }

      final newSessionIds = <String>{};
      for (final entry in importedSessionRows.entries) {
        if (existingIds.contains(entry.key)) {
          skippedSessions++;
          continue;
        }
        newSessionIds.add(entry.key);
      }
      final knownSessionIds = {...existingIds, ...importedSessionRows.keys};

      final validatedExclusions = <Map<String, Object?>>[];
      final exclusionIds = <String>{};
      for (final rawExclusion in archive.table('route_exclusions')) {
        final sessionId = _requiredString(
          rawExclusion,
          'session_id',
          maxLength: 128,
        );
        final session = importedSessionRows[sessionId];
        if (session == null) {
          throw const FormatException('존재하지 않는 산책을 가리키는 제외 구간이 있습니다');
        }
        final exclusion = _validatedExclusionRow(rawExclusion, session);
        final id = exclusion['id']! as String;
        if (!exclusionIds.add(id)) {
          throw const FormatException('백업에 중복된 제외 구간 ID가 있습니다');
        }
        validatedExclusions.add(exclusion);
      }
      _validateExclusionOverlaps(validatedExclusions);
      final exclusionsById = {
        for (final exclusion in validatedExclusions)
          exclusion['id']! as String: exclusion,
      };

      await _insertSessions(txn, [
        for (final entry in importedSessionRows.entries)
          if (newSessionIds.contains(entry.key)) entry.value,
      ]);
      await _insertRouteExclusions(txn, [
        for (final exclusion in validatedExclusions)
          if (newSessionIds.contains(exclusion['session_id'])) exclusion,
      ]);

      // Resolve only places used by newly imported sessions. This keeps a
      // duplicate-only import from leaving behind unreferenced coordinates.
      final referencedSourcePlaceIds = <int>{};
      for (final rawWindow in archive.table('minute_windows')) {
        final sessionId = _requiredString(
          rawWindow,
          'session_id',
          maxLength: 128,
        );
        if (!knownSessionIds.contains(sessionId)) {
          throw const FormatException('존재하지 않는 산책을 가리키는 구간 데이터가 있습니다');
        }
        if (!newSessionIds.contains(sessionId)) continue;
        final sourcePlaceId = _optionalInt(rawWindow, 'place_id', min: 1);
        if (sourcePlaceId != null) referencedSourcePlaceIds.add(sourcePlaceId);
      }

      final sourcePlaces = <int, Map<String, Object?>>{};
      for (final rawPlace in archive.table('places')) {
        final sourceId = _requiredInt(rawPlace, 'id', min: 1);
        if (sourcePlaces.containsKey(sourceId)) {
          throw const FormatException('백업에 중복된 장소 ID가 있습니다');
        }
        sourcePlaces[sourceId] = rawPlace;
      }

      var importedSamples = 0;
      final sampleKeys = <String>{};
      final sampleBatch = txn.batch();
      for (final rawSample in archive.table('location_samples')) {
        final sessionId = _requiredString(
          rawSample,
          'session_id',
          maxLength: 128,
        );
        if (!knownSessionIds.contains(sessionId)) {
          throw const FormatException('존재하지 않는 산책을 가리키는 위치 데이터가 있습니다');
        }
        if (!newSessionIds.contains(sessionId)) continue;
        final session = importedSessionRows[sessionId]!;
        final timezone = session['timezone']! as String;
        final ts = _requiredDate(rawSample, 'ts', timezone: timezone);
        final sessionStart = _requiredDate(session, 'started_at').toUtc();
        final sessionEnd = _requiredDate(session, 'ended_at').toUtc();
        final isFilteredOut = _requiredBoolInt(rawSample, 'is_filtered_out');
        // Finalization retains clock-skewed provider fixes as filtered audit
        // data, but an included sample outside the completed span could later
        // be reinterpreted as route data when exclusions are rebuilt.
        if (isFilteredOut == 0 &&
            (ts.toUtc().isBefore(sessionStart) ||
                ts.toUtc().isAfter(sessionEnd))) {
          throw const FormatException('산책 범위를 벗어난 위치 데이터가 있습니다');
        }
        final lat = _requiredCoordinate(rawSample, 'lat', -90, 90);
        final lon = _requiredCoordinate(rawSample, 'lon', -180, 180);
        final key = '$sessionId|${ts.toUtc().microsecondsSinceEpoch}|$lat|$lon';
        if (!sampleKeys.add(key)) continue;
        sampleBatch.insert('location_samples', {
          'session_id': sessionId,
          'ts': ts.toUtc().toIso8601String(),
          'lat': lat,
          'lon': lon,
          'accuracy_m': _optionalDouble(rawSample, 'accuracy_m', min: 0),
          'speed_mps': _optionalDouble(rawSample, 'speed_mps', min: 0),
          'altitude_m': _optionalDouble(rawSample, 'altitude_m'),
          'is_filtered_out': isFilteredOut,
        });
        importedSamples++;
      }
      await sampleBatch.commit(noResult: true);

      final placeIdMap = <int, int>{};
      for (final sourceId in referencedSourcePlaceIds) {
        final rawPlace = sourcePlaces[sourceId];
        if (rawPlace == null) {
          throw const FormatException('존재하지 않는 장소를 가리키는 구간이 있습니다');
        }
        final lat = _requiredCoordinate(rawPlace, 'lat', -90, 90);
        final lon = _requiredCoordinate(rawPlace, 'lon', -180, 180);
        final name = _requiredString(rawPlace, 'name', maxLength: 60).trim();
        if (name.isEmpty) throw const FormatException('빈 장소 이름이 있습니다');
        final address = _optionalString(rawPlace, 'address', maxLength: 300);
        final updatedAt = _requiredDate(rawPlace, 'updated_at');

        int? targetId;
        final sameName = await txn.query(
          'places',
          where: 'name = ?',
          whereArgs: [name],
        );
        for (final candidate in sameName) {
          final distance = haversineMeters(
            lat1: lat,
            lon1: lon,
            lat2: (candidate['lat']! as num).toDouble(),
            lon2: (candidate['lon']! as num).toDouble(),
          );
          if (distance <= 35) {
            targetId = candidate['id']! as int;
            break;
          }
        }
        targetId ??= await txn.insert('places', {
          'lat': lat,
          'lon': lon,
          'name': name,
          'address': address,
          'updated_at': updatedAt.toUtc().toIso8601String(),
        });
        placeIdMap[sourceId] = targetId;
      }

      var importedWindows = 0;
      final windowKeys = <String>{};
      final windowBatch = txn.batch();
      for (final rawWindow in archive.table('minute_windows')) {
        final sessionId = _requiredString(
          rawWindow,
          'session_id',
          maxLength: 128,
        );
        if (!knownSessionIds.contains(sessionId)) {
          throw const FormatException('존재하지 않는 산책을 가리키는 구간 데이터가 있습니다');
        }
        if (!newSessionIds.contains(sessionId)) continue;
        final session = importedSessionRows[sessionId]!;
        final sessionStart = _requiredDate(session, 'started_at').toUtc();
        final sessionEnd = _requiredDate(session, 'ended_at').toUtc();
        final timezone = session['timezone']! as String;
        final windowStart = _requiredDate(
          rawWindow,
          'window_start',
          timezone: timezone,
        );
        final canonicalWindowStart = windowStart.toUtc();
        final expectedWindowStart = floorToMinute(
          windowStart,
          timezone: timezone,
        ).toUtc();
        final firstWindowStart = floorToMinute(
          sessionStart,
          timezone: timezone,
        ).toUtc();
        if (!canonicalWindowStart.isAtSameMomentAs(expectedWindowStart)) {
          throw const FormatException('시간 구간 시작이 분 경계에 맞지 않습니다');
        }
        if (canonicalWindowStart.isBefore(firstWindowStart) ||
            !canonicalWindowStart.isBefore(sessionEnd)) {
          throw const FormatException('시간 구간이 산책 범위를 벗어났습니다');
        }
        final windowKey =
            '$sessionId|${canonicalWindowStart.millisecondsSinceEpoch}';
        if (!windowKeys.add(windowKey)) {
          throw const FormatException('백업에 중복된 시간 구간이 있습니다');
        }
        final durationS = _requiredInt(
          rawWindow,
          'duration_s',
          min: 1,
          max: 60,
        );
        final minuteEnd = canonicalWindowStart.add(const Duration(minutes: 1));
        final actualWindowStart = canonicalWindowStart.isAfter(sessionStart)
            ? canonicalWindowStart
            : sessionStart;
        final actualWindowEnd = minuteEnd.isBefore(sessionEnd)
            ? minuteEnd
            : sessionEnd;
        final expectedDurationS = positiveDurationSeconds(
          actualWindowStart,
          actualWindowEnd,
        );
        if (durationS != expectedDurationS) {
          throw const FormatException('시간 구간 길이가 산책 범위와 맞지 않습니다');
        }
        final partial = _requiredBoolInt(rawWindow, 'partial');
        if ((partial == 1) != (expectedDurationS < 60)) {
          throw const FormatException('시간 구간 부분 여부가 산책 범위와 맞지 않습니다');
        }
        final userExclusionId = _optionalString(
          rawWindow,
          'user_exclusion_id',
          maxLength: 128,
        );
        if (userExclusionId != null) {
          final exclusion = exclusionsById[userExclusionId];
          if (exclusion == null || exclusion['session_id'] != sessionId) {
            throw const FormatException('구간 제외 참조가 올바르지 않습니다');
          }
          final touching = validatedExclusions
              .where((candidate) {
                if (candidate['session_id'] != sessionId) return false;
                final candidateStart = _requiredDate(candidate, 'start_at');
                final candidateEnd = _requiredDate(candidate, 'end_at');
                return actualWindowStart.isBefore(candidateEnd) &&
                    candidateStart.isBefore(actualWindowEnd);
              })
              .toList(growable: false);
          if (!touching.any(
            (candidate) => candidate['id'] == userExclusionId,
          )) {
            throw const FormatException('제외 범위 밖의 구간이 있습니다');
          }
        }
        final quality = _requiredString(rawWindow, 'quality', maxLength: 20);
        if (!WindowQuality.values.any((value) => value.name == quality)) {
          throw const FormatException('알 수 없는 구간 품질 값이 있습니다');
        }
        final hypothesis = _requiredString(
          rawWindow,
          'hypothesis_label',
          maxLength: 40,
        );
        _validateActivityKey(hypothesis);
        final userLabel = _optionalString(
          rawWindow,
          'user_label',
          maxLength: 40,
        );
        if (userLabel != null) _validateActivityKey(userLabel);
        final evidence = _requiredString(
          rawWindow,
          'evidence_json',
          maxLength: 10000,
        );
        final decodedEvidence = jsonDecode(evidence);
        if (decodedEvidence is! List<dynamic> ||
            decodedEvidence.length > 100 ||
            decodedEvidence.any((item) => item is! String)) {
          throw const FormatException('활동 근거 형식이 올바르지 않습니다');
        }
        final centroid = _optionalCoordinatePair(
          rawWindow,
          latKey: 'centroid_lat',
          lonKey: 'centroid_lon',
        );
        final start = _optionalCoordinatePair(
          rawWindow,
          latKey: 'start_lat',
          lonKey: 'start_lon',
        );
        final end = _optionalCoordinatePair(
          rawWindow,
          latKey: 'end_lat',
          lonKey: 'end_lon',
        );
        final sourcePlaceId = _optionalInt(rawWindow, 'place_id', min: 1);
        final targetPlaceId = sourcePlaceId == null
            ? null
            : placeIdMap[sourcePlaceId];
        if (sourcePlaceId != null && targetPlaceId == null) {
          throw const FormatException('존재하지 않는 장소를 가리키는 구간이 있습니다');
        }

        windowBatch.insert('minute_windows', {
          'session_id': sessionId,
          'window_start': _stableWindowStart(windowStart),
          'duration_s': durationS,
          'partial': partial,
          'sample_count': _requiredInt(rawWindow, 'sample_count', min: 0),
          'raw_sample_count': _requiredInt(
            rawWindow,
            'raw_sample_count',
            min: 0,
          ),
          'distance_m': _requiredDouble(rawWindow, 'distance_m', min: 0),
          'avg_speed_mps': _requiredDouble(rawWindow, 'avg_speed_mps', min: 0),
          'max_speed_mps': _requiredDouble(rawWindow, 'max_speed_mps', min: 0),
          'stationary_ratio': _requiredDouble(
            rawWindow,
            'stationary_ratio',
            min: 0,
            max: 1,
          ),
          'quality': quality,
          'gap_reason': _optionalString(
            rawWindow,
            'gap_reason',
            maxLength: 300,
          ),
          'centroid_lat': centroid.lat,
          'centroid_lon': centroid.lon,
          'start_lat': start.lat,
          'start_lon': start.lon,
          'end_lat': end.lat,
          'end_lon': end.lon,
          'hypothesis_label': hypothesis,
          'hypothesis_confidence': _requiredDouble(
            rawWindow,
            'hypothesis_confidence',
            min: 0,
            max: 1,
          ),
          'evidence_json': evidence,
          'user_label': userLabel,
          'user_note': _optionalString(rawWindow, 'user_note', maxLength: 2000),
          'user_confirmed': _requiredBoolInt(rawWindow, 'user_confirmed'),
          'place_id': targetPlaceId,
          'user_exclusion_id': userExclusionId,
        });
        importedWindows++;
      }
      await windowBatch.commit(noResult: true);

      final foreignKeyErrors = await txn.rawQuery('PRAGMA foreign_key_check');
      if (foreignKeyErrors.isNotEmpty) {
        throw const FormatException('백업 데이터 연결 관계가 올바르지 않습니다');
      }
      return BackupImportResult(
        importedSessions: newSessionIds.length,
        skippedSessions: skippedSessions,
        importedSamples: importedSamples,
        importedWindows: importedWindows,
      );
    });
  }

  Future<void> _deleteOrphanPlaces() async {
    await _db.rawDelete(
      'DELETE FROM places WHERE id NOT IN '
      '(SELECT DISTINCT place_id FROM minute_windows WHERE place_id IS NOT NULL)',
    );
  }

  Future<void> _insertSessions(
    Transaction txn,
    Iterable<Map<String, Object?>> sessions,
  ) async {
    for (final session in sessions) {
      await txn.insert('sessions', session);
    }
  }

  Future<void> _insertRouteExclusions(
    Transaction txn,
    Iterable<Map<String, Object?>> exclusions,
  ) async {
    for (final exclusion in exclusions) {
      await txn.insert('route_exclusions', exclusion);
    }
  }

  Map<String, Object?> _validatedExclusionRow(
    Map<String, Object?> raw,
    Map<String, Object?> session,
  ) {
    final id = _requiredString(raw, 'id', maxLength: 128);
    final sessionId = _requiredString(raw, 'session_id', maxLength: 128);
    final timezone = _requiredString(session, 'timezone', maxLength: 80);
    final startAt = _requiredDate(raw, 'start_at', timezone: timezone).toUtc();
    final endAt = _requiredDate(raw, 'end_at', timezone: timezone).toUtc();
    final createdAt = _requiredDate(
      raw,
      'created_at',
      timezone: timezone,
    ).toUtc();
    if (!startAt.isBefore(endAt)) {
      throw const FormatException('제외 시작은 종료보다 빨라야 합니다');
    }
    final sessionStart = _requiredDate(session, 'started_at').toUtc();
    final sessionEnd = _requiredDate(session, 'ended_at').toUtc();
    if (startAt.isBefore(sessionStart) || endAt.isAfter(sessionEnd)) {
      throw const FormatException('산책 범위를 벗어난 제외 구간이 있습니다');
    }
    final reason = _requiredString(raw, 'reason', maxLength: 40);
    if (!RouteExclusionReason.values.any((value) => value.name == reason)) {
      throw const FormatException('알 수 없는 제외 사유가 있습니다');
    }
    return {
      'id': id,
      'session_id': sessionId,
      'start_at': startAt.toIso8601String(),
      'end_at': endAt.toIso8601String(),
      'reason': reason,
      'created_at': createdAt.toIso8601String(),
    };
  }

  void _validateExclusionOverlaps(List<Map<String, Object?>> exclusions) {
    final bySession = <String, List<Map<String, Object?>>>{};
    for (final exclusion in exclusions) {
      final sessionId = exclusion['session_id']! as String;
      (bySession[sessionId] ??= []).add(exclusion);
    }
    for (final entries in bySession.values) {
      entries.sort(
        (a, b) => _requiredDate(
          a,
          'start_at',
        ).compareTo(_requiredDate(b, 'start_at')),
      );
      for (var index = 1; index < entries.length; index++) {
        final previousEnd = _requiredDate(entries[index - 1], 'end_at');
        final start = _requiredDate(entries[index], 'start_at');
        if (start.isBefore(previousEnd)) {
          throw const FormatException('겹치는 제외 구간이 있습니다');
        }
      }
    }
  }

  Map<String, Object?> _withoutKeys(
    Map<String, Object?> row,
    Set<String> keys,
  ) {
    return Map<String, Object?>.fromEntries(
      row.entries.where((entry) => !keys.contains(entry.key)),
    );
  }

  Map<String, Object?> _validatedSessionRow(Map<String, Object?> raw) {
    final id = _requiredString(raw, 'id', maxLength: 128);
    final timezone = _requiredString(raw, 'timezone', maxLength: 80);
    final startedAt = _requiredDate(
      raw,
      'started_at',
      timezone: timezone,
    ).toUtc();
    final endedAt = _requiredDate(raw, 'ended_at', timezone: timezone).toUtc();
    if (endedAt.isBefore(startedAt)) {
      throw const FormatException('종료 시각이 시작 시각보다 빠른 산책이 있습니다');
    }
    final status = _requiredString(raw, 'status', maxLength: 30);
    if (status != SessionStatus.completed.name) {
      throw const FormatException('완료되지 않은 산책은 가져올 수 없습니다');
    }
    final trackingMode = _requiredString(raw, 'tracking_mode', maxLength: 30);
    if (!TrackingMode.values.any((value) => value.name == trackingMode)) {
      throw const FormatException('알 수 없는 위치 기록 모드가 있습니다');
    }
    return {
      'id': id,
      'started_at': _canonicalUtcInstant(startedAt),
      'ended_at': _canonicalUtcInstant(endedAt),
      'status': status,
      'tracking_mode': trackingMode,
      'timezone': timezone,
      'total_distance_m': _optionalDouble(raw, 'total_distance_m', min: 0),
      'duration_s': _optionalInt(raw, 'duration_s', min: 0),
      'moving_time_s': _optionalInt(raw, 'moving_time_s', min: 0),
      'stationary_time_s': _optionalInt(raw, 'stationary_time_s', min: 0),
      'avg_speed_mps': _optionalDouble(raw, 'avg_speed_mps', min: 0),
      'valid_sample_count': _optionalInt(raw, 'valid_sample_count', min: 0),
      'median_accuracy_m': _optionalDouble(raw, 'median_accuracy_m', min: 0),
      'notes': _optionalString(raw, 'notes', maxLength: 10000),
    };
  }

  String _requiredString(
    Map<String, Object?> row,
    String key, {
    required int maxLength,
  }) {
    final value = row[key];
    if (value is! String || value.isEmpty || value.length > maxLength) {
      throw FormatException('$key 문자열이 올바르지 않습니다');
    }
    return value;
  }

  String? _optionalString(
    Map<String, Object?> row,
    String key, {
    required int maxLength,
  }) {
    final value = row[key];
    if (value == null) return null;
    if (value is! String || value.length > maxLength) {
      throw FormatException('$key 문자열이 올바르지 않습니다');
    }
    return value;
  }

  DateTime _requiredDate(
    Map<String, Object?> row,
    String key, {
    String? timezone,
  }) {
    final value = row[key];
    if (value is! String) throw FormatException('$key 시각이 없습니다');
    try {
      return parseStoredInstant(value, timezone: timezone);
    } on FormatException {
      throw FormatException('$key 시각이 올바르지 않습니다');
    }
  }

  int _requiredInt(Map<String, Object?> row, String key, {int? min, int? max}) {
    final value = row[key];
    if (value is! num || !value.isFinite || value != value.roundToDouble()) {
      throw FormatException('$key 정수가 올바르지 않습니다');
    }
    final result = value.toInt();
    if ((min != null && result < min) || (max != null && result > max)) {
      throw FormatException('$key 범위가 올바르지 않습니다');
    }
    return result;
  }

  int? _optionalInt(
    Map<String, Object?> row,
    String key, {
    int? min,
    int? max,
  }) {
    if (row[key] == null) return null;
    return _requiredInt(row, key, min: min, max: max);
  }

  double _requiredDouble(
    Map<String, Object?> row,
    String key, {
    double? min,
    double? max,
  }) {
    final value = row[key];
    if (value is! num || !value.isFinite) {
      throw FormatException('$key 숫자가 올바르지 않습니다');
    }
    final result = value.toDouble();
    if ((min != null && result < min) || (max != null && result > max)) {
      throw FormatException('$key 범위가 올바르지 않습니다');
    }
    return result;
  }

  double? _optionalDouble(
    Map<String, Object?> row,
    String key, {
    double? min,
    double? max,
  }) {
    if (row[key] == null) return null;
    return _requiredDouble(row, key, min: min, max: max);
  }

  double _requiredCoordinate(
    Map<String, Object?> row,
    String key,
    double min,
    double max,
  ) => _requiredDouble(row, key, min: min, max: max);

  double? _optionalCoordinate(
    Map<String, Object?> row,
    String key,
    double min,
    double max,
  ) => _optionalDouble(row, key, min: min, max: max);

  ({double? lat, double? lon}) _optionalCoordinatePair(
    Map<String, Object?> row, {
    required String latKey,
    required String lonKey,
  }) {
    final lat = _optionalCoordinate(row, latKey, -90, 90);
    final lon = _optionalCoordinate(row, lonKey, -180, 180);
    if ((lat == null) != (lon == null)) {
      throw const FormatException('위도와 경도 중 하나만 있는 구간이 있습니다');
    }
    return (lat: lat, lon: lon);
  }

  int _requiredBoolInt(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value == true || value == 1) return 1;
    if (value == false || value == 0) return 0;
    throw FormatException('$key 불리언 값이 올바르지 않습니다');
  }

  void _validateActivityKey(String key) {
    if (!ActivityLabel.values.any((value) => value.storageKey == key)) {
      throw const FormatException('알 수 없는 활동 값이 있습니다');
    }
  }

  DateTime _localDateOnly(DateTime value) {
    final local = value.isUtc ? value.toLocal() : value;
    return DateTime(local.year, local.month, local.day);
  }

  String _dateKey(DateTime value) {
    final day = _localDateOnly(value);
    final year = day.year.toString().padLeft(4, '0');
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '$year-$month-$date';
  }

  DateTime _dateFromKey(String value) {
    final parsed = DateTime.parse(value);
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  int _nonNegativeInt(Object? value) {
    if (value is! num || !value.isFinite || value < 0) return 0;
    return value.toInt();
  }

  double _nonNegativeDouble(Object? value) {
    if (value is! num || !value.isFinite || value < 0) return 0;
    return value.toDouble();
  }

  String _stableWindowStart(DateTime ts) {
    final instant = ts.toUtc();
    final floored = DateTime.utc(
      instant.year,
      instant.month,
      instant.day,
      instant.hour,
      instant.minute,
    );
    return floored.toIso8601String();
  }

  String _canonicalUtcInstant(DateTime value) {
    final iso = value.toUtc().toIso8601String();
    final match = RegExp(
      r'^(.*T\d{2}:\d{2}:\d{2})\.(\d{3,6})Z$',
    ).firstMatch(iso);
    if (match == null) return iso;
    return '${match.group(1)}.${match.group(2)!.padRight(6, '0')}Z';
  }

  // ── mapping ────────────────────────────────────────────────────

  Map<String, Object?> _sessionToRow(WalkSession s) => {
    'id': s.id,
    'started_at': _canonicalUtcInstant(s.startedAt),
    'ended_at': s.endedAt == null ? null : _canonicalUtcInstant(s.endedAt!),
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
    'stationary_warning_at': s.stationaryWarningAt == null
        ? null
        : _canonicalUtcInstant(s.stationaryWarningAt!),
    'stationary_limit_at': s.stationaryLimitAt == null
        ? null
        : _canonicalUtcInstant(s.stationaryLimitAt!),
    'duration_warning_at': s.durationWarningAt == null
        ? null
        : _canonicalUtcInstant(s.durationWarningAt!),
    'duration_limit_at': s.durationLimitAt == null
        ? null
        : _canonicalUtcInstant(s.durationLimitAt!),
    'notes': s.notes,
  };

  DateTime? _nullableUtcInstant(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  WalkSession _sessionFromRow(Map<String, Object?> r) {
    final timezone = r['timezone']! as String;
    return WalkSession(
      id: r['id']! as String,
      startedAt: asLocal(
        parseStoredInstant(r['started_at']! as String, timezone: timezone),
        timezone: timezone,
      ),
      endedAt: r['ended_at'] == null
          ? null
          : asLocal(
              parseStoredInstant(r['ended_at']! as String, timezone: timezone),
              timezone: timezone,
            ),
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
      stationaryWarningAt: _nullableUtcInstant(r['stationary_warning_at']),
      stationaryLimitAt: _nullableUtcInstant(r['stationary_limit_at']),
      durationWarningAt: _nullableUtcInstant(r['duration_warning_at']),
      durationLimitAt: _nullableUtcInstant(r['duration_limit_at']),
      notes: r['notes'] as String?,
    );
  }

  LocationSample _sampleFromRow(
    Map<String, Object?> r, {
    required String timezone,
  }) {
    return LocationSample(
      // Samples are instants used by filtering and route math. Keep the
      // public value in UTC so equality and ordering do not depend on the
      // timezone object used to interpret a legacy offsetless row.
      timestamp: parseStoredInstant(r['ts']! as String, timezone: timezone),
      latitude: (r['lat']! as num).toDouble(),
      longitude: (r['lon']! as num).toDouble(),
      accuracyM: (r['accuracy_m'] as num?)?.toDouble(),
      speedMps: (r['speed_mps'] as num?)?.toDouble(),
      altitudeM: (r['altitude_m'] as num?)?.toDouble(),
      isFilteredOut: (r['is_filtered_out'] as int? ?? 0) == 1,
    ).normalizedMetadata();
  }

  Map<String, Object?> _sanitizedSessionBackupRow(Map<String, Object?> row) {
    final sanitized = Map<String, Object?>.from(row);
    for (final column in const [
      'total_distance_m',
      'avg_speed_mps',
      'median_accuracy_m',
    ]) {
      sanitized[column] = _safeBackupDouble(sanitized[column], min: 0);
    }
    return sanitized;
  }

  Map<String, Object?>? _sanitizedSampleBackupRow(Map<String, Object?> row) {
    final sanitized = _withoutKeys(row, const {'id'});
    final lat = _safeBackupDouble(sanitized['lat'], min: -90, max: 90);
    final lon = _safeBackupDouble(sanitized['lon'], min: -180, max: 180);
    if (lat == null || lon == null) return null;
    sanitized['lat'] = lat;
    sanitized['lon'] = lon;
    sanitized['accuracy_m'] = _safeBackupDouble(
      sanitized['accuracy_m'],
      min: 0,
    );
    sanitized['speed_mps'] = _safeBackupDouble(sanitized['speed_mps'], min: 0);
    sanitized['altitude_m'] = _safeBackupDouble(sanitized['altitude_m']);
    return sanitized;
  }

  Map<String, Object?> _sanitizedWindowBackupRow(
    Map<String, Object?> row,
    Set<int> validPlaceIds,
  ) {
    final sanitized = _withoutKeys(row, const {'id'});
    for (final column in const [
      'distance_m',
      'avg_speed_mps',
      'max_speed_mps',
    ]) {
      sanitized[column] = _safeBackupDouble(sanitized[column], min: 0) ?? 0.0;
    }
    for (final column in const ['stationary_ratio', 'hypothesis_confidence']) {
      sanitized[column] =
          _safeBackupDouble(sanitized[column], min: 0, max: 1) ?? 0.0;
    }
    _sanitizeBackupCoordinatePair(sanitized, 'centroid_lat', 'centroid_lon');
    _sanitizeBackupCoordinatePair(sanitized, 'start_lat', 'start_lon');
    _sanitizeBackupCoordinatePair(sanitized, 'end_lat', 'end_lon');
    if (!validPlaceIds.contains(sanitized['place_id'])) {
      sanitized['place_id'] = null;
    }
    return sanitized;
  }

  Map<String, Object?>? _sanitizedPlaceBackupRow(Map<String, Object?> row) {
    final sanitized = Map<String, Object?>.from(row);
    final lat = _safeBackupDouble(sanitized['lat'], min: -90, max: 90);
    final lon = _safeBackupDouble(sanitized['lon'], min: -180, max: 180);
    if (lat == null || lon == null) return null;
    sanitized['lat'] = lat;
    sanitized['lon'] = lon;
    return sanitized;
  }

  void _sanitizeBackupCoordinatePair(
    Map<String, Object?> row,
    String latKey,
    String lonKey,
  ) {
    final lat = _safeBackupDouble(row[latKey], min: -90, max: 90);
    final lon = _safeBackupDouble(row[lonKey], min: -180, max: 180);
    row[latKey] = lat != null && lon != null ? lat : null;
    row[lonKey] = lat != null && lon != null ? lon : null;
  }

  double? _safeBackupDouble(Object? value, {double? min, double? max}) {
    if (value == null) return null;
    if (value is! num || !value.isFinite) return null;
    final result = value.toDouble();
    if ((min != null && result < min) || (max != null && result > max)) {
      return null;
    }
    return result;
  }

  Map<String, Object?> _windowToRow(String sessionId, MinuteWindow w) => {
    'session_id': sessionId,
    'window_start': _stableWindowStart(w.windowStart),
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
    'place_id': w.placeId,
    'user_exclusion_id': w.userExclusionId,
  };

  MinuteWindow _windowFromRow(
    Map<String, Object?> r, {
    required String timezone,
  }) {
    final evidenceRaw = r['evidence_json'] as String? ?? '[]';
    final evidence = (jsonDecode(evidenceRaw) as List<dynamic>)
        .map((e) => e.toString())
        .toList();
    final persistedStart = parseStoredInstant(
      r['window_start']! as String,
      timezone: timezone,
    );
    return MinuteWindow(
      windowStart: asLocal(persistedStart, timezone: timezone),
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
      hypothesisLabel: ActivityLabelX.fromStorage(
        r['hypothesis_label'] as String?,
      ),
      hypothesisConfidence: (r['hypothesis_confidence'] as num).toDouble(),
      evidence: evidence,
      userLabel: r['user_label'] == null
          ? null
          : ActivityLabelX.fromStorage(r['user_label'] as String?),
      userNote: r['user_note'] as String?,
      userConfirmed: (r['user_confirmed'] as int? ?? 0) == 1,
      userExclusionId: r['user_exclusion_id'] as String?,
      placeId: r['place_id'] as int?,
      placeName: r['place_name'] as String?,
      placeAddress: r['place_address'] as String?,
    );
  }

  PlaceMemory _placeFromRow(Map<String, Object?> r) {
    return PlaceMemory(
      id: r['id']! as int,
      latitude: (r['lat']! as num).toDouble(),
      longitude: (r['lon']! as num).toDouble(),
      name: r['name']! as String,
      address: r['address'] as String?,
      updatedAt: parseStoredInstant(r['updated_at']! as String),
    );
  }

  Map<String, Object?> _exclusionToRow(RouteExclusion item) => {
    'id': item.id,
    'session_id': item.sessionId,
    'start_at': item.startAt.toUtc().toIso8601String(),
    'end_at': item.endAt.toUtc().toIso8601String(),
    'reason': item.reason.name,
    'created_at': item.createdAt.toUtc().toIso8601String(),
  };

  RouteExclusion _exclusionFromRow(
    Map<String, Object?> row, {
    String? timezone,
  }) => RouteExclusion(
    id: row['id']! as String,
    sessionId: row['session_id']! as String,
    startAt: parseStoredInstant(row['start_at']! as String, timezone: timezone),
    endAt: parseStoredInstant(row['end_at']! as String, timezone: timezone),
    reason: RouteExclusionReason.values.byName(row['reason']! as String),
    createdAt: parseStoredInstant(
      row['created_at']! as String,
      timezone: timezone,
    ),
  );
}

class _RouteEditSnapshot {
  const _RouteEditSnapshot({
    required this.session,
    required this.samples,
    required this.windows,
    required this.exclusions,
  });

  final WalkSession session;
  final List<LocationSample> samples;
  final List<MinuteWindow> windows;
  final List<RouteExclusion> exclusions;
}

/// Overridden in bootstrap with real DB; tests inject via ProviderScope.
final walkRepositoryProvider = Provider<WalkRepository>((ref) {
  throw UnimplementedError('WalkRepository must be overridden at bootstrap');
});
