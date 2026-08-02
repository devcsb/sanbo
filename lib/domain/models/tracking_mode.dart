/// Battery / accuracy trade-off for GPS sampling.
enum TrackingMode { batterySaver, balanced, highAccuracy }

extension TrackingModeX on TrackingMode {
  String get labelKo => switch (this) {
    TrackingMode.batterySaver => '절전',
    TrackingMode.balanced => '균형',
    TrackingMode.highAccuracy => '정밀',
  };

  /// Short user-facing description (settings).
  String get descriptionKo => switch (this) {
    TrackingMode.batterySaver => '약 20초 간격 · 배터리를 우선합니다',
    TrackingMode.balanced => '추천 · 약 8초 간격으로 기록합니다',
    TrackingMode.highAccuracy => '약 4초 간격 · 경로 정확도를 우선합니다',
  };

  /// Target sample interval in seconds.
  int get targetIntervalSeconds => switch (this) {
    TrackingMode.batterySaver => 20,
    TrackingMode.balanced => 8,
    TrackingMode.highAccuracy => 4,
  };
}
