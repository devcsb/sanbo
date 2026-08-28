import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/services/local_calendar.dart';

void main() {
  test('normalizes UTC instants to the local calendar date', () {
    final value = DateTime.utc(2026, 8, 15, 23, 30);

    final day = localDateOnly(value);

    expect(day.hour, 0);
    expect(day.minute, 0);
    expect(day.year, value.toLocal().year);
    expect(day.month, value.toLocal().month);
    expect(day.day, value.toLocal().day);
  });

  test('adds calendar days at local midnight', () {
    final value = DateTime(2026, 8, 15, 13, 45);

    final next = addLocalCalendarDays(value, 1);
    final previous = addLocalCalendarDays(value, -1);

    expect(next, DateTime(2026, 8, 16));
    expect(previous, DateTime(2026, 8, 14));
  });
}
