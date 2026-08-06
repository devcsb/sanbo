import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sanbo/data/walk_repository.dart';

var _ffiReady = false;

void ensureSqfliteFfi() {
  if (_ffiReady) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _ffiReady = true;
}

Future<WalkRepository> openTestRepository({String? path}) async {
  ensureSqfliteFfi();
  final databasePath =
      path ??
      '${Directory.systemTemp.path}/sanbo_test_${DateTime.now().microsecondsSinceEpoch}.db';
  final repo = await WalkRepository.open(path: databasePath);
  return repo;
}
