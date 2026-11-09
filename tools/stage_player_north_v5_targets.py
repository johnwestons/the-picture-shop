"""Extract immutable north-v4 frames for a two-passing-pose ImageGen edit review."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
STRIP = ROOT / "assets/generated/player-walk-v4/walk_north.png"
OUT = ROOT / "assets/source/animation-overhaul-luna-player-v1/consistent-north-v5"
FRAME = 512
PHASES = (3, 7)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    strip = Image.open(STRIP).convert("RGBA")
    if strip.size != (FRAME * 8, FRAME):
        raise SystemExit(f"Unexpected north strip size: {strip.size}")
    OUT.mkdir(parents=True, exist_ok=True)
    records = {}
    for phase in PHASES:
        path = OUT / f"north-v4-phase{phase}-source.png"
        frame = strip.crop(((phase - 1) * FRAME, 0, phase * FRAME, FRAME))
        frame.save(path)
        Image.alpha_composite(Image.new("RGBA", frame.size, (255, 255, 255, 255)), frame).convert("RGB").save(
            OUT / f"north-v4-phase{phase}-source-white.png"
        )
        records[path.relative_to(ROOT).as_posix()] = {
            "sha256": sha256(path),
            "copied_from_runtime_phase": phase,
            "dimensions": [FRAME, FRAME],
        }
    generated = {}
    for phase in PHASES:
        for suffix, role in (("imagegen-generated-raw", "imagegen_raw_candidate"), ("exact-prompt", "exact_generation_prompt")):
            path = OUT / f"north-v5-phase{phase}-{suffix}.{ 'png' if suffix == 'imagegen-generated-raw' else 'txt' }"
            if path.exists():
                generated[path.relative_to(ROOT).as_posix()] = {
                    "sha256": sha256(path),
                    "role": role,
                }
    manifest = {
        "version": 1,
        "scope": "Two passing-pose edit candidates only; no in-betweens and no runtime changes.",
        "runtime_strip": STRIP.relative_to(ROOT).as_posix(),
        "runtime_strip_sha256": sha256(STRIP),
        "phase_order": ["phase3 right passing", "phase7 left passing"],
        "source_frames": records,
        "generated_artifacts": generated,
        "instructions": "Original north-v4 frames are preserved as source references. Review edited cells for exact two-ear anatomy, stable body scale, opposite leg ownership, compact low passes, clean alpha, and no red fringe before any selection.",
    }
    manifest_path = OUT / "source-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"staged {len(PHASES)} immutable phase references in {OUT}")
    print(f"manifest sha256: {sha256(manifest_path)}")


if __name__ == "__main__":
    main()
