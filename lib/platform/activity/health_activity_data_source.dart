import 'dart:io' show Platform;

import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/activity_data_source.dart';

/// Production adapter for Apple HealthKit and Google Health Connect.
///
/// Reads are intentionally on-demand from the history screen. No observer,
/// background task, or polling loop is installed, so connecting health data
/// does not add to the GPS session's battery budget.
class HealthPluginDailyStepsReader implements DailyStepsReader {
  HealthPluginDailyStepsReader({Health? health}) : _health = health ?? Health();

  final Health _health;

  @override
  ActivitySourceKind get sourceKind => Platform.isIOS
      ? ActivitySourceKind.healthKit
      : ActivitySourceKind.healthConnect;

  @override
  Future<void> configure() => _health.configure();

  @override
  Future<bool> isAvailable() async {
    if (Platform.isIOS) return true;
    return _health.isHealthConnectAvailable();
  }

  @override
  Future<bool?> hasReadPermission() async {
    if (Platform.isAndroid) {
      final activityPermission = await Permission.activityRecognition.status;
      if (!activityPermission.isGranted) return false;
    }
    return _health.hasPermissions(const [HealthDataType.STEPS]);
  }

  @override
  Future<bool> requestReadPermission() async {
    if (Platform.isAndroid) {
      final activityPermission = await Permission.activityRecognition.request();
      if (!activityPermission.isGranted) return false;
    }
    return _health.requestAuthorization(const [HealthDataType.STEPS]);
  }

  @override
  Future<int?> readTotalSteps({
    required DateTime start,
    required DateTime end,
  }) => _health.getTotalStepsInInterval(start, end);
}

HealthActivityDataSource createPlatformHealthActivityDataSource() =>
    HealthActivityDataSource(HealthPluginDailyStepsReader());
