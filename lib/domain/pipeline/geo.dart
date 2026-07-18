import 'dart:math' as math;

/// Haversine distance in meters between two WGS84 points.
double haversineMeters({
  required double lat1,
  required double lon1,
  required double lat2,
  required double lon2,
}) {
  const earthRadiusM = 6371000.0;
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusM * c;
}

/// Path length with optional micro-jitter suppression.
///
/// Segments shorter than [minSegmentM] are ignored so stationary GPS noise
/// does not inflate distance, while real walking steps still accumulate.
double pathDistanceMeters(
  Iterable<({double lat, double lon})> points, {
  double minSegmentM = 1.5,
}) {
  final list = points.toList();
  if (list.length < 2) return 0;
  var total = 0.0;
  for (var i = 1; i < list.length; i++) {
    final d = haversineMeters(
      lat1: list[i - 1].lat,
      lon1: list[i - 1].lon,
      lat2: list[i].lat,
      lon2: list[i].lon,
    );
    if (d >= minSegmentM) {
      total += d;
    }
  }
  return total;
}

double _toRad(double deg) => deg * math.pi / 180.0;

/// Convert any DateTime to the device local timeline (defensive vs UTC GPS).
DateTime asLocal(DateTime ts) => ts.isUtc ? ts.toLocal() : ts;

/// Floor [ts] to **local** wall-clock minute boundary.
///
/// Always converts UTC → local first. Geolocator samples are UTC; session
/// bounds use `DateTime.now()` (local). Without this, minute keys diverge
/// in non-UTC zones (e.g. KST) and every window becomes an empty gap.
DateTime floorToMinute(DateTime ts) {
  final local = asLocal(ts);
  return DateTime(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
  );
}
