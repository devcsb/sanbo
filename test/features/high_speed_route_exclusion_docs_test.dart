import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _section(String document, String start, String end) {
  final startIndex = document.indexOf(start);
  final endIndex = document.indexOf(end, startIndex);
  if (startIndex == -1 || endIndex == -1) return '';
  return document.substring(startIndex, endIndex);
}

void main() {
  test(
    'PRD documents the complete high-speed confirmation and refresh contract',
    () {
      final prd = File('docs/PRD.md').readAsStringSync();
      final requirement = _section(
        prd,
        '### FR: 고속 이동 종료 확인과 기록 구간 제외',
        '### 6.4',
      );

      for (final contract in [
        '120초',
        '60초',
        '28.8km/h',
        '14.4km/h',
        '30초',
        '기록 종료',
        '계속 기록',
        '자동 종료하지 않고',
        '산책에서 제외',
        '제외 취소',
        '지도, 세션 통계, 기록 화면 합계와 일별 합계',
      ]) {
        expect(requirement, contains(contract));
      }
    },
  );

  test('TRD scopes shipped storage, guard, backup, and notification contracts', () {
    final trd = File('docs/TRD.md').readAsStringSync();
    final guard = _section(trd, '### 3.7 고속 guard와 경로 제외 계약', '---\n\n## 4.');
    final export = _section(trd, '### 9.2 Export 포맷', '---\n\n## 10.');

    for (final contract in [
      'DB schemaVersion = 4',
      'route_exclusions',
      'minute_windows.user_exclusion_id',
      'location_samples.user_exclusion_id` 열은 만들지 않는다',
      'location_samples.is_filtered_out',
      '[startAt, endAt)',
      '제외 레코드 삽입, 분 기록 전체 교체, 세션 집계 갱신 순',
      'abstract final class RoutePartitioner',
      'static RoutePartitionResult partition',
      'SessionGuardDecision evaluate',
      'void continueStationaryTracking(DateTime now)',
      'Stream<SessionNotificationTap> get taps',
      'Future<void> showCompletion({required String title, required String body})',
      'duration limit, stationary limit, duration warning, stationary warning, high-speed warning',
      'observedAt',
      'notificationTapped({kind: highSpeed})',
    ]) {
      expect(guard, contains(contract));
    }
    for (final contract in [
      'schema_version: 2',
      'backup_schema_version: 2',
      'v1과 v2를 지원',
      'route_exclusions',
      'user_exclusion_id',
    ]) {
      expect(export, contains(contract));
    }
  });

  test(
    'device matrix keeps every Android and iOS scenario unverified and observable',
    () {
      final matrix = File('docs/DEVICE_VALIDATION.md').readAsStringSync();
      expect(
        matrix,
        contains('| 확인 | 플랫폼 | 기기·OS | 권한 상태 | 기대 상태 | 관측 결과 | 통과/실패 |'),
      );

      const scenarios = [
        'foreground warning without system banner',
        'background notification',
        'screen-off notification',
        'warm tap',
        'killed-app cold tap',
        'notification denied',
        'notification API failure',
        'continued background location',
        'route exclusion',
        'all-points exclusion',
        'restore',
        'app restart persistence',
      ];
      for (final platform in ['Android', 'iOS']) {
        for (final scenario in scenarios) {
          final row = matrix
              .split('\n')
              .singleWhere(
                (line) => line.contains('| [ ] $scenario | $platform |'),
              );
          expect(row, contains('위치: '));
          expect(row, contains('알림: '));
          expect(row, contains('미판정'));
        }
      }
    },
  );
}
