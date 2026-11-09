"""Build one staged south K3 passing replacement and its comparisons.

All source art remains immutable. This builder writes only Luna's cat-worker
staging and output folders; it does not alter the existing K7 proposal builder,
transitions, runtime registration, shared specs, or game saves.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import PIL
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / "assets/source/animation-overhaul-luna-v1/cat-worker"
OUTPUT = ROOT / "output/animation-overhaul/luna-cat/canonical-correction-candidate"

RAW_K3 = STAGE / "generated/walk_south-canonical-key03-correction-imagegen-v1.png"
PROMPT = STAGE / "prompts/walk_south-canonical-key03-passing-correction-v1.txt"
BASE_KEYS = STAGE / "canonical-replacements/walk_south-corrected-canonical-8phase-v2.png"
K7_CANDIDATE = STAGE / "canonical-replacements/walk_south-canonical-key07-correction-candidate-v1.png"
K7_PROPOSAL = STAGE / "canonical-replacements/walk_south-corrected-canonical-8phase-proposal-key07v1.png"
K7_PROVENANCE = STAGE / "canonical-replacements/walk_south-canonical-key07-correction-candidate-v1.json"
REFERENCES = {
    "key2_previous_weight_down": STAGE / "generated/references/south-v2-key02-transition02-endpoint.png",
    "key4_next_knee_up": STAGE / "generated/references/south-v2-key04-transition08-endpoint.png",
    "corrected_key7_opposite_passing": K7_CANDIDATE,
    "style_identity": STAGE / "generated/references/south-phase1-style-reference.png",
    "screen_side_leg_role_guide": STAGE / "generated/references/south-leg-role-diagram-v1.png",
}

EXPECTED_SHA256 = {
    RAW_K3: "e1ce9f7fd6d1cbd4b2d3b2cc11beecb71959d59684c59193e4b6a37eec4dda06",
    PROMPT: "4ed689980fedced0e79a1c7b361d2c18415f4a622f3dcbfe444f70691dd80219",
    BASE_KEYS: "03de4d1b38ef9506959e7d8ab49967c0454fe413a27812f7190b0563848ee2b8",
    K7_CANDIDATE: "996caae74ee2902bdf5574a9b5f3eeb4ed986ef7fe181e7fd7b6c00521bc161e",
    K7_PROPOSAL: "d5b032c7f1968017c647e5d7c3511d2da099e815bbecd1040df4826b05adce7a",
    K7_PROVENANCE: "61a572c44add6348cd5a8c73193ae2c8426ee15025789860ceb58e9e9b174bf8",
    REFERENCES["key2_previous_weight_down"]: "0765974a7da3198576346bc2dbafd367203b1705afed66daec49d27dd7427b2f",
    REFERENCES["key4_next_knee_up"]: "1345f627aaad85250caa0db711d190e88980e722576410c38faa20466fb58ee7",
    REFERENCES["style_identity"]: "09ccd6f1fef354f3fd83c2554915d224c3b8c1823e7d3cad730a1fac80192dc7",
    REFERENCES["screen_side_leg_role_guide"]: "a51ec422c7d799415df3c718c1023992dcce1a244925f50c4308a006e691fe20",
}

EXPECTED_PILLOW_VERSION = "12.3.0"
FRAME = 512
ALPHA_THRESHOLD = 16
SCALE = 0.40707497
CHECK_SIZE = 16
CHECK_A = (185, 186, 181)
CHECK_B = (211, 212, 206)

K3_CANDIDATE = STAGE / "canonical-replacements/walk_south-canonical-key03-correction-candidate-v1.png"
TRIPLET_REVIEW = OUTPUT / "walk_south-key03-correction-v1-K2-K3-K4-review.png"
FULL8_PROPOSAL = STAGE / "canonical-replacements/walk_south-corrected-canonical-8phase-proposal-key03v1.png"
FULL8_CONTACT = OUTPUT / "walk_south-corrected-canonical-8phase-proposal-key03v1-contact.png"
MANIFEST = STAGE / "canonical-replacements/walk_south-canonical-key03-correction-candidate-v1.json"

PHASES = [
    "left_contact", "left_weight_down", "right_passing", "right_knee_up",
    "right_contact", "right_weight_down", "left_passing", "left_knee_up",
]
PHASE_CAPTIONS = [
    "screen-left support; screen-right trailing",
    "screen-left support; screen-right begins swing",
    "screen-left support; screen-right passes under pelvis",
    "screen-left support; screen-right knee-up",
    "screen-right support; screen-left trailing",
    "screen-right support; screen-left begins swing",
    "screen-right support; screen-left passes under pelvis",
    "screen-right support; screen-left knee-up",
]


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pixel_hash(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def occupied_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    return image.convert("RGBA").getchannel("A").point(
        lambda value: 255 if value >= ALPHA_THRESHOLD else 0
    ).getbbox()


def bottom_row_anchor(image: Image.Image) -> dict[str, int | float]:
    mask = image.convert("RGBA").getchannel("A").point(
        lambda value: 255 if value >= ALPHA_THRESHOLD else 0
    )
    box = mask.getbbox()
    if box is None:
        raise ValueError("An image has no significant alpha pixels")
    y = box[3] - 1
    xs = [x for x, value in enumerate(mask.crop((0, y, image.width, y + 1)).get_flattened_data()) if value]
    return {"ground_y_px": y, "x_min_px": min(xs), "x_max_px": max(xs), "x_mid_px": round((min(xs) + max(xs)) / 2, 2)}


def torso_axis_x(image: Image.Image) -> float:
    """Median center of the longest torso-band alpha run."""
    mask = image.convert("RGBA").getchannel("A").point(
        lambda value: 255 if value >= ALPHA_THRESHOLD else 0
    )
    box = mask.getbbox()
    if box is None:
        raise ValueError("Cannot measure torso axis in an empty image")
    y0, y1 = box[1], box[3]
    start_y = max(0, round(y0 + 0.30 * (y1 - y0)))
    end_y = min(image.height, round(y0 + 0.75 * (y1 - y0)))
    centers = []
    for y in range(start_y, end_y):
        row = list(mask.crop((0, y, image.width, y + 1)).get_flattened_data()) + [0]
        runs = []
        start = None
        for x, value in enumerate(row):
            if value and start is None:
                start = x
            elif not value and start is not None:
                runs.append((start, x))
                start = None
        if runs:
            left, right = max(runs, key=lambda run: run[1] - run[0])
            if right - left >= 12:
                centers.append((left + right) / 2)
    if not centers:
        raise ValueError("Could not estimate torso axis")
    centers.sort()
    return centers[len(centers) // 2]


def head_width(image: Image.Image) -> int | None:
    box = occupied_bbox(image)
    if box is None:
        return None
    left, top, _, bottom = box
    upper = image.convert("RGBA").getchannel("A").point(
        lambda value: 255 if value >= ALPHA_THRESHOLD else 0
    ).crop((0, top, image.width, min(image.height, top + round(0.43 * (bottom - top)))))
    bbox = upper.getbbox()
    return None if bbox is None else bbox[2] - bbox[0]


def checker(size: tuple[int, int]) -> Image.Image:
    image = Image.new("RGB", size, CHECK_A)
    draw = ImageDraw.Draw(image)
    width, height = size
    for y in range(0, height, CHECK_SIZE):
        for x in range(0, width, CHECK_SIZE):
            if ((x // CHECK_SIZE) + (y // CHECK_SIZE)) % 2:
                draw.rectangle((x, y, min(width - 1, x + CHECK_SIZE - 1), min(height - 1, y + CHECK_SIZE - 1)), fill=CHECK_B)
    return image


def composite_checker(frame: Image.Image) -> Image.Image:
    background = checker((FRAME, FRAME))
    rgba = frame.convert("RGBA")
    background.paste(rgba, (0, 0), rgba.getchannel("A"))
    return background


def make_triplet(frames: list[Image.Image]) -> Image.Image:
    title_h, label_h, caption_h = 70, 28, 32
    canvas = Image.new("RGB", (3 * FRAME, title_h + label_h + FRAME + caption_h), (48, 51, 49))
    draw = ImageDraw.Draw(canvas)
    title = ImageFont.load_default(size=20)
    label = ImageFont.load_default(size=16)
    caption = ImageFont.load_default(size=13)
    draw.text((8, 7), "SOUTH K3 CORRECTION · K2 / NEW K3 / K4 · 512 PX CELLS", fill=(245, 245, 237), font=title)
    draw.text((8, 42), "Old v2 K3 was near-identical to K2; the new passing boot is still partly occluded, so root must confirm phase separation.", fill=(250, 216, 150), font=caption)
    labels = ["K2 · LEFT WEIGHT-DOWN", "NEW K3 · RIGHT PASSING", "K4 · RIGHT KNEE-UP"]
    captions = [
        "screen-left support; screen-right begins swing",
        "screen-left support; screen-right ankle tucked beneath pelvis",
        "screen-left support; screen-right knee raised",
    ]
    for index, frame in enumerate(frames):
        x = index * FRAME
        draw.text((x + 7, title_h + 5), labels[index], fill=(245, 245, 237), font=label)
        canvas.paste(composite_checker(frame), (x, title_h + label_h))
        draw.text((x + 7, title_h + label_h + FRAME + 7), captions[index], fill=(230, 231, 224), font=caption)
    return canvas


def make_full_contact(frames: list[Image.Image]) -> Image.Image:
    title_h, label_h, caption_h = 72, 25, 22
    row_h = label_h + FRAME + caption_h
    canvas = Image.new("RGB", (4 * FRAME, title_h + 2 * row_h), (48, 51, 49))
    draw = ImageDraw.Draw(canvas)
    title = ImageFont.load_default(size=20)
    note = ImageFont.load_default(size=12)
    label = ImageFont.load_default(size=15)
    caption = ImageFont.load_default(size=11)
    draw.text((8, 7), "CAT-WORKER SOUTH · EIGHT-KEY COMPARISON · NEW K3 + STAGED K7", fill=(245, 245, 237), font=title)
    draw.text((8, 39), "Old v2 K3 was near-identical to K2; this K3 replaces it. Root review must confirm phase separation and full-cycle seam.", fill=(250, 216, 150), font=note)
    for index, frame in enumerate(frames):
        row, column = divmod(index, 4)
        x = column * FRAME
        y = title_h + row * row_h
        suffix = " · NEW CANDIDATE" if index == 2 else " · STAGED K7" if index == 6 else ""
        draw.text((x + 7, y + 4), f"K{index + 1} · {PHASES[index].replace('_', ' ').upper()}{suffix}", fill=(245, 245, 237), font=label)
        canvas.paste(composite_checker(frame), (x, y + label_h))
        draw.text((x + 7, y + label_h + FRAME + 4), PHASE_CAPTIONS[index], fill=(230, 231, 224), font=caption)
    return canvas


def verify_inputs() -> dict[str, str]:
    if PIL.__version__ != EXPECTED_PILLOW_VERSION:
        raise RuntimeError(f"Expected Pillow {EXPECTED_PILLOW_VERSION}; found {PIL.__version__}")
    hashes = {}
    for path, expected in EXPECTED_SHA256.items():
        if not path.is_file():
            raise FileNotFoundError(path)
        actual = file_hash(path)
        hashes[path.relative_to(ROOT).as_posix()] = actual
        if actual != expected:
            raise ValueError(f"Pinned input changed: {path} expected {expected}, got {actual}")
    return hashes


def build() -> dict[str, object]:
    pinned = verify_inputs()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    raw = Image.open(RAW_K3).convert("RGBA")
    base = Image.open(BASE_KEYS).convert("RGBA")
    prior_proposal = Image.open(K7_PROPOSAL).convert("RGBA")
    if raw.size != (1254, 1254):
        raise ValueError(f"Unexpected raw K3 master canvas {raw.size}")
    if base.size != (FRAME * 8, FRAME) or prior_proposal.size != base.size:
        raise ValueError("Expected 4096x512 eight-key inputs")

    source_keys = [base.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(8)]
    k2, k4 = source_keys[1], source_keys[3]
    scaled = raw.resize((round(raw.width * SCALE), round(raw.height * SCALE)), Image.Resampling.LANCZOS)
    scaled_axis = torso_axis_x(scaled)
    scaled_ground = bottom_row_anchor(scaled)["ground_y_px"]
    target_axis = (torso_axis_x(k2) + torso_axis_x(k4)) / 2
    target_ground = round((bottom_row_anchor(k2)["ground_y_px"] + bottom_row_anchor(k4)["ground_y_px"]) / 2)
    dx = round(target_axis - scaled_axis)
    dy = target_ground - int(scaled_ground)
    candidate = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    candidate.alpha_composite(scaled, (dx, dy))
    if occupied_bbox(candidate) is None:
        raise ValueError("Normalized K3 candidate has no significant alpha")
    if bottom_row_anchor(candidate)["ground_y_px"] != target_ground:
        raise AssertionError("K3 support foot failed to align to the neighbor baseline")
    candidate.save(K3_CANDIDATE, optimize=True)
    saved_candidate = Image.open(K3_CANDIDATE).convert("RGBA")
    if saved_candidate.tobytes() != candidate.tobytes():
        raise AssertionError("Saved K3 candidate differs from normalized pixels")

    triplet_frames = [k2, saved_candidate, k4]
    triplet = make_triplet(triplet_frames)
    triplet.save(TRIPLET_REVIEW, optimize=True)

    prior_frames = [prior_proposal.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(8)]
    full_frames = list(prior_frames)
    full_frames[2] = saved_candidate.copy()
    full_proposal = Image.new("RGBA", (FRAME * 8, FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(full_frames):
        full_proposal.paste(frame, (index * FRAME, 0))
    full_proposal.save(FULL8_PROPOSAL, optimize=True)
    reread = Image.open(FULL8_PROPOSAL).convert("RGBA")
    reread_frames = [reread.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(8)]
    for index in range(8):
        if reread_frames[index].tobytes() != full_frames[index].tobytes():
            raise AssertionError(f"Full8 proposal changed pixels in K{index + 1}")
        if index != 2 and reread_frames[index].tobytes() != prior_frames[index].tobytes():
            raise AssertionError(f"K{index + 1} differs from prior K7 proposal")
    if pixel_hash(reread_frames[6]) != pixel_hash(Image.open(K7_CANDIDATE).convert("RGBA")):
        raise AssertionError("Previously reviewed K7 candidate was altered")
    full_contact = make_full_contact(reread_frames)
    full_contact.save(FULL8_CONTACT, optimize=True)

    k7_data = json.loads(K7_PROVENANCE.read_text(encoding="utf-8"))
    cell_sources = []
    for index, frame in enumerate(reread_frames):
        replacement = index == 2
        source = saved_candidate if replacement else prior_frames[index]
        source_path = K3_CANDIDATE if replacement else K7_PROPOSAL
        cell_sources.append({
            "key_index_1based": index + 1,
            "phase": PHASES[index],
            "source_path": source_path.relative_to(ROOT).as_posix(),
            "source_file_sha256": file_hash(source_path),
            "source_cell_rgba_sha256": pixel_hash(source),
            "proposal_cell_rgba_sha256": pixel_hash(frame),
            "pixel_identical_to_source_cell": pixel_hash(source) == pixel_hash(frame),
            "key3_replacement": replacement,
            "retained_from_prior_k7_proposal": not replacement,
            "alpha_bbox_threshold_16": list(occupied_bbox(frame)),
            "lowest_sole_candidate": bottom_row_anchor(frame),
        })

    manifest = {
        "version": 1,
        "status": "single_k3_correction_and_eight_key_comparison_staged_for_root_review",
        "character": "cat-worker south-facing walk",
        "contains_transitions": False,
        "runtime_registered": False,
        "pose_order": PHASES,
        "pinned_inputs": pinned,
        "generation": {
            "tool": "built-in image_gen",
            "generation_id": "exec-b9c6756b-3e7b-46f5-83d7-2ec576b9a0f7.png",
            "raw_image_path": RAW_K3.relative_to(ROOT).as_posix(),
            "raw_image_sha256": file_hash(RAW_K3),
            "prompt_path": PROMPT.relative_to(ROOT).as_posix(),
            "prompt_sha256": file_hash(PROMPT),
            "reference_roles_and_hashes": {
                role: {"path": path.relative_to(ROOT).as_posix(), "sha256": file_hash(path)}
                for role, path in REFERENCES.items()
            },
        },
        "normalization": {
            "raw_master_size_px": list(raw.size),
            "resized_master_canvas_px": list(scaled.size),
            "one_uniform_scale_factor": SCALE,
            "same_scale_as_reviewed_k7_candidate": True,
            "method": "LANCZOS on the complete raw image master once, then rigid whole-sprite translation only; no per-cell or per-part scaling, deformation, mirroring, or alpha-height fitting",
            "torso_axis_before_translation_px": round(scaled_axis, 2),
            "neighbor_torso_axis_target_px": round(target_axis, 2),
            "rigid_x_translation_px": dx,
            "support_ground_row_before_translation_px": scaled_ground,
            "neighbor_support_ground_target_px": target_ground,
            "rigid_y_translation_px": dy,
            "candidate_alpha_bbox_threshold_16": list(occupied_bbox(saved_candidate)),
            "candidate_torso_axis_after_translation_px": round(torso_axis_x(saved_candidate), 2),
            "candidate_support_ground_row_after_translation_px": bottom_row_anchor(saved_candidate)["ground_y_px"],
            "candidate_support_sole_center_x_px": bottom_row_anchor(saved_candidate)["x_mid_px"],
            "neighbor_support_sole_centers_x_px": [bottom_row_anchor(k2)["x_mid_px"], bottom_row_anchor(k4)["x_mid_px"]],
            "candidate_head_width_diagnostic_px": head_width(saved_candidate),
            "neighbor_head_width_diagnostic_px": [head_width(k2), head_width(k4)],
        },
        "outputs": {
            "single_key_candidate": {"path": K3_CANDIDATE.relative_to(ROOT).as_posix(), "sha256": file_hash(K3_CANDIDATE)},
            "k2_new_k3_k4_review": {"path": TRIPLET_REVIEW.relative_to(ROOT).as_posix(), "sha256": file_hash(TRIPLET_REVIEW)},
            "full8_comparison_strip": {"path": FULL8_PROPOSAL.relative_to(ROOT).as_posix(), "sha256": file_hash(FULL8_PROPOSAL)},
            "full8_comparison_contact": {"path": FULL8_CONTACT.relative_to(ROOT).as_posix(), "sha256": file_hash(FULL8_CONTACT)},
        },
        "full8_cell_source_hashes": cell_sources,
        "integrity_checks": {
            "all_cells_roundtrip_pixel_identical": True,
            "seven_other_cells_pixel_identical_to_prior_k7_proposal": all(
                reread_frames[i].tobytes() == prior_frames[i].tobytes() for i in range(8) if i != 2
            ),
            "k7_still_pixel_identical_to_root_reviewed_candidate": pixel_hash(reread_frames[6]) == pixel_hash(Image.open(K7_CANDIDATE).convert("RGBA")),
        },
        "review_findings": {
            "old_k3": "Original v2 K3 was visibly near-identical to K2 and was replaced in this comparison.",
            "new_k3_visual_check": "Generated view appears to keep the screen-left support foot planted and tuck the screen-right free boot beneath the pelvis, but that boot remains partly obscured by the satchel/body and may still read close to K2. Root must confirm whether the phase distinction is sufficient.",
            "k7": k7_data["visual_audit"]["K7_candidate"],
            "root_review_required": "Review K2/new K3/K4 and the full 8-key cycle/loop seam. This is a staged source comparison only; no runtime registration or motion-auditor claim.",
        },
        "generator": {
            "script_path": Path(__file__).relative_to(ROOT).as_posix(),
            "script_sha256": file_hash(Path(__file__)),
            "pillow_version": EXPECTED_PILLOW_VERSION,
            "determinism": "pinned input hashes, fixed scale and alignment arithmetic, fixed frame order, lossless RGBA cell copies, fixed checker presentation; no timestamps or randomness",
        },
        "outputs_do_not_include": ["transition frames", "runtime strips", "Config or motion-spec updates"],
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return {
        "candidate": K3_CANDIDATE.relative_to(ROOT).as_posix(),
        "triplet_review": TRIPLET_REVIEW.relative_to(ROOT).as_posix(),
        "full8_strip": FULL8_PROPOSAL.relative_to(ROOT).as_posix(),
        "full8_contact": FULL8_CONTACT.relative_to(ROOT).as_posix(),
        "manifest": MANIFEST.relative_to(ROOT).as_posix(),
        "scale": SCALE,
        "rigid_translation_px": [dx, dy],
    }


if __name__ == "__main__":
    print(json.dumps(build(), indent=2))
