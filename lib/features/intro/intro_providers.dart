import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/prefs/app_flags.dart';

final appFlagsStoreProvider = Provider<AppFlagsStore>((ref) => AppFlagsStore());

/// When false, router sends the user to the brand intro once.
final introSeenProvider = StateProvider<bool>((ref) => true);
