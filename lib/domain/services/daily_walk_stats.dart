/// Completed-walk totals for one local calendar day.
class DailyWalkStats {
  const DailyWalkStats({
    required this.date,
    required this.walkCount,
    required this.totalDistanceM,
    required this.totalDurationS,
  });

  final DateTime date;
  final int walkCount;
  final double totalDistanceM;
  final int totalDurationS;

  double get totalDistanceKm => totalDistanceM / 1000.0;

  Duration get totalDuration => Duration(seconds: totalDurationS);

  static DailyWalkStats zero(DateTime date) {
    return DailyWalkStats(
      date: DateTime(date.year, date.month, date.day),
      walkCount: 0,
      totalDistanceM: 0,
      totalDurationS: 0,
    );
  }
}
