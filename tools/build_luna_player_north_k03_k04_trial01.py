"""Build the staged North K3/K4 canonical repair candidate.

This review-only builder reads the immutable ImageGen master, original rabbit
North strip, accepted North K5 correction and prompt/reference artifacts. It
writes only normalized candidate cells and review artifacts under the owned
animation-overhaul-luna-player-v1 staging paths. It never edits runtime art.
Both new cells use one shared uniform scale; only crop and anchor translation
vary by pose.
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
RAW = SOURCE_DIR / "north-canonical-03-04-trial-01-generated.png"
PROMPT_PATH = SOURCE_DIR / "north-canonical-03-04-trial-01-prompt.txt"
ORIGINAL = ROOT / "assets/generated/characters/rabbit-worker/walk_north.png"
BASE_PROPOSAL = OUTPUT_DIR / "north-phase5-trial06-8frame-proposal.png"
K5 = OUTPUT_DIR / "north-canonical-05-trial-06-uniform.png"

K3_OUT = OUTPUT_DIR / "north-canonical-03-trial-01-uniform.png"
K4_OUT = OUTPUT_DIR / "north-canonical-04-trial-01-uniform.png"
PROPOSAL_OUT = OUTPUT_DIR / "north-k03-k04-trial01-8frame-proposal.png"
FULL8_REVIEW = OUTPUT_DIR / "north-k03-k04-trial01-full8-review.png"
NEIGHBOR_REVIEW = OUTPUT_DIR / "north-k03-k04-trial01-k02-k05-review.png"
NOMINAL_GIF = OUTPUT_DIR / "north-k03-k04-trial01-nominal-8phase.gif"
HALF_SPEED_GIF = OUTPUT_DIR / "north-k03-k04-trial01-half-speed-8phase.gif"
MANIFEST_OUT = SOURCE_DIR / "north-k03-k04-trial01-manifest.json"

FRAME = 512
FRAME_COUNT = 8
ALPHA_THRESHOLD = 16
GROUND_Y = 465
TORSO_CENTER_X = 256
CANONICAL_HEAD_EARS_WIDTH = 114.0
CANONICAL_TORSO_WIDTH = 78.0
RAW_HEAD_EARS_WIDTHS = (185.0, 184.0)
RAW_TORSO_WIDTHS = (138.0, 147.0)
RAW_HEAD_EARS_WIDTH = sum(RAW_HEAD_EARS_WIDTHS) / 2
RAW_TORSO_WIDTH = sum(RAW_TORSO_WIDTHS) / 2
UNIFORM_SCALE = math.sqrt(
    (CANONICAL_HEAD_EARS_WIDTH / RAW_HEAD_EARS_WIDTH)
    * (CANONICAL_TORSO_WIDTH / RAW_TORSO_WIDTH)
)

# Alpha>16 crops are per-pose crops from the stacked master. They remove only
# detached, nearly transparent matte specks; all retained pixels are resampled
# together at the same scale. The bottom-row y coordinates are local to row 2.
CROP_K3 = (485, 31, 780, 614)
CROP_K4 = (467, 8, 803, 596)
RAW_ROWS = ((0, 627), (627, 1254))
TORSO_CENTERS_RAW = (628.0, 629.5)
EXPECTED_RAW_SHA256 = "51f3979a1cf7044a66ea30436db897cb0eb8fefd0cb519e601b8f5e006d0ccab"
EXPECTED_ORIGINAL_SHA256 = "feb7dedef4e77f5b1b28d5143d641b99d3a90500abaa5b9827989e96af76927b"
EXPECTED_BASE_PROPOSAL_SHA256 = "244171ab60f25e618891511062f94add0c8a83851b734b4593330a634c071f8c"
EXPECTED_K5_SHA256 = "1b55ca0f529776adb290c5ca680e6547772b4df4edafedeb64743ed4ab6e0979"

POSE_ORDER = [
    "left_contact",
    "left_weight_down",
    "right_passing_candidate_k03",
    "right_knee_up_candidate_k04",
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


def render_contact(frames: list[Image.Image], indices: list[int], path: Path, columns: int) -> None:
    font_path = Path("C:/Windows/Fonts/arial.ttf")
    font = ImageFont.truetype(str(font_path), 16) if font_path.exists() else ImageFont.load_default()
    rows = math.ceil(len(indices) / columns)
    label_h = 36
    canvas = Image.new("RGB", (columns * FRAME, rows * (FRAME + label_h)), "#eeeeee")
    draw = ImageDraw.Draw(canvas)
    labels = {
        0: "K1 left contact: viewer-right sole trails",
        1: "K2 left weight-down: both boots grounded",
        2: "K3 candidate: right leg passes; left supports",
        3: "K4 candidate: right knee-up; left supports",
        4: "K5 trial06: right contact; viewer-left sole trails",
        5: "K6 right weight-down: both boots grounded",
        6: "K7 original: viewer-left sole owner (residue flagged)",
        7: "K8 original: viewer-left sole lifted",
    }
    for slot, idx in enumerate(indices):
        r, c = divmod(slot, columns)
        x, y = c * FRAME, r * (FRAME + label_h)
        draw.text((x + 8, y + 8), labels[idx], fill="#111111", font=font)
        canvas.paste(composite_checker(frames[idx]), (x, y + label_h))
    canvas.save(path)


def make_gif(frames: list[Image.Image], path: Path, frame_delay_ms: int) -> None:
    # Checker composite keeps the preview faithful without GIF alpha fringes.
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
            raise SystemExit(f"Required immutable input is missing: {path}")
    for path, expected, label in (
        (RAW, EXPECTED_RAW_SHA256, "raw master"),
        (ORIGINAL, EXPECTED_ORIGINAL_SHA256, "original North strip"),
        (BASE_PROPOSAL, EXPECTED_BASE_PROPOSAL_SHA256, "trial06 base proposal"),
        (K5, EXPECTED_K5_SHA256, "accepted K5 normalized source"),
    ):
        actual = sha_path(path)
        if actual != expected:
            raise SystemExit(f"Pinned {label} hash mismatch: {actual}")

    raw = Image.open(RAW).convert("RGBA")
    if raw.size != (1254, 1254) or raw.getchannel("A").getextrema() != (0, 255):
        raise SystemExit(f"Unexpected raw master dimensions/transparency: {raw.size}")

    normalized: list[Image.Image] = []
    records: list[dict[str, object]] = []
    crops = (CROP_K3, CROP_K4)
    for pose_idx, (row_bounds, crop_box, torso_center) in enumerate(
        zip(RAW_ROWS, crops, TORSO_CENTERS_RAW), start=3
    ):
        y0, y1 = row_bounds
        row = raw.crop((0, y0, raw.width, y1))
        alpha_box = visible_bbox(row)
        if alpha_box != crop_box:
            raise SystemExit(f"Pose K{pose_idx} alpha crop changed: {alpha_box}")
        subject = row.crop(crop_box)
        size = (round(subject.width * UNIFORM_SCALE), round(subject.height * UNIFORM_SCALE))
        resized = subject.resize(size, Image.Resampling.LANCZOS)
        resized_bbox = visible_bbox(resized)
        if resized_bbox is None:
            raise SystemExit(f"Pose K{pose_idx} vanished during normalization")
        norm = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
        # Only translation varies: align torso center and planted footline.
        torso_relative_x = (torso_center - crop_box[0]) * UNIFORM_SCALE
        paste_x = round(TORSO_CENTER_X - torso_relative_x)
        paste_y = GROUND_Y - resized_bbox[3]
        norm.alpha_composite(resized, (paste_x, paste_y))
        final_bbox = visible_bbox(norm)
        if final_bbox is None or final_bbox[3] != GROUND_Y:
            raise SystemExit(f"Pose K{pose_idx} ground anchor changed: {final_bbox}")
        normalized.append(norm)
        records.append(
            {
                "canonical_key": pose_idx,
                "crop_box_in_row_xyxy": list(crop_box),
                "raw_row_y_bounds": list(row_bounds),
                "alpha_threshold_for_crop_and_bounds": ALPHA_THRESHOLD,
                "shared_uniform_scale": UNIFORM_SCALE,
                "resampling": "Pillow Lanczos",
                "resampled_dimensions_px": list(size),
                "resampled_visible_bbox_xyxy": list(resized_bbox),
                "paste_xy": [paste_x, paste_y],
                "normalized_visible_bbox_xyxy": list(final_bbox),
                "head_ears_width_raw_px": RAW_HEAD_EARS_WIDTHS[pose_idx - 3],
                "torso_width_raw_px": RAW_TORSO_WIDTHS[pose_idx - 3],
                "head_width_after_uniform_scale_px": RAW_HEAD_EARS_WIDTHS[pose_idx - 3] * UNIFORM_SCALE,
                "torso_width_after_uniform_scale_px": RAW_TORSO_WIDTHS[pose_idx - 3] * UNIFORM_SCALE,
                "relative_to_canonical_medians_pct": {
                    "head_ears_width": (RAW_HEAD_EARS_WIDTHS[pose_idx - 3] * UNIFORM_SCALE / CANONICAL_HEAD_EARS_WIDTH - 1) * 100,
                    "torso_width": (RAW_TORSO_WIDTHS[pose_idx - 3] * UNIFORM_SCALE / CANONICAL_TORSO_WIDTH - 1) * 100,
                    "subject_height_vs_410px_canonical": (size[1] / 410 - 1) * 100,
                },
                "normalized_sha256": sha_bytes(png_bytes(norm)),
            }
        )

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    K3_OUT.write_bytes(png_bytes(normalized[0]))
    K4_OUT.write_bytes(png_bytes(normalized[1]))

    original = Image.open(ORIGINAL).convert("RGBA")
    if original.size != (FRAME * FRAME_COUNT, FRAME):
        raise SystemExit(f"Expected 8-frame original North strip, got {original.size}")
    base = Image.open(BASE_PROPOSAL).convert("RGBA")
    frames = [base.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(FRAME_COUNT)]
    # Verify base proposal is the corrected-N5 candidate with seven exact originals.
    for i in range(FRAME_COUNT):
        if i not in (4,) and frames[i].tobytes() != original.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)).tobytes():
            raise SystemExit(f"Base proposal source cell {i + 1} differs from the original")
    frames[2] = normalized[0]
    frames[3] = normalized[1]
    proposal = Image.new("RGBA", (FRAME * FRAME_COUNT, FRAME), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        proposal.alpha_composite(frame, (i * FRAME, 0))
    PROPOSAL_OUT.write_bytes(png_bytes(proposal))

    render_contact(frames, list(range(8)), FULL8_REVIEW, columns=4)
    render_contact(frames, [1, 2, 3, 4], NEIGHBOR_REVIEW, columns=4)
    make_gif(frames, NOMINAL_GIF, 130)
    make_gif(frames, HALF_SPEED_GIF, 260)

    prompt = PROMPT_PATH.read_text(encoding="utf-8").strip()
    if not prompt:
        raise SystemExit("Exact ImageGen prompt is empty")
    raw_sha = sha_path(RAW)
    refs = []
    for name, role in (
        ("north-canonical-02-for-k03-k04-ref-v1.png", "left weight-down endpoint and identity"),
        ("north-corrected-canonical-05-for-k03-k04-ref-v1.png", "approved corrected canonical style and rigid proportions"),
        ("north-canonical-06-for-k03-k04-ref-v1.png", "right weight-down endpoint and identity"),
        ("north-canonical-upper-body-rigid-reference.png", "rigid head and torso design reference"),
    ):
        ref = REF_DIR / name
        refs.append({"path": str(ref.relative_to(ROOT)).replace("\\", "/"), "role": role, "sha256": sha_path(ref)})

    manifest = {
        "version": 1,
        "batch": "luna-player-north-k03-k04-trial01-canonical-repair-v1",
        "status": "rejected by root for canonical review; retained immutable as a pose-only reference; no runtime integration",
        "raw_master": {
            "path": str(RAW.relative_to(ROOT)).replace("\\", "/"),
            "sha256": raw_sha,
            "dimensions_px": list(raw.size),
            "transparent_background": True,
            "low_alpha_note": "Detached alpha specks below threshold 16 extend beyond the subjects; row crops use alpha>16 bounds and retain all pixel values inside the crop.",
        },
        "exact_prompt_path": str(PROMPT_PATH.relative_to(ROOT)).replace("\\", "/"),
        "exact_prompt": prompt,
        "reference_roles": refs,
        "base_inputs": {
            "original_strip_path": str(ORIGINAL.relative_to(ROOT)).replace("\\", "/"),
            "original_strip_sha256": sha_path(ORIGINAL),
            "base_corrected_n5_proposal_path": str(BASE_PROPOSAL.relative_to(ROOT)).replace("\\", "/"),
            "base_corrected_n5_proposal_sha256": sha_path(BASE_PROPOSAL),
            "accepted_n5_normalized_sha256": sha_path(K5),
        },
        "normalization_policy": "one uniform scale for the two-pose raw master, derived from the geometric mean of canonical median head+ears and torso width ratios; per-cell crop and translation only; no cell-specific scale, warp, deformation, mirroring, or pose duplication",
        "normalization_landmarks": {
            "canonical_median_head_ears_width_px": CANONICAL_HEAD_EARS_WIDTH,
            "canonical_median_torso_width_px": CANONICAL_TORSO_WIDTH,
            "raw_master_head_ears_widths_px": list(RAW_HEAD_EARS_WIDTHS),
            "raw_master_torso_widths_px": list(RAW_TORSO_WIDTHS),
            "raw_master_median_head_ears_width_px": RAW_HEAD_EARS_WIDTH,
            "raw_master_median_torso_width_px": RAW_TORSO_WIDTH,
            "shared_uniform_scale": UNIFORM_SCALE,
            "anchor_policy": "torso center x=256; lowest visible pixel y=465; these are translations only",
            "remaining_mismatch": "The raw head-to-torso width ratio is broader than canonical; landmark scale leaves approx. 6% opposing head/torso residuals and both full-body heights approx. 17% shorter than the 410px canonical median. Do not accept by hiding this with per-cell scale.",
        },
        "pose_order": POSE_ORDER,
        "canonical_cell_selection": [
            {"cell": 1, "role": "unchanged original left_contact", "exact_original_pixels": True},
            {"cell": 2, "role": "unchanged original left_weight_down", "exact_original_pixels": True},
            {"cell": 3, "role": "new K3 right-passing candidate; viewer-right/anatomical-right leg passes, viewer-left supports", "exact_original_pixels": False, "selection": "unselected pending owner and scale review"},
            {"cell": 4, "role": "new K4 right-knee-up candidate; same viewer-right/anatomical-right leg lifted, viewer-left supports", "exact_original_pixels": False, "selection": "unselected pending owner and scale review"},
            {"cell": 5, "role": "accepted corrected N5 trial06", "exact_original_pixels": False},
            {"cell": 6, "role": "unchanged original right_weight_down", "exact_original_pixels": True},
            {"cell": 7, "role": "unchanged original left_passing; contains pre-existing detached top-line residue flagged separately", "exact_original_pixels": True},
            {"cell": 8, "role": "unchanged original left_knee_up", "exact_original_pixels": True},
        ],
        "normalized_cells": records,
        "outputs": {
            "k03_path": str(K3_OUT.relative_to(ROOT)).replace("\\", "/"),
            "k03_sha256": sha_path(K3_OUT),
            "k04_path": str(K4_OUT.relative_to(ROOT)).replace("\\", "/"),
            "k04_sha256": sha_path(K4_OUT),
            "review_strip_path": str(PROPOSAL_OUT.relative_to(ROOT)).replace("\\", "/"),
            "review_strip_sha256": sha_path(PROPOSAL_OUT),
            "review_strip_dimensions_px": list(proposal.size),
            "full8_contact_path": str(FULL8_REVIEW.relative_to(ROOT)).replace("\\", "/"),
            "full8_contact_sha256": sha_path(FULL8_REVIEW),
            "neighbor_contact_path": str(NEIGHBOR_REVIEW.relative_to(ROOT)).replace("\\", "/"),
            "neighbor_contact_sha256": sha_path(NEIGHBOR_REVIEW),
            "nominal_preview_path": str(NOMINAL_GIF.relative_to(ROOT)).replace("\\", "/"),
            "nominal_frame_delay_ms": 130,
            "half_speed_preview_path": str(HALF_SPEED_GIF.relative_to(ROOT)).replace("\\", "/"),
            "half_speed_frame_delay_ms": 260,
        },
        "visual_findings": [
            "K3 viewer-right/anatomical-right leg is the free passing leg under the pelvis; viewer-left boot stays flat on the baseline.",
            "K4 continues the same viewer-right leg into a distinct knee-up pose; viewer-left support boot stays planted.",
            "Each pose has exactly two ears, two arms, two legs, one right-side tool pouch, one red tool and one yellow tool; no mirror or extra appendage observed.",
            "K3 arm counter-swing is readable; K4 arms are less clearly opposed and need owner review.",
            "Root rejected the pair: the shared-scale result leaves an obvious approximately 17% body-height shrink; K4 counter-swing is also unclear.",
            "The pair may be used only as a leg-pose/ownership reference for a targeted K3 edit; never as a body-size or proportion reference.",
        ],
    }
    MANIFEST_OUT.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"K3 sha256: {sha_path(K3_OUT)}; bbox: {visible_bbox(normalized[0])}")
    print(f"K4 sha256: {sha_path(K4_OUT)}; bbox: {visible_bbox(normalized[1])}")
    print(f"Proposal sha256: {sha_path(PROPOSAL_OUT)}; dimensions: {proposal.size}")
    print(f"Shared scale: {UNIFORM_SCALE:.16f}; manifest: {MANIFEST_OUT}")


if __name__ == "__main__":
    main()
