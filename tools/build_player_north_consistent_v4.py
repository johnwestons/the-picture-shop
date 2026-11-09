"""Build the reviewed eight-frame north walk with the accepted phase-7 pass.

Stages under output/ by default. Pass --apply to install the strip and update
the motion spec plus src/player_walk_art.lua. Previous runtime strips remain.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from statistics import median

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/animation-overhaul-luna-player-v1/consistent-north-v2"
OUT = ROOT / "output/animation-overhaul/player-north-v4"
BASE_RAW = SOURCE / "north-consistent-v2-generated-raw.png"
BASE_NATIVE = ROOT / "output/animation-overhaul/luna-player/consistent-north-v2/north-v2-full8-native.png"
PHASE7_RAW = SOURCE / "north-v2-phase7-root-imageedit-generated-raw.png"
PHASE7_PROMPT = SOURCE / "north-v2-phase7-root-imageedit-exact-prompt.txt"
RUNTIME_REL = Path("assets/generated/player-walk-v4/walk_north.png")
BASE_NATIVE_SHA256 = "4477238ea7096cf078778b787f644be8d4433d06071b5f32366225aa6739466e"
EXPECTED = {
    "base_raw": "0fce24948744ba68d614af1e5a994b88659c05e5f840a54e80c5d0df661c63f7",
    "phase7_raw": "1880da44bb554d562e45f24c0a4fe820b39104ff404857121a520eacb6f85913",
    "phase7_prompt": "ab1afaf0be6e0aacd0a369bea38784ac42ddc93cda502020f2f98c530f524376",
}

SPEC_PATH = ROOT / "character-motion/rabbit-worker.json"
PLAYER_ART_PATH = ROOT / "src/player_walk_art.lua"
OLD_RUNTIME = "assets/generated/player-walk-v3/walk_north.png"

BASE_SPEC = ROOT / "tools/build_luna_north_consistent_v2.py"
MODULE_SPEC = importlib.util.spec_from_file_location("north_v2_base", BASE_SPEC)
base = importlib.util.module_from_spec(MODULE_SPEC)
assert MODULE_SPEC.loader is not None
MODULE_SPEC.loader.exec_module(base)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lua(value) -> str:
    if isinstance(value, dict):
        return "{" + ",".join("[" + json.dumps(key) + "]=" + lua(item) for key, item in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ",".join(lua(item) for item in value) + "}"
    return json.dumps(value)


def changed_pixels(first: Image.Image, second: Image.Image) -> int:
    difference = ImageChops.difference(first.convert("RGBA"), second.convert("RGBA"))
    return sum(pixel != (0, 0, 0, 0) for pixel in difference.get_flattened_data())


def normalized_base_frames() -> tuple[list[Image.Image], list[Image.Image], dict]:
    raw = Image.open(BASE_RAW).convert("RGBA")
    if raw.size != (1536, 1024):
        raise SystemExit(f"Unexpected base atlas dimensions: {raw.size}")
    source_cells = [
        raw.crop((col * 384, row * 512, (col + 1) * 384, (row + 1) * 512))
        for row in range(2)
        for col in range(4)
    ]
    boxes = [base.bbox_alpha(cell) for cell in source_cells]
    if any(box is None for box in boxes):
        raise SystemExit("One or more base cells are blank")
    heights = [box[3] - box[1] for box in boxes]
    scale = 410.0 / median(heights)
    dx = round(base.HEAD_CENTER_X - 192 * scale)
    dy = base.GROUND_Y - round(median([box[3] - 1 for box in boxes]) * scale)
    frames = [base.padded_cell(cell, scale, dx, dy) for cell in source_cells]

    native = Image.open(BASE_NATIVE).convert("RGBA")
    if native.size != (4096, 512) or sha(BASE_NATIVE) != BASE_NATIVE_SHA256:
        raise SystemExit("The pinned V2 normalized base strip is missing or changed")
    native_frames = [native.crop((i * 512, 0, (i + 1) * 512, 512)) for i in range(8)]
    if any(changed_pixels(expected, actual) for expected, actual in zip(frames, native_frames)):
        raise SystemExit("V2 normalization no longer reproduces the pinned base strip")
    return frames, native_frames, {
        "scale": scale,
        "translation_xy": [dx, dy],
        "source_visible_heights": heights,
    }


def register_phase7() -> tuple[Image.Image, dict]:
    source = Image.open(PHASE7_RAW).convert("RGBA")
    if source.size != (1254, 1254):
        raise SystemExit(f"Unexpected phase-7 source dimensions: {source.size}")
    box = base.bbox_alpha(source)
    if box is None:
        raise SystemExit("Phase-7 source is blank")
    pixels = source.load()
    orange_x = []
    head_end = min(source.height, box[1] + round((box[3] - box[1]) * 0.46))
    for y in range(box[1], head_end):
        for x in range(box[0], box[2]):
            if base.orange(*pixels[x, y]):
                orange_x.append(x)
    if not orange_x:
        raise SystemExit("Phase-7 head anchor could not be found")
    head_center_x = sum(orange_x) / len(orange_x)
    scale = base.K5_MASTER_SCALE
    scaled_box = [round(value * scale) for value in box]
    translation = [
        round(base.HEAD_CENTER_X - head_center_x * scale),
        base.GROUND_Y - (scaled_box[3] - 1),
    ]
    frame = base.padded_cell(source, scale, *translation)
    return frame, {
        "source_bbox_alpha_gt16": list(box),
        "head_anchor_centroid_x": head_center_x,
        "scale": scale,
        "translation_xy": translation,
        "metrics": base.metrics(frame),
    }


def build(apply: bool) -> None:
    for name, path in [("base_raw", BASE_RAW), ("phase7_raw", PHASE7_RAW), ("phase7_prompt", PHASE7_PROMPT)]:
        if sha(path) != EXPECTED[name]:
            raise SystemExit(f"Pinned {name} source mismatch: {path}")

    base_frames, native_frames, normalization = normalized_base_frames()
    phase7, registration = register_phase7()
    frames = list(base_frames)
    frames[6] = phase7

    updated_spec = None
    if apply:
        spec_text = SPEC_PATH.read_text(encoding="utf-8")
        old_quoted, new_quoted = json.dumps(OLD_RUNTIME), json.dumps(RUNTIME_REL.as_posix())
        old_count, new_count = spec_text.count(old_quoted), spec_text.count(new_quoted)
        if old_count == 1 and new_count == 0:
            updated_spec = spec_text.replace(old_quoted, new_quoted)
        elif old_count == 0 and new_count == 1:
            updated_spec = spec_text
        else:
            raise SystemExit("Expected exactly one current north walk path in the motion spec")
        json.loads(updated_spec)

    root = ROOT if apply else OUT
    runtime_path = root / RUNTIME_REL
    runtime_path.parent.mkdir(parents=True, exist_ok=True)
    strip = Image.new("RGBA", (base.FRAME * 8, base.FRAME), (0, 0, 0, 0))
    contact = Image.new("RGBA", (base.FRAME * 4, base.FRAME * 2), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * base.FRAME, 0))
        row, col = divmod(index, 4)
        contact.alpha_composite(frame, (col * base.FRAME, row * base.FRAME))
    strip.save(runtime_path)
    base.white_composite(contact).save(OUT / "north-v4-contact-white.png")
    base.make_gif(frames, OUT / "north-v4-64worldpx-timed.gif", duration_ms=130)

    v2_diffs = [changed_pixels(expected, actual) for expected, actual in zip(native_frames, frames)]
    if any(v2_diffs[index] for index in range(8) if index != 6):
        raise SystemExit("A phase other than phase 7 changed from the V2 source")
    metrics = [base.metrics(frame) for frame in frames]
    if any(item["visible_height_px"] < 408 or item["visible_height_px"] > 413 for item in metrics):
        raise SystemExit("A frame falls outside the reviewed 409-412px height band")
    bottom_rows = [item["alpha_bbox_threshold_16"][3] for item in metrics]
    if min(bottom_rows) < base.GROUND_Y or max(bottom_rows) > base.GROUND_Y + 3:
        raise SystemExit("A frame falls outside the accepted 0-3px foot/baseline tolerance")

    manifest = {
        "version": 1,
        "scope": "Root-reviewed eight-frame player north walk; the clean V2 full cycle is retained and only phase 7 is replaced with the compact opposite-side pass.",
        "runtime_path": RUNTIME_REL.as_posix(),
        "frame_size": [base.FRAME, base.FRAME],
        "frame_count": 8,
        "fps": 7.75,
        "sources": {
            BASE_RAW.relative_to(ROOT).as_posix(): EXPECTED["base_raw"],
            BASE_NATIVE.relative_to(ROOT).as_posix(): BASE_NATIVE_SHA256,
            PHASE7_RAW.relative_to(ROOT).as_posix(): EXPECTED["phase7_raw"],
            PHASE7_PROMPT.relative_to(ROOT).as_posix(): EXPECTED["phase7_prompt"],
        },
        "normalization": normalization,
        "phase7_registration": registration,
        "changed_pixel_count_by_phase_vs_v2": v2_diffs,
        "phase_metrics": metrics,
        "review": "Root compared phase 3 and phase 7 at the fixed 410px scale, checked the full eight-phase contact and timed 64px loop on white. Phase 3 and phase 7 use opposite screen-side free legs; phase 7 passes low under the pelvis, with a narrower tread presentation than phase 3. Transparent edges are clean on white. Other seven phases are exact V2 pixels.",
    }
    (runtime_path.parent / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    anchors = [{"x": base.HEAD_CENTER_X, "y": base.GROUND_Y - 1} for _ in range(8)]
    bounds = []
    for index in range(8):
        box = frames[index].getchannel("A").point(lambda value: 255 if value > base.ALPHA_THRESHOLD else 0).getbbox()
        if box is None:
            raise SystemExit(f"Phase {index + 1} is blank after packing")
        bounds.append(list(box))
    module = {
        "paths": {"rabbit-worker": {"walk_north": RUNTIME_REL.as_posix()}},
        "anchors": {"rabbit-worker": {"walk_north": anchors}},
        "metrics": {"rabbit-worker": {"walk_north": bounds}},
    }
    module_text = "-- Generated by tools/build_player_north_consistent_v4.py.\nreturn " + lua(module) + "\n"

    if apply:
        PLAYER_ART_PATH.write_text(module_text, encoding="utf-8")
        assert updated_spec is not None
        SPEC_PATH.write_text(updated_spec, encoding="utf-8")
    else:
        preview_spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
        preview_spec["animations"]["walk_north"]["path"] = RUNTIME_REL.as_posix()
        preview = OUT / "player_walk_art.lua"
        preview.parent.mkdir(parents=True, exist_ok=True)
        preview.write_text(module_text, encoding="utf-8")
        (OUT / "rabbit-worker-preview.json").write_text(json.dumps(preview_spec, indent=2) + "\n", encoding="utf-8")

    audit_path = OUT / "north-v4-audit.json"
    audit_path.write_text(json.dumps({
        "applied": apply,
        "runtime_path": RUNTIME_REL.as_posix(),
        "runtime_sha256": sha(runtime_path),
        "source_manifest_path": (runtime_path.parent / "manifest.json").relative_to(ROOT).as_posix() if apply else (runtime_path.parent / "manifest.json").relative_to(OUT).as_posix(),
        "contact_sheet": "north-v4-contact-white.png",
        "timed_preview": "north-v4-64worldpx-timed.gif",
        "phase_metrics": metrics,
        "changed_pixel_count_by_phase_vs_v2": v2_diffs,
        "checks": {
            "dimensions_4096x512": list(Image.open(runtime_path).size) == [4096, 512],
            "8_frames": len(frames) == 8,
            "only_phase7_changed": sum(v2_diffs[index] != 0 for index in range(8)) == 1,
            "baseline_y466_with_3px_pose_tolerance": min(bottom_rows) >= base.GROUND_Y and max(bottom_rows) <= base.GROUND_Y + 3,
            "visible_height_within_408_413": all(408 <= item["visible_height_px"] <= 413 for item in metrics),
        },
    }, indent=2) + "\n", encoding="utf-8")
    print(("Installed" if apply else "Staged") + f" reviewed north walk v4: {runtime_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="install runtime art and update metadata")
    build(parser.parse_args().apply)
