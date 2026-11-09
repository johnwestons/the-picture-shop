"""Mechanically crop and downsample the selected bridge-rail sprite."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "assets/source/commute-bridge-rails-v1"
SOURCE = SOURCE_DIR / "center-post-variant02-imagegen-source.png"
PROMPTS = SOURCE_DIR / "imagegen-prompts.json"
TARGET_DIR = ROOT / "assets/commute/bridge"
TARGET = TARGET_DIR / "rail-bay.png"
MANIFEST = TARGET_DIR / "rail-bay-manifest.json"
REVIEW_DIR = ROOT / "output/commute-bridge-rails"
REVIEW = REVIEW_DIR / "rail-bay-tiling-review.png"

MAX_WIDTH = 2048
ALPHA_TRIM_THRESHOLD = 8
SPAN_METERS = 2.8
HEIGHT_METERS = 0.9


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    TARGET_DIR.mkdir(parents=True, exist_ok=True)
    REVIEW_DIR.mkdir(parents=True, exist_ok=True)

    source = Image.open(SOURCE).convert("RGBA")
    if source.size != (2172, 724):
        raise ValueError(f"Unexpected generated source dimensions: {source.size}")

    alpha = source.getchannel("A")
    threshold_mask = alpha.point(
        lambda value: 255 if value >= ALPHA_TRIM_THRESHOLD else 0
    )
    crop = threshold_mask.getbbox()
    if crop != (0, 108, 2172, 634):
        raise ValueError(f"Unexpected alpha silhouette bounds: {crop}")

    bay = source.crop(crop)
    # Clear generator residue below the documented low-alpha matte threshold;
    # pixels belonging to the painted subject and its antialiased edge remain.
    bay_alpha = bay.getchannel("A")
    bay_alpha = bay_alpha.point(
        lambda value: value if value >= ALPHA_TRIM_THRESHOLD else 0
    )
    bay.putalpha(bay_alpha)

    scale = min(1.0, MAX_WIDTH / bay.width)
    if scale < 1:
        target_size = (MAX_WIDTH, round(bay.height * scale))
        bay = bay.resize(target_size, Image.Resampling.LANCZOS)
    bay.save(TARGET, optimize=True)

    # A simple repeated preview reveals any gaps where adjacent bays meet.
    tile_scale = min(1000 / bay.width, 240 / bay.height)
    tile_size = (round(bay.width * tile_scale), round(bay.height * tile_scale))
    tile = bay.resize(tile_size, Image.Resampling.LANCZOS)
    preview = Image.new("RGBA", (tile.width * 3, tile.height), (240, 240, 240, 255))
    draw = ImageDraw.Draw(preview)
    grid = 18
    for y in range(0, preview.height, grid):
        for x in range(0, preview.width, grid):
            if (x // grid + y // grid) % 2:
                draw.rectangle((x, y, x + grid - 1, y + grid - 1), fill=(208, 208, 208, 255))
    for index in range(3):
        preview.alpha_composite(tile, (index * tile.width, 0))
    preview.save(REVIEW, optimize=True)

    prompts = json.loads(PROMPTS.read_text(encoding="utf-8"))
    selected = next(
        item for item in prompts["generations"]
        if item["result"] == "selected_for_development_integration"
    )
    manifest = {
        "version": 1,
        "status": "development_integrated_review_candidate",
        "generator": "built-in imagegen",
        "generationId": selected["id"],
        "source": SOURCE.relative_to(ROOT).as_posix(),
        "sourceSha256": sha256(SOURCE),
        "promptLog": PROMPTS.relative_to(ROOT).as_posix(),
        "promptLogSha256": sha256(PROMPTS),
        "referenceSource": selected["reference"],
        "runtime": TARGET.relative_to(ROOT).as_posix(),
        "runtimeSha256": sha256(TARGET),
        "runtimeSize": list(bay.size),
        "sourceSize": list(source.size),
        "sourceCrop": list(crop),
        "alphaTrimThreshold": ALPHA_TRIM_THRESHOLD,
        "packing": "alpha crop and uniform downsample only; no paint edits",
        "registration": {
            "view": "front elevation",
            "spanMeters": SPAN_METERS,
            "railHeightMeters": HEIGHT_METERS,
            "postOffsetMeters": SPAN_METERS / 2,
            "baseAnchor": "bottom edge of sprite maps to bridge deck height",
        },
        "reviewPreview": REVIEW.relative_to(ROOT).as_posix(),
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Packed {TARGET.relative_to(ROOT)}: {bay.width}x{bay.height} px")
    print(f"Tiling preview: {REVIEW.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
