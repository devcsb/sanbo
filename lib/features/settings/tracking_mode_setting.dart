import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/tracking_mode.dart';

final trackingModeSettingProvider = StateProvider<TrackingMode>(
  (ref) => TrackingMode.balanced,
);

TrackingMode trackingModeFromStoredName(String name) {
  for (final mode in TrackingMode.values) {
    if (mode.name == name) return mode;
  }
  return TrackingMode.balanced;
}
