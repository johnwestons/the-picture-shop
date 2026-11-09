"""Stage the eight authored high-five poses; install only after visual review.

No synthesized poses or source rewrites. Crops, a shared scale and boot anchors
convert the immutable ImageGen master to the game's horizontal-strip contract.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from statistics import median

from PIL import Image, ImageDraw

import build_visitor_character_assets as visitor
from build_worker_action_assets import lua

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/animation-overhaul-v1/rabbit-high-five-draft.png"
REVIEW = ROOT / "output/animation-overhaul/high-five-v5"
TARGET = ROOT / "assets/generated/characters/rabbit-worker/high-five-v5.png"
SIZE, HEIGHT, BASELINE = 512, 410, 465
PHASES = ["neutral", "anticipation", "raise", "extend", "contact", "recoil", "return", "settle"]
DURATIONS = [.08, .10, .12, .12, .10, .12, .18, .18]


def boot_axis(frame: Image.Image, box: tuple[int, int, int, int]) -> float:
    left, top, right, bottom = box
    alpha = frame.getchannel("A")
    rows = []
    for y in range(top + round((bottom - top) * .90), top + round((bottom - top) * .97)):
        row = alpha.crop((0, y, frame.width, y + 1)).point(lambda a: 255 if a > 128 else 0).getbbox()
        if row:
            rows.append((row[0] + row[2]) / 2)
    if not rows:
        raise ValueError("A planted boot anchor is required in every pose")
    return median(rows)


def build(apply: bool) -> None:
    REVIEW.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    source_manifest = ROOT / "assets/source/animation-overhaul-v1/high-five-manifest.json"
    if source_manifest.exists() and json.loads(source_manifest.read_text(encoding="utf-8"))["sha256"] != digest:
        raise ValueError("High-five source changed after review")
    image = Image.open(SOURCE).convert("RGBA")
    if image.size != (1536, 1024):
        raise ValueError("The reviewed source is a 1536x1024, four-column/two-row atlas")
    # The authored contact spark extends 26px beyond the nominal first cell.
    # These reviewed transparent-gutter crops retain it without admitting it
    # into the following recoil pose. No character pixels are erased.
    crops = [(i * 384, 0, (i + 1) * 384, 512) for i in range(4)]
    crops += [(0, 512, 464, 1024), (464, 512, 768, 1024),
              (768, 512, 1152, 1024), (1152, 512, 1536, 1024)]
    cells = [visitor.clean_export(image.crop(crop), 16) for crop in crops]
    boxes = [visitor.bounds(cell) for cell in cells]
    axes = [boot_axis(cell, box) for cell, box in zip(cells, boxes)]
    scale = HEIGHT / max(box[3] - box[1] for box in boxes)
    strip = Image.new("RGBA", (8 * SIZE, SIZE))
    anchors, metrics, frames, planted = [], [], [], []
    for index, (cell, box, axis) in enumerate(zip(cells, boxes, axes)):
        crop = cell.crop(box)
        crop = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.Resampling.LANCZOS)
        frame = Image.new("RGBA", (SIZE, SIZE))
        frame.alpha_composite(crop, (round(SIZE / 2 - (axis - box[0]) * scale), BASELINE - crop.height))
        frame = visitor.clean_export(frame, 4)
        bounds = visitor.bounds(frame)
        if min(bounds[0], bounds[1], SIZE - bounds[2], SIZE - bounds[3]) < 3:
            raise ValueError(f"Pose {index + 1} touches a cell boundary")
        frames.append(frame)
        strip.alpha_composite(frame, (index * SIZE, 0))
        anchors.append({"x": SIZE / 2, "y": BASELINE})
        metrics.append(list(bounds))
        planted.append(boot_axis(frame, bounds))
    if max(planted) - min(planted) > 2:
        raise ValueError(f"Boot anchor drift: {planted}")
    preview = REVIEW / "high-five-v5.png"
    strip.save(preview, optimize=True)
    contact = Image.new("RGBA", (4 * 240, 2 * 256), (30, 36, 42, 255))
    draw = ImageDraw.Draw(contact)
    for i, frame in enumerate(frames):
        x, y = i % 4 * 240, i // 4 * 256
        contact.alpha_composite(frame.resize((230, 230)), (x + 5, y + 20))
        draw.text((x + 6, y + 3), f"{i + 1}: {PHASES[i]}", fill=(240, 220, 160))
    contact.save(REVIEW / "contact-sheet.png")
    gif = []
    for frame in frames:
        background = Image.new("RGBA", (SIZE, SIZE), (38, 46, 54, 255))
        background.alpha_composite(frame)
        gif.append(background.convert("RGB"))
    gif[0].save(REVIEW / "high-five-v5.gif", save_all=True, append_images=gif[1:], loop=0,
                duration=[round(.95 * 1000 * d) for d in DURATIONS], disposal=2)
    manifest = {"generator": "OpenAI imagegen (built-in)", "source": SOURCE.relative_to(ROOT).as_posix(),
                "sha256": digest, "crops": crops, "review_status": "selected",
                "phases": PHASES, "duration_weights": DURATIONS, "boot_axes": planted,
                "scale": scale, "baseline": BASELINE, "runtime": TARGET.relative_to(ROOT).as_posix(),
                "prompt": "assets/source/animation-overhaul-v1/high-five-prompt.txt",
                "reviewed_audit_findings": {
                    "frame_5_detached_component": "Intentional contact spark; present only at impact.",
                    "center_jitter": "Extended arm moves the alpha-box center. Planted boot anchor drift is separately bounded to 2px."
                }}
    (REVIEW / "build-report.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    spec = json.loads((ROOT / "character-motion/rabbit-worker.json").read_text(encoding="utf-8"))
    spec["animations"]["high_five"] = {"path": preview.relative_to(ROOT).as_posix(),
        "frame_width": SIZE, "frame_height": SIZE, "frame_count": 8, "loop": False,
        "role": "gesture", "fps": 8 / .95}
    (REVIEW / "staging-spec.json").write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")
    if apply:
        TARGET.write_bytes(preview.read_bytes())
        art = {"path": TARGET.relative_to(ROOT).as_posix(), "frameSize": SIZE,
               "anchors": anchors, "metrics": metrics, "durationWeights": DURATIONS}
        (ROOT / "src/high_five_art.lua").write_text(
            "-- Generated by tools/build_high_five_v5.py from reviewed source art.\nreturn " + lua(art) + "\n", encoding="utf-8")
        spec["animations"]["high_five"]["path"] = TARGET.relative_to(ROOT).as_posix()
        (ROOT / "character-motion/rabbit-worker.json").write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")
        (ROOT / "assets/source/animation-overhaul-v1/high-five-manifest.json").write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"{'Installed' if apply else 'Staged'} {len(frames)} high-five poses; boot drift {max(planted) - min(planted):.2f}px")
    print(REVIEW)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="install after reviewing the staged contacts and audit")
    build(parser.parse_args().apply)
