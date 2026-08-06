#!/usr/bin/env python3
"""
Structural verifier for Sanbo PRD/TRD documents.

Drives the real shipped artifacts under docs/ — not a re-implementation of
product logic. Exit 0 only when acceptance-critical structure is present.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRD = ROOT / "docs" / "PRD.md"
TRD = ROOT / "docs" / "TRD.md"
PLATFORM = ROOT / "docs" / "PLATFORM_AND_MAPS.md"
REF_IMAGE_NAMES = [
    "산책, 달리기 추적 앱.jpg",
    "산책, 달리기 추적 앱2.jpg",
]


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


def must_exist(path: Path) -> str:
    if not path.is_file():
        fail(f"missing file: {path}")
    text = path.read_text(encoding="utf-8")
    if len(text.strip()) < 500:
        fail(f"too short to be a deep doc: {path} ({len(text)} chars)")
    return text


def must_match_any(text: str, patterns: list[str], label: str) -> None:
    for p in patterns:
        if re.search(p, text, re.IGNORECASE | re.MULTILINE):
            return
    fail(f"{label}: none of {patterns!r} found")


def must_all(text: str, patterns: list[str], label: str) -> None:
    missing = [p for p in patterns if not re.search(p, text, re.IGNORECASE | re.MULTILINE)]
    if missing:
        fail(f"{label}: missing patterns {missing!r}")


def count_axes(text: str) -> int:
    """Count multi-axis review sections (축 A/B/C… or numbered axes)."""
    axes = set(re.findall(r"축\s*[A-F]|축\s*[1-6]|###\s*축\s+", text))
    # Also accept English-style "Axis A"
    axes |= set(re.findall(r"###\s*축\s+[A-F]", text))
    # PRD uses ### 축 A —
    found = re.findall(r"###\s*축\s+([A-F])\s*[—-]", text)
    return max(len(axes), len(set(found)))


def main() -> None:
    prd = must_exist(PRD)
    trd = must_exist(TRD)
    platform = must_exist(PLATFORM)

    # --- AC1 / verification plan 2: PRD concepts ---
    must_all(
        prd,
        [
            r"분\s*단위|minute\s*window|MinuteWindow",
            r"동선|경로",
            r"이동\s*속도|avg_speed|속도",
            r"장소|POI|역지오코딩|place",
            r"활동\s*추측|hypothesis|ActivityHypothesis",
            r"산책",
            r"영감|레퍼런스|Codex",
            r"MVP",
            r"FR-\d+",
            r"NFR-\d+",
            r"성공\s*지표",
            r"비목표|Out of Scope|Non-goals",
        ],
        "PRD core concepts",
    )

    # Inspiration images mentioned in PRD
    must_all(
        prd,
        [
            r"산책, 달리기 추적 앱\.jpg",
            r"산책, 달리기 추적 앱2\.jpg",
        ],
        "PRD inspiration image filenames",
    )
    # These are historical design references. They were intentionally removed
    # from the public repository; PRD filename citations remain useful for
    # traceability, but must not make the structural verifier fail.

    # Core flow section
    must_match_any(
        prd,
        [r"핵심\s*플로우", r"\[F0\]", r"세션 시작"],
        "PRD core flow",
    )

    # Activity inference features
    must_all(
        prd,
        [
            r"confidence|신뢰도",
            r"evidence|근거",
            r"walk_steady|속도 대역",
            r"시간대|hour",
        ],
        "PRD activity hypothesis shape",
    )

    # --- AC2 / plan 3: TRD pipeline & sections ---
    must_all(
        trd,
        [
            r"location_samples|LocationSample",
            r"minute_windows|MinuteWindow",
            r"WindowAggregator|분\s*윈도우|MinuteWindowAggregator",
            r"ActivityInferencer|활동\s*추측|Inferencer",
            r"SampleFilter|필터",
            r"권한|permission|Background",
            r"배터리|battery|tracking_mode",
            r"프라이버시|privacy",
            r"결측|gap|오류",
            r"지오코딩|geocod|POI|MapLibre|역지오",
            r"스키마|schema|필드",
        ],
        "TRD pipeline/sections",
    )

    # Pipeline order evidence
    must_match_any(
        trd,
        [r"SampleFilter\s*→", r"LocationSample.*MinuteWindow", r"처리 파이프라인"],
        "TRD pipeline narrative",
    )

    # --- AC3 / plan 4: cross-traceability ---
    must_all(
        prd,
        [r"TRD", r"FR-01", r"FR-10"],
        "PRD references TRD / IDs",
    )
    must_all(
        trd,
        [
            r"PRD",
            r"PRD\s*↔\s*TRD|추적\s*표|FR-01",
            r"FR-04",
            r"FR-10",
            r"NFR-01",
        ],
        "TRD traceability table",
    )
    # Mapping table should list multiple FR rows
    fr_rows = re.findall(r"\|\s*\*?FR-\d+\*?\s*\|", trd)
    if len(fr_rows) < 10:
        fail(f"TRD mapping table too thin: only {len(fr_rows)} FR rows")

    # --- AC4 / plan 5: multi-axis review ---
    prd_axes = count_axes(prd)
    trd_has_review = bool(
        re.search(r"다방면|재검증|축\s+[A-F]", trd, re.IGNORECASE)
    )
    if prd_axes < 4:
        fail(f"PRD review axes < 4 (found ~{prd_axes})")
    if not trd_has_review:
        fail("TRD missing multi-axis review section")
    # Each PRD axis should have 가정/위험/완화-ish content nearby
    for axis in ["A", "B", "C", "D"]:
        if not re.search(rf"축\s+{axis}[\s\S]{{0,800}}가정", prd):
            fail(f"PRD axis {axis} missing 가정 within following block")

    # --- AC5: MVP boundary + hypothesis not fact ---
    must_all(
        prd,
        [r"MVP\s*vs|후속", r"가설|사실이 아님|확정 표현 금지"],
        "PRD depth markers",
    )

    # --- Platform / Korea public maps / Flutter / simple UX ---
    must_all(
        prd,
        [
            r"Flutter",
            r"Android",
            r"OpenStreetMap|OSM",
            r"VWorld|브이월드",
            r"MapLibre",
            r"D-PLAT-01|D-MAP-01",
            r"심플|Borrow|3탭|FR-21",
        ],
        "PRD platform/map/simple decisions",
    )
    must_all(
        trd,
        [
            r"Flutter",
            r"Foreground Service|FGS|foregroundServiceType",
            r"MapLibre",
            r"osmPublic|OSM|OpenStreetMap",
            r"VWorld|vworld",
            r"D-MAP-0",
            r"domain/",
        ],
        "TRD Flutter/Android/map stack",
    )
    must_all(
        platform,
        [
            r"D-PLAT-01",
            r"D-MAP-01",
            r"D-UX-01",
            r"브이월드|VWorld",
            r"Borrow|가져올",
            r"Reject|가져오지 않을",
            r"MapLibre",
            r"Flutter",
        ],
        "PLATFORM_AND_MAPS decisions",
    )

    print("PASS: PRD and TRD structural verification")
    print(f"  PRD: {PRD} ({len(prd)} chars)")
    print(f"  TRD: {TRD} ({len(trd)} chars)")
    print(f"  PLATFORM: {PLATFORM} ({len(platform)} chars)")
    print(f"  PRD review axes (approx): {prd_axes}")
    print(f"  TRD FR mapping rows: {len(fr_rows)}")
    print(
        f"  Reference image citations: {len(REF_IMAGE_NAMES)} historical filenames; "
        "binary files intentionally not required"
    )


if __name__ == "__main__":
    main()
