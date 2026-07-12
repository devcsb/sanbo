import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../app.dart';
import '../data/walk_repository.dart';
import '../features/home/session_controller.dart';
import '../platform/location/geolocator_location_engine.dart';
import '../platform/location/location_engine.dart';
import '../platform/location/synthetic_location_engine.dart';

const appLogName = 'sanbo';

/// When true (tests), bootstrap is not used; ProviderScope overrides inject deps.
Future<void> bootstrapAndRun({
  WalkRepository? repository,
  LocationEngine? locationEngine,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorLogging();
  await initializeDateFormatting('ko', null);

  final repo = repository ?? await WalkRepository.open();
  final engine = locationEngine ??
      (Platform.isAndroid || Platform.isIOS
          ? GeolocatorLocationEngine()
          : SyntheticLocationEngine(
              permission: LocationPermissionState.granted,
            ));

  final container = ProviderContainer(
    observers: const [AppProviderObserver()],
    overrides: [
      walkRepositoryProvider.overrideWithValue(repo),
      locationEngineProvider.overrideWithValue(engine),
    ],
  );

  // Recover incomplete session after first frame without blocking startup.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      container.read(sessionControllerProvider.notifier).restoreIfNeeded(),
    );
  });

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SanboApp(),
    ),
  );
}

void logUncaughtZoneError(Object error, StackTrace stack) {
  developer.log(
    'Uncaught zone error',
    name: appLogName,
    error: error,
    stackTrace: stack,
  );
}

void _installErrorLogging() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    developer.log(
      'FlutterError',
      name: appLogName,
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    developer.log(
      'PlatformDispatcher error',
      name: appLogName,
      error: error,
      stackTrace: stack,
    );
    return true;
  };
}

final class AppProviderObserver extends ProviderObserver {
  const AppProviderObserver();

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    developer.log(
      'Provider failed: ${provider.name ?? provider.runtimeType}',
      name: appLogName,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
