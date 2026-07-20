import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../data/walk_repository.dart';
import '../../domain/models/tracking_mode.dart';
import '../../shared/widgets/ui_bits.dart';
import '../history/history_providers.dart';
import '../home/session_controller.dart';
import '../intro/intro_providers.dart';
import 'tracking_mode_setting.dart';

bool _isSessionInProgress(LiveSessionState state) {
  return state.session != null ||
      state.isTracking ||
      state.needsRecovery ||
      state.isBusy;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  var _isSavingTrackingMode = false;
  var _isDeletingAll = false;

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(trackingModeSettingProvider);
    final liveSession = ref.watch(sessionControllerProvider);
    final sessionInProgress = _isSessionInProgress(liveSession);
    final canChangeMode = !sessionInProgress && !_isSavingTrackingMode;
    final canDeleteAll = !sessionInProgress && !_isDeletingAll;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const AppBarTitle('설정', showBrand: true)),
      body: ListView(
        children: [
          PageFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageIntro(
                  eyebrow: '산보',
                  title: '설정',
                  description: '기록 방식과 이 기기에 저장되는 데이터를 확인하세요.',
                ),
                const SizedBox(height: 24),
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
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              AppInfo.tagline,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppInfo.versionLabel,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const SectionLabel('기록'),
                SoftPanel(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const TonalIcon(
                            icon: Icons.location_searching_rounded,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '위치 간격',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        mode.descriptionKo,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (sessionInProgress) ...[
                        const SizedBox(height: 12),
                        Text(
                          '진행 중인 산책을 마친 뒤 기록 간격을 바꿀 수 있어요.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ] else if (_isSavingTrackingMode) ...[
                        const SizedBox(height: 12),
                        Text(
                          '기록 간격을 저장하고 있어요.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _TrackingModeSelector(
                        mode: mode,
                        enabled: canChangeMode,
                        onSelected: (selected) =>
                            unawaited(_changeTrackingMode(selected, mode)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const SectionLabel('지도 · 데이터'),
                SoftPanel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      const ListTile(
                        minTileHeight: 56,
                        leading: TonalIcon(icon: Icons.map_outlined),
                        title: Text('OpenStreetMap'),
                        subtitle: Text('누구나 이용할 수 있는 공개 지도'),
                      ),
                      Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                      ListTile(
                        minTileHeight: 56,
                        leading: TonalIcon(
                          icon: Icons.phone_iphone_rounded,
                          color: theme.colorScheme.secondary,
                        ),
                        title: const Text('이 기기에만 저장'),
                        subtitle: const Text('서버 업로드 · 계정 없음'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const SectionLabel('관리'),
                SoftPanel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        minTileHeight: 56,
                        leading: TonalIcon(
                          icon: Icons.delete_outline_rounded,
                          color: canDeleteAll
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          '모든 기록 삭제',
                          style: TextStyle(
                            color: canDeleteAll
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: _isDeletingAll
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        enabled: canDeleteAll,
                        onTap: canDeleteAll
                            ? () => unawaited(_deleteAll(context))
                            : null,
                      ),
                      if (sessionInProgress)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Text(
                            '진행 중인 산책을 마친 뒤 모든 기록을 삭제할 수 있어요.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (_isDeletingAll)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Text(
                            '기록을 삭제하고 있어요.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeTrackingMode(
    TrackingMode selected,
    TrackingMode previous,
  ) async {
    if (_isSavingTrackingMode ||
        _isSessionInProgress(ref.read(sessionControllerProvider))) {
      return;
    }

    final modeNotifier = ref.read(trackingModeSettingProvider.notifier);
    final flagsStore = ref.read(appFlagsStoreProvider);
    setState(() => _isSavingTrackingMode = true);
    modeNotifier.state = selected;
    try {
      await flagsStore.setTrackingModeName(selected.name);
    } on Object {
      modeNotifier.state = previous;
      if (!mounted) return;
      setState(() => _isSavingTrackingMode = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기록 간격을 저장하지 못했어요. 다시 시도해 주세요.')),
      );
      return;
    }

    if (mounted) setState(() => _isSavingTrackingMode = false);
  }

  Future<void> _deleteAll(BuildContext context) async {
    if (_isDeletingAll) return;
    if (_isSessionInProgress(ref.read(sessionControllerProvider))) {
      _showSessionInProgressMessage(context);
      return;
    }

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
    if (ok != true) return;
    if (_isSessionInProgress(ref.read(sessionControllerProvider))) {
      if (context.mounted) _showSessionInProgressMessage(context);
      return;
    }

    setState(() => _isDeletingAll = true);
    try {
      await ref.read(walkRepositoryProvider).deleteAll();
      ref.read(historyTickProvider.notifier).state++;
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('모든 기록을 지웠어요')));
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('기록을 삭제하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeletingAll = false);
    }
  }

  void _showSessionInProgressMessage(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('진행 중인 산책을 마친 뒤 다시 시도해 주세요.')));
  }
}

class _TrackingModeSelector extends StatelessWidget {
  const _TrackingModeSelector({
    required this.mode,
    required this.enabled,
    required this.onSelected,
  });

  final TrackingMode mode;
  final bool enabled;
  final ValueChanged<TrackingMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useStackedLayout =
            constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(14) > 19;
        if (!useStackedLayout) {
          return Semantics(
            enabled: enabled,
            label: '위치 기록 간격 ${mode.labelKo}',
            child: SegmentedButton<TrackingMode>(
              segments: [
                for (final value in TrackingMode.values)
                  ButtonSegment(
                    value: value,
                    label: Text(value.labelKo),
                    tooltip: value.descriptionKo,
                  ),
              ],
              selected: {mode},
              showSelectedIcon: false,
              onSelectionChanged: enabled
                  ? (selection) => onSelected(selection.first)
                  : null,
            ),
          );
        }

        final scheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final value in TrackingMode.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  button: true,
                  selected: value == mode,
                  enabled: enabled,
                  child: OutlinedButton(
                    onPressed: enabled ? () => onSelected(value) : null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      alignment: Alignment.centerLeft,
                      backgroundColor: value == mode
                          ? scheme.primaryContainer
                          : null,
                      foregroundColor: value == mode
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                      side: BorderSide(
                        color: value == mode ? scheme.primary : scheme.outline,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          value == mode
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(value.labelKo),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
