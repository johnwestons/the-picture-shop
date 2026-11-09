"""Stage two isolated north weight-down poses for root review.

The generated frames are registered at the accepted V5 source scale, and the
approved upper body plus tail/pouch artwork is preserved from V5. This builder
never writes runtime assets.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/animation-overhaul-luna-player-v1/consistent-north-v7"
BASE = ROOT / "assets/generated/player-walk-v5/walk_north.png"
OUT = ROOT / "output/animation-overhaul/player-walk-cross-view-v5/weightdown-correction-v7"
EXPECTED = {
    "north-v7-phase2-imagegen-raw.png": "222e8a0316feb1fadca3a72322965ffdf80d1ccc4d855e2d2373a631535977b6",
    "north-v7-phase6-imagegen-raw.png": "adacf22da422d8373340f46cfb6823c3597d31af6a8ff797fcffa877325a9ad8",
}
EXPECTED_PROMPTS = {
    2: "484c7588108afff7dc5e8cfe9c241cfd27123fd4ac8bad1066485571f8153c77",
    6: "a3176c4d047687e8c8d884d50efb6719fc8c114f07020b8192313cabcff93814",
}
EXPECTED_REFERENCES = {
    2: "60218b57e48e52e3028ace0959d178e65e59865904def017498da2f403ac262e",
    6: "613c76164c76d2bb5c195c01d0833efe84e84a081714e6fee321c8d6e14c45e6",
}
EXPECTED_BASE = "09cd04db24b729e0d963590f2d24e1175f0e0cace11057c8929ff37be99af9bf"
FRAME = 512
SCALE = 0.40773276015281634
PRESERVE_CUT_Y = 360
TARGET_PHASES = (2, 6)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def visible_box(image: Image.Image, threshold: int = 16) -> tuple[int, int, int, int]:
    box = image.getchannel("A").point(lambda value: 255 if value > threshold else 0).getbbox()
    if box is None:
        raise SystemExit("Sprite is transparent")
    return box


def split_strip(image: Image.Image) -> list[Image.Image]:
    if image.size != (FRAME * 8, FRAME):
        raise SystemExit(f"Unexpected base dimensions: {image.size}")
    return [image.crop((index * FRAME, 0, (index + 1) * FRAME, FRAME)) for index in range(8)]


def preserve_tail_and_pouch(target: Image.Image, candidate: Image.Image) -> Image.Image:
    rgba = np.asarray(target)
    yy, xx = np.indices(rgba.shape[:2])
    rgb, alpha = rgba[:, :, :3], rgba[:, :, 3]
    tail = ((alpha > 64) & (yy >= 300) & (yy <= 390) & (xx >= 210) & (xx <= 300)
            & (rgb[:, :, 0] > 190) & (rgb[:, :, 1] > 180) & (rgb[:, :, 2] > 170))
    pouch = ((alpha > 64) & (yy >= 300) & (yy <= 400) & (xx >= 292) & (xx <= 370)
             & (rgb[:, :, 0] > rgb[:, :, 1] * 1.18) & (rgb[:, :, 1] > rgb[:, :, 2] * 1.2))
    overlay_mask = Image.fromarray(((tail | pouch).astype(np.uint8) * 255)).filter(ImageFilter.MaxFilter(11))
    overlay_alpha = np.asarray(overlay_mask) > 0
    overlay_alpha[:PRESERVE_CUT_Y, :] = False
    overlay = target.copy()
    overlay.putalpha(Image.fromarray((alpha * overlay_alpha).astype(np.uint8)))
    candidate.alpha_composite(overlay)
    return candidate


def register_pose(raw_path: Path, target: Image.Image) -> tuple[Image.Image, dict]:
    raw = Image.open(raw_path).convert("RGBA")
    if raw.size != (1254, 1254):
        raise SystemExit(f"Unexpected generated image size at {raw_path}: {raw.size}")
    raw_box = visible_box(raw)
    crop = raw.crop(raw_box)
    resized_size = (round(crop.width * SCALE), round(crop.height * SCALE))
    resized = crop.convert("RGBa").resize(resized_size, Image.Resampling.LANCZOS).convert("RGBA")
    target_box = visible_box(target)
    x = round((target_box[0] + target_box[2]) / 2 - resized.width / 2)
    y = target_box[3] - resized.height
    generated = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    generated.alpha_composite(resized, (x, y))
    candidate = generated.copy()
    candidate.paste(target.crop((0, 0, FRAME, PRESERVE_CUT_Y)), (0, 0))
    candidate = preserve_tail_and_pouch(target, candidate)
    box = visible_box(candidate)
    height = box[3] - box[1]
    if not 408 <= height <= 413 or not 465 <= box[3] <= 469:
        raise SystemExit(f"Candidate missed accepted scale/baseline: bbox={box}")
    before = np.asarray(target).astype(np.int16)
    after = np.asarray(candidate).astype(np.int16)
    changed = np.max(np.abs(before - after), axis=2) > 24
    rgba = np.asarray(candidate)
    rgb = rgba[:, :, :3]
    visible = rgba[:, :, 3] > 16
    magenta = visible & (rgb[:, :, 0] > 120) & (rgb[:, :, 2] > 120) & (rgb[:, :, 1] < 100)
    green = visible & (rgb[:, :, 1] > 120) & (rgb[:, :, 1] > rgb[:, :, 0] * 1.25) & (rgb[:, :, 1] > rgb[:, :, 2] * 1.25)
    return candidate, {
        "raw_path": raw_path.relative_to(ROOT).as_posix(),
        "raw_sha256": sha(raw_path),
        "raw_size": list(raw.size),
        "raw_corner_alpha": int(raw.getpixel((0, 0))[3]),
        "raw_transparent_pixels": int(np.count_nonzero(np.asarray(raw)[:, :, 3] == 0)),
        "target_bbox_alpha_gt16": list(target_box),
        "candidate_bbox_alpha_gt16": list(box),
        "candidate_visible_height": height,
        "registered_offset_xy": [x, y],
        "changed_pixels_delta_gt24": int(changed.sum()),
        "changed_pixels_above_preserved_cut": int(changed[:PRESERVE_CUT_Y].sum()),
        "magenta_fringe_pixels_alpha_gt16": int(magenta.sum()),
        "green_fringe_pixels_alpha_gt16": int(green.sum()),
    }


def main() -> None:
    if sha(BASE) != EXPECTED_BASE:
        raise SystemExit("Pinned V5 base changed; review the new source before rebuilding")
    for name, expected_hash in EXPECTED.items():
        if sha(SOURCE / name) != expected_hash:
            raise SystemExit(f"Pinned generated source changed: {name}")

    base_strip = Image.open(BASE).convert("RGBA")
    frames = split_strip(base_strip)
    records = {}
    for phase in TARGET_PHASES:
        prompt_path = SOURCE / f"north-v7-phase{phase}-exact-prompt.txt"
        reference_path = SOURCE / f"north-v5-phase{phase}-reference.png"
        if sha(prompt_path) != EXPECTED_PROMPTS[phase] or sha(reference_path) != EXPECTED_REFERENCES[phase]:
            raise SystemExit(f"Pinned prompt/reference changed for phase {phase}")
        candidate, record = register_pose(SOURCE / f"north-v7-phase{phase}-imagegen-raw.png", frames[phase - 1])
        record["prompt_path"] = prompt_path.relative_to(ROOT).as_posix()
        record["prompt_sha256"] = sha(prompt_path)
        record["reference_path"] = reference_path.relative_to(ROOT).as_posix()
        record["reference_sha256"] = sha(reference_path)
        frames[phase - 1] = candidate
        records[str(phase)] = record

    OUT.mkdir(parents=True, exist_ok=True)
    strip = Image.new("RGBA", (FRAME * 8, FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME, 0))
    strip_path = OUT / "north-v7-weightdown-candidate-strip.png"
    strip.save(strip_path)

    contact = Image.new("RGBA", (FRAME * 4, FRAME * 2 + 24), (255, 255, 255, 255))
    draw = ImageDraw.Draw(contact)
    for index, frame in enumerate(frames):
        x, y = (index % 4) * FRAME, (index // 4) * FRAME
        draw.text((x + 4, y + 4), f"North phase {index + 1}" + (" (V7 staged)" if index + 1 in TARGET_PHASES else ""), fill=(15, 15, 15, 255))
        contact.alpha_composite(Image.alpha_composite(Image.new("RGBA", frame.size, (255, 255, 255, 255)), frame), (x, y + 24))
    contact.convert("RGB").save(OUT / "north-v5-v7-weightdown-contact-white.png")

    compare = Image.new("RGBA", (FRAME * 4, FRAME + 24), (255, 255, 255, 255))
    draw = ImageDraw.Draw(compare)
    order = (2, 6)
    for col, phase in enumerate(order):
        draw.text((col * FRAME + 4, 4), f"V5 phase {phase}", fill=(15, 15, 15, 255))
        draw.text(((col + 2) * FRAME + 4, 4), f"V7 phase {phase}", fill=(15, 15, 15, 255))
        compare.alpha_composite(Image.alpha_composite(Image.new("RGBA", (FRAME, FRAME), (255, 255, 255, 255)), split_strip(base_strip)[phase - 1]), (col * FRAME, 24))
        compare.alpha_composite(Image.alpha_composite(Image.new("RGBA", (FRAME, FRAME), (255, 255, 255, 255)), frames[phase - 1]), ((col + 2) * FRAME, 24))
    compare.convert("RGB").save(OUT / "north-v5-v7-weightdown-pairs.png")

    thumb = Image.new("RGBA", (64 * 8, 88), (255, 255, 255, 255))
    draw = ImageDraw.Draw(thumb)
    for index, frame in enumerate(frames):
        draw.text((index * 64 + 2, 2), f"K{index + 1}", fill=(15, 15, 15, 255))
        small = frame.resize((64, 64), Image.Resampling.LANCZOS)
        thumb.alpha_composite(Image.alpha_composite(Image.new("RGBA", small.size, (255, 255, 255, 255)), small), (index * 64, 20))
    thumb.convert("RGB").save(OUT / "north-v7-weightdown-64px.png")

    report = {
        "status": "staged for visual review only; not approved or integrated",
        "base_path": BASE.relative_to(ROOT).as_posix(),
        "base_sha256": EXPECTED_BASE,
        "fixed_scale": SCALE,
        "preserved_upper_body_cut_y": PRESERVE_CUT_Y,
        "target_phases": list(TARGET_PHASES),
        "phases": records,
        "staged_strip": strip_path.relative_to(ROOT).as_posix(),
        "candidate_runtime_changes": False,
    }
    (OUT / "north-v7-weightdown-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
