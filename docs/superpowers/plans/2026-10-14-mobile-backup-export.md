# 산보 모바일 백업 내보내기 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android/iOS의 지원되지 않는 save-location 호출을 시스템 파일 내보내기로 교체하고 실제 파일 왕복으로 MR-01을 검증한다.

**Architecture:** 기존 BackupFileService 계약을 유지한다. Dart는 기존 path_provider의 Caches 경로 아래 산보 전용 임시 파일을 준비하고, 작은 native handler가 사용자 선택 파일로 복사/내보낸다. 원본 SQLite와 백업 codec은 그대로 둔다.

**Tech Stack:** Flutter/Dart, 기존 path_provider/file_selector, Kotlin/Android Storage Access Framework, Swift/UIKit, JUnit/XCTest, integration_test.

**Spec:** [승인된 1차 설계](../specs/2026-10-13-measurement-consistency-and-backup-design.md). 승인일 2026-10-14. 실행은 현재 세션에서 직접 수행한다.

## Global Constraints

- `BackupFileService.save({required String fileName, required Uint8List bytes}) -> Future<String?>`를 유지한다. nonnull은 실제 외부 저장 완료, null은 사용자 취소, exception은 실패다.
- 기존 `pick`, import merge/중복 방지/rollback, SQLite v6, 전체 백업 v2를 유지한다.
- 새 제품 dependency와 저장소 권한을 추가하지 않는다. 시스템 picker에서 사용자가 목적지를 고른다.
- 입력 상한은 기존 `maxBackupBytes = 50 * 1024 * 1024`, native도 같은 52,428,800bytes다.
- 임시 root는 `getTemporaryDirectory()/sanbo_exports`. iOS path_provider2.6.0의 임시 API는 NSCachesDirectory이므로 Swift도 `.cachesDirectory`를 사용한다.
- channel은 `sanbo/backup_export`, method는 `save`, args는 `{sourcePath: String, fileName: String}`, result는 destination String/null이다.
- 파일 이름은 단일 basename이고 source의 실제 파일 이름과 같아야 한다. native export root는 신뢰하는 플랫폼 cache에서 계산하며 payload로 받지 않는다.
- 파일이 외부에 복사되고 stream이 close되거나 OS export callback이 끝난 뒤 응답한다. Dart가 먼저 임시 파일을 지우지 않는다.
- 작업은 현재 Codex 실행자가 수행하고 재위임하지 않는다.

## Review Focus

- 동일 이름이 이미 있거나 사용자가 picker를 취소했을 때 이전 파일을 지우지 않고 성공 안내도 하지 않는다. Task 1/3의 실제 파일 시나리오에서 확인한다.
- sourcePath의 `../`/symlink/다른 cache 폴더와 파일 이름의 slash/NUL을 거부한다. Task 1/2의 실제 filesystem validator tests로 검사한다.
- Activity/engine 재생성과 늦은 copy callback이 result를 두 번 반환하거나 source를 일찍 정리하지 않는다. Task 1/2에서 pending state를 분리하고 Task 3의 UI 시나리오로 확인한다.
- output open/write/close 실패를 완료로 오인하지 않는다. Task 1의 stream fault tests와 Task 3의 channel error/cleanup tests로 검사한다.
- cancel/error/동시 요청 시 산보가 만든 임시 폴더만 정리하고 기존 산책/다른 임시 파일은 남긴다. Task 3의 실제 임시 filesystem tests로 검사한다.

## 파일 구조와 고정 계약

| 파일 | 책임 |
|---|---|
| 새 `android/app/src/main/kotlin/com/sanbo/sanbo/BackupExportHandler.kt` | 입력 경계, 시스템 문서 생성, copy 완료와 pending result |
| `android/app/src/main/kotlin/com/sanbo/sanbo/MainActivity.kt` | handler/channel 등록과 해당 activity result 전달 |
| 새 `ios/Runner/BackupExportCoordinator.swift` | source 검증, picker delegate 소유와 완료/취소 |
| `ios/Runner/AppDelegate.swift` | implicit engine 등록과 presenter 제공 |
| `ios/Runner.xcodeproj/project.pbxproj` | 새 Swift 파일을 Runner sources/group에 등록 |
| `lib/platform/backup/backup_file_service.dart` | mobile/desktop 선택, temp file, channel, finally cleanup |
| 새 `test/platform/backup_file_service_test.dart` | actual Dart adapter의 filesystem/channel 경계 |
| 새 `integration_test/native_backup_export_e2e_test.dart` | 시스템 picker로 저장 후 기존 pick으로 재가져오기 |

오류 code는 `invalid_arguments`, `export_busy`, `export_unavailable`, `export_failed`,
`export_interrupted`로 제한한다. 메시지에는 원시 경로/백업 본문을 넣지 않는다.
Flutter 설정 화면은 기존 `저장 실패` 처리와 busy/finally를 재사용한다.

### Task 1: Android 시스템 문서 저장

**Files**
- Create: `android/app/src/main/kotlin/com/sanbo/sanbo/BackupExportHandler.kt`.
- Modify: `android/app/src/main/kotlin/com/sanbo/sanbo/MainActivity.kt`.
- Create: `android/app/src/test/kotlin/com/sanbo/sanbo/BackupExportContractTest.kt`.
- Existing regression: `NotificationIntentContractTest.kt`, `HealthConnectIntentContractTest.kt`.

**Interfaces**
- `validatedBackupExportSource(sourcePath: String, fileName: String, exportRoot: File): File` validates the channel/file boundary.
- `copyBackupExport(source: File, openOutput: () -> OutputStream): Unit` returns only after both streams close.
- `BackupExportHandler(activity: FlutterFragmentActivity)` exposes `attach(messenger: BinaryMessenger)`, `onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean`, `close()`.
- Request code4105 is unique; existing notification permission request4104 remains unchanged.

- [x] Step 1: 새 validator/stream 함수가 없는 상태에서 실패하는 JUnit 회귀를 작성한다.

```kotlin
@Test fun rejectsSourceOutsideExportRoot() {
    val root = java.nio.file.Files.createTempDirectory("sanbo-native-test").toFile()
    val outside = File(root.parentFile, root.name + "-outside.sanbo")
    try {
        outside.writeText("{}")
        try {
            validatedBackupExportSource(outside.path, outside.name, root)
            org.junit.Assert.fail("outside source must be rejected")
        } catch (_: IllegalArgumentException) { }
    } finally {
        outside.delete()
        root.deleteRecursively()
    }
}
```

valid source는`root/export-1/audit.sanbo`를 만들어 같은 File이 반환되는지 검사한다.
symlink가 root 밖을 가리키는 경우, missing file, slash/NUL name, 50MB 초과 파일도
거부하는 tests를 추가한다. 큰 테스트 파일은 RandomAccessFile.setLength를 사용해
52MB 데이터를 메모리로 만들지 않는다.

- [x] Step 2: 아래 close 실패를 성공으로 처리하지 않는 stream test를 추가한다.

```kotlin
@Test fun propagatesOutputCloseFailure() {
    val source = File.createTempFile("sanbo-copy-test", ".sanbo")
    try {
        source.writeText("{}")
        val output = object : java.io.ByteArrayOutputStream() {
            override fun close() { throw java.io.IOException("close failed") }
        }
        try {
            copyBackupExport(source) { output }
            org.junit.Assert.fail("close failure must not mean saved")
        } catch (_: java.io.IOException) { }
    } finally { source.delete() }
}
```

openOutput가 IOException을 던지는 경우, write fault, 성공 시 byte 동일 및 close
완료도 같은 실제 stream 경계로 검사한다.

- [x] Step 3: `android`에서 `./gradlew app:testDebugUnitTest --tests 'com.sanbo.sanbo.BackupExportContractTest'`를 실행해 RED를 확인하고 다음 validation/copy를 구현한다.

```kotlin
internal fun validatedBackupExportSource(
    sourcePath: String, fileName: String, exportRoot: File,
): File {
    require(fileName.isNotBlank() && fileName != "." && fileName != "..")
    require(!fileName.contains('/') && !fileName.contains('\\') && !fileName.contains('\u0000'))
    val root = exportRoot.canonicalFile
    val source = File(sourcePath).canonicalFile
    require(source.path.startsWith(root.path + File.separator))
    require(source.name == fileName && source.isFile)
    require(source.length() in 1..(50L * 1024 * 1024))
    return source
}

internal fun copyBackupExport(source: File, openOutput: () -> java.io.OutputStream) {
    openOutput().use { output -> source.inputStream().use { input -> input.copyTo(output) } }
}
```

- [x] Step 4: handler에서 `save`의 typed args를 검증하고 동시 pending은export_busy로
반환한다. 다음 Intent를 띄우고 native callback에 source/result를 보존한다.

```kotlin
val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
    addCategory(Intent.CATEGORY_OPENABLE)
    type = "application/octet-stream"
    putExtra(Intent.EXTRA_TITLE, fileName)
}
activity.startActivityForResult(intent, 4105)
```

미지원 picker/ActivityNotFoundException은export_unavailable이다. owned request4105만
처리한다. RESULT_CANCELED는null, RESULT_OK인데URI가 없으면export_failed다. 복사는
단일 ExecutorService에서 수행하고 UI thread에서 결과를 반환한다.

```kotlin
copyBackupExport(source) {
    activity.contentResolver.openOutputStream(uri, "w")
        ?: throw java.io.IOException("output unavailable")
}
```

pending operation을picker/copy 단계로 나눈다. `close()`는picker 단계에서 한 번만
export_interrupted를 반환한다. copy 중이면 interrupted flag를 세우고 copy/close가
끝난 뒤 실패를 반환해 Dart의source 정리가 먼저 실행되지 않게 한다. 늦은 결과는
operation identity를 비교해 이미 완료된 result에 다시 응답하지 않는다.

- [x] Step 5: MainActivity에서configureFlutterEngine에 새 handler를 등록한다. 기존
notification/Health channel과 onNewIntent는 유지한다. onActivityResult는 owned
result만 handler에 맡기고 나머지는super로 전달한다. onDestroy/새 engine 등록에서
이전 handler를 close한다. copy executor는 동작 종료 후shutdown한다.
- [x] Step 6: Android native unit tests 전체를 실행한다. Intent/picker의 실제 성공/취소와
Activity 재생성은Task3 native E2E에서 검사한다. pure helper 통과를 실제 UI 저장
성공으로 주장하지 않는다.
- [x] Step 7: `fix: Android 시스템 문서 저장으로 백업 내보내기`로 커밋한다.

### Task 2: iOS 파일 export와 delegate 수명

**Files**
- Create: `ios/Runner/BackupExportCoordinator.swift`.
- Modify: `ios/Runner/AppDelegate.swift`, `ios/Runner.xcodeproj/project.pbxproj`.
- Test: `ios/RunnerTests/RunnerTests.swift`.

**Interfaces**
- `validatedBackupExportSource(source: URL, fileName: String, exportRoot: URL) throws -> URL`.
- `BackupExportCoordinator(exportRoot: URL, presentPicker: @escaping (UIDocumentPickerViewController) -> Bool)` implements UIDocumentPickerDelegate/UIAdaptivePresentationControllerDelegate.
- It exposes `attach(messenger: FlutterBinaryMessenger)` and `close()`, owns a pending FlutterResult and picker strongly, and completes each operation once.
- Minimum iOS15.0 already permits `UIDocumentPickerViewController(forExporting:asCopy:)`; deployment target is not raised.

- [x] Step 1: 실제 임시 파일을 만드는 validator test를 RunnerTests에 추가하고 함수가 없어 실패하는지 확인한다.

```swift
func testBackupSourceMustStayInsideExportRoot() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("audit.sanbo")
  try Data("{}".utf8).write(to: source)
  XCTAssertEqual(try validatedBackupExportSource(
    source: source, fileName: "audit.sanbo", exportRoot: root),
    source.resolvingSymlinksInPath())
  XCTAssertThrowsError(try validatedBackupExportSource(
    source: source, fileName: "../audit.sanbo", exportRoot: root))
}
```

다른 root의 file, 바깥을 가리키는 symlink, missing file, 50MB 초과 sparse file을
같은 경계 test로 검사한다. helper는`FileManager.default.urls(for:.cachesDirectory,
in:.userDomainMask).first` 아래`sanbo_exports`가 product root임을 별도로 검증한다.
FileManager.temporaryDirectory를 product root로 쓰지 않는다.

- [x] Step 2: validator를 구현하고 PBXFileReference/PBXBuildFile/Runner group/
Runner Sources에 새 Swift 파일을 등록한다.

```swift
enum BackupExportValidationError: Error { case invalidSource }

func validatedBackupExportSource(
  source: URL, fileName: String, exportRoot: URL
) throws -> URL {
  let root = exportRoot.resolvingSymlinksInPath().standardizedFileURL
  let file = source.resolvingSymlinksInPath().standardizedFileURL
  let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
  guard !fileName.isEmpty, fileName != ".", fileName != "..",
        !fileName.contains("/"), !fileName.contains("\\"), !fileName.contains("\0"),
        file.path.hasPrefix(root.path + "/"), file.lastPathComponent == fileName,
        values.isRegularFile == true, let size = values.fileSize,
        size > 0, size <= 50 * 1024 * 1024 else {
    throw BackupExportValidationError.invalidSource
  }
  return file
}
```

- [x] Step 3: coordinator가 save 요청의 typed args, 검증한 URL과 pending 단일성을
확인한다. picker delegate를 self로 설정하고 강한 참조를 유지한다.

```swift
let picker = UIDocumentPickerViewController(forExporting: [source], asCopy: true)
picker.delegate = self
picker.presentationController?.delegate = self
```

presentPicker가 false면 export_unavailable을 반환한다. didPickDocumentsAt에서
목적지 URL을 받으면 URL.absoluteString을 반환하고 취소/interactive dismiss는
null로 처리한다. pending을 먼저 nil로 만든 뒤 callback을 완료해 중복 응답을
막는다. close는 picker dismiss가 끝난 뒤 export_interrupted를 반환해 OS가
source를 사용하는 동안 Dart finally가 파일을 지우지 않게 한다.

- [x] Step 4: AppDelegate의 implicit engine 등록에서 coordinator를 유지하고 channel을
attach한다. 현재 key UIWindowScene의 root와 최상위 presented controller를 찾아
window에 올라와 있을 때 picker를 표시한다.

```swift
let root = UIApplication.shared.connectedScenes
  .compactMap { $0 as? UIWindowScene }
  .flatMap { $0.windows }
  .first(where: { $0.isKeyWindow })?.rootViewController
```

이전 engine coordinator는 close한다. notification readiness와 SceneDelegate의
tap 처리는 유지하고 coordinator를 picker delegate 종료까지 보관한다.

- [x] Step 5: callback recorder를 주입한 presentPicker에서 picker를 보관해 실제
UIDocumentPickerDelegate 메서드를 호출한다. 성공/취소/중복 callback/presenter
부재의 응답 횟수를 검사하고 Task3의 simulator E2E에서 닫힘 순서와 파일 재읽기를
확인한다.
- [x] Step 6: `bash scripts/run_native_platform_tests.sh`로 XCTest와 기존 notification
회귀를 실행한다. 같은 revision에서 통과한 gate를 바로 반복하지 않는다.
- [x] Step 7: `fix: iOS 파일 내보내기로 전체 백업 저장`로 해당 파일만 커밋한다.

### Task 3: Flutter 실제 저장 어댑터와 파일 왕복

**Files**
- Modify: `lib/platform/backup/backup_file_service.dart`.
- Create: `test/platform/backup_file_service_test.dart`, `integration_test/native_backup_export_e2e_test.dart`.
- Existing regression: `test/features/ux_settings_safety_test.dart`, `test/data/walk_backup_test.dart`.
- Read: `lib/features/settings/settings_screen.dart`의 `_exportBackup`와 `test/helpers/route_exclusion_fixture.dart`.

**Interfaces**
- PlatformBackupFileService constructor allows `TargetPlatform? platform`, `Future<Directory> Function()? temporaryDirectory`, `MethodChannel? channel` for actual-adapter tests. Production platform comes from the OS, temporaryDirectory defaults to existing getTemporaryDirectory, channel defaults to sanbo/backup_export.
- Android/iOS use native save, desktop uses existing file_selector save. Existing provider creates the default service; no new service interface.
- Request source is `Caches/sanbo_exports/export-<unique>/fileName`. Unique operation directory prevents concurrent export files colliding.
- Integration fixture produces `seedNativeBackupWalk(WalkRepository repo) -> Future<String>` and uses the native sqflite factory, never host FFI initialization.

- [x] Step 1: 실제서비스에 Android/iOS platform과임시Directory, mock channel을 주입한다.
fake BackupFileService를 만들지 않고 channel에서 실제source 파일을 읽는 아래 test를
추가한다. 클래스의 새 constructor parameter 부재로 RED를 확인한다.

```dart
test('mobile save hands a real file to native and cleans it afterwards', () async {
  final temp = await Directory.systemTemp.createTemp('sanbo-save-test-');
  addTearDown(() => temp.delete(recursive: true));
  const channel = MethodChannel('sanbo/backup_export');
  String? exportedSource;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    expect(call.method, 'save');
    final args = call.arguments as Map;
    exportedSource = args['sourcePath'] as String;
    expect(args['fileName'], 'audit.sanbo');
    expect(await File(exportedSource!).readAsBytes(), [123, 125]);
    expect(args.values.whereType<Uint8List>(), isEmpty);
    return 'content://test/saved-backup';
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  final service = PlatformBackupFileService(
    platform: TargetPlatform.android, temporaryDirectory: () async => temp,
    channel: channel,
  );
  final result = await service.save(
    fileName: 'audit.sanbo', bytes: Uint8List.fromList([123, 125]),
  );
  expect(result, 'content://test/saved-backup');
  expect(await File(exportedSource!).exists(), isFalse);
});
```

imports는 dart:io/dart:typed_data, Flutter foundation/services/test, 실제 서비스다.
같은 어댑터에서 iOS, native null 취소, PlatformException, pending Completer 동안
source 유지, 동시 저장의 서로 다른 source, 다른 temp file 보존, 50MB 초과,
잘못된 basename, 빈 destination을 각각 검사한다.

- [x] Step 2: 파일/경로/typed message 경계를 아래 코드로 구현한다. desktop branch는
기존 getSaveLocation/saveTo를 유지한다.

```dart
final cache = await _temporaryDirectory();
final root = await Directory(p.join(cache.path, 'sanbo_exports')).create(recursive: true);
final operation = await root.createTemp('export-');
try {
  final source = File(p.join(operation.path, fileName));
  await source.writeAsBytes(bytes, flush: true);
  final destination = await _channel.invokeMethod<String>('save', {
    'sourcePath': source.path, 'fileName': fileName,
  });
  if (destination != null && destination.isEmpty) {
    throw PlatformException(code: 'export_failed');
  }
  return destination;
} finally {
  await operation.delete(recursive: true);
}
```

임시파일 준비 전에 bytes상한, basename/slash/NUL을 검사한다. 이전 프로세스가 남긴
`sanbo_exports/export-` 디렉터리는24시간보다 오래된 것만 다음save 전에 정리한다.
현재/최근export와다른cache 파일은 지우지 않는다. Native callback/stream 종료까지
promise를 기다리고 cleanup 실패가 원래 native 오류를 감추지 않도록 오류 우선순위를
명시한다. 디렉터리가 이미 없으면 cleanup은 성공으로 취급한다.

- [x] Step 3: `flutter test --no-pub --concurrency=1 test/platform/backup_file_service_test.dart test/features/ux_settings_safety_test.dart test/data/walk_backup_test.dart`를 실행한다. 설정 busy/cancel/error/성공 문구는 기존구조로 검증하며 native지원완료를fake만으로 주장하지 않는다.

- [ ] Step 4: integration_test에서는 host용 FFI DB helper를 호출하지 않는다.
기존 native_location_e2e_test처럼 `WalkRepository.open(path:)`와 실제 sqflite를
사용해 서로 다른 두 임시 DB를 연다. route_exclusion_fixture의 seed 데이터 부분을
로컬 함수로 정의하고 session ID를 반환한다. 다음 실제 repository fixture로
원본, 장소, 확인 라벨과 제외 기록을 포함한다.

```dart
Future<String> seedNativeBackupWalk(WalkRepository repo) async {
  final t = DateTime.utc(2026, 8, 21);
  final session = await repo.startSession(startedAt: t);
  final samples = [for (var seconds = 0; seconds <= 120; seconds += 20)
    LocationSample(timestamp: t.add(Duration(seconds: seconds)),
      latitude: 37.5, longitude: 127 + seconds * 0.00001,
      accuracyM: 5, speedMps: 1)];
  final end = t.add(const Duration(minutes: 2));
  final pipeline = SessionPipeline();
  final result = pipeline.process(session: session, rawSamples: samples, endedAt: end);
  final m = result.metrics;
  await repo.finalizeSession(session: session, samples: result.filteredSamples,
    windows: result.windows, endedAt: end, totalDistanceM: m.totalDistanceM,
    durationS: m.durationS, movingTimeS: m.movingTimeS,
    stationaryTimeS: m.stationaryTimeS, avgSpeedMps: m.avgSpeedMps,
    validSampleCount: m.validSampleCount, medianAccuracyM: m.medianAccuracyM);
  final windows = await repo.getWindows(session.id);
  await repo.rememberPlaceForWindows(sessionId: session.id,
    windowStarts: [windows.first.windowStart], latitude: 37.5,
    longitude: 127, name: '출발 장소');
  await repo.updateWindowUserLabel(sessionId: session.id,
    windowStart: windows.first.windowStart, userLabel: ActivityLabel.walkSteady,
    note: '확인한 산책', confirmed: true);
  await repo.updateWindowUserLabel(sessionId: session.id,
    windowStart: windows.last.windowStart, userLabel: ActivityLabel.strollSlow,
    note: '마지막 구간', confirmed: true);
  final segments = pipeline.segmentMerger.merge(await repo.getWindows(session.id),
    sessionId: session.id, sessionStart: t, sessionEnd: end);
  await repo.excludeRouteSegment(sessionId: session.id, segment: segments.last);
  return session.id;
}
```

source/target는 `WalkRepository.open(path:)`로 서로 다른 전용 임시 DB에 만들고
테스트 종료 시 close한다. `raw = await source.createBackupJson()`을 캡처한 뒤
실제 서비스를 호출한다. presenter와 plugin registrant는 기존 native integration
binding 패턴을 사용하며 백업 테스트에서는 GPS를 시작하지 않는다.

native picker는 CUA로 local Downloads/On My iPhone에 저장한다. 기존 pick으로
방금 저장한 파일을 다시 선택하고 decode/import를 실행해 아래 불변식을 검사한다.

```dart
expect(picked, isNotNull);
final restoredFile = picked!;
expect(restoredFile.bytes, utf8.encode(raw));
final imported = await target.importBackupJson(utf8.decode(restoredFile.bytes));
expect(imported.importedSessions, 1);
expect((await target.getSamples(sessionId)).length,
    (await source.getSamples(sessionId)).length);
final originalWindows = await source.getWindows(sessionId);
final restoredWindows = await target.getWindows(sessionId);
expect(restoredWindows.map((w) => (w.windowStart, w.userLabel, w.userNote,
  w.userConfirmed, w.placeName, w.userExclusionId)),
  originalWindows.map((w) => (w.windowStart, w.userLabel, w.userNote,
    w.userConfirmed, w.placeName, w.userExclusionId)));
final duplicate = await target.importBackupJson(utf8.decode(restoredFile.bytes));
expect(duplicate.importedSessions, 0);
expect(duplicate.skippedSessions, 1);
```

source/target의 `getRouteExclusions(sessionId)`도 ID/시작/끝/이유가 같은지 비교한다.
rollback과 손상 파일 거부는 기존 walk_backup_test를 함께 실행해 유지한다.

테스트는 영속 데이터가 없는 전용 기기에서 실행하고 기존 사용자 DB를 clear하지
않는다. save 취소 후 null을 검사하는 scenario를 별도로 두고 동일 이름 두 번
저장 시 이전 파일이 남는지도 실제 picker에서 확인한다.

- [x] Step 5: Android emulator와 iOS simulator의 실제 picker로 native integration test를
각각 실행한다. `adb devices`/`xcrun simctl list devices available`로 전용 기기를
조회하고 선택한 실제 ID를 `backup_device_id`에 넣어 아래 명령을 실행한다.

```bash
flutter test --no-pub integration_test/native_backup_export_e2e_test.dart -d "$backup_device_id"
```

실제 값/OS/저장 위치/파일 재가져오기/취소/재생성 결과를 검증 문서에 남긴다.
물리 기기 결과로 승격하지 않는다.
- [x] Step 6: `fix: 모바일 백업 저장 어댑터와 파일 왕복 복구`로 커밋한다.

## 이 계획의 종료 증거

- 외부에 저장한 실제 파일을 다시 읽어 원래 백업 bytes와 일치하고 import가 완료돼야 한다.
- Android stream close와 iOS picker 완료/취소/실패의 실제 결과를 구분한다.
- source cleanup, 동시 pending, lifecycle 늦은 callback, 설정 busy 회귀가 통과한다.
- Android/iOS native build와 Flutter 검증의 구체적인 revision/log를 [통합 계획](2026-10-14-maintenance-stage1.md)에 남긴다.

근거는 [Android 문서 생성 계약](https://developer.android.com/training/data-storage/shared/documents-files),
[iOS export initializer](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init(forexporting:ascopy:)),
설치된 path_provider_foundation 2.6.0 및 file_selector_ios 0.5.3+5 코드다. Android
ACTION_CREATE_DOCUMENT는 기존 파일을 덮어쓰지 않고 이름을 조정하며 별도 저장소 권한을
요구하지 않는다. 동일 이름 동작도 실제 E2E에서 확인한다.

현재 Task 3 구현과 host 26개 테스트, 전체 품질/native gate는 통과했습니다.
iOS 실제 picker는 Mac 접근이 복구된 뒤 같은 소스로 재시도해 취소/저장/복원과
동일 이름 두 파일 보존이 통과했습니다. Android도2026-10-15 대체 UI 자동화 승인 뒤
전용 API34 emulator의 실제 picker E2E1개가1분15초에 통과했습니다. 취소/저장/
복원/중복 ID 건너뛰기/동일 이름 두 파일 재읽기를 확인해 Task3 검증을 완료했습니다.
[검증 기록](../verification/2026-10-14-maintenance-stage1.md)에 상태를 남겼습니다.
