import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/platform/prefs/app_flags.dart';

void main() {
  test(
    'loads the last valid flags when an interrupted temp file is present',
    () async {
      final path =
          '${Directory.systemTemp.path}/sanbo_flags_${DateTime.now().microsecondsSinceEpoch}.json';
      final file = File(path);
      addTearDown(() async {
        await file.delete().catchError((_) => file);
        await File('$path.tmp').delete().catchError((_) => File('$path.tmp'));
      });
      final store = AppFlagsStore(pathOverride: path);
      await store.save(AppFlags(hasSeenIntro: true));
      await File('$path.tmp').writeAsString('{not-json');

      final loaded = await store.load();

      expect(loaded.hasSeenIntro, isTrue);
    },
  );

  test('recovers a valid temp file when the target is missing', () async {
    final path =
        '${Directory.systemTemp.path}/sanbo_flags_${DateTime.now().microsecondsSinceEpoch}.json';
    final file = File(path);
    addTearDown(() async {
      await file.delete().catchError((_) => file);
      await File('$path.tmp').delete().catchError((_) => File('$path.tmp'));
    });
    await File('$path.tmp').writeAsString(
      '{"hasSeenIntro":true,"trackingMode":"balanced","unlockedMilestones":[]}',
    );

    final loaded = await AppFlagsStore(pathOverride: path).load();

    expect(loaded.hasSeenIntro, isTrue);
  });

  test('serializes concurrent read-modify-write updates', () async {
    final path =
        '${Directory.systemTemp.path}/sanbo_flags_${DateTime.now().microsecondsSinceEpoch}.json';
    final file = File(path);
    addTearDown(() async {
      await file.delete().catchError((_) => file);
      await File('$path.tmp').delete().catchError((_) => File('$path.tmp'));
    });
    final store = AppFlagsStore(pathOverride: path);

    await Future.wait([
      store.setHasSeenIntro(true),
      store.setTrackingModeName('high_accuracy'),
      store.unlockMilestones(['first_walk']),
    ]);

    final loaded = await store.load();
    expect(loaded.hasSeenIntro, isTrue);
    expect(loaded.trackingModeName, 'high_accuracy');
    expect(loaded.unlockedMilestones, contains('first_walk'));
  });
}
