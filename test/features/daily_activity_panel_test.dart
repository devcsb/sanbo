import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/core/theme/app_theme.dart';
import 'package:sanbo/domain/services/daily_walk_stats.dart';
import 'package:sanbo/features/history/daily_activity_panel.dart';
import 'package:sanbo/features/history/history_providers.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko');
  });

  testWidgets('daily panel shows seven dates and selected day metrics', (
    tester,
  ) async {
    final days = _days();
    await _pumpPanel(tester, days, selected: DateTime(2026, 8, 12));

    expect(find.text('일별 운동량'), findsOneWidget);
    expect(find.text('4.00 km'), findsOneWidget);
    expect(find.text('4:00:00'), findsOneWidget);
    expect(find.text('4회'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^8월 12일')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^8월 15일')), findsOneWidget);
  });

  testWidgets('daily panel navigates weeks but never into the future', (
    tester,
  ) async {
    final days = _days();
    await _pumpPanel(tester, days, selected: DateTime(2026, 8, 15));

    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
    );
    expect(next.onPressed, isNull);

    await tester.tap(find.byTooltip('이전 7일'));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DailyActivityPanel)),
    );
    expect(container.read(dailyWeekEndProvider), DateTime(2026, 8, 8));
  });

  testWidgets('selecting a date changes metrics without leaving the panel', (
    tester,
  ) async {
    final days = _days();
    await _pumpPanel(tester, days, selected: DateTime(2026, 8, 15));

    await tester.tap(find.bySemanticsLabel(RegExp(r'^8월 11일')));
    await tester.pump();

    expect(find.text('3.00 km'), findsOneWidget);
    expect(find.text('3:00:00'), findsOneWidget);
    expect(find.text('3회'), findsOneWidget);
  });

  testWidgets('daily panel renders a retry state for an API failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyActivityProvider.overrideWith(
            (ref) async => throw StateError('offline'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: DailyActivityPanel()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('일별 운동량을 불러오지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('daily panel stacks safely on a compact large-text phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: ProviderScope(
          overrides: [
            dailyActivityProvider.overrideWith(
              (ref) async => DailyActivitySnapshot(
                days: _days(),
                weekStart: DateTime(2026, 8, 9),
                weekEnd: DateTime(2026, 8, 15),
              ),
            ),
            dailyWeekEndProvider.overrideWith((ref) => DateTime(2026, 8, 15)),
            dailySelectedDayProvider.overrideWith(
              (ref) => DateTime(2026, 8, 15),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: SingleChildScrollView(child: DailyActivityPanel()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPanel(
  WidgetTester tester,
  List<DailyWalkStats> days, {
  required DateTime selected,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dailyActivityProvider.overrideWith(
          (ref) async => DailyActivitySnapshot(
            days: days,
            weekStart: days.first.date,
            weekEnd: days.last.date,
          ),
        ),
        dailyWeekEndProvider.overrideWith((ref) => days.last.date),
        dailySelectedDayProvider.overrideWith((ref) => selected),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: DailyActivityPanel()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

List<DailyWalkStats> _days() {
  return [
    for (var index = 0; index < 7; index++)
      DailyWalkStats(
        date: DateTime(2026, 8, 9 + index),
        walkCount: index + 1,
        totalDistanceM: (index + 1) * 1000,
        totalDurationS: (index + 1) * 3600,
      ),
  ];
}
