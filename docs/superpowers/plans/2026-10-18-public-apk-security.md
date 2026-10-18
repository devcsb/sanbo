# 공개 APK 보안 개선 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 지도 인증 실패를 정확히 표시하고 개인 빌드 경로가 없는 Android 릴리스와 재발 방지 검사를 만든다.

**Architecture:** 기존 CARTO callback/cache 흐름을 보존한다. Python stdlib 검사와 중립 경로 빌드 절차를 기존 품질 게이트에 연결하고, 실제 APK와 운영 계정 조건으로 결과를 확인한다.

**Tech Stack:** Flutter/Dart, Python 3 stdlib/unittest, Bash, Git, Android SDK, 기존 REA 6.5.0.

**Spec:** [승인된 설계](../specs/2026-10-18-public-apk-security-design.md).

## Global Constraints

- 별도 산보 서버, 광고 SDK, 새 의존성, DB 스키마 변경을 추가하지 않는다.
- 원본 GPS, 확정 라벨, 제외 취소, 기존 서명 인증서를 보존한다.
- 공급자 안내 PNG와 attribution을 유지한다. 키/URL/개인 경로 원문을 진단에 출력하지 않는다.
- 사용자 AGENTS에 따라 실행자가 이 세션에서 직접 구현한다. 다른 작업 트리의 변경을 건드리지 않는다.
- 계정 조건을 못 확인하면 미확인으로 남긴다. 기존 키 제한/폐기로 v0.9.3 지도를 끊지 않는다.
- 후보 버전은 구현자 판단으로 패치 릴리스 `0.9.4+18`을 사용한다. 공개/병합은 구체적 후보와 검증 결과를 제공한 뒤 승인 범위에 맞춘다.

## Review Focus

- ETag가 없거나 일반 타일인 경우 정상 지도를 실패로 분류하지 않아야 한다. Task 1의 strong/weak/normal/missing 사례로 검사한다.
- 아카이브 파일명/entry/예외에 비밀 문자열이 있어도 CLI가 출력하면 안 된다. Task 2에서 stdout/stderr를 검사한다.
- AAB 또는 여러 ABI 중 하나에만 개인정보/키 누락이 있어도 실패해야 한다. Task 2의 혼합 payload 사례로 검사한다.
- 키/서명 설정 부족, 빌드 실패, 출력 폴더 충돌이 사용자 파일을 덮거나 임시 설정을 남기면 안 된다. Task 3에서 격리된 fixture로 검사한다.
- 정상 지도 복구, 앱 업데이트, 기존 기록 보존은 문자열 테스트만으로 증명할 수 없다. Task 5에서 실제 서명 APK와 QA 기기로 확인한다.

---

### Task 1: CARTO 인증 안내와 회복

**Files:** Modify `lib/shared/widgets/carto_basemap.dart`, `test/shared/carto_basemap_test.dart`; provider 통합 검사는 `test/widget/route_map_test.dart`를 사용한다.

**Interfaces:** 기존 `CartoTileClient(http.Client, {onAuthenticationNotice})`, `CartoBasemapUnavailable`와 반환 body를 유지한다. provider에 새 public 인터페이스를 추가하지 않는다.

- [ ] 현재 무키 응답 ETag `"wm-6dc6c2207e69-light"`, weak 표현 `W/"wm-6dc6c2207e69-light"`, 이전 ETag의 callback=1/body 보존 검사와 normal/missing/부분 일치 callback=0 검사를 추가한다. 비밀 포함 전송 오류는 기존 generic 예외여야 한다.
- [ ] `flutter test --no-pub test/shared/carto_basemap_test.dart`를 실행해 새 안내 사례가 실패함을 확인한다.
- [ ] strong/weak의 관측된 `wm-…-light` 형태만 좁게 인식하도록 완전 일치를 바꾼다. 원래 PNG와 generic 오류 처리를 유지한다.
- [ ] CARTO 테스트와 실제 존재하는 지도 위젯 테스트를 실행해 정상/안내/실패 뒤 회복과 진단 redaction을 검사한다. 명령은 `flutter test --no-pub test/shared/carto_basemap_test.dart test/widget/route_map_test.dart`다.
- [ ] 해당 파일만 커밋한다. 메시지 `fix: 변경된 지도 인증 안내를 감지하도록 수정`.

### Task 2: 공개 Android 산출물 검사

**Files:** Create `scripts/audit_android_artifact.py`, `test/scripts/test_android_artifact_audit.py`.

**Interfaces:** `audit_archive(path: Path, *, forbidden_values: Sequence[bytes] = (), expected_carto_key: bytes | None = None) -> list[dict[str, object]]`. CLI는 APK/AAB 경로 목록을 받고 실패 항목의 종류와 entry 순번만 출력한다. `CARTO_BASEMAP_KEY`와 선택적 JSON 배열 `SANBO_AUDIT_FORBIDDEN_TEXTS`를 환경에서 읽으며 값은 출력하지 않는다.

- [ ] stdlib unittest로 합성 APK/AAB zip을 만든다. 정상 공개 클라이언트 키는 허용, Mac/Linux/Windows 개인 경로와 private-key PEM/keystore/비밀 설정 entry는 검출, 공급된 개인 문자열 검출, 모든 libapp.so의 기대 키 존재, 손상 zip/중복 entry/예산 초과와 stdout/stderr 비밀 부재를 검사한다.
- [ ] `python3 -m unittest discover -s test/scripts -p 'test_android_artifact_audit.py' -v`에서 구현 부재로 실패함을 확인한다.
- [ ] zip을 추출하지 않고 읽는 검사기를 구현한다. 입력 2GiB, entry 256MiB, 전체 비압축 1GiB, entry 10,000개를 상한으로 둔다. 알려진 개인 이메일은 private 환경 입력으로 전달한다. 진단에 원문/주변 바이트/entry 이름/traceback을 넣지 않는다.
- [ ] 위 unittest를 실행한다. 기존 공개 v0.9.3 APK에 적용했을 때 개인 경로 검출로 실패하고 키 값은 나오지 않는지 별도 확인한다.
- [ ] 검사기와 테스트만 커밋한다. 메시지 `test: Android 배포물의 개인정보와 비밀 파일 검사 추가`.

### Task 3: 중립 경로 릴리스 빌드

**Files:** Create `scripts/build_private_android_release.py`, `test/scripts/test_private_android_release.py`; Modify `scripts/run_quality_loop.sh`.

**Interfaces:** `python3 scripts/build_private_android_release.py --output <새 출력 디렉터리>`는 현재 저장소의 clean HEAD를 `/tmp` 아래 0700 임시 checkout으로 복제해 기존 품질 게이트를 실행한다. 실제 서명 파일은 외부에 유지하고 staged `android/key.properties`에 원래 상대 storeFile을 절대 경로로 해석해 0600으로 기록한다. CARTO/비밀번호는 기존 private 환경 입력을 재사용한다. 성공 시 APK/AAB/체크섬만 새 output으로 복사하고 임시 checkout은 종료 시 정리한다.

- [ ] unittest로 별도 임시 Git 저장소와 stub quality 명령을 사용한다. clean HEAD만 반영, 상대 키스토어 경로 보존, 기존 output/dirty source/키 누락 거부, 실패/성공 정리, 기존 사용자 파일 보존, 비밀 출력 부재를 검사한다. 실제 Flutter/JDK 빌드는 stub하지 않는 Task 5에서 검증한다.
- [ ] `python3 -m unittest discover -s test/scripts -p 'test_private_android_release.py' -v`에서 구현 부재로 실패함을 확인한다.
- [ ] wrapper를 구현한다. 임시 clone/설정/log는 private 권한으로 만들고 키스토어를 복사하거나 추적하지 않는다. 기존 output을 덮지 않는다. 오류 시 로그 원문을 자동 출력하지 않는다.
- [ ] 기존 quality loop에 Python 보안 테스트와 release 산출물 검사를 연결한다. debug 경로에 실제 키나 서명을 새로 요구하지 않는다. 이미 있는 CARTO 빌드 설정/서명/clean-tree 게이트를 재사용한다.
- [ ] Python 전체 스크립트 테스트와 `flutter test --no-pub test/scripts/carto_release_config_test.dart`를 실행해 wrapper 동작과 기존 debug 호환성을 확인한다.
- [ ] 관련 파일만 커밋한다. 메시지 `build: 중립 경로에서 비공개 Android 릴리스 생성`.

### Task 4: 개인정보 안내와 운영 조건

**Files:** Modify `lib/features/settings/settings_screen.dart`, `README.md`, `docs/PRD.md`, `docs/TRD.md`; Create `docs/security/carto-operations.md`. Modify `test/features/ux_settings_safety_test.dart`에서 노출/스크롤을 검증한다.

**Interfaces:** DB나 외부 API를 바꾸지 않는다. 지도 설명은 ‘지도 화면을 열면 표시 영역과 IP 주소 등 요청 정보가 CARTO에 전달돼요. 이 정보로 표시 위치를 추정할 수 있어요.’로 바꾼다. 사용자 요청 OS 주소 조회 안내를 같은 데이터 설명에 추가한다.

- [ ] 기존 설정 위젯 검사에 새 지도 안내와 OS 주소 조회 안내가 표시되고 관리 버튼에 계속 접근할 수 있는지 사례를 추가해 실패를 확인한다.
- [ ] 문구와 README/PRD/TRD를 고친다. 공개 키의 재사용 가능성, 평문 백업, 중립 빌드 절차, 광고 전 상업용 변경/건강 데이터 광고 사용 금지를 설명한다.
- [ ] CARTO dashboard의 현재 로그인 상태를 확인하고, 접근 가능한 계정 정보만 읽는다. 카드 구매, 메일 발송, 키 폐기/새 제한 저장은 하지 않는다. 분류/한도/사용량/초과 처리/알림/모바일 제한 형식의 확인 여부와 출처를 operations 문서에 남긴다. 미확인 항목은 완료 처리하지 않는다.
- [ ] `flutter test --no-pub test/features/ux_settings_safety_test.dart`와 `python3 scripts/verify_prd_trd.py`로 실제 안내와 문서 구조를 검증한다.
- [ ] 해당 변경을 커밋한다. 메시지 `docs: 지도 통신과 광고 도입 전 운영 조건 명확화`.

### Task 5: 새 서명 후보와 최종 확인

**Files:** Modify `pubspec.yaml`, `scripts/run_quality_loop.sh`, `test/features/release_metadata_docs_test.dart`; Create `docs/release/2026-10-18-security-hardening-release.md`; 기존 audit 보고서에는 후속 조치 상태만 덧붙인다.

**Interfaces:** `0.9.4+18`, 기존 package `com.sanbo.sanbo`, 기존 인증서 SHA-256 `ceb40402d706589acee5da5df5a010c3dd5c2e9329cd3218961dfce56a6d38ac`.

- [ ] 선택한 후보와 새 evidence 문서를 기대하는 metadata 검사를 먼저 바꾸고 실패를 확인한다. 버전/게이트/증거를 함께 맞춰 커밋해 clean source를 만든다.
- [ ] private 환경으로 Task 3 wrapper를 실행한다. 전체 Flutter/분석/Android 서명 빌드와 산출물 검사는 wrapper 내부 quality loop에서 한 번 수행한다. 별도로 필요한 기존 native gate를 한 번 실행한다.
- [ ] 모든 ABI APK와 AAB에 Task 2 검사를 적용한다. 개인 이메일 입력도 비공개로 공급하고 APK 서명/버전/manifest, AAB 메타데이터와 체크섬을 확인한다. 원래 개인 경로가 없는 실제 바이트로 SEC-03 해결을 판단한다.
- [ ] 소유한 QA Android에서 v0.9.3 위에 교체 설치해 기록/백업 보존, 정상 CARTO 지도, 무효 키의 안내/기록 유지, 정상 상태로 복구를 확인한다. 실제 키/좌표가 없는 요약 증거만 Git에 남기고 시작한 에뮬레이터를 정리한다.
- [ ] 변경 diff를 검토한다. 독립 검토가 재위임 금지로 불가능하면 그 제한을 명시한다. PR을 만들 경우 attach_artifact를 호출한다. 실제 후보를 제공한 뒤 공개/병합에 필요한 사용자 결정을 받는다. 공개됐다면 익명 다운로드 해시와 보안 검사를 다시 적용한다.
- [ ] 보고서/체크리스트에 실제 통과, 남은 위험, 계정 미확인 범위를 적고 문서 커밋으로 마무리한다.

## 계획 자체 점검

설계 A는 Task 1, B는 Task 2/3/5, C는 Task 4/5, D는 Task 4에 대응한다. 실제 지도 회복/업데이트는 Task 5가 담당한다. 공개 클라이언트 키 비밀화, 신규 서버/광고, 계정 미확인 상태에서 강한 남용 방지 보장은 구현하지 않는다. 실행 방법은 기존 사용자 지시대로 이 세션 직접 구현을 유지한다.
