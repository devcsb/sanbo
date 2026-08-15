import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/walk_repository.dart';
import '../../domain/models/walk_session.dart';
import '../../domain/services/daily_walk_stats.dart';
import '../../domain/services/walk_stats.dart';

const historyPageSize = 50;

final historyPageProvider = StateProvider<int>((ref) => 1);

final dailyWeekEndProvider = StateProvider<DateTime>(
  (ref) => localDateOnly(DateTime.now()),
);

final dailySelectedDayProvider = StateProvider<DateTime>(
  (ref) => localDateOnly(DateTime.now()),
);

class DailyActivitySnapshot {
  const DailyActivitySnapshot({
    required this.days,
    required this.weekStart,
    required this.weekEnd,
  });

  final List<DailyWalkStats> days;
  final DateTime weekStart;
  final DateTime weekEnd;
}

class HistorySnapshot {
  const HistorySnapshot({
    required this.sessions,
    required this.stats,
    required this.hasMore,
  });

  final List<WalkSession> sessions;
  final WalkStats stats;
  final bool hasMore;
}

final completedHistoryProvider = FutureProvider<HistorySnapshot>((ref) async {
  ref.watch(historyTickProvider);
  final page = ref.watch(historyPageProvider);
  final requested = page * historyPageSize;
  final repo = ref.watch(walkRepositoryProvider);
  final loaded = await repo.listCompleted(limit: requested + 1);
  final hasMore = loaded.length > requested;
  final sessions = hasMore ? loaded.sublist(0, requested) : loaded;
  return HistorySnapshot(
    sessions: sessions,
    stats: await repo.completedStats(),
    hasMore: hasMore,
  );
});

final dailyActivityProvider = FutureProvider<DailyActivitySnapshot>((
  ref,
) async {
  ref.watch(historyTickProvider);
  final weekEnd = ref.watch(dailyWeekEndProvider);
  final weekStart = weekEnd.subtract(const Duration(days: 6));
  final repo = ref.watch(walkRepositoryProvider);
  final days = await repo.dailyStats(
    startDate: weekStart,
    endDateExclusive: weekEnd.add(const Duration(days: 1)),
  );
  return DailyActivitySnapshot(
    days: days,
    weekStart: weekStart,
    weekEnd: weekEnd,
  );
});

/// Bump to refresh history list after stop/delete.
final historyTickProvider = StateProvider<int>((ref) => 0);

DateTime localDateOnly(DateTime value) {
  final local = value.isUtc ? value.toLocal() : value;
  return DateTime(local.year, local.month, local.day);
}
