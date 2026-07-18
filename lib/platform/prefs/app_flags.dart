import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Lightweight local preferences needed before the widget tree starts.
class AppFlags {
  AppFlags({
    this.hasSeenIntro = false,
    this.trackingModeName = 'balanced',
    this.unlockedMilestones = const {},
  });

  final bool hasSeenIntro;
  final String trackingModeName;
  final Set<String> unlockedMilestones;

  AppFlags copyWith({
    bool? hasSeenIntro,
    String? trackingModeName,
    Set<String>? unlockedMilestones,
  }) {
    return AppFlags(
      hasSeenIntro: hasSeenIntro ?? this.hasSeenIntro,
      trackingModeName: trackingModeName ?? this.trackingModeName,
      unlockedMilestones: unlockedMilestones ?? this.unlockedMilestones,
    );
  }

  Map<String, Object?> toJson() => {
        'hasSeenIntro': hasSeenIntro,
        'trackingMode': trackingModeName,
        'unlockedMilestones': unlockedMilestones.toList()..sort(),
      };

  static AppFlags fromJson(Map<String, Object?> json) {
    final trackingMode = json['trackingMode'];
    final raw = json['unlockedMilestones'];
    final milestones = <String>{};
    if (raw is List) {
      for (final item in raw) {
        if (item is String && item.isNotEmpty) milestones.add(item);
      }
    }
    return AppFlags(
      hasSeenIntro: json['hasSeenIntro'] == true,
      trackingModeName: trackingMode is String && trackingMode.isNotEmpty
          ? trackingMode
          : 'balanced',
      unlockedMilestones: milestones,
    );
  }
}

class AppFlagsStore {
  AppFlagsStore({this.pathOverride});

  final String? pathOverride;

  Future<File> _file() async {
    final override = pathOverride;
    if (override != null) return File(override);
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'app_flags.json'));
  }

  Future<AppFlags> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return AppFlags();
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return AppFlags();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return AppFlags();
      return AppFlags.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      return AppFlags();
    }
  }

  Future<void> save(AppFlags flags) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(flags.toJson()));
  }

  Future<void> setHasSeenIntro(bool value) async {
    final current = await load();
    await save(current.copyWith(hasSeenIntro: value));
  }

  Future<void> setTrackingModeName(String value) async {
    final current = await load();
    await save(current.copyWith(trackingModeName: value));
  }

  Future<Set<String>> unlockMilestones(Iterable<String> ids) async {
    final current = await load();
    final next = {...current.unlockedMilestones, ...ids};
    if (next.length == current.unlockedMilestones.length) {
      return {};
    }
    final newly = next.difference(current.unlockedMilestones);
    await save(current.copyWith(unlockedMilestones: next));
    return newly;
  }
}
