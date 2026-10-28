"""Build isolated, review-only K5 correction comparisons for Luna's mouse gait.

The ImageGen PNG remains immutable. The new single pose is normalized to the
K1 raw-art head-width landmark, then uses the existing atlas-wide runtime scale
and rigid vest-axis/common-ground registration. No runtime files are touched.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import numpy as np
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
OUTPUT = ROOT / "output/animation-overhaul/luna-worker-actions/mouse-west/contact5-correction-v1"
RAW_ATLAS = SOURCE / "field-mouse-technician-west-canonical-8phase-v1-generated.png"
K5_RAW = SOURCE / "contact5-correction-v1/field-mouse-worker-k5-opposite-contact-v1-imagegen.png"
REGISTERED_ATLAS = ROOT / "output/animation-overhaul/luna-worker-actions/mouse-west/field-mouse-technician-west-canonical-8phase-v2-torso-axis-registered-4x2.png"
ATLAS_SCALE = 0.4276018099547511
K1_HEAD_WIDTH_RAW = 219
CONTACT_BACKGROUND = (30, 36, 42)


def centered_cell(source: Image.Image, label: str, size: int = TARGET) -> Image.Image:
    """Keep source registered at 256px; upscale uniformly for review panels."""
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(source, (0, 0))
    return out


def panel_sheet(path: Path, items: list[tuple[Image.Image, str]], columns: int) -> None:
    panel_scale = 2
    panel = TARGET * panel_scale
    label_h = 40
    header_h = 38
    rows = (len(items) + columns - 1) // columns
    canvas = Image.new("RGB", (columns * panel, header_h + rows * (panel + label_h)), (27, 32, 38))
    draw = ImageDraw.Draw(canvas)
    draw.text((10, 10), "OWNER: /root/luna_worker_actions | K5 ONE-EDIT CANDIDATE | ROOT REVIEW ONLY", fill=(255, 210, 135))
    for index, (cell, label) in enumerate(items):
        col, row = index % columns, index // columns
        x, y = col * panel, header_h + row * (panel + label_h)
        bg = Image.new("RGBA", (panel, panel), (*CONTACT_BACKGROUND, 255))
        enlarged = cell.resize((panel, panel), Image.Resampling.NEAREST)
        bg.alpha_composite(enlarged)
        canvas.paste(bg.convert("RGB"), (x, y))
        draw.text((x + 8, y + panel + 8), label, fill=(245, 220, 165))
    canvas.save(path, optimize=True)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    atlas = Image.open(RAW_ATLAS).convert("RGBA")
    frames, _ = extract_atlas(atlas)
    if len(frames) != 8:
        raise ValueError(f"Expected eight raw phases, found {len(frames)}")
    old_strip = Image.open(REGISTERED_ATLAS).convert("RGBA")
    if old_strip.size != (TARGET * 4, TARGET * 2):
        raise ValueError(f"Unexpected registered strip size {old_strip.size}")
    old_cells = [
        old_strip.crop((i % 4 * TARGET, i // 4 * TARGET, (i % 4 + 1) * TARGET, (i // 4 + 1) * TARGET))
        for i in range(8)
    ]

    generated = Image.open(K5_RAW).convert("RGBA")
    gen_bbox = mask_bounds(generated)
    cropped = generated.crop(gen_bbox)
    generated_head_width = head_width(cropped)
    if generated_head_width <= 0:
        raise ValueError("Generated K5 candidate has no measurable head landmark")
    source_scale_normalization = K1_HEAD_WIDTH_RAW / generated_head_width
    normalized_size = (round(cropped.width * source_scale_normalization), round(cropped.height * source_scale_normalization))
    normalized = cropped.resize(normalized_size, Image.Resampling.LANCZOS)
    normalized_path = OUTPUT / "field-mouse-worker-k5-opposite-contact-v1-normalized-to-atlas-source-scale.png"
    normalized.save(normalized_path, optimize=True)

    resized_size = (round(normalized.width * ATLAS_SCALE), round(normalized.height * ATLAS_SCALE))
    resized = normalized.resize(resized_size, Image.Resampling.LANCZOS)
    resized_box = mask_bounds(resized)
    torso_axis, orange_pixels = vest_axis_x(resized)
    tx = round(ANCHOR[0] - torso_axis)
    ty = round(ANCHOR[1] - (resized_box[3] - 1))
    transformed_bbox = [resized_box[0] + tx, resized_box[1] + ty, resized_box[2] + tx, resized_box[3] + ty]
    cell = Image.new("RGBA", (TARGET, TARGET), (0, 0, 0, 0))
    cell.alpha_composite(resized, (tx, ty))
    registered_bbox = mask_bounds(cell)
    touches = {
        "left": registered_bbox[0] == 0,
        "top": registered_bbox[1] == 0,
        "right": registered_bbox[2] == TARGET,
        "bottom": registered_bbox[3] == TARGET,
    }
    if any(touches.values()):
        raise ValueError(f"K5 edit clips at the registered cell edge: {registered_bbox}")

    k5_path = OUTPUT / "field-mouse-worker-k5-opposite-contact-v1-registered-256.png"
    cell.save(k5_path, optimize=True)
    boot = lowest_boot_contacts(normalized)
    effective_source_factor = source_scale_normalization * ATLAS_SCALE
    foot_points = [
        {"x": round(point["x"] * ATLAS_SCALE + tx, 3), "y": round(point["y"] * ATLAS_SCALE + ty, 3), "normalized_row_span_x": point["row_span_x"]}
        for point in boot["contacts"]
    ]
    tail_box = pink_tail_bbox(cell, ANCHOR[0])

    comparison_path = OUTPUT / "owner-luna-worker-actions-contact1-vs-new-contact5-v1.png"
    panel_sheet(comparison_path, [
        (old_cells[0], "K1 source contact: near/pocketed leg leads"),
        (cell, "NEW K5 candidate: far/un-pocketed leg leads; root review only"),
    ], columns=2)
    context_path = OUTPUT / "owner-luna-worker-actions-knee4-new-contact5-weight6-context-v1.png"
    panel_sheet(context_path, [
        (old_cells[3], "K4: knee-up candidate; root flagged same leg as K8"),
        (cell, "NEW K5: opposite-contact edit candidate"),
        (old_cells[5], "K6: flagged; reads heel-lift/passing-like, not clear weight-down"),
    ], columns=3)

    normalized_head = head_width(normalized)
    metadata = {
        "status": "one K5 correction generation staged; source is immutable; candidate awaits root review; full eight-phase cycle remains rejected; no runtime install",
        "raw_candidate": {
            "path": K5_RAW.relative_to(ROOT).as_posix(),
            "sha256": sha256(K5_RAW),
            "size_px": list(generated.size),
            "alpha_bbox_gt16": list(gen_bbox),
            "head_width_before_normalization_px": generated_head_width,
        },
        "normalization": {
            "method": "uniformly resize the new full-character image crop so its established top-43%-silhouette head-width landmark matches K1 raw art (219 px); then apply the same 0.4276018099547511 atlas-wide scale used for all original phases; no per-frame fitting, warp, or limb-specific edit",
            "K1_raw_head_width_px": K1_HEAD_WIDTH_RAW,
            "candidate_uniform_resize_factor_to_K1_raw_art_scale": source_scale_normalization,
            "normalized_candidate_size_px": list(normalized.size),
            "normalized_candidate_head_width_px": normalized_head,
            "atlas_wide_scale": ATLAS_SCALE,
            "effective_uniform_scale_from_candidate_crop": effective_source_factor,
        },
        "registration": {
            "method": "same v2 rigid vest-orange torso-axis x registration and lowest visible body alpha ground baseline as the existing K1-K8 review strip",
            "torso_axis_landmark": "median x-coordinate of orange vest pixels in upper torso band",
            "torso_axis_before_translation_px": round(torso_axis, 3),
            "orange_landmark_pixels": orange_pixels,
            "rigid_translation_px": [tx, ty],
            "registered_torso_axis_x_px": round(torso_axis + tx, 3),
            "common_ground_contact_y_px": round((resized_box[3] - 1) + ty, 3),
            "registered_alpha_bbox_gt16": list(registered_bbox),
            "opaque_alpha_touches_cell_border": touches,
            "estimated_sole_contact_points_px": foot_points,
            "estimated_sole_spread_px": round(boot["screen_x_spread"] * ATLAS_SCALE, 3),
            "estimated_sole_contact_y_before_registration_px": boot["row_y"],
            "pink_tail_bbox_after_registration_px": tail_box,
            "limitation": "Alpha-derived contact points are proxies; root should visually confirm that each boot is planted and the semantic FAR/RIGHT leading leg is correct.",
        },
        "owner_review_context": {
            "K1_vs_new_K5": "Agent visual audit: the un-pocketed far/right leg leads toward screen-left in the new K5 candidate; the pocketed near/left leg trails screen-right; near arm swings forward; black case remains on screen-right. Root acceptance pending.",
            "K4": "Root has flagged the original K4 knee-up as repeating the same raised leg as K8; shown for context only.",
            "K6": "Root has flagged original K6 as reading more like a heel-lift/passing pose than clear right weight-down; shown for context only.",
            "remaining_cycle_status": "No full-cycle approval. Existing K2, K4, K6, and K8 semantic gaps remain unresolved; K3/K7 are only tentative passing references per root.",
        },
        "outputs": {
            "normalized_candidate_source_scale": {"path": normalized_path.relative_to(ROOT).as_posix(), "sha256": sha256(normalized_path), "size_px": list(normalized.size)},
            "registered_k5_cell": {"path": k5_path.relative_to(ROOT).as_posix(), "sha256": sha256(k5_path), "size_px": list(cell.size)},
            "owner_contact_comparison": {"path": comparison_path.relative_to(ROOT).as_posix(), "sha256": sha256(comparison_path)},
            "owner_context_comparison": {"path": context_path.relative_to(ROOT).as_posix(), "sha256": sha256(context_path)},
        },
    }
    metrics_path = OUTPUT / "field-mouse-worker-k5-opposite-contact-v1-review-metrics.json"
    metrics_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"k5": str(k5_path), "contact_comparison": str(comparison_path), "context_comparison": str(context_path), "metrics": str(metrics_path), "registered_bbox": registered_bbox, "feet": foot_points}, indent=2))


if __name__ == "__main__":
    main()
