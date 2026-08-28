import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activity_data_source.dart';
import '../../data/walk_repository.dart';
import '../../domain/models/walk_session.dart';
import '../../domain/services/daily_walk_stats.dart';
import '../../domain/services/local_calendar.dart' as calendar;
import '../../domain/services/walk_stats.dart';

const historyPageSize = 50;

final historyPageProvider = StateProvider<int>((ref) => 1);

final dailyWeekEndProvider = StateProvider<DateTime>(
  (ref) => localDateOnly(DateTime.now()),
);

final dailySelectedDayProvider = StateProvider<DateTime>(
  (ref) => localDateOnly(DateTime.now()),
);

final dailyAutoWeekEndProvider = StateProvider<DateTime>(
  (ref) => localDateOnly(DateTime.now()),
);

final activityDataSourceProvider = Provider<ActivityDataSource>(
  (ref) => const UnavailableActivityDataSource(),
);

class DailyActivitySnapshot {
  const DailyActivitySnapshot({
    required this.days,
    required this.weekStart,
    required this.weekEnd,
    this.stepsByDate = const {},
  });

  final List<DailyWalkStats> days;
  final DateTime weekStart;
  final DateTime weekEnd;
  final Map<DateTime, DailyStepSnapshot> stepsByDate;
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
  final weekStart = addLocalCalendarDays(weekEnd, -6);
  final repo = ref.watch(walkRepositoryProvider);
  final days = await repo.dailyStats(
    startDate: weekStart,
    endDateExclusive: addLocalCalendarDays(weekEnd, 1),
  );
  final source = ref.watch(activityDataSourceProvider);
  final sourceRows = await source.readDailySteps(
    startDate: weekStart,
    endDateExclusive: addLocalCalendarDays(weekEnd, 1),
  );
  final stepsByDate = <DateTime, DailyStepSnapshot>{
    for (final row in sourceRows) localDateOnly(row.date): row,
  };
  for (final day in days) {
    stepsByDate.putIfAbsent(
      day.date,
      () => DailyStepSnapshot.unavailable(day.date),
    );
  }
  return DailyActivitySnapshot(
    days: days,
    weekStart: weekStart,
    weekEnd: weekEnd,
    stepsByDate: stepsByDate,
  );
});

/// Bump to refresh history list after stop/delete.
final historyTickProvider = StateProvider<int>((ref) => 0);

DateTime localDateOnly(DateTime value) {
  return calendar.localDateOnly(value);
}

DateTime addLocalCalendarDays(DateTime value, int days) {
  return calendar.addLocalCalendarDays(value, days);
}

/// Refreshes the automatic “today” window without overwriting a week the user
/// deliberately browsed. The anchor tracks only automatic selections.
void refreshCurrentLocalDate(WidgetRef ref, {DateTime? now}) {
  final today = localDateOnly(now ?? DateTime.now());
  final automaticEnd = ref.read(dailyAutoWeekEndProvider);
  final currentEnd = ref.read(dailyWeekEndProvider);
  if (currentEnd == automaticEnd && currentEnd != today) {
    ref.read(dailyWeekEndProvider.notifier).state = today;
    if (ref.read(dailySelectedDayProvider) == automaticEnd) {
      ref.read(dailySelectedDayProvider.notifier).state = today;
    }
  }
  ref.read(dailyAutoWeekEndProvider.notifier).state = today;
}
