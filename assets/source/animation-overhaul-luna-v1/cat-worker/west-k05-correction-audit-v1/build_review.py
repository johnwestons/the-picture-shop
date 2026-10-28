"""Rebuild the West K5 source-only correction attempt review; never writes runtime art."""
from __future__ import annotations

from hashlib import sha256
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[5]
BATCH = Path(__file__).resolve().parent
OUT = ROOT / "output/animation-overhaul/luna-cat/view-audit/west-k05-correction-attempts"
WALK = ROOT / "assets/source/cat-worker-v1/locomotion/walk_west.png"
IDLE = ROOT / "assets/source/cat-worker-v1/locomotion/idle_west.png"
REFERENCE_DIR = ROOT / "output/animation-overhaul/luna-cat/view-audit/west-candidate-references"
ATTEMPTS = [
    ("attempt-01-full-pose", BATCH / "attempt-01-full-pose.png", BATCH / "prompt-attempt-01.txt",
     "exec-e185ead1-acf0-493d-be62-7615d580f2e0.png", "C:/Users/johnw/.codex/generated_images/01a17bf6-4592-76b2-9ffc-934be2409a07/exec-e185ead1-acf0-493d-be62-7615d580f2e0.png",
     "2026-10-27T19:39:27Z",
     [
         ("output/animation-overhaul/luna-cat/view-audit/west-candidate-references/idle_west_key01_source.png", "West identity, outfit, style and asymmetric details"),
         ("output/animation-overhaul/luna-cat/view-audit/west-candidate-references/walk_west_key01_source.png", "K1 opposite left-contact foot-owner reference"),
         ("output/animation-overhaul/luna-cat/view-audit/west-candidate-references/walk_west_key04_source.png", "K4 right knee-up far-side/right leg anatomy"),
         ("output/animation-overhaul/luna-cat/view-audit/west-candidate-references/walk_west_key05_source.png", "K5 head/body/upper-body placement; current leg owner is wrong"),
         ("output/animation-overhaul/luna-cat/view-audit/west-candidate-references/walk_west_key06_source.png", "K6 right-support leg context"),
     ]),
    ("attempt-02-source-edit", BATCH / "attempt-02-source-edit.png", BATCH / "prompt-attempt-02.txt",
     "exec-f77cdbc0-0ae0-452d-8c99-d1bbb30b12ed.png", "C:/Users/johnw/.codex/generated_images/01a17bf6-4592-76b2-9ffc-934be2409a07/exec-f77cdbc0-0ae0-452d-8c99-d1bbb30b12ed.png",
     "2026-10-27T19:42:54Z",
     [
         ("output/animation-overhaul/luna-cat/view-audit/west-candidate-references/walk_west_key05_source.png", "K5 exact source pose to edit"),
         ("output/animation-overhaul/luna-cat/view-audit/west-candidate-references/walk_west_key01_source.png", "K1 opposite left-contact owner reference"),
         ("output/animation-overhaul/luna-cat/view-audit/west-candidate-references/walk_west_key06_source.png", "K6 right-support leg context"),
     ]),
    ("attempt-03-owner-guide-edit", BATCH / "attempt-03-owner-guide-edit.png", BATCH / "prompt-attempt-03-owner-guide.txt",
     "exec-fa0c0992-b6ae-40b6-ab6c-8f95bd2e2cf8.png", "C:/Users/johnw/.codex/generated_images/01a17bf6-4592-76b2-9ffc-934be2409a07/exec-fa0c0992-b6ae-40b6-ab6c-8f95bd2e2cf8.png",
     "2026-10-27T20:32:41Z",
     [
         ("output/animation-overhaul/luna-cat/view-audit/west-candidate-references/walk_west_key05_source.png", "Original K5 target pose"),
         ("output/animation-overhaul/luna-cat/view-audit/west-candidate-references/walk_west_key01_source.png", "K1 opposite left-contact owner"),
         ("output/animation-overhaul/luna-cat/view-audit/west-candidate-references/walk_west_key04_source.png", "K4 right-knee-up transition"),
         ("output/animation-overhaul/luna-cat/view-audit/west-candidate-references/walk_west_key06_source.png", "K6 right-weight-down continuation"),
         ("output/animation-overhaul/luna-cat/view-audit/west-k05-correction-attempts/west-k05-leg-owner-guide.png", "Annotated leg-owner phase guide"),
     ]),
]


def digest(path: Path) -> str:
    return sha256(path.read_bytes()).hexdigest()


def alpha_bbox(image: Image.Image, threshold: int = 16):
    return image.getchannel("A").point(lambda value: 255 if value >= threshold else 0).getbbox()


def checker(size: tuple[int, int], cell: int = 16) -> Image.Image:
    image = Image.new("RGBA", size, (220, 220, 220, 255))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(190, 190, 190, 255))
    return image


def rigid_height_match(candidate: Image.Image, target: Image.Image) -> tuple[Image.Image, float, list[int], list[int]]:
    source_box, target_box = alpha_bbox(candidate), alpha_bbox(target)
    if not source_box or not target_box:
        raise ValueError("candidate or target has no alpha16 pixels")
    scale = (target_box[3] - target_box[1]) / (source_box[3] - source_box[1])
    resized = candidate.resize((round(candidate.width * scale), round(candidate.height * scale)), Image.Resampling.NEAREST)
    resized_box = tuple(round(value * scale) for value in source_box)
    target_center_x = (target_box[0] + target_box[2]) / 2
    source_center_x = (resized_box[0] + resized_box[2]) / 2
    left = round(target_center_x - source_center_x)
    top = target_box[3] - resized_box[3]
    placed = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    placed.alpha_composite(resized, (left, top))
    return placed, scale, list(source_box), [left, top]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    walk = Image.open(WALK).convert("RGBA")
    if walk.size != (4096, 512):
        raise ValueError(f"Expected 8×512 source walk strip, got {walk.size}")
    original_k1 = walk.crop((0, 0, 512, 512))
    original_k5 = walk.crop((4 * 512, 0, 5 * 512, 512))
    original_k5.save(OUT / "original-west-k05-unchanged.png")
    transformed = []
    attempt_records = []
    for name, path, prompt_path, generation_id, original_path, created_utc, reference_images in ATTEMPTS:
        raw = Image.open(path).convert("RGBA")
        review, scale, raw_bbox, translation = rigid_height_match(raw, original_k5)
        transformed.append((name, review))
        review.save(OUT / f"{name}-rigid-review-only.png")
        if name == "attempt-01-full-pose":
            rejection_reason = "View drifts toward a broad front three-quarter angle; contact ownership remains unclear."
        elif name == "attempt-02-source-edit":
            rejection_reason = "The broad green trouser/boot still occupies screen-left forward position; the opposite far-side owner is not identifiable, and the generated outline has a vivid magenta edge."
        else:
            rejection_reason = "Even with the owner guide, the broad green screen-left leg remains the forward support and the far-side/right ownership is not visually distinguishable; outline and body style still drift from the source."
        attempt_records.append({
            "name": name,
            "generation_id": generation_id,
            "original_generated_image_path": original_path,
            "created_utc": created_utc,
            "staged_raw_path": path.relative_to(ROOT).as_posix(),
            "sha256": digest(path),
            "size": list(raw.size),
            "alpha16_bbox": raw_bbox,
            "alpha16_pixels": sum(1 for value in raw.getchannel("A").get_flattened_data() if value >= 16),
            "prompt_path": prompt_path.relative_to(ROOT).as_posix(),
            "prompt_sha256": digest(prompt_path),
            "tool": "built-in image_gen.imagegen",
            "result_metadata": {
                "result_type": "object",
                "result_keys": ["image_url", "output_hint"],
                "output_hint": f"Generated images are saved to C:/Users/johnw/.codex/generated_images/01a17bf6-4592-76b2-9ffc-934be2409a07 as {original_path} by default.",
            },
            "reference_images": [{"path": ref, "role": role, "sha256": digest(ROOT / ref)} for ref, role in reference_images],
            "review_transform": {
                "kind": "uniform_scale_and_rigid_translation_for_review_only",
                "uniform_scale": scale,
                "alpha16_bbox_before_transform": raw_bbox,
                "translation_xy": translation,
                "target": "original K5 alpha16 height and silhouette center",
                "not_usable_as_source_or_runtime_art": True,
            },
            "review_status": "rejected_after_visual_inspection",
            "reason": rejection_reason,
        })

    font = ImageFont.load_default()
    labels = [("Original K1: left contact", original_k1), ("Original K5: repeated owner", original_k5)] + transformed
    board = Image.new("RGB", (len(labels) * 512, 30 + 512), (42, 44, 48))
    draw = ImageDraw.Draw(board)
    for index, (label, image) in enumerate(labels):
        x = index * 512
        draw.text((x + 6, 8), label, fill=(245, 240, 220), font=font)
        tile = checker((512, 512))
        tile.alpha_composite(image)
        board.paste(tile.convert("RGB"), (x, 30))
    board.save(OUT / "west-k05-source-and-generation-contact.png")

    # A lower-body-only comparison makes the alleged owner swap easy to inspect.
    lower_h = 180
    crop_y = 278
    lower = Image.new("RGB", (len(labels) * 512, 30 + lower_h * 3), (42, 44, 48))
    draw = ImageDraw.Draw(lower)
    for index, (label, image) in enumerate(labels):
        x = index * 512
        draw.text((x + 6, 8), label, fill=(245, 240, 220), font=font)
        tile = checker((512, 512))
        tile.alpha_composite(image)
        detail = tile.crop((0, crop_y, 512, crop_y + lower_h)).resize((512, lower_h * 3), Image.Resampling.NEAREST)
        lower.paste(detail.convert("RGB"), (x, 30))
    lower.save(OUT / "west-k05-lower-body-review-3x.png")

    manifest = {
        "version": 1,
        "status": "audit_staged_no_accepted_correction",
        "original_walk_path": "assets/source/cat-worker-v1/locomotion/walk_west.png",
        "original_walk_sha256": digest(WALK),
        "original_idle_path": "assets/source/cat-worker-v1/locomotion/idle_west.png",
        "original_idle_sha256": digest(IDLE),
        "issue": "West K1 and K5 both visibly use the near-side screen-left forward boot; K5 should transfer support to far-side/right.",
        "evidence": [
            "output/animation-overhaul/luna-cat/view-audit/west-candidate-references/walk_west_contact_owners_source.png",
            "output/animation-overhaul/luna-cat/view-audit/lower-body/west-opposite-phase-pairs-2x.png",
            "output/animation-overhaul/luna-cat/view-audit/source-skill-audit/contact-sheets/walk_west.png",
        ],
        "attempts": attempt_records,
        "cycle_review": {
            "script": "assets/source/animation-overhaul-luna-v1/cat-worker/west-k05-correction-audit-v1/build_cycle_64px_review.py",
            "source_variant": "immutable original West eight-key source strip, with each candidate substituted into K5 for review only",
            "runtime_source_scale_256_to_64px": 0.32989690721649484,
            "source_master_scale_512_to_64px": 0.16494845360824742,
            "nominal_key_duration_ms": 180,
            "half_speed_key_duration_ms": 360,
            "outputs": [
                "output/animation-overhaul/luna-cat/view-audit/west-k05-correction-attempts/west-complete-cycle-64px-review.png",
                "output/animation-overhaul/luna-cat/view-audit/west-k05-correction-attempts/west-k04-k05-k06-64px-review.png",
                "output/animation-overhaul/luna-cat/view-audit/west-k05-correction-attempts/west-contact-owner-feet-4x.png",
                "output/animation-overhaul/luna-cat/view-audit/west-k05-correction-attempts/west-k04-k05-k06-feet-4x.png",
            ],
            "review_conclusion": "All candidates preserve the screen-left contact trajectory, but none makes the far/right owner independently identifiable through the satchel and leg overlap; no candidate is accepted.",
        },
        "scope": "source-only audit; no runtime, spec, docs, tests, or canonical strip changed",
    }
    (BATCH / "registration.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output_dir": OUT.as_posix(), "manifest": (BATCH / "registration.json").as_posix(),
                      "attempts": [{"name": row["name"], "scale": row["review_transform"]["uniform_scale"],
                                    "sha256": row["sha256"]} for row in attempt_records]}, indent=2))


if __name__ == "__main__":
    main()
