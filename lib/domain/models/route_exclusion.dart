import 'walk_session.dart';

enum RouteExclusionReason { vehicle }

class RouteExclusion {
  factory RouteExclusion({
    required String id,
    required String sessionId,
    required DateTime startAt,
    required DateTime endAt,
    required RouteExclusionReason reason,
    required DateTime createdAt,
  }) {
    if (id.trim().isEmpty || id != id.trim()) {
      throw ArgumentError.value(id, 'id', '비어 있거나 공백이 있는 ID입니다');
    }
    if (sessionId.trim().isEmpty || sessionId != sessionId.trim()) {
      throw ArgumentError.value(
        sessionId,
        'sessionId',
        '비어 있거나 공백이 있는 세션 ID입니다',
      );
    }
    final normalizedStart = startAt.toUtc();
    final normalizedEnd = endAt.toUtc();
    if (!normalizedStart.isBefore(normalizedEnd)) {
      throw ArgumentError('제외 시작은 종료보다 빨라야 합니다');
    }
    return RouteExclusion._(
      id: id,
      sessionId: sessionId,
      startAt: normalizedStart,
      endAt: normalizedEnd,
      reason: reason,
      createdAt: createdAt.toUtc(),
    );
  }

  const RouteExclusion._({
    required this.id,
    required this.sessionId,
    required this.startAt,
    required this.endAt,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final DateTime startAt;
  final DateTime endAt;
  final RouteExclusionReason reason;
  final DateTime createdAt;

  RouteExclusion clampedTo(WalkSession session) {
    final endedAt = session.endedAt;
    if (session.id != sessionId ||
        endedAt == null ||
        session.status != SessionStatus.completed) {
      throw StateError('완료된 대상 산책과 제외 범위가 일치하지 않습니다');
    }
    final sessionStart = session.startedAt.toUtc();
    final sessionEnd = endedAt.toUtc();
    final start = startAt.isBefore(sessionStart) ? sessionStart : startAt;
    final end = endAt.isAfter(sessionEnd) ? sessionEnd : endAt;
    if (!start.isBefore(end)) {
      throw ArgumentError('제외할 수 있는 시간 범위가 없습니다');
    }
    return RouteExclusion(
      id: id,
      sessionId: sessionId,
      startAt: start,
      endAt: end,
      reason: reason,
      createdAt: createdAt,
    );
  }

  bool contains(DateTime value) {
    final instant = value.toUtc();
    return !instant.isBefore(startAt) && instant.isBefore(endAt);
  }

  bool overlaps(DateTime start, DateTime end) {
    return start.toUtc().isBefore(endAt) && end.toUtc().isAfter(startAt);
  }
}
