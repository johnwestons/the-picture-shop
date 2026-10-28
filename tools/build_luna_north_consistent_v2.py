from __future__ import annotations

import hashlib
import json
from pathlib import Path
from statistics import median

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/animation-overhaul-luna-player-v1/consistent-north-v2"
OUT = ROOT / "output/animation-overhaul/luna-player/consistent-north-v2"

RAW = SOURCE / "north-consistent-v2-generated-raw.png"
REPLACEMENT_RAW = SOURCE / "north-v2-phase7-replacement-generated-raw.png"
PROMPT = SOURCE / "north-consistent-v2-exact-prompt.txt"
REPLACEMENT_PROMPT = SOURCE / "north-v2-phase7-replacement-exact-prompt.txt"
K5_RAW = ROOT / "assets/source/animation-overhaul-luna-player-v1/pose-corrections-v1/north-canonical-05-trial-06-generated.png"
K5_NORMALIZED = ROOT / "output/animation-overhaul/luna-player/pose-corrections-v1/north-phase5-trial06-8frame-proposal.png"
POSE_GUIDE = SOURCE / "v1-k3-lowerbody-pose-role-reference.png"

FRAME = 512
GROUND_Y = 466
HEAD_CENTER_X = 256
ALPHA_THRESHOLD = 16
K5_MASTER_SCALE = 0.40773276015281634
EXPECTED = {
    "v2_raw": "0fce24948744ba68d614af1e5a994b88659c05e5f840a54e80c5d0df661c63f7",
    "phase7_raw": "82a060ccd9d5e412341c863df9cd4abab2f2108ad71cfa6c63b9b46c704e6225",
    "k5_raw": "d8f4220f356bc5069ab10252b641d839f54e9023451dce2e487b03a89bc72c83",
    "pose_guide": "eb98aad0385f6dd8cccedbcca16087b0dc2a122c510c6318c7af9052974b66ad",
}

RUNTIME_DIRECTIONS = [
    ("north", "walk_north.png", "idle_north.png"),
    ("northeast", "walk_northeast.png", "idle_northeast.png"),
    ("east", "walk.png", "idle.png"),
    ("southeast", "walk_southeast.png", "idle_southeast.png"),
    ("south", "walk_south.png", "idle_south.png"),
]
RUNTIME_DIR = ROOT / "assets/generated/characters/rabbit-worker"

PHASES = [
    {"phase": 1, "role": "left contact", "owner": "left lead planted; right trailing heel low"},
    {"phase": 2, "role": "left weight-down", "owner": "left support; right heel release near ground"},
    {"phase": 3, "role": "right compact passing", "owner": "right ankle under pelvis; left support planted"},
    {"phase": 4, "role": "right knee-up recovery", "owner": "right knee bent and lifted; left support"},
    {"phase": 5, "role": "right contact", "owner": "right lead planted; left trailing heel low"},
    {"phase": 6, "role": "right weight-down", "owner": "right support; left heel release near ground"},
    {"phase": 7, "role": "left compact passing", "owner": "left ankle under pelvis; right support planted"},
    {"phase": 8, "role": "left knee-up recovery", "owner": "left knee bent and lifted; right support"},
]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bbox_alpha(image: Image.Image, threshold: int = ALPHA_THRESHOLD):
    alpha = image.convert("RGBA").getchannel("A")
    return alpha.point(lambda value: 255 if value > threshold else 0).getbbox()


def resize_premultiplied(image: Image.Image, scale: float) -> Image.Image:
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    return image.convert("RGBa").resize(size, Image.Resampling.LANCZOS).convert("RGBA")


def orange(r: int, g: int, b: int, a: int) -> bool:
    return a > 64 and r > 130 and g > 45 and r > g * 1.20 and g > b * 1.10 and b < 125


def blue(r: int, g: int, b: int, a: int) -> bool:
    return a > 64 and b > 70 and b > r * 1.25 and g > 35 and b > g * 0.90


def row_widths(image: Image.Image, y0: int, y1: int, predicate):
    pixels = image.convert("RGBA").load()
    result = []
    for y in range(max(0, y0), min(image.height, y1)):
        xs = [x for x in range(image.width) if predicate(*pixels[x, y])]
        if xs:
            result.append({"y": y, "width": max(xs) - min(xs) + 1, "x_min": min(xs), "x_max": max(xs)})
    return result


def metrics(image: Image.Image):
    image = image.convert("RGBA")
    box = bbox_alpha(image)
    head_rows = row_widths(image, 170, 250, orange)
    torso_rows = row_widths(image, 245, 335, blue)
    max_head = max(head_rows, key=lambda row: row["width"]) if head_rows else None
    max_torso = max(torso_rows, key=lambda row: row["width"]) if torso_rows else None
    px = image.load()
    red_all = red_outside_tools = dark_ink = visible = 0
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = px[x, y]
            if a > 64:
                visible += 1
                if max(r, g, b) < 55:
                    dark_ink += 1
                if r > 160 and g < 80 and b < 95:
                    red_all += 1
                    if not (x > 285 and 230 < y < 330):
                        red_outside_tools += 1
    return {
        "alpha_bbox_threshold_16": list(box) if box else None,
        "visible_height_px": box[3] - box[1] if box else 0,
        "orange_head_band_y170_249_max_row_width_px": max_head,
        "blue_overall_band_y245_334_median_row_width_px": median([row["width"] for row in torso_rows]) if torso_rows else None,
        "blue_overall_band_y245_334_max_row_width_px": max_torso,
        "bright_red_pixels_total_alpha64": red_all,
        "bright_red_pixels_outside_expected_tool_roi_alpha64": red_outside_tools,
        "dark_ink_pixel_share_of_visible_alpha64_percent": round(100 * dark_ink / visible, 3) if visible else 0,
        "visible_alpha64_pixel_count": visible,
    }


def dark_roi_measure(image: Image.Image, box):
    x0, y0, x1, y1 = box
    pixels = image.convert("RGBA").load()
    points = []
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, a = pixels[x, y]
            if a > 64 and max(r, g, b) < 80:
                points.append((x, y))
    bbox = None if not points else [min(x for x, _ in points), min(y for _, y in points), max(x for x, _ in points) + 1, max(y for _, y in points) + 1]
    return {
        "roi_xyxy": list(box),
        "dark_pixel_bbox_proxy": bbox,
        "dark_pixel_count": len(points),
        "roi_area_px": (x1 - x0) * (y1 - y0),
        "dark_pixel_share_of_roi_percent": round(100 * len(points) / ((x1 - x0) * (y1 - y0)), 2),
    }


def white_composite(image: Image.Image) -> Image.Image:
    base = Image.new("RGBA", image.size, (255, 255, 255, 255))
    base.alpha_composite(image.convert("RGBA"))
    return base.convert("RGB")


def make_gif(frames, path: Path, duration_ms: int = 130):
    indexed_frames = []
    for frame in frames:
        small = resize_premultiplied(frame, 64 / FRAME)
        alpha = small.getchannel("A")
        indexed = small.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT)
        qpix = indexed.load()
        apix = alpha.load()
        for y in range(64):
            for x in range(64):
                if apix[x, y] <= 96:
                    qpix[x, y] = 255
        palette = indexed.getpalette() or []
        palette.extend([0] * (768 - len(palette)))
        palette[765:768] = [0, 0, 0]
        indexed.putpalette(palette[:768])
        indexed_frames.append(indexed)
    indexed_frames[0].save(path, save_all=True, append_images=indexed_frames[1:], duration=duration_ms, loop=0, transparency=255, disposal=2, optimize=False)


def padded_cell(source: Image.Image, scale: float, dx: int, dy: int) -> Image.Image:
    resized = resize_premultiplied(source, scale)
    cell = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    cell.alpha_composite(resized, (dx, dy))
    return cell


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for key, path in [("v2_raw", RAW), ("phase7_raw", REPLACEMENT_RAW), ("k5_raw", K5_RAW), ("pose_guide", POSE_GUIDE)]:
        if sha(path) != EXPECTED[key]:
            raise SystemExit(f"Pinned source mismatch for {key}: {path}")
    if Image.open(RAW).size != (1536, 1024):
        raise SystemExit(f"Unexpected V2 raw dimensions: {Image.open(RAW).size}")
    if Image.open(REPLACEMENT_RAW).size != (1254, 1254):
        raise SystemExit(f"Unexpected phase-7 raw dimensions: {Image.open(REPLACEMENT_RAW).size}")

    raw = Image.open(RAW).convert("RGBA")
    raw_cells = [raw.crop((col * 384, row * 512, (col + 1) * 384, (row + 1) * 512)) for row in range(2) for col in range(4)]
    source_boxes = [bbox_alpha(cell) for cell in raw_cells]
    source_heights = [box[3] - box[1] for box in source_boxes]
    base_scale = 410.0 / median(source_heights)
    base_x = round(HEAD_CENTER_X - (384 / 2) * base_scale)
    base_y = GROUND_Y - round(median([box[3] - 1 for box in source_boxes]) * base_scale)
    base_frames = [padded_cell(cell, base_scale, base_x, base_y) for cell in raw_cells]

    native = Image.new("RGBA", (FRAME * 8, FRAME), (0, 0, 0, 0))
    contact = Image.new("RGBA", (FRAME * 4, FRAME * 2), (0, 0, 0, 0))
    for i, frame in enumerate(base_frames):
        native.alpha_composite(frame, (i * FRAME, 0))
        row, col = divmod(i, 4)
        contact.alpha_composite(frame, (col * FRAME, row * FRAME))
    native_path = OUT / "north-v2-full8-native.png"
    contact_path = OUT / "north-v2-full8-contact-white.png"
    native.save(native_path)
    white_composite(contact).save(contact_path)
    base_gif_path = OUT / "north-v2-64worldpx-timed.gif"
    make_gif(base_frames, base_gif_path)

    # Use the accepted K5 raw master's pinned character calibration exactly. Translation
    # only follows that scale; no independent bounding-box fit is applied to phase 7.
    replacement_raw = Image.open(REPLACEMENT_RAW).convert("RGBA")
    replacement_box = bbox_alpha(replacement_raw)
    if replacement_box is None:
        raise SystemExit("Empty phase-7 replacement")
    # Head anchor is the centroid of orange pixels in the source head region; this is a
    # rigid horizontal registration only and does not alter scale or anatomy.
    source_px = replacement_raw.load()
    orange_xs = []
    for y in range(max(0, replacement_box[1]), min(replacement_raw.height, replacement_box[1] + round((replacement_box[3] - replacement_box[1]) * 0.46))):
        for x in range(replacement_box[0], replacement_box[2]):
            if orange(*source_px[x, y]):
                orange_xs.append(x)
    if not orange_xs:
        raise SystemExit("No orange head anchor in phase-7 replacement")
    replacement_center_x = sum(orange_xs) / len(orange_xs)
    scaled_box = [round(value * K5_MASTER_SCALE) for value in replacement_box]
    replacement_dx = round(HEAD_CENTER_X - replacement_center_x * K5_MASTER_SCALE)
    replacement_dy = GROUND_Y - (scaled_box[3] - 1)
    replacement_cell = padded_cell(replacement_raw, K5_MASTER_SCALE, replacement_dx, replacement_dy)
    proposal_frames = list(base_frames)
    proposal_frames[6] = replacement_cell
    proposal = Image.new("RGBA", (FRAME * 8, FRAME), (0, 0, 0, 0))
    proposal_contact = Image.new("RGBA", (FRAME * 4, FRAME * 2), (0, 0, 0, 0))
    for i, frame in enumerate(proposal_frames):
        proposal.alpha_composite(frame, (i * FRAME, 0))
        row, col = divmod(i, 4)
        proposal_contact.alpha_composite(frame, (col * FRAME, row * FRAME))
    proposal_path = OUT / "north-v2-phase7-replacement-proposal.png"
    proposal_contact_path = OUT / "north-v2-phase7-replacement-contact-white.png"
    proposal_gif_path = OUT / "north-v2-phase7-replacement-64worldpx-timed.gif"
    proposal.save(proposal_path)
    white_composite(proposal_contact).save(proposal_contact_path)
    make_gif(proposal_frames, proposal_gif_path)

    phase7_neighbor = Image.new("RGBA", (FRAME * 5, FRAME), (255, 255, 255, 255))
    k5_sheet = Image.open(K5_NORMALIZED).convert("RGBA")
    k5_cell = k5_sheet.crop((FRAME * 4, 0, FRAME * 5, FRAME))
    compare_cells = [base_frames[5], base_frames[6], replacement_cell, base_frames[7], k5_cell]
    for i, frame in enumerate(compare_cells):
        phase7_neighbor.alpha_composite(frame, (i * FRAME, 0))
    phase7_neighbor_path = OUT / "north-v2-phase7-neighbors-and-k5-white.png"
    phase7_neighbor.convert("RGB").save(phase7_neighbor_path)

    north_walk = Image.open(RUNTIME_DIR / "walk_north.png").convert("RGBA")
    north_frames = [north_walk.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(8)]
    north_compare = Image.new("RGBA", (FRAME * 4, FRAME * 4), (255, 255, 255, 255))
    for i, frame in enumerate(base_frames):
        row, col = divmod(i, 4)
        north_compare.alpha_composite(frame, (col * FRAME, row * FRAME))
    for i, frame in enumerate(north_frames):
        row, col = divmod(i, 4)
        north_compare.alpha_composite(frame, (col * FRAME, (row + 2) * FRAME))
    north_compare_path = OUT / "north-v2-vs-installed-north-walk-white.png"
    north_compare.convert("RGB").save(north_compare_path)

    # Five-view reference sheet: idle phase 1 in row 1, walk phase 1 in row 2.
    crossview = Image.new("RGBA", (FRAME * 5, FRAME * 2), (255, 255, 255, 255))
    crossview.draw = ImageDraw.Draw(crossview)
    direction_audit = []
    for col, (direction, walk_name, idle_name) in enumerate(RUNTIME_DIRECTIONS):
        walk_image = Image.open(RUNTIME_DIR / walk_name).convert("RGBA")
        idle_image = Image.open(RUNTIME_DIR / idle_name).convert("RGBA")
        walk_count = walk_image.width // FRAME
        idle_count = idle_image.width // FRAME
        walk_cells = [walk_image.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(walk_count)]
        idle_cells = [idle_image.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(idle_count)]
        crossview.alpha_composite(idle_cells[0], (col * FRAME, 0))
        crossview.alpha_composite(walk_cells[0], (col * FRAME, FRAME))
        direction_audit.append({
            "direction": direction,
            "walk_path": (RUNTIME_DIR / walk_name).relative_to(ROOT).as_posix(),
            "walk_sha256": sha(RUNTIME_DIR / walk_name),
            "walk_frames": [
                {"phase": i + 1, "alpha_bbox_threshold_16": bbox_alpha(cell), "visible_height_px": (bbox_alpha(cell)[3] - bbox_alpha(cell)[1]) if bbox_alpha(cell) else 0,
                 "dark_ink_pixel_share_of_visible_alpha64_percent": metrics(cell)["dark_ink_pixel_share_of_visible_alpha64_percent"]}
                for i, cell in enumerate(walk_cells)
            ],
            "idle_path": (RUNTIME_DIR / idle_name).relative_to(ROOT).as_posix(),
            "idle_sha256": sha(RUNTIME_DIR / idle_name),
            "idle_frames": [
                {"phase": i + 1, "alpha_bbox_threshold_16": bbox_alpha(cell), "visible_height_px": (bbox_alpha(cell)[3] - bbox_alpha(cell)[1]) if bbox_alpha(cell) else 0}
                for i, cell in enumerate(idle_cells)
            ],
        })
    crossview_path = OUT / "north-v2-cross-view-idle-walk-contact-white.png"
    crossview.convert("RGB").save(crossview_path)

    base_metrics = [metrics(frame) for frame in base_frames]
    proposal_metrics = [metrics(frame) for frame in proposal_frames]
    k5_metrics = metrics(k5_cell)
    phase7_dark_before = dark_roi_measure(base_frames[6], (178, 390, 250, 466))
    phase7_dark_after = dark_roi_measure(replacement_cell, (178, 390, 250, 466))
    phase3_dark = dark_roi_measure(base_frames[2], (280, 390, 342, 466))
    diff_counts = []
    for i, (before, after) in enumerate(zip(base_frames, proposal_frames)):
        diff = ImageChops.difference(before, after)
        diff_counts.append({"phase": i + 1, "changed_pixel_count": sum(1 for pixel in diff.getdata() if pixel != (0, 0, 0, 0))})

    # Cross-view reference set includes both walk and idle art for all five installed views.
    accepted_walk_heights = [
        f["visible_height_px"]
        for group in direction_audit for f in group["walk_frames"]
    ]
    all_idle_heights = [
        f["visible_height_px"]
        for group in direction_audit for f in group["idle_frames"]
    ]
    candidate_heights = [m["visible_height_px"] for m in base_metrics]
    replacement_height = proposal_metrics[6]["visible_height_px"]

    gif_info = []
    for gif_path in [base_gif_path, proposal_gif_path]:
        gif = Image.open(gif_path)
        durations = []
        for frame_index in range(gif.n_frames):
            gif.seek(frame_index)
            durations.append(gif.info.get("duration"))
        gif_info.append({"path": gif_path.relative_to(ROOT).as_posix(), "sha256": sha(gif_path), "frame_count": gif.n_frames, "frame_size_px": list(gif.size), "durations_ms": durations})

    source_paths = [RAW, REPLACEMENT_RAW, PROMPT, REPLACEMENT_PROMPT, K5_RAW, POSE_GUIDE]
    output_paths = [native_path, contact_path, base_gif_path, proposal_path, proposal_contact_path, proposal_gif_path, phase7_neighbor_path, north_compare_path, crossview_path]
    audit = {
        "title": "Luna rabbit-worker north V2 cycle and isolated phase-7 replacement audit; staged only",
        "generation_provenance": {
            "v2_full8_generation_id": "exec-077b4008-f33c-41c8-b2bc-ecb3dea427c5",
            "v2_full8_cached_output": r"C:\Users\johnw\.codex\generated_images\01a17bec-a216-72b3-ac73-5e56d3da1c90\exec-077b4008-f33c-41c8-b2bc-ecb3dea427c5.png",
            "v2_full8_transparent_background_requested": True,
            "phase7_replacement_generation_id": "exec-7da74b6f-5014-4e25-9c63-4a2bc1234d97",
            "phase7_replacement_cached_output": r"C:\Users\johnw\.codex\generated_images\01a17bec-a216-72b3-ac73-5e56d3da1c90\exec-7da74b6f-5014-4e25-9c63-4a2bc1234d97.png",
            "phase7_replacement_transparent_background_requested": True,
        },
        "provenance": {
            "source_hashes_sha256": {p.relative_to(ROOT).as_posix(): sha(p) for p in source_paths},
            "identity_style_reference": K5_RAW.relative_to(ROOT).as_posix(),
            "identity_style_reference_sha256": sha(K5_RAW),
            "identity_style_reference_role": "sole full-character identity, style, outfit, proportion, camera, palette, and outline reference for both generations",
            "pose_role_reference": POSE_GUIDE.relative_to(ROOT).as_posix(),
            "pose_role_reference_sha256": sha(POSE_GUIDE),
            "pose_role_reference_role": "lower-body compact-passing amplitude only; upper-body style excluded; phase 7 uses opposite leg owner without mirroring",
            "runtime_comparison_hashes_sha256": {group["walk_path"]: group["walk_sha256"] for group in direction_audit} | {group["idle_path"]: group["idle_sha256"] for group in direction_audit},
        },
        "transparency_verification": {
            "raw_full8_mode": Image.open(RAW).mode,
            "raw_full8_alpha_extrema": list(Image.open(RAW).getchannel("A").getextrema()),
            "raw_full8_corner_alpha": [Image.open(RAW).getpixel(pt)[3] for pt in [(0, 0), (1535, 0), (0, 1023), (1535, 1023)]],
            "raw_full8_background_gap_alpha_at_700_500": Image.open(RAW).getpixel((700, 500))[3],
            "white_composite_diagnostic": "The brown/blue tint visible in a raw preview is RGB stored under alpha=0. Compositing the PNG against white removes it; no background-removal operation was applied.",
            "phase7_raw_mode": Image.open(REPLACEMENT_RAW).mode,
            "phase7_raw_alpha_extrema": list(Image.open(REPLACEMENT_RAW).getchannel("A").getextrema()),
            "phase7_raw_corner_alpha": [Image.open(REPLACEMENT_RAW).getpixel(pt)[3] for pt in [(0, 0), (1253, 0), (0, 1253), (1253, 1253)]],
        },
        "base_normalization": {
            "raw_grid": "4 columns x 2 rows, row-major; source cells are 384 x 512 px",
            "source_visible_heights_alpha_gt_16_px": source_heights,
            "one_shared_source_master_scale": base_scale,
            "scale_formula": "410 / median(alpha>16 visible heights of the eight source cells)",
            "fixed_translation_xy_px_for_all_base_phases": [base_x, base_y],
            "common_ground_anchor_y": GROUND_Y,
            "cell_registration": "same scale and same fixed translation for all eight source cells; only rigid registration, no per-cell scale or deformation",
            "resampling": "Lanczos on premultiplied RGBA to avoid hidden transparent RGB bleeding; source PNG remains untouched",
            "phase_transforms": [
                {"phase": i + 1, "source_crop_xyxy": [i % 4 * 384, i // 4 * 512, (i % 4 + 1) * 384, (i // 4 + 1) * 512], "source_bbox_alpha_gt_16": list(source_boxes[i]), "scale": base_scale, "translation_xy_px": [base_x, base_y], "registered_bbox_alpha_gt_16": bbox_alpha(base_frames[i])}
                for i in range(8)
            ],
        },
        "phase7_registration": {
            "scale": K5_MASTER_SCALE,
            "scale_source": "pinned accepted K5 raw-master scale from north-phase5-trial06-8frame-proposal-manifest.json; same identity calibration, not refit from phase-7 bounds",
            "raw_bbox_alpha_gt_16": list(replacement_box),
            "head_anchor_source_x": replacement_center_x,
            "translation_xy_px": [replacement_dx, replacement_dy],
            "registered_bbox_alpha_gt_16": bbox_alpha(replacement_cell),
            "no_per_cell_fitting": True,
            "other_seven_frame_diff_counts_vs_base": diff_counts,
        },
        "phase_owner_and_visual_audit": [
            {**PHASES[0], "visual_finding": "Clear left contact; opposite boot stays low. Validate final row ownership at game scale."},
            {**PHASES[1], "visual_finding": "Both legs are near the baseline; weight-down compression is subtle."},
            {**PHASES[2], "visual_finding": "Right free foot reads low and compact under the pelvis; narrow shoe presentation, closer to passing than recovery."},
            {**PHASES[3], "visual_finding": "Right knee-up recovery is higher and more flexed than phase 3."},
            {**PHASES[4], "visual_finding": "Clear right contact; left trailing boot rises behind the body."},
            {**PHASES[5], "visual_finding": "Both feet near the ground; weight shift remains subtle."},
            {**PHASES[6], "visual_finding": "Base V2 shows the left boot raised behind with visible broad sole, so it reads as recovery rather than compact passing. The sole-guided replacement also lifts the left boot behind and shows a broad dark sole; it does not correct phase role."},
            {**PHASES[7], "visual_finding": "Left knee-up recovery is distinct from contact, though phase 7 still needs to be lower than this pose."},
        ],
        "per_phase_metrics_registered_512": base_metrics,
        "phase7_before_after_dark_sole_proxy": {
            "method": "fixed manually selected dark-pixel ROI, alpha>64 and max(RGB)<80; rough sole proxy, not exact boot segmentation",
            "base_v2_phase7": phase7_dark_before,
            "replacement_phase7": phase7_dark_after,
            "phase3_compact_pass_comparator": phase3_dark,
        },
        "proportion_and_outline_comparison": {
            "k5_accepted_normalized_cell_metrics": k5_metrics,
            "base_v2_cycle_head_widths_px": [m["orange_head_band_y170_249_max_row_width_px"]["width"] if m["orange_head_band_y170_249_max_row_width_px"] else None for m in base_metrics],
            "base_v2_cycle_torso_median_widths_px": [m["blue_overall_band_y245_334_median_row_width_px"] for m in base_metrics],
            "base_v2_cycle_visible_heights_px": candidate_heights,
            "replacement_phase7_metrics": proposal_metrics[6],
            "head_torso_and_height_metrics_are_proxy_values": "Color-mask row-span and alpha-bounds are comparison signals; the adjacent-direction visual contact is the deciding evidence.",
        },
        "installed_cross_view_comparison": {
            "directions": direction_audit,
            "installed_walk_visible_height_range_px": [min(accepted_walk_heights), max(accepted_walk_heights)],
            "installed_idle_visible_height_range_px": [min(all_idle_heights), max(all_idle_heights)],
            "v2_visible_height_range_px": [min(candidate_heights), max(candidate_heights)],
            "cross_view_sheet_rows": ["idle frame 1", "walk phase 1"],
            "visual_comparison_paths": [north_compare_path.relative_to(ROOT).as_posix(), crossview_path.relative_to(ROOT).as_posix(), phase7_neighbor_path.relative_to(ROOT).as_posix()],
        },
        "timed_previews": gif_info,
        "outputs_sha256": {p.relative_to(ROOT).as_posix(): sha(p) for p in output_paths},
        "acceptance": "Staged for root review only. Base V2 has true transparent alpha and no red fringe, with phase 3 reading compact and low. The one phase-7 replacement remains recovery-like with a broad visible sole and exceeds the V2 body height under the pinned K5 calibration; do not promote this replacement. Root decides whether to keep the base V2 phase 7 or reject the full cycle.",
    }
    audit_path = OUT / "north-v2-candidate-and-phase7-replacement-audit.json"
    audit_path.write_text(json.dumps(audit, indent=2), encoding="utf-8")
    print(json.dumps({
        "base_scale": base_scale,
        "base_translation_xy": [base_x, base_y],
        "base_visible_heights": candidate_heights,
        "phase7_replacement_scale": K5_MASTER_SCALE,
        "phase7_replacement_visible_height": replacement_height,
        "phase7_replacement_metrics": proposal_metrics[6],
        "phase7_dark_sole_proxy": {"base": phase7_dark_before, "replacement": phase7_dark_after, "phase3": phase3_dark},
        "changed_pixels_by_phase": diff_counts,
        "installed_walk_height_range": [min(accepted_walk_heights), max(accepted_walk_heights)],
        "installed_idle_height_range": [min(all_idle_heights), max(all_idle_heights)],
        "output_hashes": audit["outputs_sha256"],
        "audit_path": audit_path.relative_to(ROOT).as_posix(),
    }, indent=2))


if __name__ == "__main__":
    main()
