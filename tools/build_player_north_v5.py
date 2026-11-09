"""Build the reviewed north passing-pose pair at the frozen accepted scale.

Stages a candidate under output/ by default. Pass --apply to install the strip,
motion-spec path and player-walk metadata. Source art is never overwritten.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/animation-overhaul-luna-player-v1/consistent-north-v5"
OUT = ROOT / "output/animation-overhaul/player-north-v5-install-review"
OLD_STRIP = ROOT / "assets/generated/player-walk-v4/walk_north.png"
RUNTIME_REL = Path("assets/generated/player-walk-v5/walk_north.png")
SPEC_PATH = ROOT / "character-motion/rabbit-worker.json"
PLAYER_ART_PATH = ROOT / "src/player_walk_art.lua"
MANIFEST_PATH = ROOT / "assets/generated/player-walk-v5/manifest.json"
FRAME = 512
SCALE = 0.40773276015281634
EXPECTED = {
    "v4_strip": "c01210e2a7fc8cb796591ff6aa217f3c6e730af386f9e541366b5f1bc3cf14fc",
    "phase3_raw": "430f4eafabfb7f3ebf21af204bf9c8c05424bf1f3e36f7a595648de2d05d8960",
    "phase7_raw": "34df3586c8c04f6414b976936743d3bdb19f9a8e9d580295d952d474f33c42e8",
    "phase7_prompt": "a65317aa37cca1388186452084d22ddd73fef4b6b784125d18a4709bf30288e8",
}
SOURCES = {
    3: SOURCE / "north-v5-phase3-iteration2-imagegen-generated-raw.png",
    7: SOURCE / "north-v5-phase7-lowerbody-only-edit01-imagegen-generated-raw.png",
}
PROMPTS = {
    7: SOURCE / "north-v5-phase7-lowerbody-only-edit01-exact-prompt.txt",
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lua(value) -> str:
    if isinstance(value, dict):
        return "{" + ",".join("[" + json.dumps(key) + "]=" + lua(item) for key, item in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ",".join(lua(item) for item in value) + "}"
    return json.dumps(value)


def visible_box(image: Image.Image, threshold: int = 16) -> tuple[int, int, int, int]:
    mask = image.getchannel("A").point(lambda value: 255 if value > threshold else 0)
    box = mask.getbbox()
    if box is None:
        raise SystemExit("Sprite frame is transparent")
    return box


def split_strip(path: Path) -> list[Image.Image]:
    strip = Image.open(path).convert("RGBA")
    if strip.size != (FRAME * 8, FRAME):
        raise SystemExit(f"Unexpected eight-frame strip size {strip.size}: {path}")
    return [strip.crop((index * FRAME, 0, (index + 1) * FRAME, FRAME)) for index in range(8)]


def register(phase: int, raw_path: Path, target: Image.Image) -> tuple[Image.Image, dict]:
    raw = Image.open(raw_path).convert("RGBA")
    if raw.size != (1254, 1254):
        raise SystemExit(f"Unexpected phase {phase} source size {raw.size}")
    source_box = visible_box(raw)
    target_box = visible_box(target)
    crop = raw.crop(source_box)
    width = max(1, round(crop.width * SCALE))
    height = max(1, round(crop.height * SCALE))
    resized = crop.convert("RGBa").resize((width, height), Image.Resampling.LANCZOS).convert("RGBA")
    x = round((target_box[0] + target_box[2] - width) / 2)
    y = target_box[3] - height
    frame = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    frame.alpha_composite(resized, (x, y))
    return frame, {
        "source_path": raw_path.relative_to(ROOT).as_posix(),
        "source_sha256": sha(raw_path),
        "source_visible_bbox_alpha_gt16": list(source_box),
        "accepted_fixed_scale": SCALE,
        "target_visible_bbox_alpha_gt16": list(target_box),
        "registered_offset_xy": [x, y],
        "registered_visible_bbox_alpha_gt16": list(visible_box(frame)),
        "visible_height_px": visible_box(frame)[3] - visible_box(frame)[1],
    }


def metrics(frames: list[Image.Image]) -> list[list[int]]:
    result = []
    for frame in frames:
        box = visible_box(frame)
        if not 408 <= box[3] - box[1] <= 413:
            raise SystemExit(f"Phase height outside reviewed scale band: {box[3] - box[1]}px")
        if not 465 <= box[3] <= 469:
            raise SystemExit(f"Phase bottom outside accepted foot baseline: y={box[3] - 1}")
        result.append(list(box))
    return result


def build(apply: bool) -> None:
    expected_files = {
        OLD_STRIP: EXPECTED["v4_strip"],
        SOURCES[3]: EXPECTED["phase3_raw"],
        SOURCES[7]: EXPECTED["phase7_raw"],
        PROMPTS[7]: EXPECTED["phase7_prompt"],
    }
    for path, expected in expected_files.items():
        if sha(path) != expected:
            raise SystemExit(f"Pinned input changed: {path}")

    frames = split_strip(OLD_STRIP)
    registrations = {}
    for phase in (3, 7):
        frames[phase - 1], registrations[str(phase)] = register(phase, SOURCES[phase], frames[phase - 1])
    boxes = metrics(frames)

    output_root = ROOT if apply else OUT
    runtime_path = output_root / RUNTIME_REL
    runtime_path.parent.mkdir(parents=True, exist_ok=True)
    strip = Image.new("RGBA", (FRAME * 8, FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME, 0))
    strip_buffer = io.BytesIO()
    strip.save(strip_buffer, format="PNG")
    strip_bytes = strip_buffer.getvalue()
    runtime_file_sha = hashlib.sha256(strip_bytes).hexdigest()
    if apply and runtime_path.exists() and sha(runtime_path) != runtime_file_sha:
        raise SystemExit(f"Refusing to overwrite an existing different runtime strip: {runtime_path}")
    runtime_path.write_bytes(strip_bytes)

    staged_runtime_rel = runtime_path.relative_to(ROOT).as_posix()
    module_runtime_path = RUNTIME_REL.as_posix() if apply else staged_runtime_rel
    module = {
        "paths": {"rabbit-worker": {"walk_north": module_runtime_path}},
        "anchors": {"rabbit-worker": {"walk_north": [{"x": 256, "y": 465} for _ in range(8)]}},
        "metrics": {"rabbit-worker": {"walk_north": boxes}},
    }
    module_text = "-- Generated by tools/build_player_north_v5.py.\nreturn " + lua(module) + "\n"

    manifest = {
        "version": 1,
        "status": "installed and root-reviewed" if apply else "staged review only; no runtime/spec changes",
        "scope": "Replace only north-walk phases 3 and 7 in the installed V4 cycle; no extra in-betweens.",
        "runtime_path": RUNTIME_REL.as_posix(),
        "runtime_sha256": runtime_file_sha,
        "frame_size": [FRAME, FRAME],
        "frame_count": 8,
        "fps": 7.75,
        "base_strip": OLD_STRIP.relative_to(ROOT).as_posix(),
        "base_strip_sha256": EXPECTED["v4_strip"],
        "phase_order": ["left_contact", "left_weight_down", "right_passing", "right_knee_up", "right_contact", "right_weight_down", "left_passing", "left_knee_up"],
        "accepted_scale": SCALE,
        "phase_registrations": registrations,
        "phase3_generation_id": "exec-c6e29136-5057-49c5-a42d-7f665ac37172.png",
        "phase3_prompt_status": "Original iteration2 tool prompt not retained; raw candidate is pinned by SHA-256 and preserved unchanged.",
        "phase7_prompt": PROMPTS[7].relative_to(ROOT).as_posix(),
        "phase7_prompt_sha256": EXPECTED["phase7_prompt"],
        "phase_metrics_alpha_gt16_bbox": boxes,
        "changed_phases": [3, 7],
        "review": "Phase 3 uses a flat left support and compact, occluded right pass. Phase 7 uses a flat right support and low left pass. Root reviewed both at fixed scale, white/checkerboard and 64px, across all five authored views, and through 32 local/guest production captures on desktop and landscape phone layouts.",
    }
    manifest_text = json.dumps(manifest, indent=2) + "\n"

    if apply:
        spec_text = SPEC_PATH.read_text(encoding="utf-8")
        old_path, new_path = json.dumps("assets/generated/player-walk-v4/walk_north.png"), json.dumps(RUNTIME_REL.as_posix())
        if spec_text.count(old_path) == 1 and spec_text.count(new_path) == 0:
            updated_spec = spec_text.replace(old_path, new_path)
        elif spec_text.count(old_path) == 0 and spec_text.count(new_path) == 1:
            updated_spec = spec_text
        else:
            raise SystemExit("Expected exactly one north-walk path in the character motion spec")
        json.loads(updated_spec)
        PLAYER_ART_PATH.write_text(module_text, encoding="utf-8")
        SPEC_PATH.write_text(updated_spec, encoding="utf-8")
        MANIFEST_PATH.write_text(manifest_text, encoding="utf-8")
    else:
        staged_source = OUT / "src/player_walk_art.lua"
        staged_source.parent.mkdir(parents=True, exist_ok=True)
        staged_source.write_text(module_text, encoding="utf-8")
        staging_spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
        staging_spec["animations"]["walk_north"]["path"] = (OUT / RUNTIME_REL).relative_to(ROOT).as_posix()
        (OUT / "staging-spec.json").write_text(json.dumps(staging_spec, indent=2) + "\n", encoding="utf-8")
        (OUT / "manifest.json").write_text(manifest_text, encoding="utf-8")

    contact = Image.new("RGBA", (FRAME * 4, FRAME * 2), (255, 255, 255, 255))
    for index, frame in enumerate(frames):
        contact.alpha_composite(Image.alpha_composite(Image.new("RGBA", frame.size, (255, 255, 255, 255)), frame), ((index % 4) * FRAME, (index // 4) * FRAME))
    output_contact = (output_root / RUNTIME_REL.parent / "north-v5-contact-white.png") if apply else OUT / "north-v5-contact-white.png"
    output_contact.parent.mkdir(parents=True, exist_ok=True)
    contact.convert("RGB").save(output_contact)
    preview = Image.new("RGBA", (64 * 8, 64 + 24), (255, 255, 255, 255))
    draw = ImageDraw.Draw(preview)
    for index, frame in enumerate(frames):
        draw.text((index * 64 + 1, 3), f"K{index + 1}", fill=(0, 0, 0, 255))
        sized = frame.resize((64, 64), Image.Resampling.LANCZOS)
        white = Image.alpha_composite(Image.new("RGBA", sized.size, (255, 255, 255, 255)), sized)
        preview.alpha_composite(white, (index * 64, 24))
    preview.convert("RGB").save(OUT / "north-v5-64worldpx-cycle-white.png")
    print(("Installed" if apply else "Staged") + f" north walk v5: {runtime_path}")
    print(f"strip_sha256={runtime_file_sha}")
    print(f"phase3_height={registrations['3']['visible_height_px']} phase7_height={registrations['7']['visible_height_px']}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="install the reviewed strip and update runtime metadata")
    build(parser.parse_args().apply)
