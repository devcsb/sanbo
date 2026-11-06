import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sanbo/data/app_database.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/core/theme/app_theme.dart';
import 'package:sanbo/domain/services/app_backup.dart';
import 'package:sanbo/features/history/history_providers.dart';
import 'package:sanbo/features/settings/settings_screen.dart';
import 'package:sanbo/platform/backup/backup_file_service.dart';
import '../helpers/test_db.dart';

class DelayedImport extends WalkRepository {
  DelayedImport(super.db);
  final completion = Completer<BackupImportResult>();
  bool started = false;
  @override
  Future<BackupImportResult> importBackup(AppBackupArchive archive) {
    started = true;
    return completion.future;
  }
}

class PickFile implements BackupFileService {
  @override
  Future<void> cancelPick() async {}
  @override
  Future<String?> save({
    required String fileName,
    required Uint8List bytes,
  }) async => null;
  @override
  Future<PickedBackupFile?> pick() async => PickedBackupFile(
    name: 'test.sanbo',
    bytes: Uint8List.fromList(
      utf8.encode(
        AppBackupCodec.encode(
          databaseSchemaVersion: 6,
          tables: {for (final name in AppBackupCodec.requiredTables) name: []},
        ),
      ),
    ),
  );
}

class ReadingFile extends PickFile {
  final completion = Completer<PickedBackupFile?>();
  int cancelled = 0;
  @override
  Future<PickedBackupFile?> pick() => completion.future;
  @override
  Future<void> cancelPick() async {
    cancelled++;
    completion.complete(null);
  }
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('backup progress and recovery fit 320px at 200% dark=$dark', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final files = ReadingFile();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backupFileServiceProvider.overrideWithValue(files)],
          child: MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.scrollUntilVisible(find.text('백업 가져오기'), 300);
      await tester.ensureVisible(find.text('백업 가져오기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('백업 가져오기'));
      await tester.pump();
      await tester.pump();
      expect(find.text('파일 읽기 취소').hitTestable(), findsOneWidget);
      await tester.scrollUntilVisible(find.text('파일 읽기 취소'), 150);
      await tester.ensureVisible(find.text('파일 읽기 취소'));
      await tester.pump();
      expect(find.text('파일 읽기 취소').hitTestable(), findsOneWidget);
      expect(
        tester.getSize(find.widgetWithText(TextButton, '파일 읽기 취소')).height,
        greaterThanOrEqualTo(48),
      );
      files.completion.completeError(const FormatException('파일을 확인해 주세요'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('백업을 가져오지 못했어요').hitTestable(),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.text('다시 시도'), 150);
      await tester.ensureVisible(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('다시 시도').hitTestable(), findsOneWidget);
      expect(find.textContaining('기존 기록과 원본 파일은 그대로'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('전체 백업 내보내기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('전체 백업 내보내기'));
      await tester.pumpAndSettle();
      expect(
        ModalRoute.of(
          tester.element(find.byType(AlertDialog)),
        )!.transitionDuration,
        Duration.zero,
      );
      expect(find.text('취소').hitTestable(), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
    });
  }
  testWidgets('leaving settings cancels only the pending file read', (
    tester,
  ) async {
    final files = ReadingFile();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [backupFileServiceProvider.overrideWithValue(files)],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.scrollUntilVisible(find.text('백업 가져오기'), 300);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('백업 가져오기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('백업 가져오기'));
    await tester.pump();
    expect(find.text('파일 읽기 취소'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(files.cancelled, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('successful import refreshes history after leaving settings', (
    tester,
  ) async {
    late DelayedImport repo;
    await tester.runAsync(() async {
      ensureSqfliteFfi();
      repo = DelayedImport(await openAppDatabase(path: inMemoryDatabasePath));
    });
    addTearDown(() => tester.runAsync(repo.close));
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          backupFileServiceProvider.overrideWithValue(PickFile()),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: visible,
            builder: (_, shown, _) =>
                shown ? const SettingsScreen() : const Text('left'),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    await tester.scrollUntilVisible(find.text('백업 가져오기'), 300);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('백업 가져오기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('백업 가져오기'));
    await tester.pump();
    for (
      var i = 0;
      i < 200 && find.widgetWithText(FilledButton, '가져오기').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, '가져오기'));
    await tester.pump();
    expect(repo.started, isTrue);
    visible.value = false;
    await tester.pump();
    repo.completion.complete(
      const BackupImportResult(
        importedSessions: 1,
        skippedSessions: 0,
        importedSamples: 0,
        importedWindows: 0,
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(historyTickProvider), 1);
  });
}
