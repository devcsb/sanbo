import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/shared/widgets/route_map.dart';

void main() {
  testWidgets('RouteMap mounts with polyline and OSM attribution',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RouteMap(
            offlinePreview: true,
            points: [
              (lat: 37.5665, lon: 126.9780),
              (lat: 37.5670, lon: 126.9785),
              (lat: 37.5675, lon: 126.9790),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(RouteMap), findsOneWidget);
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
  });
}
