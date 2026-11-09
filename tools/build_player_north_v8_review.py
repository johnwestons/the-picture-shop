"""Stage North V5/V7 with paired V8 knee-up corrections for review only."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/animation-overhaul-luna-player-v1/consistent-north-v8"
BASE = ROOT / "output/animation-overhaul/player-walk-cross-view-v5/weightdown-correction-v7/north-v7-weightdown-candidate-strip.png"
V5 = ROOT / "assets/generated/player-walk-v5/walk_north.png"
OUT = ROOT / "output/animation-overhaul/player-walk-cross-view-v5/leg-phase-correction-v8"
EXPECTED_BASE = "2d089ed5607977b58cc31a01f60530fc5ddde37de3f0c484d1b2332766dea483"
EXPECTED_V5 = "09cd04db24b729e0d963590f2d24e1175f0e0cace11057c8929ff37be99af9bf"
EXPECTED_RAW = {
    "north-v8-phase4-imagegen-raw.png": "a32b1879fca15760809005e448eae291b71335a1dec5057cd8b11da954e3b445",
    "north-v8-phase8-imagegen-raw.png": "8c127530139c7a61e05caccecf651f71742f950cc815b7039266d44bd2fbdd5b",
}
EXPECTED_PROMPTS = {
    4: "e2cccda358a5679f57709e3c5eb20db772de163a552bf980c1c03455a32f4d7b",
    8: "5c8e4ae873bf51b8768b828ff40536296e9ce62175b827747c2337dca082cb9a",
}
EXPECTED_REFERENCES = {
    4: "03ba1d6521e503a4bd4b6642938fb27acadf5b673742b3327aaeac116e3b37e5",
    8: "6b738149d4a7a2cca252d120cf177ec8d9640f376fea408e22f90ce078177a96",
}
REFERENCE_DIR = ROOT / "assets/source/animation-overhaul-luna-player-v1/consistent-north-v7"
FRAME = 512
SCALE = 0.40773276015281634
CUT_Y = 360
PHASES = (4, 8)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def visible_box(image: Image.Image) -> tuple[int, int, int, int]:
    box = image.getchannel("A").point(lambda value: 255 if value > 16 else 0).getbbox()
    if box is None:
        raise SystemExit("Sprite is transparent")
    return box


def split_strip(image: Image.Image) -> list[Image.Image]:
    if image.size != (FRAME * 8, FRAME):
        raise SystemExit(f"Unexpected strip dimensions: {image.size}")
    return [image.crop((index * FRAME, 0, (index + 1) * FRAME, FRAME)) for index in range(8)]


def restore_accessories(target: Image.Image, candidate: Image.Image) -> None:
    rgba = np.asarray(target)
    yy, xx = np.indices(rgba.shape[:2])
    rgb, alpha = rgba[:, :, :3], rgba[:, :, 3]
    tail = ((alpha > 64) & (yy >= 300) & (yy <= 390) & (xx >= 210) & (xx <= 300)
            & (rgb[:, :, 0] > 190) & (rgb[:, :, 1] > 180) & (rgb[:, :, 2] > 170))
    pouch = ((alpha > 64) & (yy >= 300) & (yy <= 400) & (xx >= 292) & (xx <= 370)
             & (rgb[:, :, 0] > rgb[:, :, 1] * 1.18) & (rgb[:, :, 1] > rgb[:, :, 2] * 1.2))
    dilated = Image.fromarray(((tail | pouch).astype(np.uint8) * 255)).filter(ImageFilter.MaxFilter(11))
    mask = np.asarray(dilated) > 0
    mask[:CUT_Y, :] = False
    overlay = target.copy()
    overlay.putalpha(Image.fromarray((alpha * mask).astype(np.uint8)))
    candidate.alpha_composite(overlay)


def register(raw_path: Path, target: Image.Image) -> tuple[Image.Image, dict]:
    raw = Image.open(raw_path).convert("RGBA")
    if raw.size != (1254, 1254):
        raise SystemExit(f"Unexpected generated image size at {raw_path}: {raw.size}")
    raw_box = visible_box(raw)
    crop = raw.crop(raw_box)
    size = (round(crop.width * SCALE), round(crop.height * SCALE))
    resized = crop.convert("RGBa").resize(size, Image.Resampling.LANCZOS).convert("RGBA")
    target_box = visible_box(target)
    x = round((target_box[0] + target_box[2]) / 2 - resized.width / 2)
    y = target_box[3] - resized.height
    generated = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    generated.alpha_composite(resized, (x, y))
    candidate = generated.copy()
    candidate.paste(target.crop((0, 0, FRAME, CUT_Y)), (0, 0))
    restore_accessories(target, candidate)
    box = visible_box(candidate)
    height = box[3] - box[1]
    if not 408 <= height <= 413 or not 465 <= box[3] <= 469:
        raise SystemExit(f"Candidate missed accepted scale/baseline: bbox={box}")
    before, after = np.asarray(target).astype(np.int16), np.asarray(candidate).astype(np.int16)
    changed = np.max(np.abs(before - after), axis=2) > 24
    rgba = np.asarray(candidate)
    rgb, alpha = rgba[:, :, :3], rgba[:, :, 3]
    visible = alpha > 16
    magenta = visible & (rgb[:, :, 0] > 120) & (rgb[:, :, 2] > 120) & (rgb[:, :, 1] < 100)
    green = visible & (rgb[:, :, 1] > 120) & (rgb[:, :, 1] > rgb[:, :, 0] * 1.25) & (rgb[:, :, 1] > rgb[:, :, 2] * 1.25)
    return candidate, {
        "raw_path": raw_path.relative_to(ROOT).as_posix(), "raw_sha256": sha(raw_path),
        "raw_corner_alpha": int(raw.getpixel((0, 0))[3]),
        "raw_transparent_pixels": int(np.count_nonzero(np.asarray(raw)[:, :, 3] == 0)),
        "target_bbox_alpha_gt16": list(target_box), "candidate_bbox_alpha_gt16": list(box),
        "candidate_visible_height": height, "registered_offset_xy": [x, y],
        "changed_pixels_delta_gt24": int(changed.sum()),
        "changed_pixels_above_preserved_cut": int(changed[:CUT_Y].sum()),
        "magenta_fringe_pixels_alpha_gt16": int(magenta.sum()),
        "green_fringe_pixels_alpha_gt16": int(green.sum()),
    }


def lua(value) -> str:
    if isinstance(value, dict):
        return "{" + ",".join("[" + json.dumps(key) + "]=" + lua(item) for key, item in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ",".join(lua(item) for item in value) + "}"
    return json.dumps(value)


def main() -> None:
    if sha(BASE) != EXPECTED_BASE or sha(V5) != EXPECTED_V5:
        raise SystemExit("Pinned V5/V7 base changed; review before rebuilding")
    for name, expected_hash in EXPECTED_RAW.items():
        if sha(SOURCE / name) != expected_hash:
            raise SystemExit(f"Pinned generated source changed: {name}")

    v5_frames = split_strip(Image.open(V5).convert("RGBA"))
    frames = split_strip(Image.open(BASE).convert("RGBA"))
    records = {}
    for phase in PHASES:
        prompt_path = SOURCE / f"north-v8-phase{phase}-exact-prompt.txt"
        reference_path = REFERENCE_DIR / f"north-v5-phase{phase}-reference.png"
        if sha(prompt_path) != EXPECTED_PROMPTS[phase] or sha(reference_path) != EXPECTED_REFERENCES[phase]:
            raise SystemExit(f"Pinned prompt/reference changed for phase {phase}")
        candidate, record = register(SOURCE / f"north-v8-phase{phase}-imagegen-raw.png", v5_frames[phase - 1])
        record["prompt_path"] = prompt_path.relative_to(ROOT).as_posix()
        record["prompt_sha256"] = sha(prompt_path)
        record["reference_path"] = reference_path.relative_to(ROOT).as_posix()
        record["reference_sha256"] = sha(reference_path)
        records[str(phase)] = record
        frames[phase - 1] = candidate

    OUT.mkdir(parents=True, exist_ok=True)
    strip = Image.new("RGBA", (FRAME * 8, FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME, 0))
    strip_path = OUT / "north-v8-leg-phase-candidate-strip.png"
    strip.save(strip_path)

    contact = Image.new("RGBA", (FRAME * 4, FRAME * 2 + 24), (255, 255, 255, 255))
    draw = ImageDraw.Draw(contact)
    for index, frame in enumerate(frames):
        x, y = (index % 4) * FRAME, (index // 4) * FRAME
        draw.text((x + 4, y + 4), f"North phase {index + 1}" + (" (V7/V8 staged)" if index + 1 in (2, 4, 6, 8) else ""), fill=(15, 15, 15, 255))
        contact.alpha_composite(Image.alpha_composite(Image.new("RGBA", frame.size, (255, 255, 255, 255)), frame), (x, y + 24))
    contact.convert("RGB").save(OUT / "north-v5-v8-full-cycle-white.png")

    pair = Image.new("RGBA", (FRAME * 4, FRAME + 24), (255, 255, 255, 255))
    draw = ImageDraw.Draw(pair)
    for col, phase in enumerate(PHASES):
        draw.text((col * FRAME + 4, 4), f"V5 phase {phase}", fill=(15, 15, 15, 255))
        draw.text(((col + 2) * FRAME + 4, 4), f"V8 phase {phase}", fill=(15, 15, 15, 255))
        pair.alpha_composite(Image.alpha_composite(Image.new("RGBA", (FRAME, FRAME), (255, 255, 255, 255)), v5_frames[phase - 1]), (col * FRAME, 24))
        pair.alpha_composite(Image.alpha_composite(Image.new("RGBA", (FRAME, FRAME), (255, 255, 255, 255)), frames[phase - 1]), ((col + 2) * FRAME, 24))
    pair.convert("RGB").save(OUT / "north-v5-v8-knee-up-pairs.png")

    thumb = Image.new("RGBA", (64 * 8, 88), (255, 255, 255, 255))
    draw = ImageDraw.Draw(thumb)
    for index, frame in enumerate(frames):
        draw.text((index * 64 + 2, 2), f"K{index + 1}", fill=(15, 15, 15, 255))
        small = frame.resize((64, 64), Image.Resampling.LANCZOS)
        thumb.alpha_composite(Image.alpha_composite(Image.new("RGBA", small.size, (255, 255, 255, 255)), small), (index * 64, 20))
    thumb.convert("RGB").save(OUT / "north-v8-leg-phase-64px.png")

    metrics = [list(visible_box(frame)) for frame in frames]
    module = {"paths": {"rabbit-worker": {"walk_north": strip_path.relative_to(ROOT).as_posix()}},
              "anchors": {"rabbit-worker": {"walk_north": [{"x": 256, "y": 465} for _ in range(8)]}},
              "metrics": {"rabbit-worker": {"walk_north": metrics}}}
    module_path = OUT / "src/player_walk_art.lua"
    module_path.parent.mkdir(parents=True, exist_ok=True)
    module_path.write_text("-- Staged V8 review only; generated by tools/build_player_north_v8_review.py.\nreturn " + lua(module) + "\n", encoding="utf-8")
    spec = json.loads((ROOT / "character-motion/rabbit-worker.json").read_text(encoding="utf-8"))
    spec["animations"]["walk_north"]["path"] = strip_path.relative_to(ROOT).as_posix()
    spec_path = OUT / "north-v8-candidate-motion-spec.json"
    spec_path.write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")

    report = {"status": "staged for review only; not approved or integrated", "base_v5_sha256": EXPECTED_V5,
              "base_v7_sha256": EXPECTED_BASE, "fixed_scale": SCALE, "preserved_upper_body_cut_y": CUT_Y,
              "corrected_phases": [2, 4, 6, 8], "new_v8_phases": list(PHASES), "phases": records,
              "stance_track_review": {
                  "contact_to_passing_slip_pixels": [-39.814, -40.186],
                  "staged_support_sole_y_by_phase": [467, 467, 468, 469, 467, 467, 466, 467],
                  "decision": "not promoted; pose edits do not correct the 20-world-pixel-per-pose planted-foot mismatch",
              },
              "candidate_runtime_changes": False, "candidate_strip": strip_path.relative_to(ROOT).as_posix(),
              "motion_spec": spec_path.relative_to(ROOT).as_posix(), "art_module": module_path.relative_to(ROOT).as_posix()}
    (OUT / "north-v8-candidate-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
