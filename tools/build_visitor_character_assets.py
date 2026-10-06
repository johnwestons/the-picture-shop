"""Package reviewed imagegen visitor sheets without inventing animation poses.

Source masters stay immutable. Preview is the default; --apply requires the full
five-view pack for every visitor and writes static, precomputed runtime metadata.
"""
from __future__ import annotations

import argparse
import json
import statistics
from pathlib import Path

from PIL import Image, ImageOps, ImageChops, ImageFilter

from build_player_character_assets import atomic_write, png_bytes, clear_small_detached_components
from character_sprite_doctor import audit_strip, render_contact_sheet

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/visitor-motion-v1/source-manifest.json"
REVIEW = ROOT / "output/visitor-motion-review"
CHARACTERS = ("business-dragon", "business-fox", "tan-cat", "green-blazer-cat", "blue-coaler-cat", "business-cat")
VIEWS = ("north", "northeast", "east", "southeast", "south")
SIZE, HEIGHT, WIDTH, BASELINE = 512, 410, 430, 466
POSES = ["left_contact", "left_weight_down", "right_passing", "right_knee_up",
         "right_contact", "right_weight_down", "left_passing", "left_knee_up"]


def split_sheet(record: dict) -> dict[str, list[Image.Image]]:
    source = Image.open(ROOT / record["source"]).convert("RGBA")
    cols, rows = record["layout"]["columns"], record["layout"]["rows"]
    cells = []
    for row in range(rows):
        for col in range(cols):
            cells.append(source.crop((round(col * source.width / cols), round(row * source.height / rows),
                                      round((col + 1) * source.width / cols), round((row + 1) * source.height / rows))))
    if record["action"] == "idle-directions":
        result = {}
        for col, view in enumerate(VIEWS):
            frames = [cells[col], cells[cols + col]]
            if view in record.get("mirror_source_views", []):
                frames = [ImageOps.mirror(frame) for frame in frames]
            result["idle" if view == "east" else f"idle_{view}"] = frames
        return result
    view = record["layout"]["view"]
    frames = [cells[index] for index in record.get("frame_order", range(len(cells)))]
    if record.get("mirror_source", False):
        frames = [ImageOps.mirror(frame) for frame in frames]
    return {"walk" if view == "east" else f"walk_{view}": frames}


def bounds(frame: Image.Image) -> tuple[int, int, int, int]:
    box = frame.getchannel("A").point(lambda a: 255 if a >= 16 else 0).getbbox()
    if box is None:
        raise ValueError("Empty source cell")
    return box


def body_axis(frame: Image.Image, box: tuple[int, int, int, int]) -> float:
    """Use the upper torso, rather than a swinging tail, as the x anchor."""
    left, top, right, bottom = box
    alpha = frame.getchannel("A")
    centers = []
    for y in range(top + round((bottom - top) * .32), top + round((bottom - top) * .50)):
        row = alpha.crop((left, y, right, y + 1)).point(lambda a: 255 if a >= 128 else 0)
        row_box = row.getbbox()
        if row_box:
            centers.append(left + (row_box[0] + row_box[2]) / 2)
    return statistics.median(centers) if centers else (left + right) / 2


def pack(frames: list[Image.Image], cleanup_area: int = 64) -> Image.Image:
    # Established export cleanup: detached flecks smaller than 64 pixels are
    # proven stray components, never colors inside the connected character.
    frames = [clean_export(frame, cleanup_area) for frame in frames]
    boxes = [bounds(frame) for frame in frames]
    # One scale for the entire loop preserves the weight-down / knee-up poses.
    # Center each source body over the same world anchor; do not resize each pose.
    axes = [body_axis(frame, box) for frame, box in zip(frames, boxes)]
    height = max(box[3] - box[1] for box in boxes)
    extent = max(max(axis - box[0], box[2] - axis) for axis, box in zip(axes, boxes))
    scale = min(HEIGHT / height, (WIDTH / 2) / extent)
    strip = Image.new("RGBA", (SIZE * len(frames), SIZE))
    for index, (frame, box, axis) in enumerate(zip(frames, boxes, axes)):
        left, top, right, bottom = box
        crop = frame.crop(box)
        resized = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.Resampling.LANCZOS)
        cell = Image.new("RGBA", (SIZE, SIZE))
        x = round(SIZE / 2 - (axis - left) * scale)
        y = BASELINE - resized.height
        cell.alpha_composite(resized, (x, y))
        cell = clean_export(cell, 16)
        # Copy through alpha onto fresh transparent pixels, removing hidden RGB
        # from the imagegen export without erasing pale clothing or fur.
        strip.alpha_composite(cell, (index * SIZE, 0))
    return strip


def clean_export(frame: Image.Image, minimum_area: int) -> Image.Image:
    frame = clear_small_detached_components(frame, minimum_area=minimum_area)
    alpha = frame.getchannel("A")
    # Keep soft edges within three pixels of the visible silhouette. Faint,
    # disconnected alpha far outside that silhouette is export background noise.
    supported = alpha.point(lambda a: 255 if a > 16 else 0).filter(ImageFilter.MaxFilter(7))
    frame.putalpha(ImageChops.multiply(alpha, supported))
    return frame


def spec_for(character: str, staging: bool = False) -> dict:
    prefix = f"output/visitor-motion-review/preview/{character}" if staging else f"assets/generated/characters/{character}"
    animations, directions = {}, {}
    speed = 72 if character.startswith("business-") else 68
    for view in VIEWS:
        for role, count, fps in (("idle", 2, .65), ("walk", 8, speed / 13)):
            action = role if view == "east" else f"{role}_{view}"
            animations[f"{role}_{view}"] = {"path": f"{prefix}/{action}.png", "frame_width": SIZE,
                "frame_height": SIZE, "frame_count": count, "loop": True,
                "role": "gait" if role == "walk" else "directional_idle", "fps": fps}
        directions[view] = {"walk_animation": f"walk_{view}", "idle_animation": f"idle_{view}", "mirror_x": False}
    for view, original in (("northwest", "northeast"), ("west", "east"), ("southwest", "southeast")):
        directions[view] = {"walk_animation": f"walk_{original}", "idle_animation": f"idle_{original}", "mirror_x": True}
    return {"version": 1, "character": character, "animations": animations, "directions": directions,
        "gait": {"pose_order": POSES, "pixels_per_frame": 13, "base_speed": speed,
            "speed_multipliers": [.96, .94, 1.04, 1.06] * 2,
            "acceleration_multipliers": [.92, .90, 1.08, 1.10] * 2},
        "anchor_contract": {"x": 256, "y": 465, "mode": "upper_torso_and_ground",
                            "maximum_torso_drift": 6, "maximum_ground_drift": 1},
        # The whole alpha-box center moves as a tail crosses behind the legs.
        # Runtime uses the separately checked upper-torso axis, not that box.
        "audit": {"alpha_threshold": 16, "edge_margin": 2, "detached_component_ratio": .003,
                  "baseline_tolerance": 1, "center_tolerance": 80}}


def lua_metadata(metadata: dict, field: str) -> str:
    lines = ["-- Generated by tools/build_visitor_character_assets.py; no runtime pixel scans.", "return {"]
    for character, actions in sorted(metadata.items()):
        lines.append(f'    ["{character}"] = {{')
        for action, frames in sorted(actions.items()):
            values = []
            for frame in frames:
                if field == "anchors":
                    values.append("{ x = 256, y = 465 }")
                else:
                    left, top, right, bottom = frame["bounds"]
                    values.append(f"{{ {left}, {top}, {right}, {bottom} }}")
            lines.append(f'        ["{action}"] = {{ ' + ", ".join(values) + " },")
        lines.append("    },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    manifest = json.loads(SOURCE.read_text(encoding="utf-8"))
    built = {character: {} for character in CHARACTERS}
    # The tabby already has reviewed directional strips; keep those pixels and
    # replace only newly authored actions in this pass.
    for view in VIEWS:
        for role in ("idle", "walk"):
            action = role if view == "east" else f"{role}_{view}"
            built["business-cat"][action] = Image.open(ROOT / "assets/generated/characters/business-cat" / f"{action}.png").convert("RGBA")
    selected = {}
    for record in manifest["sources"]:
        if record.get("review_status") != "selected":
            continue
        key = (record["character"], record["action"])
        if key in selected:
            raise ValueError(f"Multiple selected source revisions: {key}")
        selected[key] = record
    for record in selected.values():
        if record["character"] in built:
            for action, frames in split_sheet(record).items():
                built[record["character"]][action] = pack(frames, record.get("cleanup_detached_area", 64))
    if args.apply and any(len(actions) != 10 for actions in built.values()):
        raise ValueError("Runtime installation requires all five walk and five idle views for every character")
    audits, metadata, alignment = [], {}, {}
    for character, actions in built.items():
        metadata[character] = {}
        for action, strip in actions.items():
            path = REVIEW / "preview" / character / f"{action}.png"
            atomic_write(png_bytes(strip), path)
            audit = audit_strip(strip, path)
            render_contact_sheet(audit, REVIEW / "contact-sheets" / character / f"{action}.png")
            audits.append(audit)
            metadata[character][action] = [{"bounds": list(metric.bbox), "anchor": {"x": 256, "y": 465}}
                                            for metric in audit.metrics if metric.bbox]
            axes, floors = [], []
            for index in range(strip.width // SIZE):
                cell = strip.crop((index * SIZE, 0, (index + 1) * SIZE, SIZE))
                box = bounds(cell)
                axes.append(body_axis(cell, box))
                floors.append(box[3])
            key = f"{character}/{action}"
            alignment[key] = {"torso_drift": round(max(axes) - min(axes), 3),
                              "ground_drift": max(floors) - min(floors)}
            if character != "business-cat" or action in ("walk_southeast", "walk_south"):
                if alignment[key]["torso_drift"] > 6 or alignment[key]["ground_drift"] > 1:
                    raise ValueError(f"Unstable ground/body anchor: {key}: {alignment[key]}")
        if len(actions) == 10:
            atomic_write((json.dumps(spec_for(character, True), indent=2) + "\n").encode(), REVIEW / "specs" / f"{character}.json")
    report = {"strips": [audit.to_dict() for audit in audits], "runtime_metadata": metadata,
              "anchor_alignment": alignment}
    atomic_write((json.dumps(report, indent=2) + "\n").encode(), REVIEW / "report.json")
    errors = sum(audit.counts["error"] for audit in audits)
    warnings = sum(audit.counts["warning"] for audit in audits)
    print(f"Built {len(audits)} visitor strips: {errors} errors, {warnings} warnings; preview in {REVIEW}")
    if errors:
        return 1
    if args.apply:
        for character, actions in built.items():
            for action, strip in actions.items():
                atomic_write(png_bytes(strip), ROOT / "assets/generated/characters" / character / f"{action}.png")
            atomic_write((json.dumps(spec_for(character), indent=2) + "\n").encode(), ROOT / "character-motion" / f"{character}.json")
        for field in ("anchors", "metrics"):
            atomic_write(lua_metadata(metadata, field).encode(), ROOT / "src" / f"visitor_character_{field}.lua")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
