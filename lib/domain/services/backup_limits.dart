import '../pipeline/geo.dart';

const maxSessionProcessingSpan = Duration(days: 7);
const maxProcessingWindows = 10081;
const maxStoredMagnitude = 1e9;
const maxStoredSampleCount = 500000;

/// Resource bound, not a walking classifier. Never truncates a user's record.
int validateProcessingSpan(DateTime start, DateTime end) {
  final span = end.difference(start);
  if (span.isNegative || span > maxSessionProcessingSpan) {
    throw const FormatException('산책 한 건은 최대 7일까지 처리할 수 있어요. 원본 기록은 변경하지 않았어요.');
  }
  return positiveDurationSeconds(start, end);
}
