enum ActivitySourceKind { healthConnect, healthKit, unavailable, denied }

enum ActivityCoverage { complete, partial, unavailable }

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

  /// `null` means denied/unavailable; zero is a valid reported total.
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
