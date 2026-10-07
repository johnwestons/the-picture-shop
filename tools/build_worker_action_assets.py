"""Build normalized, anchored task loops from the reviewed worker atlases."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import build_visitor_character_assets as visitor


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/worker-actions-v1"
REVIEW = ROOT / "output/worker-actions-review"
SIZE = 256
BASELINE = 229
HEIGHT = 192
WIDTH = 232
ACTION_ROWS = {
    "work_cutter": 0,
    "work_press": 1,
    "work_wrapping": 2,
    "push_jack": 3,
}
CHARACTERS = {
    "cat-worker": "cat-worker-actions-v1.png",
    "tinker-fox-worker": "tinker-fox-worker-actions-v1.png",
    "ferret-engineer-worker": "ferret-engineer-worker-actions-v1.png",
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_source_manifest() -> None:
    records = []
    for character, filename in CHARACTERS.items():
        path = SOURCE / filename
        records.append({
            "character": character,
            "path": path.relative_to(ROOT).as_posix(),
            "sha256": digest(path),
            "generator": "OpenAI imagegen",
            "layout": {"columns": 4, "rows": 4, "frame_order": "left to right"},
            "rows": list(ACTION_ROWS),
        })
    (SOURCE / "source-manifest.json").write_text(
        json.dumps({"version": 1, "sources": records}, indent=2) + "\n",
        encoding="utf-8",
    )


def lua(value: object) -> str:
    if isinstance(value, dict):
        return "{ " + ", ".join(f'[{json.dumps(k)}] = {lua(v)}' for k, v in value.items()) + " }"
    if isinstance(value, list):
        return "{ " + ", ".join(lua(item) for item in value) + " }"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, (int, float)):
        return str(value)
    raise TypeError(f"Unsupported Lua metadata value: {type(value)!r}")


def build() -> None:
    visitor.SIZE, visitor.HEIGHT, visitor.WIDTH, visitor.BASELINE = SIZE, HEIGHT, WIDTH, BASELINE
    source_manifest = json.loads((SOURCE / "source-manifest.json").read_text(encoding="utf-8"))
    records = {record["character"]: record for record in source_manifest.get("sources", [])}
    REVIEW.mkdir(parents=True, exist_ok=True)
    combined_anchors: dict[str, dict[str, list[dict[str, float]]]] = {}
    combined_metrics: dict[str, dict[str, list[list[int]]]] = {}

    for character, filename in CHARACTERS.items():
        source = SOURCE / filename
        record = records.get(character)
        if not record or record.get("sha256") != digest(source):
            raise ValueError(f"Unreviewed or modified source atlas: {source.relative_to(ROOT)}")
        source_image = Image.open(source).convert("RGBA")
        if source_image.size != (1254, 1254):
            raise ValueError(f"Expected 1254x1254 4x4 atlas, got {source_image.size}: {source}")

        runtime = ROOT / "assets/generated/characters" / character
        runtime.mkdir(parents=True, exist_ok=True)
        anchors: dict[str, list[dict[str, float]]] = {}
        metrics: dict[str, list[list[int]]] = {}
        motion_spec_path = ROOT / "character-motion" / f"{character}.json"
        motion_spec = json.loads(motion_spec_path.read_text(encoding="utf-8"))
        animation_specs = motion_spec.setdefault("animations", {})

        contact = Image.new("RGBA", (4 * 142, 4 * 156), (35, 40, 39, 255))
        draw = ImageDraw.Draw(contact)
        try:
            font = ImageFont.truetype("arial.ttf", 12)
        except OSError:
            font = ImageFont.load_default()
        frames_by_action: dict[str, list[Image.Image]] = {}

        for action, row in ACTION_ROWS.items():
            cells = []
            for column in range(4):
                x0, x1 = round(column * source_image.width / 4), round((column + 1) * source_image.width / 4)
                y0, y1 = round(row * source_image.height / 4), round((row + 1) * source_image.height / 4)
                cells.append(source_image.crop((x0, y0, x1, y1)))

            # Small detached flecks and action-sheet boundary fragments are
            # outside the connected worker/prop silhouette; remove them before
            # normalization while retaining each complete hand-held prop.
            strip = visitor.pack(cells, cleanup_area=1600)
            runtime_path = runtime / f"{action}.png"
            strip.save(runtime_path, optimize=True)
            frame_records, bounds_records = [], []
            preview_frames = []
            for index in range(4):
                frame = strip.crop((index * SIZE, 0, (index + 1) * SIZE, SIZE))
                box = visitor.bounds(frame)
                frame_records.append({"x": round(visitor.body_axis(frame, box), 2), "y": float(box[3])})
                bounds_records.append(list(box))
                preview = frame.resize((126, 126), Image.Resampling.NEAREST)
                preview_frames.append(preview)

            # Draw four consecutive frames per action in its named row.
            row_index = list(ACTION_ROWS).index(action)
            draw.text((4, row_index * 156 + 2), action.replace("_", " ").upper(), fill=(226, 193, 111, 255), font=font)
            for index, preview in enumerate(preview_frames):
                contact.alpha_composite(preview, (index * 142 + 8, row_index * 156 + 24))
            frames_by_action[action] = [
                strip.crop((index * SIZE, 0, (index + 1) * SIZE, SIZE)) for index in range(4)
            ]
            anchors[action], metrics[action] = frame_records, bounds_records
            animation_specs[action] = {
                "path": runtime_path.relative_to(ROOT).as_posix(),
                "frame_width": SIZE,
                "frame_height": SIZE,
                "frame_count": 4,
                "loop": True,
                "role": "task_action",
                "fps": 4,
            }

        motion_spec["worker_action_contract"] = {
            "job_models": {
                "polar_115": "work_cutter",
                "heidelberg_10x15": "work_press",
                "skid_wrapper": "work_wrapping",
            },
            "future_pallet_jack_action": "push_jack",
            "frame_count": 4,
            "fps": 4,
            "baseline": BASELINE,
        }
        motion_spec_path.write_text(json.dumps(motion_spec, indent=2) + "\n", encoding="utf-8")
        contact.save(REVIEW / f"{character}-contact.png", optimize=True)
        combined_anchors[character], combined_metrics[character] = anchors, metrics
        for action, frames in frames_by_action.items():
            frames[0].save(REVIEW / f"{character}-{action}.gif", save_all=True,
                append_images=frames[1:], duration=250, loop=0, disposal=2)

    (ROOT / "src/worker_action_anchors.lua").write_text(
        "-- Generated by tools/build_worker_action_assets.py.\nreturn " + lua(combined_anchors) + "\n",
        encoding="utf-8",
    )
    (ROOT / "src/worker_action_metrics.lua").write_text(
        "-- Generated by tools/build_worker_action_assets.py.\nreturn " + lua(combined_metrics) + "\n",
        encoding="utf-8",
    )

    print(f"Built four 4-frame work/pallet-jack actions for {len(CHARACTERS)} workers.")
    print(f"Review images and GIFs: {REVIEW}")


if __name__ == "__main__":
    if "--prepare" in sys.argv:
        write_source_manifest()
        print(f"Pinned reviewed source atlases: {SOURCE / 'source-manifest.json'}")
    else:
        build()
