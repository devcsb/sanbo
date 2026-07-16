import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/core/theme/app_theme.dart';
import 'package:sanbo/features/home/home_screen.dart';
import 'package:sanbo/features/intro/intro_screen.dart';
import 'package:sanbo/features/settings/settings_screen.dart';
import 'package:sanbo/shared/widgets/ui_bits.dart';

void main() {
  test('semantic theme roles meet contrast and target baselines', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final scheme = theme.colorScheme;
      expect(
        _contrast(scheme.primary, scheme.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(scheme.onSurfaceVariant, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(scheme.outline, scheme.surface),
        greaterThanOrEqualTo(3),
      );
      expect(
        _contrast(scheme.tertiary, scheme.onTertiary),
        greaterThanOrEqualTo(4.5),
      );

      final filledSize = theme.filledButtonTheme.style?.minimumSize?.resolve(
        {},
      );
      final outlinedSize = theme.outlinedButtonTheme.style?.minimumSize
          ?.resolve({});
      final iconSize = theme.iconButtonTheme.style?.minimumSize?.resolve({});
      expect(filledSize?.height, greaterThanOrEqualTo(48));
      expect(filledSize?.width.isFinite, isTrue);
      expect(outlinedSize?.height, greaterThanOrEqualTo(48));
      expect(outlinedSize?.width.isFinite, isTrue);
      expect(iconSize?.height, greaterThanOrEqualTo(48));
      expect(iconSize?.width, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('metric strip stacks without overflow at large text', (
    tester,
  ) async {
    await _setCompactPhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: MetricStrip(
                  metrics: [
                    MetricData(label: '시간', value: '1:24:37', emphasize: true),
                    MetricData(label: '거리', value: '12.34 km'),
                    MetricData(label: '평균 속도', value: '8.7 km/h'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('1:24:37'), findsOneWidget);
    expect(find.text('12.34 km'), findsOneWidget);
    expect(find.text('8.7 km/h'), findsOneWidget);
  });

  testWidgets('top-level screens remain usable on a compact large-text phone', (
    tester,
  ) async {
    await _setCompactPhone(tester);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: HomeScreen(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.text('산책 시작'), findsOneWidget);
    await tester.ensureVisible(find.text('산책 시작'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: SettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('모든 기록 삭제'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: IntroScreen(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.text('시작하기'), findsOneWidget);
    await tester.ensureVisible(find.text('시작하기'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _setCompactPhone(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 568);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

double _contrast(Color a, Color b) {
  final lighter = a.computeLuminance() > b.computeLuminance() ? a : b;
  final darker = identical(lighter, a) ? b : a;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}
