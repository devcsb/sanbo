# 산보 0.9.1 Android 릴리즈 후보

검토 기준일: 2026-09-24

## 후보 정보

| 항목 | 값 |
|---|---|
| 버전 | `0.9.1+15` |
| Android target SDK | `36` |
| 최소 Android SDK | `26` |
| 릴리즈 인증서 SHA-256 | `ceb40402d706589acee5da5df5a010c3dd5c2e9329cd3218961dfce56a6d38ac` |
| 배포 대상 | 외부 배포 전 확인 필요 |

## 포함한 안정화 작업

- 완료 산책 상세와 export의 속도·페이스를 이동 시간 기준 평균값으로 통일했다.
- 세션 시작 이전 캐시 위치를 거부하고, Android 재개 시 권한·정밀도 상태를 다시 확인한다.
- Health Connect 설정 진입을 SDK 제공 action과 Android 버전 fallback으로 보강했다.
- 자동 경로 제외를 원시 GPS 보존·복원 가능 구조로 정리하고, 사용자가 차량이 아닌 활동으로 확정한 빠른 걷기를 덮어쓰지 않게 했다.

## 산출물 증적

품질 게이트가 생성하고 검증해야 하는 파일은 아래와 같다.

- `build/app/outputs/bundle/release/app-release.aab`
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- `build/app/outputs/flutter-apk/app-x86_64-release.apk`
- `build/app/outputs/release/SHA256SUMS_v0.9.1.txt`

`SHA-256` 값은 서명된 산출물을 최종 빌드한 뒤 기록한다. APK는 `apksigner`로
인증서와 서명을 확인하고, arm64 APK는 `apkanalyzer`로 application ID, version,
target SDK, 위치·foreground service·알림·WakeLock 권한을 확인한다.

## 검증 상태

- `targetSdk 36`: arm64 APK manifest에서 확인한다.
- `flutter analyze --no-pub`: 릴리즈 게이트에서 확인한다.
- `flutter test --no-pub --concurrency=1`: 릴리즈 게이트에서 확인한다.
- `python3 scripts/verify_prd_trd.py`: 릴리즈 게이트에서 확인한다.
- Android native unit tests: 확인한다.
- 서명된 AAB·ABI APK: 로컬 release keystore로 생성하고 확인한다.
- 물리 Android 기기 검증: 미실행. 현재 연결된 환경에 실측 Android 기기가 없다.
- Google Play 또는 GitHub 외부 배포: 대상과 계정 권한 확인 전 보류한다.
