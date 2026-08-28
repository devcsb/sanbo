# 산보 0.9.0 독립 릴리즈 품질 검토

검토일: 2026-08-29
비교 범위: `v0.8.0..v0.9.0` 후보

## 최종 판정

배터리 친화적 위치 수집 프로파일, Health Connect/HealthKit 일별 운동량,
저장·복구 경계, 접근성 및 화면 전환 보강을 포함한 후보를 요구사항·정적 분석·
회귀·네이티브·Android manifest·서명·버전 관점에서 검증했다. 릴리즈 품질 루프가
깨끗한 커밋 트리에서 통과했고, 기존 릴리즈 인증서와 증가한 versionCode를 확인했으므로
정식 배포 가능 상태로 판정한다.

## 확인 항목

| 영역 | 확인 결과 |
|---|---|
| 요구사항 | PRD/TRD 구조 검증 통과; 배터리·일별 운동량·저장 경계·접근성 계약 확인 |
| 배터리/GPS | 절전·균형·정밀 프로파일, Android provider fallback, 백그라운드 checkpoint와 화면 갱신 억제 회귀 통과 |
| 일별 운동량 | GPS 합계와 Health 데이터 분리, 0/권한 없음/지원 불가/부분 범위 상태 구분, 5분 메모리 캐시 회귀 통과 |
| 데이터 | SQLite v6 마이그레이션, 백업 v2 import/export, pending 샘플 재시도와 세션 복구 회귀 통과 |
| UI/UX | keyed fade, reduced motion, 이전 비동기 화면 입력 차단, 빈 기록·큰 글자·스크린 리더 경로 회귀 통과 |
| Android | 위치·FGS location·알림·WakeLock·Health Connect 권한 및 `GeolocatorLocationService`, `foregroundServiceType="0x8"` 확인 |
| iOS | HealthKit capability, Pod 통합, no-codesign device build와 XCTest 통과 |
| 서명 | 3개 ABI 모두 인증서 SHA-256 `ceb40402d706589acee5da5df5a010c3dd5c2e9329cd3218961dfce56a6d38ac` |
| 버전 | `0.9.0+14`; ABI별 versionCode `1014`/`2014`/`4014` |

## 검증 증거

- `bash scripts/run_quality_loop.sh --release-apk` — PASS
- `python3 scripts/verify_prd_trd.py` — PASS
- `flutter analyze --no-pub` — No issues found
- `flutter test --no-pub --concurrency=1` — 397개 통과
- Android release split APK 3개 빌드·manifest·서명 검사 통과
- Android native unit tests 및 iOS XCTest 통과
- `flutter build ios --no-codesign` — 통과
- 산출물 checksum: [`SHA256SUMS_v0.9.0.txt`](../SHA256SUMS_v0.9.0.txt)
- 릴리즈 노트: [`RELEASE_NOTES_v0.9.0.md`](../RELEASE_NOTES_v0.9.0.md)

## 잔여 검증 위험

자동화 검증은 배터리 사용량의 절대 수치나 제조사별 Doze·백그라운드 정책을 보장하지
않는다. Galaxy/iPhone 실기기에서 절전·균형·정밀 프로파일별 배터리, 잠금 화면 위치
전달, Health 권한 UX를 별도 측정해야 한다. `health` 플러그인의 legacy Kotlin Gradle
Plugin 경고와 일부 의존성의 Java 8 경고가 남아 있으므로 플러그인 업데이트를 추적한다.

Health 데이터는 사용자가 연결한 때에만 읽으며, 앱 삭제 시 OS 정책에 따라 로컬 기록이
삭제될 수 있다. 기기 이동이나 삭제 전 전체 백업을 권장한다.
