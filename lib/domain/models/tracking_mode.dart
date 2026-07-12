/// Battery / accuracy trade-off for GPS sampling.
enum TrackingMode {
  batterySaver,
  balanced,
  highAccuracy,
}

extension TrackingModeX on TrackingMode {
  String get labelKo => switch (this) {
        TrackingMode.batterySaver => '절전',
        TrackingMode.balanced => '균형',
        TrackingMode.highAccuracy => '정밀',
      };

  /// Short user-facing description (settings).
  String get descriptionKo => switch (this) {
        TrackingMode.batterySaver => '배터리를 아끼고, 위치는 조금 덜 자주 기록합니다',
        TrackingMode.balanced => '추천 · 배터리와 정확도의 균형',
        TrackingMode.highAccuracy => '위치를 더 자주 기록합니다 (배터리 사용 ↑)',
      };

  /// Target sample interval in seconds.
  int get targetIntervalSeconds => switch (this) {
        TrackingMode.batterySaver => 12,
        TrackingMode.balanced => 4,
        TrackingMode.highAccuracy => 2,
      };
}
