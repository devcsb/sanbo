import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/walk_repository.dart';
import '../../domain/models/walk_session.dart';
import '../../domain/services/walk_stats.dart';

const historyPageSize = 50;

final historyPageProvider = StateProvider<int>((ref) => 1);

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

/// Bump to refresh history list after stop/delete.
final historyTickProvider = StateProvider<int>((ref) => 0);
