/// Public map tile sources (PLATFORM_AND_MAPS D-MAP-*).
enum TileSourceId {
  /// OpenStreetMap-compatible public tiles (MVP default).
  osmPublic,

  /// VWorld 2D base (v1, requires API key).
  vworld2d,
}

extension TileSourceIdX on TileSourceId {
  String get labelKo => switch (this) {
    TileSourceId.osmPublic => 'OpenStreetMap (공개)',
    TileSourceId.vworld2d => '브이월드 (공공)',
  };

  String get attribution => switch (this) {
    TileSourceId.osmPublic => '© OpenStreetMap contributors',
    TileSourceId.vworld2d => '© 브이월드(VWorld) · 국토교통부',
  };
}
