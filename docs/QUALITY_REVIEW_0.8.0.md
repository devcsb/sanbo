# 산보 0.8.0 독립 릴리즈 품질 검토

검토일: 2026-08-25
비교 범위: `v0.7.2..v0.8.0` 후보

## 최종 판정

고속 이동 종료 확인·알림과 완료 기록의 구간 제외·복원, 위치 스트림과 알림 복구
경로 정비를 포함한 후보를 구조·정적 분석·회귀·Android manifest·서명·버전 관점에서
검증했다. 모든 게이트가 통과했고 기존 공개 릴리즈와 동일한 인증서 및 증가한
versionCode를 확인했으므로 정식 배포 가능 상태로 판정한다.

## 확인 항목

| 영역 | 확인 결과 |
|---|---|
| 요구사항 | PRD/TRD 구조 검증 통과; FR-26 고속 이동 종료 확인과 구간 제외·복원 매핑 확인 |
| GPS 정확성 | stale anchor 복구, filtered fix 제외, 미관측 gap 통계 회귀 통과 |
| 데이터 | DB 스키마 v4 마이그레이션, `backup_schema_version` 2 내보내기·v1 호환 읽기 회귀 통과 |
| 시각 | 산책 시각 UTC 저장과 알 수 없는 IANA timezone fallback 회귀 통과 |
| UI/UX | 고속 경고 카피, 구간 제외·복원 뒤 지도·세션·기록·일별 합계 동시 갱신 회귀 통과 |
| Android | 위치·FGS location·알림·WakeLock 권한 및 `GeolocatorLocationService`, `foregroundServiceType="0x8"` 확인 |
| iOS | 알림 채널 등록과 scene delegate 탭 경로, 위치 시작 fallback 회귀 통과 |
| 서명 | 3개 ABI 모두 인증서 SHA-256 `ceb40402d706589acee5da5df5a010c3dd5c2e9329cd3218961dfce56a6d38ac` |
| 버전 | versionName `0.8.0`; ABI별 versionCode `1013`/`2013`/`4013` |

## 검증 증거

- `python3 scripts/verify_prd_trd.py` — PASS
- `flutter analyze` — No issues found
- `flutter test` — 356개 통과
- `flutter build apk --release --split-per-abi --target lib/main.dart` — 서명된 3개 ABI 산출
- `apkanalyzer manifest` 권한·서비스·FGS 타입 확인, `apksigner verify --print-certs` 인증서 일치
- 산출물 checksum: [`SHA256SUMS_v0.8.0.txt`](../SHA256SUMS_v0.8.0.txt)
- 릴리즈 노트: [`RELEASE_NOTES_v0.8.0.md`](../RELEASE_NOTES_v0.8.0.md)

## 잔여 검증 위험

`scripts/run_quality_loop.sh --release-apk`는 clean committed working tree를
요구하지만, `flutter pub get`이 `ios/Podfile`과 `ios/Flutter/*.xcconfig`의
CocoaPods 통합 줄을 매번 다시 만든다. 이 파일들은 커밋 4956a88에서 의도적으로
제거했으므로 현재 이 조합에서는 전제조건을 만족할 수 없다. 이번 검토는 스크립트가
수행하는 검사 항목을 동일하게 개별 실행해 대체했으며, 스크립트와 생성 파일 정책의
정합은 후속 과제로 남는다.

`DEVICE_VALIDATION.md`의 물리 기기 행은 여전히 전부 `미판정`이다. 고속 이동
알림 전달, 잠금 화면과 제조사 절전 정책, 구간 제외의 실기기 지속성은 emulator와
simulator 증거만 있으며 현장 측정이 필요하다.

이번 아키텍처 보강에서도 동일한 원칙을 적용한다. SQLite 무결성·자동 종료 경계·UI
재생 성능은 자동화 테스트로 확인할 수 있지만, 실제 배터리 소모율과 Doze/Background
위치 전달은 Galaxy/iPhone 실기기 측정 전까지 수치나 통과로 표기하지 않는다.
