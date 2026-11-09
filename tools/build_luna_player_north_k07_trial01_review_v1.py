"""Build a review-only North K7 correction proposal against installed v3.

The K7 raw master was edited from accepted K5 trial06. Its single fixed scale
is frozen to the accepted K5 scale; crop and translation only are applied.
K3 and K4 are the staged two-role proposal already under root review. Every
other cell is copied byte-for-byte from installed v3. No runtime asset is written.
"""

from __future__ import annotations

import hashlib
import json
import math
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "assets/source/animation-overhaul-luna-player-v1/pose-corrections-v1"
REF_DIR = SOURCE_DIR / "references"
OUTPUT_DIR = ROOT / "output/animation-overhaul/luna-player/pose-corrections-v1"

RAW_K7 = SOURCE_DIR / "north-canonical-07-trial-01-generated.png"
PROMPT = SOURCE_DIR / "north-canonical-07-trial-01-prompt.txt"
PROMPT_LOG = SOURCE_DIR / "imagegen-prompt-log-v1.json"
RAW_K5 = SOURCE_DIR / "north-canonical-05-trial-06-generated.png"
REF_K7_POSE = REF_DIR / "north-v3-k07-pose-owner-only-v1.png"
REF_K3_POSE = REF_DIR / "north-k03-trial03-compact-pass-pose-only-v1.png"

V3 = ROOT / "assets/generated/player-walk-v3/walk_north.png"
K3_TRIAL03 = OUTPUT_DIR / "north-canonical-03-trial-03-uniform.png"
K4_TRIAL02 = OUTPUT_DIR / "north-canonical-03-trial-02-uniform.png"
K5_TRIAL06 = OUTPUT_DIR / "north-canonical-05-trial-06-uniform.png"

K7_NORMALIZED = OUTPUT_DIR / "north-canonical-07-trial-01-uniform.png"
PROPOSAL = OUTPUT_DIR / "north-v3-k03trial03-k04trial02-k07trial01-proposal.png"
K6_K7_K8 = OUTPUT_DIR / "north-v3-k06-k07trial01-k08-review.png"
K3_TO_K8 = OUTPUT_DIR / "north-v3-k03trial03-k04trial02-k05-k06-k07trial01-k08-review.png"
FULL8 = OUTPUT_DIR / "north-v3-k03trial03-k04trial02-k07trial01-full8-game-scale-review.png"
ORIGINAL_VS_PROPOSAL = OUTPUT_DIR / "north-v3-k07trial01-original-vs-proposal-game-scale.png"
NOMINAL_GIF = OUTPUT_DIR / "north-v3-k03-k04-k07trial01-nominal-8phase.gif"
HALF_GIF = OUTPUT_DIR / "north-v3-k03-k04-k07trial01-half-speed-8phase.gif"
MANIFEST = SOURCE_DIR / "north-k07trial01-v3-proposal-manifest.json"

FRAME = 512
COUNT = 8
ALPHA_THRESHOLD = 16
GROUND_Y = 465
ANCHOR_X = 256
FROZEN_SCALE = 0.40773276015281634
RAW_HEAD_CENTER_X = 628.5

HASH_RAW_K7 = "567fb6558bbe26edef0e663a08b308510cacae24d881932d5c4c42483cb8306c"
HASH_PROMPT = "205241719d914539a9c2724e06e112833dea0b04252fee91f9cb9f5061427efa"
HASH_PROMPT_LOG = "688da585c3dfb5c9a02372ac6ecc2b8526be4cb4b42d4943ab41e836884b2448"
HASH_RAW_K5 = "d8f4220f356bc5069ab10252b641d839f54e9023451dce2e487b03a89bc72c83"
HASH_REF_K7 = "7e9d2ab7c3cf21706c8c6c39150557f0b19840ce8ba7c77da62fd1cec7c64fb3"
HASH_REF_K3 = "b43d7fe484bfdcc1d2c3ac2597d3ebbb4ee589915024df370976b44e44459b38"
HASH_V3 = "7df2307d8ac60ebd895077b39d856be3336c8430399bcb77b64a822d19840709"
HASH_K3_CANDIDATE = "22c9d7611d0667e9035c1733f814ce22d9cf226ca336956a8c0eac1f709e8743"
HASH_K4_CANDIDATE = "bc051d10cc7f99104f8a0f0906fc901d87f1cb59326746014847d70c8257e2be"
HASH_K5_CANDIDATE = "1b55ca0f529776adb290c5ca680e6547772b4df4edafedeb64743ed4ab6e0979"

LABELS = [
    "K1 installed v3",
    "K2 installed v3 / left support",
    "K3 trial03 / compact right passing",
    "K4 trial02 / right knee-up recovery",
    "K5 installed v3 / corrected trial06 contact",
    "K6 installed v3 / right weight-down",
    "K7 trial01 / left passing candidate",
    "K8 installed v3 / left knee-up",
]


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha_path(path: Path) -> str:
    return sha_bytes(path.read_bytes())


def pixel_sha(image: Image.Image) -> str:
    return sha_bytes(image.convert("RGBA").tobytes())


def visible_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    alpha = image.convert("RGBA").getchannel("A")
    return alpha.point(lambda value: 255 if value > ALPHA_THRESHOLD else 0).getbbox()


def png_bytes(image: Image.Image) -> bytes:
    buffer = BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def checker(cell: Image.Image, tile_size: int = 32) -> Image.Image:
    background = Image.new("RGBA", cell.size, "white")
    draw = ImageDraw.Draw(background)
    for y in range(0, cell.height, tile_size):
        for x in range(0, cell.width, tile_size):
            if (x // tile_size + y // tile_size) % 2:
                draw.rectangle(
                    (x, y, min(x + tile_size - 1, cell.width - 1), min(y + tile_size - 1, cell.height - 1)),
                    fill="#c7c7c7",
                )
    background.alpha_composite(cell.convert("RGBA"))
    return background.convert("RGB")


def contact(frames: list[Image.Image], labels: list[str], path: Path, columns: int) -> None:
    font_path = Path("C:/Windows/Fonts/arial.ttf")
    font = ImageFont.truetype(str(font_path), 16) if font_path.exists() else ImageFont.load_default()
    label_h = 36
    rows = math.ceil(len(frames) / columns)
    canvas = Image.new("RGB", (columns * FRAME, rows * (FRAME + label_h)), "#eeeeee")
    draw = ImageDraw.Draw(canvas)
    for index, frame in enumerate(frames):
        row, col = divmod(index, columns)
        x, y = col * FRAME, row * (FRAME + label_h)
        draw.text((x + 8, y + 8), labels[index], fill="#111111", font=font)
        canvas.paste(checker(frame), (x, y + label_h))
    canvas.save(path)


def write_gif(frames: list[Image.Image], path: Path, delay: int) -> None:
    previews = [checker(frame).convert("P", palette=Image.Palette.ADAPTIVE, colors=256) for frame in frames]
    previews[0].save(path, save_all=True, append_images=previews[1:], duration=delay, loop=0, disposal=2, optimize=False)


def main() -> None:
    inputs = (RAW_K7, PROMPT, PROMPT_LOG, RAW_K5, REF_K7_POSE, REF_K3_POSE, V3, K3_TRIAL03, K4_TRIAL02, K5_TRIAL06)
    missing = [str(path) for path in inputs if not path.is_file()]
    if missing:
        raise SystemExit("Missing required inputs: " + ", ".join(missing))
    expected = (
        (RAW_K7, HASH_RAW_K7, "raw K7 master"),
        (PROMPT_LOG, HASH_PROMPT_LOG, "ImageGen provenance log"),
        (RAW_K5, HASH_RAW_K5, "accepted raw K5 master"),
        (REF_K7_POSE, HASH_REF_K7, "K7 pose-only reference"),
        (REF_K3_POSE, HASH_REF_K3, "opposite-owner K3 pose-only reference"),
        (V3, HASH_V3, "installed v3 North strip"),
        (K3_TRIAL03, HASH_K3_CANDIDATE, "K3 trial03 normalized cell"),
        (K4_TRIAL02, HASH_K4_CANDIDATE, "K4 trial02 normalized cell"),
        (K5_TRIAL06, HASH_K5_CANDIDATE, "accepted K5 trial06 normalized cell"),
    )
    for path, wanted, label in expected:
        actual = sha_path(path)
        if actual != wanted:
            raise SystemExit(f"Pinned {label} hash mismatch: {actual}")
    prompt_hash = sha_path(PROMPT)
    if HASH_PROMPT and prompt_hash != HASH_PROMPT:
        raise SystemExit("Pinned K7 prompt hash mismatch")
    prompt_text = PROMPT.read_text(encoding="utf-8").strip()

    v3 = Image.open(V3).convert("RGBA")
    raw = Image.open(RAW_K7).convert("RGBA")
    k3 = Image.open(K3_TRIAL03).convert("RGBA")
    k4 = Image.open(K4_TRIAL02).convert("RGBA")
    k5 = Image.open(K5_TRIAL06).convert("RGBA")
    if v3.size != (FRAME * COUNT, FRAME):
        raise SystemExit(f"Expected 8x512 installed v3 strip, got {v3.size}")
    if raw.size != (1254, 1254) or raw.getchannel("A").getextrema() != (0, 255):
        raise SystemExit(f"Unexpected raw K7 dimensions/transparency: {raw.size}")
    if any(cell.size != (FRAME, FRAME) for cell in (k3, k4, k5)):
        raise SystemExit("A staged canonical candidate is not 512x512")

    v3_cells = [v3.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(COUNT)]
    if v3_cells[4].tobytes() != k5.tobytes():
        raise SystemExit("Installed v3 K5 differs from accepted trial06")

    crop = visible_bbox(raw)
    if crop is None:
        raise SystemExit("K7 raw master has no visible pixels")
    subject = raw.crop(crop)
    size = (round(subject.width * FROZEN_SCALE), round(subject.height * FROZEN_SCALE))
    resized = subject.resize(size, Image.Resampling.LANCZOS)
    resized_bbox = visible_bbox(resized)
    if resized_bbox is None:
        raise SystemExit("Normalized K7 vanished")

    normalized_k7 = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    head_center_from_crop = (RAW_HEAD_CENTER_X - crop[0]) * FROZEN_SCALE
    paste_x = round(ANCHOR_X - head_center_from_crop)
    paste_y = GROUND_Y - resized_bbox[3]
    normalized_k7.alpha_composite(resized, (paste_x, paste_y))
    final_bbox = visible_bbox(normalized_k7)
    if final_bbox is None or final_bbox[3] != GROUND_Y:
        raise SystemExit(f"Normalized K7 baseline differs: {final_bbox}")

    frames = list(v3_cells)
    frames[2], frames[3], frames[6] = k3, k4, normalized_k7
    for index in (0, 1, 4, 5, 7):
        if frames[index].tobytes() != v3_cells[index].tobytes():
            raise SystemExit(f"Untouched installed v3 K{index + 1} changed")
    if frames[2].tobytes() != k3.tobytes() or frames[3].tobytes() != k4.tobytes():
        raise SystemExit("Existing staged K3/K4 proposal pixels changed")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    K7_NORMALIZED.write_bytes(png_bytes(normalized_k7))
    strip = Image.new("RGBA", (FRAME * COUNT, FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME, 0))
    PROPOSAL.write_bytes(png_bytes(strip))

    k6_k7_k8 = [frames[i] for i in (5, 6, 7)]
    contact(k6_k7_k8, ["K6 v3 / right weight-down", "K7 trial01 / left passing candidate", "K8 v3 / left knee-up"], K6_K7_K8, columns=3)
    k3_to_k8 = frames[2:8]
    contact(k3_to_k8, LABELS[2:8], K3_TO_K8, columns=3)
    contact(frames, LABELS, FULL8, columns=4)
    comparison_labels = [f"Installed v3 / {label}" for label in LABELS] + [f"Proposal / {label}" for label in LABELS]
    contact(v3_cells + frames, comparison_labels, ORIGINAL_VS_PROPOSAL, columns=4)
    write_gif(frames, NOMINAL_GIF, 130)
    write_gif(frames, HALF_GIF, 260)

    k6_box = visible_bbox(v3_cells[5])
    k8_box = visible_bbox(v3_cells[7])
    k3_box = visible_bbox(k3)
    k4_box = visible_bbox(k4)
    k5_box = visible_bbox(k5)
    hashes = {
        "normalized_k7": sha_path(K7_NORMALIZED),
        "proposal_strip": sha_path(PROPOSAL),
        "k6_k7_k8_contact": sha_path(K6_K7_K8),
        "k3_to_k8_contact": sha_path(K3_TO_K8),
        "full8_contact": sha_path(FULL8),
        "original_vs_proposal_contact": sha_path(ORIGINAL_VS_PROPOSAL),
        "nominal_gif": sha_path(NOMINAL_GIF),
        "half_speed_gif": sha_path(HALF_GIF),
    }
    manifest = {
        "version": 1,
        "batch": "luna-player-north-k07-trial01-v3-review-v1",
        "status": "staged for root review only; no runtime integration",
        "imagegen": {
            "generation_id": "exec-11cdb414-5f46-44a4-8d4c-451377856bf4",
            "cache_path": "C:/Users/johnw/.codex/generated_images/01a17bec-a216-72b3-ac73-5e56d3da1c90/exec-11cdb414-5f46-44a4-8d4c-451377856bf4.png",
            "cache_timestamp_local": "2026-10-27T11:41:41-04:00",
            "exact_prompt_path": PROMPT.relative_to(ROOT).as_posix(),
            "exact_prompt_sha256": prompt_hash,
            "exact_prompt": prompt_text,
            "references": [
                {"path": RAW_K5.relative_to(ROOT).as_posix(), "sha256": sha_path(RAW_K5), "role": "editable identity/head/torso/outline/proportion/style source master"},
                {"path": REF_K7_POSE.relative_to(ROOT).as_posix(), "sha256": sha_path(REF_K7_POSE), "role": "cropped installed-v3 K7 lower-body pose/left-owner guide only"},
                {"path": REF_K3_POSE.relative_to(ROOT).as_posix(), "sha256": sha_path(REF_K3_POSE), "role": "opposite-owner compact passing amplitude cue only"},
            ],
        },
        "prompt_log": {
            "path": PROMPT_LOG.relative_to(ROOT).as_posix(),
            "sha256": sha_path(PROMPT_LOG),
            "entry_id": "exec-11cdb414-5f46-44a4-8d4c-451377856bf4",
        },
        "raw_master": {
            "path": RAW_K7.relative_to(ROOT).as_posix(),
            "sha256": sha_path(RAW_K7),
            "dimensions_px": list(raw.size),
            "alpha_bbox_gt_16": list(crop),
            "transparent_background": True,
        },
        "normalization": {
            "policy": "one frozen accepted K5 raw-master uniform scale; crop and translation only; no per-cell scale, deformation or height fit",
            "frozen_scale": FROZEN_SCALE,
            "resampling": "Pillow Lanczos",
            "raw_crop_xyxy": list(crop),
            "resized_size_px": list(size),
            "resized_visible_bbox_xyxy": list(resized_bbox),
            "raw_head_center_anchor_x": RAW_HEAD_CENTER_X,
            "target_center_x": ANCHOR_X,
            "ground_baseline_y": GROUND_Y,
            "paste_xy": [paste_x, paste_y],
            "normalized_visible_bbox_xyxy": list(final_bbox),
            "normalized_visible_height_px": final_bbox[3] - final_bbox[1],
            "neighbor_visible_heights_px": {
                "K6_v3": k6_box[3] - k6_box[1],
                "K3_trial03": k3_box[3] - k3_box[1],
                "K4_trial02": k4_box[3] - k4_box[1],
                "K5_trial06": k5_box[3] - k5_box[1],
                "K8_v3": k8_box[3] - k8_box[1],
            },
        },
        "base": {"path": V3.relative_to(ROOT).as_posix(), "sha256": sha_path(V3), "k5_matches_trial06": True},
        "phase_roles": [
            {"cell": 1, "role": "installed v3 original", "pixel_sha256": pixel_sha(v3_cells[0])},
            {"cell": 2, "role": "installed v3 left support", "pixel_sha256": pixel_sha(v3_cells[1])},
            {"cell": 3, "role": "staged trial03 compact right-passing candidate", "pixel_sha256": pixel_sha(frames[2])},
            {"cell": 4, "role": "staged trial02 provisional right knee-up/recovery", "pixel_sha256": pixel_sha(frames[3])},
            {"cell": 5, "role": "installed v3 accepted trial06 contact", "pixel_sha256": pixel_sha(v3_cells[4])},
            {"cell": 6, "role": "installed v3 right weight-down", "pixel_sha256": pixel_sha(v3_cells[5])},
            {"cell": 7, "role": "new left passing K7 candidate; review pending", "pixel_sha256": pixel_sha(frames[6])},
            {"cell": 8, "role": "installed v3 left knee-up", "pixel_sha256": pixel_sha(v3_cells[7])},
        ],
        "review_findings": [
            "Raw K7 candidate contains exactly two rabbit ears, two arms, two hands, two legs and two boots; right-side pouch and red/yellow tools remain visible.",
            "Viewer-right support boot is flat at the baseline; viewer-left leg is lifted low beneath the pelvis and remains connected to the left hip.",
            "The viewer-left boot shows only a narrow dark edge at game scale; the low passing pose reads compact between K6 and K8, pending root review.",
            "All unselected cells K1/K2/K5/K6/K8 are byte-exact installed v3; staged K3/K4 are reused unchanged. This proposal retains v3 K7 cleanup only in the comparison row; the new K7 is a separate proposal cell.",
            "No runtime edits or shared smoke checks were run.",
        ],
        "outputs": {key: {"path": path.relative_to(ROOT).as_posix(), "sha256": hashes[key]} for key, path in {
            "normalized_k7": K7_NORMALIZED,
            "proposal_strip": PROPOSAL,
            "k6_k7_k8_contact": K6_K7_K8,
            "k3_to_k8_contact": K3_TO_K8,
            "full8_contact": FULL8,
            "original_vs_proposal_contact": ORIGINAL_VS_PROPOSAL,
            "nominal_gif": NOMINAL_GIF,
            "half_speed_gif": HALF_GIF,
        }.items()},
        "gif_delays_ms": {"nominal": 130, "half_speed": 260},
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"K7 normalized sha256: {hashes['normalized_k7']}; bbox={final_bbox}; height={final_bbox[3] - final_bbox[1]}")
    print(f"Proposal strip sha256: {hashes['proposal_strip']}; base v3 {sha_path(V3)}")
    print(f"Manifest: {MANIFEST}")


if __name__ == "__main__":
    main()
