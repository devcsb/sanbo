# 산보 0.9.5 릴리스 증거

2026-11-07 사용자가 배포를 지시했다. 후보는 `0.9.5+19`, package `com.sanbo.sanbo`,
targetSdk 36이다. [PR #4](https://github.com/devcsb/sanbo/pull/4)를 병합하고
[GitHub v0.9.5](https://github.com/devcsb/sanbo/releases/tag/v0.9.5)를 공개했다.
공개 시각은 2026-11-07 08:34:48 KST다. 스토어/iOS 공개는 하지 않았다.

## 변경

- 이번 산책 경로와 주간 누적을 전환하는 요약 화면, 이동 평균 속도의 계산 설명.
- 백업의 50MiB 실제 읽기 제한, 비정상 수치/기간 거부, 취소와 Activity 재생성 때 작업 정리.
- 통계 오류에도 기록 접근 유지, 원본은 안내 후 파일 저장, 요약 복사에서 메모와 장소 제외.
- GPS 흔들림 의심 구간의 확인 안내와 낮은 확신 추정. 원본과 거리/시간은 보존한다.
- 경로 분할 반복 계산 제거와 큰 글자 지도 출처 줄바꿈.

세부 증거는 [백업 검증](../superpowers/verification/2026-11-07-backup-privacy-boundaries.md)과
[GPS 후속 검증](../superpowers/verification/2026-11-07-gps-quality-followup.md)에 있다.
기존 앱을 삭제하지 않고 같은 인증서로 업데이트한다. 새 DB 열/마이그레이션은 없다.

## 후보 검증

기존 서명 인증서 SHA-256은 `ceb40402d706589acee5da5df5a010c3dd5c2e9329cd3218961dfce56a6d38ac`이다.
중립 임시 경로에서 clean commit을 빌드하고 개인 경로/비밀 패턴/기대 지도 키 포함을 검사한다.
공개 자산은 `app-arm64-v8a-release.apk`, 나머지 ABI APK, `app-release.aab`, checksum이다.

| 항목 | 확인 |
|---|---|
| 빌드 소스/태그 | `33dca38548273690b2d8ad8ef3d38705ab23f251`, v0.9.5가 동일 commit을 가리킴 |
| 병합 | `89f3553d16d916a394dce163cae670604877781c`, 빌드 소스와 전체 트리 동일 |
| 배포 전 CI | [42311417666](https://github.com/devcsb/sanbo/actions/runs/42311417666), 두 작업 모두 success |
| Flutter/Python | private release 경로와 CI에서 Flutter 655개, Python 21개, 분석 및 빌드 통과 |
| native | GitHub macOS 작업의 Android native/XCTest 실행과 `[native] PASS` 확인 |
| APK | versionName 0.9.5, ABI versionCode 1019/2019/4019, targetSdk 36, debuggable=false, 기존 서명 일치 |
| AAB | bundletool 1.18.3 validate, JAR 서명 검증과 기존 인증서 SHA-256 일치 |
| 개인정보 검사 | 3 ABI APK/AAB 모두 개인 home 경로/지정 이메일/비밀 파일·패턴 검사 통과, 기대 CARTO 키 포함 확인 |
| 업데이트 | 공개 0.9.4 위 0.9.5 서명 APK 덮어 설치 성공. 앱 삭제 없이 후보 업데이트 |
| 기록/스키마 | 전후 5개 테이블 전체 값과 schema/user_version snapshot 정확히 일치 |
| 지도/상세 | 실제 CARTO 배경 지도, attribution, 14개 경로 좌표와 재생 제어, 새 요약 화면 확인 |
| 공개 파일 | 5개 모두 무인증 HTTP 200, 로컬 검증 후보와 SHA-256 일치 |

기록 비교는 산책 1개, GPS 15개, 분 기록 7개, 장소 1개, 제외 0개의 합성 QA 자료다.
기존 QA fixture를 공개 0.9.4에 준비한 뒤 실제 업데이트 경로를 검사했다. 실제 사용자 DB나
원래 AVD를 초기화하지 않았고 read-only/no-snapshot overlay를 종료했다. snapshot SHA-256은
전후 모두 `95e06d3c1a064570d22e630790ecefa2bcb28abd6c478cf8aa44d7ec81d43984`다.

private release 로그와 입력은 소유자 전용 로컬 자료이며 공개 자산에 넣지 않았다.
공개 검증은 `build/public-release-verification.log`, CI 로그는 `build/release-ci-complete.log`다.
GitHub의 Flutter reporter는 `655 tests passed.` 형식을 사용했으며 실제 완료 문구도 확인했다.
외부 자동 리뷰 표시는 trial 만료로 건너뛰었으므로 별도 코드 리뷰 수행 증거로 세지 않았다.


## 한계

물리 Android 기기 검증: 미실행. 사용자는 S26 연결과 GPS/배터리 실측을 추후로 미뤘다.
흔들림 안내는 자동 GPS 보정이나 실제 보행 판별의 완성이 아니다. CARTO 클라이언트 키의
추출/외부 재사용 가능성과 계정 사용량 조건은 [운영 문서](../security/carto-operations.md)에 남는다.
키/요금제/광고 SDK와 기존 고속 제외 기준은 변경하지 않는다. 원본 백업은 비암호화 파일이다.
독립 모델/업체의 새 감사로 표현하지 않고 코드와 반례, CI 및 배포 산출물을 대조한다.

## 공개 파일

| 파일 | bytes | SHA-256 |
|---|---:|---|
| `SHA256SUMS_v0.9.5.txt` | 357 | `318ff5f04e5e1ef140de23067706802997b1ad5211d96bbf9095f16b0bc392f4` |
| `app-arm64-v8a-release.apk` | 21906510 | `36c08e309c0b5bffca421b45b75389f71e1ee0f8237396d807ba014fefe1f8b1` |
| `app-armeabi-v7a-release.apk` | 19577276 | `2814820d0c1e8434691974e86cf4b1b995ee25583defefc0db1e3650141153b3` |
| `app-release.aab` | 59181797 | `afd22fff76d17754009027d3abae261f3811a0a315ef642a3e8714d05ab53477` |
| `app-x86_64-release.apk` | 23390237 | `e2850024f6785411ceeb48fe0bc3c7736036286ee45eb547646b88421816e322` |
