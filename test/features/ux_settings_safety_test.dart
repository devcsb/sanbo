import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/core/theme/app_theme.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/services/app_backup.dart';
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

  testWidgets(
    'privacy disclosures and backup remain readable on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late WalkRepository repository;
      await tester.runAsync(
        () async => repository = await openTestRepository(),
      );
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
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (_, child) => MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.scrollUntilVisible(find.textContaining('IP 주소'), 250);
      expect(find.textContaining('표시 위치를 추정'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('주소 조회 서비스'), 200);
      expect(find.textContaining('요청할 때만'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('전체 백업 내보내기'), 200);
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, '전체 백업 내보내기'))
            .enabled,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('recovered walk disables mode changes and delete-all', (
    tester,
  ) async {
    late WalkRepository repository;
    await tester.runAsync(() async {
      repository = await openTestRepository();
      await repository.startSession(
        mode: TrackingMode.highAccuracy,
        startedAt: DateTime.now().subtract(const Duration(hours: 1)),
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
    expect(find.textContaining('앱 삭제 전 보관'), findsOneWidget);
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
        'route_exclusions': [],
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
    final importDialog = find.textContaining('기존 기록은 지우지 않고');
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (importDialog.evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(importDialog, findsOneWidget);
    await tester.tap(find.text('가져오기'));
    await tester.pump();
    final imported = find.text('산책 0개를 가져왔어요');
    final importDeadline = DateTime.now().add(const Duration(seconds: 3));
    while (imported.evaluate().isEmpty &&
        DateTime.now().isBefore(importDeadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(imported, findsOneWidget);
  });
}
