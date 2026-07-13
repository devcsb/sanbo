import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/walk_repository.dart';
import '../../domain/models/walk_session.dart';
import '../../shared/widgets/ui_bits.dart';
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
    final dateFmt = DateFormat('M월 d일 (E) · HH:mm', 'ko');

    return Scaffold(
      appBar: AppBar(title: const Text('기록')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => EmptyStateView(
          icon: Icons.cloud_off_outlined,
          title: '기록을 불러오지 못했어요',
          message: '잠시 후 다시 시도해 주세요.',
          actionLabel: '다시 시도',
          onAction: () => ref.invalidate(completedSessionsProvider),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return EmptyStateView(
              icon: Icons.directions_walk_rounded,
              title: '아직 기록이 없어요',
              message: '홈에서 산책을 시작하면\n여기에 모입니다.',
              actionLabel: '산책 시작하기',
              onAction: () => context.go('/'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final s = sessions[index];
              final km = (s.totalDistanceM ?? 0) / 1000.0;
              final dur = Duration(seconds: s.durationS ?? 0);
              final title = dateFmt.format(s.startedAt);
              final subtitle =
                  '${km.toStringAsFixed(2)} km  ·  ${_fmt(dur)}';
              return Semantics(
                button: true,
                label: '$title, $subtitle. 상세 보기',
                child: Material(
                  color: theme.cardTheme.color ?? theme.colorScheme.surface,
                  shape: theme.cardTheme.shape,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.go('/history/${s.id}'),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 64),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: theme.colorScheme.outline,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
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
