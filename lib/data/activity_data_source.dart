import '../domain/services/local_calendar.dart';

enum ActivitySourceKind { healthConnect, healthKit, unavailable, denied, error }

enum ActivityCoverage { complete, partial, unavailable }

/// Result of checking or requesting access to the platform activity source.
///
/// This is deliberately separate from [ActivitySourceKind]. A source can be
/// installed but not connected yet, and a read can fail without turning a
/// legitimate zero-step value into an error.
enum ActivityAccessState { connected, denied, unavailable, error }

class DailyStepSnapshot {
  const DailyStepSnapshot({
    required this.date,
    required this.steps,
    required this.source,
    required this.coverage,
    this.recordedAt,
  });

  const DailyStepSnapshot.unavailable(DateTime date)
    : this(
        date: date,
        steps: null,
        source: ActivitySourceKind.unavailable,
        coverage: ActivityCoverage.unavailable,
      );

  final DateTime date;

  /// `null` means denied, unavailable, or a read error; zero is a valid
  /// reported total.
  final int? steps;
  final ActivitySourceKind source;
  final ActivityCoverage coverage;
  final DateTime? recordedAt;

  bool get isAvailable => steps != null;
}

abstract interface class ActivityDataSource {
  Future<List<DailyStepSnapshot>> readDailySteps({
    required DateTime startDate,
    required DateTime endDateExclusive,
  });
}

/// Optional capability exposed by a data source that can show a permission
/// flow. Keeping this separate preserves the small read-only seam for tests
/// and for future sources that are read-only by design.
abstract interface class ActivityDataSourceConnector {
  Future<ActivityAccessState> getAccessState();

  Future<ActivityAccessState> requestAccess();
}

/// Minimal reader contract used by [HealthActivityDataSource]. It keeps the
/// platform plugin behind a replaceable boundary and makes date/permission
/// behavior testable without a device or a method channel.
abstract interface class DailyStepsReader {
  ActivitySourceKind get sourceKind;

  Future<void> configure();

  Future<bool> isAvailable();

  Future<bool?> hasReadPermission();

  Future<bool> requestReadPermission();

  Future<int?> readTotalSteps({required DateTime start, required DateTime end});
}

/// Coordinates access state and normalizes daily totals from a platform
/// health provider. The concrete plugin reader lives in the platform layer.
class HealthActivityDataSource
    implements ActivityDataSource, ActivityDataSourceConnector {
  HealthActivityDataSource(this._reader);

  static const _cacheTtl = Duration(minutes: 5);
  static const _maxCachedDays = 31;

  final DailyStepsReader _reader;
  bool _configured = false;
  final Map<_DailyStepCacheKey, _CachedDailyStep> _cache = {};
  DateTime? _cachedRangeStart;
  DateTime? _cachedRangeEnd;

  @override
  Future<ActivityAccessState> getAccessState() async {
    try {
      await _configure();
      if (!await _reader.isAvailable()) {
        return ActivityAccessState.unavailable;
      }
      final permission = await _reader.hasReadPermission();
      if (permission == false) return ActivityAccessState.denied;

      // HealthKit intentionally returns null for read permission checks to
      // protect the user's privacy. A subsequent read is the real authority
      // on iOS, so treat an indeterminate result as connected there.
      if (permission == true ||
          _reader.sourceKind == ActivitySourceKind.healthKit) {
        return ActivityAccessState.connected;
      }
      return ActivityAccessState.error;
    } catch (_) {
      return ActivityAccessState.error;
    }
  }

  @override
  Future<ActivityAccessState> requestAccess() async {
    // Permission changes can make a previously successful total invalid. Clear
    // before entering the platform flow so an exception cannot leave stale
    // rows visible on the next history refresh.
    _clearCache();
    try {
      await _configure();
      if (!await _reader.isAvailable()) {
        return ActivityAccessState.unavailable;
      }
      final granted = await _reader.requestReadPermission();
      return granted
          ? ActivityAccessState.connected
          : ActivityAccessState.denied;
    } catch (_) {
      return ActivityAccessState.error;
    }
  }

  @override
  Future<List<DailyStepSnapshot>> readDailySteps({
    required DateTime startDate,
    required DateTime endDateExclusive,
  }) async {
    final start = localDateOnly(startDate);
    final end = localDateOnly(endDateExclusive);
    if (!end.isAfter(start)) return const [];

    // A week navigation outside the previously read range must not reuse a
    // stale partial window. The five-minute per-day cache still deduplicates
    // rebuilds and rotations within the same range.
    final previousStart = _cachedRangeStart;
    final previousEnd = _cachedRangeEnd;
    if (previousStart != null &&
        previousEnd != null &&
        (start.isBefore(previousStart) || end.isAfter(previousEnd))) {
      _clearCache();
      _cachedRangeStart = start;
      _cachedRangeEnd = end;
    } else {
      _cachedRangeStart = previousStart == null || start.isBefore(previousStart)
          ? start
          : previousStart;
      _cachedRangeEnd = previousEnd == null || end.isAfter(previousEnd)
          ? end
          : previousEnd;
    }

    final access = await getAccessState();
    if (access != ActivityAccessState.connected) {
      return [
        for (
          var date = start;
          date.isBefore(end);
          date = addLocalCalendarDays(date, 1)
        )
          _unavailableSnapshot(date, access),
      ];
    }

    final rows = <DailyStepSnapshot>[];
    for (
      var date = start;
      date.isBefore(end);
      date = addLocalCalendarDays(date, 1)
    ) {
      final cached = _cachedSnapshot(date);
      if (cached != null) {
        rows.add(cached);
        continue;
      }
      final dayEnd = addLocalCalendarDays(date, 1);
      int? steps;
      try {
        steps = await _reader.readTotalSteps(
          start: date,
          end: dayEnd.isBefore(end) ? dayEnd : end,
        );
      } catch (_) {
        // One protected/temporarily unavailable day (for example iOS health
        // data while the device is locked) must not hide the other six days.
        steps = null;
      }
      final snapshot = DailyStepSnapshot(
        date: date,
        steps: steps,
        source: steps == null ? ActivitySourceKind.error : _reader.sourceKind,
        coverage: steps == null
            ? ActivityCoverage.unavailable
            : ActivityCoverage.complete,
        recordedAt: DateTime.now(),
      );
      if (snapshot.steps != null &&
          snapshot.coverage == ActivityCoverage.complete) {
        _cache[_DailyStepCacheKey(_reader.sourceKind, date)] = _CachedDailyStep(
          snapshot,
          DateTime.now(),
        );
        _trimCache();
      }
      rows.add(snapshot);
    }
    return rows;
  }

  DailyStepSnapshot? _cachedSnapshot(DateTime date) {
    final key = _DailyStepCacheKey(_reader.sourceKind, date);
    final cached = _cache[key];
    if (cached == null) return null;
    if (DateTime.now().difference(cached.cachedAt) > _cacheTtl) {
      _cache.remove(key);
      return null;
    }
    return cached.snapshot;
  }

  void _trimCache() {
    if (_cache.length <= _maxCachedDays) return;
    final oldest = _cache.entries.reduce(
      (a, b) => a.value.cachedAt.isBefore(b.value.cachedAt) ? a : b,
    );
    _cache.remove(oldest.key);
  }

  void _clearCache() {
    _cache.clear();
    _cachedRangeStart = null;
    _cachedRangeEnd = null;
  }

  Future<void> _configure() async {
    if (_configured) return;
    await _reader.configure();
    _configured = true;
  }

  DailyStepSnapshot _unavailableSnapshot(
    DateTime date,
    ActivityAccessState state,
  ) => DailyStepSnapshot(
    date: date,
    steps: null,
    source: switch (state) {
      ActivityAccessState.denied => ActivitySourceKind.denied,
      ActivityAccessState.error => ActivitySourceKind.error,
      ActivityAccessState.connected ||
      ActivityAccessState.unavailable => ActivitySourceKind.unavailable,
    },
    coverage: ActivityCoverage.unavailable,
  );
}

final class _DailyStepCacheKey {
  const _DailyStepCacheKey(this.source, this.date);

  final ActivitySourceKind source;
  final DateTime date;

  @override
  bool operator ==(Object other) =>
      other is _DailyStepCacheKey &&
      other.source == source &&
      other.date == date;

  @override
  int get hashCode => Object.hash(source, date);
}

final class _CachedDailyStep {
  const _CachedDailyStep(this.snapshot, this.cachedAt);

  final DailyStepSnapshot snapshot;
  final DateTime cachedAt;
}

/// Default until the user explicitly connects a platform health provider.
/// It never requests permission and never turns missing data into zero.
class UnavailableActivityDataSource implements ActivityDataSource {
  const UnavailableActivityDataSource();

  @override
  Future<List<DailyStepSnapshot>> readDailySteps({
    required DateTime startDate,
    required DateTime endDateExclusive,
  }) async => const [];
}
