import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/walk_repository.dart';
import '../../domain/models/tracking_mode.dart';
import '../../domain/models/walk_session.dart';
import 'history_providers.dart';

final completedSessionsProvider = FutureProvider<List<WalkSession>>((ref) async {
  ref.watch(historyTickProvider);
  return ref.watch(walkRepositoryProvider).listCompleted();
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(completedSessionsProvider);
    final theme = Theme.of(context);
    final dateFmt = DateFormat('M월 d일 (E) HH:mm', 'ko');

    return Scaffold(
      appBar: AppBar(title: const Text('기록')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '기록을 불러오지 못했어요',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '$e',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(completedSessionsProvider),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.directions_walk_outlined,
                      size: 48,
                      color: theme.colorScheme.primary.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '아직 산책 기록이 없습니다',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '홈에서 산책을 시작하면\n여기에 분 단위 기록이 쌓입니다.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => context.go('/'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(200, 48),
                      ),
                      child: const Text('산책 시작하기'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final s = sessions[index];
              final km = (s.totalDistanceM ?? 0) / 1000.0;
              final dur = Duration(seconds: s.durationS ?? 0);
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                title: Text(dateFmt.format(s.startedAt)),
                subtitle: Text(
                  '${km.toStringAsFixed(2)} km · ${_fmt(dur)} · ${s.trackingMode.labelKo}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/history/${s.id}'),
              );
            },
          );
        },
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
