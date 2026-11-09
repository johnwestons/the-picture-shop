"""Build the staged single-pose North K3 trial02 review candidate.

The source master is the one ImageGen edit of accepted North K5 trial06. The
accepted K5 raw-source scale is pinned and reused unchanged. This builder only
normalizes one cell with that fixed scale, crop/anchor translation, and writes
review-only outputs; it does not touch shared runtime assets.
"""

from __future__ import annotations

import hashlib
import json
import math
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "assets/source/animation-overhaul-luna-player-v1/pose-corrections-v1"
REF_DIR = SOURCE_DIR / "references"
OUTPUT_DIR = ROOT / "output/animation-overhaul/luna-player/pose-corrections-v1"
RAW = SOURCE_DIR / "north-canonical-03-trial-02-generated.png"
PROMPT_PATH = SOURCE_DIR / "north-canonical-03-trial-02-prompt.txt"
ORIGINAL = ROOT / "assets/generated/characters/rabbit-worker/walk_north.png"
BASE_PROPOSAL = OUTPUT_DIR / "north-phase5-trial06-8frame-proposal.png"
K5 = OUTPUT_DIR / "north-canonical-05-trial-06-uniform.png"

K3_OUT = OUTPUT_DIR / "north-canonical-03-trial-02-uniform.png"
PROPOSAL_OUT = OUTPUT_DIR / "north-k03-trial02-8frame-proposal.png"
FULL8_REVIEW = OUTPUT_DIR / "north-k03-trial02-full8-review.png"
NEIGHBOR_REVIEW = OUTPUT_DIR / "north-k03-trial02-k02-k04-k05-review.png"
NOMINAL_GIF = OUTPUT_DIR / "north-k03-trial02-nominal-8phase.gif"
HALF_SPEED_GIF = OUTPUT_DIR / "north-k03-trial02-half-speed-8phase.gif"
MANIFEST_OUT = SOURCE_DIR / "north-k03-trial02-manifest.json"

FRAME = 512
FRAME_COUNT = 8
ALPHA_THRESHOLD = 16
GROUND_Y = 465
TORSO_CENTER_X = 256
# The exact one-source-master scale accepted for canonical K5 trial06.
FIXED_K5_SCALE = 0.40773276015281634
EXPECTED_RAW_SHA256 = "5b150d47cf946f3ba6ef19a61cb1895c0d5c50032d9d535665948039f03aeccd"
EXPECTED_ORIGINAL_SHA256 = "feb7dedef4e77f5b1b28d5143d641b99d3a90500abaa5b9827989e96af76927b"
EXPECTED_BASE_PROPOSAL_SHA256 = "244171ab60f25e618891511062f94add0c8a83851b734b4593330a634c071f8c"
EXPECTED_K5_SHA256 = "1b55ca0f529776adb290c5ca680e6547772b4df4edafedeb64743ed4ab6e0979"
EXPECTED_RAW_VISIBLE_BBOX = (345, 107, 866, 1146)
RAW_HEAD_EARS_WIDTH = 291.0  # same orange-pixel mask family as accepted raw K5's 283px
RAW_TORSO_WIDTH_ESTIMATE = 185.0  # rigid blue bib/torso body, not sleeves or legs
CANONICAL_HEAD_EARS_TARGET = 114.0
CANONICAL_TORSO_TARGET = 78.0
RAW_HEAD_CENTER_X = 628.5

POSE_ORDER = [
    "left_contact",
    "left_weight_down",
    "right_passing_candidate_k03_trial02",
    "right_knee_up_original",
    "right_contact_corrected_trial06",
    "right_weight_down",
    "left_passing_original",
    "left_knee_up_original",
]


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha_path(path: Path) -> str:
    return sha_bytes(path.read_bytes())


def visible_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    alpha = image.convert("RGBA").getchannel("A")
    return alpha.point(lambda value: 255 if value > ALPHA_THRESHOLD else 0).getbbox()


def png_bytes(image: Image.Image) -> bytes:
    buf = BytesIO()
    image.save(buf, format="PNG")
    return buf.getvalue()


def composite_checker(cell: Image.Image, tile_size: int = 32) -> Image.Image:
    bg = Image.new("RGBA", cell.size, "white")
    draw = ImageDraw.Draw(bg)
    for y in range(0, cell.height, tile_size):
        for x in range(0, cell.width, tile_size):
            if (x // tile_size + y // tile_size) % 2:
                draw.rectangle(
                    (x, y, min(x + tile_size - 1, cell.width - 1), min(y + tile_size - 1, cell.height - 1)),
                    fill="#c7c7c7",
                )
    bg.alpha_composite(cell.convert("RGBA"))
    return bg.convert("RGB")


LABELS = {
    0: "K1 original contact",
    1: "K2 left weight-down / support left",
    2: "K3 trial02: right passing candidate",
    3: "K4 original: old left-sole owner",
    4: "K5 corrected trial06 / right contact",
    5: "K6 original weight-down",
    6: "K7 original left passing (root cleanup separate)",
    7: "K8 original left knee-up",
}


def render_contact(frames: list[Image.Image], indices: list[int], path: Path, columns: int) -> None:
    font_path = Path("C:/Windows/Fonts/arial.ttf")
    font = ImageFont.truetype(str(font_path), 16) if font_path.exists() else ImageFont.load_default()
    rows = math.ceil(len(indices) / columns)
    label_h = 36
    canvas = Image.new("RGB", (columns * FRAME, rows * (FRAME + label_h)), "#eeeeee")
    draw = ImageDraw.Draw(canvas)
    for slot, idx in enumerate(indices):
        r, c = divmod(slot, columns)
        x, y = c * FRAME, r * (FRAME + label_h)
        draw.text((x + 8, y + 8), LABELS[idx], fill="#111111", font=font)
        canvas.paste(composite_checker(frames[idx]), (x, y + label_h))
    canvas.save(path)


def make_gif(frames: list[Image.Image], path: Path, frame_delay_ms: int) -> None:
    previews = [composite_checker(frame).convert("P", palette=Image.Palette.ADAPTIVE, colors=256) for frame in frames]
    previews[0].save(
        path,
        save_all=True,
        append_images=previews[1:],
        duration=frame_delay_ms,
        loop=0,
        disposal=2,
        optimize=False,
    )


def main() -> None:
    for path in (RAW, PROMPT_PATH, ORIGINAL, BASE_PROPOSAL, K5):
        if not path.is_file():
            raise SystemExit(f"Required staged input is missing: {path}")
    for path, expected, label in (
        (RAW, EXPECTED_RAW_SHA256, "raw K3 master"),
        (ORIGINAL, EXPECTED_ORIGINAL_SHA256, "original North strip"),
        (BASE_PROPOSAL, EXPECTED_BASE_PROPOSAL_SHA256, "corrected-K5 base proposal"),
        (K5, EXPECTED_K5_SHA256, "accepted K5 normalized cell"),
    ):
        actual = sha_path(path)
        if actual != expected:
            raise SystemExit(f"Pinned {label} hash mismatch: {actual}")

    raw = Image.open(RAW).convert("RGBA")
    if raw.size != (1254, 1254) or raw.getchannel("A").getextrema() != (0, 255):
        raise SystemExit(f"Unexpected raw master dimensions/transparency: {raw.size}")
    crop = visible_bbox(raw)
    if crop != EXPECTED_RAW_VISIBLE_BBOX:
        raise SystemExit(f"Raw K3 visible bbox changed: {crop}")

    # One accepted fixed scale; dimensions are the natural result of this scale,
    # never a height-derived fit. Crop and anchor translation are the only edits.
    subject = raw.crop(crop)
    size = (round(subject.width * FIXED_K5_SCALE), round(subject.height * FIXED_K5_SCALE))
    resized = subject.resize(size, Image.Resampling.LANCZOS)
    resized_bbox = visible_bbox(resized)
    if resized_bbox is None:
        raise SystemExit("Normalized K3 vanished")
    norm = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    torso_relative_x = (RAW_HEAD_CENTER_X - crop[0]) * FIXED_K5_SCALE
    paste_x = round(TORSO_CENTER_X - torso_relative_x)
    paste_y = GROUND_Y - resized_bbox[3]
    norm.alpha_composite(resized, (paste_x, paste_y))
    final_bbox = visible_bbox(norm)
    if final_bbox is None or final_bbox[3] != GROUND_Y:
        raise SystemExit(f"K3 baseline changed: {final_bbox}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    K3_OUT.write_bytes(png_bytes(norm))
    original = Image.open(ORIGINAL).convert("RGBA")
    if original.size != (FRAME * FRAME_COUNT, FRAME):
        raise SystemExit(f"Expected original 8-frame strip, got {original.size}")
    base = Image.open(BASE_PROPOSAL).convert("RGBA")
    frames = [base.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(FRAME_COUNT)]
    # All old canonical cells other than the already accepted K5 must remain exact.
    for i in range(FRAME_COUNT):
        source = original.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME))
        if i == 4:
            if frames[i].tobytes() != Image.open(K5).convert("RGBA").tobytes():
                raise SystemExit("Base K5 is not the accepted trial06 normalized cell")
        elif frames[i].tobytes() != source.tobytes():
            raise SystemExit(f"Base source cell {i + 1} differs from original")
    frames[2] = norm
    proposal = Image.new("RGBA", (FRAME * FRAME_COUNT, FRAME), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        proposal.alpha_composite(frame, (i * FRAME, 0))
    PROPOSAL_OUT.write_bytes(png_bytes(proposal))

    render_contact(frames, list(range(FRAME_COUNT)), FULL8_REVIEW, columns=4)
    render_contact(frames, [1, 2, 3, 4], NEIGHBOR_REVIEW, columns=4)
    make_gif(frames, NOMINAL_GIF, 130)
    make_gif(frames, HALF_SPEED_GIF, 260)

    prompt = PROMPT_PATH.read_text(encoding="utf-8").strip()
    refs = []
    for name, role in (
        ("north-canonical-05-trial-06-generated.png", "sole identity/proportion/style/canvas source master"),
        ("references/north-k03-leg-owner-pose-only-ref-v1.png", "lower-body pose ownership cue only; excluded from proportion decisions"),
        ("references/north-canonical-02-for-k03-k04-ref-v1.png", "neighboring K2 planted-left foot and continuity cue"),
    ):
        ref = SOURCE_DIR / name
        refs.append({"path": str(ref.relative_to(ROOT)).replace("\\", "/"), "role": role, "sha256": sha_path(ref)})

    manifest = {
        "version": 1,
        "batch": "luna-player-north-k03-trial02-single-key-v1",
        "status": "staged for root review only; not integrated",
        "raw_master": {
            "path": str(RAW.relative_to(ROOT)).replace("\\", "/"),
            "sha256": sha_path(RAW),
            "dimensions_px": list(raw.size),
            "visible_bbox_alpha_gt_16": list(crop),
            "transparent_background": True,
        },
        "exact_prompt_path": str(PROMPT_PATH.relative_to(ROOT)).replace("\\", "/"),
        "exact_prompt": prompt,
        "reference_roles": refs,
        "normalization": {
            "policy": "Use exactly the accepted North K5 trial06 raw-master uniform scale; crop and translation only; no height fit or per-cell resize.",
            "fixed_scale": FIXED_K5_SCALE,
            "resampling": "Pillow Lanczos",
            "raw_subject_crop_xyxy": list(crop),
            "resampled_dimensions_px": list(size),
            "resampled_visible_bbox_xyxy": list(resized_bbox),
            "torso_center_anchor_x": TORSO_CENTER_X,
            "raw_center_x_used_for_translation": RAW_HEAD_CENTER_X,
            "ground_baseline_y": GROUND_Y,
            "paste_xy": [paste_x, paste_y],
            "normalized_visible_bbox_xyxy": list(final_bbox),
            "accepted_target_widths_px": {"head_and_ears": [112, 114], "torso": [77, 78]},
            "measured_head_and_ears_raw_px": RAW_HEAD_EARS_WIDTH,
            "measured_head_and_ears_after_fixed_scale_px": RAW_HEAD_EARS_WIDTH * FIXED_K5_SCALE,
            "estimated_rigid_torso_raw_px": RAW_TORSO_WIDTH_ESTIMATE,
            "estimated_rigid_torso_after_fixed_scale_px": RAW_TORSO_WIDTH_ESTIMATE * FIXED_K5_SCALE,
            "total_visible_height_after_fixed_scale_px": final_bbox[3] - final_bbox[1],
            "height_delta_vs_accepted_k5_416px_pct": ((final_bbox[3] - final_bbox[1]) / 416 - 1) * 100,
            "scale_note": "Scale remains fixed at the accepted trial06 value. The natural result is retained even if landmarks do not exactly meet target; no height fit applied.",
        },
        "pose_order": POSE_ORDER,
        "canonical_cell_selection": [
            {"cell": 1, "role": "original left_contact", "exact_original_pixels": True},
            {"cell": 2, "role": "original left_weight_down; support-left cue", "exact_original_pixels": True},
            {"cell": 3, "role": "new right-passing K3 trial02 candidate; viewer-right free leg, viewer-left support", "exact_original_pixels": False, "selection": "pending root review"},
            {"cell": 4, "role": "original K4 right_knee_up, retained unchanged for context", "exact_original_pixels": True},
            {"cell": 5, "role": "accepted corrected K5 trial06", "exact_original_pixels": False},
            {"cell": 6, "role": "original right_weight_down", "exact_original_pixels": True},
            {"cell": 7, "role": "original left_passing; detached top-line cleanup is separately owned by root", "exact_original_pixels": True},
            {"cell": 8, "role": "original left_knee_up", "exact_original_pixels": True},
        ],
        "visual_findings": [
            "Exactly two ears, two arms, two legs, one right-side tool pouch and one red plus one yellow tool are present.",
            "Viewer-left/anatomical-left support boot is planted; viewer-right/anatomical-right free boot is raised and belongs to the right leg.",
            "The raised right boot still presents a broad sole toward camera, so this may read as knee-up rather than the requested compact toe-down passing key.",
            "Arm counter-swing is asymmetric but needs owner review for a clear opposite swing.",
            "Body scale is normalized with the accepted fixed scale; remaining head/torso measurements and overall height are recorded without fitting.",
        ],
        "outputs": {
            "normalized_k03_path": str(K3_OUT.relative_to(ROOT)).replace("\\", "/"),
            "normalized_k03_sha256": sha_path(K3_OUT),
            "review_strip_path": str(PROPOSAL_OUT.relative_to(ROOT)).replace("\\", "/"),
            "review_strip_sha256": sha_path(PROPOSAL_OUT),
            "review_strip_dimensions_px": list(proposal.size),
            "full8_contact_path": str(FULL8_REVIEW.relative_to(ROOT)).replace("\\", "/"),
            "full8_contact_sha256": sha_path(FULL8_REVIEW),
            "k02_k03_k04_k05_contact_path": str(NEIGHBOR_REVIEW.relative_to(ROOT)).replace("\\", "/"),
            "k02_k03_k04_k05_contact_sha256": sha_path(NEIGHBOR_REVIEW),
            "nominal_preview_path": str(NOMINAL_GIF.relative_to(ROOT)).replace("\\", "/"),
            "nominal_frame_delay_ms": 130,
            "half_speed_preview_path": str(HALF_SPEED_GIF.relative_to(ROOT)).replace("\\", "/"),
            "half_speed_frame_delay_ms": 260,
        },
    }
    MANIFEST_OUT.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"K3 sha256: {sha_path(K3_OUT)}; bbox: {final_bbox}; size: {size}")
    print(f"Review strip sha256: {sha_path(PROPOSAL_OUT)}; dimensions: {proposal.size}")
    print(f"Fixed accepted scale: {FIXED_K5_SCALE:.17f}; manifest: {MANIFEST_OUT}")


if __name__ == "__main__":
    main()
