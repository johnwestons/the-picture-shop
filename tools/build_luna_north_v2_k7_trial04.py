from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
from statistics import median

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
BASE_PATH = ROOT / "tools/build_luna_north_consistent_v2.py"
SPEC = importlib.util.spec_from_file_location("north_v2_base", BASE_PATH)
base = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(base)

SOURCE, OUT = base.SOURCE, base.OUT
RAW = SOURCE / "north-consistent-v2-generated-raw.png"
TRIAL_RAW = SOURCE / "north-v2-phase7-replacement-trial04-generated-raw.png"
PROMPT = SOURCE / "north-v2-phase7-replacement-trial04-exact-prompt.txt"
IDENTITY = SOURCE / "accepted-k5-style-identity-reference.png"
POSE = SOURCE / "north-v2-phase7-clean-compact-pass-legs-only-pose-guide.png"
K5_NORMALIZED = base.K5_NORMALIZED
SCALE = base.K5_MASTER_SCALE
EXPECTED_RAW = "56b2b4312f121cb35aad139c8aebb93794251f8bebf324170799a87af3f21274"
FRAME = base.FRAME


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def register(source: Image.Image):
    source = source.convert("RGBA")
    box = base.bbox_alpha(source)
    if box is None:
        raise SystemExit("Trial04 source is blank at alpha threshold")
    pixels = source.load()
    orange_x = []
    head_end = min(source.height, box[1] + round((box[3] - box[1]) * 0.46))
    for y in range(box[1], head_end):
        for x in range(box[0], box[2]):
            if base.orange(*pixels[x, y]):
                orange_x.append(x)
    if not orange_x:
        raise SystemExit("Trial04 head anchor missing")
    center_x = sum(orange_x) / len(orange_x)
    scaled_box = [round(value * SCALE) for value in box]
    translation = [
        round(base.HEAD_CENTER_X - center_x * SCALE),
        base.GROUND_Y - (scaled_box[3] - 1),
    ]
    registered = base.padded_cell(source, SCALE, *translation)
    return registered, box, center_x, translation


def nonzero_diff(a: Image.Image, b: Image.Image) -> int:
    diff = ImageChops.difference(a, b)
    return sum(1 for pixel in diff.getdata() if pixel != (0, 0, 0, 0))


def build() -> None:
    if sha(TRIAL_RAW) != EXPECTED_RAW:
        raise SystemExit("Trial04 source hash mismatch")
    raw = Image.open(RAW).convert("RGBA")
    source_cells = [raw.crop((col * 384, row * 512, (col + 1) * 384, (row + 1) * 512)) for row in range(2) for col in range(4)]
    boxes = [base.bbox_alpha(cell) for cell in source_cells]
    heights = [box[3] - box[1] for box in boxes]
    base_scale = 410.0 / median(heights)
    base_dx = round(base.HEAD_CENTER_X - 192 * base_scale)
    base_dy = base.GROUND_Y - round(median([box[3] - 1 for box in boxes]) * base_scale)
    frames = [base.padded_cell(cell, base_scale, base_dx, base_dy) for cell in source_cells]

    trial_raw = Image.open(TRIAL_RAW).convert("RGBA")
    trial, trial_bbox, head_center_x, trial_translation = register(trial_raw)
    proposal_frames = list(frames)
    proposal_frames[6] = trial

    OUT.mkdir(parents=True, exist_ok=True)
    paths = {
        "raw_white": OUT / "north-v2-phase7-trial04-raw-white.png",
        "proposal": OUT / "north-v2-phase7-trial04-proposal.png",
        "contact": OUT / "north-v2-phase7-trial04-contact-white.png",
        "neighbors": OUT / "north-v2-phase7-trial04-neighbors-k5-white.png",
        "gif": OUT / "north-v2-phase7-trial04-64worldpx-timed.gif",
    }
    base.white_composite(trial_raw).save(paths["raw_white"])
    proposal_strip = Image.new("RGBA", (FRAME * 8, FRAME), (0, 0, 0, 0))
    contact = Image.new("RGBA", (FRAME * 4, FRAME * 2), (0, 0, 0, 0))
    for index, frame in enumerate(proposal_frames):
        proposal_strip.alpha_composite(frame, (index * FRAME, 0))
        row, col = divmod(index, 4)
        contact.alpha_composite(frame, (col * FRAME, row * FRAME))
    proposal_strip.save(paths["proposal"])
    base.white_composite(contact).save(paths["contact"])
    base.make_gif(proposal_frames, paths["gif"], duration_ms=130)

    k5sheet = Image.open(K5_NORMALIZED).convert("RGBA")
    k5cell = k5sheet.crop((FRAME * 4, 0, FRAME * 5, FRAME))
    neighbor = Image.new("RGBA", (FRAME * 5, FRAME), (255, 255, 255, 255))
    for index, frame in enumerate([frames[5], frames[6], trial, frames[7], k5cell]):
        neighbor.alpha_composite(frame, (index * FRAME, 0))
    neighbor.convert("RGB").save(paths["neighbors"])

    diffs = [{"phase": i + 1, "changed_pixel_count": nonzero_diff(before, after)} for i, (before, after) in enumerate(zip(frames, proposal_frames))]
    trial_metrics = base.metrics(trial)
    k5_metrics = base.metrics(k5cell)
    v2_metrics = [base.metrics(frame) for frame in frames]
    sole_trial = base.dark_roi_measure(trial, (178, 390, 258, 466))
    sole_v2_k7 = base.dark_roi_measure(frames[6], (178, 390, 258, 466))
    sole_v2_k3 = base.dark_roi_measure(frames[2], (270, 390, 350, 466))
    raw_alpha = trial_raw.getchannel("A")
    gif = Image.open(paths["gif"])
    durations = []
    for index in range(gif.n_frames):
        gif.seek(index)
        durations.append(gif.info.get("duration"))

    source_paths = [RAW, TRIAL_RAW, PROMPT, IDENTITY, POSE, base.K5_RAW]
    audit = {
        "title": "North phase-7 final bounded attempt (trial04), staged only",
        "generation": {
            "imagegen_id": "exec-1c6d99f3-87a7-4d9e-9b99-2118bbb0f958",
            "cached_output": r"C:\Users\johnw\.codex\generated_images\01a17bec-a216-72b3-ac73-5e56d3da1c90\exec-1c6d99f3-87a7-4d9e-9b99-2118bbb0f958.png",
            "transparent_background_requested": True,
            "prompt_path": PROMPT.relative_to(ROOT).as_posix(),
            "prompt_text": PROMPT.read_text(encoding="utf-8"),
        },
        "source_hashes_sha256": {p.relative_to(ROOT).as_posix(): sha(p) for p in source_paths},
        "reference_roles": {
            "identity_style_reference": IDENTITY.relative_to(ROOT).as_posix(),
            "identity_style_reference_role": "only full-character identity, outfit, proportion, palette, outline, texture, lighting, and camera reference",
            "pose_guide": POSE.relative_to(ROOT).as_posix(),
            "pose_guide_role": "clean lower-leg compact-pass pose geometry and screen-side ownership cue only",
            "cycle_source": RAW.relative_to(ROOT).as_posix(),
            "cycle_source_role": "all eight original V2 phases; only phase 7 is replaced in proposal",
        },
        "raw_alpha": {
            "size": list(trial_raw.size),
            "mode": Image.open(TRIAL_RAW).mode,
            "alpha_extrema": list(raw_alpha.getextrema()),
            "alpha_bbox_gt16": list(base.bbox_alpha(trial_raw)),
            "corner_alpha": [trial_raw.getpixel(pt)[3] for pt in [(0, 0), (1253, 0), (0, 1253), (1253, 1253)]],
            "visual_note": "White-alpha preview shows clean transparent canvas and no matte. One isolated alpha-1 pixel is present at the lower-left canvas corner and is below the alpha>16 normalized-art threshold.",
        },
        "registration": {
            "scale": SCALE,
            "scale_source": "fixed accepted K5 raw-master calibration; no per-cell fitting",
            "raw_bbox_alpha_gt16": list(trial_bbox),
            "head_anchor_centroid_x": head_center_x,
            "translation_xy": trial_translation,
            "groundline_y": base.GROUND_Y,
            "transform_policy": "one uniform full-source scale plus rigid horizontal/head and groundline translations only; no deformation",
        },
        "trial04_metrics_registered_512": trial_metrics,
        "k5_metrics_registered_512": k5_metrics,
        "v2_metrics_by_phase_registered_512": v2_metrics,
        "foot_proxy": {
            "method": "fixed dark-pixel ROI proxy, not semantic boot segmentation",
            "trial04_k7": sole_trial,
            "base_v2_k7": sole_v2_k7,
            "base_v2_k3_compact_pass_comparator": sole_v2_k3,
        },
        "phase7_visual_review": {
            "intended_role": "screen-left free boot nearly occluded behind screen-right planted boot; toe down, heel low, compact pass",
            "finding": "The free boot is now partly occluded behind the support boot, but its broad tread/sole is still visible toward camera. The boot silhouette remains a high, heel-recovery-like lift rather than a low passing foot. Reject the phase-role claim.",
            "anatomy": "Exactly two ears, two arms and two legs; no extra appendages or detached body parts visible at game scale.",
            "identity_and_style": "K5 identity, outfit, pouch and red/yellow tools remain recognizable. Head/body scale and bold line treatment are visibly larger/heavier than neighboring V2 phases at the fixed calibration; do not hide with independent scaling.",
        },
        "cycle_integrity": {
            "changed_pixels_by_phase_vs_base_v2": diffs,
            "other_seven_phases_pixel_identical": all(item["changed_pixel_count"] == 0 for item in diffs if item["phase"] != 7),
            "proposed_order": ["left contact", "left weight-down", "right compact passing", "right knee-up recovery", "right contact", "right weight-down", "left compact passing", "left knee-up recovery"],
        },
        "cross_view_comparison": {
            "five_view_idle_walk_contact_path": (OUT / "north-v2-cross-view-idle-walk-contact-white.png").relative_to(ROOT).as_posix(),
            "north_v2_vs_installed_contact_path": (OUT / "north-v2-vs-installed-north-walk-white.png").relative_to(ROOT).as_posix(),
            "comparison": "Installed walk/idle sheets use 410px alpha bounds, with old north K7's detached top-line exception documented in the prior V2 audit. Trial04 remains taller than the V2 409-412px band under fixed K5 calibration, and its large outline treatment still stands out against the five installed views, especially E/NE/SE.",
            "dark_ink_share_percent": {
                "installed_walk_phase1_range": [9.033, 13.613],
                "v2_cycle_range": [m["dark_ink_pixel_share_of_visible_alpha64_percent"] for m in v2_metrics],
                "trial04_phase7": trial_metrics["dark_ink_pixel_share_of_visible_alpha64_percent"],
                "metric_caveat": "This proxy includes internal dark detail and does not directly measure stroke width.",
            },
        },
        "timed_preview": {"path": paths["gif"].relative_to(ROOT).as_posix(), "frame_count": gif.n_frames, "size_px": list(gif.size), "durations_ms": durations},
        "output_hashes_sha256": {p.relative_to(ROOT).as_posix(): sha(p) for p in paths.values()},
        "builder_sha256": sha(Path(__file__)),
        "decision": "Rejected for phase 7 after one bounded attempt. Keep raw and proposal as evidence only; no runtime or spec integration.",
    }
    audit_path = OUT / "north-v2-phase7-trial04-audit.json"
    audit_path.write_text(json.dumps(audit, indent=2), encoding="utf-8")
    print(json.dumps({
        "raw_sha256": sha(TRIAL_RAW),
        "prompt_sha256": sha(PROMPT),
        "registered_metrics": trial_metrics,
        "k5_metrics": k5_metrics,
        "sole_proxy": audit["foot_proxy"],
        "changed_pixels": diffs,
        "output_hashes": audit["output_hashes_sha256"],
        "audit_path": audit_path.relative_to(ROOT).as_posix(),
    }, indent=2))


if __name__ == "__main__":
    build()
