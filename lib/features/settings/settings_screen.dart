import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../data/walk_repository.dart';
import '../../domain/models/tracking_mode.dart';
import '../../shared/widgets/ui_bits.dart';
import '../history/history_providers.dart';

final trackingModeSettingProvider = StateProvider<TrackingMode>(
  (ref) => TrackingMode.balanced,
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(trackingModeSettingProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SoftPanel(
            child: Row(
              children: [
                const BrandMark(size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppInfo.nameKo,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppInfo.tagline,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppInfo.versionLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('기록'),
          SoftPanel(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '위치 간격',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  mode.descriptionKo,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Semantics(
                  label: '위치 기록 간격 ${mode.labelKo}',
                  child: SegmentedButton<TrackingMode>(
                    segments: [
                      for (final m in TrackingMode.values)
                        ButtonSegment(
                          value: m,
                          label: Text(m.labelKo),
                          tooltip: m.descriptionKo,
                        ),
                    ],
                    selected: {mode},
                    showSelectedIcon: false,
                    onSelectionChanged: (set) {
                      ref.read(trackingModeSettingProvider.notifier).state =
                          set.first;
                    },
                    style: ButtonStyle(
                      visualDensity: VisualDensity.comfortable,
                      minimumSize: WidgetStateProperty.all(
                        const Size(0, 44),
                      ),
                      textStyle: WidgetStateProperty.all(
                        const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('지도 · 데이터'),
          SoftPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.map_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('OpenStreetMap'),
                  subtitle: const Text('공개 지도 · 별도 키 없음'),
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
                ListTile(
                  leading: Icon(
                    Icons.phone_iphone_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('이 기기에만 저장'),
                  subtitle: const Text('서버 업로드 · 계정 없음'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('관리'),
          SoftPanel(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: theme.colorScheme.error,
              ),
              title: Text(
                '모든 기록 삭제',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => _deleteAll(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('모든 기록 삭제'),
        content: const Text('이 기기의 산책 기록을 모두 지웁니다. 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(walkRepositoryProvider).deleteAll();
      ref.read(historyTickProvider.notifier).state++;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('모든 기록을 삭제했습니다')),
        );
      }
    }
  }
}
