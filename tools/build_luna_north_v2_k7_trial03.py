from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
from statistics import median

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BASE_BUILDER = ROOT / "tools/build_luna_north_consistent_v2.py"
SPEC = importlib.util.spec_from_file_location("north_v2_base", BASE_BUILDER)
base = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(base)

SOURCE = base.SOURCE
OUT = base.OUT
RAW = SOURCE / "north-consistent-v2-generated-raw.png"
TRIAL_RAW = SOURCE / "north-v2-phase7-replacement-trial03-generated-raw.png"
PROMPT = SOURCE / "north-v2-phase7-replacement-trial03-exact-prompt.txt"
K5_RAW = base.K5_RAW
K5_NORMALIZED = base.K5_NORMALIZED
V2_GUIDE = SOURCE / "north-v2-phase7-clean-compact-pass-legs-only-pose-guide.png"
FRAME = base.FRAME
GROUND_Y = base.GROUND_Y
HEAD_CENTER_X = base.HEAD_CENTER_X
SCALE = base.K5_MASTER_SCALE
TRIAL_RAW_SHA256 = "8553721d06cbf4a70d20654c2d146c90da6dd0a1f52bf86d48fc6e17cb247b56"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def register_trial(raw: Image.Image):
    rgba = raw.convert("RGBA")
    box = base.bbox_alpha(rgba)
    if box is None:
        raise SystemExit("Trial 03 has no visible pixels")
    px = rgba.load()
    orange_xs = []
    head_end = min(rgba.height, box[1] + round((box[3] - box[1]) * 0.46))
    for y in range(max(0, box[1]), head_end):
        for x in range(box[0], box[2]):
            if base.orange(*px[x, y]):
                orange_xs.append(x)
    if not orange_xs:
        raise SystemExit("No orange head anchor in trial 03")
    head_center = sum(orange_xs) / len(orange_xs)
    scaled_box = [round(v * SCALE) for v in box]
    dx = round(HEAD_CENTER_X - head_center * SCALE)
    dy = GROUND_Y - (scaled_box[3] - 1)
    return base.padded_cell(rgba, SCALE, dx, dy), box, head_center, [dx, dy]


def build():
    if sha(TRIAL_RAW) != TRIAL_RAW_SHA256:
        raise SystemExit("Pinned trial 03 raw hash mismatch")
    raw_sheet = Image.open(RAW).convert("RGBA")
    raw_cells = [
        raw_sheet.crop((col * 384, row * 512, (col + 1) * 384, (row + 1) * 512))
        for row in range(2) for col in range(4)
    ]
    boxes = [base.bbox_alpha(cell) for cell in raw_cells]
    heights = [box[3] - box[1] for box in boxes]
    base_scale = 410.0 / __import__("statistics").median(heights)
    dx = round(HEAD_CENTER_X - (384 / 2) * base_scale)
    dy = GROUND_Y - round(__import__("statistics").median([box[3] - 1 for box in boxes]) * base_scale)
    frames = [base.padded_cell(cell, base_scale, dx, dy) for cell in raw_cells]

    trial, raw_box, head_center, trial_translation = register_trial(Image.open(TRIAL_RAW))
    proposal_frames = list(frames)
    proposal_frames[6] = trial

    native = Image.new("RGBA", (FRAME * 8, FRAME), (0, 0, 0, 0))
    contact = Image.new("RGBA", (FRAME * 4, FRAME * 2), (0, 0, 0, 0))
    proposal_contact = Image.new("RGBA", (FRAME * 4, FRAME * 2), (0, 0, 0, 0))
    for i, frame in enumerate(proposal_frames):
        native.alpha_composite(frame, (i * FRAME, 0))
        row, col = divmod(i, 4)
        contact.alpha_composite(frame, (col * FRAME, row * FRAME))
    proposal = native.copy()
    for i, frame in enumerate(proposal_frames):
        row, col = divmod(i, 4)
        proposal_contact.alpha_composite(frame, (col * FRAME, row * FRAME))

    OUT.mkdir(parents=True, exist_ok=True)
    paths = {
        "proposal": OUT / "north-v2-phase7-trial03-proposal.png",
        "contact": OUT / "north-v2-phase7-trial03-contact-white.png",
        "neighbors": OUT / "north-v2-phase7-trial03-neighbors-k5-white.png",
        "gif": OUT / "north-v2-phase7-trial03-64worldpx-timed.gif",
    }
    proposal.save(paths["proposal"])
    base.white_composite(proposal_contact).save(paths["contact"])
    base.make_gif(proposal_frames, paths["gif"], duration_ms=130)

    k5sheet = Image.open(K5_NORMALIZED).convert("RGBA")
    k5cell = k5sheet.crop((FRAME * 4, 0, FRAME * 5, FRAME))
    near = Image.new("RGBA", (FRAME * 5, FRAME), (255, 255, 255, 255))
    for i, frame in enumerate([frames[5], frames[6], trial, frames[7], k5cell]):
        near.alpha_composite(frame, (i * FRAME, 0))
    near.convert("RGB").save(paths["neighbors"])

    before_after_diff = []
    for i, (before, after) in enumerate(zip(frames, proposal_frames), start=1):
        difference = ImageChops_difference_count(before, after)
        before_after_diff.append({"phase": i, "changed_pixel_count": difference})

    base_metrics = [base.metrics(frame) for frame in frames]
    trial_metrics = base.metrics(trial)
    k5_metrics = base.metrics(k5cell)
    trial_sole = base.dark_roi_measure(trial, (178, 390, 258, 466))
    base_k7_sole = base.dark_roi_measure(frames[6], (178, 390, 258, 466))
    phase3_sole = base.dark_roi_measure(frames[2], (270, 390, 350, 466))

    raw_trial = Image.open(TRIAL_RAW).convert("RGBA")
    raw_alpha = raw_trial.getchannel("A")
    gif = Image.open(paths["gif"])
    gif_durations = []
    for i in range(gif.n_frames):
        gif.seek(i)
        gif_durations.append(gif.info.get("duration"))

    prior_audit_path = OUT / "north-v2-candidate-and-phase7-replacement-audit.json"
    prior_audit = json.loads(prior_audit_path.read_text(encoding="utf-8"))
    directions = prior_audit["installed_cross_view_comparison"]["directions"]
    installed_direction_summary = []
    for item in directions:
        installed_direction_summary.append({
            "direction": item["direction"],
            "walk_path": item["walk_path"],
            "walk_sha256": item["walk_sha256"],
            "walk_phase1_visible_height_px": item["walk_frames"][0]["visible_height_px"],
            "walk_phase1_dark_ink_share_percent": item["walk_frames"][0]["dark_ink_pixel_share_of_visible_alpha64_percent"],
            "idle_path": item["idle_path"],
            "idle_sha256": item["idle_sha256"],
            "idle_visible_heights_px": [frame["visible_height_px"] for frame in item["idle_frames"]],
        })
    v2_head_widths = [m["orange_head_band_y170_249_max_row_width_px"]["width"] for m in base_metrics]
    v2_torso_widths = [m["blue_overall_band_y245_334_median_row_width_px"] for m in base_metrics]
    v2_ink_shares = [m["dark_ink_pixel_share_of_visible_alpha64_percent"] for m in base_metrics]
    installed_walk1_ink = [item["walk_phase1_dark_ink_share_percent"] for item in installed_direction_summary]

    hash_paths = [RAW, TRIAL_RAW, PROMPT, K5_RAW, V2_GUIDE,
                  SOURCE / "north-v2-phase7-clean-compact-pass-legs-only-pose-guide.sha256"]
    # The adjacent root-provided guide hash is computed from the image itself; the
    # optional sidecar is included only when present.
    hash_paths = [p for p in hash_paths if p.exists()]
    outputs = [*paths.values()]
    audit = {
        "title": "North phase-7 replacement trial 03; staged, not accepted",
        "generation": {
            "imagegen_generation_id": "exec-1c8b3cbb-2f2e-4e1d-89a6-b700185807f4",
            "cached_output": r"C:\Users\johnw\.codex\generated_images\01a17bec-a216-72b3-ac73-5e56d3da1c90\exec-1c8b3cbb-2f2e-4e1d-89a6-b700185807f4.png",
            "transparent_background_requested": True,
            "exact_prompt_path": PROMPT.relative_to(ROOT).as_posix(),
            "exact_prompt": PROMPT.read_text(encoding="utf-8"),
        },
        "source_hashes_sha256": {p.relative_to(ROOT).as_posix(): sha(p) for p in hash_paths},
        "reference_roles": {
            "primary_identity_style_reference": K5_RAW.relative_to(ROOT).as_posix(),
            "primary_role": "sole full-character identity, head/torso proportion, outline, palette, wardrobe, anatomy and camera reference",
            "pose_only_reference": V2_GUIDE.relative_to(ROOT).as_posix(),
            "pose_role": "clean lower-body compact-pass leg ownership/pose cue only; no upper body, identity, scale, or style copied",
            "cycle_base": RAW.relative_to(ROOT).as_posix(),
            "cycle_base_role": "all eight base poses and style context; only phase 7 cell replaced in proposal",
        },
        "raw_image": {
            "dimensions": list(raw_trial.size),
            "mode": Image.open(TRIAL_RAW).mode,
            "alpha_extrema": list(raw_alpha.getextrema()),
            "alpha_bbox_gt16": list(base.bbox_alpha(raw_trial)),
            "transparent_corner_alpha": [raw_trial.getpixel(pt)[3] for pt in [(0, 0), (1253, 0), (0, 1253), (1253, 1253)]],
        },
        "registration": {
            "scale": SCALE,
            "scale_source": "accepted K5 trial06 raw-master calibration, held fixed",
            "source_alpha_bbox_gt16": list(raw_box),
            "orange_head_anchor_centroid_x": head_center,
            "translation_xy_px": trial_translation,
            "groundline_y": GROUND_Y,
            "method": "one uniform whole-source scale, horizontal head-anchor translation and groundline translation only; no per-cell fitting or deformation",
        },
        "phase7_trial03_metrics_at_shared_scale": trial_metrics,
        "base_v2_metrics_by_phase": base_metrics,
        "accepted_k5_normalized_metrics": k5_metrics,
        "sole_proxy": {
            "method": "rough fixed ROI dark-pixel proxy; not exact semantic boot segmentation",
            "base_v2_phase7": base_k7_sole,
            "trial03_phase7": trial_sole,
            "phase3_compact_pass_reference": phase3_sole,
        },
        "phase_owner_and_visual_finding": {
            "intended_phase7": "left/anatomical-left free compact passing foot under pelvis, toe down and sole hidden; right/viewer-right support planted",
            "visual_review": "The raw trial still raises the viewer-left boot behind the body and presents a wide dark underside toward the camera. It reads as heel recovery rather than a low passing pose. Reject phase-role claim despite the explicit prompt and improved compositional scale.",
            "identity_anatomy": "Exactly two ears, two arms and two legs are visible; no detached parts or camera drift detected in raw review.",
            "outline_palette": "No broad red fringe is visible; the raw retains transparent alpha. The new cell's outlines appear heavier than the small installed sprite style at source preview scale, so use registered contact for comparison.",
        },
        "proposal_integrity": {
            "changed_pixels_by_phase_vs_v2": before_after_diff,
            "other_seven_frames_unchanged": all(item["changed_pixel_count"] == 0 for item in before_after_diff if item["phase"] != 7),
            "phase_owner_contract": [
                "left contact", "left weight-down", "right compact passing", "right knee-up recovery",
                "right contact", "right weight-down", "left compact passing", "left knee-up recovery",
            ],
        },
        "timed_preview": {
            "path": paths["gif"].relative_to(ROOT).as_posix(),
            "frame_count": gif.n_frames,
            "frame_size_px": list(gif.size),
            "durations_ms": gif_durations,
        },
        "cross_view_comparison": {
            "installed_walk_idle_contact_path": (base.OUT / "north-v2-cross-view-idle-walk-contact-white.png").relative_to(ROOT).as_posix(),
            "installed_north_walk_contact_path": (base.OUT / "north-v2-vs-installed-north-walk-white.png").relative_to(ROOT).as_posix(),
            "installed_direction_measurements": installed_direction_summary,
            "installed_walk_idle_alpha_bbox_height_px": {"walk_range": prior_audit["installed_cross_view_comparison"]["installed_walk_visible_height_range_px"], "idle_range": prior_audit["installed_cross_view_comparison"]["installed_idle_visible_height_range_px"]},
            "artifact_aware_north_k7_note": "Raw alpha bounds report 410px for the installed set, but installed north phase 7 includes two detached pixels rows at y=56-57; body begins at y=80, so body-only height is 386px. Root is separately cleaning that residue without changing body pixels.",
            "normalized_candidate_metrics": {
                "v2_phase1_to_phase8_head_widths_px": v2_head_widths,
                "v2_phase1_to_phase8_torso_median_widths_px": v2_torso_widths,
                "v2_phase1_to_phase8_visible_heights_px": [m["visible_height_px"] for m in base_metrics],
                "trial03_phase7": {"head_width_px": trial_metrics["orange_head_band_y170_249_max_row_width_px"]["width"], "torso_median_width_px": trial_metrics["blue_overall_band_y245_334_median_row_width_px"], "visible_height_px": trial_metrics["visible_height_px"]},
                "accepted_k5": {"head_width_px": k5_metrics["orange_head_band_y170_249_max_row_width_px"]["width"], "torso_median_width_px": k5_metrics["blue_overall_band_y245_334_median_row_width_px"], "visible_height_px": k5_metrics["visible_height_px"]},
            },
            "outline_weight_proxy": {
                "measure": "dark RGB pixel share of visible alpha>64 pixels; includes dark internal details and is not a literal stroke-width measure",
                "installed_walk_phase1_range_percent": [min(installed_walk1_ink), max(installed_walk1_ink)],
                "v2_all_phase_range_percent": [min(v2_ink_shares), max(v2_ink_shares)],
                "trial03_phase7_percent": trial_metrics["dark_ink_pixel_share_of_visible_alpha64_percent"],
                "visual_finding": "V2 dark-pixel share is above all installed walk phase-1 comparators; the registered V2 and trial03 contact looks heavier in outline/detail than east, southeast and northeast, and somewhat heavier than installed north/south. This remains a visible cross-view style risk, not an acceptance conclusion.",
            },
            "comparison_note": "Review the installed five-direction idle/walk contact with the all-eight north V2 contact and the K6/V2-K7/trial03/K8/K5 neighbor strip. The measured full-cell trial03 is 425px versus the installed 410px band, V2 409-412px and K5 416px; this is a visible size pop under the frozen shared scale. No runtime art is changed.",
        },
        "output_hashes_sha256": {p.relative_to(ROOT).as_posix(): sha(p) for p in outputs},
        "decision": "Hold. One bounded edit did not produce a compact phase-7 pass; root review is required and no runtime integration is authorized by this staging output.",
    }
    audit_path = OUT / "north-v2-phase7-trial03-audit.json"
    audit_path.write_text(json.dumps(audit, indent=2), encoding="utf-8")
    print(json.dumps({
        "trial03_sha256": sha(TRIAL_RAW),
        "scale": SCALE,
        "translation_xy": trial_translation,
        "trial_metrics": trial_metrics,
        "k5_metrics": k5_metrics,
        "sole_proxy": audit["sole_proxy"],
        "changed_pixels": before_after_diff,
        "outputs": audit["output_hashes_sha256"],
        "audit_path": audit_path.relative_to(ROOT).as_posix(),
    }, indent=2))


def ImageChops_difference_count(a: Image.Image, b: Image.Image) -> int:
    from PIL import ImageChops
    diff = ImageChops.difference(a, b)
    return sum(1 for pixel in diff.getdata() if pixel != (0, 0, 0, 0))


if __name__ == "__main__":
    build()
