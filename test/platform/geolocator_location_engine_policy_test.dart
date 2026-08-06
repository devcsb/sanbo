import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/platform/location/location_request_policy.dart';

void main() {
  test('tracking modes map to deliberate battery request profiles', () {
    final saver = locationRequestProfile(TrackingMode.batterySaver);
    expect(saver.accuracy, LocationAccuracy.medium);
    expect(saver.interval, const Duration(seconds: 20));
    expect(saver.distanceFilterM, 10);
    expect(saver.keepCpuAwake, isFalse);

    final balanced = locationRequestProfile(TrackingMode.balanced);
    expect(balanced.accuracy, LocationAccuracy.high);
    expect(balanced.interval, const Duration(seconds: 8));
    expect(balanced.distanceFilterM, 5);
    expect(balanced.keepCpuAwake, isFalse);

    final precise = locationRequestProfile(TrackingMode.highAccuracy);
    expect(precise.accuracy, LocationAccuracy.bestForNavigation);
    expect(precise.interval, const Duration(seconds: 4));
    expect(precise.distanceFilterM, 2);
    expect(precise.keepCpuAwake, isTrue);
  });
}
