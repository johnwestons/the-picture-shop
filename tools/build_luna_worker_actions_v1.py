"""Build review-only diagnostics for Luna's isolated mouse-west gait master.

The ImageGen source is immutable. This script detects its eight horizontally
separated silhouettes by transparent alpha gaps, derives one atlas-wide scale
from the approved runtime west idle, then registers the v2 review by the vest
torso axis and common boot baseline. The rejected v1 foot registration is
preserved in its output. No shared technician builder or runtime art is edited.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "assets/source/animation-overhaul-luna-worker-actions-v1/mouse-west"
OUTPUT_DIR = ROOT / "output/animation-overhaul/luna-worker-actions/mouse-west"
RAW = SOURCE_DIR / "field-mouse-technician-west-canonical-8phase-v1-generated.png"
REFERENCE = ROOT / "assets/generated/technician-motion-v2/field-mouse-technician/idle_west.png"
PHASES = [
    "left_contact", "left_weight_down", "right_passing", "right_knee_up",
    "right_contact", "right_weight_down", "left_passing", "left_knee_up",
]
TARGET = 256
ANCHOR = (128.0, 229.0)
ALPHA_THRESHOLD = 16
PHASE_DURATION_MS = 1000 / 6  # review preview only; no runtime timing is assigned


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mask_bounds(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = np.asarray(image.getchannel("A"))
    ys, xs = np.where(alpha > ALPHA_THRESHOLD)
    if len(xs) == 0:
        raise ValueError("An extracted pose has no alpha above threshold 16")
    return int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)


def row_runs(row: np.ndarray, minimum_width: int = 6, merge_gap: int = 12) -> list[tuple[int, int]]:
    xs = np.flatnonzero(row)
    if len(xs) == 0:
        return []
    cuts = np.flatnonzero(np.diff(xs) > 1) + 1
    groups = np.split(xs, cuts)
    spans = [(int(group[0]), int(group[-1] + 1)) for group in groups if len(group) >= minimum_width]
    merged: list[list[int]] = []
    for start, end in spans:
        if merged and start - merged[-1][1] <= merge_gap:
            merged[-1][1] = end
        else:
            merged.append([start, end])
    return [(start, end) for start, end in merged]


def horizontal_runs(mask: np.ndarray) -> list[tuple[int, int]]:
    active = np.any(mask, axis=0)
    points = np.flatnonzero(active)
    if len(points) == 0:
        return []
    groups = np.split(points, np.flatnonzero(np.diff(points) > 1) + 1)
    return [(int(g[0]), int(g[-1] + 1)) for g in groups]


def head_width(image: Image.Image) -> int:
    left, top, right, bottom = mask_bounds(image)
    height = bottom - top
    alpha = image.getchannel("A").crop((left, top, right, top + round(height * 0.43)))
    box = alpha.point(lambda value: 255 if value > ALPHA_THRESHOLD else 0).getbbox()
    if box is None:
        raise ValueError("Missing head landmark in pose")
    return box[2] - box[0]


def reference_head_widths(path: Path) -> list[int]:
    image = Image.open(path).convert("RGBA")
    if image.width % 2:
        raise ValueError("Expected the reviewed two-frame west idle reference")
    widths = []
    for index in range(2):
        cell = image.crop((index * image.width // 2, 0, (index + 1) * image.width // 2, image.height))
        widths.append(head_width(cell))
    return widths


def extract_atlas(raw: Image.Image) -> tuple[list[Image.Image], list[dict]]:
    width, height = raw.size
    rows = [(0, round(height / 2)), (round(height / 2), height)]
    alpha = np.asarray(raw.getchannel("A"))
    binary = alpha > ALPHA_THRESHOLD
    frames, records = [], []
    for row_index, (y0, y1) in enumerate(rows):
        x_runs = horizontal_runs(binary[y0:y1, :])
        if len(x_runs) != 4:
            raise ValueError(f"Expected four separated alpha silhouettes in row {row_index + 1}; got {x_runs}")
        for col_index, (x0, x1) in enumerate(x_runs):
            frame = raw.crop((x0, y0, x1, y1)).convert("RGBA")
            frames.append(frame)
            nominal_left = round(col_index * width / 4)
            nominal_right = round((col_index + 1) * width / 4)
            records.append({
                "phase": len(frames),
                "phase_name": PHASES[len(frames) - 1],
                "atlas_cell_row_one_based": row_index + 1,
                "atlas_cell_column_one_based": col_index + 1,
                "alpha_gap_extraction_bounds_raw_px": [x0, y0, x1, y1],
                "nominal_equal_grid_bounds_raw_px": [nominal_left, y0, nominal_right, y1],
                "extends_outside_nominal_grid_x": x0 < nominal_left or x1 > nominal_right,
            })
    return frames, records


def lowest_boot_contacts(frame: Image.Image) -> dict:
    alpha = np.asarray(frame.getchannel("A"))
    mask = alpha > ALPHA_THRESHOLD
    left, top, right, bottom = mask_bounds(frame)
    scan_top = max(top, bottom - round((bottom - top) * 0.17))
    selected = None
    for y in range(bottom - 1, scan_top - 1, -1):
        runs = row_runs(mask[y, :])
        if runs:
            selected = (y, runs)
            break
    if selected is None:
        raise ValueError("Could not find lower boot-contact pixels")
    # The lowest visible sole row is the ground-contact proxy. Choosing a
    # higher row because it exposes more fragments can place the sprite below
    # its 256px cell after registration.
    y, runs = selected
    contacts = [
        {"x": round((x0 + x1 - 1) / 2, 3), "y": y, "row_span_x": [x0, x1 - 1]}
        for x0, x1 in runs
    ]
    return {
        "row_y": y,
        "contacts": contacts,
        "midpoint_x": round(float(np.mean([point["x"] for point in contacts])), 3),
        "screen_x_spread": round(max(point["x"] for point in contacts) - min(point["x"] for point in contacts), 3),
        "method": "alpha>16 row runs on the lowest visible sole row in the lowest 17% of silhouette; merge same-sole fragments separated by <=12 raw pixels",
    }


def transparent_cell(frame: Image.Image, scale: float) -> tuple[Image.Image, dict]:
    original_bounds = mask_bounds(frame)
    boot = lowest_boot_contacts(frame)
    resized = frame.resize((round(frame.width * scale), round(frame.height * scale)), Image.Resampling.LANCZOS)
    transformed_x = boot["midpoint_x"] * scale
    transformed_y = boot["row_y"] * scale
    tx = round(ANCHOR[0] - transformed_x)
    ty = round(ANCHOR[1] - transformed_y)
    cell = Image.new("RGBA", (TARGET, TARGET), (0, 0, 0, 0))
    cell.alpha_composite(resized, (tx, ty))
    box = mask_bounds(cell)
    # Preserve every opaque pixel with a tiny whole-pose rigid correction if
    # the boot-registered transform places an extreme tail/outline on an edge.
    # The body is never resized; the resulting anchor offset is reported.
    margin = 1
    correction_x = max(margin - box[0], min(0, (TARGET - margin) - box[2]))
    correction_y = max(margin - box[1], min(0, (TARGET - margin) - box[3]))
    if correction_x or correction_y:
        fitted = Image.new("RGBA", (TARGET, TARGET), (0, 0, 0, 0))
        fitted.alpha_composite(cell, (correction_x, correction_y))
        cell = fitted
        tx += correction_x
        ty += correction_y
        box = mask_bounds(cell)
    edge_touch = {
        "left": box[0] == 0,
        "top": box[1] == 0,
        "right": box[2] == TARGET,
        "bottom": box[3] == TARGET,
    }
    return cell, {
        "raw_alpha_bbox_local_px_gt16": list(original_bounds),
        "raw_head_width_px": head_width(frame),
        "raw_boot_contacts": boot,
        "uniform_scale_for_entire_atlas": scale,
        "rigid_translation_cell_px": [tx, ty],
        "registered_boot_anchor_cell_px": [ANCHOR[0], ANCHOR[1]],
        "actual_boot_anchor_after_edge_fit_px": [
            round(boot["midpoint_x"] * scale + tx, 3),
            round(boot["row_y"] * scale + ty, 3),
        ],
        "edge_fit_rigid_correction_px": [correction_x, correction_y],
        "registered_foot_span_cell_px": [
            round((contact["x"] * scale + tx), 3) for contact in boot["contacts"]
        ],
        "registered_boot_contact_y_cell_px": round(boot["row_y"] * scale + ty, 3),
        "registered_body_axis_cell_px": None,
        "registered_alpha_bbox_gt16": list(box),
        "opaque_alpha_touches_cell_border": edge_touch,
        "clipped_by_registered_cell": any(edge_touch.values()),
    }


def body_axis(frame: Image.Image) -> float:
    left, top, right, bottom = mask_bounds(frame)
    alpha = np.asarray(frame.getchannel("A"))
    start = top + round((bottom - top) * 0.32)
    stop = top + round((bottom - top) * 0.50)
    centers = []
    for y in range(start, min(stop, frame.height)):
        xs = np.flatnonzero(alpha[y, left:right] >= 128)
        if len(xs):
            centers.append(left + (float(xs[0]) + float(xs[-1]) + 1) / 2)
    return float(np.median(centers)) if centers else (left + right) / 2


def vest_axis_x(frame: Image.Image) -> tuple[float, int]:
    """Use the orange vest body, excluding swinging arms, tail and black case."""
    left, top, right, bottom = mask_bounds(frame)
    rgb = np.asarray(frame.convert("RGB"))
    alpha = np.asarray(frame.getchannel("A"))
    y0 = top + round((bottom - top) * 0.30)
    y1 = top + round((bottom - top) * 0.61)
    r, g, b = rgb[y0:y1, :, 0], rgb[y0:y1, :, 1], rgb[y0:y1, :, 2]
    orange = (alpha[y0:y1, :] > ALPHA_THRESHOLD) & (r >= 170) & (g >= 45) & (g <= 185) & (b <= 125) & ((r - g) >= 45)
    xs = np.where(orange)[1]
    if len(xs) == 0:
        raise ValueError("Could not find orange vest landmark for torso-axis registration")
    return float(np.median(xs)), int(len(xs))


def pink_tail_bbox(frame: Image.Image, torso_x: float) -> list[int] | None:
    left, top, right, bottom = mask_bounds(frame)
    height = bottom - top
    y0 = top + round(height * 0.44)
    y1 = top + round(height * 0.88)
    rgb = np.asarray(frame.convert("RGB"))
    alpha = np.asarray(frame.getchannel("A"))
    r, g, b = rgb[y0:y1, :, 0], rgb[y0:y1, :, 1], rgb[y0:y1, :, 2]
    pink = (alpha[y0:y1, :] > ALPHA_THRESHOLD) & (r > 145) & (g > 45) & (b > 70) & ((r - b) < 120)
    pink[:, :max(0, int(torso_x))] = False
    ys, xs = np.where(pink)
    if len(xs) == 0:
        return None
    return [int(xs.min()), int(y0 + ys.min()), int(xs.max() + 1), int(y0 + ys.max() + 1)]


def torso_plan(frame: Image.Image, scale: float) -> dict:
    resized = frame.resize((round(frame.width * scale), round(frame.height * scale)), Image.Resampling.LANCZOS)
    box = mask_bounds(resized)
    axis, orange_pixels = vest_axis_x(resized)
    tx = round(ANCHOR[0] - axis)
    ty = round(ANCHOR[1] - (box[3] - 1))
    transformed_box = [box[0] + tx, box[1] + ty, box[2] + tx, box[3] + ty]
    return {
        "resized": resized,
        "resized_bbox": box,
        "vest_axis_x": axis,
        "orange_landmark_pixel_count": orange_pixels,
        "tx": tx,
        "ty": ty,
        "transformed_bbox": transformed_box,
        "ground_contact_y": box[3] - 1,
    }


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    raw = Image.open(RAW).convert("RGBA")
    frames, source_records = extract_atlas(raw)
    reference_widths = reference_head_widths(REFERENCE)
    raw_widths = [head_width(frame) for frame in frames]
    scale = float(np.median(reference_widths) / np.median(raw_widths))

    plans = [torso_plan(frame, scale) for frame in frames]
    margin = 1
    required_padding = 0
    for plan in plans:
        left, top, right, bottom = plan["transformed_bbox"]
        required_padding = max(required_padding, margin - left, margin - top,
                               right - (TARGET - margin), bottom - (TARGET - margin), 0)
    pad = math.ceil(required_padding)
    cell_size = TARGET + 2 * pad
    ground_y = ANCHOR[1] + pad
    torso_x = ANCHOR[0] + pad

    strip = Image.new("RGBA", (cell_size * 4, cell_size * 2), (0, 0, 0, 0))
    registered, pose_metrics = [], []
    for index, (frame, plan) in enumerate(zip(frames, plans)):
        cell = Image.new("RGBA", (cell_size, cell_size), (0, 0, 0, 0))
        tx, ty = plan["tx"] + pad, plan["ty"] + pad
        cell.alpha_composite(plan["resized"], (tx, ty))
        box = mask_bounds(cell)
        boot = lowest_boot_contacts(frame)
        foot_points = [{
            "x": round(point["x"] * scale + tx, 3),
            "y": round(point["y"] * scale + ty, 3),
        } for point in boot["contacts"]]
        tail_bbox = pink_tail_bbox(cell, torso_x)
        col, row = index % 4, index // 4
        strip.alpha_composite(cell, (col * cell_size, row * cell_size))
        registered.append(cell)
        pose_metrics.append({
            **source_records[index],
            "raw_alpha_bbox_gt16": list(mask_bounds(frame)),
            "raw_head_width_px": head_width(frame),
            "scale_shared_across_all_eight_poses": scale,
            "torso_axis_landmark": "median x-coordinate of vest-orange pixels in upper torso band",
            "raw_torso_axis_x_px_after_uniform_resize": round(plan["vest_axis_x"], 3),
            "vest_landmark_pixel_count": plan["orange_landmark_pixel_count"],
            "rigid_translation_px": [tx, ty],
            "registered_torso_axis_x_px": round(plan["vest_axis_x"] + tx, 3),
            "registered_common_ground_contact_y_px": round(plan["ground_contact_y"] + ty, 3),
            "estimated_sole_contact_points_after_registration_px": foot_points,
            "estimated_sole_spread_px": round(boot["screen_x_spread"] * scale, 3),
            "pink_tail_bbox_after_registration_px": tail_bbox,
            "pink_tail_tip_x_after_registration_px": tail_bbox[2] - 1 if tail_bbox else None,
            "registered_alpha_bbox_gt16": list(box),
            "opaque_alpha_touches_cell_border": {
                "left": box[0] == 0, "top": box[1] == 0,
                "right": box[2] == cell_size, "bottom": box[3] == cell_size,
            },
            "clipped_by_registered_cell": box[0] == 0 or box[1] == 0 or box[2] == cell_size or box[3] == cell_size,
        })

    strip_path = OUTPUT_DIR / "field-mouse-technician-west-canonical-8phase-v2-torso-axis-registered-4x2.png"
    strip.save(strip_path, optimize=True)

    background = Image.new("RGBA", (cell_size * 4, cell_size * 2), (30, 36, 42, 255))
    background.alpha_composite(strip)
    contact = Image.new("RGB", (cell_size * 4, cell_size * 2 + 52), (30, 36, 42))
    contact.paste(background.convert("RGB"), (0, 0))
    draw = ImageDraw.Draw(contact)
    for index, name in enumerate(PHASES):
        col, row = index % 4, index // 4
        draw.text((col * cell_size + 5, row * cell_size + cell_size + 5), f"{index + 1}: {name}", fill=(245, 220, 165))
    sheet_path = OUTPUT_DIR / "field-mouse-technician-west-canonical-8phase-v2-torso-axis-contact-sheet.png"
    contact.save(sheet_path, optimize=True)

    anchor_sheet = contact.copy()
    draw = ImageDraw.Draw(anchor_sheet)
    for index, metrics in enumerate(pose_metrics):
        col, row = index % 4, index // 4
        y = row * cell_size + int(round(ground_y))
        x = col * cell_size + int(round(torso_x))
        draw.line((col * cell_size + 1, y, (col + 1) * cell_size - 2, y), fill=(65, 235, 95), width=1)
        draw.line((x, row * cell_size + 2, x, row * cell_size + cell_size - 2), fill=(90, 120, 255), width=1)
        draw.ellipse((x - 4, y - 4, x + 4, y + 4), outline=(255, 80, 80), width=2)
        for point in metrics["estimated_sole_contact_points_after_registration_px"]:
            px = col * cell_size + int(round(point["x"]))
            py = row * cell_size + int(round(point["y"]))
            draw.ellipse((px - 2, py - 2, px + 2, py + 2), fill=(255, 235, 80))
    anchor_path = OUTPUT_DIR / "field-mouse-technician-west-canonical-8phase-v2-torso-axis-diagnostic.png"
    anchor_sheet.save(anchor_path, optimize=True)

    preview_frames = []
    for frame in registered:
        preview = Image.new("RGBA", frame.size, (30, 36, 42, 255))
        preview.alpha_composite(frame)
        preview_frames.append(preview.convert("RGB"))
    gif_path = OUTPUT_DIR / "field-mouse-technician-west-canonical-8phase-v2-torso-axis-preview-6fps.gif"
    delays = [round(PHASE_DURATION_MS)] * len(preview_frames)
    preview_frames[0].save(gif_path, save_all=True, append_images=preview_frames[1:], loop=0, duration=delays, disposal=2)
    slow_path = OUTPUT_DIR / "field-mouse-technician-west-canonical-8phase-v2-torso-axis-preview-3fps.gif"
    preview_frames[0].save(slow_path, save_all=True, append_images=preview_frames[1:], loop=0, duration=[round(2 * PHASE_DURATION_MS)] * len(preview_frames), disposal=2)

    statuses = [metrics["extends_outside_nominal_grid_x"] for metrics in source_records]
    torso_axes = [metric["registered_torso_axis_x_px"] for metric in pose_metrics]
    support_y = [metric["registered_common_ground_contact_y_px"] for metric in pose_metrics]
    sole_spreads = [metric["estimated_sole_spread_px"] for metric in pose_metrics]
    tail_tip_xs = [metric["pink_tail_tip_x_after_registration_px"] for metric in pose_metrics if metric["pink_tail_tip_x_after_registration_px"] is not None]
    comparison_path = OUTPUT_DIR / "owner-luna-worker-actions-contact1-vs5-knee4-vs8-v2.png"
    comparison_header = 34
    panel_size = cell_size * 2
    comparison = Image.new("RGB", (panel_size * 2, comparison_header + (panel_size + 30) * 2), (27, 32, 38))
    cd = ImageDraw.Draw(comparison)
    cd.text((10, 8), "OWNER: /root/luna_worker_actions | v2 torso-axis review | ROOT REVIEW ONLY — FULL CYCLE REJECTED", fill=(255, 210, 135))
    compare_items = [(0, "CONTACT 1: LEFT CONTACT"), (4, "CONTACT 5: RIGHT CONTACT"),
                     (3, "KNEE-UP 4: RIGHT LEG"), (7, "KNEE-UP 8: LEFT LEG")]
    for item_index, (phase_index, label) in enumerate(compare_items):
        panel_col, panel_row = item_index % 2, item_index // 2
        x0 = panel_col * panel_size
        y0 = comparison_header + panel_row * (panel_size + 30)
        enlarged = registered[phase_index].resize((panel_size, panel_size), Image.Resampling.NEAREST)
        comparison.paste((30, 36, 42), (x0, y0, x0 + panel_size, y0 + panel_size))
        comparison.paste(enlarged.convert("RGB"), (x0, y0))
        cd.text((x0 + 8, y0 + panel_size + 6), label, fill=(245, 220, 165))
    comparison.save(comparison_path, optimize=True)
    secondary_comparison_path = OUTPUT_DIR / "owner-luna-worker-actions-weight2-vs6-passing3-vs7-v2.png"
    secondary_header = 34
    secondary = Image.new("RGB", (panel_size * 2, secondary_header + (panel_size + 30) * 2), (27, 32, 38))
    sd = ImageDraw.Draw(secondary)
    sd.text((10, 8), "OWNER: /root/luna_worker_actions | TENTATIVE SOURCE-PAIR REVIEW | ROOT REVIEW ONLY", fill=(255, 210, 135))
    secondary_items = [(1, "WEIGHT 2: LEFT LOAD"), (5, "WEIGHT 6: RIGHT LOAD"),
                       (2, "PASSING 3: RIGHT LEG"), (6, "PASSING 7: LEFT LEG")]
    for item_index, (phase_index, label) in enumerate(secondary_items):
        panel_col, panel_row = item_index % 2, item_index // 2
        x0 = panel_col * panel_size
        y0 = secondary_header + panel_row * (panel_size + 30)
        enlarged = registered[phase_index].resize((panel_size, panel_size), Image.Resampling.NEAREST)
        secondary.paste((30, 36, 42), (x0, y0, x0 + panel_size, y0 + panel_size))
        secondary.paste(enlarged.convert("RGB"), (x0, y0))
        sd.text((x0 + 8, y0 + panel_size + 6), label, fill=(245, 220, 165))
    secondary.save(secondary_comparison_path, optimize=True)

    metadata = {
        "status": "full-cycle poses rejected by root; v2 is torso-axis-registered review material only; no ImageGen retry or runtime installation authorized",
        "raw_source": RAW.relative_to(ROOT).as_posix(),
        "raw_sha256": sha256(RAW),
        "raw_size_px": list(raw.size),
        "raw_mode": raw.mode,
        "alpha_threshold_exclusive": ALPHA_THRESHOLD,
        "grid": {"rows": 2, "columns": 4, "phase_order": PHASES, "raw_horizontal_separators_detected_per_row": 4},
        "extraction": {
            "method": "four contiguous horizontal alpha>16 silhouette runs per row, separated by transparent gaps; preserves complete tails that cross the nominal equal-grid boundary",
            "poses_outside_nominal_equal_grid_x": [i + 1 for i, extends in enumerate(statuses) if extends],
            "warning": "Raw silhouettes cross nominal equal-cell x boundaries; direct equal-grid cropping would trim adjacent alpha. Registered review strip uses alpha-gap silhouette extraction.",
        },
        "scale": {
            "method": "one uniform scale for the entire raw atlas, matched by median head-width landmark to the approved runtime west idle pair; no per-pose resizing",
            "reference_path": REFERENCE.relative_to(ROOT).as_posix(),
            "reference_sha256": sha256(REFERENCE),
            "reference_head_widths_px": reference_widths,
            "reference_median_head_width_px": float(np.median(reference_widths)),
            "raw_pose_head_widths_px": raw_widths,
            "raw_median_head_width_px": float(np.median(raw_widths)),
            "atlas_uniform_scale": scale,
        },
        "registration": {
            "method": "one global scale; rigid per-pose x registration by vest-orange torso landmark; vertical registration by lowest boot alpha to one common ground baseline; no per-pose resizing/warping",
            "torso_axis_target_px_before_padding": ANCHOR[0],
            "common_ground_target_px_before_padding": ANCHOR[1],
            "cell_padding_each_side_px": pad,
            "cell_size_px": cell_size,
            "torso_axis_target_px_after_padding": torso_x,
            "common_ground_px_after_padding": ground_y,
            "torso_axis_x_spread_after_registration_px": round(max(torso_axes) - min(torso_axes), 4),
            "ground_contact_y_spread_after_registration_px": round(max(support_y) - min(support_y), 4),
            "estimated_sole_span_spread_by_pose_px": [round(value, 3) for value in sole_spreads],
            "pink_tail_tip_x_positions_after_registration_px": tail_tip_xs,
            "pink_tail_tip_x_spread_px": round(max(tail_tip_xs) - min(tail_tip_xs), 3) if tail_tip_xs else None,
            "individual_poses": pose_metrics,
            "limitation": "Sole spans are alpha-derived geometry estimates, not semantic left/right foot IDs; root should visually verify the specific support legs.",
        },
        "outputs": {
            "registered_strip": {"path": strip_path.relative_to(ROOT).as_posix(), "sha256": sha256(strip_path), "size_px": list(strip.size)},
            "contact_sheet": {"path": sheet_path.relative_to(ROOT).as_posix(), "sha256": sha256(sheet_path)},
            "torso_axis_ground_diagnostic": {"path": anchor_path.relative_to(ROOT).as_posix(), "sha256": sha256(anchor_path)},
            "preview_6fps_visual_only": {"path": gif_path.relative_to(ROOT).as_posix(), "sha256": sha256(gif_path)},
            "preview_3fps_visual_only": {"path": slow_path.relative_to(ROOT).as_posix(), "sha256": sha256(slow_path)},
            "owner_labeled_comparison": {"path": comparison_path.relative_to(ROOT).as_posix(), "sha256": sha256(comparison_path)},
            "owner_labeled_tentative_pairs": {"path": secondary_comparison_path.relative_to(ROOT).as_posix(), "sha256": sha256(secondary_comparison_path)},
        },
        "proposed_phase_semantics": [
            {"phase": i + 1, "name": name, "preview_duration_ms": round(PHASE_DURATION_MS), "duration_status": "visual preview only; no runtime timing assigned"}
            for i, name in enumerate(PHASES)
        ],
        "visual_review": {
            "anatomy": "At atlas view, two anatomical ears are visible per pose (one pink near ear and one small gray far ear); no separate third-ear lobe is apparent. Two arms, two legs, one pink tail, and the black case are visible.",
            "identity_and_view": "Gray west-facing mouse, blue shirt, orange reflective vest, navy trousers, brown boots, pink tail to screen right, nose screen left; the black case stays behind the right hip on the same screen side across poses.",
            "contact_alternation": "Rejected by root: phases 1 and 5 both lead with the pocketed near-left leg.",
            "passing_and_knee_up": "Rejected by root: phases 4 and 8 raise the same far leg. Phases 3 and 7 remain tentative opposite-leg passing candidates pending close inspection.",
            "loading_phases": "Phases 2 and 6 have potential as distinct weight-down candidates, but root noted tail alignment and registration required correction; full semantic acceptance remains pending.",
            "usable_source_cells": "Tentative only: phases 3 and 7 are the most plausible opposite-leg passing pair; phases 2 and 6 may serve as weight-down references, although phase 2 nearly repeats contact 1 and phase 6 shows only subtle unload. No cells are approved independently by this agent.",
            "cell_margin": "The v2 torso-axis/common-ground registration uses one atlas-wide scale and keeps all alpha inside the 256px cell without padding or tail clipping; the original v1 foot-midpoint registration remains preserved and marked rejected.",
            "acceptance": "full cycle rejected; torso-axis v2 is review-only and awaits root inspection",
        },
    }
    metrics_path = OUTPUT_DIR / "field-mouse-technician-west-canonical-8phase-v2-torso-axis-review-metrics.json"
    metrics_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"scale": scale, "raw_pose_head_widths": raw_widths, "reference_head_widths": reference_widths,
                      "padding": pad, "cell_size": cell_size,
                      "torso_axis_spread": metadata["registration"]["torso_axis_x_spread_after_registration_px"],
                      "ground_spread": metadata["registration"]["ground_contact_y_spread_after_registration_px"],
                      "strip": str(strip_path), "sheet": str(sheet_path), "comparison": str(comparison_path),
                      "secondary_comparison": str(secondary_comparison_path), "metrics": str(metrics_path)}, indent=2))


if __name__ == "__main__":
    main()
