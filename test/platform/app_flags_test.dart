import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/features/settings/tracking_mode_setting.dart';
import 'package:sanbo/platform/prefs/app_flags.dart';

void main() {
  test('legacy flags default to balanced tracking', () {
    final flags = AppFlags.fromJson({'hasSeenIntro': true});

    expect(flags.hasSeenIntro, isTrue);
    expect(flags.trackingModeName, 'balanced');
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
}
