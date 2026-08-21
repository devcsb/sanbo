import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'PRD and TRD document high-speed warning and reversible exclusion contracts',
    () {
      final prd = File('docs/PRD.md').readAsStringSync();
      final trd = File('docs/TRD.md').readAsStringSync();
      expect(prd, contains('28.8km/h'));
      expect(prd, contains('60초'));
      expect(prd, contains('기록 종료'));
      expect(prd, contains('계속 기록'));
      expect(prd, contains('산책에서 제외'));
      expect(prd, contains('제외 취소'));
      expect(trd, contains('route_exclusions'));
      expect(trd, contains('user_exclusion_id'));
      expect(trd, contains('RoutePartitioner'));
      expect(trd, contains('backup_schema_version: 2'));
      expect(trd, contains('notificationTapped({kind: highSpeed})'));
    },
  );
}
