"""Compile reviewed ride-action cell sheets into the 256px runtime strips."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/source/commute-ride-actions-v1"
RUNTIME = ROOT / "assets/generated/commute-ride-actions-v1"
CELL = 256

SHEETS = {
    "mount": ("mount-six-frame-source.png", 3, 2, 0.8, 224, 228),
    "dismount": ("dismount-six-frame-source.png", 3, 2, 1.1, 224, 200),
    "crash": ("crash-eight-frame-source.png", 4, 2, 1.35, 232, 214),
}


def compile_sheet(name: str, specification: tuple[str, int, int, float, int, int]) -> dict:
    source_name, columns, rows, duration, anchor_y, height = specification
    source_path = SOURCE / source_name
    source = Image.open(source_path).convert("RGBA")
    cell_width, cell_height = source.width // columns, source.height // rows
    frame_count = columns * rows
    strip = Image.new("RGBA", (CELL * frame_count, CELL), (0, 0, 0, 0))
    for frame_index in range(frame_count):
        x, y = frame_index % columns * cell_width, frame_index // columns * cell_height
        cell = source.crop((x, y, x + cell_width, y + cell_height))
        alpha = cell.getchannel("A").point(lambda value: 0 if value <= 8 else value)
        cell.putalpha(alpha)
        visible = alpha.point(lambda value: 255 if value > 100 else 0).getbbox()
        if visible is None:
            raise ValueError(f"empty frame {frame_index + 1} in {source_path}")
        frame_image = cell.copy()
        frame_image.thumbnail((CELL, CELL), Image.Resampling.LANCZOS)
        frame_x = (CELL - frame_image.width) // 2
        frame_y = (CELL - frame_image.height) // 2
        strip.alpha_composite(frame_image, (frame_index * CELL + frame_x, frame_y))

    path = RUNTIME / f"{name}-southeast.png"
    strip.save(path, optimize=True)
    mask_path = RUNTIME / f"{name}-southeast-mask.png"
    Image.new("RGBA", strip.size, (0, 0, 0, 0)).save(mask_path, optimize=True)
    return {
        "path": path.relative_to(ROOT).as_posix(),
        "maskPath": mask_path.relative_to(ROOT).as_posix(),
        "source": source_path.relative_to(ROOT).as_posix(),
        "sourceSha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "frameSize": CELL,
        "frameCount": frame_count,
        "duration": duration,
        "normalizationHeight": height,
        "anchor": [128, anchor_y],
    }


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    actions = {name: compile_sheet(name, spec) for name, spec in SHEETS.items()}
    registration = {
        "status": "runtime_approved",
        "character": "rabbit-worker",
        "direction": "southeast",
        "referenceHeight": CELL,
        "frameSize": CELL,
        "anchor": [128, 224],
        "actions": actions,
    }
    (RUNTIME / "registration.json").write_text(
        json.dumps(registration, indent=2) + "\n", encoding="utf-8"
    )
    lines = [
        "-- Authored southeast action strips for the helmeted motorcycle rider.",
        "return {status='runtime_approved',character='rabbit-worker',",
        "    direction='southeast',referenceHeight=256,frameSize=256,anchor={128,224},",
        "    actions={",
    ]
    for name, action in actions.items():
        lines.extend([
            f"        {name}={{path='{action['path']}',maskPath='{action['maskPath']}',",
            f"            duration={action['duration']},frameCount={action['frameCount']},",
            f"            frameSize=256,anchor={{{action['anchor'][0]},{action['anchor'][1]}}},",
            f"            normalizationHeight={action['normalizationHeight']},}},",
        ])
    lines.extend(["    },", "}", ""])
    (RUNTIME / "registration.lua").write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps(actions, indent=2))


if __name__ == "__main__":
    main()
