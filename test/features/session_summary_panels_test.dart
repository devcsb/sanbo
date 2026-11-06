import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/features/session_detail/session_summary_panels.dart';

Widget host({double scale = 1, bool reduced = false, bool dark = false}) =>
    MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduced,
        ),
        child: Scaffold(body: SingleChildScrollView(child: _Harness())),
      ),
    );

class _Harness extends StatefulWidget {
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Text('2.00 km'),
      SessionSummaryPanels(
        index: index,
        onPageChanged: (value) => setState(() => index = value),
        route: const Column(
          children: [
            Text('경로 본문'),
            TextField(key: ValueKey('route-input')),
          ],
        ),
        week: Column(
          children: [for (var i = 0; i < 14; i++) Text('긴 주간 본문 $i')],
        ),
      ),
    ],
  );
}

void main() {
  testWidgets(
    'tabs, swipe, keyboard share selection and exclude hidden semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('summary-tab-0'))).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.byKey(const ValueKey('summary-tab-1')));
      await tester.pumpAndSettle();
      expect(find.text('2.00 km'), findsOneWidget);
      expect(find.bySemanticsLabel('경로 본문'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('경로 본문'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('경로 본문'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('경로 본문'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('route-input')));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('경로 본문'), findsOneWidget);
      semantics.dispose();
    },
  );
  testWidgets(
    'drag can reverse beyond halfway and vertical gestures scroll the page',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(160, 140));
      await gesture.moveBy(const Offset(-210, 0));
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.moveBy(const Offset(205, 0));
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SessionSummaryPanels>(find.byType(SessionSummaryPanels))
            .index,
        0,
      );
      await tester.dragFrom(const Offset(160, 140), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SessionSummaryPanels>(find.byType(SessionSummaryPanels))
            .index,
        0,
      );
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        greaterThan(0),
      );
    },
  );
  testWidgets('reduced motion tab selection is immediate in dark landscape', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(scale: 2, reduced: true, dark: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('summary-tab-1')));
    await tester.pump();
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 1);
    expect(tester.takeException(), isNull);
  });
  for (final (origin, multiTouch, cancelled) in [
    (0, false, true),
    (1, false, true),
    (0, true, true),
    (0, true, false),
  ]) {
    testWidgets(
      'interrupted drag restores panel $origin (multiple: $multiTouch, cancel: $cancelled)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var selected = origin;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => SessionSummaryPanels(
                  index: selected,
                  onPageChanged: (index) => setState(() => selected = index),
                  route: const SizedBox(height: 200, child: Text('route')),
                  week: const SizedBox(height: 200, child: Text('week')),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final first = await tester.startGesture(
          const Offset(160, 140),
          pointer: 1,
        );
        await first.moveBy(Offset(origin == 0 ? -220 : 220, 0));
        await tester.pump(const Duration(milliseconds: 100));
        if (multiTouch) {
          final second = await tester.startGesture(
            const Offset(200, 160),
            pointer: 2,
          );
          if (cancelled) {
            await first.cancel();
          } else {
            await first.up();
          }
          await second.up();
        } else {
          await first.cancel();
        }
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SessionSummaryPanels>(find.byType(SessionSummaryPanels))
              .index,
          origin,
        );
        expect(
          tester.widget<PageView>(find.byType(PageView)).controller!.page,
          origin,
        );
        // A fresh, ordinary gesture still works after cancellation.
        await tester.dragFrom(
          const Offset(160, 140),
          Offset(origin == 0 ? -280 : 280, 0),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SessionSummaryPanels>(find.byType(SessionSummaryPanels))
              .index,
          1 - origin,
        );
      },
    );
  }
  for (final scale in [1.0, 1.6, 2.0]) {
    testWidgets('320px scale $scale natural panel heights fit long content', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(host(scale: scale, reduced: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('summary-tab-1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('긴 주간 본문 13'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
