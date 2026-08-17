# 산보 0.7.2 독립 릴리즈 품질 검토

검토일: 2026-08-17  
비교 범위: `v0.7.1..v0.7.2` 후보

## 최종 판정

일별 운동량 API·UI, 장시간 GPS 거리·속도 보정, 5시간 세션 보호 정책을 포함한
후보를 구조·정적 분석·회귀·Android manifest·서명·버전 관점에서 재검증했다.
자동 릴리즈 게이트가 통과했고, 기존 공개 릴리즈와 동일한 인증서 및 증가한
versionCode를 확인했으므로 정식 배포 가능 상태로 판정한다.

## 확인 항목

| 영역 | 확인 결과 |
|---|---|
| 요구사항 | PRD/TRD 구조 검증 통과; 일별 운동량과 4시간 45분/5시간 정책 매핑 확인 |
| GPS 정확성 | 60초 초과 gap 비연결, provider zero-speed fallback, filtered jump 회귀 통과 |
| 데이터 | 기존 DB·백업·복구·마이그레이션 전체 회귀 통과 |
| UI/UX | 최근 7일 패널, 큰 글씨·compact 화면, 경고·완료 카피 회귀 통과 |
| Android | 위치·FGS location·알림·WakeLock 권한 및 `GeolocatorLocationService` 확인 |
| 서명 | 3개 ABI 모두 인증서 SHA-256 `ceb40402d706589acee5da5df5a010c3dd5c2e9329cd3218961dfce56a6d38ac` |
| 버전 | versionName `0.7.2`; ABI별 versionCode `1012`/`2012`/`4012` |

## 검증 증거

- `python3 scripts/verify_prd_trd.py`
- `flutter analyze --no-pub`
- `flutter test --no-pub --concurrency=1` — 154개
- `bash scripts/run_quality_loop.sh --release-apk` — PASS
- 산출물 checksum: [`SHA256SUMS_v0.7.2.txt`](../SHA256SUMS_v0.7.2.txt)
- 릴리즈 노트: [`RELEASE_NOTES_v0.7.2.md`](../RELEASE_NOTES_v0.7.2.md)

## 잔여 검증 위험

연결된 Android 실기기가 없어 5시간 잠금 화면 기록, 제조사 절전 정책, 실제 알림
전달 및 배터리 수치는 현장에서 확인하지 못했다. 이는 코드·시뮬레이션 게이트와
별도로 `DEVICE_VALIDATION.md` 절차에 따라 후속 측정해야 한다.
