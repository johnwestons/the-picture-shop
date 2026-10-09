"""Build anchored, five-view rabbit-worker task loops from reviewed atlases."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

import build_visitor_character_assets as visitor


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "assets/source/player-actions-v2"
STANDING_SOURCE = SOURCE_DIR / "rabbit-worker-standing-work-v2.png"
FORKLIFT_SOURCE = SOURCE_DIR / "rabbit-worker-forklift-work-v2.png"
COMPUTER_SOURCE = SOURCE_DIR / "rabbit-worker-computer-use-v1.png"
PHONE_SOURCE = SOURCE_DIR / "rabbit-worker-answer-phone-v1.png"
MANIFEST = SOURCE_DIR / "source-manifest.json"
SIZE, HEIGHT, WIDTH, BASELINE = 256, 192, 232, 229
DIRECTIONS = ("east", "northeast", "north", "southeast", "south")
WORK_ACTIONS = ("work_cutter", "work_press", "work_wrapping", "work_task")
SOURCE_SETS = {
    "standing_work": (STANDING_SOURCE, WORK_ACTIONS, "work"),
    "forklift_operation": (FORKLIFT_SOURCE, ("operate_forklift",), "operate_forklift"),
    "computer_use": (COMPUTER_SOURCE, ("use_computer",), "use_computer"),
    "answer_phone": (PHONE_SOURCE, ("answer_phone",), "answer_phone"),
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_manifest() -> None:
    records = []
    for action_set, (path, actions, _prefix) in SOURCE_SETS.items():
        records.append({
            "character": "rabbit-worker",
            "action_set": action_set,
            "source": path.relative_to(ROOT).as_posix(),
            "sha256": digest(path),
            "generator": "OpenAI imagegen",
            "layout": {"columns": 4, "rows": 5, "row_views": list(DIRECTIONS),
                       "frame_order": "left to right"},
            "actions": list(actions),
        })
    MANIFEST.write_text(json.dumps({"version": 2, "sources": records}, indent=2) + "\n",
                        encoding="utf-8")


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
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    records = {record.get("action_set"): record for record in manifest.get("sources", [])}
    source_images = {}
    for action_set, (path, actions, _prefix) in SOURCE_SETS.items():
        record = records.get(action_set)
        if not record or record.get("sha256") != digest(path):
            raise ValueError(f"Source atlas changed after review: {path.relative_to(ROOT)}")
        if record.get("source") != path.relative_to(ROOT).as_posix():
            raise ValueError(f"Player action manifest points elsewhere: {action_set}")
        if record.get("actions") != list(actions) or record.get("layout", {}).get("row_views") != list(DIRECTIONS):
            raise ValueError(f"Player action manifest layout is stale: {action_set}")
        source_image = Image.open(path).convert("RGBA")
        if source_image.width < 4 or source_image.height < 5:
            raise ValueError(f"Expected a 4-column by 5-row atlas: {path}")
        source_images[action_set] = source_image

    visitor.SIZE, visitor.HEIGHT, visitor.WIDTH, visitor.BASELINE = SIZE, HEIGHT, WIDTH, BASELINE
    runtime = ROOT / "assets/generated/characters/rabbit-worker"
    runtime.mkdir(parents=True, exist_ok=True)
    action_strips = {action_set: {} for action_set in SOURCE_SETS}
    action_metadata: dict[str, dict[str, tuple[list[dict[str, float]], list[list[int]]]]] = {}
    for action_set, (source_path, actions, prefix) in SOURCE_SETS.items():
        source_image = source_images[action_set]
        for row, direction in enumerate(DIRECTIONS):
            cells = []
            for column in range(4):
                x0 = round(column * source_image.width / 4)
                x1 = round((column + 1) * source_image.width / 4)
                y0 = round(row * source_image.height / 5)
                y1 = round((row + 1) * source_image.height / 5)
                cells.append(source_image.crop((x0, y0, x1, y1)))
            strip = visitor.pack(cells, cleanup_area=1600)
            action_strips[action_set][direction] = strip
            strip.save(runtime / f"{prefix}_{direction}.png", optimize=True)

            anchors, metrics = [], []
            for frame_index in range(4):
                frame = strip.crop((frame_index * SIZE, 0, (frame_index + 1) * SIZE, SIZE))
                box = visitor.bounds(frame)
                anchors.append({"x": round(visitor.body_axis(frame, box), 2), "y": float(box[3])})
                metrics.append(list(box))
            for action in actions:
                key = action if direction == "east" else f"{action}_{direction}"
                action_metadata[key] = (anchors, metrics)

    anchors = {key: value[0] for key, value in action_metadata.items()}
    metrics = {key: value[1] for key, value in action_metadata.items()}
    (ROOT / "src/player_action_anchors.lua").write_text(
        "-- Generated by tools/build_player_action_assets.py.\nreturn " + lua({"rabbit-worker": anchors}) + "\n",
        encoding="utf-8")
    (ROOT / "src/player_action_metrics.lua").write_text(
        "-- Generated by tools/build_player_action_assets.py.\nreturn " + lua({"rabbit-worker": metrics}) + "\n",
        encoding="utf-8")
    print("Built five-view, four-frame rabbit-worker task action strips.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--write-manifest", action="store_true",
                        help="Record the reviewed source atlas digest before the first build")
    args = parser.parse_args()
    if args.write_manifest:
        write_manifest()
    build()
