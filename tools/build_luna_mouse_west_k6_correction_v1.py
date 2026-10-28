"""Build the isolated K5/K6/K7 review for Luna's mouse-west gait."""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.build_luna_worker_actions_v1 import (  # noqa: E402
    ALPHA_THRESHOLD,
    ANCHOR,
    TARGET,
    extract_atlas,
    head_width,
    lowest_boot_contacts,
    mask_bounds,
    pink_tail_bbox,
    sha256,
    vest_axis_x,
)

SOURCE = ROOT / "assets/source/animation-overhaul-luna-worker-actions-v1/mouse-west"
OUTPUT = ROOT / "output/animation-overhaul/luna-worker-actions/mouse-west/contact6-correction-v1"
RAW_ATLAS = SOURCE / "field-mouse-technician-west-canonical-8phase-v1-generated.png"
K6_RAW = SOURCE / "contact6-correction-v1/field-mouse-worker-k6-right-weight-down-v1-imagegen.png"
K5_CELL = ROOT / "output/animation-overhaul/luna-worker-actions/mouse-west/contact5-correction-v1/field-mouse-worker-k5-opposite-contact-v1-registered-256.png"
OLD_STRIP = ROOT / "output/animation-overhaul/luna-worker-actions/mouse-west/field-mouse-technician-west-canonical-8phase-v2-torso-axis-registered-4x2.png"
ATLAS_SCALE = 0.4276018099547511
SOURCE_HEAD_WIDTH = 219
BACKGROUND = (30, 36, 42)


def make_sheet(path: Path, cells: list[tuple[Image.Image, str]]) -> None:
    scale = 2
    panel = TARGET * scale
    label_h, header_h = 42, 38
    sheet = Image.new("RGB", (len(cells) * panel, header_h + panel + label_h), (27, 32, 38))
    draw = ImageDraw.Draw(sheet)
    draw.text((10, 10), "OWNER: /root/luna_worker_actions | K6 ONE-EDIT CANDIDATE | ROOT REVIEW ONLY", fill=(255, 210, 135))
    for index, (cell, label) in enumerate(cells):
        x, y = index * panel, header_h
        bg = Image.new("RGBA", (panel, panel), (*BACKGROUND, 255))
        bg.alpha_composite(cell.resize((panel, panel), Image.Resampling.NEAREST))
        sheet.paste(bg.convert("RGB"), (x, y))
        draw.text((x + 8, y + panel + 8), label, fill=(245, 220, 165))
    sheet.save(path, optimize=True)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    atlas = Image.open(RAW_ATLAS).convert("RGBA")
    old_frames, _ = extract_atlas(atlas)
    if len(old_frames) != 8:
        raise ValueError(f"Expected eight atlas phases, found {len(old_frames)}")
    old_strip = Image.open(OLD_STRIP).convert("RGBA")
    if old_strip.size != (TARGET * 4, TARGET * 2):
        raise ValueError(f"Unexpected old strip dimensions: {old_strip.size}")
    old_k7 = old_strip.crop((2 * TARGET, TARGET, 3 * TARGET, 2 * TARGET))
    k5 = Image.open(K5_CELL).convert("RGBA")
    if k5.size != (TARGET, TARGET):
        raise ValueError(f"Unexpected registered K5 size: {k5.size}")

    generated = Image.open(K6_RAW).convert("RGBA")
    raw_bbox = mask_bounds(generated)
    cropped = generated.crop(raw_bbox)
    raw_head_width = head_width(cropped)
    if raw_head_width <= 0:
        raise ValueError("Generated K6 has no measurable head landmark")
    normalization = SOURCE_HEAD_WIDTH / raw_head_width
    normalized_size = (round(cropped.width * normalization), round(cropped.height * normalization))
    normalized = cropped.resize(normalized_size, Image.Resampling.LANCZOS)
    normalized_path = OUTPUT / "field-mouse-worker-k6-right-weight-down-v1-normalized-to-atlas-source-scale.png"
    normalized.save(normalized_path, optimize=True)

    resized_size = (round(normalized.width * ATLAS_SCALE), round(normalized.height * ATLAS_SCALE))
    resized = normalized.resize(resized_size, Image.Resampling.LANCZOS)
    resized_bbox = mask_bounds(resized)
    vest_x, orange_pixels = vest_axis_x(resized)
    tx = round(ANCHOR[0] - vest_x)
    ty = round(ANCHOR[1] - (resized_bbox[3] - 1))
    cell = Image.new("RGBA", (TARGET, TARGET), (0, 0, 0, 0))
    cell.alpha_composite(resized, (tx, ty))
    bbox = mask_bounds(cell)
    edge = {"left": bbox[0] == 0, "top": bbox[1] == 0, "right": bbox[2] == TARGET, "bottom": bbox[3] == TARGET}
    if any(edge.values()):
        raise ValueError(f"K6 candidate touches/clips a cell edge: {bbox}")
    k6_cell_path = OUTPUT / "field-mouse-worker-k6-right-weight-down-v1-registered-256.png"
    cell.save(k6_cell_path, optimize=True)

    boots = lowest_boot_contacts(normalized)
    feet = [{
        "x": round(point["x"] * ATLAS_SCALE + tx, 3),
        "y": round(point["y"] * ATLAS_SCALE + ty, 3),
        "normalized_row_span_x": point["row_span_x"],
    } for point in boots["contacts"]]
    tail_bbox = pink_tail_bbox(cell, ANCHOR[0])
    sheet_path = OUTPUT / "owner-luna-worker-actions-contact5-new-weightdown6-tentative-passing7-v1.png"
    make_sheet(sheet_path, [
        (k5, "K5: provisionally accepted far/right contact; staged only"),
        (cell, "NEW K6: far boot flat, near heel-up/toe-down candidate; root review"),
        (old_k7, "OLD K7: tentative left-passing reference per root; not approved"),
    ])

    metrics = {
        "status": "one K6 edit staged for root review only; K5 is provisionally accepted as a staged cell; K7 remains tentative; full gait cycle remains unapproved; no runtime install",
        "raw_candidate": {
            "path": K6_RAW.relative_to(ROOT).as_posix(),
            "sha256": sha256(K6_RAW),
            "size_px": list(generated.size),
            "alpha_bbox_gt16": list(raw_bbox),
            "head_width_before_normalization_px": raw_head_width,
        },
        "normalization": {
            "method": "one uniform full-pose scale maps the same top-43%-silhouette head-width landmark to the K1 raw-art width; the same atlas-wide runtime match scale is then applied; no cell-bbox fitting, warp, or limb-specific edits",
            "source_head_width_target_px": SOURCE_HEAD_WIDTH,
            "candidate_uniform_resize_to_source_landmark": normalization,
            "normalized_size_px": list(normalized.size),
            "normalized_head_width_px": head_width(normalized),
            "shared_atlas_scale": ATLAS_SCALE,
            "effective_uniform_candidate_crop_scale": normalization * ATLAS_SCALE,
        },
        "registration": {
            "method": "same torso vest-axis x registration and lowest body-alpha common ground baseline as K1-K8 v2 review",
            "landmark": "median x-coordinate of orange vest pixels in upper-torso band",
            "vest_axis_before_translation_px": round(vest_x, 3),
            "orange_landmark_pixel_count": orange_pixels,
            "rigid_translation_px": [tx, ty],
            "registered_torso_axis_x_px": round(vest_x + tx, 3),
            "common_ground_y_px": round(resized_bbox[3] - 1 + ty, 3),
            "registered_alpha_bbox_gt16": list(bbox),
            "opaque_alpha_touches_cell_border": edge,
            "estimated_sole_contact_points_px": feet,
            "estimated_sole_x_spread_px": round(boots["screen_x_spread"] * ATLAS_SCALE, 3),
            "estimated_lowest_sole_row_before_registration_px": boots["row_y"],
            "pink_tail_bbox_after_registration_px": tail_bbox,
            "foot_metric_limit": "Alpha-row runs estimate sole contacts; they do not identify semantic leg side. Visually check flat far boot and grounded near toe before approving.",
        },
        "visual_audit": {
            "anatomy_identity": "At raw-image view, two ears (near pink, far gray), two arms, two legs, one pink tail, and one black case remain visible; case hand/side and near-arm counter-swing appear unchanged.",
            "target_pose": "First visual read shows the un-pocketed far/right forward boot flat on the baseline and the pocketed near/left trailing boot with its toe down and heel raised modestly; body load appears restrained. Parent review remains authoritative.",
            "unresolved": "Fullcycle still requires viable K8 and other missing semantics; this one K6 candidate does not approve a cycle. K7 is shown only as a tentative passing reference.",
        },
        "outputs": {
            "normalized_candidate": {"path": normalized_path.relative_to(ROOT).as_posix(), "sha256": sha256(normalized_path), "size_px": list(normalized.size)},
            "registered_k6_cell": {"path": k6_cell_path.relative_to(ROOT).as_posix(), "sha256": sha256(k6_cell_path), "size_px": list(cell.size)},
            "owner_k5_k6_k7_sheet": {"path": sheet_path.relative_to(ROOT).as_posix(), "sha256": sha256(sheet_path)},
        },
    }
    metrics_path = OUTPUT / "field-mouse-worker-k6-right-weight-down-v1-review-metrics.json"
    metrics_path.write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"k6_cell": str(k6_cell_path), "sheet": str(sheet_path), "metrics": str(metrics_path), "bbox": bbox, "feet": feet}, indent=2))


if __name__ == "__main__":
    main()
