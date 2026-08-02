import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:sanbo/platform/place/place_lookup.dart';

void main() {
  test('placemark becomes a concise Korean place suggestion', () {
    const placemark = Placemark(
      name: '서울시청',
      street: '세종대로 110',
      subLocality: '태평로1가',
      locality: '중구',
      administrativeArea: '서울특별시',
    );
    final result = placeLookupResultFromPlacemark(placemark);
    expect(result?.suggestedName, '서울시청');
    expect(result?.address, '서울특별시 중구 태평로1가 세종대로 110');
  });

  test('coordinate-like placemark name falls back to street', () {
    const placemark = Placemark(name: '37.5665, 126.9780', street: '세종대로 110');
    final result = placeLookupResultFromPlacemark(placemark);
    expect(result?.suggestedName, '세종대로 110');
  });
}
