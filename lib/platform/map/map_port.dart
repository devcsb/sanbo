/// Abstract map surface (TRD MapPort). UI uses [RouteMap] (flutter_map + OSM).
abstract class MapPort {
  Future<void> setPolyline(List<({double lat, double lon})> points);
  Future<void> setMarkers({
    ({double lat, double lon})? start,
    ({double lat, double lon})? end,
  });
  Future<void> dispose();
}

/// Skeleton stub — kept for architecture parity with TRD.
class PlaceholderMapPort implements MapPort {
  List<({double lat, double lon})> polyline = const [];

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
