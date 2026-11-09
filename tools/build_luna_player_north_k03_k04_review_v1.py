"""Build a review-only North K3/K4 two-key proposal against installed v3.

K3 trial03 is normalized from its immutable raw master with the frozen K5
uniform scale. K4 uses the already-normalized trial02 source pixels unchanged;
that artwork was reclassified by root as a knee-up / recovery key. All other
cells come byte-for-byte from installed player-walk-v3 North, including K5 and
the separate K7 cleanup. No runtime asset is written.
"""

from __future__ import annotations

import hashlib
import json
import math
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "assets/source/animation-overhaul-luna-player-v1/pose-corrections-v1"
OUTPUT_DIR = ROOT / "output/animation-overhaul/luna-player/pose-corrections-v1"
RAW_K3 = SOURCE_DIR / "north-canonical-03-trial-03-generated.png"
PROMPT_PATH = SOURCE_DIR / "north-canonical-03-trial-03-prompt.txt"
RAW_K5 = SOURCE_DIR / "north-canonical-05-trial-06-generated.png"
K2_REFERENCE = SOURCE_DIR / "references/north-canonical-02-for-k03-k04-ref-v1.png"
K4_TRIAL02 = OUTPUT_DIR / "north-canonical-03-trial-02-uniform.png"
V3 = ROOT / "assets/generated/player-walk-v3/walk_north.png"
LEGACY_SOURCE = ROOT / "assets/generated/characters/rabbit-worker/walk_north.png"
ACCEPTED_K5 = OUTPUT_DIR / "north-canonical-05-trial-06-uniform.png"

K3_NORMALIZED = OUTPUT_DIR / "north-canonical-03-trial-03-uniform.png"
PROPOSAL = OUTPUT_DIR / "north-v3-k03trial03-k04trial02-proposal.png"
NEIGHBOR_CONTACT = OUTPUT_DIR / "north-v3-k02-k03trial03-k04trial02-k05-neighbor-review.png"
FULL8_CONTACT = OUTPUT_DIR / "north-v3-k03trial03-k04trial02-full8-game-scale-review.png"
ORIGINAL_VS_PROPOSAL = OUTPUT_DIR / "north-v3-k03trial03-k04trial02-original-vs-proposal-game-scale.png"
NOMINAL_GIF = OUTPUT_DIR / "north-v3-k03trial03-k04trial02-nominal-8phase.gif"
HALF_SPEED_GIF = OUTPUT_DIR / "north-v3-k03trial03-k04trial02-half-speed-8phase.gif"
MANIFEST = SOURCE_DIR / "north-k03trial03-k04trial02-v3-proposal-manifest.json"

FRAME = 512
FRAME_COUNT = 8
ALPHA_THRESHOLD = 16
GROUND_Y = 465
TORSO_CENTER_X = 256
# Exact accepted uniform scale of raw K5 trial06 and the preceding K3 trial02.
FROZEN_SCALE = 0.40773276015281634
RAW_HEAD_CENTER_X = 628.5

EXPECTED_RAW_K3_SHA256 = "a6cd1bbf56e023102936c4b77a59d9150cef332018b0b28b657fe3dd919571b6"
EXPECTED_PROMPT_SHA256 = "1c0dad59c69ae24cf19aab4729369b55d7568bc6d74360a6376cbb6cdcde487e"
EXPECTED_V3_SHA256 = "7df2307d8ac60ebd895077b39d856be3336c8430399bcb77b64a822d19840709"
EXPECTED_K4_TRIAL02_FILE_SHA256 = "bc051d10cc7f99104f8a0f0906fc901d87f1cb59326746014847d70c8257e2be"
EXPECTED_K5_FILE_SHA256 = "1b55ca0f529776adb290c5ca680e6547772b4df4edafedeb64743ed4ab6e0979"
EXPECTED_LEGACY_SHA256 = "feb7dedef4e77f5b1b28d5143d641b99d3a90500abaa5b9827989e96af76927b"
EXPECTED_K4_RAW_SHA256 = "5b150d47cf946f3ba6ef19a61cb1895c0d5c50032d9d535665948039f03aeccd"

LABELS = [
    "K1 installed v3",
    "K2 installed v3 / left support",
    "K3 trial03 / compact right passing",
    "K4 trial02 / compact knee-up recovery",
    "K5 installed v3 / corrected trial06 contact",
    "K6 installed v3",
    "K7 installed v3 / detached-line cleanup retained",
    "K8 installed v3",
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


def orange_head_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    """Rough orange head/ear mask, clipped above the arms for scale comparison."""
    rgba = np.asarray(image.convert("RGBA"), dtype=np.float32)
    y, _x = np.indices(rgba.shape[:2])
    red, green, blue, alpha = (rgba[:, :, i] for i in range(4))
    mask = (alpha > ALPHA_THRESHOLD) & (y < 275) & (red > green * 1.12) & (red > blue * 1.18)
    yy, xx = np.where(mask)
    if not len(xx):
        return None
    return (int(xx.min()), int(yy.min()), int(xx.max() + 1), int(yy.max() + 1))


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
    label_height = 36
    rows = math.ceil(len(frames) / columns)
    canvas = Image.new("RGB", (columns * FRAME, rows * (FRAME + label_height)), "#eeeeee")
    draw = ImageDraw.Draw(canvas)
    for index, frame in enumerate(frames):
        row, col = divmod(index, columns)
        x, y = col * FRAME, row * (FRAME + label_height)
        draw.text((x + 8, y + 8), labels[index], fill="#111111", font=font)
        canvas.paste(checker(frame), (x, y + label_height))
    canvas.save(path)


def write_gif(frames: list[Image.Image], path: Path, delay: int) -> None:
    previews = [checker(frame).convert("P", palette=Image.Palette.ADAPTIVE, colors=256) for frame in frames]
    previews[0].save(
        path,
        save_all=True,
        append_images=previews[1:],
        duration=delay,
        loop=0,
        disposal=2,
        optimize=False,
    )


def main() -> None:
    inputs = (RAW_K3, PROMPT_PATH, RAW_K5, K2_REFERENCE, K4_TRIAL02, V3, LEGACY_SOURCE, ACCEPTED_K5)
    missing = [str(path) for path in inputs if not path.is_file()]
    if missing:
        raise SystemExit("Missing required inputs: " + ", ".join(missing))

    expected_hashes = (
        (RAW_K3, EXPECTED_RAW_K3_SHA256, "raw K3 trial03"),
        (V3, EXPECTED_V3_SHA256, "installed v3 North strip"),
        (K4_TRIAL02, EXPECTED_K4_TRIAL02_FILE_SHA256, "normalized K4 trial02"),
        (ACCEPTED_K5, EXPECTED_K5_FILE_SHA256, "accepted normalized K5"),
        (LEGACY_SOURCE, EXPECTED_LEGACY_SHA256, "immutable legacy source North strip"),
    )
    for path, expected, label in expected_hashes:
        actual = sha_path(path)
        if actual != expected:
            raise SystemExit(f"Pinned {label} hash mismatch: {actual}")

    raw_k4 = SOURCE_DIR / "north-canonical-03-trial-02-generated.png"
    if sha_path(raw_k4) != EXPECTED_K4_RAW_SHA256:
        raise SystemExit("Pinned trial02 raw K4-role source hash mismatch")
    k4_manifest = json.loads((SOURCE_DIR / "north-k03-trial02-manifest.json").read_text(encoding="utf-8"))
    if k4_manifest["normalization"]["fixed_scale"] != FROZEN_SCALE:
        raise SystemExit("Trial02 K4 role does not use the frozen K5 scale")
    prompt_hash = sha_path(PROMPT_PATH)
    if EXPECTED_PROMPT_SHA256 and prompt_hash != EXPECTED_PROMPT_SHA256:
        raise SystemExit("Pinned trial03 prompt hash mismatch")
    prompt_text = PROMPT_PATH.read_text(encoding="utf-8").strip()

    v3 = Image.open(V3).convert("RGBA")
    legacy = Image.open(LEGACY_SOURCE).convert("RGBA")
    accepted_k5 = Image.open(ACCEPTED_K5).convert("RGBA")
    trial02_k4 = Image.open(K4_TRIAL02).convert("RGBA")
    raw_k3 = Image.open(RAW_K3).convert("RGBA")
    if v3.size != (FRAME * FRAME_COUNT, FRAME) or legacy.size != v3.size:
        raise SystemExit(f"Expected native 8x512 strips; got v3={v3.size}, legacy={legacy.size}")
    if trial02_k4.size != (FRAME, FRAME) or accepted_k5.size != (FRAME, FRAME):
        raise SystemExit("A normalized candidate is not a native 512x512 cell")
    if raw_k3.size != (1254, 1254) or raw_k3.getchannel("A").getextrema() != (0, 255):
        raise SystemExit(f"Unexpected trial03 master dimensions/transparency: {raw_k3.size}")

    # Confirm current installed v3 carries accepted K5 and its separately-owned K7 cleanup.
    v3_cells = [v3.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(FRAME_COUNT)]
    legacy_cells = [legacy.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(FRAME_COUNT)]
    if v3_cells[4].tobytes() != accepted_k5.tobytes():
        raise SystemExit("Installed v3 K5 does not match accepted trial06")
    if v3_cells[6].tobytes() == legacy_cells[6].tobytes():
        raise SystemExit("Installed v3 K7 no longer differs from immutable legacy source; cleanup not confirmed")

    raw_bbox = visible_bbox(raw_k3)
    if raw_bbox is None:
        raise SystemExit("Trial03 master has no visible pixels")
    cropped = raw_k3.crop(raw_bbox)
    scaled_size = (round(cropped.width * FROZEN_SCALE), round(cropped.height * FROZEN_SCALE))
    scaled = cropped.resize(scaled_size, Image.Resampling.LANCZOS)
    scaled_bbox = visible_bbox(scaled)
    if scaled_bbox is None:
        raise SystemExit("Normalized K3 trial03 vanished")

    normalized_k3 = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    head_center_from_crop = (RAW_HEAD_CENTER_X - raw_bbox[0]) * FROZEN_SCALE
    paste_x = round(TORSO_CENTER_X - head_center_from_crop)
    paste_y = GROUND_Y - scaled_bbox[3]
    normalized_k3.alpha_composite(scaled, (paste_x, paste_y))
    final_bbox = visible_bbox(normalized_k3)
    if final_bbox is None or final_bbox[3] != GROUND_Y:
        raise SystemExit(f"K3 trial03 baseline mismatch: {final_bbox}")

    # K4 is the exact prior trial02 pixel cell, now only relabeled as knee-up/recovery.
    frames = list(v3_cells)
    frames[2] = normalized_k3
    frames[3] = trial02_k4

    # The proposal is separate; every cell outside K3/K4 must remain exact to installed v3.
    for index in (0, 1, 4, 5, 6, 7):
        if frames[index].tobytes() != v3_cells[index].tobytes():
            raise SystemExit(f"Untouched installed v3 cell K{index + 1} changed")
    if frames[3].tobytes() != trial02_k4.tobytes():
        raise SystemExit("K4 role remapping changed trial02 pixels")

    compare_indices = {"K2 installed v3": 1, "K4 trial02": 3, "K5 installed v3": 4}
    scale_comparison = {}
    k3_height = visible_bbox(normalized_k3)[3] - visible_bbox(normalized_k3)[1]
    for label, index in compare_indices.items():
        other = trial02_k4 if label == "K4 trial02" else v3_cells[index]
        bbox = visible_bbox(other)
        height = bbox[3] - bbox[1] if bbox else None
        head_bbox = orange_head_bbox(other)
        scale_comparison[label] = {
            "visible_height_px": height,
            "k3_height_delta_pct": ((k3_height / height) - 1) * 100 if height else None,
            "orange_head_ears_hue_bbox_y_lt_275": list(head_bbox) if head_bbox else None,
            "orange_head_ears_mask_width_px": head_bbox[2] - head_bbox[0] if head_bbox else None,
        }
    k3_head_bbox = orange_head_bbox(normalized_k3)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    K3_NORMALIZED.write_bytes(png_bytes(normalized_k3))
    strip = Image.new("RGBA", (FRAME * FRAME_COUNT, FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME, 0))
    PROPOSAL.write_bytes(png_bytes(strip))

    labels = list(LABELS)
    contact(frames, labels, FULL8_CONTACT, columns=4)
    neighbor_frames = [frames[index] for index in (1, 2, 3, 4)]
    neighbor_labels = ["K2 installed v3 / left support", "K3 trial03 / compact right passing", "K4 trial02 / knee-up recovery", "K5 installed v3 / corrected contact"]
    contact(neighbor_frames, neighbor_labels, NEIGHBOR_CONTACT, columns=4)
    contact(v3_cells + frames, [f"Installed v3 / {label}" for label in LABELS] + [f"Proposal / {label}" for label in labels], ORIGINAL_VS_PROPOSAL, columns=4)
    write_gif(frames, NOMINAL_GIF, 130)
    write_gif(frames, HALF_SPEED_GIF, 260)

    output_hashes = {
        "normalized_k3_sha256": sha_path(K3_NORMALIZED),
        "proposal_strip_sha256": sha_path(PROPOSAL),
        "neighbor_contact_sha256": sha_path(NEIGHBOR_CONTACT),
        "full8_contact_sha256": sha_path(FULL8_CONTACT),
        "original_vs_proposal_contact_sha256": sha_path(ORIGINAL_VS_PROPOSAL),
        "nominal_gif_sha256": sha_path(NOMINAL_GIF),
        "half_speed_gif_sha256": sha_path(HALF_SPEED_GIF),
    }
    manifest = {
        "version": 1,
        "batch": "luna-player-north-k03trial03-k04trial02-v3-review-v1",
        "status": "staged for root review only; no runtime integration",
        "source_masters": {
            "trial03_k3": {
                "path": RAW_K3.relative_to(ROOT).as_posix(),
                "sha256": sha_path(RAW_K3),
                "cache_path": "C:/Users/johnw/.codex/generated_images/01a17bec-a216-72b3-ac73-5e56d3da1c90/exec-50a5647b-b2f8-40ed-bc55-b65540e383f6.png",
                "imagegen_generation_id": "exec-50a5647b-b2f8-40ed-bc55-b65540e383f6",
                "dimensions_px": list(raw_k3.size),
                "alpha_bbox_gt_16": list(raw_bbox),
                "transparent_background": True,
                "exact_prompt_path": PROMPT_PATH.relative_to(ROOT).as_posix(),
                "prompt_sha256": prompt_hash,
            },
            "trial02_k4": {
                "raw_path": raw_k4.relative_to(ROOT).as_posix(),
                "raw_sha256": sha_path(raw_k4),
                "normalized_path": K4_TRIAL02.relative_to(ROOT).as_posix(),
                "normalized_sha256": sha_path(K4_TRIAL02),
                "role": "root-classified provisional compact knee-up / heel-recovery key; exact trial02 cell pixels reused",
            },
            "installed_v3_base": {
                "path": V3.relative_to(ROOT).as_posix(),
                "sha256": sha_path(V3),
                "accepted_k5_normalized_sha256": sha_path(ACCEPTED_K5),
                "k5_matches_accepted_trial06": True,
                "k7_differs_from_immutable_legacy": True,
                "k7_role": "retain root-installed detached-line cleanup unchanged",
            },
            "legacy_north_source_preserved": {
                "path": LEGACY_SOURCE.relative_to(ROOT).as_posix(),
                "sha256": sha_path(LEGACY_SOURCE),
            },
        },
        "imagegen_provenance": {
            "generation_id": "exec-50a5647b-b2f8-40ed-bc55-b65540e383f6",
            "recovered_cache_path": "C:/Users/johnw/.codex/generated_images/01a17bec-a216-72b3-ac73-5e56d3da1c90/exec-50a5647b-b2f8-40ed-bc55-b65540e383f6.png",
            "recovered_cache_timestamp_local": "2026-10-27T10:58:30-04:00",
            "returned_wrapper_metadata": "The original exec wrapper did not surface result type/keys or image blocks; root recovered the PNG from the generated-image cache. No retry was made.",
            "exact_prompt_path": PROMPT_PATH.relative_to(ROOT).as_posix(),
            "exact_prompt_sha256": prompt_hash,
            "exact_prompt": prompt_text,
            "references": [
                {
                    "path": raw_k4.relative_to(ROOT).as_posix(),
                    "sha256": sha_path(raw_k4),
                    "role": "editable trial02 K3 source; identity, body and outfit preserved while changing lower-body pose",
                },
                {
                    "path": RAW_K5.relative_to(ROOT).as_posix(),
                    "sha256": sha_path(RAW_K5),
                    "role": "accepted K5 design consistency, fixed scale and limb anatomy; contact pose not copied",
                },
                {
                    "path": K2_REFERENCE.relative_to(ROOT).as_posix(),
                    "sha256": sha_path(K2_REFERENCE),
                    "role": "neighboring K2 support-foot and baseline cue",
                },
            ],
        },
        "normalization": {
            "policy": "one frozen K5 uniform scale for K3; crop and translation only, no per-cell scale or deformation; K4 uses existing normalized trial02 pixels unchanged",
            "fixed_scale": FROZEN_SCALE,
            "resampling": "Pillow Lanczos",
            "trial03_raw_crop_xyxy": list(raw_bbox),
            "trial03_scaled_size_px": list(scaled_size),
            "trial03_scaled_visible_bbox_xyxy": list(scaled_bbox),
            "raw_head_center_x_anchor": RAW_HEAD_CENTER_X,
            "target_head_center_x": TORSO_CENTER_X,
            "ground_baseline_y": GROUND_Y,
            "paste_xy": [paste_x, paste_y],
            "normalized_k3_visible_bbox_xyxy": list(final_bbox),
            "normalized_k3_visible_height_px": final_bbox[3] - final_bbox[1],
            "accepted_k5_visible_height_px": visible_bbox(accepted_k5)[3] - visible_bbox(accepted_k5)[1],
            "game_scale_comparison": {
                "trial03_orange_head_ears_hue_bbox_y_lt_275": list(k3_head_bbox) if k3_head_bbox else None,
                "trial03_orange_head_ears_mask_width_px": k3_head_bbox[2] - k3_head_bbox[0] if k3_head_bbox else None,
                "trial03_vs_neighbors": scale_comparison,
                "measurement_note": "Orange mask uses alpha>16, y<275, R>1.12*G and R>1.18*B to exclude lower arms approximately; compare as a rough head/ear scale indicator, not a semantic segmentation.",
            },
            "no_per_cell_fit": True,
        },
        "selection": [
            {"cell": 1, "role": "installed v3 original", "source_cell_pixel_sha256": pixel_sha(v3_cells[0])},
            {"cell": 2, "role": "installed v3 left-support key", "source_cell_pixel_sha256": pixel_sha(v3_cells[1])},
            {"cell": 3, "role": "trial03 compact right-passing candidate", "source_cell_pixel_sha256": pixel_sha(frames[2])},
            {"cell": 4, "role": "trial02 reclassified as provisional knee-up/recovery", "source_cell_pixel_sha256": pixel_sha(frames[3])},
            {"cell": 5, "role": "installed v3 corrected trial06 right contact", "source_cell_pixel_sha256": pixel_sha(v3_cells[4])},
            {"cell": 6, "role": "installed v3 original", "source_cell_pixel_sha256": pixel_sha(v3_cells[5])},
            {"cell": 7, "role": "installed v3 root cleanup retained", "source_cell_pixel_sha256": pixel_sha(v3_cells[6])},
            {"cell": 8, "role": "installed v3 original", "source_cell_pixel_sha256": pixel_sha(v3_cells[7])},
        ],
        "review_notes": [
            "Trial03 raw master visually shows exactly two ears, two arms, two legs, one right-side pouch with one red and one yellow tool.",
            "Trial03 right boot is compact and near the ground, with a narrow visible sole band instead of a broad camera-facing sole; owner review remains pending.",
            "The proposal is based on installed v3 so untouched K1/K2/K5/K6/K7/K8 cells, including the separate K7 cleanup, remain exact.",
            "The game-scale comparison shows K3 at 421px visible height versus K2 at 410px and K5 at 416px; K4 trial02 is 424px. K3 is 2.7% taller than K2 and 1.2% taller than K5, with no independent fitting.",
            "The rough orange head/ear mask is 191px wide for K3, 193px for K4, 194px for K5 and 176px for K2; the original K2 head appears smaller than the new masters, so scale continuity remains a review issue.",
            "No sprite-motion auditor or runtime smoke check was run because this is staged art only; root owns integration review.",
        ],
        "outputs": {key: {"path": path.relative_to(ROOT).as_posix(), "sha256": output_hashes[key]} for key, path in {
            "normalized_k3_sha256": K3_NORMALIZED,
            "proposal_strip_sha256": PROPOSAL,
            "neighbor_contact_sha256": NEIGHBOR_CONTACT,
            "full8_contact_sha256": FULL8_CONTACT,
            "original_vs_proposal_contact_sha256": ORIGINAL_VS_PROPOSAL,
            "nominal_gif_sha256": NOMINAL_GIF,
            "half_speed_gif_sha256": HALF_SPEED_GIF,
        }.items()},
        "gif_delays_ms": {"nominal": 130, "half_speed": 260},
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"K3 trial03 normalized sha256: {output_hashes['normalized_k3_sha256']}; bbox={final_bbox}; height={final_bbox[3] - final_bbox[1]}")
    print(f"K4 trial02 exact candidate pixel sha256: {pixel_sha(trial02_k4)}")
    print(f"Proposal sha256: {output_hashes['proposal_strip_sha256']}")
    print(f"Installed v3 base sha256: {sha_path(V3)}; K7 cleanup retained")
    print(f"Manifest: {MANIFEST}")


if __name__ == "__main__":
    main()
