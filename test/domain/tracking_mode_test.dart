import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';

void main() {
  test('battery-friendly sampling intervals stay intentionally relaxed', () {
    expect(TrackingMode.batterySaver.targetIntervalSeconds, 20);
    expect(TrackingMode.balanced.targetIntervalSeconds, 8);
    expect(TrackingMode.highAccuracy.targetIntervalSeconds, 4);
  });

  test('settings copy communicates the battery and accuracy trade-off', () {
    expect(TrackingMode.batterySaver.descriptionKo, contains('배터리'));
    expect(TrackingMode.balanced.descriptionKo, contains('추천'));
    expect(TrackingMode.highAccuracy.descriptionKo, contains('정확도'));
  });
}
