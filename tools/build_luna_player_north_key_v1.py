"""Rebuild the staged North phase-5 canonical proposal deterministically.

This script writes only two review artifacts under
output/animation-overhaul/luna-player/pose-corrections-v1/:

* north-canonical-05-trial-06-uniform.png
* north-phase5-trial06-8frame-proposal.png

It reads the immutable original North walk strip and the immutable ImageGen
source master. The fixed crop, single uniform scale, Lanczos resampling, and
anchor/ground translation are pinned below. It never modifies runtime assets,
Config, specs, tests, or source masters.
"""

from __future__ import annotations

import hashlib
import math
from io import BytesIO
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
RAW_MASTER = (
    ROOT
    / "assets/source/animation-overhaul-luna-player-v1/pose-corrections-v1/"
    / "north-canonical-05-trial-06-generated.png"
)
ORIGINAL_STRIP = ROOT / "assets/generated/characters/rabbit-worker/walk_north.png"
OUTPUT_DIR = ROOT / "output/animation-overhaul/luna-player/pose-corrections-v1"
NORMALIZED_PATH = OUTPUT_DIR / "north-canonical-05-trial-06-uniform.png"
PROPOSAL_PATH = OUTPUT_DIR / "north-phase5-trial06-8frame-proposal.png"

FRAME = 512
FRAME_COUNT = 8
REPLACEMENT_INDEX = 4  # zero-based canonical phase 5
ALPHA_THRESHOLD = 16  # pixels with alpha > 16 are visible
EXPANDED_SUBJECT_CROP = (401, 138, 932, 1174)
UNIFORM_SCALE = 0.40773276015281634
CANONICAL_MEDIAN_HEAD_WIDTH = 114.0
CANONICAL_MEDIAN_TORSO_WIDTH = 78.0
RAW_MASTER_HEAD_WIDTH = 283.0
RAW_MASTER_TORSO_WIDTH = 189.0
RESAMPLED_SIZE = (217, 422)
RESAMPLED_VISIBLE_BBOX = (3, 3, 214, 419)
PASTE_XY = (160, 46)  # torso center x=256; visible ground line y=465
EXPECTED_FINAL_VISIBLE_BBOX = (163, 49, 374, 465)

# Hashes pin both immutable inputs and the reviewed staged outputs.
EXPECTED_RAW_SHA256 = "d8f4220f356bc5069ab10252b641d839f54e9023451dce2e487b03a89bc72c83"
EXPECTED_ORIGINAL_STRIP_SHA256 = "feb7dedef4e77f5b1b28d5143d641b99d3a90500abaa5b9827989e96af76927b"
EXPECTED_NORMALIZED_SHA256 = "1b55ca0f529776adb290c5ca680e6547772b4df4edafedeb64743ed4ab6e0979"
EXPECTED_PROPOSAL_SHA256 = "244171ab60f25e618891511062f94add0c8a83851b734b4593330a634c071f8c"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_path(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def visible_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    alpha = image.convert("RGBA").getchannel("A")
    return alpha.point(lambda value: 255 if value > ALPHA_THRESHOLD else 0).getbbox()


def png_bytes(image: Image.Image) -> bytes:
    buffer = BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def main() -> None:
    if sha256_path(RAW_MASTER) != EXPECTED_RAW_SHA256:
        raise SystemExit(f"Pinned raw source hash mismatch: {RAW_MASTER}")
    if sha256_path(ORIGINAL_STRIP) != EXPECTED_ORIGINAL_STRIP_SHA256:
        raise SystemExit(f"Pinned original strip hash mismatch: {ORIGINAL_STRIP}")

    raw = Image.open(RAW_MASTER).convert("RGBA")
    if raw.size != (1254, 1254):
        raise SystemExit(f"Unexpected raw master dimensions: {raw.size}")
    if raw.getchannel("A").getextrema() != (0, 255):
        raise SystemExit("Raw master must retain real transparent pixels")

    alpha_bbox = visible_bbox(raw)
    if alpha_bbox != (409, 146, 924, 1166):
        raise SystemExit(f"Unexpected raw visible bounds: {alpha_bbox}")
    subject = raw.crop(EXPANDED_SUBJECT_CROP)
    derived_scale = math.sqrt(
        (CANONICAL_MEDIAN_HEAD_WIDTH / RAW_MASTER_HEAD_WIDTH)
        * (CANONICAL_MEDIAN_TORSO_WIDTH / RAW_MASTER_TORSO_WIDTH)
    )
    if derived_scale != UNIFORM_SCALE:
        raise SystemExit(f"Pinned landmark scale changed: {derived_scale:.17f}")
    derived_size = (
        round(subject.width * UNIFORM_SCALE),
        round(subject.height * UNIFORM_SCALE),
    )
    if derived_size != RESAMPLED_SIZE:
        raise SystemExit(f"Pinned resampled dimensions changed: {derived_size}")
    resized = subject.resize(derived_size, Image.Resampling.LANCZOS)
    resized_bbox = visible_bbox(resized)
    if resized_bbox != RESAMPLED_VISIBLE_BBOX:
        raise SystemExit(f"Unexpected resized visible bounds: {resized_bbox}")

    normalized = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    normalized.alpha_composite(resized, PASTE_XY)
    final_bbox = visible_bbox(normalized)
    if final_bbox != EXPECTED_FINAL_VISIBLE_BBOX:
        raise SystemExit(f"Unexpected normalized visible bounds: {final_bbox}")

    original = Image.open(ORIGINAL_STRIP).convert("RGBA")
    if original.size != (FRAME * FRAME_COUNT, FRAME):
        raise SystemExit(f"Expected an 8-cell horizontal strip, got {original.size}")
    frames = [
        original.crop((index * FRAME, 0, (index + 1) * FRAME, FRAME))
        for index in range(FRAME_COUNT)
    ]
    old_replacement = frames[REPLACEMENT_INDEX]
    if old_replacement.tobytes() == normalized.tobytes():
        raise SystemExit("Replacement unexpectedly matches the original phase 5")
    frames[REPLACEMENT_INDEX] = normalized

    for index, frame in enumerate(frames):
        if index != REPLACEMENT_INDEX:
            source_cell = original.crop((index * FRAME, 0, (index + 1) * FRAME, FRAME))
            if frame.tobytes() != source_cell.tobytes():
                raise SystemExit(f"Canonical source cell {index + 1} changed")

    proposal = Image.new("RGBA", original.size, (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        proposal.alpha_composite(frame, (index * FRAME, 0))

    normalized_data = png_bytes(normalized)
    proposal_data = png_bytes(proposal)
    normalized_hash = sha256_bytes(normalized_data)
    proposal_hash = sha256_bytes(proposal_data)
    if normalized_hash != EXPECTED_NORMALIZED_SHA256:
        raise SystemExit(f"Normalized PNG hash changed: {normalized_hash}")
    if proposal_hash != EXPECTED_PROPOSAL_SHA256:
        raise SystemExit(f"Proposal PNG hash changed: {proposal_hash}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    NORMALIZED_PATH.write_bytes(normalized_data)
    PROPOSAL_PATH.write_bytes(proposal_data)
    if sha256_path(NORMALIZED_PATH) != EXPECTED_NORMALIZED_SHA256:
        raise SystemExit("Written normalized PNG did not match the pinned hash")
    if sha256_path(PROPOSAL_PATH) != EXPECTED_PROPOSAL_SHA256:
        raise SystemExit("Written proposal PNG did not match the pinned hash")

    print("Rebuilt the staged North phase-5 normalized cell and 8-frame proposal.")
    print(f"Raw source SHA-256: {EXPECTED_RAW_SHA256}")
    print(f"Original strip SHA-256: {EXPECTED_ORIGINAL_STRIP_SHA256}")
    print(f"Crop: {EXPANDED_SUBJECT_CROP}; scale: {UNIFORM_SCALE:.17f}; Lanczos: {RESAMPLED_SIZE}")
    print(f"Translation: {PASTE_XY}; normalized SHA-256: {normalized_hash}")
    print(f"Proposal SHA-256: {proposal_hash}; unchanged canonical cells: 7/7")


if __name__ == "__main__":
    main()
