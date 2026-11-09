"""Pack imagegen bridge-concrete sources without changing their painted content."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SOURCE_V1 = ROOT / "assets/source/commute-bridge-concrete-v1"
SOURCE_V2 = ROOT / "assets/source/commute-bridge-concrete-v2"
SOURCE_V3 = ROOT / "assets/source/commute-bridge-concrete-v3"
TARGET_DIR = ROOT / "assets/commute/bridge"
OUTPUT_DIR = ROOT / "output/commute-bridge-concrete"
PROMPTS = SOURCE_V1 / "imagegen-prompts.json"
ALPHA_THRESHOLD = 8
SIDE_BAY_METERS = 4.8
SIDE_PROFILE_METERS = 3.0
SIDE_DECK_LINE_FROM_TOP = 0.53
END_PROFILE_METERS = 3.0
END_DECK_LINE_FROM_TOP = 0.48
PIER_DECK_WIDTH_METERS = 5.0
PIER_SOURCE_TOP_CROP_PX = 0


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def trim_alpha(source: Path, target: Path, max_dimension: int, top_crop: int = 0) -> dict:
    image = Image.open(source).convert("RGBA")
    if top_crop:
        image = image.crop((0, top_crop, image.width, image.height))
    alpha = image.getchannel("A")
    box = alpha.point(lambda value: 255 if value >= ALPHA_THRESHOLD else 0).getbbox()
    if not box:
        raise ValueError(f"No visible sprite pixels in {source}")
    image = image.crop(box)
    image.putalpha(image.getchannel("A").point(
        lambda value: value if value >= ALPHA_THRESHOLD else 0
    ))
    scale = min(1.0, max_dimension / max(image.size))
    if scale < 1:
        size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
        image = image.resize(size, Image.Resampling.LANCZOS)
    image.save(target, optimize=True)
    return {"sourceSize": list(Image.open(source).size), "sourceCrop": list(box), "topCropPx": top_crop,
            "runtimeSize": list(image.size), "alphaThreshold": ALPHA_THRESHOLD}


def make_preview(image: Image.Image, path: Path, background=(222, 224, 221, 255)) -> None:
    canvas = Image.new("RGBA", image.size, background)
    canvas.alpha_composite(image)
    canvas.convert("RGB").save(path, quality=93)


def main() -> None:
    TARGET_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    side_source = SOURCE_V1 / "concrete-side-bay-imagegen-source.png"
    pier_source = SOURCE_V1 / "concrete-pier-imagegen-source.png"
    cap_source = SOURCE_V3 / "parapet-cap-top-imagegen-source.png"
    end_block_source = SOURCE_V3 / "parapet-end-block-imagegen-source.png"
    asphalt_source = SOURCE_V2 / "asphalt-fine-imagegen-source.png"
    side_target = TARGET_DIR / "concrete-side-bay.png"
    pier_target = TARGET_DIR / "concrete-pier.png"
    cap_target = TARGET_DIR / "concrete-parapet-cap.png"
    end_block_target = TARGET_DIR / "concrete-parapet-end-block.png"
    asphalt_target = TARGET_DIR / "asphalt.png"

    side_info = trim_alpha(side_source, side_target, 2048)
    pier_info = trim_alpha(pier_source, pier_target, 1024, PIER_SOURCE_TOP_CROP_PX)
    end_block_info = trim_alpha(end_block_source, end_block_target, 1024)
    cap = Image.open(cap_source).convert("RGB")
    cap = cap.resize((512, 128), Image.Resampling.LANCZOS)
    cap.save(cap_target, optimize=True)
    asphalt = Image.open(asphalt_source).convert("RGB")
    asphalt = asphalt.resize((256, 256), Image.Resampling.LANCZOS)
    asphalt.save(asphalt_target, optimize=True)

    side = Image.open(side_target).convert("RGBA")
    tile_scale = min(1300 / side.width, 280 / side.height)
    tile = side.resize((round(side.width * tile_scale), round(side.height * tile_scale)), Image.Resampling.LANCZOS)
    preview = Image.new("RGBA", (tile.width * 3, tile.height), (220, 222, 220, 255))
    for index in range(3):
        preview.alpha_composite(tile, (index * tile.width, 0))
    make_preview(preview, OUTPUT_DIR / "concrete-side-tiling-review.png")
    make_preview(Image.open(pier_target).convert("RGBA"), OUTPUT_DIR / "concrete-pier-review.png")
    make_preview(Image.open(end_block_target).convert("RGBA"), OUTPUT_DIR / "concrete-parapet-end-block-review.png")
    Image.open(cap_target).save(OUTPUT_DIR / "concrete-parapet-cap-review.png")
    Image.open(asphalt_target).save(OUTPUT_DIR / "asphalt-review.png")

    prompt_log = SOURCE_V3 / "imagegen-prompts.json"
    prompts = json.loads(prompt_log.read_text(encoding="utf-8"))
    source_records = {
        "side": (side_source, side_target, side_info),
        "pier": (pier_source, pier_target, pier_info),
        "parapet-cap-top": (cap_source, cap_target, {"sourceSize": list(Image.open(cap_source).size), "runtimeSize": [512, 128]}),
        "parapet-end-block": (end_block_source, end_block_target, end_block_info),
        "asphalt": (asphalt_source, asphalt_target, {"sourceSize": list(Image.open(asphalt_source).size), "runtimeSize": [256, 256]}),
    }
    for record in prompts["generations"]:
        name = record["asset"].replace("-imagegen-source.png", "")
        key = name
        source, runtime, packing = source_records[key]
        record.update({"sourceSha256": sha256(source), "runtime": runtime.relative_to(ROOT).as_posix(),
                      "runtimeSha256": sha256(runtime), "packing": packing})
    prompt_log.write_text(json.dumps(prompts, indent=2) + "\n", encoding="utf-8")

    manifest = {
        "version": 3,
        "status": "generated_development_review_candidate",
        "generator": "built-in imagegen",
        "promptLog": prompt_log.relative_to(ROOT).as_posix(),
        "promptLogSha256": sha256(prompt_log),
        "baseArtPromptLogs": [{"path": path.relative_to(ROOT).as_posix(), "sha256": sha256(path)} for path in (PROMPTS, SOURCE_V2 / "imagegen-prompts.json")],
        "alphaThreshold": ALPHA_THRESHOLD,
        "packing": "alpha-bound crop and low-alpha cleanup for sprites; uniform raster resampling for textures",
        "assets": {
            "concreteSideBay": {"source": side_source.relative_to(ROOT).as_posix(), "sourceSha256": sha256(side_source), "runtime": side_target.relative_to(ROOT).as_posix(), "runtimeSha256": sha256(side_target), **side_info, "registration": {"view": "side elevation", "spanMeters": SIDE_BAY_METERS, "totalProfileMeters": SIDE_PROFILE_METERS, "deckLineFromTop": SIDE_DECK_LINE_FROM_TOP}},
            "concretePier": {"source": pier_source.relative_to(ROOT).as_posix(), "sourceSha256": sha256(pier_source), "runtime": pier_target.relative_to(ROOT).as_posix(), "runtimeSha256": sha256(pier_target), **pier_info, "registration": {"view": "front elevation billboard with complete bearing beam and support legs", "deckWidthMeters": PIER_DECK_WIDTH_METERS, "baseAnchor": "terrain height", "topAnchor": "bearing beam meets fascia underside at deck height minus registered girder depth"}},
            "concreteParapetCap": {"source": cap_source.relative_to(ROOT).as_posix(), "sourceSha256": sha256(cap_source), "runtime": cap_target.relative_to(ROOT).as_posix(), "runtimeSha256": sha256(cap_target), "sourceSize": list(Image.open(cap_source).size), "runtimeSize": [512, 128], "registration": {"view": "top-down repeatable cap surface", "stripWidthMeters": 0.48, "tileMeters": 3.2}},
            "concreteParapetEndBlock": {"source": end_block_source.relative_to(ROOT).as_posix(), "sourceSha256": sha256(end_block_source), "runtime": end_block_target.relative_to(ROOT).as_posix(), "runtimeSha256": sha256(end_block_target), **end_block_info, "registration": {"view": "travel-direction billboard at each parapet corner", "widthMeters": 0.58, "heightMeters": SIDE_PROFILE_METERS * SIDE_DECK_LINE_FROM_TOP, "baseAnchor": "bridge deck height"}},
            "asphalt": {"source": asphalt_source.relative_to(ROOT).as_posix(), "sourceSha256": sha256(asphalt_source), "runtime": asphalt_target.relative_to(ROOT).as_posix(), "runtimeSha256": sha256(asphalt_target), "sourceSize": list(Image.open(asphalt_source).size), "runtimeSize": [256, 256], "registration": {"view": "top-down repeatable material", "tileMeters": 3.2}},
        },
        "rejectedCandidates": [{"runtime": "assets/commute/bridge/concrete-end-frame.png", "promptLog": "assets/source/commute-bridge-concrete-v2/imagegen-prompts.json", "reason": "Full-width cross-section read as a barrier across the lane in native end-on review; not referenced by runtime."}],
        "notes": "Terrain, road and parking surfaces remain generated geometry; bridge parapet sides, overhead caps, end blocks, piers, and asphalt material use generated 2D artwork. Bridge art does not change the road support or collision contract.",
        "reviews": [(OUTPUT_DIR / "concrete-side-tiling-review.png").relative_to(ROOT).as_posix(), (OUTPUT_DIR / "concrete-pier-review.png").relative_to(ROOT).as_posix(), (OUTPUT_DIR / "concrete-parapet-cap-review.png").relative_to(ROOT).as_posix(), (OUTPUT_DIR / "concrete-parapet-end-block-review.png").relative_to(ROOT).as_posix(), (OUTPUT_DIR / "asphalt-review.png").relative_to(ROOT).as_posix()],
    }
    (TARGET_DIR / "concrete-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Packed bridge side bay {side.width}x{side.height}; pier {Image.open(pier_target).size}; terminal {Image.open(end_block_target).size}; cap {Image.open(cap_target).size}; asphalt {Image.open(asphalt_target).size}")
    print(f"Review files: {OUTPUT_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
