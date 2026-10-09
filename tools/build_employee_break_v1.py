"""Package reviewed four-row worker break atlases into aligned animation strips."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import build_visitor_character_assets as visitor

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/employee-break-v1"
REVIEW = ROOT / "output/employee-break-v1"
SIZE, HEIGHT, WIDTH, BASELINE = 256, 192, 232, 229
FPS = 1.5
CHARACTERS = {
    "cat-worker": "cat-worker-break-atlas-v1.png",
    "tinker-fox-worker": "tinker-fox-worker-break-atlas-v1.png",
    "ferret-engineer-worker": "ferret-engineer-worker-break-atlas-v1.png",
}
ACTION_ROWS = {
    "break_eat": 0,
    "break_water": 1,
    "break_coffee": 2,
    "break_idle": 3,
}
PROMPT_SET = {
    "use_case": "stylized-concept",
    "asset_type": "Production 2D game character sprite atlas; transparent 4x4 sheet; each row is one four-frame loop.",
    "reference_role": "Use each worker's existing chair_east sprite as the exact character identity, seated pose, and rendering-style reference.",
    "style": "Preserve the reference's polished hand-painted game-sprite style, shading, crisp silhouette, warm highlights, scale, and right-facing seated profile.",
    "composition": "Square transparent atlas, four equal columns and four equal rows, no gutters or labels; full worker centered in every cell at a shared scale and foot baseline.",
    "rows": [
        "Eating a small sandwich: hands on lap, lift sandwich, take a bite, lower it while chewing.",
        "Drinking water from a small clear bottle: bottle on lap, raise it, sip, lower it.",
        "Drinking coffee from a small plain paper cup: cup on lap, raise it, sip, lower it.",
        "Relaxed seated break idle with hands on lap and one brief blink.",
    ],
    "constraints": "Keep face, clothing, goggles, scarf or satchel, tail, body proportions, and seated legs from the reference. Animate only arms, hands, prop, and slight head tilt. Props stay in the worker's hands. No chair, backdrop, extra objects, shadows, borders, or text.",
    "subjects": {
        "cat-worker": "The exact black cat warehouse worker with orange goggles/scarf and orange tool satchel.",
        "tinker-fox-worker": "The exact orange fox warehouse worker with large ears, aviator goggles, red neckerchief, brown work clothes, and bushy tail.",
        "ferret-engineer-worker": "The exact brown-and-cream ferret engineer with blue-lensed goggles, teal work shirt, brown trousers, and orange tool satchel.",
    },
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lua(value: object) -> str:
    if isinstance(value, dict):
        return "{ " + ", ".join(f'[{json.dumps(key)}] = {lua(item)}' for key, item in value.items()) + " }"
    if isinstance(value, list):
        return "{ " + ", ".join(lua(item) for item in value) + " }"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, (int, float)):
        return str(value)
    raise TypeError(f"Unsupported Lua metadata value: {type(value)!r}")


def prepare() -> None:
    records = []
    for character, filename in CHARACTERS.items():
        path = SOURCE / filename
        records.append({
            "character": character,
            "path": path.relative_to(ROOT).as_posix(),
            "sha256": digest(path),
            "generator": "built-in image_gen",
            "layout": {"columns": 4, "rows": 4, "frame_order": "left to right"},
            "rows": list(ACTION_ROWS),
        })
    (SOURCE / "source-manifest.json").write_text(
        json.dumps({"version": 1, "sources": records}, indent=2) + "\n",
        encoding="utf-8",
    )
    (SOURCE / "prompts.json").write_text(json.dumps(PROMPT_SET, indent=2) + "\n", encoding="utf-8")


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
        atlas = Image.open(source).convert("RGBA")
        if atlas.width != atlas.height or atlas.width < 4:
            raise ValueError(f"Expected a square 4x4 atlas, got {atlas.size}: {source}")

        runtime = ROOT / "assets/generated/employee-break-v1" / character
        runtime.mkdir(parents=True, exist_ok=True)
        motion_spec_path = ROOT / "character-motion" / f"{character}.json"
        motion_spec = json.loads(motion_spec_path.read_text(encoding="utf-8"))
        animation_specs = motion_spec.setdefault("animations", {})
        anchors: dict[str, list[dict[str, float]]] = {}
        metrics: dict[str, list[list[int]]] = {}
        contact = Image.new("RGBA", (4 * 142, 4 * 156), (35, 40, 39, 255))
        draw = ImageDraw.Draw(contact)
        try:
            font = ImageFont.truetype("arial.ttf", 12)
        except OSError:
            font = ImageFont.load_default()

        for action, row in ACTION_ROWS.items():
            frames = []
            for column in range(4):
                x0, x1 = round(column * atlas.width / 4), round((column + 1) * atlas.width / 4)
                y0, y1 = round(row * atlas.height / 4), round((row + 1) * atlas.height / 4)
                frames.append(atlas.crop((x0, y0, x1, y1)))

            # Keep each complete worker/prop silhouette, then align the four
            # cells on one upper-body axis and shared ground baseline.
            strip = visitor.pack(frames, cleanup_area=1600)
            runtime_path = runtime / f"{action}.png"
            strip.save(runtime_path, optimize=True)
            frame_anchors, frame_metrics = [], []
            for index in range(4):
                frame = strip.crop((index * SIZE, 0, (index + 1) * SIZE, SIZE))
                box = visitor.bounds(frame)
                frame_anchors.append({"x": round(visitor.body_axis(frame, box), 2), "y": float(box[3])})
                frame_metrics.append(list(box))
                preview = frame.resize((126, 126), Image.Resampling.NEAREST)
                contact.alpha_composite(preview, (index * 142 + 8, row * 156 + 24))
            draw.text((4, row * 156 + 2), action.replace("_", " ").upper(),
                      fill=(226, 193, 111, 255), font=font)
            anchors[action], metrics[action] = frame_anchors, frame_metrics
            animation_specs[action] = {
                "path": runtime_path.relative_to(ROOT).as_posix(),
                "frame_width": SIZE,
                "frame_height": SIZE,
                "frame_count": 4,
                "loop": True,
                "role": "seated_break",
                "fps": FPS if action != "break_idle" else 0.65,
            }
            preview_frames = [strip.crop((i * SIZE, 0, (i + 1) * SIZE, SIZE)) for i in range(4)]
            preview_frames[0].save(REVIEW / f"{character}-{action}.gif", save_all=True,
                append_images=preview_frames[1:], duration=round(1000 / FPS), loop=0, disposal=2)

        motion_spec["break_action_contract"] = {
            "actions": {"meal": "break_eat", "rest_water": "break_water",
                        "rest_coffee": "break_coffee", "idle": "break_idle"},
            "frame_count": 4,
            "active_fps": FPS,
            "idle_fps": 0.65,
            "baseline": BASELINE,
            "west_view": "mirror east-facing strip",
        }
        motion_spec_path.write_text(json.dumps(motion_spec, indent=2) + "\n", encoding="utf-8")
        contact.save(REVIEW / f"{character}-contact.png", optimize=True)
        combined_anchors[character], combined_metrics[character] = anchors, metrics

    art = {"anchors": combined_anchors, "metrics": combined_metrics}
    (ROOT / "src/employee_break_art.lua").write_text(
        "-- Generated by tools/build_employee_break_v1.py.\nreturn " + lua(art) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    if "--prepare" in sys.argv:
        prepare()
    else:
        build()
