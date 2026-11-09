#!/usr/bin/env python3
"""Copy accepted generated source sheets and existing idle art into the project."""

import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GENERATED = Path(r"C:\Users\johnw\.codex\generated_images\01a194d9-39bc-7503-abe7-d56b09a860b9")
RAW = ROOT / "assets/source/commute-rider-v3/raw"
SHEETS = {
    "walk_north-sheet.png": "exec-b2c48809-9edc-41d1-bbbc-fde53645e33b.png",
    "walk_northeast-sheet.png": "exec-d66bed17-b958-4ebe-84c1-13337db47a98.png",
    "walk_east-sheet.png": "exec-bac311f1-81da-483f-bd6e-5009837a1365.png",
    "walk_southeast-sheet.png": "exec-202e4f1a-faac-442c-a716-14f2531aa980.png",
    "walk_south-sheet.png": "exec-1adedc64-3f1c-43f7-ac04-aedd3c18bde3.png",
}

RAW.mkdir(parents=True, exist_ok=True)
for destination, source in SHEETS.items():
    shutil.copy2(GENERATED / source, RAW / destination)
    print(f"Imported {destination}", flush=True)
for direction in ("north", "northeast", "east", "southeast", "south"):
    source = ROOT / f"assets/staging/commute-rider-v2/idle_{direction}.png"
    shutil.copy2(source, RAW / source.name)
    print(f"Imported {source.name}", flush=True)
