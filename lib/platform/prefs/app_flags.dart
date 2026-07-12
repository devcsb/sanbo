import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Lightweight local flags (intro seen, etc.).
class AppFlags {
  AppFlags({this.hasSeenIntro = false});

  final bool hasSeenIntro;

  AppFlags copyWith({bool? hasSeenIntro}) {
    return AppFlags(hasSeenIntro: hasSeenIntro ?? this.hasSeenIntro);
  }

  Map<String, Object?> toJson() => {'hasSeenIntro': hasSeenIntro};

  static AppFlags fromJson(Map<String, Object?> json) {
    return AppFlags(hasSeenIntro: json['hasSeenIntro'] == true);
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
}
