# 산보 배터리·저장 안정성·UX 고도화 설계

작성일: 2026-08-06
대상 기준선: v0.7.0 (`f9cfc5c`)
범위: Android 우선 패치 릴리스

## 1. 목표와 제약

이번 작업은 기존 사용자의 기록과 업데이트 경로를 보존하면서, 장시간 산책 중
데이터 저장 경계·배터리 요청·권한 안내·화면 상태를 고도화한다.

반드시 지키는 제약:

- SQLite 스키마와 기존 백업 포맷을 불필요하게 변경하지 않는다.
- 기존 application ID와 릴리스 서명 인증서 호환성을 유지한다.
- 기존 추적 목표 주기(절전 20초, 균형 8초, 정밀 4초)와 거리 필터를 바꾸지 않는다.
- Android 동작을 먼저 개선하고, iOS 위치 수집 정책은 이번 작업에서 변경하지 않는다.
- 알림 실패는 위치 기록 실패로 취급하지 않는다.

## 2. 현재 위험과 원인

### 2.1 저장 경합

`SessionController`의 체크포인트·샘플 묶음 flush는 unawaited maintenance로 시작된다.
사용자가 같은 시점에 종료하거나 버리면 `_pendingPersist`와 SQLite 쓰기가 서로 다른
비동기 흐름에서 진행될 수 있다. 최종화 transaction 뒤에 이전 batch가 도착하면
완료 세션에 오래된 원본 행이 재삽입될 수 있고, discard 뒤에는 삭제한 샘플이
되살아날 수 있다.

### 2.2 권한 UX와 seed 요청

Android 최초 시작에서 알림 권한을 위치 권한보다 먼저 요청한다. 알림은 기록의
필수 조건이 아니므로 사용자에게 목적이 거꾸로 전달된다. 또한 첫 위치 seed와
fallback에 공통 `LocationSettings`를 사용해 현재 모드보다 높은 정확도 요청이
발생할 수 있다.

### 2.3 상태 표현

백그라운드 복귀·자동 종료·저장 실패가 동일한 라이브 상태 전환과 인접해 있어,
늦게 완료된 비동기 결과가 현재 화면의 busy/error 상태를 덮어쓰지 않는지에 대한
명시적 회귀 기준이 부족하다.

## 3. 설계

### 3.1 단일 유지보수 큐와 세션 세대

`SessionController`에 다음 상태를 추가한다.

- 실행 중인 maintenance를 나타내는 공유 Future/직렬 큐
- 종료 시작 여부와 세션 세대(token 또는 동일한 단조 식별자)
- 마지막 flush 실패 batch를 보존하는 pending 상태

모든 maintenance 요청은 같은 큐를 통과한다. 이미 실행 중인 요청이 있으면 새
요청은 중복 실행하지 않고, 큐 뒤에서 한 번만 따라잡는다.

`stop()` 순서:

1. 종료 세대를 닫고 새 sample/maintenance 반영을 차단한다.
2. 현재 maintenance가 끝날 때까지 기다린다.
3. 남은 pending 샘플을 세션 세대 검증 후 한 번 flush한다.
4. DB 샘플과 메모리 샘플을 병합해 기존 `finalizeSession()` transaction으로 최종화한다.
5. 성공하면 세션 버퍼와 세대 상태를 폐기한다.
6. 실패하면 active 세션과 pending 샘플을 보존하고 재시도 가능한 복구 상태를 유지한다.

`discardActive()`도 같은 종료 세대 차단과 maintenance 대기를 거친 뒤 세션을
삭제한다. 삭제 완료 이후 어떤 늦은 callback도 샘플을 삽입할 수 없어야 한다.

### 3.2 배터리·권한

`GeolocatorLocationEngine.requestPermission()`은 위치 서비스·위치 권한을 먼저
확인/요청하고, 위치 권한이 granted일 때만 Android 알림 권한을 요청한다. 알림
거절은 기록을 중단시키지 않으며, 실제 알림 표시는 기존처럼 best-effort다.

첫 위치 seed와 Android fallback의 `getCurrentPosition`에도 현재 모드에 대응하는
`AndroidSettings`를 사용한다. 정확도, 거리 필터, 간격, `forceLocationManager`
정책을 일관되게 적용하되, seed의 time limit만 짧은 일회성 값으로 둔다.

기존 stream 수집 주기와 FGS 설정은 유지한다. 백그라운드에서는 native 수집,
checkpoint, safety guard만 유지하고 화면 상태 발행은 foreground 복귀 때 한 번
동기화한다.

### 3.3 UI/UX 상태 규칙

- GPS 샘플이 없는 동안은 `GPS 잡는 중`/첫 위치 대기 안내를 유지한다.
- 일반 기록 중, 자동 종료 경고, 저장 중, 저장 실패 복구를 서로 다른 상태로 표현한다.
- 저장·버리기·데이터 관리 작업이 진행 중이면 관련 CTA를 비활성화하고 spinner를
  표시한다.
- 늦은 성공/실패 callback은 현재 세션 세대가 맞을 때만 화면 상태를 변경한다.
- 백그라운드 복귀 시 시간·거리·속도·정확도·경고를 한 번에 갱신한다.

## 4. 데이터 흐름과 오류 처리

위치 stream → `_onSample` → 메모리 buffer/pending → 단일 maintenance queue →
SQLite checkpoint → stop 시 finalization transaction 순서를 유지한다.

SQLite write가 실패하면 해당 batch는 메모리에 남기고 다음 maintenance 또는 stop
재시도에서 다시 쓴다. 최종화가 실패하면 세션을 완료로 표시하지 않고 사용자가
홈 화면에서 저장을 재시도할 수 있게 한다. 알림·지도·장소 보강 실패는 핵심 GPS
기록을 실패시키지 않는다.

## 5. 테스트 전략

새 회귀 테스트:

- maintenance flush 지연 중 stop을 호출해도 샘플이 중복·유실되지 않는다.
- finalization 완료 뒤 늦은 maintenance callback이 샘플을 재삽입하지 않는다.
- discard 완료 뒤 active 세션과 샘플이 남지 않는다.
- 저장 실패 후 재시도하면 동일 세션이 완료된다.
- Android 권한 요청 순서는 위치 → 알림이며, 알림 거절 후에도 위치 시작 경로가 유지된다.
- batterySaver/balanced/highAccuracy seed 요청이 각 모드 설정을 사용한다.
- 백그라운드 복귀가 한 번의 최신 snapshot을 게시하고 자동 종료 경고를 잃지 않는다.

기존 회귀 게이트도 다시 실행한다:

- `flutter analyze`
- `flutter test --concurrency=1`
- Android debug APK
- Android release split APK(로컬 서명 설정이 있는 환경)

## 6. 비목표와 후속 과제

- Android native 별도 영속 큐/완전한 native foreground service 재설계
- iOS 자동 일시정지 정책 변경
- 새로운 DB 스키마·클라우드 동기화·백업 암호화
- 사용자별 실제 배터리 퍼센트의 코드 기반 보장

실기기 Galaxy에서 동일 경로·화면 꺼짐·60분 조건으로 모드별 배터리 측정을
후속 검증 과제로 남긴다.
