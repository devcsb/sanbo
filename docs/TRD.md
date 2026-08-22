# TRD: 산보(Sanbo) — 위치 수집 · 분 윈도우 · 장소 · 활동 추측 기술 요구사항

| 항목 | 내용 |
|------|------|
| 문서 ID | `TRD-SANBO-v1.7` |
| 버전 | 1.7 (Flutter · Android · 한국 공개 지도 고정) |
| 상태 | 구현 가능 수준 스펙 / 앱 코드 미포함 |
| 상위 문서 | [PRD](./PRD.md) (`PRD-SANBO-v1.2`), [PLATFORM_AND_MAPS](./PLATFORM_AND_MAPS.md) |
| 추적 | §12 PRD↔TRD 매핑 표 |

본 TRD는 PRD 요구를 **구현 가능한 데이터 모델·파이프라인·휴리스틱·플랫폼 정책**으로 분해한다. 모호한 “나중에 정함”으로 핵심 경로를 남기지 않는다. 수치가 튜닝 가능하면 **기본값 + 설정 키**로 명시한다.

---

## 1. 기술 목표와 범위

### 1.1 목표

1. 위치 샘플을 안정적으로 수집·저장한다 (FR-01, FR-02).  
2. **분 단위 윈도우**로 집계한다 (FR-04, FR-05).  
3. 속도·정지·품질 메트릭을 산출한다 (FR-07, NFR-03).  
4. 장소/체류를 추론한다 (FR-08, FR-09).  
5. 활동 **가설**을 규칙으로 생성하고 사용자 라벨을 우선 저장한다 (FR-10–12).  
6. 조회·맵·삭제·로컬 우선·export를 지원한다 (FR-06, FR-14–19).
7. 기록 화면에서 로컬 날짜별 완료 산책 합계를 조회한다 (FR-25).

### 1.2 비범위

- 프로덕션 백엔드, 계정 시스템, 앱 스토어 제출 체크리스트 전문  
- ML 모델 학습 파이프라인 (later 훅만)  
- 법률 확정 해석

### 1.3 플랫폼 · 지도 결정 (Fixed — 가정 아님)

| 항목 | 결정 | 근거 / 결정 ID |
|------|------|----------------|
| 런타임 | **Flutter** | D-PLAT-01; Android→iOS 코드 공유 |
| 1차 OS | **Android (MVP)** | D-PLAT-02; FGS·권한 먼저 검증 |
| 2차 OS | **iOS (Later)** | 동일 `domain/` 재사용 |
| 저장 | **sqflite (SQLite)** 온디바이스 | FR-19 |
| 지도 렌더러 | **MapLibre GL** (Flutter 플러그인) | D-MAP-01; 타일 교체 가능 |
| MVP 타일 | **OSM 호환 공개 타일** + attribution | D-MAP-02; 영감 UX 패리티 |
| 베이스맵 | **OSM 공개 타일만** (VWorld 연동 제외, D-MAP-03 개정) | D-MAP-02·03 |
| 상용 맵 SDK | **MVP 비포함** (카카오/네이버/구글 맵 뷰) | D-MAP-04 |
| 지오코딩 | 체류 시만; VWorld 또는 (선택) 카카오 로컬 **REST**; 실패 시 좌표 | D-MAP-05, FR-08 |
| 상태관리 | Provider **또는** Riverpod **중 하나** | 심플 원칙 |
| 백엔드 | 없음 (MVP) | D-PLAT-03 |

상세 비교: [PLATFORM_AND_MAPS.md](./PLATFORM_AND_MAPS.md).  
아래 API는 논리 계층; 구현 언어는 **Dart**.

---

## 2. 시스템 아키텍처 (Flutter)

```
lib/
┌─────────────────────────────────────────────────────────┐
│  features/  UI (최대 3탭: 홈 · 기록 · 설정)                 │
│  SessionLive · SummaryMap · Timeline · History · Settings │
├─────────────────────────────────────────────────────────┤
│  app services (얇은 오케스트레이션)                          │
│  SessionService │ QueryService │ ExportService            │
├─────────────────────────────────────────────────────────┤
│  domain/  순수 Dart (flutter import 금지)                   │
│  SampleFilter → WindowAggregator → Metrics → PlaceLogic →│
│  ActivityInferencer → SessionRollup                       │
├─────────────────────────────────────────────────────────┤
│  platform/  adapters                                      │
│  LocationEngine │ AndroidFgs │ GeocoderClient │ MapPort   │
├─────────────────────────────────────────────────────────┤
│  data/  sqflite  │  map/ tile: osm (Carto)                 │
└─────────────────────────────────────────────────────────┘
```

- **domain/** 순수 파이프라인 → 단위·골든 테스트.  
- **MapPort**: `setTileSource`, `setPolyline`, `setMarkers` — UI는 타일 벤더를 모름.  
- **LocationEngine**: Android는 Fused/LocationManager + **Foreground Service**; iOS 어댑터는 later.

---

## 3. 데이터 모델 (스키마 수준)

DB 스키마 버전은 `4`다. v4는 완료 기록의 가역적 사용자 제외를 위한
`route_exclusions`와 `minute_windows.user_exclusion_id`를 추가한다.

### 3.1 `sessions`

| 필드 | 타입 | 설명 |
|------|------|------|
| `id` | UUID | PK |
| `started_at` | ISO-8601 datetime | 로컬 타임존 보존 권장 (offset 포함) |
| `ended_at` | datetime? | null = 진행 중 |
| `status` | enum | `active` \| `completed` \| `crashed_recovered` \| `discarded` |
| `tracking_mode` | enum | `balanced` \| `high_accuracy` \| `battery_saver` |
| `timezone` | string | IANA e.g. `Asia/Seoul` |
| `total_distance_m` | float? | 롤업 후 |
| `duration_s` | int? | ended_at - started_at |
| `moving_time_s` | int? | 정지 제외 추정 |
| `stationary_time_s` | int? | |
| `avg_speed_mps` | float? | moving 구 간 기준 권장 |
| `median_accuracy_m` | float? | |
| `valid_sample_count` | int? | |
| `polyline_simplified` | blob/text? | 인코딩 폴리라인 또는 JSON coords |
| `notes` | text? | 세션 메모 |

### 3.2 `location_samples`

| 필드 | 타입 | 설명 |
|------|------|------|
| `id` | integer | PK auto |
| `session_id` | UUID | FK |
| `ts` | datetime | 샘플 시각 |
| `lat` | double | |
| `lon` | double | |
| `accuracy_m` | float? | horizontal accuracy |
| `altitude_m` | float? | optional |
| `speed_mps` | float? | OS 제공 시; 없으면 파생 |
| `bearing_deg` | float? | |
| `is_filtered_out` | bool | 점프/이상치 제외 여부 (원본은 보존 권장) |
| `source` | enum | `gps` \| `network` \| `fused` \| `unknown` |

**보존 정책**: MVP는 필터 플래그만 두고 **원본 샘플 유지**(재집계·디버그). 용량 이슈 시 later에 raw 샘플 다운샘플.

### 3.3 `minute_windows`  ← 1급 집계

| 필드 | 타입 | 설명 |
|------|------|------|
| `id` | integer | PK |
| `session_id` | UUID | FK |
| `window_start` | datetime | 분 경계 정렬 (로컬 tz) |
| `duration_s` | int | 보통 60; partial면 <60 |
| `partial` | bool | 세션 시작/끝 분 |
| `sample_count` | int | 필터 통과 샘플 수 |
| `raw_sample_count` | int | 필터 전 |
| `distance_m` | float | 윈도우 내 연속 거리 합(필터 후) |
| `avg_speed_mps` | float | distance / moving_or_duration (정의 §5) |
| `max_speed_mps` | float | |
| `median_speed_mps` | float? | |
| `stationary_ratio` | float | 0–1 |
| `start_lat/lon` | double? | 첫 유효 샘플 |
| `end_lat/lon` | double? | 마지막 |
| `centroid_lat/lon` | double? | 산술 평균(소구간) |
| `quality` | enum | `high` \| `medium` \| `low` \| `gap` |
| `gap_reason` | string? | `no_samples` \| `permission` \| `provider_off` \| … |
| `place_id` | integer? | FK places; 장소 삭제 시 null |
| `hypothesis_label` | string | FR-12 라벨 |
| `hypothesis_confidence` | float | 0–1 |
| `hypothesis_evidence_json` | text | JSON array of {code, detail} |
| `user_label` | string? | 사용자 확정/수정 |
| `user_note` | text? | |
| `user_confirmed` | bool | default false |
| `user_exclusion_id` | string? | `route_exclusions.id`를 가리키는 파생 상태 |

**유니크**: `(session_id, window_start)`.

### 3.4 `places`

| 필드 | 타입 | 설명 |
|------|------|------|
| `id` | integer | PK |
| `lat` | double | 사용자가 확인한 체류 대표 좌표 |
| `lon` | double | |
| `name` | string | 사용자 확인 장소 이름 |
| `address` | string? | 사용자가 요청·확인한 OS 주소 제안 |
| `updated_at` | datetime | 이름·좌표 갱신 시각 |

### 3.5 `segments` (P1)

| 필드 | 타입 | 설명 |
|------|------|------|
| `id` | integer | |
| `session_id` | UUID | |
| `start_window` | datetime | |
| `end_window` | datetime | inclusive |
| `label` | string | user_label 우선 else hypothesis |
| `confidence_min` | float | 구간 내 최소 신뢰도 |
| `distance_m` | float | |
| `place_id` | integer? | |

### 3.6 논리 JSON 예시 — MinuteWindow

```json
{
  "session_id": "8f2c…",
  "window_start": "2026-07-11T22:44:00+09:00",
  "duration_s": 60,
  "partial": false,
  "sample_count": 18,
  "distance_m": 72.4,
  "avg_speed_mps": 1.21,
  "stationary_ratio": 0.05,
  "quality": "high",
  "centroid": { "lat": 37.55, "lon": 126.99 },
  "place": { "name": "한강공원", "category": "park" },
  "hypothesis": {
    "label": "walk_steady",
    "confidence": 0.78,
    "evidence": [
      { "code": "speed_band", "detail": "1.0–1.5 m/s" },
      { "code": "low_stationary", "detail": "0.05" },
      { "code": "place_category", "detail": "park" }
    ]
  },
  "user_label": null,
  "user_confirmed": false
}
```

### 3.7 고속 guard와 경로 제외 계약

고속 판단은 `SessionGuard`가 저장 시각이 아니라 앱 수신 시각 `observedAt`으로 freshness를 확인해 수행한다. 신뢰 가능한 샘플은 정확도 80m 이하, 자동 필터 제외 아님, 좌표가 유효함을 만족해야 한다. receipt는 최대 30초 전, 최대 5초 미래까지 허용한다. 최근 120초에서 8.0m/s(28.8km/h) 이상 구간이 누적 60초면 `SessionGuardEvent.highSpeedWarning`을 낸다. 4.0m/s(14.4km/h) 이하가 연속 30초가 되어야 다시 무장한다. 라이브 `SampleFilter`가 거부한 fix는 guard에 전달하지 않는 대신 `interruptHighSpeedContinuity()`로 누적 연속성을 끊는다. 복구에서는 저장된 샘플에 `SampleFilter.apply`를 먼저 적용한 marked 결과로 guard 상태를 재구축한다. 고속 이동만으로 세션을 자동 종료하지 않는다.

`SessionGuard.evaluate`의 경고 우선순위는 duration limit, stationary limit, duration warning, stationary warning, high-speed warning 순서다. 고속 경고는 `SessionWarningKind.highSpeed`로 표현하며 `기록 종료`는 `SessionController.stopFromHighSpeedWarning()`, `계속 기록`은 `SessionController.continueAfterWarning()`으로 처리한다.

완료 세션의 사용자 제외 원본은 UTC ISO 8601으로 저장한 반개구간 `[startAt, endAt)`인 `route_exclusions`다. 저장소는 transaction snapshot의 분 기록으로 authoritative `ActivitySegment`를 다시 만들고 요청이 그중 정확히 하나와 일치할 때만 허용한다. 첫 부분 분의 시작은 `max(first.windowStart, session.startedAt)`, 마지막 분의 끝은 `min(last.windowStart + 1분, session.endedAt)`이다. 임의의 같은 분 부분 범위와 불연속 분 선택은 거부한다. 겹치는 범위는 거부하고 맞닿은 authoritative 범위는 별도 레코드로 보존한다. 원시 `location_samples.is_filtered_out` 값과 행은 제외와 복원에서 절대 변경하지 않으며, `location_samples.user_exclusion_id` 열은 만들지 않는다.

DB v4는 `route_exclusions`와 `minute_windows.user_exclusion_id`를 추가한다.

```sql
-- DB schemaVersion = 4
CREATE TABLE route_exclusions (
  id TEXT PRIMARY KEY NOT NULL,
  session_id TEXT NOT NULL,
  start_at TEXT NOT NULL,
  end_at TEXT NOT NULL,
  reason TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
);
ALTER TABLE minute_windows ADD COLUMN user_exclusion_id TEXT
  REFERENCES route_exclusions(id) ON DELETE SET NULL;
```

`RoutePartitioner.partition`은 필터, 무효 좌표, 제외 교차와 trustedLocationGap에서는 fragment와 segment를 절대 연결하지 않는다. 즉 필터된 샘플, 유효하지 않은 좌표, 사용자 제외 내부 샘플, 제외 범위를 가로지르는 두 endpoint와 `trustedLocationGap`보다 긴 공백을 지나 선분을 잇지 않는다. 포함 샘플만 fragments에 두며, fragment의 각 선분은 시간 순서이고 0보다 길며 `maxGap` 이하이고 제외 범위를 교차하지 않는다. 양수인 1ms 미만 간격도 microseconds로 유한 속도를 계산한다. 1.5m 미만 선분은 fragment와 관측 시간 분류에는 남기되 거리에는 더하지 않는다. `timestamp == sessionEnd` 샘플은 마지막 실제 분이 소유한다. 지도, 재생, 분 집계와 세션 집계는 같은 partition fragments와 segments를 사용한다.

`SessionGuard`의 observedAt 수신 시각은 최대 과거 30초와 미래 5초만 허용한다. `WalkRepository.excludeRouteSegment`는 한 SQLite transaction에서 제외 레코드 삽입, 분 기록 전체 교체, 세션 집계 갱신 순으로 쓴다. 복원은 분 기록 전체 교체, 세션 집계 갱신, 제외 레코드 삭제 마지막 순서로 쓴다. 같은 SQLite transaction은 원본과 파생 상태를 함께 rollback한다. 제외된 분은 삭제하지 않고 `quality=gap`, `gap_reason=user_excluded`, 거리·속도·유효 샘플 수 0으로 바꾸며 원시 샘플 수, 사용자 라벨, 메모, 확정 상태와 장소 연결을 보존한다.

알림 tap에서 warm tap은 즉시 `/`로 이동한다. cold tap은 복구가 끝난 뒤 active session이 있을 때만 경고를 표시한다. 종료됐거나 없는 세션은 tap을 버린다. native와 Dart의 pending buffer는 하나만 저장하고 한 번만 전달한다.

정확한 공개 표면은 아래와 같다. 아래 선언은 완전한 독립 라이브러리가 아니라 실제 Dart 소스의 public type, field, getter, method 선언을 계약으로 옮긴 것이다.

```dart
enum RouteExclusionReason { vehicle }

class RouteExclusion {
  factory RouteExclusion({
    required String id,
    required String sessionId,
    required DateTime startAt,
    required DateTime endAt,
    required RouteExclusionReason reason,
    required DateTime createdAt,
  });
  final String id;
  final String sessionId;
  final DateTime startAt;
  final DateTime endAt;
  final RouteExclusionReason reason;
  final DateTime createdAt;
  RouteExclusion clampedTo(WalkSession session);
  bool contains(DateTime value);
  bool overlaps(DateTime start, DateTime end);
}

class RouteSegment {
  const RouteSegment({
    required LocationSample start,
    required LocationSample end,
    required double distanceM,
  });
  final LocationSample start;
  final LocationSample end;
  final double distanceM;
  Duration get duration;
  double get speedMps;
}

class RouteFragment {
  const RouteFragment(List<LocationSample> samples);
  final List<LocationSample> samples;
}

class RoutePartitionResult {
  const RoutePartitionResult({
    required List<RouteFragment> fragments,
    required List<LocationSample> includedSamples,
    required List<RouteSegment> segments,
  });
  final List<RouteFragment> fragments;
  final List<LocationSample> includedSamples;
  final List<RouteSegment> segments;
}

abstract final class RoutePartitioner {
  static RoutePartitionResult partition({
    required List<LocationSample> samples,
    required List<RouteExclusion> exclusions,
    Duration maxGap = trustedLocationGap,
  });
}

class MinuteWindow {
  final String? userExclusionId;
  bool get isUserExcluded;
}

class ActivitySegment {
  const ActivitySegment({
    required DateTime start,
    required DateTime endInclusive,
    required ActivityLabel label,
    required double confidenceMin,
    required double distanceM,
    required int sampleCount,
    required int durationS,
    required bool userConfirmed,
    required List<MinuteWindow> windows,
    String? sessionId,
    double avgSpeedMps = 0,
    WindowQuality quality = WindowQuality.medium,
    DateTime? actualStart,
    DateTime? actualEndExclusive,
  });
  final DateTime start;
  final DateTime endInclusive;
  final ActivityLabel label;
  final double confidenceMin;
  final double distanceM;
  final int sampleCount;
  final int durationS;
  final bool userConfirmed;
  final double avgSpeedMps;
  final WindowQuality quality;
  final DateTime? actualStart;
  final DateTime? actualEndExclusive;
  final List<MinuteWindow> windows;
  final String? sessionId;
  String? get userExclusionId;
  int get minuteCount;
  DateTime get startAt;
  DateTime get endExclusive;
  bool get isMultiMinute;
}

class SegmentMerger {
  SegmentMerger({double minConfidence = 0.4});
  final double minConfidence;
  List<ActivitySegment> merge(
    List<MinuteWindow> windows, {
    String? sessionId,
    DateTime? sessionStart,
    DateTime? sessionEnd,
  });
}

class WindowAggregator {
  WindowAggregator({
    WindowAggregatorConfig config = const WindowAggregatorConfig(),
    ActivityInferencer? inferencer,
  });
  final WindowAggregatorConfig config;
  final ActivityInferencer inferencer;
  List<MinuteWindow> aggregate({
    required RoutePartitionResult partition,
    required List<LocationSample> rawSamples,
    required List<RouteExclusion> exclusions,
    required DateTime sessionStart,
    required DateTime sessionEnd,
  });
}

class SessionRollupResult {
  const SessionRollupResult({
    required double totalDistanceM,
    required int durationS,
    required int movingTimeS,
    required int stationaryTimeS,
    required double avgSpeedMps,
    required int validSampleCount,
    double? medianAccuracyM,
  });
  final double totalDistanceM;
  final int durationS;
  final int movingTimeS;
  final int stationaryTimeS;
  final double avgSpeedMps;
  final int validSampleCount;
  final double? medianAccuracyM;
}

class SessionRollup {
  SessionRollup({double stationarySpeedMps = 0.3});
  final double stationarySpeedMps;
  SessionRollupResult compute({
    required WalkSession session,
    required RoutePartitionResult partition,
    required List<RouteExclusion> exclusions,
    required DateTime endedAt,
  });
}

class SessionPipeline {
  SessionPipeline({
    SampleFilter? filter,
    WindowAggregator? aggregator,
    SessionRollup? rollup,
    SegmentMerger? segmentMerger,
  });
  final SampleFilter filter;
  final WindowAggregator aggregator;
  final SessionRollup rollup;
  final SegmentMerger segmentMerger;
  SessionProcessResult process({
    required WalkSession session,
    required List<LocationSample> rawSamples,
    required DateTime endedAt,
  });
  CompletedSessionRecalculation recalculateCompleted({
    required WalkSession session,
    required List<LocationSample> storedSamples,
    required List<RouteExclusion> exclusions,
    required List<MinuteWindow> previousWindows,
  });
}

class SessionProcessResult {
  const SessionProcessResult({
    required List<LocationSample> filteredSamples,
    required List<RouteFragment> fragments,
    required List<MinuteWindow> windows,
    required SessionRollupResult metrics,
    List<ActivitySegment> segments = const [],
  });
  final List<LocationSample> filteredSamples;
  final List<RouteFragment> fragments;
  final List<MinuteWindow> windows;
  final List<ActivitySegment> segments;
  final SessionRollupResult metrics;
}

class CompletedSessionRecalculation {
  const CompletedSessionRecalculation({
    required List<MinuteWindow> windows,
    required List<RouteFragment> fragments,
    required SessionRollupResult metrics,
  });
  final List<MinuteWindow> windows;
  final List<RouteFragment> fragments;
  final SessionRollupResult metrics;
}

enum SessionGuardEvent {
  none,
  stationaryWarning,
  stationaryLimit,
  durationWarning,
  durationLimit,
  highSpeedWarning,
}

class SessionGuardObservation {
  const SessionGuardObservation({
    this.acceptedForHighSpeed = false,
    this.clearedStationaryWarning = false,
  });
  final bool acceptedForHighSpeed;
  final bool clearedStationaryWarning;
}

class SessionGuard {
  SessionGuardObservation observe(LocationSample sample, {required DateTime observedAt});
  void rebuildHighSpeedState({
    required Iterable<LocationSample> samples,
    required DateTime observedAt,
  });
  void dismissHighSpeedWarning();
  void interruptHighSpeedContinuity();
  SessionGuardDecision evaluate({required DateTime startedAt, required DateTime now});
  void continueStationaryTracking(DateTime now);
}

enum SessionWarningKind { stationary, duration, highSpeed }
enum SessionWarningAction { stopRecording, continueRecording }

class SessionWarning {
  const SessionWarning({
    required SessionWarningKind kind,
    required String title,
    required String message,
    required Set<SessionWarningAction> actions,
    Duration? remaining,
  });
  final SessionWarningKind kind;
  final String title;
  final String message;
  final Set<SessionWarningAction> actions;
  final Duration? remaining;
}

class LiveSessionState {
  final SessionWarning? activeWarning;
}

class SessionController {
  Future<void> start({TrackingMode mode = TrackingMode.balanced});
  Future<void> restoreIfNeeded();
  Future<void> retryRecovery();
  void clearError();
  void clearNotice();
  Future<void> restorePendingNotificationTap();
  void handleNotificationTap(SessionNotificationTap tap);
  Future<void> continueAfterWarning();
  Future<WalkSession?> stopFromHighSpeedWarning();
  void debugIngestSamples(List<LocationSample> samples);
  Future<void> debugEvaluateSessionGuard([DateTime? now]);
  void setAppForeground(bool foreground);
  Future<WalkSession?> stop({String? completionNotice});
  Future<void> discardActive();
}

enum NotificationPermissionResult { granted, denied, unsupported, failed }

class SessionNotificationTap {
  const SessionNotificationTap(SessionWarningKind kind);
  final SessionWarningKind kind;
}

abstract class SessionNotificationService {
  Future<void> initialize();
  Future<NotificationPermissionResult> requestPermission();
  Stream<SessionNotificationTap> get taps;
  Future<void> showWarning(SessionWarning warning);
  Future<void> showCompletion({required String title, required String body});
  Future<void> cancel({required SessionWarningKind kind});
  Future<void> cancelAllWarnings();
}

class PlatformSessionNotificationService implements SessionNotificationService {
  Stream<SessionNotificationTap> get taps;
  Future<void> initialize();
  Future<NotificationPermissionResult> requestPermission();
  Future<void> showWarning(SessionWarning warning);
  Future<void> showCompletion({required String title, required String body});
  Future<void> cancel({required SessionWarningKind kind});
  Future<void> cancelAllWarnings();
}

class RoutePlaybackPoint {
  const RoutePlaybackPoint({
    required LocationSample sample,
    required int fragmentIndex,
    required int pointIndex,
  });
  final LocationSample sample;
  final int fragmentIndex;
  final int pointIndex;
  bool get startsFragment => pointIndex == 0;
}

class RoutePlaybackCursor {
  const RoutePlaybackCursor({
    required int fragmentIndex,
    required int pointIndex,
  });
  final int fragmentIndex;
  final int pointIndex;
}

abstract final class RoutePlayback {
  static List<RoutePlaybackPoint> flatten(RoutePartitionResult route);
  static List<LocationSample> playableSamples(
    Iterable<LocationSample> samples,
  );
  static int nearestIndex(List<LocationSample> sortedSamples, DateTime time);
  static List<LocationSample> samplesInRange(
    List<LocationSample> sortedSamples, {
    required DateTime start,
    required DateTime endExclusive,
  });
  static int stepForSampleCount(int sampleCount);
  static Duration intervalForSampleCount(int sampleCount);
}

Future<List<RouteExclusion>> WalkRepository.getRouteExclusions(String sessionId);
Future<RouteExclusion> WalkRepository.excludeRouteSegment({
  required String sessionId,
  required ActivitySegment segment,
  RouteExclusionReason reason = RouteExclusionReason.vehicle,
  DateTime? createdAt,
});
Future<void> WalkRepository.restoreRouteExclusion({
  required String sessionId,
  required String exclusionId,
});
```

알림 권한 거부와 notification API 실패는 비치명이다. 위치 권한, location engine 시작, 세션 생성과 기록을 지연하거나 실패시키지 않는다. native payload는 `kind: highSpeed`와 `sessionId`이고 Dart 전달은 `notificationTapped({kind: highSpeed, sessionId})`다. Dart가 `ready` handshake를 보내기 전까지 Android와 iOS native가 cold tap을 한 항목 버퍼에 보관한다. warm start에서는 tap을 받은 즉시 홈으로 이동해 활성 고속 경고를 표시한다. cold start에서는 native 버퍼를 `initialize()` 뒤 전달하고, 세션 복구가 끝난 뒤 `rebuildHighSpeedState`로 고속 상태와 경고를 재구성한다. 일반 종료, 고속 경고 종료와 discard는 `cancelAllWarnings()`로 4101과 4103을 모두 지운다. 고속 경고의 종료 성공도 `historyTickProvider`를 갱신하고 완료 상세 화면으로 이동한다.

---

## 4. 처리 파이프라인 (핵심 경로)

PRD §8 플로우의 기술 분해. **필수 순서**:

```
LocationSample 수집
    → SampleFilter (이상치·정확도)
    → (버퍼) MinuteWindowAggregator   // 분 경계 또는 종료 시
    → WindowMetrics                     // 거리·속도·정지
    → StayAndPlaceResolver              // 체류·지오코딩
    → ActivityInferencer                // 가설
    → LocalStore.upsert
세션 종료 시:
    → SessionRollup (전체 경로 재계산)
    → PolylineSimplifier
    → (P1) SegmentMerger
```

### 4.1 Location 수집 — `LocationEngine` (Flutter · Android MVP)

| 모드 `tracking_mode` | 목표 주기 | 정확도 힌트 | 거리 필터 | CPU WakeLock | 사용 |
|----------------------|-----------|-------------|-----------|--------------|------|
| `battery_saver` | **20 s** | medium | 10 m | 끔 | 배터리 우선 |
| `balanced` (**default**) | **8 s** | high | 5 m | 끔 | 일반 산책 |
| `high_accuracy` | **4 s** | best for navigation | 2 m | 켬 | 경로 정밀도 우선 |

목표 주기는 OS에 전달하는 요청값이며 절전 정책·신호 상태에 따라 실제 전달 간격은 더 길어질 수 있다. 샘플 DB 체크포인트는 30초 배치로 수행한다.

#### Android (MVP 필수)

| 항목 | 구현 요구 |
|------|-----------|
| 권한 | 화면에서 시작하는 location FGS는 `ACCESS_FINE_LOCATION`만 요청한다. 현재 흐름에 불필요한 `ACCESS_BACKGROUND_LOCATION`은 선언하지 않는다. |
| 서비스 | `foregroundServiceType=location` + 진행 중 **고정 알림** (“산보: 산책 기록 중”) — FR-22 |
| 알림 채널 | Android 13+ 알림 권한 거부는 FGS 시작을 막지 않지만 알림 서랍 노출을 제한한다. 안전 안내 가시성을 위해 시작 시 권한을 요청한다. |
| 배터리 | 최적화 예외 **강요 금지**; 설정 화면 딥링크 안내만 |
| 플러그인 가이드 | `geolocator` 등 + 네이티브 FGS 설정 문서화; 프로세스 킬 대비 체크포인트 |

#### 세션 안전 종료

| 조건 | 사전 안내 | 종료 |
|------|-----------|------|
| 한 장소 장기 정지 | 20분에 앱 내 + OS 알림, `계속 기록` 선택 가능 | 30분에 자동 저장·종료 |
| 전체 기록 시간 | 4시간 45분에 앱 내 + OS 알림 | 5시간에 자동 저장·종료 |

정지는 정확도 인지 반경(기본 35m, 현재·기준 샘플 각각의 `accuracy × 1.5` 중 큰 값) 안의 유효 샘플로 판단한다. 반경을 벗어나거나 신뢰 가능한 보행 속도(기본 0.9m/s 이상)가 관측되면 정지 타이머를 초기화한다. 정확도 80m 초과 샘플은 정지 판단에서 제외한다.

안전 조건은 30초 타이머와 모드별 샘플 묶음(약 30초)을 한 유지보수 경로에서 평가한다. OS 절전으로 타이머가 지연되어도 새 샘플 묶음과 앱 포그라운드 복귀 시 즉시 따라잡는다. 강제 종료로 프로세스가 사라진 경우에는 다음 실행 시 미완료 기록 복구 흐름으로 이어진다.

#### iOS (실험 지원)

- When In Use → Always 교육, `UIBackgroundModes: location`, 파란 상태바 기대 관리.  
- `AppleSettings(activityType=fitness)`와 백그라운드 위치 표시를 사용한다.
- 출시 전 실제 잠금 화면·권한 승격·App Store 설명을 별도 검증한다.

- 레퍼런스(2–3s, ±3.8m)는 **high_accuracy** 벤치마크.  
- 권한 부족 시 샘플 중단 + `gap_reason=permission` 윈도우.

**매핑**: FR-02, FR-03, FR-22, NFR-02, 축 C.

### 4.2 SampleFilter

기본 규칙 (키: `filter.*`):

| 규칙 | 기본 | 동작 |
|------|------|------|
| `max_accuracy_m` | 80 | 초과 샘플 `is_filtered_out=true` (집계 제외, 원본 보존) |
| `max_jump_speed_mps` | 40 | 이전 유효점 대비 순간 속도 초과 시 제외 (차량 오인 전 GPS 점프 억제) |
| `min_time_delta_ms` | 500 | 중복 폭주 억제 |

저품질 윈도우: 유효 샘플 < `min_samples_per_window` (default **3**) 또는 median accuracy > 50m → `quality=low`.

### 4.3 MinuteWindowAggregator

1. 샘플 `ts`를 세션 `timezone`의 **분 바닥(floor)** 으로 버킷.  
2. 세션 시작 전·종료 후 샘플 무시.  
3. 진행 중: 직전 완성 분만 확정 저장; 현재 열린 분은 메모리 버퍼(+주기 체크포인트).  
4. 샘플 0: `quality=gap`, distance=0, hypothesis=`unknown`, confidence=0.  
5. **부분 분**: `duration_s = actual`, `partial=true`.

**매핑**: FR-04, FR-05, G1.

### 4.4 WindowMetrics

- **거리**: 필터 통과 샘플에 Haversine 순차 합.  
- **avg_speed_mps**:  
  - 기본: `distance_m / max(duration_s - estimated_stationary_s, 1)` (이동 시간 분모)  
  - 대안 표시용: `distance_m / duration_s` (전체 평균)  
- **stationary**: 순간 속도 < `stationary_speed_mps` (default **0.3**) 인 구간의 시간 비율; 또는 연속 점 이동 < `stationary_radius_m` (default **8m**) 유지 시간.  
- **세션 롤업 거리**: 윈도우 distance **합을 쓰지 않음**. 세션 전체 필터 샘플 경로를 다시 한 번 계산 (PRD 재검증 축 B).

**페이스** (선택 표시): `pace_s_per_km = 1000 / avg_speed_mps` when speed > ε.

**매핑**: FR-07, FR-15, NFR-03.

### 4.5 StayAndPlaceResolver

**체류 탐지 (윈도우 또는 멀티윈도우)**:

- 조건 예: `stationary_ratio ≥ 0.7` 이고 `distance_m < 25` → 체류 후보.  
- 연속 N분(default **3**) 체류 후보 → `place_stay` 입력 강화.  
- 클러스터 중심 = centroid 또는 medoid.

**장소 기억 · 주소 제안**:

- 체류형 세그먼트(`place_stay`, `cafe_or_shop`, `park_linger`, 2분 이상
  `stationary`)에만 장소 이름 편집을 제공한다.
- 주소 제안은 사용자가 버튼을 누를 때 대표 좌표 1건을 OS 기기
  지오코더에 전달한다. 자동·배치·공용 Nominatim 호출은 하지 않는다.
- 제안 결과는 사용자가 확인·수정한 뒤에만 `places`에 저장한다.
- 기존 장소는 대표 좌표 반경 35m 안의 새 체류 구간에 로컬 재사용한다.
- 실패/오프라인에서도 직접 이름 저장과 GPS 기록·활동 추정은 유지한다.
- 세션 삭제 후 연결이 없는 장소 행은 제거하고, 전체 삭제는 장소 캐시도
  함께 삭제한다.
- P1: 명시적 동의를 전제로 POI 카테고리 맵핑 테이블 검토.

**매핑**: FR-08, FR-09, FR-20, NFR-05.

### 4.6 ActivityInferencer (규칙 엔진)

입력 특징 벡터(윈도우):

| 특징 | 출처 |
|------|------|
| `avg_speed_mps`, `max_speed_mps` | metrics |
| `stationary_ratio`, `distance_m` | metrics |
| `quality` | filter |
| `place.category` | place |
| `hour_local` | window_start |
| `partial`, `sample_count` | window |

**출력**:

```text
{ label, confidence ∈ [0,1], evidence[] }
```

`user_label`이 있으면 **표시·세그먼트는 user 우선**, hypothesis는 보존(감사용).

#### 4.6.1 규칙 표 (MVP 기본값 — 튜닝 가능)

평가는 **위에서 아래 우선** (첫 매칭 + 조정). `quality=gap|low` 이고 sample_count=0 → 즉시 `unknown` conf=0.

| 우선 | 조건 (요약) | label | base conf |
|------|-------------|-------|-----------|
| 1 | quality low/gap 또는 sample_count < 3 | `unknown` | 0.0–0.3 |
| 2 | avg_speed ≥ 8.0 m/s (~29 km/h) 및 지속 | `vehicle` | 0.55 (높여야 확정 느낌 금지) |
| 3 | stationary_ratio ≥ 0.7 & distance < 25m & place.category in cafe/shop/restaurant | `cafe_or_shop` | 0.5–0.7 |
| 4 | 동일 체류 & category=park | `park_linger` | 0.5–0.65 |
| 5 | 동일 체류 (POI 없음) | `place_stay` | 0.45–0.6 |
| 6 | stationary_ratio ≥ 0.7 & distance < 25m | `stationary` | 0.5–0.65 |
| 7 | avg_speed in [1.6, 2.5) m/s & stationary < 0.3 | `walk_brisk` | 0.55–0.75 |
| 8 | avg_speed in [0.8, 1.6) m/s & stationary < 0.35 | `walk_steady` | 0.55–0.8 |
| 9 | avg_speed in [0.3, 0.8) m/s | `stroll_slow` | 0.5–0.7 |
| 10 | else | `unknown` | ≤ 0.4 |

**confidence 보정**:

- place 일치 시 +0.05~0.1  
- quality medium −0.1, low 이미 unknown 쪽  
- 속도가 경계(±0.1 m/s)면 conf cap 0.55  
- **표시 임계**: conf < `hypothesis_min_display` (default **0.4**) 이면 UI상 `unknown`으로 강등 가능(저장은 원래 값 유지 옵션).

**evidence 코드 목록**: `speed_band`, `stationary_ratio`, `place_category`, `quality`, `time_of_day`, `distance_window`, `multi_minute_stay`.

**매핑**: FR-10, FR-12, 축 E.  
**명시적 비목표**: LLM으로 자유 문장 활동 생성(환각) — later + 인간 검수 전제.

### 4.7 SessionRollup

종료 시 계산:

- `total_distance_m`: 연속 유효 샘플(간격 ≤ 60초) 사이의 필터 경로. 긴 GPS gap을 직선으로 연결하지 않음
- `moving_time_s` / `stationary_time_s`: 연속 유효 샘플 간격만 분류. 첫 fix 전·마지막 fix 후·60초 초과 gap은 미관측 시간으로 두며 이동 시간에 포함하지 않음
- `avg_speed_mps`: distance / moving_time  
- `median_accuracy_m`, `valid_sample_count`  
- 단순화 폴리라인: Douglas-Peucker, ε ≈ 8–12 m (맵 표시용); raw는 samples에 유지

**매핑**: FR-15, 레퍼런스 요약 카드 패리티.

실시간 홈 지표, 완료 분 집계, 세션 롤업과 미완료 세션 복구 지표도 `trustedLocationGap = 60초`와
`minMeaningfulSegmentDistanceM = 1.5m`을 동일하게 적용한다. 경로 fragment에는 1.5m 미만 선분을 유지하지만 거리 기여는 0이다. 60초를 넘긴 두 fix를
직선으로 연결하지 않아 화면상의 누적 거리와 종료 후 롤업이 서로 달라지지 않게 한다.
OS가 `speed_mps = 0` 또는 값을 생략한 경우에는 인접한 신뢰 fix의 좌표·시간으로
속도를 파생하고, 필터된 fix의 공급자 속도는 UI에 반영하지 않는다.

### 4.7.1 DailyActivityQuery

기록 화면의 최근 7일 요약은 세션 목록을 메모리에서 재합산하지 않고
`WalkRepository.dailyStats(startDate, endDateExclusive)`의 SQLite 집계 결과를 사용한다.

- 범위는 로컬 자정 기준 `[startDate, endDateExclusive)`이며 `started_at`의 시작일에
  완료 세션을 귀속한다. 자정을 넘어 종료한 세션도 시작일에 남긴다.
- SQL은 `status = completed`와 `started_at` 범위를 함께 제한하고, 날짜별
  `COUNT(*)`, `SUM(total_distance_m)`, `SUM(duration_s)`를 그룹화한다. 누락된 날짜는
  `DailyWalkStats.zero`로 채워 항상 7개를 반환한다.
- UI provider는 `historyTickProvider`를 구독해 산책 종료·삭제·가져오기 뒤 갱신한다.
  날짜 선택은 이미 로드된 7개 행만 바꾸고, 주간 이동에서만 새 쿼리를 실행한다.
- 패널은 거리·시간·횟수만 노출한다. 걸음 수, 칼로리, Samsung Health/Health Connect,
  월간 차트는 이 API의 범위가 아니다. 최근 산책 목록은 선택일로 필터링하지 않는다.
- API 오류는 패널 내부 재시도 상태로 열화하며 전체 기록 목록을 가리지 않는다.

**매핑**: FR-14, FR-25, NFR-05, NFR-06.

### 4.8 SegmentMerger (P1)

- 표시 라벨(`user_label ?? hypothesis_label`)이 동일하고 연속이며 둘 다 conf ≥ 0.4 (또는 user 확정)이면 병합.  
- `unknown` 단독 분 끼면 분리 유지.
- 세션 경계를 받은 경우 `startAt`과 `endExclusive`는 첫 분과 마지막 분의 실제 세션 범위로 clamp한다. 저장소와 지도 강조는 이 실제 반개구간을 함께 사용한다.

**매핑**: FR-13.

### 4.9 RoutePlayback · 지도–타임라인 연동

- 필터 제외 샘플을 시간순으로 정렬하고 슬라이더 인덱스의 현재 좌표를
  지도 마커와 현재 활동·장소 카피에 함께 사용한다.
- 전체 경로, 현재 인덱스까지의 진행 경로, 선택 세그먼트 경로를 서로
  다른 색·두께로 그린다. 체류처럼 경로 길이가 0에 가까운 구간도
  중심 강조 링을 표시한다.
- 재생은 400ms tick, 최대 약 50 tick이 되도록 긴 기록의 샘플을
  건너뛴다. 사용자 슬라이더 조작·구간 선택·화면 dispose 시 timer를
  즉시 취소한다.
- 구간 시작 시각과 가장 가까운 샘플은 이진 탐색으로 찾고,
  `[segment.start, segment.endExclusive)` 샘플만 강조한다.
- 타임라인 구간 탭은 지도 보기, 별도 48dp 편집 버튼은 활동·장소
  수정으로 분리한다.
- 긴 상세 리스트에서 상단 지도가 dispose된 경우 리스트를 먼저
  상단으로 복귀시킨 뒤 `ensureVisible`로 지도에 맞춘다.

**매핑**: FR-06, FR-13, FR-14, NFR-06.

---

## 5. 속도·거리 정의 (모호성 제거)

| 용어 | 정의 |
|------|------|
| 순간 속도 | OS `speed` 또는 Δdistance/Δt |
| 윈도우 거리 | 윈도우 내 필터 샘플 Haversine 합 |
| 세션 거리 | 세션 전 구간 필터 샘플 Haversine 합 (**윈도우 합 ≠ 세션 거리** 가능: 경계 샘플·필터 재적용) |
| 정지 시간 | stationary 판정 구간 길이 합 |
| 이동 시간 | duration − stationary (음수 방지 clip) |

UI는 세션 카드에 **세션 거리**를 1차 표시 (레퍼런스와 동일 정신).

---

## 6. 오류 · 결측 · 비정상 종료

| 상황 | 감지 | 처리 |
|------|------|------|
| GPS 꺼짐 | provider status | 수집 pause, UI 경고, gap 윈도우 |
| 권한 철회 | OS callback | 동일 + 설정 유도 |
| 샘플 공백 > 90s | 타임스탬프 | 중간 분에 gap; 거리 보간 **하지 않음**(허위 경로 방지) |
| 좌표 점프 | filter | 제외, quality 하락 가능 |
| 앱 프로세스 사망 | cold start | `active` 세션 있으면 `crashed_recovered`; 버퍼 체크포인트에서 윈도우 재집계; 사용자에 “복구된 기록” 표시 |
| 지오코딩 실패 | HTTP/timeout | place null, 추측은 속도만 |
| 저장소 full | IO error | 세션 안전 종료 시도, 에러 노출 |

체크포인트: 30초마다 또는 모드별 약 30초 분량(절전 2·균형 4·정밀 8개) 샘플이 쌓일 때 커밋. 백그라운드에서는 네이티브 위치 수집을 유지하되 1초 경과 타이머와 매 샘플 UI 상태 발행은 중단하고 복귀 시 한 번에 동기화한다.

**매핑**: S3, S5, NFR-01, NFR-05.

---

## 7. 플랫폼 · 권한 · 배터리 · 지도 공급

### 7.0 Flutter 타깃 매트릭스

| 단계 | Android | iOS | 비고 |
|------|---------|-----|------|
| MVP | **필수** | 선택(스킵 가능) | `flutter build apk` / appbundle 검증 대상 |
| v1+ | 유지 | 권장 착수 | domain 100% 공유, platform 어댑터 추가 |

### 7.1 권한 매트릭스

| 플랫폼 | 최소 | 백그라운드 산책 | UX |
|--------|------|-----------------|-----|
| **Android (MVP)** | FINE/COARSE | `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION` + 알림; 필요 시 BACKGROUND 단계적 | 목적: “산책 동선을 분 단위로 기록합니다”; 배터리 예외 **강요 금지** |
| iOS (실험 지원) | When In Use로 시작, OS 정책에 따라 Always 안내 | `UIBackgroundModes=location` + `AppleSettings` fitness/background indicator | 백그라운드 표시를 숨기지 않음; 출시 전 실기기·스토어 심사 검증 |

### 7.1.1 지도 · 네트워크 권한

| 항목 | MVP | 비고 |
|------|-----|------|
| 인터넷 | 타일 로드·(선택) 역지오코딩에 필요 | **오프라인**: 이미 캐시된 타일 범위 외 맵은 빈 격자 가능; **GPS 기록·DB는 오프라인 동작** |
| 타일 캐시 | MapLibre/HTTP 캐시 기본 활용 | 경로 원본을 직접 보내지는 않지만 조회 타일 좌표·IP 등 네트워크 정보로 대략적 표시 영역이 CARTO에 노출될 수 있으므로 설정·개인정보 안내에 고지 |

### 7.2 배터리 트레이드오프

| 모드 | 수집 | 지오코딩 | 맵 라이브 |
|------|------|----------|-----------|
| battery_saver | 20s + 10m 필터, WakeLock 끔 | 종료 배치만 | 꺼짐 가능 |
| balanced | 8s + 5m 필터, WakeLock 끔 | 체류 시 + 종료 | 요약 시 |
| high_accuracy | 4s + 2m 필터, WakeLock 켬 | 더 잦음 | 옵션 |

NFR-02: 기본 balanced; 정밀 모드만 CPU WakeLock을 유지한다. 실기기 배터리 수치는 기종·OS·신호 환경별로 별도 측정한다.

### 7.3 정확도 vs 배터리

- 레퍼런스급 ±4m·2–3s는 **high_accuracy**에서만 기대.  
- balanced에서 속도 대역(걷 vs 정지) 분류는 유지 목표, 정밀 페이스 경쟁은 비목표.

---

## 8. 프라이버시 · 보안

| 통제 | 구현 |
|------|------|
| 저장 위치 | 앱 샌드박스 SQLite; 경로 설정 화면에 표시 (FR-19) |
| 네트워크 | 기본 무전송. 사용자가 `주소 제안`을 누를 때만 체류 대표 좌표 1건을 OS 주소 서비스에 전달 (FR-20) |
| 로그 | lat/lon 크래시 로그 금지; 세션 id만 |
| 삭제 | session cascade delete samples/windows/places 고아 정리 (FR-18) |
| Export | 사용자 명시; 파일에 schema_version; 공유 시트는 OS 공유 |
| OS 자동 백업 | Android `allowBackup=false` + Android 11/12+ 백업 규칙으로 앱 데이터 전체 제외. 앱 업데이트 자체는 샌드박스 DB를 유지한다. iOS 출시 전 exclude-backup 별도 적용 — 위치 민감 |
| 수동 전체 백업 | `.sanbo` JSON, 50MB/테이블 50만 행 상한. 완료 세션·원본 위치·윈도우·수정·메모·참조 장소 포함. 내보내기 전 정밀 위치 경고 |
| 복원 | 기존 세션 ID는 건너뛰는 병합. 좌표·범위·FK·버전을 검증한 단일 SQLite transaction; 오류 시 전체 rollback |
| DB 마이그레이션 | 스키마 버전 증가형 `onUpgrade`, FK 활성화, 열기 후 `quick_check`; 미래 버전 downgrade 금지 |
| 암호화 | 기기 암호화 의존; SQLCipher는 P2 |
| 벤더 | 지오코딩 ToS·보관 정책 체크리스트 필수 (법무 자문 아님) |

**매핑**: FR-24, NFR-04, NFR-08, NFR-09, 축 D.

---

## 9. 외부 의존

| 의존 | 필수 | 용도 | 실패 시 |
|------|------|------|---------|
| OS Location (Android) | 예 | 샘플 | 앱 핵심 불가 |
| SQLite (sqflite) | 예 | 저장 | — |
| MapLibre + **OSM 타일** | 예(조회) | FR-06, D-MAP-02 | 좌표 텍스트 리스트 폴백 |
| **VWorld API/타일** | **아니오** (제품 제외) | 비교만 — D-MAP-03 | OSM 단일 소스 |
| Reverse geocoder REST | 아니오 | FR-08/09 | 좌표만 · `장소 미확인` |
| 카카오/네이버/구글 **Map SDK** | **아니오** | — | 사용하지 않음 (D-MAP-04) |
| Firebase / 계정 백엔드 | 아니오 | — | MVP 금지 |
| 라우팅/도로 스냅 | 아니오 | later | 직선 폴리라인 |
| LLM API | 아니오 | 비목표 | — |

### 9.1 지도 소스 모델

```text
// 제품 단일 소스 (D-MAP-02 · D-MAP-03 개정)
basemap = OSM-compatible public tiles (Carto Voyager)
url = https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png
attribution = © OpenStreetMap · © CARTO
// VWorld / 상용 SDK: 없음
```

- 화면 하단/코너: **OSM·CARTO attribution**.  
- 내부 좌표: 항상 **WGS84**.

### 9.2 Export 포맷 (P1, 레퍼런스 NDJSON 정신)

```text
schema_version: 2
session meta line (JSON)
one raw LocationSample per line (NDJSON), route exclusion records,
and minute windows including user_exclusion_id
```

### 9.3 전체 백업 포맷

전체 백업 출력의 리터럴 버전은 `backup_schema_version: 2`다. 입력은 v1과 v2를 지원하며 v1을 읽을 때 `route_exclusions`는 빈 목록으로, `minute_windows.user_exclusion_id`는 null로 정규화한다. v2 출력은 `sessions`, `location_samples`, `minute_windows`, `places`, `route_exclusions`를 담고 원시 샘플의 `is_filtered_out`과 분 기록의 `user_exclusion_id`를 보존한다. 가져올 때 분 기록의 실제 범위는 `[max(windowStart, session.startedAt), min(windowStart + 1분, session.endedAt))`로 계산하며, 같은 세션의 대표 제외 ID가 이 범위와 겹쳐야 한다. 같은 분의 비중첩 제외가 여러 개인 기존 백업은 겹치는 대표 ID 하나를 유지할 수 있다. 자동 증가 샘플/윈도우 ID는 내보내지 않고 복원 시 새로 부여하며, 장소와 제외 ID 참조는 백업 내부에서 매핑한다. 진행 중 세션은 복제 복구를 막기 위해 제외한다.

---

## 10. API 표면 (앱 내부 서비스)

의사 인터페이스:

```text
SessionService.start(mode) -> Session
SessionService.stop() -> SessionSummary
SessionService.list() -> [SessionHeader]
SessionService.get(id) -> SessionDetail  // windows, polyline, summary
SessionService.delete(id)
HypothesisService.update(windowId, userLabel, note?, confirmed?)
ExportService.export(sessionId, format: json|ndjson) -> FileUri
BackupService.exportAll() -> .sanbo FileUri
BackupService.importMerge(file) -> ImportResult
LocationEngine.setMode(mode)
```

UI는 위만 호출; 파이프라인은 엔진 콜백에서 구동.

---

## 11. 다방면 검토·재검증 (기술)

PRD §14와 정합. 기술 결론:

### 축 A — 제품 가치 구현성

- 분 윈도우 스키마를 1급으로 두지 않으면 타임라인 쿼리가 어려움 → **minute_windows 테이블 필수**.  
- 추측을 세션 단위 1개로 뭉개면 S2 혼합 활동 실패.

### 축 B — 정확도

- 이중 거리 정의 명문화(§5).  
- 보간으로 gap 메우기 **금지**(허위 동선).  
- 속도 임계는 설정 파일로 빼 재튜닝.

### 축 C — 모바일

- Foreground service/알림 없는 백그라운드 고주기 = 비권장.  
- 체크포인트로 crash 복구.  
- NFR-01 조건부: “권한·provider 정상” 전제.

### 축 D — 프라이버시

- 지오코딩 좌표 반올림·캐시.  
- raw_json place 저장 기본 off 가능.  
- 무서버 MVP.

### 축 E — 추측 한계

- 규칙 표 + conf cap.  
- vehicle 높은 속도만.  
- LLM 서술 자동 생성 제외.  
- evidence 필수로 디버그·신뢰.

### 축 F — 대안

| 대안 | 기술 평가 | 결정 |
|------|-----------|------|
| 1km split only | 레퍼런스 재현 쉬움, 회상 약함 | 보조 later |
| DBSCAN 체류 only | 장소엔 강, 이동 중 활동 약 | place 모듈에만 사용 |
| 온디바이스 activity recognition API | 보조 신호 later | MVP 비의존 (권한·기기 편차) |
| 분 윈도우+규칙 | 구현·테스트 용이 | **채택** |

### v1.1 기술 반영 요약

- SessionRollup ≠ sum(windows)  
- gap 비보간  
- hypothesis conf 임계  
- 플랫폼 가정 표 고정  
- export schema_version  

---

## 12. PRD ↔ TRD 추적 표

| PRD ID | TRD 절 / 구현 요소 | 충족 방식 | 제약·주의 |
|--------|-------------------|-----------|-----------|
| FR-01 | §4.1, §6 crash | SessionService start/stop, status enum | OS 킬 시 recovered |
| FR-02 | §4.1 LocationEngine | 모드별 주기 | 권한 종속 |
| FR-03 | UI + engine status | accuracy, mode 표시 | — |
| FR-04 | §3.3, §4.3 | minute_windows | tz 분 경계 |
| FR-05 | §3.3, §4.4 | metrics 필드 | quality 플래그 |
| FR-06 | §4.7, §4.9, §9.1 RouteMap | OSM 전체/진행/선택 폴리라인 + 현재 위치 | 타일 장애 시에도 경로 오버레이 유지 |
| FR-21 | §2 features 3탭 | 심플 IA | 탭 추가 금지 |
| FR-22 | §4.1 Android FGS | 알림+location type | 강요 설정 금지 |
| FR-07 | §4.4, §5 | speed/stationary | 정의 고정 |
| FR-08 | §4.5 places | geocode/cache | 오프라인 열화 |
| FR-09 | §4.5 category | P1 | 벤더 |
| FR-10 | §4.6 Inferencer | label+conf+evidence | 가설 |
| FR-11 | §3.3 user_* | update API | user 우선 |
| FR-12 | §4.6.1 | enum 라벨 | 확장 시 버전 |
| FR-13 | §4.8 | segments | P1 |
| FR-14 | QueryService | list/detail | — |
| FR-15 | §4.7 Rollup | summary fields | 레퍼런스 패리티 |
| FR-16 | §9 Export | NDJSON/JSON | P1 |
| FR-17 | — | later | 비구현 |
| FR-18 | §8 delete cascade | — | — |
| FR-19 | §1.3, §8 | SQLite only MVP | — |
| FR-20 | §4.5, §8 | round+cache | P1 |
| FR-24 | §8, §9.3 | 버전 백업 + transaction 병합 | 파일 자체 암호화는 P2 |
| FR-25 | §4.7.1 DailyActivityQuery | `WalkRepository.dailyStats` + Riverpod 7일 패널 | 로컬 시작일·완료 세션만; 목록 비필터 |
| NFR-01 | §4.3, §6 gaps | 커버리지/표시 | 조건부 |
| NFR-02 | §4.1 modes | balanced default | 기기차 |
| NFR-03 | §4.2 filter | jump/accuracy | — |
| NFR-04 | §8 | local, notice | 자문 아님 |
| NFR-05 | pipeline local | geocode optional | — |
| NFR-06 | indexes on windows | pagination | P1 목표 |
| NFR-07 | UI copy | 추정 용어 | i18n later |
| NFR-08 | §8 backup flags | PIN P2 | — |
| NFR-09 | §3 migration, §8 integrity/restore | 기존 행 보존 + atomic rollback | 손상 DB는 열기 중단 |
| G1–G5 | 전 파이프라인 | 메트릭·프라이버시 | — |

**역방향**: TRD의 모든 핵심 모듈은 위 표 PRD ID 중 하나 이상에 연결된다. 고아 기술 결정 없음.

---

## 13. 테스트 전략 (구현 단계 가이드 — 본 목표 비실행)

문서 산출 단계에서는 코드 테스트 없음. 구현 시 권장:

| 계층 | 내용 |
|------|------|
| 단위 | SampleFilter, Haversine distance, window bucketing, rule table fixtures |
| 골든 | 고정 GPS 트레이스 → 기대 windows JSON |
| 통합 | start→fake locations→stop→DB assert |
| 수동 | 실외 20분 산책, 카페 체류, 권한 거부 |

---

## 14. MVP 구현 체크리스트 (Flutter · Android)

1. Flutter 프로젝트 · Android 권한 · **FGS + 알림**  
2. `domain/` 분 윈도우·필터·롤업 + 단위 테스트  
3. sqflite 세션/샘플/윈도우 저장 + 크래시 복구  
4. **MapLibre + OSM 타일** + 폴리라인 + attribution  
5. 홈 시작/종료 · 라이브 3숫자 · 요약 카드 (러닝앱 심플 골격)  
6. 타임라인 + 활동 칩 수정  
7. 설정: 추적 모드 · 전체 백업/병합 복원 · 데이터 삭제 · 지도 정보
8. ~~(v1) VWorld 키~~ → **OSM 단일 베이스맵** (연동 제외)  
9. iOS `AppleSettings`·Background Modes 실험 지원; 출시 전 실기기/심사 검증

---

## 15. 변경 이력

| 버전 | 일자 | 내용 |
|------|------|------|
| 1.0 | 2026-07-12 | 초안: 스키마, 파이프라인, 규칙 표, 플랫폼, 매핑 |
| 1.1 | 2026-07-12 | 재검증: 롤업≠합, gap 비보간, conf 강등, 추적 표 보강, 배터리 모드 정렬 |
| 1.2 | 2026-07-12 | Flutter·Android FGS 고정, MapLibre+OSM/VWorld, 상용 SDK 배제, FR-21/22 매핑, 심플 모듈 경계 |
| 1.3 | 2026-07-29 | 수집 주기·거리 필터·WakeLock 완화, 장기 정지 및 3시간 자동 저장 종료 |
| 1.4 | 2026-07-31 | 지도–타임라인 연동, 경로 슬라이더·재생, 선택 구간 강조 및 보기/편집 분리 |
| 1.5 | 2026-08-01 | 전체 백업·원자적 병합 복원, DB 무결성/마이그레이션, 백그라운드 UI 절전, iOS background location·릴리스 서명 안전장치 |
| 1.6 | 2026-08-07 | 장기 기록 저장 재시도 내구성, 미관측 GPS gap 통계 제외, CARTO 타일 네트워크 고지, 릴리스 인증서 fail-closed 검증 |
| 1.7 | 2026-08-15 | 기록 화면 7일 일별 집계 API·Riverpod 상태·접근성 패널 매핑 추가 |
| 1.8 | 2026-08-16 | 전체 세션 자동 종료를 5시간으로 확대하고 4시간 45분 사전 안내로 조정 |

---

## 16. 참고

- PRD: [PRD.md](./PRD.md)  
- 플랫폼·지도 결정: [PLATFORM_AND_MAPS.md](./PLATFORM_AND_MAPS.md)  
- 영감 UX: 루트 `산책, 달리기 추적 앱.jpg`, `산책, 달리기 추적 앱2.jpg` (주기·NDJSON·맵·페이스/정지 메트릭)  
- VWorld: https://www.vworld.kr/ (국가 공간정보 오픈플랫폼)
