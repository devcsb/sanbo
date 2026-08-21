import 'dart:convert';

import '../models/activity_label.dart';
import '../models/location_sample.dart';
import '../models/minute_window.dart';
import '../models/route_exclusion.dart';
import '../models/walk_session.dart';
import '../pipeline/segment_merger.dart';
import 'place_memory.dart';
import 'walk_stats.dart';

/// Local export helpers (FR-16). Pure Dart — no Flutter/IO.
class SessionExport {
  const SessionExport();

  /// Short human summary for clipboard share (no GPS dump).
  String humanSummary({
    required WalkSession session,
    List<MinuteWindow> windows = const [],
  }) {
    final date = session.startedAt.toIso8601String().replaceFirst('T', ' ');
    final km = ((session.totalDistanceM ?? 0) / 1000).toStringAsFixed(2);
    final dur = formatDurationCompact(
      Duration(seconds: session.durationS ?? 0),
    );
    final kmh = ((session.avgSpeedMps ?? 0) * 3.6).toStringAsFixed(1);
    final pace = pacePerKmLabel(session.avgSpeedMps);
    final segments = SegmentMerger().merge(
      windows,
      sessionId: session.id,
      sessionStart: session.startedAt,
      sessionEnd: session.endedAt,
    );
    final buf = StringBuffer()
      ..writeln('산보 산책 요약')
      ..writeln('시작: $date')
      ..writeln('거리: $km km')
      ..writeln('시간: $dur')
      ..writeln('평균 속도: $kmh km/h');
    if (pace != null) buf.writeln('페이스: $pace');
    if (session.movingTimeS != null) {
      buf.writeln(
        '이동 시간: ${formatDurationCompact(Duration(seconds: session.movingTimeS!))}',
      );
    }
    if (session.stationaryTimeS != null) {
      buf.writeln(
        '정지 시간: ${formatDurationCompact(Duration(seconds: session.stationaryTimeS!))}',
      );
    }
    if (session.notes != null && session.notes!.trim().isNotEmpty) {
      buf.writeln('메모: ${session.notes!.trim()}');
    }
    if (segments.isNotEmpty) {
      buf.writeln('활동 구간:');
      for (final seg in segments.take(12)) {
        final start = _hhmm(seg.startAt);
        final end = _hhmm(seg.endExclusive);
        final range = seg.isMultiMinute ? '$start–$end' : start;
        final placeName = segmentPlaceName(seg);
        buf.writeln(
          '· $range ${seg.label.labelKo}'
          '${placeName == null ? '' : ' · $placeName'}',
        );
      }
      if (segments.length > 12) {
        buf.writeln('· …외 ${segments.length - 12}개 구간');
      }
    }
    buf.writeln('— 산보 (로컬 기록)');
    return buf.toString().trimRight();
  }

  /// JSON object for one session (meta + windows; samples optional).
  Map<String, Object?> toJsonDocument({
    required WalkSession session,
    required List<MinuteWindow> windows,
    List<LocationSample> samples = const [],
    List<RouteExclusion> exclusions = const [],
    bool includeSamples = false,
  }) {
    return {
      'schema_version': 2,
      'export_kind': 'sanbo_session',
      'session': {
        'id': session.id,
        'started_at': session.startedAt.toIso8601String(),
        'ended_at': session.endedAt?.toIso8601String(),
        'status': session.status.name,
        'tracking_mode': session.trackingMode.name,
        'timezone': session.timezone,
        'total_distance_m': session.totalDistanceM,
        'duration_s': session.durationS,
        'moving_time_s': session.movingTimeS,
        'stationary_time_s': session.stationaryTimeS,
        'avg_speed_mps': session.avgSpeedMps,
        'valid_sample_count': session.validSampleCount,
        'median_accuracy_m': session.medianAccuracyM,
        'notes': session.notes,
      },
      'exclusions': exclusions.map(_exclusionJson).toList(),
      'windows': windows.map(_windowJson).toList(),
      if (includeSamples) 'samples': samples.map(_sampleJson).toList(),
    };
  }

  /// NDJSON: meta line + one sample per line (reference log spirit).
  String toNdjson({
    required WalkSession session,
    required List<MinuteWindow> windows,
    required List<LocationSample> samples,
    required List<RouteExclusion> exclusions,
  }) {
    final meta = {
      'type': 'session',
      'schema_version': 2,
      'session': toJsonDocument(
        session: session,
        windows: windows,
        exclusions: exclusions,
      )['session'],
      'window_count': windows.length,
      'sample_count': samples.length,
      'exclusion_count': exclusions.length,
    };
    final buf = StringBuffer()..writeln(jsonEncode(meta));
    for (final exclusion in exclusions) {
      buf.writeln(
        jsonEncode({'type': 'exclusion', ..._exclusionJson(exclusion)}),
      );
    }
    for (final s in samples) {
      buf.writeln(jsonEncode({'type': 'sample', ..._sampleJson(s)}));
    }
    for (final w in windows) {
      buf.writeln(jsonEncode({'type': 'window', ..._windowJson(w)}));
    }
    return buf.toString();
  }

  Map<String, Object?> _windowJson(MinuteWindow w) => {
    'window_start': w.windowStart.toIso8601String(),
    'duration_s': w.durationS,
    'partial': w.partial,
    'distance_m': w.distanceM,
    'avg_speed_mps': w.avgSpeedMps,
    'stationary_ratio': w.stationaryRatio,
    'quality': w.quality.name,
    'hypothesis_label': w.hypothesisLabel.storageKey,
    'hypothesis_confidence': w.hypothesisConfidence,
    'user_label': w.userLabel?.storageKey,
    'user_confirmed': w.userConfirmed,
    'user_exclusion_id': w.userExclusionId,
    'user_note': w.userNote,
    'place_name': w.placeName,
    'place_address': w.placeAddress,
  };

  Map<String, Object?> _exclusionJson(RouteExclusion exclusion) => {
    'id': exclusion.id,
    'session_id': exclusion.sessionId,
    'start_at': exclusion.startAt.toUtc().toIso8601String(),
    'end_at': exclusion.endAt.toUtc().toIso8601String(),
    'reason': exclusion.reason.name,
    'created_at': exclusion.createdAt.toUtc().toIso8601String(),
  };

  Map<String, Object?> _sampleJson(LocationSample s) => {
    'ts': s.timestamp.toIso8601String(),
    'lat': s.latitude,
    'lon': s.longitude,
    'accuracy_m': s.accuracyM,
    'speed_mps': s.speedMps,
    'is_filtered_out': s.isFilteredOut,
  };

  String _hhmm(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
