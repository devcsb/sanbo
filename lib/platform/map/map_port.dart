import 'tile_source.dart';

/// Abstract map surface (TRD MapPort). MapLibre implementation comes later.
abstract class MapPort {
  TileSourceId get tileSource;
  Future<void> setTileSource(TileSourceId source);
  Future<void> setPolyline(List<({double lat, double lon})> points);
  Future<void> setMarkers({
    ({double lat, double lon})? start,
    ({double lat, double lon})? end,
  });
  Future<void> dispose();
}

/// Skeleton stub — UI shows placeholder until MapLibre is wired.
class PlaceholderMapPort implements MapPort {
  PlaceholderMapPort({TileSourceId initial = TileSourceId.osmPublic})
    : _tileSource = initial;

  TileSourceId _tileSource;
  List<({double lat, double lon})> polyline = const [];

  @override
  TileSourceId get tileSource => _tileSource;

  @override
  Future<void> setTileSource(TileSourceId source) async {
    _tileSource = source;
  }

  @override
  Future<void> setPolyline(List<({double lat, double lon})> points) async {
    polyline = List.unmodifiable(points);
  }

  @override
  Future<void> setMarkers({
    ({double lat, double lon})? start,
    ({double lat, double lon})? end,
  }) async {}

  @override
  Future<void> dispose() async {}
}
