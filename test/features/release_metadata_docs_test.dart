import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android release metadata records the selected candidate and evidence',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final release = File(
        'docs/release/2026-10-14-maintenance-stage1-release.md',
      ).readAsStringSync();

      expect(pubspec, contains('version: 0.9.2+16'));
      for (final contract in [
        '0.9.2+16',
        'app-release.aab',
        'app-arm64-v8a-release.apk',
        'SHA-256',
        'targetSdk 36',
        '물리 Android 기기 검증: 미실행',
      ]) {
        expect(release, contains(contract));
      }
    },
  );
}
