/// MVP activity hypothesis labels (PRD FR-12). Not ground truth.
enum ActivityLabel {
  walkSteady,
  walkBrisk,
  strollSlow,
  stationary,
  placeStay,
  cafeOrShop,
  parkLinger,
  vehicle,
  unknown,
}

extension ActivityLabelX on ActivityLabel {
  String get storageKey => switch (this) {
    ActivityLabel.walkSteady => 'walk_steady',
    ActivityLabel.walkBrisk => 'walk_brisk',
    ActivityLabel.strollSlow => 'stroll_slow',
    ActivityLabel.stationary => 'stationary',
    ActivityLabel.placeStay => 'place_stay',
    ActivityLabel.cafeOrShop => 'cafe_or_shop',
    ActivityLabel.parkLinger => 'park_linger',
    ActivityLabel.vehicle => 'vehicle',
    ActivityLabel.unknown => 'unknown',
  };

  String get labelKo => switch (this) {
    ActivityLabel.walkSteady => '걷기',
    ActivityLabel.walkBrisk => '빠른 걷기',
    ActivityLabel.strollSlow => '느리게 거닐기',
    ActivityLabel.stationary => '정지',
    ActivityLabel.placeStay => '한곳 체류',
    ActivityLabel.cafeOrShop => '카페·상점 추정',
    ActivityLabel.parkLinger => '공원 체류',
    ActivityLabel.vehicle => '차량 이동 가능',
    ActivityLabel.unknown => '알 수 없음',
  };

  static ActivityLabel fromStorage(String? key) {
    if (key == null) return ActivityLabel.unknown;
    return ActivityLabel.values.firstWhere(
      (e) => e.storageKey == key,
      orElse: () => ActivityLabel.unknown,
    );
  }
}
