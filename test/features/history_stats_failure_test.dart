import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sanbo/data/app_database.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/features/history/history_providers.dart';
import 'package:sanbo/features/history/history_screen.dart';
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
      },
    );
  }
}
