import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/services/route_playback.dart';
import 'package:sanbo/shared/widgets/route_map.dart';

void main() {
  testWidgets('RouteMap draws each route fragment as a separate polyline', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RouteMap(
            offlinePreview: true,
            fragments: [
              [(lat: 37.5665, lon: 126.9780), (lat: 37.5670, lon: 126.9785)],
              [(lat: 37.5700, lon: 126.9810), (lat: 37.5705, lon: 126.9815)],
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final layer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
    expect(
      layer.polylines.where((line) => line.strokeWidth == 3.5),
      hasLength(2),
    );
    expect(layer.polylines.any((line) => line.points.length == 4), isFalse);
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
  });

  testWidgets('RouteMap empty points shows friendly overlay', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RouteMap(offlinePreview: true, fragments: [])),
      ),
    );
    await tester.pump();
    expect(find.text('경로 포인트가 없어요'), findsOneWidget);
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
  });

  testWidgets('RouteMap distinguishes progress, selection, and replay marker', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RouteMap(
            offlinePreview: true,
            fragments: [
              [
                (lat: 37.5665, lon: 126.9780),
                (lat: 37.5670, lon: 126.9785),
                (lat: 37.5675, lon: 126.9790),
              ],
            ],
            progress: RoutePlaybackCursor(fragmentIndex: 0, pointIndex: 1),
            highlightedFragments: [
              [(lat: 37.5670, lon: 126.9785), (lat: 37.5675, lon: 126.9790)],
            ],
            currentPoint: (lat: 37.5670, lon: 126.9785),
          ),
        ),
      ),
    );
    await tester.pump();

    final polylines = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
    expect(polylines.polylines, hasLength(3));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '재생 위치',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == '선택한 활동 구간',
      ),
      findsOneWidget,
    );
  });
}
