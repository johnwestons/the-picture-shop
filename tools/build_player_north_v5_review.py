"""Register two north passing candidates at the accepted fixed master scale."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/animation-overhaul-luna-player-v1/consistent-north-v5"
RUNTIME_V4 = ROOT / "assets/generated/player-walk-v4/walk_north.png"
SPEC_PATH = ROOT / "character-motion/rabbit-worker.json"
DEFAULT_RAW = {
    3: SOURCE / "north-v5-phase3-imagegen-generated-raw.png",
    7: SOURCE / "north-v5-phase7-imagegen-generated-raw.png",
}
DEFAULT_OUT = ROOT / "output/animation-overhaul/player-north-v5-review"
FRAME = 512
ACCEPTED_SCALE = 0.40773276015281634


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lua(value) -> str:
    if isinstance(value, dict):
        return "{" + ",".join("[" + json.dumps(key) + "]=" + lua(item) for key, item in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ",".join(lua(item) for item in value) + "}"
    return json.dumps(value)


def frame_strip(path: Path) -> list[Image.Image]:
    strip = Image.open(path).convert("RGBA")
    if strip.size != (FRAME * 8, FRAME):
        raise SystemExit(f"Unexpected strip size {strip.size}: {path}")
    return [strip.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(8)]


def visible_box(image: Image.Image, threshold: int = 16) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    mask = alpha.point(lambda value: 255 if value > threshold else 0)
    box = mask.getbbox()
    if box is None:
        raise SystemExit("Missing visible character")
    return box


def support_foot_anchor(image: Image.Image, side: str) -> tuple[float, float]:
    """Return the center of the bottom contact row on the nominated character side."""
    alpha = np.asarray(image.getchannel("A"))
    box = visible_box(image)
    x0, y0, x1, y1 = box
    center_x = (x0 + x1) / 2
    lower_y = y0 + round((y1 - y0) * 0.65)
    xs0, xs1 = (x0, round(center_x)) if side == "left" else (round(center_x), x1)
    points_y, points_x = np.where(alpha[lower_y:y1, xs0:xs1] > 64)
    if not len(points_x):
        raise SystemExit(f"No support-foot pixels on {side} side")
    points_y = points_y + lower_y
    points_x = points_x + xs0
    bottom = int(points_y.max())
    row_x = points_x[points_y == bottom]
    return float(np.median(row_x)), float(bottom)


def register(raw_path: Path, target: Image.Image, phase: int) -> tuple[Image.Image, dict]:
    raw = Image.open(raw_path).convert("RGBA")
    source_box = visible_box(raw)
    source_crop = raw.crop(source_box)
    target_box = visible_box(target)
    side = "left" if phase == 3 else "right"
    source_foot = support_foot_anchor(raw, side)
    target_foot = support_foot_anchor(target, side)
    target_w = max(1, round(source_crop.width * ACCEPTED_SCALE))
    target_h = max(1, round(source_crop.height * ACCEPTED_SCALE))
    # Premultiply alpha before resampling to prevent colored transparent pixels bleeding onto the outline.
    resized = source_crop.convert("RGBa").resize((target_w, target_h), Image.Resampling.LANCZOS).convert("RGBA")
    x = round((target_box[0] + target_box[2] - target_w) / 2)
    y = target_box[3] - target_h
    canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    canvas.alpha_composite(resized, (x, y))
    return canvas, {
        "raw_path": raw_path.relative_to(ROOT).as_posix(),
        "raw_sha256": sha256(raw_path),
        "raw_visible_bbox_alpha_gt16": list(source_box),
        "source_crop_size": list(source_crop.size),
        "accepted_fixed_scale": ACCEPTED_SCALE,
        "support_side": side,
        "source_support_foot_anchor_xy": list(source_foot),
        "target_support_foot_anchor_xy": list(target_foot),
        "registered_support_foot_y": round(y + (source_foot[1] - source_box[1]) * ACCEPTED_SCALE, 2),
        "support_foot_y_delta_from_original_px": round(y + (source_foot[1] - source_box[1]) * ACCEPTED_SCALE - target_foot[1], 2),
        "registered_size": [target_w, target_h],
        "target_visible_bbox_alpha_gt16": list(target_box),
        "registered_offset_xy": [x, y],
        "registered_visible_bbox_alpha_gt16": list(visible_box(canvas)),
    }


def composite_white(image: Image.Image) -> Image.Image:
    return Image.alpha_composite(Image.new("RGBA", image.size, (255, 255, 255, 255)), image)


def compare_metrics(before: Image.Image, after: Image.Image) -> dict:
    before_a = np.asarray(before.getchannel("A"))
    after_a = np.asarray(after.getchannel("A"))
    before_rgb = np.asarray(before.convert("RGB"))
    after_rgb = np.asarray(after.convert("RGB"))

    def fixed_band_widths(alpha: np.ndarray, rgb: np.ndarray, y0: int, y1: int, rule) -> list[int]:
        widths = []
        for y in range(y0, y1):
            row = np.flatnonzero((alpha[y] > 64) & rule(rgb[y]))
            if len(row):
                widths.append(int(row[-1] - row[0] + 1))
        return widths

    head_rule = lambda row: (row[:, 0] > 130) & (row[:, 1] > 45) & (row[:, 0] > row[:, 1] * 1.2) & (row[:, 1] > row[:, 2] * 1.1) & (row[:, 2] < 125)
    blue_rule = lambda row: (row[:, 2] > 70) & (row[:, 2] > row[:, 0] * 1.25) & (row[:, 1] > 35) & (row[:, 2] > row[:, 1] * 0.9)
    old_heads = fixed_band_widths(before_a, before_rgb, 170, 250, head_rule)
    new_heads = fixed_band_widths(after_a, after_rgb, 170, 250, head_rule)
    old_body = fixed_band_widths(before_a, before_rgb, 245, 335, blue_rule)
    new_body = fixed_band_widths(after_a, after_rgb, 245, 335, blue_rule)
    old_ink = int(((before_a > 64) & (before_rgb.max(axis=2) < 80)).sum())
    new_ink = int(((after_a > 64) & (after_rgb.max(axis=2) < 80)).sum())
    old_visible = int((before_a > 64).sum())
    new_visible = int((after_a > 64).sum())
    upper_region = np.zeros(before_a.shape, dtype=bool)
    upper_region[:330] = True
    old_mask = (before_a > 64) & upper_region
    new_mask = (after_a > 64) & upper_region
    changed_upper = int(np.logical_xor(old_mask, new_mask).sum() + ((before_rgb != after_rgb).any(axis=2) & old_mask & new_mask).sum())
    return {
        "before_visible_pixels": old_visible,
        "after_visible_pixels": new_visible,
        "visible_pixel_delta_percent": round((new_visible / max(1, old_visible) - 1) * 100, 2),
        "before_head_max_row_width_y170_249": max(old_heads) if old_heads else None,
        "after_head_max_row_width_y170_249": max(new_heads) if new_heads else None,
        "before_torso_median_row_width_y245_334": float(np.median(old_body)) if old_body else None,
        "after_torso_median_row_width_y245_334": float(np.median(new_body)) if new_body else None,
        "before_outline_ink_share_percent": round(100 * old_ink / max(1, old_visible), 2),
        "after_outline_ink_share_percent": round(100 * new_ink / max(1, new_visible), 2),
        "changed_pixels_in_upper_330px": changed_upper,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase3-raw", type=Path, default=DEFAULT_RAW[3])
    parser.add_argument("--phase7-raw", type=Path, default=DEFAULT_RAW[7])
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    raw_paths = {
        3: args.phase3_raw if args.phase3_raw.is_absolute() else ROOT / args.phase3_raw,
        7: args.phase7_raw if args.phase7_raw.is_absolute() else ROOT / args.phase7_raw,
    }
    out_dir = args.output_dir if args.output_dir.is_absolute() else ROOT / args.output_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    old = frame_strip(RUNTIME_V4)
    new = list(old)
    registrations = {}
    for phase, raw_path in raw_paths.items():
        registered, detail = register(raw_path, old[phase - 1], phase)
        new[phase - 1] = registered
        detail["registered_path"] = f"phase{phase}-registered.png"
        registered.save(out_dir / detail["registered_path"])
        registrations[str(phase)] = detail

    strip = Image.new("RGBA", (FRAME * 8, FRAME), (0, 0, 0, 0))
    for index, image in enumerate(new):
        strip.alpha_composite(image, (index * FRAME, 0))
    strip_path = out_dir / "north-v5-passing-candidates-uninstalled.png"
    strip.save(strip_path)

    labels = ["v4 phase 3", "v5 phase 3", "v4 phase 7", "v5 phase 7"]
    comparisons = [old[2], new[2], old[6], new[6]]
    contact = Image.new("RGBA", (4 * FRAME, FRAME + 26), (255, 255, 255, 255))
    draw = ImageDraw.Draw(contact)
    for index, (label, image) in enumerate(zip(labels, comparisons)):
        x = index * FRAME
        draw.text((x + 4, 5), label, fill=(0, 0, 0, 255))
        contact.alpha_composite(composite_white(image), (x, 26))
    contact.convert("RGB").save(out_dir / "north-v4-v5-passing-comparison-white.png")

    game = Image.new("RGBA", (64 * 8, 64 + 20), (255, 255, 255, 255))
    draw = ImageDraw.Draw(game)
    for index, image in enumerate(new):
        x = index * 64
        draw.text((x + 1, 3), f"K{index + 1}", fill=(0, 0, 0, 255))
        sized = image.resize((64, 64), Image.Resampling.LANCZOS)
        game.alpha_composite(composite_white(sized), (x, 20))
    game.convert("RGB").save(out_dir / "north-v5-64worldpx-cycle-white.png")

    metrics = {}
    original_phase_metrics = {}
    for phase in range(1, 9):
        image = new[phase - 1]
        box = visible_box(image)
        alpha = np.asarray(image.getchannel("A"))
        visible = alpha > 64
        rgb = np.asarray(image.convert("RGB"))
        # Restrict red-edge measurement to the visible contour, excluding the solid pouch tool.
        contour = visible & ~np.logical_and.reduce((np.roll(visible, 1, axis=0), np.roll(visible, -1, axis=0), np.roll(visible, 1, axis=1), np.roll(visible, -1, axis=1)))
        red_edge = contour & (rgb[:, :, 0] > rgb[:, :, 1] * 1.35) & (rgb[:, :, 0] > rgb[:, :, 2] * 1.35) & (rgb[:, :, 0] > 60)
        metrics[str(phase)] = {
            "alpha_gt16_bbox": list(box),
            "visible_height_px": box[3] - box[1],
            "visible_alpha_gt64_pixels": int(visible.sum()),
            "red_dominant_visible_contour_pixels": int(red_edge.sum()),
        }
    for phase in (3, 7):
        original_phase_metrics[str(phase)] = compare_metrics(old[phase - 1], new[phase - 1])

    report = {
        "version": 1,
        "status": "staged review only; no runtime/spec changes",
        "scope": "Replace only the two passing poses in the installed eight-phase north v4 strip; no new in-betweens.",
        "source_runtime": RUNTIME_V4.relative_to(ROOT).as_posix(),
        "source_runtime_sha256": sha256(RUNTIME_V4),
        "candidate_strip": strip_path.relative_to(ROOT).as_posix(),
        "candidate_strip_sha256": sha256(strip_path),
        "registration_method": "Accepted fixed north-master scale (no candidate-specific resizing); center on the original phase bbox and align its visible foot-ground baseline. Expected support foot is separately measured for each candidate.",
        "accepted_fixed_scale": ACCEPTED_SCALE,
        "registrations": registrations,
        "phase_metrics": metrics,
        "phase3_phase7_before_after_metrics": original_phase_metrics,
        "unchanged_phases": [1, 2, 4, 5, 6, 8],
        "review_note": "Review the full-resolution white contact, 64-world-pixel cycle and dark-background transparency before selection. The generated candidates must retain identity, anatomy, consistent head/body proportions, opposite foot ownership, low passes, and clean edges.",
    }
    report_path = out_dir / "north-v5-review.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    strip_relative = strip_path.relative_to(ROOT).as_posix()
    anchors = [{"x": 256, "y": 465} for _ in range(8)]
    bounds = [metrics[str(phase)]["alpha_gt16_bbox"] for phase in range(1, 9)]
    art_module = {
        "paths": {"rabbit-worker": {"walk_north": strip_relative}},
        "anchors": {"rabbit-worker": {"walk_north": anchors}},
        "metrics": {"rabbit-worker": {"walk_north": bounds}},
    }
    staged_source = out_dir / "src/player_walk_art.lua"
    staged_source.parent.mkdir(parents=True, exist_ok=True)
    staged_source.write_text("-- Staged review only; never installed by this builder.\nreturn " + lua(art_module) + "\n", encoding="utf-8")
    staging_spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    staging_spec["animations"]["walk_north"]["path"] = strip_relative
    staging_spec_path = out_dir / "staging-spec.json"
    staging_spec_path.write_text(json.dumps(staging_spec, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {strip_path.relative_to(ROOT)}")
    print(f"wrote {report_path.relative_to(ROOT)} sha256={sha256(report_path)}")
    print(f"wrote {staged_source.relative_to(ROOT)} and {staging_spec_path.relative_to(ROOT)} (review only)")


if __name__ == "__main__":
    main()
