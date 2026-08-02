import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/core/theme/app_theme.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/services/app_backup.dart';
import 'package:sanbo/features/history/history_providers.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/features/settings/settings_screen.dart';
import 'package:sanbo/platform/backup/backup_file_service.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';

import '../helpers/test_db.dart';

class _FakeBackupFileService implements BackupFileService {
  _FakeBackupFileService({this.toPick});

  final PickedBackupFile? toPick;
  Uint8List? savedBytes;
  String? savedName;

  @override
  Future<PickedBackupFile?> pick() async => toPick;

  @override
  Future<String?> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    savedName = fileName;
    savedBytes = bytes;
    return '/tmp/$fileName';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recovered walk disables mode changes and delete-all', (
    tester,
  ) async {
    late WalkRepository repository;
    await tester.runAsync(() async {
      repository = await openTestRepository();
      await repository.startSession(
        mode: TrackingMode.highAccuracy,
        startedAt: DateTime(2026, 7, 16, 8),
      );
    });
    addTearDown(() => tester.runAsync(repository.close));

    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repository),
        locationEngineProvider.overrideWithValue(
          SyntheticLocationEngine(permission: LocationPermissionState.granted),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () =>
          container.read(sessionControllerProvider.notifier).restoreIfNeeded(),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    final deleteTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '모든 기록 삭제'),
    );
    final selector = tester.widget<SegmentedButton<TrackingMode>>(
      find.byType(SegmentedButton<TrackingMode>),
    );
    final exportTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '전체 백업 내보내기'),
    );
    final importTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '백업 가져오기'),
    );
    expect(deleteTile.enabled, isFalse);
    expect(deleteTile.onTap, isNull);
    expect(exportTile.enabled, isFalse);
    expect(importTile.enabled, isFalse);
    expect(selector.onSelectionChanged, isNull);
    expect(find.textContaining('진행 중인 산책을 마친 뒤'), findsNWidgets(2));
  });

  testWidgets('backup export warns about precise location and saves a file', (
    tester,
  ) async {
    late WalkRepository repository;
    await tester.runAsync(() async {
      repository = await openTestRepository();
    });
    final files = _FakeBackupFileService();
    addTearDown(repository.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repository),
          locationEngineProvider.overrideWithValue(
            SyntheticLocationEngine(
              permission: LocationPermissionState.granted,
            ),
          ),
          backupFileServiceProvider.overrideWithValue(files),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전체 백업 내보내기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('정밀한 GPS 경로'), findsOneWidget);
    await tester.tap(find.text('파일 저장'));
    await tester.pump();
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (files.savedBytes == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(files.savedName, endsWith('.sanbo'));
    expect(files.savedBytes, isNotNull);
    expect(
      AppBackupCodec.decodeBytes(files.savedBytes!).table('sessions'),
      isEmpty,
    );
    expect(find.text('전체 백업 파일을 저장했어요'), findsOneWidget);
  });

  testWidgets('backup import confirms merge semantics and refreshes history', (
    tester,
  ) async {
    late WalkRepository repository;
    await tester.runAsync(() async {
      repository = await openTestRepository();
    });
    final raw = AppBackupCodec.encode(
      databaseSchemaVersion: 2,
      tables: const {
        'sessions': [],
        'location_samples': [],
        'minute_windows': [],
        'places': [],
      },
    );
    final files = _FakeBackupFileService(
      toPick: PickedBackupFile(
        name: 'safe.sanbo',
        bytes: Uint8List.fromList(utf8.encode(raw)),
      ),
    );
    addTearDown(repository.close);

    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repository),
        locationEngineProvider.overrideWithValue(
          SyntheticLocationEngine(permission: LocationPermissionState.granted),
        ),
        backupFileServiceProvider.overrideWithValue(files),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('백업 가져오기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('기존 기록은 지우지 않고'), findsOneWidget);
    await tester.tap(find.text('가져오기'));
    await tester.pump();
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (container.read(historyTickProvider) == 0 &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(find.text('산책 0개를 가져왔어요'), findsOneWidget);
  });
}
