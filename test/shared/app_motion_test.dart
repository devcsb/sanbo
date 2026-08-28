import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sanbo/shared/widgets/app_motion.dart';

void main() {
  testWidgets('motion duration is zero when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: SizedBox()),
      ),
    );

    expect(
      AppMotion.duration(
        tester.element(find.byType(SizedBox)),
        AppMotion.standard,
      ),
      Duration.zero,
    );
  });

  testWidgets('smooth switcher uses a keyed fade transition', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SmoothSwitcher(transitionKey: 'first', child: Text('first')),
      ),
    );

    expect(find.text('first'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SmoothSwitcher),
        matching: find.byType(FadeTransition),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: SmoothSwitcher(transitionKey: 'second', child: Text('second')),
      ),
    );
    await tester.pump(AppMotion.standard);

    expect(find.text('second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
