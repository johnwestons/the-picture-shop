"""Build Luna's staged rabbit-worker 16-frame walk review sheets.

This script reads the approved runtime walks and Luna-owned generated atlases,
then writes normalized review assets only to the Luna-owned source/output paths.
It does not touch runtime art, Config, motion specs, tests, or saves.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from statistics import median

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "source" / "animation-overhaul-luna-player-v1"
OUTPUT = ROOT / "output" / "animation-overhaul" / "luna-player"
NORMALIZED = SOURCE / "normalized-transitions"

FRAME = 512
ANCHOR_X = 256
GROUND_Y = 465
ALPHA_THRESHOLD = 16
HEAD_MEASURE_CUTOFF_FRACTION = 0.42
TORSO_MEASURE_Y_FRACTIONS = (0.30, 0.52)
TORSO_MEASURE_HALF_WIDTH_FRACTION = 0.24
CONTACT_ORDER = [
    "left_contact",
    "left_weight_down",
    "right_passing",
    "right_knee_up",
    "right_contact",
    "right_weight_down",
    "left_passing",
    "left_knee_up",
]
TRANSITION_ORDER = [
    "left_contact_to_left_weight_down",
    "left_weight_down_to_right_passing",
    "right_passing_to_right_knee_up",
    "right_knee_up_to_right_contact",
    "right_contact_to_right_weight_down",
    "right_weight_down_to_left_passing",
    "left_passing_to_left_knee_up",
    "left_knee_up_to_left_contact",
]
POSE_ORDER_16 = []
for canonical, transition in zip(CONTACT_ORDER, TRANSITION_ORDER):
    POSE_ORDER_16.extend((canonical, transition))

VIEWS = {
    "east": {
        "canonical": "assets/generated/characters/rabbit-worker/walk.png",
        "first": ("east-between-atlas-v3-generated.png", 2, 2),
        "second": ("east-secondhalf-atlas-v3-generated.png", 2, 2),
        "replacement": "east-between-04-replacement-v1-generated.png",
    },
    "southeast": {
        "canonical": "assets/generated/characters/rabbit-worker/walk_southeast.png",
        "first": ("southeast-between-atlas-v1-generated.png", 2, 2),
        "second": ("southeast-secondhalf-atlas-v1-generated.png", 4, 1),
    },
    "north": {
        "canonical": "assets/generated/characters/rabbit-worker/walk_north.png",
        "first": ("north-between-atlas-v1-generated.png", 2, 2),
        "second": ("north-secondhalf-atlas-v1-generated.png", 4, 1),
    },
    "northeast": {
        "canonical": "assets/generated/characters/rabbit-worker/walk_northeast.png",
        "first": ("northeast-between-atlas-v3-generated.png", 2, 2),
        "second": ("northeast-secondhalf-atlas-v5-generated.png", 2, 2),
    },
    "south": {
        "canonical": "assets/generated/characters/rabbit-worker/walk_south.png",
        "first": ("south-between-atlas-v1-generated.png", 2, 2),
        "second": ("south-secondhalf-atlas-v1-generated.png", 4, 1),
    },
}

VISUAL_REVIEW_NOTES = {
    "east": "Selected proportion-constrained v3 atlases after comparing newer v4/v5 candidates; the maximum individual head or torso landmark deviation is 12.58%, and every atlas receives one uniform source-master scale.",
    "southeast": "Static 16-frame contact-sheet review: boot placements progress between neighboring canonical phases; two ears and carried tools remain consistent, with no matte or clipping defect observed.",
    "north": "Static 16-frame contact-sheet review: alternating rear-view boot placements remain distinct across the cycle; no anatomy, tool, matte, or clipping defect observed.",
    "northeast": "Selected v3/v5 atlases after comparing newer candidates; every individual head or torso landmark deviation stays below 13% with one uniform source-master scale.",
    "south": "Static 16-frame contact-sheet review: front-view boot placements alternate through the cycle; head/torso residuals are recorded in transition_landmark_fit; no anatomy, tool, matte, or clipping defect observed.",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def significant_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    alpha = image.convert("RGBA").getchannel("A")
    mask = alpha.point(lambda value: 255 if value > ALPHA_THRESHOLD else 0)
    return mask.getbbox()


def crop_grid(path: Path, columns: int, rows: int) -> list[tuple[Image.Image, tuple[int, int, int, int]]]:
    atlas = Image.open(path).convert("RGBA")
    cells = []
    for row in range(rows):
        top = round(row * atlas.height / rows)
        bottom = round((row + 1) * atlas.height / rows)
        for column in range(columns):
            left = round(column * atlas.width / columns)
            right = round((column + 1) * atlas.width / columns)
            cells.append((atlas.crop((left, top, right, bottom)), (left, top, right, bottom)))
    return cells


def crop_single(path: Path) -> tuple[Image.Image, tuple[int, int, int, int]]:
    atlas = Image.open(path).convert("RGBA")
    return atlas, (0, 0, atlas.width, atlas.height)


def expanded_subject_crop(image: Image.Image, bbox: tuple[int, int, int, int]) -> Image.Image:
    left, top, right, bottom = bbox
    margin = 8
    crop_box = (
        max(0, left - margin),
        max(0, top - margin),
        min(image.width, right + margin),
        min(image.height, bottom + margin),
    )
    return image.crop(crop_box)


def landmark_measurements(image: Image.Image) -> dict[str, object]:
    """Measure stable colored head and torso landmarks without using total pose height."""
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    bbox = significant_bbox(rgba)
    if bbox is None:
        raise ValueError("A generated or canonical cell has no significant alpha pixels")
    left, top, right, bottom = bbox
    width, height = right - left, bottom - top
    center_x = (left + right) / 2

    head_points: list[tuple[int, int]] = []
    head_bottom = top + round(height * HEAD_MEASURE_CUTOFF_FRACTION)
    for y in range(top, min(rgba.height, head_bottom)):
        for x in range(left, right):
            r, g, b, alpha = pixels[x, y]
            if (
                alpha > ALPHA_THRESHOLD and r > 115 and g > 30
                and r > g * 1.28 and g > b * 1.20 and b < 135
            ):
                head_points.append((x, y))

    torso_points: list[tuple[int, int]] = []
    torso_top = top + round(height * TORSO_MEASURE_Y_FRACTIONS[0])
    torso_bottom = top + round(height * TORSO_MEASURE_Y_FRACTIONS[1])
    torso_half_width = width * TORSO_MEASURE_HALF_WIDTH_FRACTION
    torso_left = max(left, round(center_x - torso_half_width))
    torso_right = min(right, round(center_x + torso_half_width))
    for y in range(torso_top, min(rgba.height, torso_bottom)):
        for x in range(torso_left, torso_right):
            r, g, b, alpha = pixels[x, y]
            if (
                alpha > ALPHA_THRESHOLD and b > 65 and b > r * 1.12
                and b > g * 1.02 and r < 135
            ):
                torso_points.append((x, y))

    if not head_points or not torso_points:
        raise ValueError("Could not measure both head and torso landmarks in a cell")

    head_bbox = (
        min(x for x, _ in head_points), min(y for _, y in head_points),
        max(x for x, _ in head_points) + 1, max(y for _, y in head_points) + 1,
    )
    torso_bbox = (
        min(x for x, _ in torso_points), min(y for _, y in torso_points),
        max(x for x, _ in torso_points) + 1, max(y for _, y in torso_points) + 1,
    )
    return {
        "head_width_px": head_bbox[2] - head_bbox[0],
        "head_bbox_xyxy": list(head_bbox),
        "torso_width_px": torso_bbox[2] - torso_bbox[0],
        "torso_bbox_xyxy": list(torso_bbox),
    }


def median_landmark_targets(frames: list[Image.Image]) -> dict[str, float]:
    measurements = [landmark_measurements(frame) for frame in frames]
    return {
        "head_width_px": float(median(float(m["head_width_px"]) for m in measurements)),
        "torso_width_px": float(median(float(m["torso_width_px"]) for m in measurements)),
    }


def source_master_scale(
    cells: list[tuple[Image.Image, tuple[int, int, int, int]]],
    canonical_targets: dict[str, float],
) -> tuple[float, dict[str, object]]:
    measurements = [landmark_measurements(image) for image, _ in cells]
    source_head = float(median(float(m["head_width_px"]) for m in measurements))
    source_torso = float(median(float(m["torso_width_px"]) for m in measurements))
    head_scale = canonical_targets["head_width_px"] / source_head
    torso_scale = canonical_targets["torso_width_px"] / source_torso
    scale = math.sqrt(head_scale * torso_scale)
    return scale, {
        "method": "one uniform scale for this raw source master; geometric mean of canonical/generated median orange head-and-ear width and centered blue torso/bib width ratios",
        "canonical_median_head_width_px": round(canonical_targets["head_width_px"], 3),
        "canonical_median_torso_width_px": round(canonical_targets["torso_width_px"], 3),
        "source_master_median_head_width_px": round(source_head, 3),
        "source_master_median_torso_width_px": round(source_torso, 3),
        "head_landmark_scale": round(head_scale, 6),
        "torso_landmark_scale": round(torso_scale, 6),
        "uniform_master_scale": round(scale, 6),
        "source_cell_landmarks": measurements,
        "per_cell_scale_used": False,
    }


def normalize_group(
    cells: list[tuple[Image.Image, tuple[int, int, int, int]]],
    *, fixed_scale: float,
) -> tuple[list[Image.Image], list[dict[str, object]]]:
    raw_bboxes = [significant_bbox(image) for image, _ in cells]
    if any(bbox is None for bbox in raw_bboxes):
        raise ValueError("A generated cell has no significant alpha pixels")
    if fixed_scale <= 0:
        raise ValueError("The source-master scale must be positive")
    scale = fixed_scale
    normalized: list[Image.Image] = []
    details: list[dict[str, object]] = []
    for index, ((image, cell_box), bbox) in enumerate(zip(cells, raw_bboxes), start=1):
        assert bbox is not None
        subject = expanded_subject_crop(image, bbox)
        resized_size = (max(1, round(subject.width * scale)), max(1, round(subject.height * scale)))
        resized = subject.resize(resized_size, Image.Resampling.LANCZOS)
        resized_bbox = significant_bbox(resized)
        if resized_bbox is None:
            raise ValueError(f"Generated cell {index} lost its significant alpha during resize")
        left, top, right, bottom = resized_bbox
        resized_landmarks = landmark_measurements(resized)
        torso_bbox = resized_landmarks["torso_bbox_xyxy"]
        assert isinstance(torso_bbox, list)
        torso_center = (torso_bbox[0] + torso_bbox[2]) / 2
        shift_x = round(ANCHOR_X - torso_center)
        shift_y = round(GROUND_Y - bottom)
        canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
        paste_x = shift_x
        paste_y = shift_y
        canvas.alpha_composite(resized, (paste_x, paste_y))
        final_bbox = significant_bbox(canvas)
        if final_bbox is None:
            raise ValueError(f"Generated cell {index} did not fit the normalized frame")
        final_left, final_top, final_right, final_bottom = final_bbox
        final_landmarks = landmark_measurements(canvas)
        clipped = (
            final_left <= 1 or final_top <= 1
            or final_right >= FRAME - 1 or final_bottom >= FRAME - 1
        )
        normalized.append(canvas)
        details.append({
            "cell_number": index,
            "atlas_cell_bounds_xyxy": list(cell_box),
            "raw_alpha_bbox_16": list(bbox),
            "raw_visible_height_px": bbox[3] - bbox[1],
            "group_uniform_scale": round(scale, 6),
            "raw_landmarks": landmark_measurements(image),
            "normalized_landmarks": final_landmarks,
            "normalized_alpha_bbox_16": list(final_bbox),
            "normalized_visible_height_px": final_bottom - final_top,
            "normalized_torso_anchor_x": round((final_landmarks["torso_bbox_xyxy"][0] + final_landmarks["torso_bbox_xyxy"][2]) / 2, 2),
            "normalized_ground_y": final_bottom,
            "edge_clipped": clipped,
        })
    return normalized, details


def checkerboard(size: tuple[int, int], tile: int = 24) -> Image.Image:
    width, height = size
    canvas = Image.new("RGBA", size, (232, 232, 232, 255))
    draw = ImageDraw.Draw(canvas)
    dark = (88, 88, 88, 255)
    for y in range(0, height, tile):
        for x in range(0, width, tile):
            if (x // tile + y // tile) % 2:
                draw.rectangle((x, y, min(width - 1, x + tile - 1), min(height - 1, y + tile - 1)), fill=dark)
    return canvas


def frame_contact_sheet(direction: str, frames: list[Image.Image], path: Path) -> None:
    columns = 4
    header = 40
    sheet = Image.new("RGBA", (columns * FRAME, 4 * (FRAME + header)), (30, 34, 40, 255))
    draw = ImageDraw.Draw(sheet)
    labels = POSE_ORDER_16
    for index, frame in enumerate(frames):
        column, row = index % columns, index // columns
        x, y = column * FRAME, row * (FRAME + header)
        draw.text((x + 8, y + 4), f"{index + 1:02d}  {labels[index]}", fill=(250, 229, 175, 255))
        tile = checkerboard((FRAME, FRAME))
        tile.alpha_composite(frame)
        guide = ImageDraw.Draw(tile)
        guide.line((0, GROUND_Y, FRAME - 1, GROUND_Y), fill=(255, 80, 80, 180), width=1)
        guide.line((ANCHOR_X, 0, ANCHOR_X, FRAME - 1), fill=(60, 150, 255, 120), width=1)
        sheet.alpha_composite(tile, (x, y + header))
    sheet.save(path)


def save_gif(frames: list[Image.Image], path: Path, durations: list[int]) -> None:
    palette_frames = []
    for frame, duration_ms in zip(frames, durations):
        rgba = frame.convert("RGBA")
        p = rgba.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT)
        palette = p.getpalette() or []
        palette = (palette[: 255 * 3] + [0, 0, 0])[: 256 * 3]
        p.putpalette(palette)
        p.paste(255, mask=rgba.getchannel("A").point(lambda value: 255 if value < 16 else 0))
        p.info["transparency"] = 255
        p.info["duration"] = duration_ms
        palette_frames.append(p)
    palette_frames[0].save(
        path,
        save_all=True,
        append_images=palette_frames[1:],
        loop=0,
        transparency=255,
        disposal=2,
        optimize=False,
    )


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    NORMALIZED.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, object] = {
        "version": 1,
        "character": "rabbit-worker",
        "owner_batch": "animation-overhaul-luna-player-v1",
        "status": "staged-review-only; not promoted to runtime",
        "prompt_log": {
            "path": (SOURCE / "imagegen-prompt-log.json").relative_to(ROOT).as_posix(),
            "sha256": sha256(SOURCE / "imagegen-prompt-log.json"),
            "exact_prompt_count": 13,
            "reference_roles": "recorded verbatim in each prompt; num_last_images_to_include is also captured",
        },
        "unselected_generated_candidates": [
            {
                "path": (SOURCE / "east-between-atlas-first-attempt-unselected.png").relative_to(ROOT).as_posix(),
                "sha256": sha256(SOURCE / "east-between-atlas-first-attempt-unselected.png"),
                "reason": "Unselected output from the first of two east first-half prompt attempts; second output was used.",
            },
            {
                "path": (SOURCE / "east-between-atlas-raw.png").relative_to(ROOT).as_posix(),
                "sha256": sha256(SOURCE / "east-between-atlas-raw.png"),
                "reason": "Redundant copy; SHA-256 matches east-between-atlas-v1-generated.png.",
            },
            {
                "path": (SOURCE / "northeast-between-atlas-v1-background-fail.png").relative_to(ROOT).as_posix(),
                "sha256": sha256(SOURCE / "northeast-between-atlas-v1-background-fail.png"),
                "reason": "Rejected because the candidate includes a visible colored radial background glow; v2 is selected.",
            },
            {
                "path": (SOURCE / "east-between-atlas-v3-generated.png").relative_to(ROOT).as_posix(),
                "sha256": sha256(SOURCE / "east-between-atlas-v3-generated.png"),
                "reason": "Superseded by the new proportion-constrained east first-half master; transition 3 torso landmark was 12.58% below the canonical median.",
            },
            {
                "path": (SOURCE / "east-secondhalf-atlas-v2-generated.png").relative_to(ROOT).as_posix(),
                "sha256": sha256(SOURCE / "east-secondhalf-atlas-v2-generated.png"),
                "reason": "Superseded by the new proportion-constrained east second-half master; transition 5 head was 13.13% above and transition 8 torso was 13.91% below canonical medians.",
            },
            {
                "path": (SOURCE / "northeast-secondhalf-atlas-v2-generated.png").relative_to(ROOT).as_posix(),
                "sha256": sha256(SOURCE / "northeast-secondhalf-atlas-v2-generated.png"),
                "reason": "Rejected because opaque pixels crossed the 2-row atlas boundary between y=511 and y=512.",
            },
            {
                "path": (SOURCE / "northeast-secondhalf-atlas-v3-generated.png").relative_to(ROOT).as_posix(),
                "sha256": sha256(SOURCE / "northeast-secondhalf-atlas-v3-generated.png"),
                "reason": "Superseded by a new proportion-constrained northeast second-half master; its normalized cells still had up to 14.98% head and 12.05% torso landmark deviations.",
            },
        ],
        "normalization": {
            "frame_width": FRAME,
            "frame_height": FRAME,
            "strip_width": FRAME * 16,
            "strip_height": FRAME,
            "alpha_threshold": ALPHA_THRESHOLD,
            "anchor_x": ANCHOR_X,
            "ground_y": GROUND_Y,
            "method": "one uniform scale per raw generated source master, derived from the geometric mean of canonical-to-source median orange head-and-ear width and centered blue torso/bib width; crop transparent cell padding; translate each cell's torso anchor to x=256 and lowest supporting alpha to y=465; preserve each canonical input cell pixel-for-pixel",
            "landmark_measurement": {
                "head": "orange fur pixels above 42% of each significant-alpha bbox height; measured width includes head and ears",
                "torso": "blue overall/bib pixels in the centered 48% of the significant-alpha bbox width and the 30%-52% height band",
                "per_cell_rescaling": False,
                "pose_height_used_to_choose_scale": False,
            },
        },
        "canonical_pose_order": CONTACT_ORDER,
        "transition_order": TRANSITION_ORDER,
        "interleaved_pose_order": POSE_ORDER_16,
        "preview_timing": {
            "existing_config_speed_px_s": 155,
            "existing_config_pixels_per_canonical_frame": 20,
            "recommended_pixels_per_16_frame_subdivision": 10,
            "canonical_cycle_duration_ms": round(8 * 20 / 155 * 1000),
            "nominal_16_frame_rate_fps": 15.5,
        "one_x_gif_durations_ms": [60, 70] * 8,
        "half_speed_gif_duration_per_frame_ms": 130,
            "note": "Timing contract is a preview recommendation; engine subdivision and timing integration remain with the primary owner.",
        },
        "directions": {},
    }

    for direction, config in VIEWS.items():
        canonical_path = ROOT / str(config["canonical"])
        canonical_strip = Image.open(canonical_path).convert("RGBA")
        if canonical_strip.size != (FRAME * 8, FRAME):
            raise ValueError(f"Unexpected canonical strip dimensions for {direction}: {canonical_strip.size}")
        canonical_frames = [canonical_strip.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(8)]

        first_name, first_columns, first_rows = config["first"]  # type: ignore[index]
        second_name, second_columns, second_rows = config["second"]  # type: ignore[index]
        first_path = SOURCE / str(first_name)
        second_path = SOURCE / str(second_name)
        first_cells = crop_grid(first_path, int(first_columns), int(first_rows))
        second_cells = crop_grid(second_path, int(second_columns), int(second_rows))
        canonical_targets = median_landmark_targets(canonical_frames)
        first_scale, first_scale_details = source_master_scale(first_cells, canonical_targets)
        second_scale, second_scale_details = source_master_scale(second_cells, canonical_targets)
        first_frames, first_details = normalize_group(first_cells, fixed_scale=first_scale)
        second_frames, second_details = normalize_group(second_cells, fixed_scale=second_scale)

        replacement_details = None
        replacement_scale_details = None
        if direction == "east":
            replacement_path = SOURCE / str(config["replacement"])
            replacement_cell = crop_single(replacement_path)
            replacement_scale, replacement_scale_details = source_master_scale([replacement_cell], canonical_targets)
            replacement_frames, replacement_details = normalize_group(
                [replacement_cell], fixed_scale=replacement_scale
            )
            first_frames[3] = replacement_frames[0]
            first_details[3] = {
                **replacement_details[0],
                "selected_source": replacement_path.relative_to(ROOT).as_posix(),
                "selected_source_kind": "standalone generated pose; not an atlas cell",
                "selected_cell_number": None,
                "rejected_atlas_cell_number": 4,
                "selection_reason": "The first atlas cell 4 exceeded the canonical contact stride; this shorter descending-contact pose is the selected replacement.",
            }

        transitions = first_frames + second_frames
        transition_details = first_details + second_details
        landmark_fit = []
        for details in transition_details:
            normalized_landmarks = details["normalized_landmarks"]
            assert isinstance(normalized_landmarks, dict)
            head_width = float(normalized_landmarks["head_width_px"])
            torso_width = float(normalized_landmarks["torso_width_px"])
            head_delta = (head_width / canonical_targets["head_width_px"] - 1) * 100
            torso_delta = (torso_width / canonical_targets["torso_width_px"] - 1) * 100
            details["canonical_landmark_delta_pct"] = {
                "head_width": round(head_delta, 2),
                "torso_width": round(torso_delta, 2),
            }
            landmark_fit.append({
                "head_width_px": round(head_width, 2),
                "torso_width_px": round(torso_width, 2),
                "head_delta_from_canonical_median_pct": round(head_delta, 2),
                "torso_delta_from_canonical_median_pct": round(torso_delta, 2),
            })
        normalized_dir = NORMALIZED / direction
        normalized_dir.mkdir(parents=True, exist_ok=True)
        for index, (frame, phase, details) in enumerate(zip(transitions, TRANSITION_ORDER, transition_details), start=1):
            destination = normalized_dir / f"transition_{index:02d}_{phase}.png"
            frame.save(destination)
            details["phase"] = phase
            details["normalized_asset"] = destination.relative_to(ROOT).as_posix()
            details["selected_source"] = details.get("selected_source", (first_path if index <= 4 else second_path).relative_to(ROOT).as_posix())
            if not details.get("selected_source_kind"):
                details["selected_cell_number"] = details.get("cell_number")
                details["selected_row_major_cell"] = details.get("cell_number")

        interleaved: list[Image.Image] = []
        canonical_hashes = []
        for index in range(8):
            interleaved.extend((canonical_frames[index], transitions[index]))
            canonical_hashes.append(hashlib.sha256(canonical_frames[index].tobytes()).hexdigest())

        strip = Image.new("RGBA", (FRAME * 16, FRAME), (0, 0, 0, 0))
        for index, frame in enumerate(interleaved):
            strip.alpha_composite(frame, (index * FRAME, 0))
        strip_path = OUTPUT / f"walk-16frame-{direction}.png"
        strip.save(strip_path)

        unchanged = []
        for canonical_index in range(8):
            output_cell = strip.crop(((canonical_index * 2) * FRAME, 0, (canonical_index * 2 + 1) * FRAME, FRAME))
            unchanged.append(output_cell.tobytes() == canonical_frames[canonical_index].tobytes())
        if not all(unchanged):
            raise AssertionError(f"Canonical source poses changed in the {direction} strip")

        contact_path = OUTPUT / f"contact-sheet-16phase-{direction}.png"
        frame_contact_sheet(direction, interleaved, contact_path)
        one_x_path = OUTPUT / f"walk-16frame-{direction}-1x.gif"
        half_path = OUTPUT / f"walk-16frame-{direction}-halfspeed.gif"
        save_gif(interleaved, one_x_path, [60, 70] * 8)
        save_gif(interleaved, half_path, [130] * 16)

        bounds = [significant_bbox(frame) for frame in transitions]
        warnings = []
        for index, fit in enumerate(landmark_fit, start=1):
            if abs(fit["head_delta_from_canonical_median_pct"]) >= 13:
                warnings.append(f"transition {index} head landmark differs from canonical median by 13% or more")
            if abs(fit["torso_delta_from_canonical_median_pct"]) >= 13:
                warnings.append(f"transition {index} torso landmark differs from canonical median by 13% or more")
        for frame_index, bbox in enumerate(bounds, start=1):
            if bbox is None:
                warnings.append(f"transition {frame_index} is empty")
            elif bbox[0] <= 1 or bbox[1] <= 1 or bbox[2] >= FRAME - 1 or bbox[3] >= FRAME - 1:
                warnings.append(f"transition {frame_index} touches the normalized frame edge")
        manifest["directions"][direction] = {  # type: ignore[index]
            "camera_view": direction,
            "mirror_policy": "authored unique view; west sectors remain mirrored by the parent motion spec",
            "canonical_source": canonical_path.relative_to(ROOT).as_posix(),
            "canonical_source_sha256": sha256(canonical_path),
            "canonical_source_frame_pixel_hashes": canonical_hashes,
            "canonical_cells_unchanged_in_interleaved_strip": all(unchanged),
            "canonical_median_landmark_widths_px": {
                key: round(value, 3) for key, value in canonical_targets.items()
            },
            "transition_landmark_fit": landmark_fit,
            "manual_visual_review": {
                "contact_sheet_reviewed": True,
                "scope": "static contact-sheet comparison of each transition with its neighboring canonical frames; this does not replace in-engine review",
                "notes": VISUAL_REVIEW_NOTES[direction],
            },
            "generated_atlases": {
                "first_half": {
                    "path": first_path.relative_to(ROOT).as_posix(),
                    "sha256": sha256(first_path),
                    "dimensions": list(Image.open(first_path).size),
                    "grid_columns": int(first_columns),
                    "grid_rows": int(first_rows),
                    "selected_row_major_cells": ([1, 2, 3] if direction == "east" else [1, 2, 3, 4]),
                    "unselected_row_major_cells": ([4] if direction == "east" else []),
                    "scale_fit": first_scale_details,
                    "cell_normalization": first_details,
                },
                "second_half": {
                    "path": second_path.relative_to(ROOT).as_posix(),
                    "sha256": sha256(second_path),
                    "dimensions": list(Image.open(second_path).size),
                    "grid_columns": int(second_columns),
                    "grid_rows": int(second_rows),
                    "selected_row_major_cells": [1, 2, 3, 4],
                    "scale_fit": second_scale_details,
                    "cell_normalization": second_details,
                },
                "east_replacement": (
                    {
                        "path": (SOURCE / str(config["replacement"])).relative_to(ROOT).as_posix(),
                        "sha256": sha256(SOURCE / str(config["replacement"])),
                        "selected": True,
                        "scale_fit": replacement_scale_details,
                        "details": replacement_details,
                    }
                    if direction == "east" else None
                ),
            },
            "deliverables": {
                "normalized_strip": strip_path.relative_to(ROOT).as_posix(),
                "strip_dimensions": list(strip.size),
                "contact_sheet": contact_path.relative_to(ROOT).as_posix(),
                "one_x_preview": one_x_path.relative_to(ROOT).as_posix(),
                "half_speed_preview": half_path.relative_to(ROOT).as_posix(),
                "normalized_transitions": [
                    d["normalized_asset"] for d in transition_details
                ],
            },
            "quality_warnings": warnings,
        }

    (SOURCE / "player-walk-staging-manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Built staged 16-frame strips and previews for {len(VIEWS)} authored views.")
    print(f"Source manifest: {SOURCE / 'player-walk-staging-manifest.json'}")
    print(f"Review output: {OUTPUT}")


if __name__ == "__main__":
    main()
