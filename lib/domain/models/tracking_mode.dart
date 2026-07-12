/// Battery / accuracy trade-off (TRD §4.1).
enum TrackingMode {
  batterySaver,
  balanced,
  highAccuracy,
}

extension TrackingModeX on TrackingMode {
  String get labelKo => switch (this) {
    TrackingMode.batterySaver => '절전',
    TrackingMode.balanced => '균형',
    TrackingMode.highAccuracy => '고정확',
  };

  /// Target sample interval in seconds.
  int get targetIntervalSeconds => switch (this) {
    TrackingMode.batterySaver => 12,
    TrackingMode.balanced => 4,
    TrackingMode.highAccuracy => 2,
  };
}
