# 산보 CARTO 배경 지도 복구 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 승인된 MR-17 설계대로 CARTO 인증을 연결하고 실패 시 기록/경로/재생을 유지하며, 실제 지도와 새 서명 후보를 검증한다.

**Architecture:** 기존 RouteMap, flutter_map7의 raster renderer와 CARTO Voyager를 유지한다. 환경 키로 URL을 만들고 기존 http Client를 감싼 작은 전용 client에서 외부 실패를 키 없는 오류로 변환한다. RouteMap이 실패 상태와 provider 수명을 관리하고 release gate가 비공개 임시 Dart define 파일을 빌드에 전달한다.

**Tech Stack:** Flutter3.47.1/Dart3.13.1, flutter_map7.0.2, 기존 http1.2.2 이상, Python3 stdlib, Bash, Android/iOS.

**Spec:** [배경 지도 복구 설계](../specs/2026-10-14-basemap-service-restoration-design.md). 사용자 승인 2026-10-15, 이 세션 직접 실행 방식을 유지한다. 작성된 구현 계획도2026-10-15 승인받았다.

## Global Constraints

- Codex 실행자가 직접 구현하며 재위임하지 않는다. 기존 검토 브랜치와 사용자 변경을 보존한다.
- 기존 CARTO, raster renderer, 출처/개인정보 안내를 유지한다. 다른 지도 공급자로 자동 전환하지 않는다.
- SQLite v6, 백업/export v2, 거리/속도 계산, 기존 공개 v0.9.1을 변경하지 않는다.
- 키는 `CARTO_BASEMAP_KEY`이며 빌드 시 Dart define으로 전달한다. 키 값이나 키가 든 URL을 저장소/도구 출력/오류 로그에 남기지 않는다.
- 키 미설정이면 익명 CARTO 요청을 하지 않는다. 실패 문구는 `배경 지도를 불러올 수 없어요. 산책 경로와 기록은 그대로 볼 수 있어요.`다.
- 인증/네트워크 실패 시 경로 선분, 선택 구간, 재생 cursor, 종료/시작 marker를 유지한다. 자동 반복 재시도를 만들지 않는다.
- 키 발급, 사용 유형과 약관 동의는 사용자가 진행한다. 소스와 클라이언트에 들어가는 키를 서버 비밀 자격 증명으로 취급하지 않는다.
- 후보는 아직 공개하지 않은 `0.9.2+16`이다. 제품 변경 후 build SHA와 서명 후보를 새로 연결한다. 기존 479개/16개/11개 결과를 새 제품 검증으로 대신하지 않는다.
- 여러 파일 변경의 독립 교차 검토는 PR 사용자 검토로 받는다. 공개 게시 전에는 구체적인 검증 산출물로 확인받는다.

## Review Focus

- 잘못된 키도 HTTP200 PNG일 수 있다. 2026-10-15 합성 invalid 키에서 ETag `"wm-da89c20e77c1-light"`, 2049bytes 안내 이미지를 확인했다. Task1에서 실제 안내 응답 fixture와 정상 PNG를 구분하고 Task3에서 실제 도로/지명을 확인한다.
- http/이미지 오류에 URL이 포함될 수 있다. Task1은 원래 오류에 키가 있어도 상수 오류로 바꾸고 Task2는 debugPrint/FlutterError에 실제 키 대신 test key조차 남지 않는지 검사한다.
- 늦게 끝난 이전 요청이 새 지도나 닫힌 화면을 실패로 만들면 안 된다. Task2에서 configuration generation과 mounted를 검사하고 실제 지연 응답으로 회귀를 고정한다.
- 재생의 잦은 rebuild마다 client나 요청을 새로 만들면 안 된다. Task2에서 같은 설정의 provider 재사용, 실패 latch, key/offline 변경 시 새 provider와 이전 client 종료를 검사한다.
- 키 없는 디버그/CI와 의도적 offlinePreview는 외부 요청 없이 동작해야 한다. Task2에서 요청 수0과 기존 geometry를 확인하고 Task3은 release만 키를 필수로 검사한다.

## 파일과 책임

| 파일 | 책임 |
|---|---|
| `lib/shared/widgets/carto_basemap.dart` 신규 | CARTO URL 구성, 응답 경계와 오류의 안전한 변환 |
| `lib/shared/widgets/carto_tile_provider.dart` 신규 | SDK 진단에 키가 든 URL을 넘기지 않는 tile/image provider, 실패 cache 정리 |
| `lib/shared/widgets/route_map.dart` | 지도 배경 실패 상태와 provider 수명. 기존 geometry/rendering 유지 |
| `test/shared/carto_basemap_test.dart` 신규 | 실제 Client 경계의 URL/status/stream/안내 타일 검증 |
| `test/widget/route_map_test.dart` | 실패/늦은 응답/geometry/로그/작은 화면 회귀 |
| `test/fixtures/carto-api-key-required.png` 신규 | 확인한 공개 안내 PNG, 2049bytes. 실제 키 없음 |
| `scripts/prepare_carto_defines.py` 신규 | 환경 키를 exclusive/0600 JSON 파일로 준비 |
| `scripts/run_quality_loop.sh` | release 키 필수 검사와 define 파일 전달/정리 |
| `test/scripts/carto_release_config_test.dart` 신규 | 환경/파일 생성 경계와 release 키 누락 조기 실패 |
| `docs/release/2026-10-14-maintenance-stage1-release.md` 등 | 실제 build/지도/파일/업데이트 결과와 공개 전 상태 |

### Task 1: 인증 URL과 CARTO HTTP 경계

**Files**
- Create: `lib/shared/widgets/carto_basemap.dart`, `test/shared/carto_basemap_test.dart`, `test/fixtures/carto-api-key-required.png`.

**Interfaces**
- `const cartoBaseTileUrlTemplate`은 기존 인증 없는 URL 문자열이다.
- `String? cartoTileUrlTemplate(String key)`는 trim 후 빈 값이면 null, 아니면 base URL 뒤에 URL-encoded key query를 붙인다. `{s}/{z}/{x}/{y}` placeholder를 인코딩하지 않는다.
- `CartoTileClient extends http.BaseClient`는 `CartoTileClient(http.Client delegate, {VoidCallback? onAuthenticationNotice})`로 생성하고 delegate를 소유한다. `send(http.BaseRequest)`는 buffered StreamedResponse를 반환하고 `close()`는 delegate를 닫는다. 확인된 HTTP200 안내는 callback으로 알리며 공급자 안내 이미지는 보존한다.
- `CartoBasemapUnavailable implements Exception`의 toString은 `배경 지도 요청 실패`다. 원래 예외/URL/key를 포함하지 않는다.

- [x] Step1: URL과 실제 HTTP 경계 테스트를 추가한다. 실제 키 대신 다음 고정 문자열을 사용한다.

```dart
test('key is encoded without changing tile placeholders', () {
  expect(cartoTileUrlTemplate('  '), isNull);
  final url = cartoTileUrlTemplate('a&b?x=+')!;
  expect(url, startsWith(cartoBaseTileUrlTemplate));
  expect(url, endsWith('?key=a%26b%3Fx%3D%2B'));
});

test('HTTP200 authentication notice remains visible and reports status', () async {
  final notice = File('test/fixtures/carto-api-key-required.png').readAsBytesSync();
  var reported = 0;
  final client = CartoTileClient(MockClient((_) async => http.Response.bytes(
    notice, 200, headers: {'etag': '"wm-da89c20e77c1-light"'},
  )), onAuthenticationNotice: () => reported++);
  addTearDown(client.close);
  final response = await client.get(Uri.parse('https://a.basemaps.cartocdn.com/test?key=audit-test-key'));
  expect(response.bodyBytes, notice);
  expect(reported, 1);
});
```

imports는 dart:io, flutter_test, 기존 http/http.dart 및 http/testing.dart와 새 helper다.
fixture는 이미 저장한 `.superpowers/sdd/2026-10-14-maintenance-stage1/carto-invalid-key-response.bin`을 복사하고 PNG signature/크기/실제 안내 이미지를 대조한다.

- [x] Step2: `flutter test --no-pub test/shared/carto_basemap_test.dart`의 새 symbol 부재 RED를 확인한다.
- [x] Step3: URL과 전용 client를 구현한다. 기존 `http.Response.fromStream`으로 body를 한 번 모아 stream 오류도 이 경계에서 변환한다. 이후 renderer에는 같은 bytes를 전달하며 이미지 decode를 중복 수행하지 않는다.

```dart
String? cartoTileUrlTemplate(String key) {
  final value = key.trim();
  return value.isEmpty
      ? null
      : '$cartoBaseTileUrlTemplate?key=${Uri.encodeQueryComponent(value)}';
}

@override
Future<http.StreamedResponse> send(http.BaseRequest request) async {
  try {
    final response = await (() async {
      final stream = await _delegate.send(request);
      return http.Response.fromStream(stream);
    })().timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const CartoBasemapUnavailable();
    }
    if (response.headers['etag'] == '"wm-da89c20e77c1-light"') {
      onAuthenticationNotice?.call();
    }
    return http.StreamedResponse(
      Stream.value(response.bodyBytes), response.statusCode,
      headers: response.headers,
    );
  } catch (_) {
    throw const CartoBasemapUnavailable();
  }
}
```

15초는 단일 tile의 전체 요청/읽기 상한이며 route/GPS 시간 계약과 무관하다. 현재 안내 ETag를 인식하는 이유와 공급자 응답 변경 시 실제 지도 게이트로 다시 확인할 필요를 주석으로 남긴다. 응답 body를 잠깐 모으는 이유도 stream 오류가 원본 URL을 노출하지 않도록 경계를 닫기 위해서다.

- [x] Step4: 정상 PNG200은 bytes/headers가 보존되고, 401/403/429/500, URL을 포함한 transport 오류, body stream 실패와 15초 초과에서 상수 오류가 되는 테스트를 더한다. 시간 상한은 fake_async에 새 의존하지 않고 Flutter test의 fake clock/timer를 사용한다. close 호출도 기록한다.
- [x] Step5: 해당 focused test를 통과시키고 위 파일만 `fix: CARTO 인증 요청과 지도 오류 경계 추가`로 커밋한다.

### Task 2: RouteMap의 배경 실패 표시와 수명

**Files**
- Modify: `lib/shared/widgets/route_map.dart`, `test/widget/route_map_test.dart`.
- Existing regression: `test/shared/route_map_geometry_test.dart`, `test/domain/route_playback_test.dart`.

**Interfaces**
- 기존 RouteMap named parameter와 const 사용을 유지한다.
- `String basemapKey = const String.fromEnvironment('CARTO_BASEMAP_KEY')`, `http.Client Function()? tileHttpClientFactory`를 optional named parameter로 추가한다. factory는 테스트에서 실제 HTTP 경계를 주입하기 위한 것이며 production은 기존 http.Client를 만든다.
- `RouteMap.tileUrlTemplate`은 기존 public base URL을 유지한다. 실제 TileLayer URL만 Task1 helper로 구성한다.
- RouteMap은 StatefulWidget으로 바꾸며 provider와 실패/안내 상태, 예약 여부와 configuration generation만 배경 상태로 갖는다. geometry와 playback의 계산/캐시는 기존 그대로다. 공급자의 HTTP200 안내 타일은 지우지 않고 앱 안내와 함께 표시한다.

- [x] Step1: 키 없는 지도에서 HTTP 요청0, 실패 안내, 원래 polyline/selection/replay marker를 검증하는 새 test를 쓴다. 기존 offlinePreview 세 test는 같은 결과를 유지하며 의도적 offlinePreview에는 실패 안내를 덧붙이지 않는다.

```dart
var requests = 0;
await tester.pumpWidget(MaterialApp(home: Scaffold(body: RouteMap(
  basemapKey: '',
  tileHttpClientFactory: () => MockClient((_) async {
    requests++;
    return http.Response('', 500);
  }),
  fragments: const [[(lat:37.5, lon:127), (lat:37.501, lon:127)]],
  currentPoint: (lat:37.501, lon:127),
))));
await tester.pump();
expect(requests, 0);
expect(find.byType(TileLayer), findsNothing);
expect(find.byType(PolylineLayer), findsOneWidget);
expect(find.text('배경 지도를 불러올 수 없어요. 산책 경로와 기록은 그대로 볼 수 있어요.'), findsOneWidget);
```

- [x] Step2: `flutter test --no-pub test/widget/route_map_test.dart`의 새 parameter/기능 부재 RED를 확인한다.
- [x] Step3: State가 같은 설정의 NetworkTileProvider를 재사용한다. `CartoTileClient`를 전달하고 decoder 오류까지 기존 TileLayer.errorTileCallback에서 잡는다. Client가 상수 오류로 바꾸므로 flutter_map7의 debugPrint가 원래 URL을 출력하지 않게 한다. `silenceExceptions:true`는 callback을 없애므로 사용하지 않는다.

```dart
final generation = _basemapGeneration;
TileLayer(
  key: ValueKey<int>(generation),
  urlTemplate: cartoTileUrlTemplate(widget.basemapKey),
  tileProvider: _tileProvider ??= NetworkTileProvider(
    httpClient: CartoTileClient((widget.tileHttpClientFactory ?? http.Client)(),
      onAuthenticationNotice: () => _onAuthenticationNotice(generation)),
  ),
  userAgentPackageName: 'com.sanbo.sanbo',
  maxZoom: 19,
  subdomains: const ['a','b','c','d'],
  errorTileCallback: (_, __, ___) => _onBasemapError(generation),
)
```

키 누락/offline/HTTP·네트워크·codec 실패 시 ColoredMapBackground를 사용하고 기존 geometry layer는 모두 유지한다. 공급자의 HTTP200 안내 이미지는 그대로 보존한다. 앱의 실패 안내는 맵 아래의 별도 theme surface 영역에 같은 문구로 표시해 공급자 notice/경로/marker를 덮지 않는다. 320dp/2배 글자에서도 wrap하고 재생 버튼/slider를 덮지 않는다. 지도 geometry의 기존 height는 그대로다.

- [x] Step4: error callback에서는 현재 generation, mounted, failed/scheduled를 확인하고 addPostFrameCallback에서 한 번만 실패 상태로 전환한다. TileLayer가 제거될 때 기존 provider.dispose가 client를 닫는다. State가 이 client를 다시 사용하지 않는다. 키/offline/factory가 바뀌면 generation을 증가시키고 provider/실패 상태를 초기화한다. 키 문자열을 Widget Key나 오류 텍스트에 넣지 않는다.

```dart
void _onBasemapError(int generation) {
  if (!mounted || generation != _basemapGeneration ||
      _basemapFailed || _failureScheduled) return;
  _failureScheduled = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || generation != _basemapGeneration) return;
    setState(() => _basemapFailed = true);
  });
}
```

- [x] Step5: MockClient의 실제403/안내200/SocketException/body stream/잘못된 PNG로 안내와 geometry 보존을 검사한다. debugPrint와 FlutterError를 test 범위에서 캡처하고 `audit-test-key` 및 keyed URL이 출력되지 않는지 확인한 뒤 원래 handler를 복원한다. PNG codec 오류가 별도로 원래 URL을 보고하면 해당 출력 경계를 수정하며 원본 키가 있는 오류를 허용하지 않는다.
- [x] Step6: Completer로 늦은 응답을 제어해 화면 종료 후/설정 변경 후의 callback을 검사한다. 같은 위젯을 progress/currentPoint만 바꿔 재생해도 factory 호출1이고 실패 후 반복 요청하지 않음을 확인한다. key 변경 시 새 client가 생성되고 old client는 완료 후 닫히는 것을 검사한다. 밝음/어두움, 320dp/2배 글자와 semantics의 실패 문구/marker를 검사한다.
- [x] Step7: 위 focused tests와 기존 geometry/playback test를 한 번 통과시키고 해당 파일을 `fix: 지도 로딩 실패에도 산책 경로와 재생 유지`로 커밋한다.

실행 중 확인한 SDK 진단 경로는 상수 HTTP 오류에도 keyed URL을 출력했습니다.
계획의 조건부 오류 경계 수정에 따라 renderer/cache를 유지하는 전용
`CartoTileProvider`/ImageProvider를 추가했습니다. 실패는 SDK 투명 이미지로 처리하고
실패/서비스 안내 cache만 제거합니다. 위 NetworkTileProvider 예시는 이 경계 수정으로
대체됐으며 회귀와 실행 판정을 ledger/검증 문서에 남겼습니다.

### Task 3: 비공개 키 전달과 새 후보 검증

**Files**
- Create: `scripts/prepare_carto_defines.py`, `test/scripts/carto_release_config_test.dart`.
- Modify: `scripts/run_quality_loop.sh`, `docs/release/2026-10-14-maintenance-stage1-release.md`, `docs/superpowers/verification/2026-10-14-maintenance-stage1.md`, `RELEASE_NOTES_v0.9.2.md`.
- Artifacts: 새 APK3개/AAB/checksum, 기존 draft PR#1/release412291177. 공개 게시가 아니다.

**Interfaces**
- `python3 scripts/prepare_carto_defines.py <new-output-json-path>`는 환경 `CARTO_BASEMAP_KEY`만 읽고 trim/비어있음 검사 후 JSON `{"CARTO_BASEMAP_KEY": "..."}`를 exclusive/0600으로 작성한다. 출력과 오류에 키 값은 없다. 기존 파일을 덮어쓰지 않는다.
- quality의 release/all mode는 키가 없으면 Flutter/외부 명령 실행 전에 일반 오류로 끝난다. debug/no-build mode는 기존 CI에서 키 없이도 허용한다.
- quality는 자신이 만든 임시 디렉터리의 파일만 EXIT trap에서 정리한다. 빌드에는 `--dart-define-from-file <path>`를 전달하고 키를 argv나 shell trace에 넣지 않는다.

- [x] Step1: 새 Python CLI에 대해 환경 키 없음/공백, `a&b?x=+` 보존, 기존 파일 덮어쓰기 거부,0600 권한, stdout/stderr 키 누출 없음을 Process.run으로 검사하는 Dart test를 쓴다. release gate는 키 없는 환경에서 빠르게 실패하고 Flutter를 호출하지 않는지 확인한다. 현재 cli 부재 RED를 확인한다.
- [x] Step2: stdlib만으로 준비 스크립트를 구현한다.

```python
key = os.environ.get('CARTO_BASEMAP_KEY', '').strip()
if not key:
    raise SystemExit('CARTO_BASEMAP_KEY is required for release builds')
with open(sys.argv[1], 'x', encoding='utf-8',
          opener=lambda path, flags: os.open(path, flags, 0o600)) as output:
    json.dump({'CARTO_BASEMAP_KEY': key}, output)
```

argv 개수 오류와 파일 작성 오류는 키나 payload 대신 일반 오류로 보고한다.

- [x] Step3: quality의 mode 선택 직후 release/all의 비어있는 환경 키를 검사한다. 기존 clean-tree/signing/manifest/hash 게이트를 유지한다. private 임시 디렉터리와 trap을 만들고 Step2로 파일을 준비한 뒤 모든 해당 Flutter build에 define 파일을 전달한다.

```bash
carto_define_dir=""
cleanup_carto_defines() {
  if [[ -n "$carto_define_dir" ]]; then
    rm -f "$carto_define_dir/carto.json"
    rmdir "$carto_define_dir"
  fi
}
trap cleanup_carto_defines EXIT
flutter_build() {
  if [[ -n "$carto_define_dir" ]]; then
    flutter build "$@" --dart-define-from-file "$carto_define_dir/carto.json"
  else
    flutter build "$@"
  fi
}
# release/all의 사전 키 검사를 통과한 뒤만 실행한다.
carto_define_dir="$(mktemp -d "${TMPDIR:-/tmp}/sanbo-map-define.XXXXXX")"
python3 scripts/prepare_carto_defines.py "$carto_define_dir/carto.json"
flutter_build apk --release --split-per-abi --target lib/main.dart
flutter_build appbundle --release --target lib/main.dart
```

debug APK는 키가 있을 때만 같은 define 파일을 쓰고, 기본 CI에서는 기존 build 명령을 실행한다. 빈 배열의 Bash3 nounset 차이에도 의존하지 않는다. `set -x`를 켜지 않는다. 파일은 기존 키 파일/사용자 파일과 구별되는 새 경로만 쓴다.

- [x] Step4: focused config tests와 `bash -n scripts/run_quality_loop.sh`, 기존 release metadata tests를 통과시킨다. 키 준비 방법/비공개 파일/환경 전달을 release 문서에 기록한다. 사용자가 로컬에 둔 키의 경로만 받고 실제 값을 대화/문서에 복사하지 않는다. 해당 파일을 `build: CARTO 키를 비공개 파일로 배포 빌드에 전달`로 커밋한다.
- [ ] Step5: 사용자의 실제 전용 키가 준비됐을 때 clean committed tree에서 build SHA를 기록하고 `QUALITY_BASE_REF=v0.9.1 bash scripts/run_quality_loop.sh --all-apk`를 한 번 실행한다. native source/의존성이 달라지지 않았다면 직전16/11 native gate 소스 diff를 기록하고 불필요한 전체 native 반복을 하지 않는다. APK3개/AAB의 버전/인증서/hash를 새로 조회한다. 키 없이 signed 후보를 새로 만들거나 기존 후보를 새 제품 코드라고 주장하지 않는다.
- [ ] Step6: 실제 키를 넣은 Android/iOS build에서 도로와 지명이 표시되는지 확인한다. 키 누락 build, 합성 invalid-key build, 기기 네트워크를 끈 상태를 각각 관찰해 경로/재생/실패 안내를 검사한다. 테스트 전용 emulator/simulator만 사용하고 네트워크 설정은 원복한다. 정상200/PNG인 안내 이미지가 아닌 실제 지도를 눈으로 확인한다. 실제키/URL이 드러나는 도구 출력을 저장하지 않는다.
- [ ] Step7: 기존 Android 업데이트/백업 통과 결과와 변경 제품 소스의 연결을 구분한다. 실제 Settings 저장/재가져오기와 상세/재생을 새 APK에서도 smoke한다. 기록을 삭제하거나 pm clear/uninstall로 업데이트를 대신하지 않는다. 결과/미검증 항목을 문서에 기록하고 product-source diff를 남긴다.
- [ ] Step8: 새 build SHA/4개 asset/checksum으로 기존 draft release를 갱신하고 원격 digest/draft=true를 대조한다. PR#1을 최종 범위/실제 검증/미검증 내용으로 갱신한다. exact PR head CI를 조회하되 running을 성공으로 쓰지 않는다. 독립 PR 검토와 구체적인 게시 승인은 완료 전에 별도로 받는다.

## 계획 검토 상태

- [x] 작성된 지도 복구 설계 사용자 승인, 2026-10-15
- [x] 기존 직접 구현 방식 유지, 재위임 없음
- [x] 확인한 invalid-key200/ETag와 flutter_map7 로그 경로를 계획에 반영
- [x] 작성된 이 구현 계획의 사용자 검토, 2026-10-15 직접 구현 승인
- [ ] 실제 전용 basemap 키 준비
- [ ] 세 작업 구현/검증과 새 후보, 독립 검토/공개 확인

2026-10-15 실행 판정: 새로 확인한 [CARTO 공식 안내](https://docs.carto.com/faqs/carto-basemaps#why-do-i-see-an-api-key-required-watermark)는 공급자 notice를 숨기지 않도록 요구한다. 따라서 확인된 HTTP200 안내 PNG는 client가 성공 bytes로 보존하며 별도 상태 callback으로 앱 안내를 표시하도록 Task1/2를 구체화했다. 기존 공급자를 바꾸거나 유료 사용을 추가하는 범위 변경은 아니다.

2026-10-15 구현 상태: Task1 HTTP11개, Task2 widget16개, Task3 config13개와
metadata1개 focused 검증을 통과했습니다. 제품 소스 `8d56049`의 키 없는 전체
Flutter516개/analyzer/debug APK와 tree audit도 통과했습니다. 실제 Android에서
키 없음/합성 invalid key/네트워크 단절과 marker/재생 UI를 확인했습니다. 정상 키와
iOS 지도, 새 signed APK/AAB/asset 교체, 독립 PR 검토/공개 확인은 남아 있습니다.
