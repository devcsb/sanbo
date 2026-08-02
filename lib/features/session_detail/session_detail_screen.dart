import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/walk_repository.dart';
import '../../domain/models/activity_label.dart';
import '../../domain/models/location_sample.dart';
import '../../domain/models/minute_window.dart';
import '../../domain/models/walk_session.dart';
import '../../domain/pipeline/segment_merger.dart';
import '../../domain/services/place_memory.dart';
import '../../domain/services/route_playback.dart';
import '../../domain/services/session_export.dart';
import '../../domain/services/walk_stats.dart';
import '../../platform/place/place_lookup.dart';
import '../../shared/widgets/route_map.dart';
import '../../shared/widgets/ui_bits.dart';
import '../history/history_providers.dart';
import 'timeline_copy.dart';

final sessionDetailProvider = FutureProvider.autoDispose
    .family<SessionDetailData?, String>((ref, id) async {
      ref.watch(historyTickProvider);
      final repo = ref.watch(walkRepositoryProvider);
      final session = await repo.getSession(id);
      if (session == null) return null;
      final samples = await repo.getSamples(id);
      var windows = await repo.getWindows(id);
      var segments = SegmentMerger().merge(windows);

      // Reuse only places the user previously named. This is a local DB
      // lookup; opening a detail never triggers geocoding or network work.
      var attachedKnownPlace = false;
      for (final segment in segments) {
        if (!canRememberPlace(segment) || segmentPlaceId(segment) != null) {
          continue;
        }
        final coordinate = placeCoordinate(segment);
        if (coordinate == null) continue;
        try {
          final known = await repo.findNearestPlace(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
          );
          if (known == null) continue;
          await repo.attachPlaceToWindows(
            sessionId: id,
            windowStarts: segment.windows
                .map((window) => window.windowStart)
                .toList(),
            placeId: known.id,
          );
          attachedKnownPlace = true;
        } on Object {
          // Place enrichment is optional; never hide an otherwise valid walk.
        }
      }
      if (attachedKnownPlace) {
        windows = await repo.getWindows(id);
        segments = SegmentMerger().merge(windows);
      }
      return SessionDetailData(
        session: session,
        samples: samples,
        windows: windows,
        segments: segments,
      );
    });

final _detailCommandBusyProvider = StateProvider.autoDispose
    .family<bool, String>((ref, id) => false);

class SessionDetailData {
  const SessionDetailData({
    required this.session,
    required this.samples,
    required this.windows,
    this.segments = const [],
  });

  final WalkSession session;
  final List<LocationSample> samples;
  final List<MinuteWindow> windows;
  final List<ActivitySegment> segments;
}

class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  final _mapSectionKey = GlobalKey();
  final _scrollController = ScrollController();
  Timer? _playbackTimer;
  // -1 means "show the completed route"; pressing play then starts at 0.
  var _playbackIndex = -1;
  var _isPlaying = false;
  DateTime? _selectedSegmentStart;
  List<LocationSample>? _playbackSource;
  List<LocationSample> _playbackCache = const [];
  List<({double lat, double lon})> _pointCache = const [];

  String get sessionId => widget.sessionId;

  @override
  void didUpdateWidget(covariant SessionDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _playbackTimer?.cancel();
      _playbackTimer = null;
      _playbackIndex = -1;
      _isPlaying = false;
      _selectedSegmentStart = null;
      _playbackSource = null;
      _playbackCache = const [];
      _pointCache = const [];
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sessionDetailProvider(sessionId));
    final commandBusy = ref.watch(_detailCommandBusyProvider(sessionId));
    final hasLoadedData = async.hasValue && async.valueOrNull != null;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('산책 요약'),
        actions: [
          if (hasLoadedData) ...[
            IconButton(
              tooltip: '요약 복사',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: commandBusy ? null : () => _copySummary(context, ref),
            ),
            IconButton(
              tooltip: '데이터 복사 (NDJSON)',
              icon: const Icon(Icons.data_object_rounded),
              onPressed: commandBusy
                  ? null
                  : () => _exportSession(context, ref),
            ),
            IconButton(
              tooltip: '삭제',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: commandBusy
                  ? null
                  : () => _confirmDelete(context, ref),
            ),
          ],
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => EmptyStateView(
          icon: Icons.error_outline_rounded,
          title: '요약을 불러오지 못했어요',
          message: '잠시 후 다시 시도해 주세요.',
          actionLabel: '다시 시도',
          onAction: () => ref.invalidate(sessionDetailProvider(sessionId)),
        ),
        data: (data) {
          if (data == null) {
            return EmptyStateView(
              icon: Icons.search_off_rounded,
              title: '기록을 찾을 수 없어요',
              message: '삭제되었거나 잘못된 주소일 수 있어요.',
              actionLabel: '기록으로',
              onAction: () => context.go('/history'),
            );
          }

          final session = data.session;
          final dateFmt = DateFormat('yyyy.MM.dd  HH:mm', 'ko');
          final km = (session.totalDistanceM ?? 0) / 1000.0;
          final dur = Duration(seconds: session.durationS ?? 0);
          final kmh = (session.avgSpeedMps ?? 0) * 3.6;
          final playbackSamples = _samplesForPlayback(data.samples);
          final points = _pointCache;
          final segments = data.segments.isNotEmpty
              ? data.segments
              : SegmentMerger().merge(data.windows);
          final playbackIndex = playbackSamples.isEmpty
              ? 0
              : _playbackIndex < 0
              ? playbackSamples.length - 1
              : _playbackIndex.clamp(0, playbackSamples.length - 1);
          final currentSample = playbackSamples.isEmpty
              ? null
              : playbackSamples[playbackIndex];
          final currentSegment = currentSample == null
              ? null
              : _segmentAt(segments, currentSample.timestamp);
          final selectedSegment = _selectedSegmentStart == null
              ? null
              : _segmentStartingAt(segments, _selectedSegmentStart!);
          final highlightedPoints = selectedSegment == null
              ? const <({double lat, double lon})>[]
              : RoutePlayback.samplesInRange(
                      playbackSamples,
                      start: selectedSegment.start,
                      endExclusive: selectedSegment.endExclusive,
                    )
                    .map(
                      (sample) => (lat: sample.latitude, lon: sample.longitude),
                    )
                    .toList(growable: false);
          final collapsedCount = segments.length;
          final rawCount = data.windows.length;

          return PageFrame(
            child: ListView(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              children: [
                PageIntro(
                  eyebrow: '산책 기록',
                  title: dateFmt.format(session.startedAt),
                  description: '경로와 활동 흐름을 차분히 돌아보세요.',
                ),
                const SizedBox(height: 24),
                const SectionLabel('산책 경로'),
                KeyedSubtree(
                  key: _mapSectionKey,
                  child: RouteMap(
                    points: points,
                    height: 220,
                    progressPointCount: playbackSamples.isEmpty
                        ? null
                        : playbackIndex + 1,
                    highlightedPoints: highlightedPoints,
                    currentPoint: currentSample == null
                        ? null
                        : (
                            lat: currentSample.latitude,
                            lon: currentSample.longitude,
                          ),
                    offlinePreview:
                        !kIsWeb &&
                        Platform.environment.containsKey('FLUTTER_TEST'),
                  ),
                ),
                if (playbackSamples.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _RoutePlaybackControls(
                    sample: currentSample!,
                    firstTimestamp: playbackSamples.first.timestamp,
                    lastTimestamp: playbackSamples.last.timestamp,
                    index: playbackIndex,
                    sampleCount: playbackSamples.length,
                    isPlaying: _isPlaying,
                    currentSegment: currentSegment,
                    selectedSegment: selectedSegment,
                    onTogglePlayback: () =>
                        _togglePlayback(playbackSamples.length),
                    onIndexChanged: _setPlaybackIndex,
                  ),
                ],
                const SizedBox(height: 24),
                const SectionLabel('핵심 기록'),
                MetricStrip(
                  metrics: [
                    MetricData(
                      label: '거리',
                      value: '${km.toStringAsFixed(2)} km',
                      emphasize: true,
                    ),
                    MetricData(label: '시간', value: _fmt(dur)),
                    MetricData(
                      label: '평균 속도',
                      value: '${kmh.toStringAsFixed(1)} km/h',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SectionLabel('기록 세부 정보'),
                _SecondaryMetricStrip(
                  metrics: [
                    MetricData(
                      label: '이동 시간',
                      value: _optionalDuration(session.movingTimeS),
                    ),
                    MetricData(
                      label: '정지 시간',
                      value: _optionalDuration(session.stationaryTimeS),
                    ),
                    MetricData(
                      label: 'GPS 유효 좌표',
                      value: session.validSampleCount == null
                          ? '측정되지 않음'
                          : '${session.validSampleCount}개',
                    ),
                    MetricData(
                      label: '중앙 정확도',
                      value: session.medianAccuracyM == null
                          ? '측정되지 않음'
                          : '±${session.medianAccuracyM!.toStringAsFixed(1)} m',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SectionLabel('메모'),
                _SessionNotesCard(
                  sessionId: sessionId,
                  initialNotes: session.notes,
                  enabled: !commandBusy,
                ),
                if (pacePerKmLabel(session.avgSpeedMps) != null) ...[
                  const SizedBox(height: 16),
                  SoftPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        const TonalIcon(
                          icon: Icons.speed_rounded,
                          size: 40,
                          iconSize: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '평균 페이스',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                pacePerKmLabel(session.avgSpeedMps)!,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                const SectionLabel('활동 흐름'),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const StatusPill(
                          label: '구간 탭하여 지도에서 보기',
                          icon: Icons.map_outlined,
                        ),
                        if (rawCount > 0)
                          StatusPill(
                            label: rawCount == collapsedCount
                                ? '$collapsedCount개 구간'
                                : '$rawCount분 → $collapsedCount개 구간',
                            icon: Icons.timeline_rounded,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '같은 활동은 묶어서 보여 드려요. 수정은 각 구간의 편집 버튼에서 할 수 있어요.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (segments.isEmpty)
                  SoftPanel(
                    child: Text(
                      '구간이 없어요. 짧은 산책이거나 위치 기록이 부족했을 수 있습니다.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  SoftPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < segments.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.6),
                            ),
                          _SegmentRow(
                            segment: segments[i],
                            selected:
                                selectedSegment?.start.isAtSameMomentAs(
                                  segments[i].start,
                                ) ??
                                false,
                            onSelect: () =>
                                _selectSegment(segments[i], playbackSamples),
                            onEdit: commandBusy
                                ? null
                                : () => _showSegmentActions(
                                    context,
                                    ref,
                                    sessionId,
                                    segments[i],
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _setPlaybackIndex(int index) {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    setState(() {
      _playbackIndex = index;
      _isPlaying = false;
      _selectedSegmentStart = null;
    });
  }

  void _togglePlayback(int sampleCount) {
    if (sampleCount <= 1) return;
    if (_isPlaying) {
      _playbackTimer?.cancel();
      _playbackTimer = null;
      setState(() => _isPlaying = false);
      return;
    }

    final lastIndex = sampleCount - 1;
    final startIndex = _playbackIndex.clamp(0, lastIndex);
    setState(() {
      _playbackIndex = startIndex >= lastIndex ? 0 : startIndex;
      _selectedSegmentStart = null;
      _isPlaying = true;
    });
    final step = RoutePlayback.stepForSampleCount(sampleCount);
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(
      RoutePlayback.intervalForSampleCount(sampleCount),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final nextIndex = (_playbackIndex + step).clamp(0, lastIndex);
        if (nextIndex >= lastIndex) {
          timer.cancel();
          _playbackTimer = null;
          setState(() {
            _playbackIndex = lastIndex;
            _isPlaying = false;
          });
          return;
        }
        setState(() => _playbackIndex = nextIndex);
      },
    );
  }

  void _selectSegment(
    ActivitySegment segment,
    List<LocationSample> playbackSamples,
  ) {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    setState(() {
      _selectedSegmentStart = segment.start;
      _isPlaying = false;
      if (playbackSamples.isNotEmpty) {
        _playbackIndex = RoutePlayback.nearestIndex(
          playbackSamples,
          segment.start,
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_revealMap());
    });
  }

  List<LocationSample> _samplesForPlayback(List<LocationSample> source) {
    if (identical(_playbackSource, source)) return _playbackCache;
    _playbackSource = source;
    _playbackCache = RoutePlayback.playableSamples(source);
    _pointCache = _playbackCache
        .map((sample) => (lat: sample.latitude, lon: sample.longitude))
        .toList(growable: false);
    return _playbackCache;
  }

  Future<void> _revealMap() async {
    var mapContext = _mapSectionKey.currentContext;
    if (mapContext == null && _scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      mapContext = _mapSectionKey.currentContext;
    }
    if (!mounted || mapContext == null || !mapContext.mounted) return;
    await Scrollable.ensureVisible(
      mapContext,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  Future<void> _copySummary(BuildContext context, WidgetRef ref) async {
    final data = ref.read(sessionDetailProvider(sessionId)).valueOrNull;
    if (data == null) return;
    final summary = const SessionExport().humanSummary(
      session: data.session,
      windows: data.windows,
    );
    await Clipboard.setData(ClipboardData(text: summary));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('산책 요약을 복사했어요.')));
  }

  Future<void> _exportSession(BuildContext context, WidgetRef ref) async {
    final data = ref.read(sessionDetailProvider(sessionId)).valueOrNull;
    if (data == null) return;
    ref.read(_detailCommandBusyProvider(sessionId).notifier).state = true;
    try {
      const exporter = SessionExport();
      final ndjson = exporter.toNdjson(
        session: data.session,
        windows: data.windows,
        samples: data.samples,
      );
      // Copy the data itself, not a temp-file path: an app-private systemTemp
      // path is unreachable to the user on mobile. Clipboard NDJSON is a real,
      // pasteable export until a system share-sheet lands.
      await Clipboard.setData(ClipboardData(text: ndjson));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('산책 데이터(NDJSON)를 클립보드에 복사했어요.')),
      );
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('내보내기에 실패했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      ref.read(_detailCommandBusyProvider(sessionId).notifier).state = false;
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('기록 삭제'),
          content: const Text('이 산책을 삭제합니다. 되돌릴 수 없어요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    ref.read(_detailCommandBusyProvider(sessionId).notifier).state = true;
    try {
      await ref.read(walkRepositoryProvider).deleteSession(sessionId);
      ref.read(historyTickProvider.notifier).state++;
      ref.read(_detailCommandBusyProvider(sessionId).notifier).state = false;
      if (context.mounted) context.go('/history');
    } on Object {
      ref.read(_detailCommandBusyProvider(sessionId).notifier).state = false;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('기록을 삭제하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    }
  }

  Future<void> _showSegmentActions(
    BuildContext context,
    WidgetRef ref,
    String sessionId,
    ActivitySegment segment,
  ) async {
    final coordinate = placeCoordinate(segment);
    final canEditPlace = canRememberPlace(segment) && coordinate != null;
    final action = await showModalBottomSheet<_SegmentAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final placeName = segmentPlaceName(segment);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  '${_formatSegmentRange(segment)} 구간 편집',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.directions_walk_rounded),
                title: const Text('활동 수정'),
                subtitle: Text('현재: ${segment.label.labelKo}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(ctx, _SegmentAction.activity),
              ),
              if (canEditPlace)
                ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(placeName == null ? '장소 이름 남기기' : '장소 이름 수정'),
                  subtitle: Text(placeName ?? '이 체류 지점을 다음 산책에서도 기억해요.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(ctx, _SegmentAction.place),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case _SegmentAction.activity:
        return _editSegment(context, ref, sessionId, segment);
      case _SegmentAction.place:
        return _editPlace(context, ref, sessionId, segment);
    }
  }

  Future<void> _editPlace(
    BuildContext context,
    WidgetRef ref,
    String sessionId,
    ActivitySegment segment,
  ) async {
    final coordinate = placeCoordinate(segment);
    if (coordinate == null) return;
    final result = await showModalBottomSheet<_PlaceEditorResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PlaceEditorSheet(
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
        initialName: segmentPlaceName(segment),
        initialAddress: segmentPlaceAddress(segment),
        canRemove: segmentPlaceId(segment) != null,
      ),
    );
    if (!context.mounted || result == null) return;

    final existingPlaceId = segmentPlaceId(segment);
    if (result.remove) {
      if (existingPlaceId == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('장소 기억 지우기'),
          content: const Text(
            '이 장소 이름은 연결된 다른 산책에서도 사라집니다. 산책 기록 자체는 삭제되지 않아요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('지우기'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }

    ref.read(_detailCommandBusyProvider(sessionId).notifier).state = true;
    try {
      if (result.remove) {
        await ref.read(walkRepositoryProvider).deletePlace(existingPlaceId!);
      } else {
        await ref
            .read(walkRepositoryProvider)
            .rememberPlaceForWindows(
              sessionId: sessionId,
              windowStarts: segment.windows
                  .map((window) => window.windowStart)
                  .toList(),
              latitude: coordinate.latitude,
              longitude: coordinate.longitude,
              name: result.name,
              address: result.address,
              existingPlaceId: existingPlaceId,
            );
      }
      ref.read(historyTickProvider.notifier).state++;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.remove ? '장소 기억을 지웠어요.' : '장소 이름을 저장했어요.'),
          ),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('장소 이름을 저장하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      ref.read(_detailCommandBusyProvider(sessionId).notifier).state = false;
    }
  }

  Future<void> _editSegment(
    BuildContext context,
    WidgetRef ref,
    String sessionId,
    ActivitySegment segment,
  ) async {
    final selected = await showModalBottomSheet<ActivityLabel>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final range = _formatSegmentRange(segment);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Text('활동 선택', style: theme.textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  segment.isMultiMinute
                      ? '$range · ${segment.minuteCount}분 구간에 한 번에 적용'
                      : '$range 구간에 적용',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final label in ActivityLabel.values)
                ListTile(
                  title: Text(label.labelKo),
                  trailing: segment.label == label
                      ? Icon(
                          Icons.check_rounded,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(ctx, label),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected == null) return;
    ref.read(_detailCommandBusyProvider(sessionId).notifier).state = true;
    try {
      final starts = segment.windows.map((w) => w.windowStart).toList();
      await ref
          .read(walkRepositoryProvider)
          .updateWindowsUserLabel(
            sessionId: sessionId,
            windowStarts: starts,
            userLabel: selected,
          );
      ref.read(historyTickProvider.notifier).state++;
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('활동을 저장하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      ref.read(_detailCommandBusyProvider(sessionId).notifier).state = false;
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '$m:$s';
  }

  String _optionalDuration(int? seconds) {
    if (seconds == null) return '측정되지 않음';
    return _fmt(Duration(seconds: seconds));
  }
}

enum _SegmentAction { activity, place }

class _PlaceEditorResult {
  const _PlaceEditorResult.save({required this.name, this.address})
    : remove = false;

  const _PlaceEditorResult.remove() : name = '', address = null, remove = true;

  final String name;
  final String? address;
  final bool remove;
}

class _PlaceEditorSheet extends ConsumerStatefulWidget {
  const _PlaceEditorSheet({
    required this.latitude,
    required this.longitude,
    required this.initialName,
    required this.initialAddress,
    required this.canRemove,
  });

  final double latitude;
  final double longitude;
  final String? initialName;
  final String? initialAddress;
  final bool canRemove;

  @override
  ConsumerState<_PlaceEditorSheet> createState() => _PlaceEditorSheetState();
}

class _PlaceEditorSheetState extends ConsumerState<_PlaceEditorSheet> {
  late final TextEditingController _nameController;
  String? _address;
  var _lookingUp = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _address = widget.initialAddress;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _lookupAddress() async {
    if (_lookingUp) return;
    setState(() => _lookingUp = true);
    try {
      final result = await ref
          .read(placeLookupProvider)
          .lookup(latitude: widget.latitude, longitude: widget.longitude);
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이 위치의 주소 제안을 찾지 못했어요.')));
        return;
      }
      setState(() {
        _address = result.address.trim().isEmpty ? null : result.address.trim();
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = result.suggestedName;
          _nameController.selection = TextSelection.collapsed(
            offset: _nameController.text.length,
          );
        }
      });
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('주소 제안을 불러오지 못했어요. 직접 이름을 적어 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('기억할 장소 이름을 입력해 주세요.')));
      return;
    }
    Navigator.pop(
      context,
      _PlaceEditorResult.save(name: name, address: _address),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('장소 기억', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '확인한 이름은 이 기기에만 저장되고, 다음 체류 기록에서 가까운 장소를 찾는 데 사용됩니다.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              autofocus: widget.initialName == null,
              maxLength: 60,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: '장소 이름',
                hintText: '예: 동네 카페, 강변 벤치',
              ),
            ),
            if (_address != null && _address!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _address!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _lookingUp ? null : () => unawaited(_lookupAddress()),
              icon: _lookingUp
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.travel_explore_rounded),
              label: Text(_lookingUp ? '주소 확인 중…' : '현재 위치에서 주소 제안'),
            ),
            const SizedBox(height: 4),
            Text(
              '주소 제안은 기기의 주소 서비스를 사용하며 실제 장소와 다를 수 있어요.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _lookingUp ? null : _save,
              child: const Text('장소 이름 저장'),
            ),
            if (widget.canRemove) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _lookingUp
                    ? null
                    : () => Navigator.pop(
                        context,
                        const _PlaceEditorResult.remove(),
                      ),
                child: const Text('저장된 장소 기억 지우기'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatSegmentRange(ActivitySegment segment) {
  final start = DateFormat('HH:mm').format(segment.start);
  if (!segment.isMultiMinute) return start;
  final end = DateFormat('HH:mm').format(segment.endExclusive);
  return '$start–$end';
}

ActivitySegment? _segmentAt(
  List<ActivitySegment> segments,
  DateTime timestamp,
) {
  for (final segment in segments) {
    if (!timestamp.isBefore(segment.start) &&
        timestamp.isBefore(segment.endExclusive)) {
      return segment;
    }
  }
  return null;
}

ActivitySegment? _segmentStartingAt(
  List<ActivitySegment> segments,
  DateTime start,
) {
  for (final segment in segments) {
    if (segment.start.isAtSameMomentAs(start)) return segment;
  }
  return null;
}

String _playbackDuration(Duration duration) {
  final safeSeconds = duration.inSeconds.clamp(0, 24 * 60 * 60);
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds ~/ 60).remainder(60);
  final seconds = safeSeconds.remainder(60);
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

class _RoutePlaybackControls extends StatelessWidget {
  const _RoutePlaybackControls({
    required this.sample,
    required this.firstTimestamp,
    required this.lastTimestamp,
    required this.index,
    required this.sampleCount,
    required this.isPlaying,
    required this.currentSegment,
    required this.selectedSegment,
    required this.onTogglePlayback,
    required this.onIndexChanged,
  });

  final LocationSample sample;
  final DateTime firstTimestamp;
  final DateTime lastTimestamp;
  final int index;
  final int sampleCount;
  final bool isPlaying;
  final ActivitySegment? currentSegment;
  final ActivitySegment? selectedSegment;
  final VoidCallback onTogglePlayback;
  final ValueChanged<int> onIndexChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final elapsed = sample.timestamp.difference(firstTimestamp);
    final total = lastTimestamp.difference(firstTimestamp);
    final placeName = currentSegment == null
        ? null
        : segmentPlaceName(currentSegment!);
    final currentLabel = currentSegment?.label.labelKo ?? '활동 정보 없음';

    return SoftPanel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: isPlaying ? '경로 재생 일시정지' : '경로 재생',
                onPressed: sampleCount > 1 ? onTogglePlayback : null,
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${DateFormat('HH:mm:ss').format(sample.timestamp)} · '
                      '$currentLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '${_playbackDuration(elapsed)} / '
                            '${_playbackDuration(total)}',
                        ?placeName,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selectedSegment != null) ...[
                const SizedBox(width: 8),
                StatusPill(
                  label: '선택 구간',
                  icon: Icons.route_rounded,
                  color: theme.colorScheme.tertiary,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Semantics(
            label:
                '경로 재생 위치 ${DateFormat('HH:mm:ss').format(sample.timestamp)}',
            child: Slider(
              key: const ValueKey('route-playback-slider'),
              min: 0,
              max: sampleCount > 1 ? (sampleCount - 1).toDouble() : 1,
              value: index.toDouble(),
              onChanged: sampleCount > 1
                  ? (value) => onIndexChanged(value.round())
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('HH:mm').format(firstTimestamp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  DateFormat('HH:mm').format(lastTimestamp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryMetricStrip extends StatelessWidget {
  const _SecondaryMetricStrip({required this.metrics});

  final List<MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackMetrics =
              constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(16) > 20;
          final itemWidth = stackMetrics
              ? constraints.maxWidth
              : (constraints.maxWidth - 16) / 2;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final metric in metrics)
                SizedBox(
                  width: itemWidth,
                  child: Semantics(
                    label: '${metric.label} ${metric.value}',
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metric.label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          metric.value,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.segment,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
  });

  final ActivitySegment segment;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = _formatSegmentRange(segment);
    final confirmed = segment.userConfirmed;
    final label = segment.label.labelKo;
    final placeName = segmentPlaceName(segment);
    final status = StatusPill(
      label: confirmed ? '확정' : '추정',
      color: confirmed
          ? theme.colorScheme.primary
          : theme.colorScheme.secondary,
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        if (placeName != null) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(
                Icons.place_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  placeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 2),
        Text(
          timelineSegmentSubtitle(segment),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.42)
            : Colors.transparent,
        border: selected
            ? Border(
                left: BorderSide(color: theme.colorScheme.primary, width: 3),
              )
            : null,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Semantics(
                button: true,
                selected: selected,
                label:
                    '$range $label${confirmed ? ' 확정' : ' 추정'}'
                    '${placeName == null ? '' : ', 장소 $placeName'}. '
                    '지도에서 보기',
                enabled: onSelect != null,
                excludeSemantics: true,
                child: InkWell(
                  key: ValueKey(
                    'segment-select-${segment.start.toIso8601String()}',
                  ),
                  onTap: onSelect,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final useStackedLayout =
                            constraints.maxWidth < 232 ||
                            MediaQuery.textScalerOf(context).scale(14) > 20;
                        if (useStackedLayout) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    range,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  status,
                                ],
                              ),
                              const SizedBox(height: 6),
                              details,
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: segment.isMultiMinute ? 92 : 48,
                              child: Text(
                                range,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          label,
                                          style: theme.textTheme.titleSmall,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      status,
                                    ],
                                  ),
                                  if (placeName != null) ...[
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.place_rounded,
                                          size: 16,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            placeName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color:
                                                      theme.colorScheme.primary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 2),
                                  Text(
                                    timelineSegmentSubtitle(segment),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Center(
                child: IconButton(
                  key: ValueKey(
                    'segment-edit-${segment.start.toIso8601String()}',
                  ),
                  tooltip: '$range 구간 편집',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionNotesCard extends ConsumerStatefulWidget {
  const _SessionNotesCard({
    required this.sessionId,
    required this.initialNotes,
    required this.enabled,
  });

  final String sessionId;
  final String? initialNotes;
  final bool enabled;

  @override
  ConsumerState<_SessionNotesCard> createState() => _SessionNotesCardState();
}

class _SessionNotesCardState extends ConsumerState<_SessionNotesCard> {
  late final TextEditingController _controller;
  var _saving = false;
  var _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNotes ?? '');
  }

  @override
  void didUpdateWidget(covariant _SessionNotesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && oldWidget.initialNotes != widget.initialNotes) {
      _controller.text = widget.initialNotes ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !widget.enabled) return;
    // May be triggered by focus loss during teardown — guard setState.
    _saving = true;
    if (mounted) setState(() {});
    try {
      await ref
          .read(walkRepositoryProvider)
          .updateSessionNotes(widget.sessionId, _controller.text);
      ref.read(historyTickProvider.notifier).state++;
      _dirty = false;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('메모를 저장했어요.')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('메모를 저장하지 못했어요.')));
      }
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('그날의 한마디', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '일기처럼 짧게 남겨 두세요. 이 기기에만 저장됩니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          // Autosave on focus loss so typed-but-not-tapped-save text isn't lost
          // when the user navigates back. The explicit button stays too.
          Focus(
            onFocusChange: (hasFocus) {
              if (!hasFocus && _dirty && !_saving) unawaited(_save());
            },
            child: TextField(
              controller: _controller,
              enabled: widget.enabled && !_saving,
              minLines: 2,
              maxLines: 5,
              maxLength: 280,
              textInputAction: TextInputAction.newline,
              onChanged: (_) => _dirty = true,
              decoration: const InputDecoration(hintText: '예: 강변 바람이 시원했다'),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: widget.enabled && !_saving
                  ? () => unawaited(_save())
                  : null,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('메모 저장'),
            ),
          ),
        ],
      ),
    );
  }
}
