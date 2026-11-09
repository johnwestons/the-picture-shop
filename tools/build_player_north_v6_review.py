"""Stage one root-scale-registered north-passing pose for visual review.

The accepted V5 cycle and raw ImageGen source are pinned. This tool never edits
runtime assets; its output is an isolated phase-7 candidate contact sheet.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "assets/source/animation-overhaul-luna-player-v1/consistent-north-v6/north-v6-phase7-imagegen-raw.png"
BASE = ROOT / "assets/generated/player-walk-v5/walk_north.png"
OUT = ROOT / "output/animation-overhaul/player-walk-cross-view-v5/passing-correction-iteration"
EXPECTED_RAW = "4d746ef37e1dad178e290b253565ef67e595d24c08b70942b97432f1b1c83eac"
EXPECTED_BASE = "09cd04db24b729e0d963590f2d24e1175f0e0cace11057c8929ff37be99af9bf"
FRAME = 512
SCALE = 0.40773276015281634
TARGET_PHASE = 7


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def visible_box(image: Image.Image, threshold: int = 16) -> tuple[int, int, int, int]:
    mask = image.getchannel("A").point(lambda value: 255 if value > threshold else 0)
    box = mask.getbbox()
    if box is None:
        raise SystemExit("Sprite is transparent")
    return box


def split_strip(image: Image.Image) -> list[Image.Image]:
    if image.size != (FRAME * 8, FRAME):
        raise SystemExit(f"Unexpected base dimensions: {image.size}")
    return [image.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(8)]


def lua(value) -> str:
    if isinstance(value, dict):
        return "{" + ",".join("[" + json.dumps(key) + "]=" + lua(item) for key, item in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ",".join(lua(item) for item in value) + "}"
    return json.dumps(value)


def stage() -> None:
    if sha(RAW) != EXPECTED_RAW or sha(BASE) != EXPECTED_BASE:
        raise SystemExit("Pinned source or installed V5 strip changed")

    raw = Image.open(RAW).convert("RGBA")
    if raw.size != (1254, 1254):
        raise SystemExit(f"Unexpected generated image size: {raw.size}")
    source_box = visible_box(raw)
    crop = raw.crop(source_box)
    resized_size = (round(crop.width * SCALE), round(crop.height * SCALE))
    resized = crop.convert("RGBa").resize(resized_size, Image.Resampling.LANCZOS).convert("RGBA")

    frames = split_strip(Image.open(BASE).convert("RGBA"))
    target = frames[TARGET_PHASE - 1]
    target_box = visible_box(target)
    target_center_x = (target_box[0] + target_box[2]) / 2
    x = round(target_center_x - resized.width / 2)
    y = target_box[3] - resized.height
    generated = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    generated.alpha_composite(resized, (x, y))
    # Keep the approved upper body pixel-identical. Restore the approved tail
    # and pouch over the generated legs where their lower edges overlap.
    candidate = generated.copy()
    candidate.paste(target.crop((0, 0, FRAME, 360)), (0, 0))
    rgba = np.array(target)
    yy, xx = np.indices(rgba.shape[:2])
    rgb, alpha = rgba[:, :, :3], rgba[:, :, 3]
    tail_seed = (alpha > 64) & (yy >= 300) & (yy <= 390) & (xx >= 210) & (xx <= 300) & (rgb[:, :, 0] > 190) & (rgb[:, :, 1] > 180) & (rgb[:, :, 2] > 170)
    pouch_seed = (alpha > 64) & (yy >= 300) & (yy <= 400) & (xx >= 292) & (xx <= 370) & (rgb[:, :, 0] > rgb[:, :, 1] * 1.18) & (rgb[:, :, 1] > rgb[:, :, 2] * 1.2)
    foreground = Image.fromarray(((tail_seed | pouch_seed).astype(np.uint8) * 255)).filter(ImageFilter.MaxFilter(11))
    foreground_arr = np.array(foreground)
    foreground_arr[:360, :] = 0
    overlay = target.copy()
    overlay.putalpha(Image.fromarray((alpha * (foreground_arr > 0)).astype(np.uint8)))
    candidate.alpha_composite(overlay)
    candidate_box = visible_box(candidate)
    height = candidate_box[3] - candidate_box[1]
    if not 408 <= height <= 413 or not 465 <= candidate_box[3] <= 469:
        raise SystemExit(f"Candidate missed accepted scale/baseline: bbox={candidate_box}")

    OUT.mkdir(parents=True, exist_ok=True)
    generated.save(OUT / "north-v6-phase7-generated-normalized.png")
    candidate.save(OUT / "north-v6-phase7-normalized.png")
    source_strip = Image.open(BASE).convert("RGBA")
    frames[TARGET_PHASE - 1] = candidate
    staged_strip = Image.new("RGBA", (FRAME * 8, FRAME), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        staged_strip.alpha_composite(frame, (i * FRAME, 0))
    staged_strip_path = OUT / "north-v6-candidate-strip.png"
    staged_strip.save(staged_strip_path)

    box_metrics = [list(visible_box(frame)) for frame in frames]
    relative_strip = staged_strip_path.relative_to(ROOT).as_posix()
    staged_module = {
        "paths": {"rabbit-worker": {"walk_north": relative_strip}},
        "anchors": {"rabbit-worker": {"walk_north": [{"x": 256, "y": 465} for _ in range(8)]}},
        "metrics": {"rabbit-worker": {"walk_north": box_metrics}},
    }
    module_dir = OUT / "src"
    module_dir.mkdir(parents=True, exist_ok=True)
    (module_dir / "player_walk_art.lua").write_text("-- Staged root review only; generated by tools/build_player_north_v6_review.py.\nreturn " + lua(staged_module) + "\n", encoding="utf-8")
    staging_spec = json.loads((ROOT / "character-motion/rabbit-worker.json").read_text(encoding="utf-8"))
    staging_spec["animations"]["walk_north"]["path"] = relative_strip
    (OUT / "north-v6-candidate-motion-spec.json").write_text(json.dumps(staging_spec, indent=2) + "\n", encoding="utf-8")

    contact = Image.new("RGBA", (FRAME * 4, FRAME * 2 + 24), (255, 255, 255, 255))
    draw = ImageDraw.Draw(contact)
    for i, frame in enumerate(frames):
        col, row = i % 4, i // 4
        x0, y0 = col * FRAME, row * FRAME
        draw.text((x0 + 4, y0 + 4), f"North phase {i + 1}" + (" (V6 staged)" if i + 1 == TARGET_PHASE else ""), fill=(15, 15, 15, 255))
        white = Image.alpha_composite(Image.new("RGBA", frame.size, (255, 255, 255, 255)), frame)
        contact.alpha_composite(white, (x0, y0 + 24))
    contact.convert("RGB").save(OUT / "north-v6-candidate-cycle-white.png")

    compare = Image.new("RGBA", (FRAME * 2, FRAME + 24), (255, 255, 255, 255))
    draw = ImageDraw.Draw(compare)
    draw.text((4, 4), "Installed V5 phase 7", fill=(15, 15, 15, 255))
    draw.text((FRAME + 4, 4), "Staged V6 phase 7", fill=(15, 15, 15, 255))
    for col, im in enumerate((split_strip(source_strip)[TARGET_PHASE - 1], candidate)):
        compare.alpha_composite(Image.alpha_composite(Image.new("RGBA", im.size, (255, 255, 255, 255)), im), (col * FRAME, 24))
    compare.convert("RGB").save(OUT / "north-v5-v6-phase7-white.png")

    checker = Image.new("RGBA", (FRAME, FRAME), (255, 255, 255, 255))
    draw = ImageDraw.Draw(checker)
    cell = 32
    for yy in range(0, FRAME, cell):
        for xx in range(0, FRAME, cell):
            if (xx // cell + yy // cell) % 2:
                draw.rectangle((xx, yy, xx + cell - 1, yy + cell - 1), fill=(210, 210, 210, 255))
    checker.alpha_composite(candidate)
    checker.save(OUT / "north-v6-phase7-checker.png")

    preview = Image.new("RGBA", (64 * 8, 88), (255, 255, 255, 255))
    draw = ImageDraw.Draw(preview)
    for i, frame in enumerate(frames):
        draw.text((i * 64 + 2, 2), f"K{i + 1}", fill=(15, 15, 15, 255))
        thumb = frame.resize((64, 64), Image.Resampling.LANCZOS)
        preview.alpha_composite(Image.alpha_composite(Image.new("RGBA", thumb.size, (255, 255, 255, 255)), thumb), (i * 64, 20))
    preview.convert("RGB").save(OUT / "north-v6-candidate-64px.png")
    enlarged = preview.resize((preview.width * 4, preview.height * 4), Image.Resampling.NEAREST)
    enlarged.save(OUT / "north-v6-candidate-64px-enlarged.png")

    rgba_candidate = np.array(candidate)
    rgb_candidate = rgba_candidate[:, :, :3]
    visible = rgba_candidate[:, :, 3] > 16
    magenta_fringe = visible & (rgb_candidate[:, :, 0] > 120) & (rgb_candidate[:, :, 2] > 120) & (rgb_candidate[:, :, 1] < 100)
    green_fringe = visible & (rgb_candidate[:, :, 1] > 120) & (rgb_candidate[:, :, 1] > rgb_candidate[:, :, 0] * 1.25) & (rgb_candidate[:, :, 1] > rgb_candidate[:, :, 2] * 1.25)
    old_pixels = np.array(target).astype(np.int16)
    changed_pixels = np.max(np.abs(old_pixels - rgba_candidate.astype(np.int16)), axis=2) > 24

    report = {
        "status": "staged only; not approved or integrated",
        "base_path": BASE.relative_to(ROOT).as_posix(),
        "base_sha256": EXPECTED_BASE,
        "raw_path": RAW.relative_to(ROOT).as_posix(),
        "raw_sha256": EXPECTED_RAW,
        "prompt_path": (RAW.parent / "north-v6-phase7-exact-prompt.txt").relative_to(ROOT).as_posix(),
        "target_phase": TARGET_PHASE,
        "only_changed_phase_in_candidate_contact": TARGET_PHASE,
        "accepted_fixed_scale": SCALE,
        "source_visible_bbox_alpha_gt16": list(source_box),
        "target_v5_bbox_alpha_gt16": list(target_box),
        "registration_offset_xy": [x, y],
        "candidate_bbox_alpha_gt16": list(candidate_box),
        "candidate_visible_height_px": height,
        "candidate_bottom_exclusive_y": candidate_box[3],
        "raw_corner_alpha": raw.getpixel((0, 0))[3],
        "raw_transparent_pixel_count": sum(1 for a in raw.getchannel("A").getdata() if a == 0),
        "raw_semtransparent_pixel_count": sum(1 for a in raw.getchannel("A").getdata() if 0 < a < 255),
        "candidate_magenta_edge_color_pixels_alpha_gt16": int(magenta_fringe.sum()),
        "candidate_green_edge_color_pixels_alpha_gt16": int(green_fringe.sum()),
        "phase7_changed_pixels_delta_gt24": int(changed_pixels.sum()),
        "phase7_changed_pixels_above_preservation_cut_y360": int(changed_pixels[:360].sum()),
        "staged_strip_path": staged_strip_path.relative_to(ROOT).as_posix(),
        "staged_motion_spec_path": (OUT / "north-v6-candidate-motion-spec.json").relative_to(ROOT).as_posix(),
        "staged_player_art_module_path": (module_dir / "player_walk_art.lua").relative_to(ROOT).as_posix(),
        "candidate_only_runtime_changes": False,
    }
    (OUT / "north-v6-candidate-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    stage()
