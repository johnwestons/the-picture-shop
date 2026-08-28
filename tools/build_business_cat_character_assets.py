"""Build the reviewed multidirectional business-cat animation pack."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Sequence

from PIL import Image

from build_player_character_assets import (
    atomic_write,
    build_directional_idle_atlas,
    build_walk_atlas,
    png_bytes,
)
from character_sprite_doctor import audit_strip, render_contact_sheet


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "assets" / "Characters" / "BusinessCat"
RUNTIME_ROOT = ROOT / "assets" / "generated" / "characters" / "business-cat"
REVIEW_ROOT = ROOT / "output" / "sprite-doctor" / "business-cat-review"
IDLE_SOURCE = SOURCE_ROOT / "business-cat-directional-idle-v1.png"
WALK_SOURCES = {
    "walk": SOURCE_ROOT / "business-cat-walk-east-8pose-v1.png",
    "walk_north": SOURCE_ROOT / "business-cat-walk-north-8pose-v1.png",
    "walk_northeast": SOURCE_ROOT / "business-cat-walk-northeast-8pose-v1.png",
    "walk_southeast": SOURCE_ROOT / "business-cat-walk-southeast-8pose-v1.png",
    "walk_south": SOURCE_ROOT / "business-cat-walk-south-8pose-v1.png",
}


def runtime_metadata(audits: dict[str, object]) -> dict[str, object]:
    result: dict[str, object] = {"character": "business-cat", "actions": {}}
    for action, audit in audits.items():
        frames = []
        for metric in audit.metrics:
            if not metric.bbox:
                continue
            left, top, right, bottom = metric.bbox
            frames.append({
                "bounds": [left, top, right, bottom],
                "anchor": {"x": (left + right - 1) / 2, "y": bottom - 1},
            })
        result["actions"][action] = frames
    return result


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="install reviewed strips into the runtime pack")
    args = parser.parse_args(argv)

    preview_root = REVIEW_ROOT / "preview" / "business-cat"
    contact_root = REVIEW_ROOT / "contact-sheets" / "business-cat"
    built = build_directional_idle_atlas(IDLE_SOURCE)
    for action, source in WALK_SOURCES.items():
        built[action] = build_walk_atlas(source)
    built["sit"] = Image.open(RUNTIME_ROOT / "sit.png").convert("RGBA")

    audits = {}
    for action, strip in built.items():
        atomic_write(png_bytes(strip), preview_root / f"{action}.png")
        audit = audit_strip(strip, Path(f"{action}.png"))
        render_contact_sheet(audit, contact_root / f"{action}.png")
        audits[action] = audit

    report = {
        "strips": [audit.to_dict() for audit in audits.values()],
        "runtime_metadata": runtime_metadata(audits),
    }
    REVIEW_ROOT.mkdir(parents=True, exist_ok=True)
    (REVIEW_ROOT / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    errors = sum(audit.counts["error"] for audit in audits.values())
    warnings = sum(audit.counts["warning"] for audit in audits.values())
    print(f"Built {len(built)} business-cat strip(s): {errors} error(s), {warnings} warning(s)")
    print(f"Review contact sheets: {contact_root}")
    if errors:
        return 1
    if not args.apply:
        print(f"Preview only; runtime assets unchanged: {preview_root}")
        return 0
    for action, strip in built.items():
        if action == "sit":
            continue
        destination = RUNTIME_ROOT / f"{action}.png"
        atomic_write(png_bytes(strip), destination)
        print(f"installed {destination.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
