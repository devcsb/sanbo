import '../models/activity_label.dart';
import '../models/minute_window.dart';

class ActivityHypothesis {
  const ActivityHypothesis({
    required this.label,
    required this.confidence,
    required this.evidence,
  });

  final ActivityLabel label;
  final double confidence;
  final List<String> evidence;
}

/// Rule-based activity hypothesis (TRD §4.6). Not ground truth.
class ActivityInferencer {
  ActivityInferencer({this.minDisplayConfidence = 0.4});

  final double minDisplayConfidence;

  ActivityHypothesis infer(MinuteWindow w, {String? placeCategory}) {
    final evidence = <String>[];

    if (w.quality == WindowQuality.gap || w.sampleCount < 3) {
      evidence.add('quality:${w.quality.name}');
      evidence.add('sample_count:${w.sampleCount}');
      return ActivityHypothesis(
        label: ActivityLabel.unknown,
        confidence: w.sampleCount == 0 ? 0 : 0.25,
        evidence: evidence,
      );
    }

    evidence.add('speed_band:${w.avgSpeedMps.toStringAsFixed(2)} m/s');
    evidence.add('stationary_ratio:${w.stationaryRatio.toStringAsFixed(2)}');
    if (placeCategory != null) {
      evidence.add('place_category:$placeCategory');
    }

    if (w.avgSpeedMps >= 8.0) {
      return ActivityHypothesis(
        label: ActivityLabel.vehicle,
        confidence: 0.55,
        evidence: evidence,
      );
    }

    final stay =
        w.stationaryRatio >= 0.7 && w.distanceM < 25;
    if (stay) {
      if (placeCategory == 'cafe' ||
          placeCategory == 'shop' ||
          placeCategory == 'restaurant') {
        return ActivityHypothesis(
          label: ActivityLabel.cafeOrShop,
          confidence: 0.6,
          evidence: evidence,
        );
      }
      if (placeCategory == 'park') {
        return ActivityHypothesis(
          label: ActivityLabel.parkLinger,
          confidence: 0.55,
          evidence: evidence,
        );
      }
      if (w.distanceM < 15) {
        return ActivityHypothesis(
          label: ActivityLabel.placeStay,
          confidence: 0.5,
          evidence: evidence,
        );
      }
      return ActivityHypothesis(
        label: ActivityLabel.stationary,
        confidence: 0.55,
        evidence: evidence,
      );
    }

    if (w.avgSpeedMps >= 1.6 &&
        w.avgSpeedMps < 2.5 &&
        w.stationaryRatio < 0.3) {
      return ActivityHypothesis(
        label: ActivityLabel.walkBrisk,
        confidence: 0.7,
        evidence: evidence,
      );
    }
    if (w.avgSpeedMps >= 0.8 &&
        w.avgSpeedMps < 1.6 &&
        w.stationaryRatio < 0.35) {
      return ActivityHypothesis(
        label: ActivityLabel.walkSteady,
        confidence: 0.75,
        evidence: evidence,
      );
    }
    if (w.avgSpeedMps >= 0.3 && w.avgSpeedMps < 0.8) {
      return ActivityHypothesis(
        label: ActivityLabel.strollSlow,
        confidence: 0.6,
        evidence: evidence,
      );
    }

    return ActivityHypothesis(
      label: ActivityLabel.unknown,
      confidence: 0.35,
      evidence: evidence,
    );
  }
}
