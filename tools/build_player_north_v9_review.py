"""Build a review-only fixed-scale North passing-pose candidate."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/animation-overhaul-luna-player-v1/consistent-north-v9/generated"
BASE = ROOT / "assets/generated/player-walk-v6/walk_north.png"
OUT = ROOT / "output/animation-overhaul/player-north-v9"
FRAME = 512
SCALE = 0.40773276015281634
PRESERVE_Y = 344
BLEND_END_Y = 374
PHASES = {
    # On a rear view the character's left/right match viewer-left/viewer-right.
    # The two generated poses are cross-assigned because the first drafts followed
    # the originally reversed wording rather than the phase ownership.
    3: ("north-phase7-imagegen-raw-v2.png", "651246a523225921a700a237c642b82766c9d838058bb2ca2ae02ba824c27c3f"),
    7: ("north-phase3-imagegen-raw-v2.png", "ed64d18039587538a0d729efed32a4dcd8c2e8a5f446b36e137d22d9a7f8ce46"),
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def box_alpha(image: Image.Image, threshold: int = 16) -> tuple[int, int, int, int]:
    box = image.getchannel("A").point(lambda value: 255 if value > threshold else 0).getbbox()
    if box is None:
        raise SystemExit("Sprite is transparent")
    return box


def frames(path: Path) -> list[Image.Image]:
    sheet = Image.open(path).convert("RGBA")
    if sheet.size != (FRAME * 8, FRAME):
        raise SystemExit(f"Unexpected North strip dimensions: {sheet.size}")
    return [sheet.crop((index * FRAME, 0, (index + 1) * FRAME, FRAME)) for index in range(8)]


def register(raw_path: Path, target: Image.Image, debug_path: Path) -> tuple[Image.Image, dict]:
    raw = Image.open(raw_path).convert("RGBA")
    if raw.size != (1254, 1254):
        raise SystemExit(f"Unexpected generated image size: {raw.size}")
    alpha = np.asarray(raw.getchannel("A"))
    yy, xx = np.nonzero(alpha >= 128)
    if len(xx) == 0:
        raise SystemExit("Generated pose has no opaque character pixels")
    # Ignore isolated transparent-edge specks while keeping a small antialiased border.
    main = (max(0, int(xx.min()) - 4), max(0, int(yy.min()) - 4),
            min(raw.width, int(xx.max()) + 5), min(raw.height, int(yy.max()) + 5))
    crop = raw.crop(main)
    size = (round(crop.width * SCALE), round(crop.height * SCALE))
    resized = crop.convert("RGBa").resize(size, Image.Resampling.LANCZOS).convert("RGBA")
    target_box = box_alpha(target)
    target_center = (target_box[0] + target_box[2]) / 2
    x = round(target_center - resized.width / 2)
    y = target_box[3] - resized.height
    registered = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    registered.alpha_composite(resized, (x, y))
    registered.save(debug_path)
    # Retain the exact upper body, then blend the trouser transition so it does not
    # introduce a hard horizontal cut through the waistband or thigh contours.
    original_premultiplied = np.asarray(target.convert("RGBa")).astype(np.float32)
    generated_premultiplied = np.asarray(registered.convert("RGBa")).astype(np.float32)
    mix = np.clip((np.arange(FRAME, dtype=np.float32) - PRESERVE_Y) / (BLEND_END_Y - PRESERVE_Y), 0.0, 1.0)
    mix = mix[:, None, None]
    blended = (original_premultiplied * (1.0 - mix) + generated_premultiplied * mix).clip(0, 255).astype(np.uint8)
    candidate = Image.fromarray(blended, "RGBa").convert("RGBA")
    candidate.paste(target.crop((0, 0, FRAME, PRESERVE_Y)), (0, 0))
    target_rgba = np.asarray(target.convert("RGBA"))
    yy_grid, xx_grid = np.indices(target_rgba.shape[:2])
    rgb, a = target_rgba[:, :, :3], target_rgba[:, :, 3]
    tail = ((a > 64) & (yy_grid >= 300) & (yy_grid <= 390) & (xx_grid >= 210) & (xx_grid <= 300)
            & (rgb[:, :, 0] > 190) & (rgb[:, :, 1] > 180) & (rgb[:, :, 2] > 170))
    pouch = ((a > 64) & (yy_grid >= 300) & (yy_grid <= 400) & (xx_grid >= 292) & (xx_grid <= 370)
             & (rgb[:, :, 0] > rgb[:, :, 1] * 1.18) & (rgb[:, :, 1] > rgb[:, :, 2] * 1.2))
    accessory_mask = Image.fromarray(((tail | pouch).astype(np.uint8) * 255)).filter(ImageFilter.MaxFilter(25))
    preserve_accessory = np.asarray(accessory_mask) > 0
    accessory_alpha = (a * preserve_accessory.astype(np.uint8)).astype(np.uint8)
    accessory_alpha[:PRESERVE_Y, :] = 0
    overlay = target.copy()
    overlay.putalpha(Image.fromarray(accessory_alpha))
    candidate.alpha_composite(overlay)

    return candidate, {
        "raw_path": raw_path.relative_to(ROOT).as_posix(),
        "raw_sha256": sha(raw_path),
        "raw_alpha_gt16_bbox_including_specks": list(box_alpha(raw, 16)),
        "raw_opaque_bbox": [int(xx.min()), int(yy.min()), int(xx.max()) + 1, int(yy.max()) + 1],
        "registration_crop": list(main),
        "fixed_scale": SCALE,
        "registered_size": list(resized.size),
        "registered_offset_xy": [x, y],
        "target_bbox": list(target_box),
        "candidate_bbox": list(box_alpha(candidate)),
        "upper_body_changed_pixels_before_blend_band": int(np.count_nonzero(
            np.any(np.asarray(candidate)[:PRESERVE_Y] != np.asarray(target)[:PRESERVE_Y], axis=2))),
        "blend_band_y": [PRESERVE_Y, BLEND_END_Y],
    }


def white_composite(image: Image.Image) -> Image.Image:
    background = Image.new("RGBA", image.size, (255, 255, 255, 255))
    return Image.alpha_composite(background, image)


def lua(value) -> str:
    if isinstance(value, dict):
        return "{" + ",".join("[" + json.dumps(key) + "]=" + lua(item) for key, item in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ",".join(lua(item) for item in value) + "}"
    return json.dumps(value)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    base = frames(BASE)
    records = {}
    for phase, (name, expected_hash) in PHASES.items():
        raw_path = SOURCE / name
        if sha(raw_path) != expected_hash:
            raise SystemExit(f"Pinned generated source changed: {name}")
        candidate, record = register(raw_path, base[phase - 1], OUT / f"phase{phase}-raw-registered-debug.png")
        base[phase - 1] = candidate
        records[str(phase)] = record

    strip = Image.new("RGBA", (FRAME * 8, FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(base):
        strip.alpha_composite(frame, (index * FRAME, 0))
    strip_path = OUT / "north-v9-passing-pose-candidate-strip.png"
    strip.save(strip_path)

    contact = Image.new("RGBA", (FRAME * 4, FRAME * 2 + 28), (255, 255, 255, 255))
    draw = ImageDraw.Draw(contact)
    original = frames(BASE)
    for index, frame in enumerate(base):
        x, y = (index % 4) * FRAME, (index // 4) * FRAME
        draw.text((x + 4, y + 4), f"North phase {index + 1}" + (" (v9 candidate)" if index + 1 in PHASES else ""), fill=(10, 10, 10, 255))
        contact.alpha_composite(white_composite(frame), (x, y + 28))
    contact.convert("RGB").save(OUT / "north-v9-full-cycle-white.png")

    compare = Image.new("RGBA", (FRAME * 4, FRAME + 28), (255, 255, 255, 255))
    draw = ImageDraw.Draw(compare)
    for column, phase in enumerate((3, 7)):
        for row, frame in enumerate((original[phase - 1], base[phase - 1])):
            x = (column * 2 + row) * FRAME
            draw.text((x + 4, 4), f"phase {phase} {'current' if row == 0 else 'v9 candidate'}", fill=(10, 10, 10, 255))
            compare.alpha_composite(white_composite(frame), (x, 28))
    compare.convert("RGB").save(OUT / "north-v9-passing-pose-comparison.png")

    # Also stage the generated frames whole to compare against the soft-blended
    # lower-body version. Uniform fitting keeps each view's existing height and
    # sole baseline while avoiding a horizontal splice through the character.
    fullbody = list(original)
    fullbody_records = {}
    for phase in PHASES:
        generated = Image.open(OUT / f"phase{phase}-raw-registered-debug.png").convert("RGBA")
        generated_box = box_alpha(generated)
        target = original[phase - 1]
        target_box = box_alpha(target)
        target_height = target_box[3] - target_box[1]
        generated_crop = generated.crop(generated_box)
        factor = target_height / (generated_box[3] - generated_box[1])
        fitted_size = (round(generated_crop.width * factor), target_height)
        fitted = generated_crop.convert("RGBa").resize(fitted_size, Image.Resampling.LANCZOS).convert("RGBA")
        fitted_cell = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
        fitted_x = round((target_box[0] + target_box[2]) / 2 - fitted.width / 2)
        fitted_y = target_box[3] - fitted.height
        fitted_cell.alpha_composite(fitted, (fitted_x, fitted_y))
        fullbody[phase - 1] = fitted_cell
        fullbody_records[str(phase)] = {
            "target_bbox": list(target_box),
            "generated_bbox_before_fit": list(generated_box),
            "uniform_fit_factor": round(factor, 6),
            "fitted_bbox": list(box_alpha(fitted_cell)),
            "center_offset_px": round((fitted_x + fitted.width / 2) - (target_box[0] + target_box[2]) / 2, 3),
        }
        fitted_cell.save(OUT / f"phase{phase}-fullbody-fitted.png")
    fullbody_checks = {}
    for index, (frame, reference) in enumerate(zip(fullbody, original), start=1):
        box = box_alpha(frame)
        height = box[3] - box[1]
        if not 408 <= height <= 412 or not 465 <= box[3] <= 469:
            raise SystemExit(f"Full-body phase {index} misses the accepted height/baseline band: {box}")
        if any(frame.getpixel(point)[3] != 0 for point in ((0, 0), (FRAME - 1, 0), (0, FRAME - 1), (FRAME - 1, FRAME - 1))):
            raise SystemExit(f"Full-body phase {index} has opaque corner residue")
        changed_pixels = int(np.count_nonzero(np.any(np.asarray(frame) != np.asarray(reference), axis=2)))
        if index not in PHASES and changed_pixels:
            raise SystemExit(f"Full-body phase {index} changed outside the reviewed passing pair")
        if index in PHASES and not changed_pixels:
            raise SystemExit(f"Expected full-body phase {index} to contain the reviewed pose replacement")
        arr = np.asarray(frame.convert("RGBA"))
        rgb, alpha = arr[:, :, :3], arr[:, :, 3]
        red_mask = (rgb[:, :, 0] > 120) & (rgb[:, :, 2] > 120) & (rgb[:, :, 1] < 100)
        green_mask = ((rgb[:, :, 1] > 120) & (rgb[:, :, 1] > rgb[:, :, 0] * 1.25)
                      & (rgb[:, :, 1] > rgb[:, :, 2] * 1.25))
        red = int(((alpha > 8) & red_mask).sum())
        green = int(((alpha > 8) & green_mask).sum())
        red_low = int(((alpha > 0) & (alpha <= 8) & red_mask).sum())
        green_low = int(((alpha > 0) & (alpha <= 8) & green_mask).sum())
        fullbody_checks[str(index)] = {
            "bbox_alpha_gt16": list(box),
            "height": height,
            "changed_pixels_vs_v6": changed_pixels,
            "red_or_magenta_fringe_pixels": red,
            "green_fringe_pixels": green,
            "red_or_magenta_low_alpha_pixels_1_to_8": red_low,
            "green_low_alpha_pixels_1_to_8": green_low,
        }
        if red or green:
            raise SystemExit(f"Full-body phase {index} contains a flagged colored fringe")
    full_strip = Image.new("RGBA", (FRAME * 8, FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(fullbody):
        full_strip.alpha_composite(frame, (index * FRAME, 0))
    full_strip_path = OUT / "north-v9-fullbody-normalized-candidate-strip.png"
    full_strip.save(full_strip_path)
    full_metrics = [list(box_alpha(frame)) for frame in fullbody]
    staged_module = {
        "paths": {"rabbit-worker": {"walk_north": full_strip_path.relative_to(ROOT).as_posix()}},
        "anchors": {"rabbit-worker": {"walk_north": [{"x": 256, "y": 465} for _ in range(8)]}},
        "metrics": {"rabbit-worker": {"walk_north": full_metrics}},
    }
    staged_src = OUT / "src"
    staged_src.mkdir(parents=True, exist_ok=True)
    (staged_src / "player_walk_art.lua").write_text(
        "-- Staged North V9 full-body candidate only; generated by tools/build_player_north_v9_review.py.\nreturn "
        + lua(staged_module) + "\n", encoding="utf-8")
    spec = json.loads((ROOT / "character-motion/rabbit-worker.json").read_text(encoding="utf-8"))
    spec["animations"]["walk_north"]["path"] = full_strip_path.relative_to(ROOT).as_posix()
    (OUT / "north-v9-fullbody-motion-spec.json").write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")
    full_contact = Image.new("RGBA", (FRAME * 4, FRAME * 2 + 28), (255, 255, 255, 255))
    draw = ImageDraw.Draw(full_contact)
    for index, frame in enumerate(fullbody):
        x, y = (index % 4) * FRAME, (index // 4) * FRAME
        draw.text((x + 4, y + 4), f"North phase {index + 1}" + (" (v9 full-body)" if index + 1 in PHASES else ""), fill=(10, 10, 10, 255))
        full_contact.alpha_composite(white_composite(frame), (x, y + 28))
    full_contact.convert("RGB").save(OUT / "north-v9-fullbody-cycle-white.png")
    full_compare = Image.new("RGBA", (FRAME * 4, FRAME + 28), (255, 255, 255, 255))
    draw = ImageDraw.Draw(full_compare)
    for column, phase in enumerate((3, 7)):
        for row, frame in enumerate((original[phase - 1], fullbody[phase - 1])):
            x = (column * 2 + row) * FRAME
            draw.text((x + 4, 4), f"phase {phase} {'current' if row == 0 else 'v9 full-body'}", fill=(10, 10, 10, 255))
            full_compare.alpha_composite(white_composite(frame), (x, 28))
    full_compare.convert("RGB").save(OUT / "north-v9-fullbody-comparison.png")

    preview = Image.new("RGBA", (64 * 8, 92), (255, 255, 255, 255))
    draw = ImageDraw.Draw(preview)
    for index, frame in enumerate(base):
        draw.text((index * 64 + 2, 2), f"K{index + 1}", fill=(10, 10, 10, 255))
        thumb = white_composite(frame).resize((64, 64), Image.Resampling.LANCZOS)
        preview.alpha_composite(thumb, (index * 64, 22))
    preview.convert("RGB").save(OUT / "north-v9-game-scale-64px.png")

    summary = {
        "status": "staged for root visual and runtime review only; not integrated",
        "base_path": BASE.relative_to(ROOT).as_posix(),
        "base_sha256": sha(BASE),
        "candidate_path": strip_path.relative_to(ROOT).as_posix(),
        "candidate_sha256": sha(strip_path),
        "fullbody_candidate_path": full_strip_path.relative_to(ROOT).as_posix(),
        "fullbody_candidate_sha256": sha(full_strip_path),
        "fullbody_staged_module": (staged_src / "player_walk_art.lua").relative_to(ROOT).as_posix(),
        "frame_size": [FRAME, FRAME],
        "frame_count": 8,
        "changed_phases": [3, 7],
        "preserved_phases": [1, 2, 4, 5, 6, 8],
        "preserved_upper_body_to_y": PRESERVE_Y,
        "transition_blend_band_y": [PRESERVE_Y, BLEND_END_Y],
        "generated_pose_registration": records,
        "fullbody_fit": fullbody_records,
        "fullbody_checks": fullbody_checks,
        "fringe_counts_alpha_gt16": {},
        "fringe_counts_alpha_gt8": {},
        "fringe_counts_alpha_1_to_8": {},
        "candidate_metrics": [list(box_alpha(frame)) for frame in base],
        "fullbody_candidate_metrics": full_metrics,
        "runtime_changes": False,
    }
    for index, frame in enumerate(base, start=1):
        arr = np.asarray(frame.convert("RGBA"))
        rgb, alpha = arr[:, :, :3], arr[:, :, 3]
        red_mask = (rgb[:, :, 0] > 120) & (rgb[:, :, 2] > 120) & (rgb[:, :, 1] < 100)
        green_mask = ((rgb[:, :, 1] > 120) & (rgb[:, :, 1] > rgb[:, :, 0] * 1.25)
                      & (rgb[:, :, 1] > rgb[:, :, 2] * 1.25))
        summary["fringe_counts_alpha_gt16"][str(index)] = {
            "red_or_magenta": int(((alpha > 16) & red_mask).sum()),
            "green": int(((alpha > 16) & green_mask).sum()),
        }
        summary["fringe_counts_alpha_gt8"][str(index)] = {
            "red_or_magenta": int(((alpha > 8) & red_mask).sum()),
            "green": int(((alpha > 8) & green_mask).sum()),
        }
        summary["fringe_counts_alpha_1_to_8"][str(index)] = {
            "red_or_magenta": int(((alpha > 0) & (alpha <= 8) & red_mask).sum()),
            "green": int(((alpha > 0) & (alpha <= 8) & green_mask).sum()),
        }
    (OUT / "north-v9-candidate-report.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
