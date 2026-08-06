import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../data/walk_repository.dart';
import '../../domain/models/tracking_mode.dart';
import '../../domain/services/app_backup.dart';
import '../../platform/backup/backup_file_service.dart';
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
  var _isExportingBackup = false;
  var _isImportingBackup = false;

  bool get _isManagingData =>
      _isDeletingAll || _isExportingBackup || _isImportingBackup;

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(trackingModeSettingProvider);
    final liveSession = ref.watch(sessionControllerProvider);
    final sessionInProgress = _isSessionInProgress(liveSession);
    final canChangeMode =
        !sessionInProgress && !_isSavingTrackingMode && !_isManagingData;
    final canManageData = !sessionInProgress && !_isManagingData;
    final canDeleteAll = canManageData;
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
                        title: Text('OpenStreetMap · CARTO'),
                        subtitle: Text(
                          '지도 타일을 볼 때 대략적인 지도 영역과 네트워크 정보가 CARTO에 전달됩니다',
                        ),
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
                        subtitle: const Text('산책 원본 서버 업로드 · 계정 없음'),
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
                        minTileHeight: 64,
                        leading: const TonalIcon(
                          icon: Icons.file_upload_outlined,
                        ),
                        title: const Text('전체 백업 내보내기'),
                        subtitle: const Text(
                          '앱 삭제 전 보관 · 원본 위치·수정 내용·장소 이름 포함',
                        ),
                        trailing: _isExportingBackup
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chevron_right_rounded),
                        enabled: canManageData,
                        onTap: canManageData
                            ? () => unawaited(_exportBackup(context))
                            : null,
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
                        minTileHeight: 64,
                        leading: TonalIcon(
                          icon: Icons.file_download_outlined,
                          color: theme.colorScheme.secondary,
                        ),
                        title: const Text('백업 가져오기'),
                        subtitle: const Text('기존 기록 유지 · 중복 산책 건너뛰기'),
                        trailing: _isImportingBackup
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chevron_right_rounded),
                        enabled: canManageData,
                        onTap: canManageData
                            ? () => unawaited(_importBackup(context))
                            : null,
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
                            '진행 중인 산책을 마친 뒤 백업을 관리하거나 기록을 삭제할 수 있어요.',
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Text(
                          '앱 업데이트에는 이 기기의 기록이 유지됩니다. 앱 삭제·기기 변경 전에는 백업 파일을 별도로 보관하세요. 백업에는 정밀한 위치가 포함됩니다.',
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
    if (_isManagingData) return;
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

  Future<void> _exportBackup(BuildContext context) async {
    if (_isManagingData) return;
    if (_isSessionInProgress(ref.read(sessionControllerProvider))) {
      _showSessionInProgressMessage(context);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('전체 백업 내보내기'),
        content: const Text(
          '백업 파일에는 산책 시각, 정밀한 GPS 경로, 활동 수정 내용과 저장한 장소 이름이 포함됩니다. 신뢰할 수 있는 곳에만 보관하세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('파일 저장'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (_isSessionInProgress(ref.read(sessionControllerProvider))) {
      _showSessionInProgressMessage(context);
      return;
    }

    setState(() => _isExportingBackup = true);
    try {
      final raw = await ref.read(walkRepositoryProvider).createBackupJson();
      final path = await ref
          .read(backupFileServiceProvider)
          .save(
            fileName: _backupFileName(DateTime.now()),
            bytes: Uint8List.fromList(utf8.encode(raw)),
          );
      if (!context.mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('전체 백업 파일을 저장했어요')));
    } on Object catch (error) {
      if (context.mounted) {
        _showDataError(context, '백업을 저장하지 못했어요', error);
      }
    } finally {
      if (mounted) setState(() => _isExportingBackup = false);
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    if (_isManagingData) return;
    if (_isSessionInProgress(ref.read(sessionControllerProvider))) {
      _showSessionInProgressMessage(context);
      return;
    }

    setState(() => _isImportingBackup = true);
    try {
      final picked = await ref.read(backupFileServiceProvider).pick();
      if (picked == null || !context.mounted) return;
      // Parsing can expand a near-limit JSON file several times in memory.
      // Do it once off the UI isolate, then reuse the validated archive for
      // both the confirmation preview and the transactional import.
      final archive = await compute(AppBackupCodec.decodeBytes, picked.bytes);
      if (!context.mounted) return;
      final sessionCount = archive.table('sessions').length;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('백업 가져오기'),
          content: Text(
            '${picked.name}\n\n산책 $sessionCount개를 확인했습니다. 기존 기록은 지우지 않고, 같은 산책 ID는 건너뜁니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('가져오기'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      if (_isSessionInProgress(ref.read(sessionControllerProvider))) {
        _showSessionInProgressMessage(context);
        return;
      }
      final result = await ref
          .read(walkRepositoryProvider)
          .importBackup(archive);
      ref.read(historyTickProvider.notifier).state++;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '산책 ${result.importedSessions}개를 가져왔어요'
            '${result.skippedSessions == 0 ? '' : ' · 중복 ${result.skippedSessions}개 건너뜀'}',
          ),
        ),
      );
    } on Object catch (error) {
      if (context.mounted) {
        _showDataError(context, '백업을 가져오지 못했어요', error);
      }
    } finally {
      if (mounted) setState(() => _isImportingBackup = false);
    }
  }

  String _backupFileName(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'sanbo-backup-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}.sanbo';
  }

  void _showDataError(BuildContext context, String summary, Object error) {
    final detail = error is FormatException
        ? error.message.toString()
        : '다시 시도해 주세요.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$summary. $detail')));
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
