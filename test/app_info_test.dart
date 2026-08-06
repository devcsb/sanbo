import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/app/app_info.dart';

void main() {
  test('display version stays aligned with the package release version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: ${AppInfo.version}+'));
  });
}
