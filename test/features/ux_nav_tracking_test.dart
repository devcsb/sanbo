import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  test('ScaffoldWithNavBar ships tracking label and leave-home snack copy', () {
    final src = File(
      'lib/shared/widgets/app_bottom_nav.dart',
    ).readAsStringSync();
    expect(src, contains('ConsumerWidget'));
    expect(src, contains("tracking ? '기록 중' : '홈'"));
    expect(src, contains('산책 기록은 계속됩니다'));
    expect(src, contains('leavingHome'));
    expect(src, contains('isTracking'));
  });

  test(
    'app lifecycle suppresses presentation work as soon as it becomes inactive',
    () {
      final src = File('lib/app.dart').readAsStringSync();
      expect(src, contains('onInactive'));
      expect(src, contains('setAppInactive()'));
    },
  );
}
