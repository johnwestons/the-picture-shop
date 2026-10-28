#!/usr/bin/env python3
"""Deterministically stage the single recovered East K5 candidate for review."""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[5]
SOURCE = ROOT / "assets/source/animation-overhaul-luna-v1/cat-worker"
OUT = ROOT / "output/animation-overhaul/luna-cat/east-k5-correction-candidate-v1"
RECOVERED_RAW = Path(r"C:/Users/johnw/.codex/generated_images/01a17bf6-4592-76b2-9ffc-934be2409a07/exec-38a42a7b-e980-4ab8-87af-7bc31b9afdf6.png")
RAW = SOURCE / "generated/walk_east-canonical-key05-correction-recovered-raw-v1.png"
PROMPT = SOURCE / "prompts/walk_east-canonical-key05-correction-v1.txt"
REFERENCE = SOURCE / "references"
CELL = SOURCE / "canonical-replacements/walk_east-canonical-key05-correction-v1.png"
IDENTITY_STRIP = ROOT / "assets/source/cat-worker-v1/locomotion/walk.png"

# One uniform master scale based on head/torso landmarks. East-key body
# landmark audit estimated ~0.40 from raw head width and head-to-belt span
# against approved K1/K4/K6. Translation is rigid: horizontal torso centering
# plus planted-sole alignment to the approved baseline. No body part is scaled.
MASTER_SCALE = 0.40
PLACEMENT_X = 2
PLACEMENT_Y = 10
SOURCE_CONTACT_BASELINE_Y = 458


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    return image.getchannel("A").getbbox()


def load_source_key(number: int) -> Image.Image:
    return Image.open(REFERENCE / f"east-original-key{number:02d}-source-v1.png").convert("RGBA")


def build_candidate() -> Image.Image:
    raw = Image.open(RAW).convert("RGBA")
    scaled_size = (round(raw.width * MASTER_SCALE), round(raw.height * MASTER_SCALE))
    scaled = raw.resize(scaled_size, Image.Resampling.NEAREST)
    target = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    target.alpha_composite(scaled, (PLACEMENT_X, PLACEMENT_Y))
    return target


def make_sheet(keys: list[tuple[str, Image.Image]], target: Path, foot_notes: bool) -> None:
    label_h = 42
    note_h = 64 if foot_notes else 22
    width = len(keys) * 512
    height = label_h + 512 + note_h
    sheet = Image.new("RGBA", (width, height), (31, 35, 40, 255))
    draw = ImageDraw.Draw(sheet)
    for i, (label, image) in enumerate(keys):
        x = i * 512
        sheet.alpha_composite(image, (x, label_h))
        draw.text((x + 12, 10), label, fill=(246, 248, 250, 255), stroke_width=1, stroke_fill=(0, 0, 0, 255))
        # All keys retain their own pixels and placement; this line exposes the
        # shared sole baseline for contact comparison.
        draw.line((x, label_h + SOURCE_CONTACT_BASELINE_Y, x + 511, label_h + SOURCE_CONTACT_BASELINE_Y), fill=(255, 215, 55, 230), width=2)
        if foot_notes:
            # Screen-side positions are called out without assigning near/far
            # where the generated silhouette/occlusion does not establish it.
            for cx, name, color in ((190, "screen-left/rear boot", (90, 210, 255, 255)), (350, "screen-right/front boot", (255, 170, 80, 255))):
                cy = label_h + 448
                draw.ellipse((x + cx - 5, cy - 5, x + cx + 5, cy + 5), fill=color, outline=(10, 10, 10, 255), width=1)
                draw.text((x + 12, label_h + 512 + (0 if name.startswith("screen-left") else 30)), name, fill=color, stroke_width=1, stroke_fill=(0, 0, 0, 255))
        else:
            draw.text((x + 12, label_h + 512 + 3), "Gold line = approved contact ground baseline", fill=(255, 220, 95, 255))
    sheet.convert("RGB").save(target)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    if not RAW.exists():
        if not RECOVERED_RAW.exists():
            raise FileNotFoundError(RECOVERED_RAW)
        shutil.copyfile(RECOVERED_RAW, RAW)
    if RECOVERED_RAW.exists() and sha256(RAW) != sha256(RECOVERED_RAW):
        raise RuntimeError("Staged recovered raw differs from recovered ImageGen cache output")
    OUT.mkdir(parents=True, exist_ok=True)
    candidate = build_candidate()
    candidate.save(CELL)

    k1 = load_source_key(1)
    k4 = load_source_key(4)
    k6 = load_source_key(6)
    make_sheet(
        [("Original East K1", k1), ("Proposed East K5 (single generated candidate)", candidate)],
        OUT / "east-k1-proposed-k5-ownership-review.png",
        foot_notes=True,
    )
    make_sheet(
        [("Original East K4 (knee-up)", k4), ("Proposed East K5", candidate), ("Original East K6 (weight-down)", k6)],
        OUT / "east-k4-proposed-k5-k6-neighbor-review.png",
        foot_notes=False,
    )

    refs = {f"original_k{i:02d}": {
        "path": str(REFERENCE / f"east-original-key{i:02d}-source-v1.png"),
        "file_sha256": sha256(REFERENCE / f"east-original-key{i:02d}-source-v1.png"),
        "role": {1: "opposite contact ownership comparison", 2: "neighboring pose and identity reference", 4: "left endpoint neighbor", 6: "right endpoint neighbor"}[i],
    } for i in (1, 2, 4, 6)}
    manifest = {
        "status": "staged candidate only; not approved and not installed",
        "source_mapping": "Original East keys 1,2,4,6 remain immutable; candidate substitutes only for East K5 in the review sheets.",
        "generation_attempt": {
            "count": 1,
            "raw_cache_path_recovered_by_parent": str(RECOVERED_RAW),
            "raw_cache_timestamp_reported_by_parent": "2026-10-27 10:58:00 local",
            "raw_image_sha256": sha256(RAW),
            "result_object_metadata": "Original wrapper lost result metadata; parent recovered the matching cache output. No retry was made.",
            "prompt_path": str(PROMPT),
            "prompt_sha256": sha256(PROMPT),
        },
        "reference_roles": {
            **refs,
            "approved_full_east_identity_strip": {
                "path": str(IDENTITY_STRIP),
                "file_sha256": sha256(IDENTITY_STRIP),
                "role": "approved full-direction identity, outfit, palette, scale, and asymmetric satchel reference",
            },
        },
        "normalization": {
            "source_master_size": list(Image.open(RAW).size),
            "source_master_alpha_bbox_all_nonzero": list(alpha_bbox(Image.open(RAW).convert("RGBA"))),
            "source_master_visible_alpha_bbox_ge128_min3_pixels_per_row_col": [269, 178, 1001, 1120],
            "approved_cell_size": [512, 512],
            "uniform_scale": MASTER_SCALE,
            "scale_basis": "one fixed scale estimated from raw head width and head-to-belt torso span against original East K1/K4/K6; not fitted independently to each pose alpha height/bbox",
            "resampling": "nearest-neighbor; no blending, recoloring, warping, part resizing, or per-cell scaling",
            "rigid_translation_px": [PLACEMENT_X, PLACEMENT_Y],
            "translation_basis": "horizontal torso-axis centering and planted contact-sole alignment to source baseline y=458",
            "output_contact_baseline_y": SOURCE_CONTACT_BASELINE_Y,
            "generated_top_vs_neighbor": "At the selected ground alignment, top ear pixels are about 8 px lower than K4; this is retained as visible source-proportion/pose drift, not concealed by rescaling.",
        },
        "review_findings": {
            "identity": "Charcoal cat, two ears, two arms, two legs, one tail; East-facing profile, orange workwear/gloves, olive scarf/trousers, dark boots and screen-left rear satchel are visible.",
            "screen_side_observation": "Candidate shows a screen-right/front boot at the contact baseline and a screen-left/rear boot behind the pelvis. The satchel partly occludes the rear leg; the available image alone does not establish with confidence that the forward boot belongs to the far-side leg rather than repeating K1's near-side owner.",
            "limitation": "This review candidate is not evidence of a corrected opposite near/far contact owner. Parent/root review is required before any proposal can be considered; East sequence remains unchanged.",
        },
        "outputs": {},
    }
    output_paths = [CELL, OUT / "east-k1-proposed-k5-ownership-review.png", OUT / "east-k4-proposed-k5-k6-neighbor-review.png"]
    manifest["outputs"] = {p.name: {"path": str(p), "sha256": sha256(p), "size": list(Image.open(p).size)} for p in output_paths}
    (OUT / "east-k5-candidate-provenance-v1.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"raw_sha256": sha256(RAW), "cell": str(CELL), "cell_sha256": sha256(CELL), "sheets": [str(p) for p in output_paths[1:]], "manifest": str(OUT / "east-k5-candidate-provenance-v1.json")}, indent=2))


if __name__ == "__main__":
    main()
