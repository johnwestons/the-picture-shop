"""Rebuild Luna's staged south-facing eight-key cat-worker proposal.

This script reads pinned, immutable review inputs and writes only the Luna
source/output staging paths. It replaces canonical key 7 in the v2 eight-key
master with the separately reviewed candidate; it never adds transitions,
registers runtime art, edits a motion spec, or touches game saves.
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

BASE_MASTER = STAGE / "canonical-replacements/walk_south-corrected-canonical-8phase-v2.png"
K7_CANDIDATE = STAGE / "canonical-replacements/walk_south-canonical-key07-correction-candidate-v1.png"
K7_PROVENANCE = STAGE / "canonical-replacements/walk_south-canonical-key07-correction-candidate-v1.json"
K7_PROMPT = STAGE / "prompts/walk_south-canonical-key07-passing-correction-v1.txt"
# Preserve the original timing/pose contract even after South is installed at runtime.
MOTION_SPEC_SNAPSHOT = STAGE / "references/cat-worker-motion-generation-v1.json"

EXPECTED_INPUT_SHA256 = {
    BASE_MASTER: "03de4d1b38ef9506959e7d8ab49967c0454fe413a27812f7190b0563848ee2b8",
    K7_CANDIDATE: "996caae74ee2902bdf5574a9b5f3eeb4ed986ef7fe181e7fd7b6c00521bc161e",
    K7_PROVENANCE: "61a572c44add6348cd5a8c73193ae2c8426ee15025789860ceb58e9e9b174bf8",
    K7_PROMPT: "6358f538aab9b345209fccb30026cb88a6788b2a1ca0ee7091d57a6ae195a9e8",
    MOTION_SPEC_SNAPSHOT: "e6d5cb1ee5f1dba40d0023574086b3e0915a4593b34228d433414a74f434fb2c",
}

FRAME = 512
KEY_COUNT = 8
K7_INDEX = 6
EXPECTED_PILLOW_VERSION = "12.3.0"
EXPECTED_FPS = 5.538461538461538
ALPHA_THRESHOLD = 16
CHECK_SIZE = 16
CHECK_A = (185, 186, 181)
CHECK_B = (211, 212, 206)

PHASES = [
    "left_contact",
    "left_weight_down",
    "right_passing",
    "right_knee_up",
    "right_contact",
    "right_weight_down",
    "left_passing",
    "left_knee_up",
]
PHASE_CAPTIONS = [
    "screen-left support; screen-right trailing",
    "screen-left support; screen-right begins swing",
    "screen-left support; screen-right passing",
    "screen-left support; screen-right knee-up",
    "screen-right support; screen-left trailing",
    "screen-right support; screen-left begins swing",
    "screen-right support; screen-left passing",
    "screen-right support; screen-left knee-up",
]

PROPOSAL = STAGE / "canonical-replacements/walk_south-corrected-canonical-8phase-proposal-key07v1.png"
CONTACT = OUTPUT / "walk_south-corrected-canonical-8phase-proposal-key07v1-contact.png"
NOMINAL_GIF = OUTPUT / "walk_south-corrected-canonical-8phase-proposal-key07v1-nominal.gif"
HALF_GIF = OUTPUT / "walk_south-corrected-canonical-8phase-proposal-key07v1-half-speed.gif"
MANIFEST = STAGE / "canonical-replacements/walk_south-corrected-canonical-8phase-proposal-key07v1-provenance.json"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def rgba_hash(image: Image.Image) -> str:
    return sha256_bytes(image.convert("RGBA").tobytes())


def occupied_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    mask = image.convert("RGBA").getchannel("A").point(
        lambda value: 255 if value >= ALPHA_THRESHOLD else 0
    )
    return mask.getbbox()


def bottom_row_anchor(image: Image.Image) -> dict[str, int | float]:
    mask = image.convert("RGBA").getchannel("A").point(
        lambda value: 255 if value >= ALPHA_THRESHOLD else 0
    )
    box = mask.getbbox()
    if box is None:
        raise ValueError("A proposal cell is empty")
    ground_y = box[3] - 1
    row = mask.crop((0, ground_y, image.width, ground_y + 1))
    xs = [x for x, value in enumerate(row.get_flattened_data()) if value]
    return {
        "ground_y_px": ground_y,
        "x_min_px": min(xs),
        "x_max_px": max(xs),
        "x_mid_px": round((min(xs) + max(xs)) / 2, 2),
    }


def checkerboard(size: tuple[int, int]) -> Image.Image:
    image = Image.new("RGB", size, CHECK_A)
    draw = ImageDraw.Draw(image)
    width, height = size
    for y in range(0, height, CHECK_SIZE):
        for x in range(0, width, CHECK_SIZE):
            if ((x // CHECK_SIZE) + (y // CHECK_SIZE)) % 2:
                draw.rectangle(
                    (x, y, min(width - 1, x + CHECK_SIZE - 1), min(height - 1, y + CHECK_SIZE - 1)),
                    fill=CHECK_B,
                )
    return image


def frame_on_checker(frame: Image.Image) -> Image.Image:
    background = checkerboard((FRAME, FRAME))
    background.paste(frame.convert("RGBA"), (0, 0), frame.convert("RGBA").getchannel("A"))
    return background


def make_contact_sheet(frames: list[Image.Image]) -> Image.Image:
    title_height = 68
    label_height = 25
    caption_height = 24
    row_height = label_height + FRAME + caption_height
    sheet = Image.new("RGB", (4 * FRAME, title_height + 2 * row_height), (48, 51, 49))
    draw = ImageDraw.Draw(sheet)
    title_font = ImageFont.load_default(size=20)
    label_font = ImageFont.load_default(size=15)
    caption_font = ImageFont.load_default(size=12)
    draw.text((8, 7), "CAT-WORKER SOUTH · EIGHT-KEY CANONICAL PROPOSAL · K7 REPLACEMENT", fill=(245, 245, 237), font=title_font)
    draw.text((8, 39), "K3 right-passing ownership is correct but visually close to K2 weight-down; phase separation remains for root review.", fill=(250, 216, 150), font=caption_font)
    for index, frame in enumerate(frames):
        row, column = divmod(index, 4)
        x = column * FRAME
        y = title_height + row * row_height
        draw.text((x + 7, y + 5), f"K{index + 1} · {PHASES[index].replace('_', ' ').upper()}", fill=(245, 245, 237), font=label_font)
        sheet.paste(frame_on_checker(frame), (x, y + label_height))
        draw.text((x + 7, y + label_height + FRAME + 5), PHASE_CAPTIONS[index], fill=(230, 231, 224), font=caption_font)
    return sheet


def make_gif(frames: list[Image.Image], duration_ms: int, path: Path) -> None:
    rgb_frames = [frame_on_checker(frame) for frame in frames]
    palette_source = Image.new("RGB", (FRAME, FRAME * KEY_COUNT))
    for index, image in enumerate(rgb_frames):
        palette_source.paste(image, (0, index * FRAME))
    palette = palette_source.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    gif_frames = [
        image.quantize(palette=palette, dither=Image.Dither.NONE)
        for image in rgb_frames
    ]
    gif_frames[0].save(
        path,
        format="GIF",
        save_all=True,
        append_images=gif_frames[1:],
        duration=duration_ms,
        loop=0,
        disposal=2,
        optimize=False,
    )


def verify_pinned_inputs() -> dict[str, str]:
    actual = {}
    for path, expected in EXPECTED_INPUT_SHA256.items():
        if not path.is_file():
            raise FileNotFoundError(f"Pinned input is missing: {path}")
        digest = sha256_file(path)
        actual[path.relative_to(ROOT).as_posix()] = digest
        if digest != expected:
            raise ValueError(f"Pinned input hash mismatch for {path}: expected {expected}, got {digest}")
    if PIL.__version__ != EXPECTED_PILLOW_VERSION:
        raise RuntimeError(
            f"Pillow version mismatch: expected {EXPECTED_PILLOW_VERSION}, got {PIL.__version__}"
        )
    motion = json.loads(MOTION_SPEC_SNAPSHOT.read_text(encoding="utf-8"))
    walk = motion["animations"]["walk_south"]
    if walk["frame_count"] != KEY_COUNT or abs(float(walk["fps"]) - EXPECTED_FPS) > 1e-12:
        raise ValueError("Pinned motion spec no longer matches the preview frame count/rate")
    return actual


def build() -> dict[str, object]:
    pinned_hashes = verify_pinned_inputs()
    OUTPUT.mkdir(parents=True, exist_ok=True)

    base = Image.open(BASE_MASTER).convert("RGBA")
    candidate = Image.open(K7_CANDIDATE).convert("RGBA")
    if base.size != (FRAME * KEY_COUNT, FRAME):
        raise ValueError(f"Unexpected base master size: {base.size}")
    if candidate.size != (FRAME, FRAME):
        raise ValueError(f"Unexpected K7 candidate size: {candidate.size}")

    base_frames = [base.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(KEY_COUNT)]
    frames = list(base_frames)
    frames[K7_INDEX] = candidate.copy()

    proposal = Image.new("RGBA", (FRAME * KEY_COUNT, FRAME), (0, 0, 0, 0))
    cell_records = []
    for index, frame in enumerate(frames):
        proposal.paste(frame, (index * FRAME, 0))
        box = occupied_bbox(frame)
        if box is None:
            raise ValueError(f"Proposed key {index + 1} is empty")
        is_replacement = index == K7_INDEX
        source_image = candidate if is_replacement else base_frames[index]
        cell_records.append({
            "key_index_1based": index + 1,
            "phase": PHASES[index],
            "source_path": K7_CANDIDATE.relative_to(ROOT).as_posix() if is_replacement else BASE_MASTER.relative_to(ROOT).as_posix(),
            "source_file_sha256": sha256_file(K7_CANDIDATE if is_replacement else BASE_MASTER),
            "source_cell_rgba_sha256": rgba_hash(source_image),
            "proposal_cell_rgba_sha256": rgba_hash(frame),
            "pixel_identical_to_source_cell": rgba_hash(source_image) == rgba_hash(frame),
            "retained_v2_key_without_change": not is_replacement,
            "alpha_bbox_threshold_16": list(box),
            "lowest_sole_candidate": bottom_row_anchor(frame),
        })

    # Every non-replaced key must be byte-identical at decoded RGBA pixel level.
    for index, frame in enumerate(frames):
        if index != K7_INDEX and frame.tobytes() != base_frames[index].tobytes():
            raise AssertionError(f"K{index + 1} changed unexpectedly")
    if frames[K7_INDEX].tobytes() == base_frames[K7_INDEX].tobytes():
        raise AssertionError("K7 candidate unexpectedly matches the v2 key it replaces")

    proposal.save(PROPOSAL, optimize=True)
    saved = Image.open(PROPOSAL).convert("RGBA")
    saved_frames = [saved.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(KEY_COUNT)]
    for index, frame in enumerate(saved_frames):
        if frame.tobytes() != frames[index].tobytes():
            raise AssertionError(f"Saved proposal altered pixels in K{index + 1}")

    contact = make_contact_sheet(saved_frames)
    contact.save(CONTACT, optimize=True)
    # GIF stores frame delays in 10 ms units; pin to the nearest representable
    # value so the manifest describes the encoded timing, not an unencodable one.
    nominal_delay_ms = round((1000.0 / EXPECTED_FPS) / 10) * 10
    half_speed_delay_ms = round((2000.0 / EXPECTED_FPS) / 10) * 10
    make_gif(saved_frames, nominal_delay_ms, NOMINAL_GIF)
    make_gif(saved_frames, half_speed_delay_ms, HALF_GIF)

    k7_provenance = json.loads(K7_PROVENANCE.read_text(encoding="utf-8"))
    manifest = {
        "version": 1,
        "status": "staged_eight_key_proposal_for_root_review_only",
        "character": "cat-worker south-facing walk",
        "proposal": PROPOSAL.relative_to(ROOT).as_posix(),
        "proposal_sha256": sha256_file(PROPOSAL),
        "frame_size_px": [FRAME, FRAME],
        "frame_count": KEY_COUNT,
        "contains_transitions": False,
        "runtime_registered": False,
        "pose_order": PHASES,
        "pinned_inputs": pinned_hashes,
        "generator": {
            "script_path": Path(__file__).relative_to(ROOT).as_posix(),
            "script_sha256": sha256_file(Path(__file__)),
            "pillow_version": EXPECTED_PILLOW_VERSION,
            "deterministic_behavior": "fixed pinned input hashes, fixed frame order, lossless cell copies, fixed checker/palette settings, no timestamps or random values",
        },
        "cell_sources": cell_records,
        "integrity_checks": {
            "seven_nonreplacement_keys_pixel_identical_to_v2": all(
                frames[i].tobytes() == base_frames[i].tobytes()
                for i in range(KEY_COUNT) if i != K7_INDEX
            ),
            "k7_differs_from_v2_source_key": frames[K7_INDEX].tobytes() != base_frames[K7_INDEX].tobytes(),
            "saved_strip_roundtrip_pixel_identical": all(
                saved_frames[i].tobytes() == frames[i].tobytes() for i in range(KEY_COUNT)
            ),
        },
        "previews": {
            "contact_sheet": {"path": CONTACT.relative_to(ROOT).as_posix(), "sha256": sha256_file(CONTACT)},
            "nominal": {
                "path": NOMINAL_GIF.relative_to(ROOT).as_posix(),
                "sha256": sha256_file(NOMINAL_GIF),
                "source_fps": EXPECTED_FPS,
                "frame_duration_ms": nominal_delay_ms,
            },
            "half_speed": {
                "path": HALF_GIF.relative_to(ROOT).as_posix(),
                "sha256": sha256_file(HALF_GIF),
                "source_fps": EXPECTED_FPS,
                "frame_duration_ms": half_speed_delay_ms,
            },
        },
        "review_findings": {
            "k7": k7_provenance["visual_audit"]["K7_candidate"],
            "k3_right_passing": k7_provenance["visual_audit"]["K3_right_passing"],
            "root_review_required": "Review the entire 8-key sequence and loop seam. This staged proposal is not runtime art and has not passed the animation auditor or in-engine review.",
        },
        "k7_generation_provenance": {
            "raw_imagegen_id": k7_provenance["generation"]["generation_id"],
            "prompt_path": k7_provenance["generation"]["prompt_path"],
            "prompt_sha256": k7_provenance["generation"]["prompt_sha256"],
            "reference_roles": k7_provenance["generation"]["reference_roles"],
        },
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return {
        "proposal": PROPOSAL.relative_to(ROOT).as_posix(),
        "proposal_sha256": sha256_file(PROPOSAL),
        "contact_sheet": CONTACT.relative_to(ROOT).as_posix(),
        "nominal_preview": NOMINAL_GIF.relative_to(ROOT).as_posix(),
        "half_speed_preview": HALF_GIF.relative_to(ROOT).as_posix(),
        "manifest": MANIFEST.relative_to(ROOT).as_posix(),
        "nonreplacement_keys_pixel_identical": True,
        "nominal_frame_ms": nominal_delay_ms,
        "half_speed_frame_ms": half_speed_delay_ms,
    }


if __name__ == "__main__":
    print(json.dumps(build(), indent=2))
