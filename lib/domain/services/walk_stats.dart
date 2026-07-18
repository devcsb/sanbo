import '../models/walk_session.dart';

/// Quiet personal milestones — no streaks, leaderboards, or competitive badges.
/// PRD rejects social gamification; these are private reflection cues only.
class WalkMilestone {
  const WalkMilestone({
    required this.id,
    required this.title,
    required this.detail,
  });

  final String id;
  final String title;
  final String detail;
}

/// Aggregate stats over completed walks (local-only, no ranking).
class WalkStats {
  const WalkStats({
    required this.walkCount,
    required this.totalDistanceM,
    required this.totalDurationS,
    required this.longestDurationS,
    required this.longestDistanceM,
  });

  final int walkCount;
  final double totalDistanceM;
  final int totalDurationS;
  final int longestDurationS;
  final double longestDistanceM;

  double get totalDistanceKm => totalDistanceM / 1000.0;
  double get longestDistanceKm => longestDistanceM / 1000.0;

  Duration get totalDuration => Duration(seconds: totalDurationS);
  Duration get longestDuration => Duration(seconds: longestDurationS);

  static WalkStats empty() => const WalkStats(
        walkCount: 0,
        totalDistanceM: 0,
        totalDurationS: 0,
        longestDurationS: 0,
        longestDistanceM: 0,
      );

  factory WalkStats.fromSessions(Iterable<WalkSession> sessions) {
    var count = 0;
    var distance = 0.0;
    var duration = 0;
    var longestDur = 0;
    var longestDist = 0.0;

    for (final s in sessions) {
      if (s.status != SessionStatus.completed) continue;
      count += 1;
      final d = s.totalDistanceM ?? 0;
      final t = s.durationS ?? 0;
      distance += d;
      duration += t;
      if (t > longestDur) longestDur = t;
      if (d > longestDist) longestDist = d;
    }

    return WalkStats(
      walkCount: count,
      totalDistanceM: distance,
      totalDurationS: duration,
      longestDurationS: longestDur,
      longestDistanceM: longestDist,
    );
  }

  /// All milestones currently satisfied by this aggregate (and optional last walk).
  List<WalkMilestone> satisfied({WalkSession? latest}) {
    final out = <WalkMilestone>[];
    if (walkCount >= 1) {
      out.add(
        const WalkMilestone(
          id: 'first_walk',
          title: '첫 산책을 남겼어요',
          detail: '기록이 시작됐어요. 천천히 쌓이면 됩니다.',
        ),
      );
    }
    if (walkCount >= 5) {
      out.add(
        const WalkMilestone(
          id: 'walks_5',
          title: '산책 5번',
          detail: '짧은 걸음도 다섯 번이면 흐름이 보여요.',
        ),
      );
    }
    if (walkCount >= 10) {
      out.add(
        const WalkMilestone(
          id: 'walks_10',
          title: '산책 10번',
          detail: '열 번의 동선이 쌓였어요.',
        ),
      );
    }
    if (totalDistanceM >= 5000) {
      out.add(
        const WalkMilestone(
          id: 'distance_5km',
          title: '누적 5 km',
          detail: '작은 기록들이 모여 5 km가 됐어요.',
        ),
      );
    }
    if (totalDistanceM >= 20000) {
      out.add(
        const WalkMilestone(
          id: 'distance_20km',
          title: '누적 20 km',
          detail: '동네 산책이 꽤 멀어졌네요.',
        ),
      );
    }
    if (totalDistanceM >= 50000) {
      out.add(
        const WalkMilestone(
          id: 'distance_50km',
          title: '누적 50 km',
          detail: '조용히 쌓인 거리예요. 자랑할 필요는 없어요.',
        ),
      );
    }
    final longSession =
        (latest?.durationS ?? 0) >= 3600 || longestDurationS >= 3600;
    if (longSession) {
      out.add(
        const WalkMilestone(
          id: 'long_walk_60m',
          title: '한 번에 60분',
          detail: '긴 산책을 끝까지 남겼어요.',
        ),
      );
    }
    return out;
  }

  /// Milestones newly reached vs previously unlocked ids.
  List<WalkMilestone> newlyUnlocked(
    Set<String> alreadyUnlocked, {
    WalkSession? latest,
  }) {
    return satisfied(latest: latest)
        .where((m) => !alreadyUnlocked.contains(m.id))
        .toList();
  }

  String summaryLine() {
    if (walkCount == 0) return '아직 쌓인 산책이 없어요';
    final km = totalDistanceKm;
    final kmText = km >= 10
        ? km.toStringAsFixed(0)
        : km.toStringAsFixed(km >= 1 ? 1 : 2);
    return '산책 $walkCount번 · 누적 $kmText km';
  }
}

/// Human-readable pace (min:sec per km) when speed is meaningful.
String? pacePerKmLabel(double? avgSpeedMps) {
  if (avgSpeedMps == null || avgSpeedMps < 0.3) return null;
  final sec = 1000 / avgSpeedMps;
  if (!sec.isFinite || sec <= 0 || sec > 3600) return null;
  final total = sec.round();
  final m = total ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s /km';
}

String formatDurationCompact(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}
