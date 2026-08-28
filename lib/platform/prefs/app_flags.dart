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
  Future<void> _writeTail = Future<void>.value();

  Future<File> _file() async {
    final override = pathOverride;
    if (override != null) return File(override);
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'app_flags.json'));
  }

  Future<AppFlags> load() async {
    // Reads wait for an in-flight atomic rename so callers never observe the
    // previous generation halfway through a read-modify-write update.
    await _writeTail;
    return _loadNow();
  }

  Future<AppFlags> _loadNow() async {
    final file = await _file();
    try {
      return await _readFlagsFile(file);
    } on Object {
      // A process kill between the temp write and rename can leave only the
      // sibling file. Recover it when it is valid; otherwise keep defaults.
      try {
        return await _readFlagsFile(File('${file.path}.tmp'));
      } on Object {
        return AppFlags();
      }
    }
  }

  Future<void> save(AppFlags flags) async {
    await _enqueueWrite(() => _saveNow(flags));
  }

  Future<void> _saveNow(AppFlags flags) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    final access = await temporary.open(mode: FileMode.write);
    try {
      await access.writeString(jsonEncode(flags.toJson()));
      await access.flush();
    } finally {
      await access.close();
    }
    await temporary.rename(file.path);
  }

  Future<AppFlags> _readFlagsFile(File file) async {
    if (!await file.exists()) throw const FileSystemException('flags missing');
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) throw const FormatException('flags empty');
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('flags must be an object');
    return AppFlags.fromJson(Map<String, Object?>.from(decoded));
  }

  Future<void> setHasSeenIntro(bool value) async {
    await _enqueueWrite(() async {
      final current = await _loadNow();
      await _saveNow(current.copyWith(hasSeenIntro: value));
    });
  }

  Future<void> setTrackingModeName(String value) async {
    await _enqueueWrite(() async {
      final current = await _loadNow();
      await _saveNow(current.copyWith(trackingModeName: value));
    });
  }

  Future<Set<String>> unlockMilestones(Iterable<String> ids) async {
    return _enqueueWrite(() async {
      final current = await _loadNow();
      final next = {...current.unlockedMilestones, ...ids};
      if (next.length == current.unlockedMilestones.length) {
        return <String>{};
      }
      final newly = next.difference(current.unlockedMilestones);
      await _saveNow(current.copyWith(unlockedMilestones: next));
      return newly;
    });
  }

  Future<T> _enqueueWrite<T>(Future<T> Function() operation) {
    final next = _writeTail.then<T>((_) => operation());
    _writeTail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}
