import 'dart:math' as math;

import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Maximum interval for treating two GPS fixes as an observed path segment.
/// Longer intervals are unobserved and must not be bridged with a straight
/// line in live or completed-session metrics.
const trustedLocationGap = Duration(minutes: 1);

/// Displacements below this floor are treated as GPS micro-jitter.
const minMeaningfulSegmentDistanceM = 1.5;

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
  double minSegmentM = minMeaningfulSegmentDistanceM,
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

/// Round a positive observed span up to the integer-second storage contract.
/// Zero and negative spans remain zero.
int positiveDurationSeconds(DateTime start, DateTime end) {
  final microseconds = end.difference(start).inMicroseconds;
  if (microseconds <= 0) return 0;
  return (microseconds + Duration.microsecondsPerSecond - 1) ~/
      Duration.microsecondsPerSecond;
}

double _toRad(double deg) => deg * math.pi / 180.0;

var _timeZonesInitialized = false;

void _ensureTimeZonesInitialized() {
  if (_timeZonesInitialized) return;
  tz_data.initializeTimeZones();
  _timeZonesInitialized = true;
}

tz.Location? _locationFor(String? timezone) {
  if (timezone == null || timezone.isEmpty) return null;
  try {
    _ensureTimeZonesInitialized();
    return tz.getLocation(timezone);
  } on tz.LocationNotFoundException {
    // A future or corrupted archive can contain a zone unavailable in the
    // bundled tzdata. Fall back to the device zone instead of losing a walk.
    return null;
  }
}

/// Convert any DateTime to the session or device local timeline.
DateTime asLocal(DateTime ts, {String? timezone}) {
  final location = _locationFor(timezone);
  if (location == null) return ts.toLocal();
  return tz.TZDateTime.from(ts.toUtc(), location);
}

/// Floor [ts] to **local** wall-clock minute boundary.
///
/// Always converts an instant to the session wall-clock zone first.
DateTime floorToMinute(DateTime ts, {String? timezone}) {
  final local = asLocal(ts, timezone: timezone);
  final location = _locationFor(timezone);
  if (location == null) {
    return DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    );
  }
  // Constructing TZDateTime from wall-clock fields loses the fold during a
  // fall-back hour. Truncate the original instant instead, which preserves
  // the correct UTC occurrence of an ambiguous local minute.
  final elapsedInMinute = Duration(
    seconds: local.second,
    milliseconds: local.millisecond,
    microseconds: local.microsecond,
  );
  final flooredUtc = ts.toUtc().subtract(elapsedInMinute);
  return tz.TZDateTime.from(flooredUtc, location);
}
