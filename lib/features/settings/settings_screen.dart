import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/walk_repository.dart';
import '../../domain/models/tracking_mode.dart';
import '../../platform/map/tile_source.dart';
import '../history/history_providers.dart';

final trackingModeSettingProvider = StateProvider<TrackingMode>(
  (ref) => TrackingMode.balanced,
);

final tileSourceSettingProvider = StateProvider<TileSourceId>(
  (ref) => TileSourceId.osmPublic,
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(trackingModeSettingProvider);
    final tile = ref.watch(tileSourceSettingProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          const _SectionHeader('추적'),
          ListTile(
            title: const Text('추적 모드'),
            subtitle: Text(
              '${mode.labelKo} · ${mode.targetIntervalSeconds}초 간격 목표',
            ),
            trailing: DropdownButton<TrackingMode>(
              value: mode,
              onChanged: (v) {
                if (v != null) {
                  ref.read(trackingModeSettingProvider.notifier).state = v;
                }
              },
              items: [
                for (final m in TrackingMode.values)
                  DropdownMenuItem(value: m, child: Text(m.labelKo)),
              ],
            ),
          ),
          const Divider(height: 1),
          const _SectionHeader('지도'),
          ListTile(
            title: const Text('베이스맵'),
            subtitle: Text('${tile.labelKo}\n${tile.attribution}'),
            isThreeLine: true,
            trailing: DropdownButton<TileSourceId>(
              value: tile,
              onChanged: (v) {
                if (v != null) {
                  ref.read(tileSourceSettingProvider.notifier).state = v;
                }
              },
              items: [
                for (final t in TileSourceId.values)
                  DropdownMenuItem(value: t, child: Text(t.labelKo)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              '기본은 OpenStreetMap 공개 타일입니다. 브이월드는 키 연동 전 OSM으로 표시됩니다.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          const Divider(height: 1),
          const _SectionHeader('데이터 · 프라이버시'),
          ListTile(
            title: const Text('저장 위치'),
            subtitle: const Text('기기 로컬 SQLite. 서버 업로드 없음.'),
            leading: Icon(
              Icons.phone_android,
              color: theme.colorScheme.primary,
            ),
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
                    '로컬에 저장된 산책 기록을 모두 삭제합니다. 되돌릴 수 없습니다.',
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
                    const SnackBar(content: Text('기록을 삭제했습니다')),
                  );
                }
              }
            },
          ),
          const Divider(height: 1),
          const _SectionHeader('정보'),
          const ListTile(
            title: Text('산보 (Sanbo)'),
            subtitle: Text('v0.1.0\ndocs/PRD · TRD · PLATFORM_AND_MAPS'),
            isThreeLine: true,
          ),
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
