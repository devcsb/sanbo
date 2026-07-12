import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bump to refresh history list after stop/delete.
final historyTickProvider = StateProvider<int>((ref) => 0);
