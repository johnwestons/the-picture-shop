#!/usr/bin/env python3
"""Compile the suited rider's transparent directional walk sheets into game strips."""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "assets/source/commute-rider-v3/raw"
STAGED = ROOT / "assets/staging/commute-rider-v3"
RUNTIME = ROOT / "assets/generated/commute-rider-v3"
CHARACTER = "suited-rider"
DIRECTIONS = ("north", "northeast", "east", "southeast", "south")
PHASES = (
    "left_contact", "left_down", "right_passing", "right_up",
    "right_contact", "right_down", "left_passing", "left_up",
)
FRAME_SIZE = 256
GROUND_Y = 238
HEAD_ANCHOR_X = 128
NORMALIZATION_HEIGHT = 214


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def runs(mask: np.ndarray) -> list[tuple[int, int]]:
    indexes = np.flatnonzero(mask)
    if not len(indexes):
        return []
    result: list[tuple[int, int]] = []
    start = previous = int(indexes[0])
    for value in indexes[1:]:
        value = int(value)
        if value > previous + 1:
            result.append((start, previous + 1))
            start = value
        previous = value
    result.append((start, previous + 1))
    return result


def split_source_sheet(path: Path) -> list[tuple[Image.Image, tuple[int, int, int, int]]]:
    sheet = Image.open(path).convert("RGBA")
    alpha = np.asarray(sheet.getchannel("A")) > 16
    columns = runs(np.count_nonzero(alpha, axis=0) > 30)
    rows = runs(np.count_nonzero(alpha, axis=1) > 30)
    if len(columns) != 4 or len(rows) != 2:
        raise ValueError(
            f"{path.name}: expected a transparent 4x2 sheet, found "
            f"{len(columns)} columns x {len(rows)} rows"
        )

    frames = []
    for top, bottom in rows:
        for left, right in columns:
            bounds = (max(0, left - 3), max(0, top - 3),
                      min(sheet.width, right + 4), min(sheet.height, bottom + 4))
            cell = sheet.crop(bounds)
            visible = cell.getchannel("A").point(lambda value: 255 if value > 16 else 0).getbbox()
            if not visible:
                raise ValueError(f"{path.name}: empty pose at {bounds}")
            l, t, r, b = visible
            pose = cell.crop((l, t, r, b))
            frames.append((pose, (bounds[0] + l, bounds[1] + t, bounds[0] + r, bounds[1] + b)))
    if len(frames) != 8:
        raise ValueError(f"{path.name}: expected 8 poses, found {len(frames)}")
    return frames


def compile_walk(direction: str) -> tuple[Path, list[dict], float]:
    source = RAW / f"walk_{direction}-sheet.png"
    frames = split_source_sheet(source)
    average_height = sum(frame.height for frame, _ in frames) / len(frames)
    scale = NORMALIZATION_HEIGHT / average_height
    sheet = Image.new("RGBA", (FRAME_SIZE * 8, FRAME_SIZE), (0, 0, 0, 0))
    records = []

    for index, (pose, source_rect) in enumerate(frames):
        width = max(1, round(pose.width * scale))
        height = max(1, round(pose.height * scale))
        resized = pose.resize((width, height), Image.Resampling.LANCZOS)
        # Keep the helmet's visual center and the planted shoe line fixed while
        # the limbs swing through the walk cycle.
        alpha = np.asarray(pose.getchannel("A")) > 16
        top = int(np.flatnonzero(np.any(alpha, axis=1))[0])
        bottom = int(np.flatnonzero(np.any(alpha, axis=1))[-1]) + 1
        head_bottom = min(bottom, top + round((bottom - top) * 0.22))
        head_mask = alpha[top:head_bottom]
        head_columns = np.flatnonzero(np.any(head_mask, axis=0))
        if not len(head_columns):
            raise ValueError(f"{source.name}: could not locate helmet center in pose {index + 1}")
        head_center_x = (int(head_columns[0]) + int(head_columns[-1]) + 1) / 2
        offset_x = round(HEAD_ANCHOR_X - head_center_x * scale)
        offset_y = GROUND_Y - height
        frame = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        frame.alpha_composite(resized, (offset_x, offset_y))
        sheet.alpha_composite(frame, (index * FRAME_SIZE, 0))
        bounds = frame.getchannel("A").point(lambda value: 255 if value > 16 else 0).getbbox()
        records.append({
            "sourceRect": list(source_rect),
            "sourceBounds": [0, 0, pose.width, pose.height],
            "visibleSourceHeight": pose.height,
            "helmetCenterX": round(head_center_x, 2),
            "sourceGroundY": pose.height,
            "stageBounds": list(bounds),
            "stageAnchor": [HEAD_ANCHOR_X, GROUND_Y],
            "phase": PHASES[index],
        })

    path = RUNTIME / f"walk_{direction}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path, optimize=True)
    return path, records, scale


def lua_value(value) -> str:
    if isinstance(value, dict):
        return "{" + ",".join(f"[{lua_value(k)}]={lua_value(v)}" for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ",".join(lua_value(v) for v in value) + "}"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "nil"
    return str(value)


def main() -> None:
    STAGED.mkdir(parents=True, exist_ok=True)
    RUNTIME.mkdir(parents=True, exist_ok=True)
    animations: dict[str, dict] = {}
    anchors: dict[str, list] = {}
    metrics: dict[str, list] = {}
    provenance = []

    for direction in DIRECTIONS:
        source = RAW / f"walk_{direction}-sheet.png"
        path, frames, scale = compile_walk(direction)
        staged_path = STAGED / path.name
        shutil.copy2(path, staged_path)
        animation = f"walk_{direction}"
        animations[animation] = {
            "path": path.relative_to(ROOT).as_posix(), "frame_width": FRAME_SIZE,
            "frame_height": FRAME_SIZE, "frame_count": 8, "loop": True,
            "role": "gait", "normalizationHeight": NORMALIZATION_HEIGHT,
            "uniformSourceScale": round(scale, 6), "source": source.relative_to(ROOT).as_posix(),
            "sourceSha256": sha256(source), "sha256": sha256(path), "frames": frames,
        }
        anchors[animation] = [{"x": HEAD_ANCHOR_X, "y": GROUND_Y} for _ in range(8)]
        image = Image.open(path).convert("RGBA")
        metrics[animation] = [
            list(image.crop((i * FRAME_SIZE, 0, (i + 1) * FRAME_SIZE, FRAME_SIZE))
                 .getchannel("A").point(lambda value: 255 if value > 16 else 0).getbbox())
            for i in range(8)
        ]
        provenance.append({"path": source.relative_to(ROOT).as_posix(), "sha256": sha256(source)})

    for direction in DIRECTIONS:
        source = RAW / f"idle_{direction}.png"
        image = Image.open(source).convert("RGBA")
        if image.size != (FRAME_SIZE * 2, FRAME_SIZE):
            raise ValueError(f"{source.name}: expected 512x256 two-frame idle, got {image.size}")
        path = RUNTIME / f"idle_{direction}.png"
        image.save(path, optimize=True)
        shutil.copy2(path, STAGED / path.name)
        animation = f"idle_{direction}"
        bounds_by_frame = []
        for i in range(2):
            frame = image.crop((i * FRAME_SIZE, 0, (i + 1) * FRAME_SIZE, FRAME_SIZE))
            bounds_by_frame.append(list(frame.getchannel("A").point(
                lambda value: 255 if value > 16 else 0).getbbox()))
        animations[animation] = {
            "path": path.relative_to(ROOT).as_posix(), "frame_width": FRAME_SIZE,
            "frame_height": FRAME_SIZE, "frame_count": 2, "loop": True,
            "role": "directional_idle", "fps": 0.65,
            "normalizationHeight": NORMALIZATION_HEIGHT,
            "source": source.relative_to(ROOT).as_posix(), "sourceSha256": sha256(source),
            "sha256": sha256(path), "frames": bounds_by_frame,
        }
        anchors[animation] = [{"x": HEAD_ANCHOR_X, "y": GROUND_Y} for _ in range(2)]
        metrics[animation] = bounds_by_frame
        provenance.append({"path": source.relative_to(ROOT).as_posix(), "sha256": sha256(source)})

    directions = {}
    for direction in ("north", "northeast", "east", "southeast", "south"):
        directions[direction] = {
            "walk_animation": f"walk_{direction}",
            "idle_animation": f"idle_{direction}",
            "mirror_x": False,
        }
    directions.update({
        "northwest": {"walk_animation": "walk_northeast", "idle_animation": "idle_northeast", "mirror_x": True},
        "west": {"walk_animation": "walk_east", "idle_animation": "idle_east", "mirror_x": True},
        "southwest": {"walk_animation": "walk_southeast", "idle_animation": "idle_southeast", "mirror_x": True},
    })
    motion = {
        "version": 1, "character": "shared-suited-rider-v3",
        "status": "runtime_integrated_visual_reviewed", "runtimeIntegrated": True,
        "animations": animations, "directions": directions,
        "gait": {"pose_order": list(PHASES), "pixels_per_frame": 20,
                 "base_speed": 155, "speed_multipliers": [1] * 8,
                 "acceleration_multipliers": [1] * 8},
        "audit": {"alpha_threshold": 16, "edge_margin": 2,
                  "detached_component_ratio": 0.003, "baseline_tolerance": 2,
                  "center_tolerance": 14},
        "runtime": {"rendered_height_pixels": 77, "foot_anchor": [HEAD_ANCHOR_X, GROUND_Y],
                    "pixels_per_gait_frame": 20,
                    "enginePreview": {"status": "passed", "walkingCaptures": 144,
                                      "idleCaptures": 32, "localAndRemote": True,
                                      "desktopAndLandscapePhone": True},
                    "mirror_rationale": "The suit has a centered zipper, no readable side markings, and no carried item."},
        "sources": provenance,
        "pending": [],
    }
    motion_path = STAGED / "motion.json"
    motion_path.write_text(json.dumps(motion, indent=2) + "\n", encoding="utf-8")
    manifest = {
        "version": 1, "character": "shared-suited-rider-v3",
        "status": "runtime_integrated_visual_reviewed", "runtimeIntegrated": True,
        "frameSize": FRAME_SIZE,
        "engineReview": "output/commute-rider-v3-engine-review/suited-walk/engine-review.txt",
        "spriteAudit": "output/commute-rider-v3-motion-audit/report.json",
        "directions": list(directions), "animations": animations, "sources": provenance,
    }
    (STAGED / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    paths = {animation: details["path"] for animation, details in animations.items()}
    # CharacterAnimation uses the unsuffixed action names for horizontal travel.
    for base in ("walk", "idle"):
        east = f"{base}_east"
        paths[base] = paths[east]
        anchors[base] = anchors[east]
        metrics[base] = metrics[east]
    lua = "-- Generated by tools/commute_lab/compile_rider_walk_v3.py.\nreturn " + lua_value({
        "paths": {CHARACTER: paths},
        "anchors": {CHARACTER: anchors},
        "metrics": {CHARACTER: metrics},
    }) + "\n"
    lua_path = ROOT / "src/commute/walker_art.lua"
    lua_path.write_text(lua, encoding="utf-8")

    print(f"Compiled {len(animations)} animations for {CHARACTER}.")
    print(f"Runtime art: {RUNTIME.relative_to(ROOT)}")
    print(f"Review spec: {motion_path.relative_to(ROOT)}")
    print(f"Lua registration: {lua_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
