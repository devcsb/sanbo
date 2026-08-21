# 고속 이동 경고와 산책 구간 제외 설계

작성일: 2026-08-21
대상 기준선: v0.7.2
범위: 진행 중 세션의 고속 이동 감지, 완료 세션의 구간 제외와 통계 재계산, Android와 iOS 알림

## 1. 목표와 성공 기준

사용자가 산책을 마친 뒤 기록 종료를 잊고 차량이나 지하철로 이동하더라도 그 이동이
산책 기록에 계속 포함될 가능성을 낮춘다. 진행 중에는 사람의 걷기나 달리기로 보기
어려운 속도가 충분히 오래 이어질 때 종료 여부를 확인하고, 기록을 저장한 뒤에는
잘못 포함된 연속 구간을 사용자가 직접 제외하거나 다시 복원할 수 있게 한다.

성공 기준은 다음과 같다.

- 자동 GPS 필터를 통과한 신뢰 가능한 위치만 고속 이동 판단에 사용한다.
- 최신 2분 안에서 시속 28.8km 이상인 신뢰 구간이 누적 60초에 도달하면 한 번 경고한다.
- 고속 이동만으로 기록을 자동 종료하지 않는다.
- 경고 뒤 저속 회복 조건을 충족하기 전에는 같은 고속 이동으로 다시 경고하지 않는다.
- 앱이 화면에 있을 때는 `기록 종료`와 `계속 기록`을 바로 선택할 수 있다.
- 앱이 백그라운드에 있을 때는 Android와 iOS 모두 시스템 알림을 표시한다.
- 완료 기록의 연속된 활동 구간을 산책에서 제외하고 같은 화면에서 제외를 취소할 수 있다.
- 사용자 제외 원본은 `route_exclusions`에 저장하고 자동 GPS 필터 원본인
  `location_samples.is_filtered_out`은 변경하지 않는다.
- 제외 뒤 지도, 거리, 유효 시간, 이동 시간, 정지 시간, 평균 속도, 유효 샘플 수,
  분 단위 활동, 기록 화면 합계와 일별 합계를 같은 기준으로 갱신한다.
- 제외 구간의 앞뒤 좌표를 하나의 선분으로 잇지 않는다.
- 제외 상태, 분 단위 파생 상태, 세션 집계는 하나의 SQLite 트랜잭션에서 모두
  반영되거나 모두 롤백된다.

## 2. 설계 원칙

현재 앱의 계층을 유지한다. `SessionGuard`는 판단만 하고, `SessionController`는 화면
상태와 알림을 조정하며, `SessionPipeline`은 원시 샘플에서 분 기록과 세션 집계를
계산한다. `WalkRepository`는 SQLite 트랜잭션과 백업 형식을 책임진다. 상세 화면은
저장소 명령을 호출한 뒤 기존 `historyTickProvider`를 올려 상세 기록, 전체 기록 합계,
일별 합계를 함께 새로 읽는다.

사용자 제외는 자동 필터 값을 덮어쓰는 방식으로 구현하지 않는다. 별도 제외 레코드를
원본으로 삼고 분 기록의 제외 ID만 타임라인 표시와 복원을 위한 파생 상태로 둔다.
완료 기록을 편집할 때 `SampleFilter`를 다시 실행하지 않으며 저장된
`location_samples.is_filtered_out`을 자동 필터의 단일 원천으로 사용한다. 이 구분으로
세션을 완료한 당시의 GPS 품질 판단과 사용자의 편집 의도를 각각 보존한다.

완료 세션의 `started_at`과 `ended_at`은 실제 기록 시작과 종료 시각으로 보존한다.
`duration_s`는 산책에 포함된 유효 시간으로 바꾸며, 전체 기록 시간에서 서로 겹치지
않는 사용자 제외 구간의 길이를 뺀 값으로 계산한다. 이동 시간과 정지 시간은 신뢰할
수 있는 인접 좌표 사이에서만 계산하므로 둘의 합이 유효 시간보다 작을 수 있다. GPS
공백은 현재와 같이 관측되지 않은 시간으로 남는다.

## 3. 전체 구조와 구성 요소

### 3.1 고속 이동 판단

`SessionGuardPolicy`에 다음 정책값을 추가한다.

- 고속 기준 `8.0 m/s`, 시속 28.8km
- 판단 창 `120초`
- 경고에 필요한 고속 누적 시간 `60초`
- 저속 회복 기준 `4.0 m/s`, 시속 14.4km
- 재활성화에 필요한 연속 저속 시간 `30초`
- 고속 판단 최대 수평 정확도 `80m`
- 인접 위치의 최대 허용 공백은 기존 `trustedLocationGap` 사용

`SessionGuard`는 `observe(sample, observedAt)`으로 위치와 앱 수신 시각을 함께 받으며,
최근 신뢰 선분을 시간순 deque로 보관한다. 각 항목은 샘플 시작 시각, 샘플 종료 시각,
수신 시각, 계산 속도, 고속 여부를 가진다. `observedAt`은 테스트에서 주입하는 clock과
같은 절대 시각을 사용한다. 새 위치를 관찰할 때 `observedAt - 120초`를 최근 창 시작으로
삼아 샘플 시각 구간과 겹치는 부분만 합산한다. 합계가 60초에 도달하면
`highSpeedWarning`을 한 번 반환하고 고속 경고 latch를 잠근다.

라이브 `SampleFilter`가 거부한 fix는 `SessionGuard.interruptHighSpeedContinuity()`로 기존
고속 누적을 끊는다. 복구 시에는 저장된 샘플에 `SampleFilter.apply`를 적용한 marked
결과를 `rebuildHighSpeedState`에 전달해 라이브와 같은 필터 경계를 유지한다.

`SessionController`는 해당 결정을 받아 화면 경고 상태를 `highSpeed` 종류로 저장한다.
화면에 있을 때는 경고 배너를 갱신하고, 백그라운드일 때는 시스템 알림도 보낸다.
고속 경고는 자동 종료 경로를 호출하지 않는다. 기존 30분 정지 제한과 5시간 전체
제한은 그대로 유지하며, 그 제한에 도달한 경우에는 기존 자동 저장과 종료 정책이
고속 경고보다 우선한다.

기존 `autoStopWarning` 문자열과 `canContinueAfterWarning` 불리언은 경고 종류, 문구,
가능한 동작을 함께 가진 `SessionWarning? activeWarning`으로 바꾼다. 정지 경고,
전체 시간 경고, 고속 경고를 같은 문자열 상태에 억지로 맞추지 않아 각 버튼과 취소할
시스템 알림을 종류별로 결정할 수 있게 한다. guard 평가는 신뢰할 수 있는 새 샘플을
받을 때 즉시 실행하고, 기존 ticker와 maintenance 평가는 시간 제한 보호용으로 유지한다.
경고 latch는 종류별로 독립적이며 고속 경고를 닫아도 정지 경고나 전체 시간 경고의
발행 여부는 바뀌지 않는다.

세션 종료와 discard는 현재 화면에 보이는 경고 종류와 무관하게 4101과 4103을 모두
취소한다. 고속 경고에서 종료한 경우에도 일반 종료와 같이 기록 갱신 tick을 올리고
성공한 세션 상세 화면으로 이동한다.

### 3.2 사용자 제외 모델

새 불변 모델 `RouteExclusion`은 다음 값을 가진다.

```dart
class RouteExclusion {
  const RouteExclusion({
    required this.id,
    required this.sessionId,
    required this.startAt,
    required this.endAt,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final DateTime startAt;
  final DateTime endAt;
  final RouteExclusionReason reason;
  final DateTime createdAt;
}

enum RouteExclusionReason { vehicle }
```

제외 범위는 `[startAt, endAt)` 반개구간이다. 시작은 포함하고 끝은 포함하지 않아 서로
맞닿은 구간의 샘플 소유권이 모호해지지 않게 한다. 현재 상세 화면의 편집 단위인
`ActivitySegment`를 선택 단위로 사용한다. 하나의 segment는 하나 이상의 연속된 분
기록이므로 사용자는 한 번의 동작으로 합쳐진 차량 이동 구간 전체를 제외할 수 있다.
범위 시작은 `max(firstWindowStart, session.startedAt)`, 범위 끝은
`min(lastWindowStart + 1분, session.endedAt)`으로 clamp한다. `ActivitySegment`는 분 키와
별도로 실제 `startAt`, `endExclusive`를 가지며 저장소 검증과 지도 강조가 함께 쓴다.
모든 비교는 파싱한 `DateTime`의 절대 시각으로
수행하며 문자열이나 로컬 달력 표시값을 직접 비교하지 않는다. `route_exclusions`의
모든 시각은 저장 전에 UTC로 바꾸고 ISO 8601 문자열로 기록한다.

임의의 초 단위 핸들 편집은 제공하지 않는다. 사용자가 더 넓은 범위를 제거하려면
인접 segment를 각각 제외한다. 저장소는 transaction snapshot의 분 기록에서
authoritative segment를 다시 만들고 요청이 정확히 하나와 일치하는지 확인한다. 임의의
같은 분 부분 범위와 불연속 분 선택은 거부한다. 새 범위가 기존 제외 범위와 겹치면 거부하고,
정확히 맞닿은 범위는 별도 제외 레코드로 유지한다. 따라서 각 편집을 독립적으로
취소할 수 있다.

`LocationSample` 모델에는 사용자 제외 필드를 추가하지 않는다. `location_samples`
스키마와 행도 변경하지 않는다. 기존 `isFilteredOut`은 세션 완료 시 결정된 자동 GPS
필터 결과만 뜻한다.
`MinuteWindow`에는 nullable `userExclusionId`와 `isUserExcluded` getter를 추가한다.
`SegmentMerger`는 제외 ID가 같은 연속 분만 하나의 제외 segment로 합치며 서로 다른
편집 레코드는 합치지 않는다.

### 3.3 공용 경로 분할기

새 순수 도메인 함수 `RoutePartitioner.partition`을 지도, 경로 재생, 세션 집계가 함께
사용한다. 입력은 저장된 `LocationSample` 목록, UTC로 정규화하고 시작 시각순 정렬한
서로 겹치지 않는 `RouteExclusion` 목록, `trustedLocationGap`이다. 출력은 시간순
`RouteFragment` 목록이며 각 fragment는 연결해도 되는 샘플과 선분만 가진다. 이 함수는
DB, Flutter, 플랫폼 API에 의존하지 않는다.

분할기는 다음 규칙을 한곳에서 적용한다.

- 저장된 `isFilteredOut`이 true인 샘플은 자동 필터 제외로 처리한다.
- 샘플 절대 시각이 `[exclusion.startAt, exclusion.endAt)` 안이면 경로에서 제외한다.
- 두 보존 샘플의 시각 선분이 제외 반개구간과 조금이라도 교차하면 두 점을 연결하지
  않는다. 두 끝점이 모두 제외 밖이어도 사이에 제외 범위가 있으면 새 fragment를 만든다.
- 인접 샘플 시각 차이가 0 이하이거나 `trustedLocationGap`보다 크면 새 fragment를 만든다.
- 좌표, 시각, 거리 계산값이 유효하지 않으면 해당 연결을 만들지 않는다.
- 양수인 1ms 미만 시각 차이는 microseconds로 속도를 계산하며 유한 속도만 연결한다.
- 1.5m 미만 선분은 fragment와 관측 시간에는 남기되 거리에는 더하지 않는다.
- 세션 종료 시각과 같은 샘플은 마지막 실제 분에 포함한다.

`RoutePartitionResult`는 fragments 외에 포함된 유효 샘플 목록과 분 단위 집계가 사용할
유효 선분 목록을 제공한다. 지도와 재생은 fragments를 그대로 쓰고,
`SessionRollup`은 같은 fragment의 선분만 합산한다. `WindowAggregator`도 같은 유효
샘플과 선분을 분 경계로 잘라 거리와 이동 상태를 계산한다. 따라서 제외 경계 처리,
GPS 공백 처리, 자동 필터 처리가 화면과 모든 통계에서 달라질 수 없다.

### 3.4 완료 기록 재계산

`SessionPipeline`에 완료 기록 재계산 경로를 추가한다. 입력은 완료 세션, 저장된 필터
상태를 가진 샘플, 전체 제외 범위, 기존 분 기록의 사용자 메타데이터다. 결과는 다음을
포함한다.

- 제외 분을 포함해 전체 기록 시간을 덮는 새 `MinuteWindow` 목록
- `RoutePartitioner`가 만든 지도와 재생용 경로 조각 목록
- 제외 시간을 반영한 `SessionRollupResult`

완료 기록 재계산은 `SampleFilter`를 호출하지 않는다. 세션 완료 시 저장된
`location_samples.is_filtered_out`을 그대로 읽어 `RoutePartitioner`에 전달한다. 제외와
복원을 반복해도 자동 필터 결과나 샘플 행은 변경하지 않는다.

제외된 분 기록은 타임라인과 복원 동작을 위해 삭제하지 않는다. `userExclusionId`를
설정하고 거리, 평균 속도, 최대 속도, 유효 샘플 수를 0으로 만든다. 품질은 `gap`,
사유는 `user_excluded`로 기록한다. 원시 샘플 수는 진단과 백업 검증을 위해 보존한다.
활동 라벨, 사용자 메모, 사용자 확정, 장소 연결은 같은 `window_start`의 기존 값에서
복사한다. 상세 화면에서는 이 라벨보다 `산책에서 제외됨` 상태를 우선 표시한다.

포함된 분은 `RoutePartitioner` 결과로 다시 집계하고 활동을 추론한다. 기존 분 기록의
사용자 라벨, 메모, 사용자 확정, 장소 연결은 `window_start`를 키로 다시 결합해 사용자의
다른 편집을 잃지 않는다. 제외를 취소한 분도 같은 저장 샘플과 저장 필터 상태에서 다시
계산한 뒤 같은 메타데이터를 복원한다.

세션 집계는 다음 규칙을 사용한다.

- `duration_s`는 `ended_at - started_at`에서 제외 범위 합계를 뺀다.
- `total_distance_m`, `moving_time_s`, `stationary_time_s`는 `RoutePartitioner`가 만든
  같은 fragments의 선분만 사용한다.
- `avg_speed_mps`는 재계산 거리 나누기 재계산 이동 시간이다.
- `valid_sample_count`와 `median_accuracy_m`은 partitions에 포함된 유효 샘플만 사용한다.
- 계산 결과가 음수이거나 비유한 값이면 저장을 중단해 트랜잭션을 롤백한다.

## 4. 고속 감지 데이터 흐름과 상태 전이

신뢰 선분은 두 위치가 모두 다음 조건을 만족할 때만 만든다.

- 좌표와 시각이 유효하고 시간순이다.
- 진행 중 세션의 기존 incremental `SampleFilter`가 두 위치를 자동 제외하지 않았다.
- 두 위치의 수평 정확도가 모두 존재하고 유한하며 80m 이하이다.
- 시각 차이가 0보다 크고 `trustedLocationGap` 이하이다.
- haversine 거리와 시각 차이로 계산한 속도가 유한하다.
- 각 샘플 시각이 해당 `observedAt`보다 30초 이상 오래되지 않았고 5초를 넘겨 미래가
  아니다.

수신 시각은 고속 판단의 현재 시각이다. deque를 정리할 때 샘플의 최신 timestamp가
아니라 매 `observe` 호출의 `observedAt - 120초`를 창 경계로 사용한다. 선분의 샘플
시각 구간이 이 창과 겹치는 길이만 고속 시간에 더한다. `observedAt`이 이전 호출보다
과거면 해당 관찰을 거부한다. 운영체제가 과거 위치를 묶어서 늦게 전달해도 30초보다
오래된 샘플은 anchor나 deque에 넣지 않으므로, 오래전에 끝난 차량 이동 60초가 한꺼번에
들어와 즉시 경고하는 오탐을 막는다.

위치 제공자의 `speedMps`는 화면의 순간 속도 표시에 계속 사용할 수 있지만 고속 누적
시간의 근거로 사용하지 않는다. 좌표로 검증되지 않은 단일 속도 값 때문에 경고가
발생하지 않게 하기 위해서다. GPS 수신 공백은 고속 시간에도 저속 회복 시간에도
더하지 않는다. 지하 구간에서 위치를 전혀 받지 못한 경우에는 추측으로 경고하지 않고,
다시 신뢰할 수 있는 좌표가 들어온 뒤의 이동만 판단한다.

상태 전이는 다음과 같다.

1. `armed` 상태에서 최신 2분의 고속 누적 시간이 60초 미만이면 계속 관찰한다.
2. 60초에 도달하면 `warned`로 바꾸고 한 번 경고한다.
3. 사용자가 `계속 기록`을 누르면 화면 경고와 해당 시스템 알림만 닫는다. 상태는
   `warned`로 유지해 같은 차량 이동 중 중복 경고하지 않는다.
4. `warned` 상태에서 4.0m/s 이하인 신뢰 선분이 공백 없이 연속 30초 쌓이면
   `armed`로 돌아간다.
5. 4.0m/s 초과 8.0m/s 미만인 선분은 회복 시간을 0으로 되돌리지만 새 고속 누적
   시간에는 더하지 않는다.
6. 신뢰하지 못하는 위치나 수신 공백은 회복을 완료시키지 않으며 기존 경고 latch도
   해제하지 않는다.
7. 새 세션 시작, 세션 종료, 복구 세션 재구성 때 guard 상태를 해당 세션 데이터에
   맞게 초기화한다.

한 번의 `evaluate`에서 여러 조건이 만족되면 `durationLimit`, `stationaryLimit`,
`durationWarning`, `stationaryWarning`, `highSpeedWarning` 순서로 하나만 반환한다.
각 경고의 latch와 누적 상태는 독립적이므로 우선순위가 낮아 이번 평가에서 반환되지
않은 고속 경고는 사라지지 않고 다음 평가에서 반환될 수 있다. 고속 이동으로 정지
관찰 창이 초기화돼도 고속 latch를 함께 초기화하지 않는다.

앱이 강제 종료된 뒤 활성 세션을 복구할 때 저장된 최근 샘플 중 현재 시각 기준 최신
2분만 진행 중 세션용 필터로 시간순 재구성하고 receipt freshness 조건을 적용한 뒤
마지막에 한 번 평가한다. 2분보다 오래됐거나 현재 수신 시각보다 30초 이상 오래된
위치는 버린다. 따라서 지연된 저장 샘플만으로 복구 직후 고속 60초를 새로 만들 수
없고, 이후 들어오는 신뢰 위치와 함께 조건을 다시 채운다. cold start가 이미 발행된
highSpeed 알림 탭에서 시작된 경우에는 5.2의 payload 계약에 따라 active session 복구와
최근 샘플 평가를 먼저 끝낸 뒤 경고를 재구성한다.

## 5. 화면과 알림 경험

### 5.1 진행 중 기록

고속 조건을 만족하면 홈의 진행 중 카드에 다음 안내를 표시한다.

`이동 속도가 매우 빨라요. 산책을 마쳤다면 기록을 종료해 주세요.`

안내에는 두 개의 명시적 동작을 둔다.

- `기록 종료`는 기존 사용자 종료 흐름을 호출해 원시 샘플을 저장하고 세션을 완료한다.
- `계속 기록`은 안내를 닫지만 고속 latch를 해제하지 않는다.

종료 동작이 진행되는 동안 두 버튼을 비활성화하고 기존 busy 표시를 사용한다. 종료가
실패하면 복구 가능한 세션 상태와 오류 안내를 유지한다. 고속 경고 자체에는 남은 시간,
자동 종료 표현, 위협적인 색상을 사용하지 않는다.

경고 영역은 접근성 live region으로 한 번 알리고 제목과 설명을 하나의 의미 단위로
읽는다. 버튼은 시각적 레이블과 같은 접근성 이름을 가지며 최소 48dp 터치 영역을
확보한다. 색상만으로 일반 상태와 경고 상태를 구분하지 않고 아이콘과 문구를 함께 쓴다.

### 5.2 백그라운드 시스템 알림

고속 경고 발생 시 앱이 백그라운드라면 `산책 기록을 계속할까요?` 제목과 위 안내를
시스템 알림으로 보낸다. 고속 알림은 고유 종류와 ID를 사용하므로 기존 장시간 정지,
5시간 제한, 완료 알림을 취소하지 않는다. 사용자가 앱에서 계속 기록하거나 종료하면
고속 알림만 취소한다.

알림 표시와 탭 전달에 필요한 최소 계약은 다음과 같다.

- Dart가 네이티브에 보내는 알림 payload는 `kind: highSpeed`를 포함한다.
- 사용자가 알림을 누르면 네이티브가 앱을 열고 MethodChannel로
  `notificationTapped({kind: highSpeed})` 이벤트를 Dart에 한 번 전달한다.
- Flutter engine이 준비되기 전의 cold start 탭은 네이티브가 한 건 보관했다가 handler
  등록 뒤 전달한다.
- Dart의 알림 이벤트 handler는 router를 홈으로 전환한다. 현재 active session의
  `activeWarning`이 highSpeed로 남아 있으면 홈에서 `기록 종료`와 `계속 기록`을 표시한다.
- cold start에서는 먼저 active session과 freshness를 만족하는 최근 샘플을 복구해
  guard를 평가한다. 그 뒤 보관된 highSpeed 탭 이벤트가 있고 active session이 계속
  존재하면, 이미 발행된 알림을 근거로 `activeWarning.highSpeed`를 재구성하고 홈으로
  이동한다. 세션이 끝났다면 오래된 동작을 만들지 않고 홈만 연다.

이 계약은 highSpeed 한 종류만 다루며 범용 deep link나 네이티브 알림 버튼 체계는
추가하지 않는다.

Android는 현재 `sanbo/session_notifications` 채널을 확장해 알림 종류를 전달하고,
기존 알림 채널과 `POST_NOTIFICATIONS` 권한 흐름을 사용한다. iOS는 같은 MethodChannel
계약을 `AppDelegate`의 Flutter engine 등록 시 연결하고 `UNUserNotificationCenter`로
권한 요청, 표시, 종류별 취소, 탭 이벤트 전달을 구현한다. 알림 권한 요청은 첫 산책을
시작할 때 fire-and-forget 비치명 작업으로 실행한다. 위치 권한 확인, location engine
시작, 세션 생성은 알림 권한 응답을 기다리지 않는다. 요청이 느리거나 실패하거나
거부돼도 기록 시작을 지연하거나 실패시키지 않는다.

iOS에서 앱이 화면에 있을 때 시스템 배너를 중복 표시하지 않고 앱 내 경고만 쓴다.
Android도 같은 규칙을 적용한다. 시스템 알림 API 실패는 기록 흐름을 실패시키지 않으며,
플랫폼 서비스는 성공, 권한 거부, 미지원 상태를 구분해 로그만 남긴다.

### 5.3 완료 기록의 구간 제외

상세 화면의 기존 segment 편집 시트에 다음 동작을 추가한다.

- 포함된 segment에는 `산책에서 제외`를 표시한다.
- `차량 이동`으로 추정되거나 사용자가 차량으로 확정한 segment에는 같은 동작을 첫
  항목으로 보여 발견하기 쉽게 한다.
- 다른 활동 segment에서도 사용자가 잘못 포함된 이동을 제거할 수 있다.
- 제외 전 확인 대화상자는 대상 시간 범위와 현재 거리, 이 동작이 기록 전체 통계를
  다시 계산한다는 점을 보여 준다.
- 제외된 segment는 타임라인에서 삭제하지 않고 흐리게 표시하며 `산책에서 제외됨`
  배지와 `제외 취소` 동작을 제공한다.

제외 명령 중에는 상세 화면의 기존 command busy 상태로 다른 편집, 삭제, 내보내기를
막는다. 성공하면 상세 provider와 기록 provider가 새 데이터를 읽고, 선택된 지도 강조와
재생 위치를 안전한 범위로 초기화한다. 실패하면 현재 화면 데이터를 그대로 유지하고
재시도 안내를 표시한다.

제외된 segment의 접근성 레이블에는 시간 범위, 제외 상태, 복원 가능 여부를 포함한다.
확인 대화상자의 기본 포커스는 취소에 두며, 제외와 제외 취소 버튼은 결과를 구체적으로
설명하는 이름을 사용한다.

## 6. 지도와 재생 경로

현재 `RouteMap`의 단일 points 입력을 `RoutePartitioner`가 반환한 여러 경로 조각을
받는 입력으로 확장한다. 지도는 각 조각을 별도 polyline으로 그리며 조각의 끝과 다음
조각의 시작을 절대 잇지 않는다. 경로 재생과 진행 지점 계산도 같은 fragments를
사용한다. UI에서 다시 필터하거나 독자적으로 공백을 판단하지 않는다. 제외 전 확인
상태에서는 기존 강조 색으로 대상 구간을 보여 줄 수 있지만, 저장 뒤 기본 지도와
사용자에게 보이는 경로에서는 제외된 좌표를 사용하지 않는다.

기록에 남은 조각이 하나도 없으면 지도는 경로 없음 상태를 표시하고 통계는 거리 0,
이동 시간 0, 정지 시간 0, 평균 속도 0, 유효 샘플 수 0으로 저장한다. 세션 자체는
완료 기록으로 유지되며 제외 취소를 할 수 있는 타임라인도 남긴다.

## 7. SQLite 스키마와 마이그레이션

DB 스키마 버전을 3에서 4로 올리고 다음 테이블을 추가한다.

```sql
CREATE TABLE route_exclusions (
  id TEXT PRIMARY KEY NOT NULL,
  session_id TEXT NOT NULL,
  start_at TEXT NOT NULL,
  end_at TEXT NOT NULL,
  reason TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE INDEX idx_route_exclusions_session_range
ON route_exclusions(session_id, start_at, end_at);
```

`minute_windows`에만 nullable
`user_exclusion_id TEXT REFERENCES route_exclusions(id) ON DELETE SET NULL` 열을 추가한다.
값이 null이면 산책에 포함되고, 값이 있으면 타임라인에서 해당 사용자 제외 레코드에
속한다. `location_samples` 스키마와 행은 변경하지 않으며 기존 `is_filtered_out`의
의미와 값을 자동 필터 원본으로 보존한다.

3에서 4로 올릴 때 먼저 `route_exclusions`를 만들고 `minute_windows` 열과 인덱스를
추가한다. 기존 분 기록의 새 열은 모두 null이므로 기존 기록과 집계가 변하지 않는다.
마이그레이션은 SQLite의 기존
upgrade 트랜잭션 안에서 수행하고, 열린 뒤 `quick_check`와 테스트의 `foreign_key_check`
로 무결성을 확인한다. 신규 설치용 스키마와 순차 업그레이드 스키마가 정확히 같은 열,
외래 키, 인덱스를 갖도록 검증한다.

저장소는 완료 세션에만 제외와 복원을 허용한다. 세션 범위를 벗어나거나 길이가 0인
범위, 기존 범위와 겹치는 범위, 존재하지 않는 segment, 알 수 없는 reason은 쓰기 전에
거부한다.

## 8. 원자적 제외와 복원

`WalkRepository`는 `excludeRouteSegment`와 `restoreRouteExclusion` 명령을 제공한다.
두 명령은 각각 하나의 `_db.transaction` 안에서 다음 순서로 실행한다.

1. 대상 완료 세션, 전체 원시 샘플, 기존 분 기록, 전체 제외 레코드를 같은 transaction
   executor로 읽는다.
2. snapshot의 분 기록과 세션 경계로 authoritative segment를 재구성하고 요청과 정확히
   일치하는지 확인한 뒤 절대 시각으로 유효성과 겹침을 검사하고, 제외 또는 복원 후의
   `RouteExclusion` 목록을 메모리에서 구성한다.
3. 저장된 `is_filtered_out`을 바꾸지 않은 샘플과 새 제외 목록을 `SessionPipeline`에
   전달해 분 기록, 경로 조각, 세션 집계를 다시 계산한다.
4. 제외 명령이면 UTC ISO 시각을 가진 새 `route_exclusions` 행을 삽입한다.
5. 대상 세션의 `minute_windows`를 새 결과로 교체한다. 제외된 분만 해당
   `user_exclusion_id`를 가진다.
6. `sessions`의 거리, 유효 시간, 이동 시간, 정지 시간, 평균 속도, 유효 샘플 수,
   중앙 정확도를 갱신한다.
7. 복원 명령이면 분 기록 참조가 사라진 대상 `route_exclusions` 행을 삭제한다.

`location_samples`는 이 트랜잭션에서 읽기만 하며 UPDATE나 교체 대상이 아니다.

어느 행 갱신 수가 예상과 다르거나 파이프라인이 유효하지 않은 결과를 만들거나 DB
쓰기가 실패하면 예외를 전파해 전체 변경을 롤백한다. 화면은 트랜잭션 성공 뒤에만
`historyTickProvider`를 올린다. 따라서 상세 지도와 세션 집계가 서로 다른 버전을
잠깐 표시하지 않는다.

분 기록 교체 시 기존 사용자 라벨, 메모, 장소 ID를 보존해야 하므로 저장소는 재계산
전에 이를 `window_start`별로 수집한다. 삭제된 장소를 다시 만들지 않으며, 존재하는
외래 키만 재연결한다. 제외 취소를 여러 번 반복해도 원시 샘플을 기준으로 계산하므로
거리와 시간의 반올림 오차가 누적되지 않는다.

## 9. 백업 형식

전체 백업 스키마를 1에서 2로 올린다. `AppBackupArchive`에
`backupSchemaVersion`을 추가해 decode한 버전을 import가 끝날 때까지 보존한다.
버전 2는 `route_exclusions` 테이블과 분 기록의 `user_exclusion_id`를 포함한다.
`location_samples` 형식은 버전 1과 같다. 내보내기는 완료 세션에 속한 제외 레코드만
기록하며, 세션, 제외, 장소, 분 기록의 외래 키 관계를 검증한다.

가져오기는 백업 버전 1과 2를 모두 지원한다.

- codec은 먼저 `backup_schema_version`을 1 또는 2로 검증하고 그 값을 archive에
  보존한 뒤 버전별 required tables를 적용한다.
- 버전 1 required tables는 `sessions`, `location_samples`, `minute_windows`, `places`다.
  제외 테이블이 없으므로 빈 `route_exclusions`와 모든 분 기록의 null
  `user_exclusion_id`를 정규화 결과에 합성한다.
- 버전 2 required tables는 버전 1의 네 테이블과 `route_exclusions`다. 분 기록에는
  `user_exclusion_id` 키가 반드시 있으며 값은 null 또는 문자열이어야 한다.
- 버전 2는 제외 범위가 세션 안에 있고 서로 겹치지 않는지 검증한다.
- 분 기록의 제외 ID가 같은 세션의 실제 제외 레코드를 가리키고 해당 분의 실제 범위가
  제외 범위 안에 있는지 검증한다.
- 새 세션을 가져올 때 sessions, route_exclusions, location_samples, places,
  minute_windows 순서로 하나의 기존 import 트랜잭션에 삽입한다.
- 이미 존재해 건너뛴 세션의 제외 레코드와 파생 행도 함께 건너뛴다.
- 더 새로운 백업 버전과 손상된 참조는 현재와 같이 전체 가져오기를 거부하고 롤백한다.

NDJSON 단일 세션 내보내기는 `schema_version: 2`로 올리고 제외 레코드와 각 분 기록의
제외 ID를 포함한다. 샘플 행에는 사용자 제외 필드를 추가하지 않는다.
기본 지도 경로와 사용자에게 보이는 요약은 제외 후 집계를 사용하되, 명시적 데이터
내보내기는 복원 가능성과 투명성을 위해 원시 좌표와 제외 상태를 함께 보존한다.

## 10. 오류 처리와 충돌 규칙

- 알림 권한 거부, 플랫폼 채널 미지원, 시스템 알림 실패는 비치명 오류다. 앱 내 경고와
  위치 기록은 계속 동작한다.
- 고속 guard가 판단할 만큼 신뢰 위치가 부족하면 경고하지 않는다. 불확실한 데이터를
  이동으로 단정하지 않는다.
- 여러 guard 조건이 동시에 가능하면 `durationLimit`, `stationaryLimit`,
  `durationWarning`, `stationaryWarning`, `highSpeedWarning` 순서로 처리하고 하나의 앱 내
  경고만 표시한다. 각 latch는 독립적으로 유지한다.
- 고속 경고가 떠 있는 동안 사용자가 직접 종료하면 고속 알림을 취소한 뒤 기존 종료
  흐름을 한 번만 실행한다.
- 상세 기록이 다른 화면에서 삭제되거나 변경돼 대상 제외 범위가 사라지면 명령을
  거부하고 최신 데이터를 다시 불러온다.
- 제외 트랜잭션 실패 시 메모리 provider를 무효화하지 않는다. 사용자는 변경 전 지도와
  통계를 계속 보며 재시도할 수 있다.
- 앱이 트랜잭션 도중 종료돼도 SQLite rollback으로 제외 레코드, 분 기록, 세션 집계가
  이전 일관된 상태로 돌아간다. 샘플은 애초에 쓰지 않는다.
- 제외 후 남은 샘플이 없거나 한 개뿐인 것은 유효한 결과다. 거리와 속도는 0으로
  정규화하고 기록과 복원 동작은 유지한다.

## 11. 테스트 전략

### 11.1 도메인 테스트

- 8.0m/s 미만은 경고하지 않고 정확히 8.0m/s인 신뢰 선분은 고속 시간에 포함한다.
- 최신 120초 안의 고속 선분 누적이 59초면 경고하지 않고 60초면 한 번 경고한다.
- 창 경계에 걸친 선분은 120초 창과 겹치는 시간만 더한다.
- 고속 시간이 여러 신뢰 선분으로 나뉘어도 누적 60초면 경고한다.
- 자동 필터된 위치, 80m 초과 정확도, 역순 시각, 0초 간격, 긴 GPS 공백은 누적하지 않는다.
- `observedAt`보다 30초 이상 오래된 샘플과 5초를 넘겨 미래인 샘플을 거부한다.
- 최근 창은 sample timestamp의 최댓값이 아니라 `observedAt - 120초`로 정리한다.
- 60초가 넘는 과거 샘플 묶음을 한 번에 받아도 고속 경고를 만들지 않는다.
- 위치 제공자 속도만 높고 좌표 기반 속도가 낮으면 경고하지 않는다.
- 경고 뒤 계속 고속이어도 중복 경고하지 않는다.
- 4.0m/s 이하가 연속 29초면 latch를 유지하고 30초면 재활성화한다.
- 4.0m/s 초과 속도와 GPS 공백은 저속 회복 연속 시간을 끊는다.
- 여러 조건을 동시에 만족하면 지정한 다섯 단계 우선순위로 이벤트를 반환하고 각
  latch는 독립적으로 남는다.
- 새 세션과 복구 세션 초기화가 이전 세션 guard 상태를 누설하지 않는다.
- `RoutePartitioner`가 저장된 `is_filtered_out`, 제외 안의 샘플, 제외 범위와 교차하는
  선분, `trustedLocationGap`을 각각 올바르게 분할한다.
- 두 끝점이 제외 밖이고 30초 이내여도 그 선분이 제외 범위와 교차하면 연결하지 않는다.
- 지도, 재생, 거리, 이동 시간, 정지 시간이 같은 fragments를 소비한다.
- 여러 제외 범위와 경로 끝 제외에서 유효 시간과 모든 집계가 정확하다.
- 전부 제외, 샘플 없음, 단일 샘플 결과가 유한한 0값 집계를 만든다.

### 11.2 저장소와 마이그레이션 테스트

- 새 제외 레코드, 분 기록 제외 ID, 세션 집계가 한 번에 저장된다.
- 제외 취소가 원시 좌표에서 기존 거리와 시간을 복구한다.
- 완료 기록 재계산이 `SampleFilter`를 호출하지 않고 저장된 `is_filtered_out`을 그대로
  사용하며, 제외와 취소 전후의 `location_samples` 행이 바뀌지 않는다.
- 기존 사용자 활동 라벨, 메모, 장소 연결이 재계산 뒤에도 유지된다.
- 겹친 범위, 세션 밖 범위, 활성 세션, 존재하지 않는 제외 ID를 거부한다.
- 첫 분과 마지막 분 경계를 세션 시작과 종료로 정확히 clamp한다.
- offset이 다른 같은 절대 시각과 DST 경계에서도 범위를 UTC ISO로 저장하고 절대 시각으로
  비교한다.
- 제외 삽입, 분 기록 교체, 세션 갱신 각 단계에 강제 실패를 넣어 모든 쓰기 테이블이
  변경 전 상태로 롤백되는지 검증한다.
- v3 DB를 v4로 올렸을 때 기존 세션, 샘플, 분 기록, 장소와 집계가 그대로다.
- 신규 v4 DB와 업그레이드한 v4 DB의 스키마와 외래 키가 같다.
- archive가 `backupSchemaVersion`을 보존하고 버전 1과 2에 서로 다른 required tables와
  기본값 정규화를 적용한다.
- 백업 v2 왕복이 제외와 통계를 보존하고, v1 백업은 제외 없는 기록으로 정상 복원된다.
- NDJSON `schema_version: 2`가 제외 레코드와 분 기록 제외 ID를 왕복하고 샘플 형식은
  변경하지 않는다.
- 손상된 제외 참조, 겹친 범위, 더 새로운 백업 버전은 전체 가져오기를 롤백한다.

### 11.3 컨트롤러와 화면 테스트

- foreground 고속 경고에 안내, 기록 종료, 계속 기록 동작이 표시된다.
- 계속 기록은 화면과 고속 알림을 닫지만 guard latch를 재활성화하지 않는다.
- 기록 종료를 누르면 자동 종료가 아닌 기존 사용자 종료 흐름이 정확히 한 번 실행된다.
- background 고속 경고는 시스템 알림을 보내고 foreground에서는 중복 알림을 보내지 않는다.
- 알림 권한 요청이 끝나지 않거나 거부돼도 기록 시작 완료를 지연하거나 실패시키지 않는다.
- warm start 알림 탭이 `kind: highSpeed` 이벤트를 Dart에 전달하고 router가 홈으로 이동한다.
- cold start 알림 탭을 engine 준비까지 한 번 보관하고 active session 복구와 최근 샘플
  평가 뒤 highSpeed 경고와 두 동작을 재구성한다.
- cold start에서 active session이 이미 끝났으면 stale 경고 동작을 만들지 않는다.
- 알림 권한 거부와 플랫폼 채널 실패가 기록 상태를 실패시키지 않는다.
- 기존 정지 경고, 30분 정지 종료, 4시간 45분 경고, 5시간 종료 회귀 테스트가 통과한다.
- 차량 segment의 편집 시트에서 제외 동작을 찾을 수 있고 확인 전에는 DB가 바뀌지 않는다.
- 성공 뒤 지도, 요약 카드, 타임라인, 전체 합계, 일별 합계가 갱신된다.
- 제외 segment가 타임라인에 남고 제외 취소로 복원된다.
- 처리 중 중복 탭을 막고 실패 시 기존 화면과 재시도 안내를 유지한다.
- 큰 글씨와 좁은 화면에서 경고와 제외 확인 화면이 넘치지 않는다.
- 스크린 리더가 경고, 두 동작, 제외 상태, 복원 동작을 정확히 읽는다.

### 11.4 지도와 플랫폼 검증

- 두 경로 조각 사이에 제외 구간이 있을 때 polyline이 서로 연결되지 않는다.
- GPS 공백과 제외 범위가 함께 있어도 조각 수와 재생 순서가 정확하다.
- 모든 좌표가 제외된 기록은 경로 없음 상태를 표시하고 복원 동작은 유지한다.
- Android 실제 기기에서 화면 켜짐, 화면 꺼짐, 백그라운드 상태의 알림과 탭 복귀를 확인한다.
- iOS 실제 기기에서 알림 허용과 거부, foreground와 background, 알림 탭 복귀를 확인한다.
- 두 플랫폼에서 고속 경고가 발생해도 위치 foreground service와 background location이
  중단되지 않는지 확인한다.

전체 회귀 게이트는 다음 명령을 사용한다.

```bash
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
flutter build apk --debug
flutter build ios --debug --no-codesign
python scripts/verify_prd_trd.py
```

## 12. 비목표

- 고속 이동만으로 세션을 자동 종료하거나 자동으로 차량 구간을 삭제하는 기능
- Core Motion, Activity Recognition, Health Connect, 외부 머신러닝 모델을 이용한
  교통수단 자동 분류
- 지하에서 GPS가 끊긴 시간을 셀룰러 기지국이나 노선 정보로 추정하는 기능
- 초 단위 자유 자르기, 지도 위 핸들 편집, 서로 떨어진 여러 범위의 일괄 선택
- 제외된 원시 좌표의 물리적 삭제
- 세션 시작 시각, 종료 시각, 메모, 장소 기억을 제외 동작으로 변경하는 기능
- 기존 30분 정지 자동 종료와 5시간 전체 자동 종료 정책 변경
- 클라우드 동기화, 다른 기기와 편집 충돌 해결
- 기존 활동 라벨 편집을 차량 구간 제외와 같은 의미로 바꾸는 기능
