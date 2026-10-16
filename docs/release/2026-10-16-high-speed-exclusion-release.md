# 산보 0.9.3 고속 자동 제외 릴리즈 증적

후보 버전은 `0.9.3+17`이다. 2026-10-16 사용자가 배포 전 점검과 release 공개를 승인했다.
배포 대상은 기존과 같은 GitHub Releases의 Android APK 3개와 AAB, SHA-256 목록이다.
Google Play와 App Store 배포를 의미하지 않는다.

## 배포할 변경

- 단발성 GPS 급증 대신 지속된 고속 이동과 GPS 품질을 함께 확인해 자동 제외한다.
- 제외 경계의 실제 좌표로 앞쪽 정상 산책의 마지막 선분을 보존한다.
- 완료 저장 재시도와 동시 요청에서 제외, 집계와 사용자 수정을 보존한다.
- 과거 형식의 시간 키를 차량으로 확정하면 실제 수정한 분에만 제외를 적용한다.
- 기존 DB schema 6과 백업 schema 2를 유지하며 원본 GPS와 과거 기록을 소급 변경하지 않는다.

제품 설계와 반례는 [비판적 검토 보고서](../superpowers/verification/2026-10-16-high-speed-critical-review.md)를 따른다.
제품 변경 head `1cef30b9e99d7d6ca393bfd1e38be05be2c804da`의
[CI 38899685211](https://github.com/devcsb/sanbo/actions/runs/38899685211)는 Flutter/Android와
native 두 job 모두 성공했다. 버전 준비 후 현재 head CI와 서명 빌드는 별도로 대조한다.

## 서명 후보 점검

기존 공개 버전은 [v0.9.2](https://github.com/devcsb/sanbo/releases/tag/v0.9.2)다.
기존 인증서 SHA-256은 `ceb40402d706589acee5da5df5a010c3dd5c2e9329cd3218961dfce56a6d38ac`다.
새 후보에서 버전, ABI별 증가한 versionCode, targetSdk 36과 minSdk 26, 위치 foreground
service 권한 및 서명을 확인한다. AAB는 bundletool 구조 검증과 JAR 서명을 확인한다.
지도 키는 사용자가 준비한 로컬 파일에서 비공개 환경으로만 전달한다.

아직 새 후보를 빌드하거나 공개하지 않았다. 결과와 artifact hash는 검증 후 아래에 기록한다.
빌드/검증 로그는 로컬 `.superpowers/sdd/2026-10-16-release-0.9.3/`에 보관한다.

## 검증 한계

합성 GPS와 emulator/simulator, 로컬 SQLite 검증은 물리 기기의 정확도와 배터리 측정이 아니다.
물리 Android/iPhone GPS, 배터리, VoiceOver/TalkBack 실사용은 미검증이다.
10km/h 이상 달리기도 자동 제외 조건에 포함되며, 사용자가 확정한 걷기와 제외 취소를 우선한다.
GPS 원본 거리의 노이즈 보정(MR-08)과 과거 부분 제외 표시(MR-15)는 별도 범위다.
