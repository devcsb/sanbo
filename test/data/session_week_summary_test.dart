import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sanbo/data/walk_repository.dart';
import '../helpers/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'repository uses moving_time_s and parses old wall clocks without rewriting daily stats',
    () async {
      ensureSqfliteFfi();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute(
        'CREATE TABLE sessions (id TEXT, started_at TEXT, ended_at TEXT, status TEXT, timezone TEXT, tracking_mode TEXT, total_distance_m REAL, duration_s INTEGER, moving_time_s INTEGER)',
      );
      for (final item in [
        ('a', '2026-10-27T09:00:00', '2026-10-27T09:20:00', 600),
        ('b', '2026-10-26T00:00:00Z', '2026-10-26T00:20:00Z', 300),
      ]) {
        await db.insert('sessions', {
          'id': item.$1,
          'started_at': item.$2,
          'ended_at': item.$3,
          'status': 'completed',
          'timezone': 'Asia/Seoul',
          'tracking_mode': 'balanced',
          'total_distance_m': 800,
          'duration_s': 1200,
          'moving_time_s': item.$4,
        });
      }
      final repo = WalkRepository(db);
      final result = await repo.sessionWeekSummary('a');
      expect(result!.movingTimeS, 900);
      expect(result.sessionCount, 2);
      final daily = await repo.dailyStats(
        startDate: DateTime(2026, 10, 26),
        endDateExclusive: DateTime(2026, 10, 28),
      );
      expect(daily.fold<int>(0, (sum, day) => sum + day.totalDurationS), 2400);
      expect(await repo.sessionWeekSummary('absent'), isNull);
    },
  );
}
