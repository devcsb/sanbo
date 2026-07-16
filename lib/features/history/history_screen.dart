import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/walk_repository.dart';
import '../../domain/models/walk_session.dart';
import '../../shared/widgets/ui_bits.dart';
import 'history_providers.dart';

final completedSessionsProvider = FutureProvider<List<WalkSession>>((
  ref,
) async {
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
      appBar: AppBar(title: const AppBarTitle('기록')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => EmptyStateView(
          icon: Icons.inventory_2_outlined,
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

          return PageFrame(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: sessions.length + 1,
              separatorBuilder: (_, index) =>
                  SizedBox(height: index == 0 ? 20 : 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const PageIntro(
                        title: '산책 기록',
                        description: '걸었던 길과 시간을 차분히 돌아보세요.',
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const SectionLabel('최근 산책'),
                          StatusPill(
                            label: '${sessions.length}개의 산책',
                            icon: Icons.directions_walk_rounded,
                          ),
                        ],
                      ),
                    ],
                  );
                }

                final s = sessions[index - 1];
                final km = (s.totalDistanceM ?? 0) / 1000.0;
                final dur = Duration(seconds: s.durationS ?? 0);
                final title = dateFmt.format(s.startedAt);
                final subtitle = '${km.toStringAsFixed(2)} km  ·  ${_fmt(dur)}';
                return Semantics(
                  button: true,
                  label: '$title, $subtitle. 상세 보기',
                  excludeSemantics: true,
                  child: SoftPanel(
                    padding: EdgeInsets.zero,
                    child: InkWell(
                      onTap: () => context.go('/history/${s.id}'),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 72),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                          child: Row(
                            children: [
                              const TonalIcon(
                                icon: Icons.directions_walk_rounded,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${km.toStringAsFixed(2)} km',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '소요 시간 ${_fmt(dur)}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
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
