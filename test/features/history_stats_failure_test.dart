import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sanbo/data/app_database.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/features/history/history_providers.dart';
import 'package:sanbo/features/history/history_screen.dart';
import 'package:sanbo/features/session_detail/session_detail_screen.dart';
import 'package:sanbo/features/session_detail/session_week_provider.dart';
import 'package:sanbo/domain/services/session_export.dart';
import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final floating in [false, true]) {
    testWidgets(
      'damaged ${floating ? 'real' : 'integer'} totals keep history accessible',
      (tester) async {
        late WalkRepository repo;
        late HistorySnapshot snapshot;
        await tester.runAsync(() async {
          await initializeDateFormatting('ko');
          ensureSqfliteFfi();
          final db = await openAppDatabase(path: inMemoryDatabasePath);
          repo = WalkRepository(db);
          for (var i = 0; i < 2; i++) {
            await db.insert('sessions', {
              'id': 'old-$i',
              'started_at': '2026-11-07T00:00:00Z',
              'ended_at': '2026-11-07T00:01:00Z',
              'status': 'completed',
              'timezone': 'UTC',
              'tracking_mode': 'balanced',
              'total_distance_m': floating ? 1e308 : 100,
              'duration_s': floating ? 60 : 9223372036854775807,
            });
          }
          final container = ProviderContainer(
            overrides: [walkRepositoryProvider.overrideWithValue(repo)],
          );
          try {
            snapshot = await container.read(completedHistoryProvider.future);
          } finally {
            container.dispose();
          }
        });
        addTearDown(() => tester.runAsync(repo.close));
        expect(snapshot.sessions, hasLength(2));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              walkRepositoryProvider.overrideWithValue(repo),
              dailyActivityProvider.overrideWith(
                (ref) async => throw StateError('daily fixture unavailable'),
              ),
              completedSessionsProvider.overrideWith((ref) async => snapshot),
            ],
            child: const MaterialApp(home: HistoryScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('일부 통계를 표시할 수 없어요'), findsOneWidget);
        expect(find.text('기록을 불러오지 못했어요'), findsNothing);
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(find.byType(InkWell), findsWidgets);
        expect(tester.takeException(), isNull);
        final router = GoRouter(
          initialLocation: '/history/old-0',
          routes: [
            GoRoute(
              path: '/history',
              builder: (_, _) => const Scaffold(body: Text('records')),
            ),
            GoRoute(
              path: '/history/:id',
              builder: (_, state) =>
                  SessionDetailScreen(sessionId: state.pathParameters['id']!),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            key: const ValueKey('detail-scope'),
            overrides: [
              walkRepositoryProvider.overrideWithValue(repo),
              sessionWeekSummaryProvider.overrideWith((ref, id) async => null),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        for (
          var i = 0;
          i < 200 && find.byTooltip('원본 파일 저장').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pumpAndSettle();
        expect(find.byTooltip('원본 파일 저장'), findsOneWidget);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionDetailScreen)),
        );
        final detail = container
            .read(sessionDetailProvider('old-0'))
            .requireValue!;
        final original = const SessionExport().toNdjson(
          session: detail.session,
          windows: detail.windows,
          samples: detail.samples,
          exclusions: detail.exclusions,
        );
        expect(original, contains('"id":"old-0"'));
        expect(original, contains(floating ? '1e+308' : '9223372036854775807'));
        await tester.tap(find.byTooltip('삭제'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '삭제'));
        for (
          var i = 0;
          i < 200 && find.text('records').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          expect(await repo.getSession('old-0'), isNull);
          expect(await repo.getSession('old-1'), isNotNull);
        });
        expect(tester.takeException(), isNull);
      },
    );
  }
}
