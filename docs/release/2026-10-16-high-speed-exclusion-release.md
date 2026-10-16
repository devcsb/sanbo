# 산보 0.9.3 고속 자동 제외 릴리즈 증적

2026-10-16 사용자가 배포 전 점검과 release 공개를 승인했다.

| 항목 | 확인한 결과 |
|---|---|
| 버전 | `0.9.3+17` |
| 공개 릴리즈 | [GitHub v0.9.3](https://github.com/devcsb/sanbo/releases/tag/v0.9.3) |
| 게시 시각 | 2026-10-16 22:44:16 KST |
| 릴리즈 상태 | 공개, 정식 버전, latest, draft/prerelease 아님 |
| 빌드 및 태그 소스 | `b00f5cd9ecc9366b611f96994bfec3c123f2bd9e` |
| 병합 PR | [PR #2](https://github.com/devcsb/sanbo/pull/2) |
| main 병합 커밋 | `482e01bb4a8b60c8395576963f71b03d738d4aec` |
| 서명 소스 CI | [run 38907358050](https://github.com/devcsb/sanbo/actions/runs/38907358050), Flutter/Android와 native 두 job 모두 성공 |
| 공개 산출물 | APK 3개, AAB, SHA-256 목록 |
| 스토어 | Google Play/App Store 신규 게시 미실행 |

`main` 병합 직후 트리는 검증한 빌드 소스와 전체 diff가 없었다. 이 문서와 설치 안내는
공개 검증 뒤 증적을 기록한 후속 문서 수정이다. 서명 산출물과 태그는 변경하지 않았다.

## 배포한 변경

지속된 고속 이동과 GPS 품질을 함께 확인해 자동 제외하며, 제외 경계의 실제 좌표로
앞쪽 정상 산책의 마지막 선분을 보존한다. 완료 저장 재시도/동시 요청과 과거 시간 키
편집의 기록 손실도 수정했다. 기존 DB schema 6과 백업 schema 2를 유지한다.
제품 계약과 반례는 [비판적 검토 보고서](../superpowers/verification/2026-10-16-high-speed-critical-review.md)를 따른다.

## 빌드와 배포 전 검증

- 앱 내부 버전 표시가 이전 `0.9.2`에 남아 있던 부분을 배포 검사에서 발견해 수정했다.
  기존 버전/릴리즈 검증 두 테스트의 실패를 확인한 뒤 동기화했다.
- clean 소스 `b00f5cd`에서 실제 CARTO 키를 비공개 환경으로 전달한
  `scripts/run_quality_loop.sh --all-apk`가 통과했다. PRD/TRD 구조 검사, analyzer,
  전체 Flutter **570개**, debug APK, release split APK/AAB와 clean-tree audit를 포함한다.
- APK 3개는 모두 package `com.sanbo.sanbo`, versionName `0.9.3`, minSdk 26,
  targetSdk 36, debuggable false다. versionCode는 armeabi-v7a 1016→1017,
  arm64-v8a 2016→2017, x86_64 4016→4017이다. AAB versionCode는 17이다.
- APK 3개와 AAB의 인증서는 기존 공개 v0.9.2와 동일하다. 인증서 SHA-256은
  `ceb40402d706589acee5da5df5a010c3dd5c2e9329cd3218961dfce56a6d38ac`다. APK는 apksigner, AAB는 JAR 서명과 인증서 조회로 확인했다.
- bundletool 1.18.3 validate와 manifest 검사가 exit 0이다. JAR self-signed/stream-order
  경고와 기존 health KGP 전환 경고는 로그에 남겼다. Google Play 접수 검증을 뜻하지 않는다.
- PR head, CI head, 빌드 소스가 동일함을 확인한 뒤 병합했다. 태그 생성은 새 태그의
  non-force push로 수행했고, 공개 후 실제 태그를 따라가 같은 소스인지 대조했다.

## 실제 release APK의 Android 검증

전용 API34 emulator에서 공개 v0.9.2 arm64 APK와 설치된 APK의 SHA-256이 같음을 먼저
확인했다. 앱 삭제 없이 `install -r`로 v0.9.3을 적용했고 앱 표시와 패키지 버전도 확인했다.

- 시스템 picker로 업데이트 전후 전체 백업을 각각 저장했다. 두 파일은 각
  12,747 bytes이고 **5개 테이블의 모든 행이 동일**했다.
  산책 2개, 원본 GPS 24개, 분 기록 10개와 장소 1개, 메모와 사용자 수정이 보존됐다.
- 구버전 백업 재가져오기는 `산책 0개를 가져왔어요 · 중복 2개 건너뜀`으로 끝났다.
- 새 서명 APK에서 실제 도로 지도와 출처 표시, 경로 재생을 확인했다.
  빌드에 사용한 client basemap 키 포함 여부만 검사했고 값은 로그/문서에 출력하지 않았다.
- 기존 emulator smoke로 실제 Geolocator provider의 기록 시작, 이동 주입과 거리 누적,
  완료 저장 화면, 종료 후 위치 요청 해제를 확인했다. release APK는 비디버그이므로
  내부 DB `run-as` 검사는 사용하지 않고 아래 실제 백업으로 저장 결과를 추가 검증했다.
- 별도 160초/41개 합성 이동을 실제 Android provider에 주입했다. 라이브 고속 경고는
  기록을 유지했고, 완료 후 실제 저장 결과에서 **2분 자동 제외**를 확인했다.
  원본 GPS 23개와 제외 분 2개의 경계 계산 근거가 백업에 남았다.
- 상세 화면의 `제외 취소`를 사용한 뒤 같은 원본 행을 그대로 보존하며
  **1,728.7m / 219초 / 유효 좌표 23개**로 복원됐다.
  제외 레코드와 분 참조는 제거됐다. 기존 기록도 모두 보존했고 위치 요청도 해제됐다.
- 사용한 emulator는 검증 후 종료했다. 다른 worktree나 공개 v0.9.2 자산은 변경하지 않았다.

## 공개 다운로드와 체크섬

원격 초안의 파일 5개 digest/크기를 로컬 서명 후보와 대조한 뒤 공개했다.
공개 후 GitHub의 latest가 v0.9.3임과 PR 병합, tag commit을 확인했다. 인증 정보를
사용하지 않는 HTTP 요청으로 **공개 파일 5개 모두 HTTP 200**으로 내려받았고,
각 크기/해시와 checksum manifest가 같은 서명 후보의 바이너리 4개를 가리킴을 확인했다.
checksum은 다운로드한 파일과 같은 폴더에서 검증할 수 있도록 basename만 기록했다.

| 파일 | SHA-256 |
|---|---|
| `app-release.aab` | `43160740d8c4cf5e43ca49a76eada20254800695f7229e80f72e2b570aceac74` |
| `app-arm64-v8a-release.apk` | `12acd6d72c2cac7bfb4c2212aafa94cb387e5fc082fc2fc17be9ecf79d1559f6` |
| `app-armeabi-v7a-release.apk` | `cb66a159ccb04b50115684983da12c5559a60b106ddfd476efdcb00f16eeed1d` |
| `app-x86_64-release.apk` | `cc51a8e9f89857f48f007285361300f91ec6c6d81e881e6ee36d6e2a64e198b9` |
| `SHA256SUMS_v0.9.3.txt` | `1744d3eebe450fc41ba1e68b1ee7ca24b54a73036af689207ad1c6ed97a36281` |

로그, 스크린샷, 설치 전후 백업과 공개 검증 receipt는 로컬
`.superpowers/sdd/2026-10-16-release-0.9.3/`에 보관한다. 로그와 문서에는 키 값이나 비밀번호를 기록하지 않았다.

## 검증 한계

물리 Android 기기 검증: 미실행. 물리 iPhone GPS/배터리와 VoiceOver/TalkBack 실사용도 미검증이다.
합성 GPS와 emulator/simulator 결과를 실제 보행 정확도와 배터리 측정으로 일반화하지 않는다.
10km/h 이상 달리기도 자동 제외 조건에 포함되며, 걷기 확정과 제외 취소를 우선한다.
분 전체가 확인되지 않은 고속 이동은 남을 수 있다. GPS 원본 거리의 노이즈 보정(MR-08)과
과거 부분 제외 표시(MR-15)는 별도 범위다. Google Play/App Store에 새로 게시하지 않았다.
