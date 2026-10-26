import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/features/session_detail/session_route_screen.dart';
import 'package:sanbo/shared/widgets/route_map.dart';

void main() {
  testWidgets(
    'preview flags are per caller and exploration closes with empty route',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RouteMap(
              fragments: [],
              offlinePreview: true,
              interactionFlags: InteractiveFlag.none,
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<FlutterMap>(find.byType(FlutterMap))
            .options
            .interactionOptions
            .flags,
        InteractiveFlag.none,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SessionRouteScreen(
                    fragments: [],
                    offlinePreview: true,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('확대'), findsOneWidget);
      final controller = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      final originalZoom = controller.camera.zoom;
      final originalCenter = controller.camera.center;
      await tester.tap(find.byTooltip('확대'));
      await tester.pump();
      expect(controller.camera.zoom, originalZoom + 1);
      await tester.tap(find.byTooltip('북쪽으로 이동'));
      await tester.pump();
      expect(
        controller.camera.center.latitude,
        greaterThan(originalCenter.latitude),
      );
      await tester.tap(find.byTooltip('전체 경로 맞춤'));
      await tester.pump();
      expect(controller.camera.zoom, originalZoom);
      expect(controller.camera.center, originalCenter);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    },
  );
}
