# 산보 0.7.1 독립 최종 품질 검토

검토일: 2026-08-07
비교 범위: `v0.7.0..v0.7.1` 후보

## 독립 검토 판정

과거 검토 결론을 전달하지 않은 독립 코드 검토자가 성능·구조·데이터 내구성·배터리·플랫폼·UI/UX·보안·릴리스 관점으로 전체 트리를 다시 감사했다. 최초 판정은 **릴리스 불가**였으며 아래 차단 항목을 수정한 뒤 전체 게이트를 재실행했다.

| 우선순위 | 최초 발견 | 최종 조치 |
|---|---|---|
| Critical | 기존 공개 릴리스와 같은 `0.7.0+10`으로 새 APK를 만들 위험 | `0.7.1+11`로 증가하고 앱 표시 버전 동기화 테스트 추가 |
| Critical | 임의 키로 서명해도 release gate가 통과하고 과거 APK hash를 현재 증거로 오인 | 기존 공개 인증서 SHA-256을 fail-closed로 고정하고 매 빌드 3 ABI를 검증; 후보 APK를 새로 빌드해 hash 재기록 |
| Critical | 기존 공개 인증서의 개인키를 기본 Android debug 키스토어에서 직접 운용 | 동일 인증서를 강한 임의 암호의 전용 PKCS#12로 분리하고 Keychain 비밀번호·소유자 전용 권한·암호화 백업으로 보호 |
| Important | 저장 종료 재시도 실패 후 메모리 전용 GPS가 재개 시 pending에서 빠짐 | 성공 전 pending을 제거하지 않고 재개 시 DB와 메모리 차이를 다시 checkpoint; 실패→재개 회귀 추가 |
| Important | 속도·고도 Infinity가 DB와 JSON 백업을 오염 | 플랫폼·도메인 경계에서 비유한 메타데이터 제거, 종료·백업 e2e 추가 |
| Important | 과거 DB의 비유한·범위 밖 REAL 값 때문에 백업 생성 또는 재가져오기가 실패할 수 있음 | 세션·샘플·구간·장소별 REAL을 정화하고 잘못된 좌표 샘플/장소를 제외한 export→fresh import 회귀 추가 |
| Important | 첫 fix 전·마지막 fix 후·긴 GPS gap을 이동 시간과 직선거리로 계산 | 60초 이내 인접 fix만 이동/정지·거리에 반영하고 gap 회귀 추가 |
| Important | 50MB 백업을 UI isolate에서 두 번 파싱 | 한 번만 background isolate에서 decode하고 검증된 archive를 preview/import에 재사용 |
| Important | v2→v3 실제 데이터 보존 증거 부족 | v2 전체 대표 schema fixture에 산책·GPS·윈도우 수정·메모·장소를 넣어 migration 보존 검증 |
| Important | `apkanalyzer` 부재·생성 파일 변화에도 품질 스크립트가 PASS | 필수 도구 부재, 인증서 불일치, 범위 whitespace, 실행 전후 작업 트리 변화에서 즉시 실패하도록 변경 |
| Important | 로컬 저장 문구가 CARTO 타일 통신을 설명하지 않음 | 설정·README·TRD에 타일 표시 영역과 네트워크 정보 고지 |

## 검증 증거

- 구조: `python3 scripts/verify_prd_trd.py`
- 정적 분석: `flutter analyze --no-pub`
- 회귀: `flutter test --no-pub --concurrency=1` — 133개
- 릴리스: `flutter build apk --release --split-per-abi`
- manifest: 위치·FGS location·알림·WakeLock 및 `GeolocatorLocationService`의 location FGS 타입
- 인증서: SHA-256 `ceb40402d706589acee5da5df5a010c3dd5c2e9329cd3218961dfce56a6d38ac`
- 버전: `0.7.1`, ABI별 versionCode `1011` / `2011` / `4011`
- migration: v1→v3와 현실적 v2→v3 fixture 보존
- 산출물 hash: [`RELEASE_NOTES_v0.7.1.md`](../RELEASE_NOTES_v0.7.1.md)

## 증거 부족·남은 위험

다음 항목은 코드·시뮬레이션만으로 충족 판정하지 않는다.

1. Galaxy 실기기 60분 모드별 배터리와 제조사 절전 정책
2. 실제 잠금 화면의 20/30분 정지 및 2시간 45분/3시간 알림·자동 종료
3. 실제 기기의 0.7.0→0.7.1 `adb install -r`와 파일 선택기 UX
4. iOS 잠금 화면 background location과 App Store 심사 문구
5. 50MB 초과 스트리밍·암호화 백업 및 앱 잠금
6. 수천 건 기록의 실제 단말 스크롤 체감

실행 절차는 [`DEVICE_VALIDATION.md`](DEVICE_VALIDATION.md)에 유지한다. 연결된 Android 실기기가 없는 이번 환경에서는 인증서·증가한 versionCode·DB migration으로 업데이트 호환성을 검증했으며, 실기기 항목을 완료했다고 주장하지 않는다.

## 최종 결론

독립 감사에서 확인된 코드·릴리스 차단 항목은 수정과 자동 회귀로 소유권을 닫았다. Android GitHub APK 배포에 필요한 정적·테스트·빌드·manifest·서명·버전·hash 증거는 확보했다. 실기기 배터리·백그라운드 결과는 알려진 미검증 위험으로 명시하며 후속 장치 검증 전까지 수치 보장을 하지 않는다.

## 0.7.2-dev 후속 검토: 일별 운동량

2026-08-15 구현 검토에서 기록 화면에 최근 7일의 완료 산책을 시작일 기준으로
SQLite 집계하는 `dailyStats` API와 Riverpod 상태, 접근성 날짜 선택 패널을 추가했다.
집계 지표는 거리·시간·횟수로 한정하고, 빈 날짜는 0값으로 채우며, 날짜 선택은 최근
산책 목록을 필터링하지 않는다. 걸음 수·칼로리·Samsung Health/Health Connect 연동과
월간 차트는 명시적으로 범위 밖이다.

검증 범위: 저장소 경계·자정 교차·진행 중 제외·인덱스 query plan, provider 갱신,
7일 탐색/미래 제한, API 오류 열화, 큰 글씨 compact 화면, 실제 기록 화면 선택/목록
유지 위젯 회귀를 자동 테스트한다. 실기기에서의 날짜 표시·스크롤 체감은 기존 장치
검증 절차로 후속 확인한다.

## 0.7.2-dev GPS 장시간 세션 후속 검토

실제 Android 3시간 이상 사용에서 보고된 거리 과대·속도 `0.0 km/h` 증상을 데이터
흐름별로 재검토했다. 기존 종료 롤업만 60초 초과 GPS 공백을 제외하고 실시간/복구
경로는 좌표를 그대로 연결하던 차이를 확인했으며, Android 공급자 `speed=0`이 좌표로
계산한 속도를 덮어쓰는 결함도 재현했다.

수정 후 실시간·복구 거리 모두 60초 공백을 비연결 구간으로 처리하고, 이동 중 좌표
변위로 속도를 파생한다. 필터된 GPS 점프의 공급자 속도는 표시하지 않으며, 세션
가드도 동일한 파생 속도를 사용한다. 회귀 테스트는 장시간 공백, 복구, zero-speed
fix, 필터 점프를 포함한다. 실기기별 GPS 품질·제조사 절전 정책은 여전히
`DEVICE_VALIDATION.md`의 장치 검증 대상이다.
