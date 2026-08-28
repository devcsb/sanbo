import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sanbo/core/theme/app_theme.dart';
import 'package:sanbo/data/activity_data_source.dart';
import 'package:sanbo/domain/services/daily_walk_stats.dart';
import 'package:sanbo/domain/services/walk_stats.dart';
import 'package:sanbo/features/history/history_providers.dart';
import 'package:sanbo/features/history/history_screen.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko');
  });

  testWidgets('empty history still exposes daily activity', (tester) async {
    final today = DateTime(2026, 8, 29);
    final days = [
      for (var index = 0; index < 7; index++)
        DailyWalkStats.zero(today.subtract(Duration(days: 6 - index))),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          completedSessionsProvider.overrideWith(
            (ref) async => HistorySnapshot(
              sessions: const [],
              stats: WalkStats.empty(),
              hasMore: false,
            ),
          ),
          dailyActivityProvider.overrideWith(
            (ref) async => DailyActivitySnapshot(
              days: days,
              weekStart: days.first.date,
              weekEnd: days.last.date,
            ),
          ),
          activityDataSourceProvider.overrideWithValue(
            const UnavailableActivityDataSource(),
          ),
          dailyWeekEndProvider.overrideWith((ref) => today),
          dailySelectedDayProvider.overrideWith((ref) => today),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const HistoryScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('일별 운동량'), findsOneWidget);
    expect(find.text('산책 시작하기'), findsOneWidget);
    expect(find.byType(ListView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
