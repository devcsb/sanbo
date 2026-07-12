# TRD: 산보(Sanbo) — 위치 수집 · 분 윈도우 · 장소 · 활동 추측 기술 요구사항

| 항목 | 내용 |
|------|------|
| 문서 ID | `TRD-SANBO-v1.2` |
| 버전 | 1.2 (Flutter · Android · 한국 공개 지도 고정) |
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

버전 필드: `schema_version = 1`.

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
| `place_id` | integer? | FK places |
| `hypothesis_label` | string | FR-12 라벨 |
| `hypothesis_confidence` | float | 0–1 |
| `hypothesis_evidence_json` | text | JSON array of {code, detail} |
| `user_label` | string? | 사용자 확정/수정 |
| `user_note` | text? | |
| `user_confirmed` | bool | default false |

**유니크**: `(session_id, window_start)`.

### 3.4 `places`

| 필드 | 타입 | 설명 |
|------|------|------|
| `id` | integer | PK |
| `lat` | double | 질의 좌표(반올림 가능) |
| `lon` | double | |
| `name` | string? | |
| `category` | string? | `cafe` \| `park` \| `shop` \| `residential` \| `unknown` \| … |
| `provider` | string? | `nominatim` \| `apple` \| `google` \| `cache` \| `none` |
| `fetched_at` | datetime? | |
| `raw_json` | text? | 디버그; 설정으로 비활성 가능 |

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

| 모드 `tracking_mode` | 목표 주기 | 정확도 힌트 | 배터리 | 사용 |
|----------------------|-----------|-------------|--------|------|
| `battery_saver` | 10–15 s | 수백 m 허용 | 최저 | 장시간·저중요 |
| `balanced` (**default**) | **3–5 s** | ≤ 20–50 m 목표 | 중 | 산책 MVP |
| `high_accuracy` | **1–2 s** | 최고 (레퍼런스 2–3s 근접) | 고 | 사용자 선택 |

#### Android (MVP 필수)

| 항목 | 구현 요구 |
|------|-----------|
| 권한 | `ACCESS_FINE_LOCATION`; 백그라운드 필요 시 `ACCESS_BACKGROUND_LOCATION`은 **단계적 요청**(한 번에 몰아주기 금지) |
| 서비스 | `foregroundServiceType=location` + 진행 중 **고정 알림** (“산보: 산책 기록 중”) — FR-22 |
| 알림 채널 | 낮은 방해 우선순위 가능, 스와이프 종료 시 정책 명시(기록 중단 여부) |
| 배터리 | 최적화 예외 **강요 금지**; 설정 화면 딥링크 안내만 |
| 플러그인 가이드 | `geolocator` 등 + 네이티브 FGS 설정 문서화; 프로세스 킬 대비 체크포인트 |

#### iOS (Later)

- When In Use → Always 교육, `UIBackgroundModes: location`, 파란 상태바 기대 관리.  
- MVP 빌드에서 iOS 타깃 미포함 허용.

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

**역지오코딩**:

- 트리거: 체류 확정 시 또는 세션 종료 배치(배터리·프라이버시 유리).  
- 캐시 키: `round(lat,4), round(lon,4)` (~11m).  
- 실패/오프라인: `place=null`, category=`unknown`, 좌표는 윈도우에 유지.  
- P1: POI 카테고리 맵핑 테이블 (`cafe`, `restaurant` → `cafe_or_shop` 입력).

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

- `total_distance_m`: 전체 필터 경로  
- `moving_time_s` / `stationary_time_s`: 샘플 간격 기반  
- `avg_speed_mps`: distance / moving_time  
- `median_accuracy_m`, `valid_sample_count`  
- 단순화 폴리라인: Douglas-Peucker, ε ≈ 8–12 m (맵 표시용); raw는 samples에 유지

**매핑**: FR-15, 레퍼런스 요약 카드 패리티.

### 4.8 SegmentMerger (P1)

- 표시 라벨(`user_label ?? hypothesis_label`)이 동일하고 연속이며 둘 다 conf ≥ 0.4 (또는 user 확정)이면 병합.  
- `unknown` 단독 분 끼면 분리 유지.

**매핑**: FR-13.

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

체크포인트: 60s마다 또는 분 확정 시 WAL 커밋.

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
| iOS (Later) | When In Use | Always + Background Modes location | 동일 목적 문자열(한국어/영문 스토어 시) |

### 7.1.1 지도 · 네트워크 권한

| 항목 | MVP | 비고 |
|------|-----|------|
| 인터넷 | 타일 로드·(선택) 역지오코딩에 필요 | **오프라인**: 이미 캐시된 타일 범위 외 맵은 빈 격자 가능; **GPS 기록·DB는 오프라인 동작** |
| 타일 캐시 | MapLibre/HTTP 캐시 기본 활용 | 경로 좌표를 타일 서버에 보내지 않음 |

### 7.2 배터리 트레이드오프

| 모드 | 수집 | 지오코딩 | 맵 라이브 |
|------|------|----------|-----------|
| battery_saver | 10–15s | 종료 배치만 | 꺼짐 가능 |
| balanced | 3–5s | 체류 시 + 종료 | 요약 시 |
| high_accuracy | 1–2s | 더 잦음 | 옵션 |

NFR-02: 기본 balanced; 고주기는 토글.

### 7.3 정확도 vs 배터리

- 레퍼런스급 ±4m·2–3s는 **high_accuracy**에서만 기대.  
- balanced에서 속도 대역(걷 vs 정지) 분류는 유지 목표, 정밀 페이스 경쟁은 비목표.

---

## 8. 프라이버시 · 보안

| 통제 | 구현 |
|------|------|
| 저장 위치 | 앱 샌드박스 SQLite; 경로 설정 화면에 표시 (FR-19) |
| 네트워크 | MVP 기본 무전송. 지오코딩 옵트인 또는 기능 사용 시 최소 좌표 (FR-20) |
| 로그 | lat/lon 크래시 로그 금지; 세션 id만 |
| 삭제 | session cascade delete samples/windows/places 고아 정리 (FR-18) |
| Export | 사용자 명시; 파일에 schema_version; 공유 시트는 OS 공유 |
| 백업 | 플랫폼 백업 제외 플래그 권장(iOS exclude backup / Android auto-backup rules) — 위치 민감 |
| 암호화 | 기기 암호화 의존; SQLCipher는 P2 |
| 벤더 | 지오코딩 ToS·보관 정책 체크리스트 필수 (법무 자문 아님) |

**매핑**: NFR-04, NFR-08, 축 D.

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
session meta line (JSON)
one LocationSample per line (NDJSON)  OR  windows-only export option
```

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
| FR-06 | §4.7, §9.1 MapPort | OSM/VWorld 폴리라인 | 타일 장애 폴백 |
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
| NFR-01 | §4.3, §6 gaps | 커버리지/표시 | 조건부 |
| NFR-02 | §4.1 modes | balanced default | 기기차 |
| NFR-03 | §4.2 filter | jump/accuracy | — |
| NFR-04 | §8 | local, notice | 자문 아님 |
| NFR-05 | pipeline local | geocode optional | — |
| NFR-06 | indexes on windows | pagination | P1 목표 |
| NFR-07 | UI copy | 추정 용어 | i18n later |
| NFR-08 | §8 backup flags | PIN P2 | — |
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
7. 설정: 추적 모드 · 데이터 삭제 · (자리) 지도 소스  
8. ~~(v1) VWorld 키~~ → **OSM 단일 베이스맵** (연동 제외)  
9. (later) iOS LocationEngine  

---

## 15. 변경 이력

| 버전 | 일자 | 내용 |
|------|------|------|
| 1.0 | 2026-07-12 | 초안: 스키마, 파이프라인, 규칙 표, 플랫폼, 매핑 |
| 1.1 | 2026-07-12 | 재검증: 롤업≠합, gap 비보간, conf 강등, 추적 표 보강, 배터리 모드 정렬 |
| 1.2 | 2026-07-12 | Flutter·Android FGS 고정, MapLibre+OSM/VWorld, 상용 SDK 배제, FR-21/22 매핑, 심플 모듈 경계 |

---

## 16. 참고

- PRD: [PRD.md](./PRD.md)  
- 플랫폼·지도 결정: [PLATFORM_AND_MAPS.md](./PLATFORM_AND_MAPS.md)  
- 영감 UX: 루트 `산책, 달리기 추적 앱.jpg`, `산책, 달리기 추적 앱2.jpg` (주기·NDJSON·맵·페이스/정지 메트릭)  
- VWorld: https://www.vworld.kr/ (국가 공간정보 오픈플랫폼)
