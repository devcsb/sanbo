import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/platform/map/tile_source.dart';
import 'package:sanbo/shared/widgets/route_map.dart';

void main() {
  testWidgets('start button and map attribution smoke', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('산보')),
          body: const Column(
            children: [
              Text('산책 시작'),
              RouteMap(
                offlinePreview: true,
                points: [
                  (lat: 37.5665, lon: 126.9780),
                  (lat: 37.5670, lon: 126.9785),
                ],
                tileSource: TileSourceId.osmPublic,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('산책 시작'), findsOneWidget);
    expect(find.text('산보'), findsOneWidget);
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
    expect(find.byType(RouteMap), findsOneWidget);
  });
}
