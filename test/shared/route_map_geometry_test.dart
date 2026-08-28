import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/shared/widgets/route_map.dart';

void main() {
  test('converts a large route to stable geometry once', () {
    final points = [
      for (var index = 0; index < 4500; index++)
        (lat: 37.5665 + index * 0.00001, lon: 126.978 + index * 0.00001),
    ];

    final geometry = RouteMapGeometry.fromFragments([points]);

    expect(geometry.fragments, hasLength(1));
    expect(geometry.fragments.single, hasLength(4500));
    expect(geometry.points, hasLength(4500));
    expect(geometry.center.latitude, closeTo(points[2250].lat, 0.0000001));
    expect(geometry.center.longitude, closeTo(points[2250].lon, 0.0000001));
  });
}
