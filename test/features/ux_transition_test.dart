import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sanbo/core/theme/app_theme.dart';
import 'package:sanbo/domain/services/walk_stats.dart';
import 'package:sanbo/features/history/history_providers.dart';
import 'package:sanbo/features/history/history_screen.dart';
import 'package:sanbo/shared/widgets/app_motion.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko');
  });

  testWidgets('loading to data keeps layout stable and has no exception', (
    tester,
  ) async {
    final result = Completer<HistorySnapshot>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          completedSessionsProvider.overrideWith((ref) => result.future),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const HistoryScreen(),
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(SmoothSwitcher), findsOneWidget);

    result.complete(
      HistorySnapshot(
        sessions: const [],
        stats: WalkStats.empty(),
        hasMore: false,
      ),
    );
    await tester.pump();
    await tester.pump(AppMotion.standard);

    expect(find.text('아직 기록이 없어요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
