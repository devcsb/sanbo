import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';
import 'package:sanbo/platform/backup/backup_file_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native backup save, cancellation and duplicate-name round trip',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp('sanbo-native-backup-');
      final source = await WalkRepository.open(path: '${dir.path}/source.db');
      final target = await WalkRepository.open(path: '${dir.path}/target.db');
      addTearDown(() async {
        await source.close();
        await target.close();
        await dir.delete(recursive: true);
      });
      Future<void> phase(String text) async {
        debugPrint('SANBO_BACKUP_E2E: $text');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(title: const Text('백업 검증')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(text),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      final sessionId = await seedNativeBackupWalk(source);
      final raw = await source.createBackupJson(
        exportedAt: DateTime.utc(2026, 10, 14),
      );
      final rawSecond = await source.createBackupJson(
        exportedAt: DateTime.utc(2026, 10, 14, 1),
      );
      final service = PlatformBackupFileService();
      final fileName =
          'sanbo-e2e-${DateTime.now().microsecondsSinceEpoch}.sanbo';
      await phase('취소 검증: 저장 화면에서 취소해 주세요.');
      final cancelled = service.save(
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(raw)),
      );
      await tester.pump();
      expect(await cancelled, isNull);
      await phase('첫 번째 백업 저장: $fileName');
      final save = service.save(
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(raw)),
      );
      await tester.pump();
      final destination = await save;
      expect(destination, isNotNull);
      debugPrint('SANBO_BACKUP_E2E: saved destination=$destination');
      await phase('첫 번째 백업을 선택해 주세요: $fileName');
      final pick = service.pick();
      await tester.pump();
      final picked = await pick;
      expect(picked, isNotNull);
      final restoredFile = picked!;
      expect(restoredFile.bytes, utf8.encode(raw));
      final imported = await target.importBackupJson(
        utf8.decode(restoredFile.bytes),
      );
      expect(imported.importedSessions, 1);
      expect((await target.getSamples(sessionId)).length, 7);
      final originalWindows = await source.getWindows(sessionId);
      final restoredWindows = await target.getWindows(sessionId);
      expect(
        restoredWindows.map(
          (w) => (
            w.windowStart,
            w.userLabel,
            w.userNote,
            w.userConfirmed,
            w.placeName,
            w.userExclusionId,
          ),
        ),
        originalWindows.map(
          (w) => (
            w.windowStart,
            w.userLabel,
            w.userNote,
            w.userConfirmed,
            w.placeName,
            w.userExclusionId,
          ),
        ),
      );
      final originalExclusions = await source.getRouteExclusions(sessionId);
      final restoredExclusions = await target.getRouteExclusions(sessionId);
      expect(
        restoredExclusions.map((e) => (e.id, e.startAt, e.endAt, e.reason)),
        originalExclusions.map((e) => (e.id, e.startAt, e.endAt, e.reason)),
      );
      final duplicate = await target.importBackupJson(
        utf8.decode(restoredFile.bytes),
      );
      expect(duplicate.importedSessions, 0);
      expect(duplicate.skippedSessions, 1);
      await phase('같은 이름으로 두 번째 백업 저장: 기존 파일을 보존해 주세요.');
      final again = service.save(
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(rawSecond)),
      );
      await tester.pump();
      final secondDestination = await again;
      expect(secondDestination, isNotNull);
      expect(secondDestination, isNot(destination));
      await phase('첫 번째 파일을 다시 선택해 주세요: 이전 내용이 남아 있어야 해요.');
      final firstAgainFuture = service.pick();
      await tester.pump();
      final firstAgain = await firstAgainFuture;
      expect(firstAgain?.bytes, utf8.encode(raw));
      await phase('두 번째로 저장한 파일을 선택해 주세요.');
      final secondPickFuture = service.pick();
      await tester.pump();
      final secondPick = await secondPickFuture;
      expect(secondPick?.bytes, utf8.encode(rawSecond));
      await phase('검증 통과: 저장, 취소, 복원, 중복 이름 보존을 확인했어요.');
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<String> seedNativeBackupWalk(WalkRepository repo) async {
  final t = DateTime.utc(2026, 8, 21);
  final session = await repo.startSession(startedAt: t);
  final samples = [
    for (var seconds = 0; seconds <= 120; seconds += 20)
      LocationSample(
        timestamp: t.add(Duration(seconds: seconds)),
        latitude: 37.5,
        longitude: 127 + seconds * 0.00001,
        accuracyM: 5,
        speedMps: 1,
      ),
  ];
  final end = t.add(const Duration(minutes: 2));
  final pipeline = SessionPipeline();
  final result = pipeline.process(
    session: session,
    rawSamples: samples,
    endedAt: end,
  );
  final m = result.metrics;
  await repo.finalizeSession(
    session: session,
    samples: result.filteredSamples,
    windows: result.windows,
    endedAt: end,
    totalDistanceM: m.totalDistanceM,
    durationS: m.durationS,
    movingTimeS: m.movingTimeS,
    stationaryTimeS: m.stationaryTimeS,
    avgSpeedMps: m.avgSpeedMps,
    validSampleCount: m.validSampleCount,
    medianAccuracyM: m.medianAccuracyM,
  );
  final windows = await repo.getWindows(session.id);
  await repo.rememberPlaceForWindows(
    sessionId: session.id,
    windowStarts: [windows.first.windowStart],
    latitude: 37.5,
    longitude: 127,
    name: '출발 장소',
  );
  await repo.updateWindowUserLabel(
    sessionId: session.id,
    windowStart: windows.first.windowStart,
    userLabel: ActivityLabel.walkSteady,
    note: '확인한 산책',
    confirmed: true,
  );
  await repo.updateWindowUserLabel(
    sessionId: session.id,
    windowStart: windows.last.windowStart,
    userLabel: ActivityLabel.strollSlow,
    note: '마지막 구간',
    confirmed: true,
  );
  final segments = pipeline.segmentMerger.merge(
    await repo.getWindows(session.id),
    sessionId: session.id,
    sessionStart: t,
    sessionEnd: end,
  );
  await repo.excludeRouteSegment(sessionId: session.id, segment: segments.last);
  return session.id;
}
