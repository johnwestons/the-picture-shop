"""Reproducibly split the v3 raw atlas on transparent gaps and rigid-register it.

This source-owned builder has no dependency on output review helpers. It preserves
every nonzero-alpha source pixel in exactly one crop, uses one recorded scale for
all frames, and applies translations only for the torso/ground anchors.
"""
from __future__ import annotations

import hashlib
import json
import statistics
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
RAW = HERE / "field-mouse-technician-west-canonical-8phase-v3-master-raw.png"
GENERATION_RECORD = HERE.parent / "canonical-8phase-v3-proportion-consistent" / "generation-record.md"
STRIP = HERE / "field-mouse-technician-west-canonical-8phase-v4-gap-registered-4x2.png"
RUNTIME_STRIP = HERE / "field-mouse-technician-west-canonical-8phase-v4-gap-registered-8x1.png"
MANIFEST = HERE / "registration-manifest.json"

EXPECTED_RAW_SHA256 = "5465fe188fea59a8d9484f27b738a9078dcb77eb0b0724b96ce53a41dbce5ef5"
WIDTH, HEIGHT = 1774, 887
CELL = 256
ALPHA_THRESHOLD = 16
AXIS_ALPHA_THRESHOLD = 128
SCALE = 27 / 56
TARGET_HEAD_WIDTH_PX = 94.5
TARGET_AXIS_X_PX = 128.0
TARGET_GROUND_Y_PX = 229.0
FOREGROUND_RENDER_PADDING_PX = 8
Y_CUT = 460
X_CUTS_BY_ROW = [
    [0, 479, 932, 1385, WIDTH],
    [0, 502, 932, 1385, WIDTH],
]
PHASE_ROLES = [
    "K1 near/pocketed lead contact, far/plain leg trails",
    "K2 near/pocketed weight-down, far/plain heel releases",
    "K3 far/plain compact pass, near/pocketed supports",
    "K4 far/plain knee-up forward, near/pocketed supports",
    "K5 far/plain lead contact, near/pocketed leg trails",
    "K6 far/plain weight-down, near/pocketed heel releases",
    "K7 near/pocketed compact pass, far/plain supports",
    "K8 near/pocketed knee-up forward, far/plain supports",
]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def bbox_alpha(frame: Image.Image, threshold: int = ALPHA_THRESHOLD) -> tuple[int, int, int, int]:
    alpha = np.asarray(frame.getchannel("A"))
    ys, xs = np.where(alpha >= threshold)
    if len(xs) == 0:
        raise ValueError("Empty alpha frame")
    return int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)


def bbox_mask(mask: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.where(mask)
    if len(xs) == 0:
        raise ValueError("No pixels in mask")
    return int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)


def true_runs(values: np.ndarray) -> list[tuple[int, int]]:
    runs = []
    start = None
    for index, value in enumerate(values):
        if value and start is None:
            start = index
        if (not value or index == len(values) - 1) and start is not None:
            end = index if not value else index + 1
            runs.append((int(start), int(end)))
            start = None
    return runs


def nearest_run(cut: int, runs: list[tuple[int, int]], *, require_contain: bool = False) -> tuple[int, int]:
    for start, end in runs:
        if start <= cut < end:
            return start, end
    if require_contain:
        raise ValueError(f"Cut {cut} is not inside a clear run: {runs}")
    return min(runs, key=lambda run: min(abs(cut - run[0]), abs(cut - run[1])))


def measured_axis(frame: Image.Image, box: tuple[int, int, int, int]) -> float:
    left, top, right, bottom = box
    alpha = np.asarray(frame.getchannel("A"))
    height = bottom - top
    y0 = top + round(height * 0.32)
    y1 = top + round(height * 0.50)
    centers = []
    for y in range(y0, y1):
        xs = np.flatnonzero(alpha[y, left:right] >= AXIS_ALPHA_THRESHOLD)
        if len(xs):
            centers.append(left + (int(xs.min()) + int(xs.max()) + 1) / 2)
    if not centers:
        raise ValueError("Could not measure torso axis")
    return float(statistics.median(centers))


def broad_head_box(frame: Image.Image, box: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    left, top, right, bottom = box
    height = bottom - top
    head_y1 = min(frame.height, top + round(height * 0.43))
    alpha = np.asarray(frame.getchannel("A"))
    return bbox_mask(alpha[top:head_y1, :] >= ALPHA_THRESHOLD)


def column_empty_runs(alpha: np.ndarray, y0: int, y1: int, threshold: int) -> list[tuple[int, int]]:
    occupied = (alpha[y0:y1, :] >= threshold).any(axis=0)
    return true_runs(~occupied)


def row_empty_runs(alpha: np.ndarray, threshold: int) -> list[tuple[int, int]]:
    occupied = (alpha >= threshold).any(axis=1)
    return true_runs(~occupied)


def counts(frame: Image.Image) -> dict[str, int]:
    a = np.asarray(frame.getchannel("A"))
    return {
        "alpha_nonzero_pixels": int((a > 0).sum()),
        "alpha_ge16_pixels": int((a >= ALPHA_THRESHOLD).sum()),
        "alpha_ge128_pixels": int((a >= AXIS_ALPHA_THRESHOLD).sum()),
    }


def edge_counts(frame: Image.Image) -> dict[str, dict[str, int]]:
    a = np.asarray(frame.getchannel("A"))
    return {
        edge: {
            "alpha_nonzero": int((row_or_col > 0).sum()),
            "alpha_ge16": int((row_or_col >= ALPHA_THRESHOLD).sum()),
        }
        for edge, row_or_col in {
            "top": a[0, :],
            "bottom": a[-1, :],
            "left": a[:, 0],
            "right": a[:, -1],
        }.items()
    }


def main() -> None:
    if sha256(RAW) != EXPECTED_RAW_SHA256:
        raise ValueError("Raw master hash changed; refusing to register a different image")
    master = Image.open(RAW).convert("RGBA")
    if master.size != (WIDTH, HEIGHT):
        raise ValueError(f"Expected {(WIDTH, HEIGHT)} raw master, found {master.size}")
    alpha = np.asarray(master.getchannel("A"))

    y_gap_ge16 = nearest_run(Y_CUT, row_empty_runs(alpha, ALPHA_THRESHOLD), require_contain=True)
    y_gap_zero = nearest_run(Y_CUT, row_empty_runs(alpha, 1))

    original_nonzero = int((alpha > 0).sum())
    original_ge16 = int((alpha >= ALPHA_THRESHOLD).sum())
    assignment = np.zeros((HEIGHT, WIDTH), dtype=np.uint8)
    cells = []
    cell_records = []
    gap_records = []
    phase = 0
    y_bands = [(0, Y_CUT), (Y_CUT, HEIGHT)]

    for row, (y0, y1) in enumerate(y_bands):
        cuts = X_CUTS_BY_ROW[row]
        empty_ge16 = column_empty_runs(alpha, y0, y1, ALPHA_THRESHOLD)
        empty_zero = column_empty_runs(alpha, y0, y1, 1)
        for cut_index, cut in enumerate(cuts[1:-1], start=1):
            gap16 = nearest_run(cut, empty_ge16, require_contain=True)
            gap0 = nearest_run(cut, empty_zero)
            gap_records.append({
                "row": row,
                "cut_x": cut,
                "left_column_x": cut - 1,
                "right_column_x": cut,
                "alpha_ge16_empty_run_xy": list(gap16),
                "alpha_zero_empty_run_xy": list(gap0),
                "weak_alpha_pixels_on_cut_column": int((alpha[y0:y1, cut] > 0).sum()),
                "weak_alpha_pixels_on_adjacent_columns": [
                    int((alpha[y0:y1, cut - 1] > 0).sum()),
                    int((alpha[y0:y1, cut] > 0).sum()),
                ],
                "alpha_ge16_pixels_on_adjacent_columns": [
                    int((alpha[y0:y1, cut - 1] >= ALPHA_THRESHOLD).sum()),
                    int((alpha[y0:y1, cut] >= ALPHA_THRESHOLD).sum()),
                ],
            })

        high_runs = true_runs((alpha[y0:y1, :] >= ALPHA_THRESHOLD).any(axis=0))
        if len(high_runs) != 4:
            raise ValueError(f"Expected four alpha>=16 figure runs in row {row}, found {high_runs}")
        for col in range(4):
            phase += 1
            x0, x1 = cuts[col], cuts[col + 1]
            frame = master.crop((x0, y0, x1, y1))
            assignment[y0:y1, x0:x1] += 1
            owned_runs = [run for run in high_runs if x0 <= run[0] and run[1] <= x1]
            if len(owned_runs) != 1:
                raise ValueError(f"Phase K{phase} crop does not own exactly one strong-foreground figure: {owned_runs}")

            raw_bbox = bbox_alpha(frame)
            head_bbox = broad_head_box(frame, raw_bbox)
            axis = measured_axis(frame, raw_bbox)
            ground = raw_bbox[3] - 1
            render_bounds = (
                max(0, raw_bbox[0] - FOREGROUND_RENDER_PADDING_PX),
                max(0, raw_bbox[1] - FOREGROUND_RENDER_PADDING_PX),
                min(frame.width, raw_bbox[2] + FOREGROUND_RENDER_PADDING_PX),
                min(frame.height, raw_bbox[3] + FOREGROUND_RENDER_PADDING_PX),
            )
            render_crop = frame.crop(render_bounds)
            render_alpha = np.asarray(render_crop.getchannel("A"))
            source_alpha = np.asarray(frame.getchannel("A"))
            omitted_weak = source_alpha.copy()
            omitted_weak[
                render_bounds[1]:render_bounds[3], render_bounds[0]:render_bounds[2]
            ] = 0
            omitted_ys, omitted_xs = np.where(omitted_weak > 0)
            omitted_strong_count = int((omitted_weak >= ALPHA_THRESHOLD).sum())
            if omitted_strong_count:
                raise ValueError(f"Phase K{phase} render crop omitted {omitted_strong_count} alpha>=16 source pixels")
            scaled_size = (max(1, round(render_crop.width * SCALE)), max(1, round(render_crop.height * SCALE)))
            resized = render_crop.resize(scaled_size, Image.Resampling.LANCZOS)
            local_axis = axis - render_bounds[0]
            local_ground = ground - render_bounds[1]
            paste_x = round(TARGET_AXIS_X_PX - local_axis * SCALE)
            paste_y = round(TARGET_GROUND_Y_PX - local_ground * SCALE)
            resized_alpha_box = resized.getchannel("A").getbbox()
            if resized_alpha_box is None:
                raise ValueError(f"Scaled phase K{phase} is empty")
            translated_nonzero = (
                resized_alpha_box[0] + paste_x,
                resized_alpha_box[1] + paste_y,
                resized_alpha_box[2] + paste_x,
                resized_alpha_box[3] + paste_y,
            )
            if translated_nonzero[0] < 0 or translated_nonzero[1] < 0 or translated_nonzero[2] > CELL or translated_nonzero[3] > CELL:
                raise ValueError(f"Phase K{phase} would clip alpha at registered cell bounds: {translated_nonzero}")
            output_cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
            output_cell.alpha_composite(resized, (paste_x, paste_y))
            output_bbox = bbox_alpha(output_cell)
            output_alpha = np.asarray(output_cell.getchannel("A"))
            edge_ge16 = {
                "top": int((output_alpha[0, :] >= ALPHA_THRESHOLD).sum()),
                "bottom": int((output_alpha[-1, :] >= ALPHA_THRESHOLD).sum()),
                "left": int((output_alpha[:, 0] >= ALPHA_THRESHOLD).sum()),
                "right": int((output_alpha[:, -1] >= ALPHA_THRESHOLD).sum()),
            }
            edge_nonzero = {
                "top": int((output_alpha[0, :] > 0).sum()),
                "bottom": int((output_alpha[-1, :] > 0).sum()),
                "left": int((output_alpha[:, 0] > 0).sum()),
                "right": int((output_alpha[:, -1] > 0).sum()),
            }
            if any(edge_ge16.values()) or any(edge_nonzero.values()):
                raise ValueError(f"Phase K{phase} registered output touches a canvas edge: ge16={edge_ge16}, nonzero={edge_nonzero}")

            cells.append(output_cell)
            cell_records.append({
                "phase": phase,
                "role": PHASE_ROLES[phase - 1],
                "raw_crop_bounds_xyxy_exclusive": [x0, y0, x1, y1],
                "raw_crop_dimensions_px": [frame.width, frame.height],
                "raw_crop_edge_alpha_counts": edge_counts(frame),
                "raw_alpha_bbox_ge16_xyxy_exclusive": list(raw_bbox),
                "raw_alpha_bbox_global_xyxy_exclusive": [raw_bbox[0] + x0, raw_bbox[1] + y0, raw_bbox[2] + x0, raw_bbox[3] + y0],
                "raw_broad_head_bbox_ge16_xyxy_exclusive": list(head_bbox),
                "raw_broad_head_bbox_global_xyxy_exclusive": [head_bbox[0] + x0, head_bbox[1] + y0, head_bbox[2] + x0, head_bbox[3] + y0],
                "raw_head_width_px": head_bbox[2] - head_bbox[0],
                "render_content_bounds_in_source_crop_xyxy_exclusive": list(render_bounds),
                "render_content_bounds_global_xyxy_exclusive": [render_bounds[0] + x0, render_bounds[1] + y0, render_bounds[2] + x0, render_bounds[3] + y0],
                "render_foreground_threshold_alpha": ALPHA_THRESHOLD,
                "render_foreground_padding_px": FOREGROUND_RENDER_PADDING_PX,
                "source_alpha_nonzero_residue_outside_render_bounds": {
                    "count": int(len(omitted_xs)),
                    "bbox_in_source_crop_xyxy_exclusive": None if len(omitted_xs) == 0 else [int(omitted_xs.min()), int(omitted_ys.min()), int(omitted_xs.max() + 1), int(omitted_ys.max() + 1)],
                    "classification": "alpha>0 pixels outside alpha>=16 figure bbox plus 3px fringe; source partition retains them; not rendered as detached faint export residue; inspect raw crop if deciding they belong to the figure",
                    "alpha_ge16_pixels_outside_render_bounds": omitted_strong_count,
                },
                "uniform_scale": SCALE,
                "scaled_crop_dimensions_px": list(scaled_size),
                "raw_torso_axis_x_px": axis,
                "raw_ground_y_px": ground,
                "paste_offset_xy_px": [paste_x, paste_y],
                "registered_alpha_bbox_ge16_xyxy_exclusive": list(output_bbox),
                "registered_alpha_counts": counts(output_cell),
                "registered_edge_alpha_ge16_counts": edge_ge16,
                "registered_edge_alpha_nonzero_counts": edge_nonzero,
                "owned_alpha_ge16_x_run_global": list(owned_runs[0]),
            })

    if not (assignment == 1).all():
        missing = int((assignment == 0).sum())
        overlap = int((assignment > 1).sum())
        raise ValueError(f"Source crop partition is not exact: {missing=} {overlap=}")
    covered_nonzero = int(((assignment == 1) & (alpha > 0)).sum())
    covered_ge16 = int(((assignment == 1) & (alpha >= ALPHA_THRESHOLD)).sum())
    if covered_nonzero != original_nonzero or covered_ge16 != original_ge16:
        raise ValueError("Not all source alpha pixels were assigned exactly once")

    strip = Image.new("RGBA", (CELL * 4, CELL * 2), (0, 0, 0, 0))
    runtime_strip = Image.new("RGBA", (CELL * 8, CELL), (0, 0, 0, 0))
    for index, cell in enumerate(cells):
        strip.alpha_composite(cell, (index % 4 * CELL, index // 4 * CELL))
        runtime_strip.alpha_composite(cell, (index * CELL, 0))
    strip.save(STRIP, optimize=True)
    runtime_strip.save(RUNTIME_STRIP, optimize=True)

    manifest = {
        "status": "v4 review-only rigid crop registration; no source repaint or runtime promotion",
        "source_provenance": {
            "exact_prompt_and_generation_record": {
                "path": GENERATION_RECORD.relative_to(ROOT).as_posix(),
                "sha256": sha256(GENERATION_RECORD),
                "note": "Contains the verbatim one-generation prompt and reference roles/hashes. V4 changes only deterministic cropping/registration; no new image generation was performed.",
            },
            "imagegen_raw_result_original_path": r"C:\Users\johnw\.codex\generated_images\01a17bff-cf8e-7f63-8e8d-221432232467\exec-a9a38e7a-ccc3-4aa2-9fa3-25267e5f7aa9.png",
            "reference_hashes": {
                "primary_k5_proportion_identity_reference": {
                    "path": "assets/source/animation-overhaul-luna-worker-actions-v1/mouse-west/contact5-proportion-correction-v1/field-mouse-worker-k5-proportion-v1-imagegen.png",
                    "sha256": "3cb33fe62981454b7eb8e13b91bfa1c69d61f1a55db30255f0b0fd7e5e67404",
                },
                "approved_idle_west_identity_reference": {
                    "path": "assets/generated/technician-motion-v2/field-mouse-technician/idle_west.png",
                    "sha256": "886efc1ad1bf57bedb3a1b98927b82135281b9d53599f080b592e37a979a0f66",
                },
                "lower_body_phase_guide_only": {
                    "path": "output/animation-overhaul/luna-worker-actions/mouse-west/field-mouse-technician-west-canonical-8phase-v2-torso-axis-registered-4x2.png",
                    "sha256": "dabb127c54e06133449edbba7901fcafc14fe861cc619ec93a1b1ba77b063e16",
                },
            },
        },
        "raw_master": {
            "path": RAW.name,
            "sha256": sha256(RAW),
            "dimensions_px": [WIDTH, HEIGHT],
            "mode": master.mode,
            "expected_generation_source_sha256": EXPECTED_RAW_SHA256,
            "source_alpha_counts": {"nonzero": original_nonzero, "ge16": original_ge16},
        },
        "source_generation_reference": {
            "relative_path": "../canonical-8phase-v3-proportion-consistent/field-mouse-technician-west-canonical-8phase-v3-imagegen.png",
            "sha256": EXPECTED_RAW_SHA256,
        },
        "frozen_selection": {
            "row_y_bounds_half_open": y_bands,
            "row_cutline_y": Y_CUT,
            "row_cutline_alpha_ge16_empty_run": list(y_gap_ge16),
            "row_cutline_alpha_zero_empty_run": list(y_gap_zero),
            "column_cutlines_by_row": [row[1:-1] for row in X_CUTS_BY_ROW],
            "column_cutline_gaps": gap_records,
            "crop_bounds_half_open_xyxy": [item["raw_crop_bounds_xyxy_exclusive"] for item in cell_records],
            "frame_order": PHASE_ROLES,
            "source_pixels_partition": {
                "assignment_count_min": int(assignment.min()),
                "assignment_count_max": int(assignment.max()),
                "alpha_nonzero_assigned_once": covered_nonzero,
                "alpha_nonzero_source_total": original_nonzero,
                "alpha_ge16_assigned_once": covered_ge16,
                "alpha_ge16_source_total": original_ge16,
                "all_source_pixels_assigned_exactly_once": bool((assignment == 1).all() and covered_nonzero == original_nonzero),
                "strong_foreground_figure_runs_per_row": [4, 4],
                "one_alpha_ge16_figure_run_per_crop": True,
            },
            "rendered_foreground_proof": {
                "alpha_ge16_pixels_outside_render_bbox_plus_fringe": 0,
                "alpha_ge16_source_pixels_preserved_in_render_crop": True,
                "weak_alpha_outside_render_crop": "tracked per frame and shown in output review; source partition retains all such pixels, but the detached low-alpha flecks are excluded from final rendered cells",
            },
        },
        "registration": {
            "global_scale": SCALE,
            "global_scale_fraction": "27/56",
            "scale_origin": "same frozen whole-master scale as v3; no per-cell or per-part scale fit",
            "target_broad_head_width_px_reference": TARGET_HEAD_WIDTH_PX,
            "target_torso_axis_x_px": TARGET_AXIS_X_PX,
            "target_ground_y_px": TARGET_GROUND_Y_PX,
            "body_reference_height_px": 192,
            "cell_canvas_px": [CELL, CELL],
            "runtime_strip_dimensions_px": [CELL * 8, CELL],
            "paste_offsets_by_phase_xy": [item["paste_offset_xy_px"] for item in cell_records],
            "output_alpha_clipping": False,
            "output_all_edge_alpha_counts_zero": all(not any(item["registered_edge_alpha_nonzero_counts"].values()) for item in cell_records),
            "source_crop_edges_alpha_ge16_counts_zero": all(not any(edge["alpha_ge16"] for edge in item["raw_crop_edge_alpha_counts"].values()) for item in cell_records),
        },
        "frames": cell_records,
        "registered_strip": {
            "path": STRIP.name,
            "sha256": sha256(STRIP),
            "dimensions_px": list(strip.size),
            "mode": strip.mode,
        },
        "runtime_strip": {
            "path": RUNTIME_STRIP.name,
            "sha256": sha256(RUNTIME_STRIP),
            "dimensions_px": list(runtime_strip.size),
            "mode": runtime_strip.mode,
            "frame_order": PHASE_ROLES,
        },
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (HERE / "selection.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "raw_sha256": manifest["raw_master"]["sha256"],
        "strip_sha256": manifest["registered_strip"]["sha256"],
        "global_scale": SCALE,
        "y_cut": Y_CUT,
        "x_cutlines_by_row": manifest["frozen_selection"]["column_cutlines_by_row"],
        "all_alpha_assigned_once": manifest["frozen_selection"]["source_pixels_partition"]["all_source_pixels_assigned_exactly_once"],
        "crop_bounds": manifest["frozen_selection"]["crop_bounds_half_open_xyxy"],
        "paste_offsets": manifest["registration"]["paste_offsets_by_phase_xy"],
    }, indent=2))


if __name__ == "__main__":
    main()
