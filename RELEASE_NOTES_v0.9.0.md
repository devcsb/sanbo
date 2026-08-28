# 산보 0.9.0 — 배터리·일별 운동량·회상 UX 고도화

산보 0.9.0은 GPS 기록의 전력 비용을 더 명확히 제어하고, 삼성 헬스·Health Connect·Apple 건강의 걸음 수를 GPS 산책 기록과 분리해 확인하며, 저장 실패와 화면 전환을 더 안정적으로 다듬은 릴리즈입니다.

## 주요 변화

### 배터리와 위치 기록

- 절전(약 20초/10m), 균형(약 8초/5m), 정밀(약 4초/2m) 모드의 정확도·주기·거리 필터·WakeLock 정책을 명시했습니다.
- Android 위치 공급자가 멈추거나 재설정될 때 중복 native stream을 만들지 않고 LocationManager fallback으로 복구합니다.
- 백그라운드에서는 1초 UI ticker와 GPS fix별 화면 갱신을 멈추고, 30초 checkpoint와 안전 판정만 유지합니다.
- 세션 종료·폐기·복구 실패 시 위치 stream, foreground service, timer, 알림을 정리합니다.

### 일별 운동량과 건강 데이터

- GPS 거리·시간·산책 횟수와 Health Connect/HealthKit 걸음 수를 별도 카드로 표시합니다.
- `0걸음`과 권한 없음·지원 불가·읽기 오류를 구분합니다.
- 건강 데이터는 사용자가 화면에서 연결할 때만 읽고, 성공한 일별 합계는 5분 동안 메모리 캐시합니다.
- 일부 기간만 읽힌 경우 완전한 총합처럼 표시하지 않습니다.
- 기록이 없어도 일별 운동량과 산책 시작 CTA에 접근할 수 있습니다.

### 데이터 안정성과 유지보수성

- pending GPS 샘플 저장을 `SessionPersistenceCoordinator`로 분리해 실패한 배치를 순서 그대로 재시도합니다.
- 유지보수 큐를 application 계층으로 이동해 feature 계층 역참조를 제거했습니다.
- 경로 재생 cursor를 분리해 긴 경로에서 매 tick prefix 복사를 줄였습니다.
- 위치 콜백·flush 시간은 원시 좌표 없이 제한된 집계 진단으로만 기록합니다.

### UI/UX와 접근성

- 공통 motion token과 keyed fade transition을 적용하고 reduced-motion 설정에서는 즉시 전환합니다.
- 이전 비동기 화면은 입력을 받지 않도록 하면서 새 CTA는 지연 없이 사용할 수 있습니다.
- 로딩·오류·빈 기록 상태의 높이와 CTA를 정리하고 큰 글자·스크린 리더 경로를 유지했습니다.

## 업데이트·데이터 안내

- 버전은 `0.9.0+14`이며 application ID와 기존 release 서명 인증서를 유지합니다.
- SQLite v6와 기존 백업 포맷을 유지하므로 일반적인 앱 업데이트에서는 로컬 기록이 이어집니다.
- 앱을 삭제하면 OS가 로컬 DB를 삭제할 수 있으므로, 기기 이동·삭제 전 전체 백업을 권장합니다.
- 전체 백업은 정밀 위치를 포함한 암호화되지 않은 로컬 파일입니다.

## Android 설치 파일

| 파일 | 대상 | versionCode | SHA-256 |
|---|---|---:|---|
| `app-arm64-v8a-release.apk` | 최근 64비트 Android | `2014` | 아래 `SHA256SUMS_v0.9.0.txt` 참조 |
| `app-armeabi-v7a-release.apk` | 구형 32비트 Android | `1014` | 아래 `SHA256SUMS_v0.9.0.txt` 참조 |
| `app-x86_64-release.apk` | x86_64 에뮬레이터·일부 기기 | `4014` | 아래 `SHA256SUMS_v0.9.0.txt` 참조 |

## 검증

- `flutter analyze --no-pub`
- Flutter 전체 테스트 397개
- PRD/TRD 구조 검사
- Android native unit tests 및 iOS XCTest
- Android release split APK manifest·FGS·서명 인증서 검사
- iOS no-codesign device build

## 알려진 제한

- 배터리 소모율, Doze, 제조사별 백그라운드 정책은 Galaxy/iPhone 실기기에서 별도 측정해야 합니다.
- 저배터리 전환 정책은 사용자 동의용 domain seam으로 준비되어 있으며, 실제 배터리 API·설정 UI 연결은 후속 작업입니다.
- `health` 플러그인의 legacy Kotlin Gradle Plugin 경고가 남아 있어 플러그인 업데이트를 추적해야 합니다.
- iOS의 보호된 건강 데이터·백그라운드 위치 권한 동작은 기기별 확인이 필요합니다.
