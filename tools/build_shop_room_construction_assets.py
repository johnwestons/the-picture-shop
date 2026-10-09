"""Extract the four room-wide expansion construction stages from reviewed atlases."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "assets/source/warehouse-expansion-v1/rooms"
OUTPUT_ROOT = ROOT / "assets/generated"
MANIFEST = SOURCE_ROOT / "construction-progress-manifest.json"
OUTPUT_SIZE = (960, 678)
ROOMS = {
    "floor": SOURCE_ROOT / "utility-room-construction-progress-atlas-v1.png",
    "storage": SOURCE_ROOT / "storage-room-construction-progress-atlas-v1.png",
    "breakroom": SOURCE_ROOT / "breakroom-construction-progress-atlas-v1.png",
}
STAGE_NAMES = ("foundation", "framing", "assembly", "finishing")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_manifest() -> None:
    records = []
    for room_type, path in ROOMS.items():
        records.append({
            "room_type": room_type,
            "source": path.relative_to(ROOT).as_posix(),
            "sha256": digest(path),
            "generator": "OpenAI imagegen",
            "layout": {
                "columns": 2,
                "rows": 2,
                "stage_cells": {
                    name: index + 1 for index, name in enumerate(STAGE_NAMES)
                },
            },
        })
    MANIFEST.write_text(
        json.dumps({"version": 1, "rooms": records}, indent=2) + "\n",
        encoding="utf-8",
    )


def build() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    records = {record.get("room_type"): record for record in manifest.get("rooms", [])}
    generated = []
    for room_type, path in ROOMS.items():
        record = records.get(room_type)
        expected_source = path.relative_to(ROOT).as_posix()
        if not record or record.get("source") != expected_source or record.get("sha256") != digest(path):
            raise ValueError(f"Construction source changed after review: {expected_source}")
        if record.get("layout", {}).get("stage_cells") != {
            name: index + 1 for index, name in enumerate(STAGE_NAMES)
        }:
            raise ValueError(f"Construction stage order is stale: {room_type}")

        with Image.open(path) as source_file:
            source = source_file.convert("RGBA")
        if source.size != (1536, 1024):
            raise ValueError(f"Expected a 1536x1024 2x2 construction atlas: {expected_source}")

        for stage, stage_name in enumerate(STAGE_NAMES, start=1):
            column = (stage - 1) % 2
            row = (stage - 1) // 2
            crop = source.crop((column * 768, row * 512, (column + 1) * 768, (row + 1) * 512))
            room = crop.resize(OUTPUT_SIZE, Image.Resampling.LANCZOS)
            output = OUTPUT_ROOT / f"shop-{room_type}-construction-stage-{stage}.png"
            room.save(output, optimize=True)
            generated.append({
                "path": output.relative_to(ROOT).as_posix(),
                "stage": stage,
                "name": stage_name,
                "width": OUTPUT_SIZE[0],
                "height": OUTPUT_SIZE[1],
                "sha256": digest(output),
            })

    manifest["generated"] = generated
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Built {len(generated)} room-wide construction backgrounds.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--write-manifest", action="store_true",
                        help="Record reviewed source atlas digests before the first build")
    args = parser.parse_args()
    if args.write_manifest:
        write_manifest()
    build()
