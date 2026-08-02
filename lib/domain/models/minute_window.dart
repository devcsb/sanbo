import 'activity_label.dart';

enum WindowQuality { high, medium, low, gap }

/// One wall-clock minute aggregation (Sanbo first-class record).
class MinuteWindow {
  const MinuteWindow({
    required this.windowStart,
    required this.durationS,
    required this.partial,
    required this.sampleCount,
    required this.rawSampleCount,
    required this.distanceM,
    required this.avgSpeedMps,
    required this.maxSpeedMps,
    required this.stationaryRatio,
    required this.quality,
    this.centroidLat,
    this.centroidLon,
    this.startLat,
    this.startLon,
    this.endLat,
    this.endLon,
    this.gapReason,
    this.hypothesisLabel = ActivityLabel.unknown,
    this.hypothesisConfidence = 0,
    this.evidence = const [],
    this.userLabel,
    this.userNote,
    this.userConfirmed = false,
    this.placeId,
    this.placeName,
    this.placeAddress,
  });

  final DateTime windowStart;
  final int durationS;
  final bool partial;
  final int sampleCount;
  final int rawSampleCount;
  final double distanceM;
  final double avgSpeedMps;
  final double maxSpeedMps;
  final double stationaryRatio;
  final WindowQuality quality;
  final double? centroidLat;
  final double? centroidLon;
  final double? startLat;
  final double? startLon;
  final double? endLat;
  final double? endLon;
  final String? gapReason;
  final ActivityLabel hypothesisLabel;
  final double hypothesisConfidence;
  final List<String> evidence;
  final ActivityLabel? userLabel;
  final String? userNote;
  final bool userConfirmed;
  final int? placeId;
  final String? placeName;
  final String? placeAddress;

  /// Display label: user override wins (PRD FR-11).
  ActivityLabel get displayLabel => userLabel ?? hypothesisLabel;
}
