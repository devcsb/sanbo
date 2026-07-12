import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../data/walk_repository.dart';
import '../../domain/models/tracking_mode.dart';
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
        children: [
          const _SectionHeader('기록 방식'),
          ListTile(
            title: const Text('위치 기록 간격'),
            subtitle: Text(mode.descriptionKo),
            trailing: DropdownButton<TrackingMode>(
              value: mode,
              underline: const SizedBox.shrink(),
              onChanged: (v) {
                if (v != null) {
                  ref.read(trackingModeSettingProvider.notifier).state = v;
                }
              },
              items: [
                for (final m in TrackingMode.values)
                  DropdownMenuItem(
                    value: m,
                    child: Text(m.labelKo),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          const _SectionHeader('지도'),
          ListTile(
            leading: Icon(Icons.map_outlined, color: theme.colorScheme.primary),
            title: const Text('OpenStreetMap'),
            subtitle: const Text(
              '산책 경로를 공개 지도 위에 표시합니다. 별도 가입이나 키가 필요하지 않습니다.',
            ),
            isThreeLine: true,
          ),
          const Divider(height: 1),
          const _SectionHeader('데이터 · 개인정보'),
          ListTile(
            leading: Icon(
              Icons.phone_android,
              color: theme.colorScheme.primary,
            ),
            title: const Text('이 기기에만 저장'),
            subtitle: const Text(
              '산책 기록은 휴대폰 안에만 남습니다. 계정 가입이나 서버 업로드가 없습니다.',
            ),
            isThreeLine: true,
          ),
          ListTile(
            title: const Text('모든 기록 삭제'),
            leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('모든 기록 삭제'),
                  content: const Text(
                    '이 기기에 저장된 산책 기록을 모두 지웁니다. 되돌릴 수 없습니다.',
                  ),
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
            },
          ),
          const Divider(height: 1),
          const _SectionHeader('앱 정보'),
          const ListTile(
            title: Text(AppInfo.nameKo),
            subtitle: Text(
              '${AppInfo.versionLabel}\n산책의 그때 그 순간을 분 단위로 남기는 개인 로그',
            ),
            isThreeLine: true,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
