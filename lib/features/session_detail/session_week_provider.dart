import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/walk_repository.dart';
import '../../domain/services/session_week_summary.dart';
import '../history/history_providers.dart';

final sessionWeekSummaryProvider = FutureProvider.autoDispose
    .family<SessionWeekSummary?, String>((ref, id) {
      ref.watch(historyTickProvider);
      return ref.watch(walkRepositoryProvider).sessionWeekSummary(id);
    });
