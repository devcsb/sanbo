import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/pipeline/route_partitioner.dart';
import 'package:sanbo/domain/services/session_export.dart';
import 'package:sanbo/features/session_detail/session_detail_screen.dart';
import 'package:sanbo/features/session_detail/session_week_provider.dart';
import 'package:sanbo/platform/backup/backup_file_service.dart';

class Files implements BackupFileService {
  Files(this.outcome);
  final String outcome;
  int calls = 0;
  String? name;
  Uint8List? bytes;
  @override
  Future<void> cancelPick() async {}

  @override
  Future<PickedBackupFile?> pick() async => null;
  @override
  Future<String?> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    calls++;
    name = fileName;
    this.bytes = bytes;
    if (outcome == 'failure') throw PlatformException(code: 'export_failed');
    return outcome == 'cancelled' ? null : 'saved';
  }
}

final session = WalkSession(
  id: 'private',
  startedAt: DateTime.utc(2026, 11, 7),
  endedAt: DateTime.utc(2026, 11, 7, 0, 1),
  timezone: 'Asia/Seoul',
  trackingMode: TrackingMode.balanced,
  status: SessionStatus.completed,
  totalDistanceM: 100,
  durationS: 60,
  movingTimeS: 60,
  notes: 'PRIVATE_NOTE',
);
void main() {
  setUpAll(() => initializeDateFormatting('ko'));
  test('default share contains metrics but no private notes', () {
    final text = const SessionExport().humanSummary(session: session);
    expect(text, isNot(contains('PRIVATE_NOTE')));
    expect(text, contains('0.10 km'));
  });
  for (final outcome in ['saved', 'cancelled', 'failure']) {
    testWidgets('raw export $outcome preserves privacy and reports its outcome', (
      tester,
    ) async {
      final files = Files(outcome);
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final samples = [
        LocationSample(
          timestamp: session.startedAt,
          latitude: 37.5,
          longitude: 127,
        ),
      ];
      final data = SessionDetailData(
        session: session,
        samples: samples,
        windows: const [],
        exclusions: const [],
        route: RoutePartitioner.partition(
          samples: samples,
          exclusions: const [],
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionDetailProvider.overrideWith((ref, id) async => data),
            sessionWeekSummaryProvider.overrideWith((ref, id) async => null),
            backupFileServiceProvider.overrideWithValue(files),
          ],
          child: const MaterialApp(
            builder: _reducedMotion,
            home: SessionDetailScreen(sessionId: 'private'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('원본 파일 저장'));
      await tester.pumpAndSettle();
      expect(
        ModalRoute.of(
          tester.element(find.byType(AlertDialog)),
        )!.transitionDuration,
        Duration.zero,
      );
      expect(files.calls, 0);
      expect(clipboard, isNull);
      expect(find.textContaining('암호화'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(files.calls, 0);
      await tester.tap(find.byTooltip('원본 파일 저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '파일 저장'));
      await tester.pump();
      // compute uses a real isolate, so allow its I/O completion outside fake time.
      for (var i = 0; i < 200 && files.calls == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(files.calls, 1);
      expect(files.name, endsWith('.ndjson'));
      expect(utf8.decode(files.bytes!), contains('PRIVATE_NOTE'));
      expect(utf8.decode(files.bytes!), contains('"lat":37.5'));
      expect(clipboard, isNull);
      expect(
        find.textContaining('원본 파일을 저장했어요.'),
        outcome == 'saved' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('파일을 저장하지 못했어요. 다시 시도해 주세요.'),
        outcome == 'failure' ? findsOneWidget : findsNothing,
      );
      expect(find.byTooltip('원본 파일 저장'), findsOneWidget);
    });
  }
}

Widget _reducedMotion(BuildContext context, Widget? child) => MediaQuery(
  data: MediaQuery.of(context).copyWith(disableAnimations: true),
  child: child!,
);
