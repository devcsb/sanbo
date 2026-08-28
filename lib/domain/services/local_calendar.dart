/// Normalizes an instant to the device's local calendar date at midnight.
DateTime localDateOnly(DateTime value) {
  final local = value.isUtc ? value.toLocal() : value;
  return DateTime(local.year, local.month, local.day);
}

/// Adds calendar days without assuming every local day is 24 hours.
///
/// Adding a [Duration] to a local [DateTime] walks the absolute timeline. On
/// daylight-saving transitions that can land at 23:00 or 01:00 on the next
/// date. Reconstructing midnight from year/month/day keeps daily query ranges
/// aligned to local calendar boundaries.
DateTime addLocalCalendarDays(DateTime value, int days) {
  final local = value.isUtc ? value.toLocal() : value;
  return DateTime(local.year, local.month, local.day + days);
}
