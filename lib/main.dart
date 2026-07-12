import 'dart:async';

import 'app/bootstrap.dart';

void main() {
  runZonedGuarded(bootstrapAndRun, logUncaughtZoneError);
}
