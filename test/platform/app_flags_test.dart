import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/features/settings/tracking_mode_setting.dart';
import 'package:sanbo/platform/prefs/app_flags.dart';

void main() {
  test('legacy flags default to balanced tracking', () {
    final flags = AppFlags.fromJson({'hasSeenIntro': true});

    expect(flags.hasSeenIntro, isTrue);
    expect(flags.trackingModeName, 'balanced');
    expect(flags.unlockedMilestones, isEmpty);
    expect(trackingModeFromStoredName('not-a-mode').name, 'balanced');
  });

  test('tracking preference persists without losing intro flag', () async {
    final directory = await Directory.systemTemp.createTemp('sanbo_flags_');
    addTearDown(() => directory.delete(recursive: true));
    final store = AppFlagsStore(
      pathOverride: '${directory.path}/app_flags.json',
    );

    await store.setHasSeenIntro(true);
    await store.setTrackingModeName('batterySaver');
    final restored = await store.load();

    expect(restored.hasSeenIntro, isTrue);
    expect(restored.trackingModeName, 'batterySaver');
    expect(
      trackingModeFromStoredName(restored.trackingModeName).name,
      'batterySaver',
    );
  });

  test('milestones unlock accumulates without wiping intro', () async {
    final directory = await Directory.systemTemp.createTemp('sanbo_flags_ms_');
    addTearDown(() => directory.delete(recursive: true));
    final store = AppFlagsStore(
      pathOverride: '${directory.path}/app_flags.json',
    );

    await store.setHasSeenIntro(true);
    final first = await store.unlockMilestones(['first_walk']);
    expect(first, {'first_walk'});
    final again = await store.unlockMilestones(['first_walk', 'walks_5']);
    expect(again, {'walks_5'});
    final restored = await store.load();
    expect(restored.hasSeenIntro, isTrue);
    expect(restored.unlockedMilestones, containsAll(['first_walk', 'walks_5']));
  });
}
