import 'tracking_mode.dart';

enum SessionStatus { active, completed, crashedRecovered, discarded }

class WalkSession {
  const WalkSession({
    required this.id,
    required this.startedAt,
    required this.timezone,
    required this.trackingMode,
    this.endedAt,
    this.status = SessionStatus.active,
    this.totalDistanceM,
    this.durationS,
    this.movingTimeS,
    this.stationaryTimeS,
    this.avgSpeedMps,
    this.validSampleCount,
    this.medianAccuracyM,
    this.notes,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final SessionStatus status;
  final TrackingMode trackingMode;
  final String timezone;
  final double? totalDistanceM;
  final int? durationS;
  final int? movingTimeS;
  final int? stationaryTimeS;
  final double? avgSpeedMps;
  final int? validSampleCount;
  final double? medianAccuracyM;
  final String? notes;

  bool get isActive => status == SessionStatus.active && endedAt == null;

  WalkSession copyWith({
    DateTime? endedAt,
    SessionStatus? status,
    double? totalDistanceM,
    int? durationS,
    int? movingTimeS,
    int? stationaryTimeS,
    double? avgSpeedMps,
    int? validSampleCount,
    double? medianAccuracyM,
    String? notes,
  }) {
    return WalkSession(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      status: status ?? this.status,
      trackingMode: trackingMode,
      timezone: timezone,
      totalDistanceM: totalDistanceM ?? this.totalDistanceM,
      durationS: durationS ?? this.durationS,
      movingTimeS: movingTimeS ?? this.movingTimeS,
      stationaryTimeS: stationaryTimeS ?? this.stationaryTimeS,
      avgSpeedMps: avgSpeedMps ?? this.avgSpeedMps,
      validSampleCount: validSampleCount ?? this.validSampleCount,
      medianAccuracyM: medianAccuracyM ?? this.medianAccuracyM,
      notes: notes ?? this.notes,
    );
  }
}
