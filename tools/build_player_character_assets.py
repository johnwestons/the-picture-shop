"""Build the rabbit player pack from reviewed ImageGen source sheets."""

from __future__ import annotations

import argparse
import io
import json
import os
import tempfile
from collections import deque
from pathlib import Path
from typing import Sequence

from PIL import Image

from character_sprite_doctor import ALPHA_THRESHOLD, audit_strip, render_contact_sheet


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "assets" / "Characters" / "Player"
RUNTIME_ROOT = ROOT / "assets" / "generated" / "characters" / "rabbit-worker"
REVIEW_ROOT = ROOT / "output" / "sprite-doctor" / "player-review"
FRAME_SIZE = 512
VISIBLE_HEIGHT = 410
MAX_VISIBLE_WIDTH = 430
BASELINE = 466
SOURCES = {
}
DIRECTIONAL_IDLE_SOURCE = SOURCE_ROOT / "rabbit-worker-directional-idle-v1.png"
DIRECTIONAL_IDLE_ACTIONS = (
    "idle_north", "idle_northeast", "idle", "idle_southeast", "idle_south",
)
WALK_SOURCES = {
    "walk": SOURCE_ROOT / "rabbit-worker-walk-east-8frame-v2.png",
    "walk_north": SOURCE_ROOT / "rabbit-worker-walk-north-8frame-v2.png",
    "walk_northeast": SOURCE_ROOT / "rabbit-worker-walk-northeast-8frame-v2.png",
    "walk_southeast": SOURCE_ROOT / "rabbit-worker-walk-southeast-8frame-v2.png",
    "walk_south": SOURCE_ROOT / "rabbit-worker-walk-south-8frame-v2.png",
}


def neutral(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, alpha = pixel
    return alpha > 0 and min(red, green, blue) > 160 and max(red, green, blue) - min(red, green, blue) <= 10


def remove_connected_neutral_background(image: Image.Image) -> Image.Image:
    """Remove an opaque white/checkerboard field without touching enclosed art."""
    image = image.convert("RGBA")
    width, height = image.size
    pixels = image.load()
    perimeter = [pixels[x, y] for x in range(width) for y in (0, height - 1)]
    perimeter.extend(pixels[x, y] for y in range(1, height - 1) for x in (0, width - 1))
    if sum(1 for pixel in perimeter if neutral(pixel)) < max(16, round(len(perimeter) * 0.20)):
        return image

    visited = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        queue.extend(((x, 0), (x, height - 1)))
    for y in range(1, height - 1):
        queue.extend(((0, y), (width - 1, y)))

    while queue:
        x, y = queue.popleft()
        index = y * width + x
        if visited[index] or not neutral(pixels[x, y]):
            continue
        visited[index] = 1
        for next_x, next_y in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= next_x < width and 0 <= next_y < height:
                queue.append((next_x, next_y))

    for y in range(height):
        for x in range(width):
            if visited[y * width + x]:
                red, green, blue, _ = pixels[x, y]
                pixels[x, y] = (red, green, blue, 0)
    return image


def remove_connected_solid_background(image: Image.Image, tolerance: int = 4) -> Image.Image:
    """Remove a flat edge-connected backdrop while preserving differently colored outlines."""
    image = image.convert("RGBA")
    width, height = image.size
    pixels = image.load()
    corners = (pixels[0, 0], pixels[width - 1, 0], pixels[0, height - 1], pixels[width - 1, height - 1])
    target = max(corners, key=corners.count)
    if target[3] <= ALPHA_THRESHOLD:
        return image

    def matches(pixel: tuple[int, int, int, int]) -> bool:
        return pixel[3] > ALPHA_THRESHOLD and max(
            abs(pixel[channel] - target[channel]) for channel in range(3)
        ) <= tolerance

    visited = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        queue.extend(((x, 0), (x, height - 1)))
    for y in range(1, height - 1):
        queue.extend(((0, y), (width - 1, y)))
    while queue:
        x, y = queue.popleft()
        index = y * width + x
        if visited[index] or not matches(pixels[x, y]):
            continue
        visited[index] = 1
        for next_x, next_y in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= next_x < width and 0 <= next_y < height:
                queue.append((next_x, next_y))
    for y in range(height):
        for x in range(width):
            if visited[y * width + x]:
                red, green, blue, _ = pixels[x, y]
                pixels[x, y] = (red, green, blue, 0)
    return image


def significant_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    mask = image.getchannel("A").point(lambda value: 255 if value > ALPHA_THRESHOLD else 0)
    return mask.getbbox()


def clear_small_detached_components(image: Image.Image, minimum_area: int = 16) -> Image.Image:
    """Drop resampling specks without touching the connected character silhouette."""
    result = image.convert("RGBA")
    pixels = result.load()
    candidates = {
        (x, y) for y in range(result.height) for x in range(result.width)
        if pixels[x, y][3] > ALPHA_THRESHOLD
    }
    components: list[set[tuple[int, int]]] = []
    while candidates:
        start = candidates.pop()
        component = {start}
        queue = deque([start])
        while queue:
            x, y = queue.popleft()
            for neighbor in (
                (x - 1, y - 1), (x, y - 1), (x + 1, y - 1),
                (x - 1, y), (x + 1, y),
                (x - 1, y + 1), (x, y + 1), (x + 1, y + 1),
            ):
                if neighbor in candidates:
                    candidates.remove(neighbor)
                    component.add(neighbor)
                    queue.append(neighbor)
        components.append(component)
    if not components:
        return result
    largest = max(components, key=len)
    for component in components:
        if component is largest or len(component) >= minimum_area:
            continue
        for x, y in component:
            red, green, blue, _ = pixels[x, y]
            pixels[x, y] = (red, green, blue, 0)
    return result


def clear_enclosed_leg_mattes(image: Image.Image) -> Image.Image:
    """Remove large neutral checker remnants trapped between lower legs."""
    result = image.convert("RGBA")
    bounds = significant_bbox(result)
    if not bounds:
        return result
    left, top, right, bottom = bounds
    region_top = round(top + (bottom - top) * 0.70)
    region_left = round(left + (right - left) * 0.12)
    region_right = round(right - (right - left) * 0.12)
    pixels = result.load()
    candidates = {
        (x, y)
        for y in range(region_top, bottom)
        for x in range(region_left, region_right)
        if neutral(pixels[x, y])
    }
    while candidates:
        start = candidates.pop()
        component = {start}
        queue = deque([start])
        while queue:
            x, y = queue.popleft()
            for neighbor in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if neighbor in candidates:
                    candidates.remove(neighbor)
                    component.add(neighbor)
                    queue.append(neighbor)
        if len(component) < 16:
            continue
        for x, y in component:
            red, green, blue, _ = pixels[x, y]
            pixels[x, y] = (red, green, blue, 0)
    return result


def normalize_frame(panel: Image.Image) -> Image.Image:
    cleaned = clear_enclosed_leg_mattes(remove_connected_solid_background(
        remove_connected_neutral_background(panel)))
    bounds = significant_bbox(cleaned)
    if not bounds:
        raise ValueError("source panel contains no visible character")
    sprite = cleaned.crop(bounds)
    scale = min(VISIBLE_HEIGHT / sprite.height, MAX_VISIBLE_WIDTH / sprite.width)
    width = max(1, round(sprite.width * scale))
    height = max(1, round(sprite.height * scale))
    sprite = sprite.resize((width, height), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(sprite, (round((FRAME_SIZE - width) / 2), BASELINE - height))
    return clear_small_detached_components(canvas)


def build_strip(source: Path, frame_count: int) -> Image.Image:
    image = Image.open(source).convert("RGBA")
    if image.width % frame_count:
        raise ValueError(f"{source} width must split evenly into {frame_count} panels")
    panel_width = image.width // frame_count
    frames = [
        normalize_frame(image.crop((index * panel_width, 0, (index + 1) * panel_width, image.height)))
        for index in range(frame_count)
    ]
    strip = Image.new("RGBA", (FRAME_SIZE * frame_count, FRAME_SIZE), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME_SIZE, 0))
    return strip


def clear_idle_leg_matte(strip: Image.Image) -> Image.Image:
    """Clear the enclosed checker remnants between the two idle legs."""
    result = strip.convert("RGBA")
    pixels = result.load()
    for frame in range(2):
        for y in range(385, 445):
            for x in range(frame * FRAME_SIZE + 245, frame * FRAME_SIZE + 280):
                red, green, blue, alpha = pixels[x, y]
                if alpha > 0 and min(red, green, blue) >= 80 \
                    and max(red, green, blue) - min(red, green, blue) <= 45:
                    pixels[x, y] = (red, green, blue, 0)
    return result


def build_walk_atlas(source: Path) -> Image.Image:
    image = Image.open(source).convert("RGBA")
    frames = []
    for index in range(8):
        row, column = divmod(index, 4)
        left = round(column * image.width / 4)
        right = round((column + 1) * image.width / 4)
        top = 0 if row == 0 else round(image.height * 0.49)
        bottom = round(image.height * 0.49) if row == 0 else image.height
        frames.append(normalize_frame(image.crop((left, top, right, bottom))))
    strip = Image.new("RGBA", (FRAME_SIZE * 8, FRAME_SIZE), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME_SIZE, 0))
    return strip


def build_directional_idle_atlas(source: Path) -> dict[str, Image.Image]:
    image = Image.open(source).convert("RGBA")
    actions: dict[str, Image.Image] = {}
    for column, action in enumerate(DIRECTIONAL_IDLE_ACTIONS):
        frames = []
        for row in range(2):
            left = round(column * image.width / 5)
            right = round((column + 1) * image.width / 5)
            top = round(row * image.height / 2)
            bottom = round((row + 1) * image.height / 2)
            frames.append(normalize_frame(image.crop((left, top, right, bottom))))
        strip = Image.new("RGBA", (FRAME_SIZE * 2, FRAME_SIZE), (0, 0, 0, 0))
        for index, frame in enumerate(frames):
            strip.alpha_composite(frame, (index * FRAME_SIZE, 0))
        actions[action] = strip
    return actions


def png_bytes(image: Image.Image) -> bytes:
    output = io.BytesIO()
    image.save(output, format="PNG", optimize=False, compress_level=9)
    return output.getvalue()


def atomic_write(content: bytes, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{destination.name}.", suffix=".tmp", dir=destination.parent)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, destination)
    finally:
        temporary = Path(temporary_name)
        if temporary.exists():
            temporary.unlink()


def metadata(audits: dict[str, object]) -> dict[str, object]:
    result: dict[str, object] = {"character": "rabbit-worker", "actions": {}}
    for action, audit in audits.items():
        frames = []
        for metric in audit.metrics:
            if not metric.bbox:
                continue
            left, top, right, bottom = metric.bbox
            frames.append({
                "bounds": [left, top, right, bottom],
                "anchor": {"x": (left + right - 1) / 2, "y": bottom - 1},
            })
        result["actions"][action] = frames
    return result


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="install reviewed strips into the runtime character pack")
    parser.add_argument("--idle-only", action="store_true", help="install only directional idle strips")
    args = parser.parse_args(argv)

    preview_root = REVIEW_ROOT / "preview" / "rabbit-worker"
    contact_root = REVIEW_ROOT / "contact-sheets" / "rabbit-worker"
    audits = {}
    built = {}
    for action, strip in build_directional_idle_atlas(DIRECTIONAL_IDLE_SOURCE).items():
        destination = preview_root / f"{action}.png"
        atomic_write(png_bytes(strip), destination)
        audit = audit_strip(strip, Path(f"{action}.png"))
        render_contact_sheet(audit, contact_root / f"{action}.png")
        audits[action] = audit
        built[action] = strip
    for action, (source, frame_count) in SOURCES.items():
        strip = build_strip(source, frame_count)
        if action == "idle": strip = clear_idle_leg_matte(strip)
        destination = preview_root / f"{action}.png"
        atomic_write(png_bytes(strip), destination)
        audit = audit_strip(strip, Path(f"{action}.png"))
        render_contact_sheet(audit, contact_root / f"{action}.png")
        audits[action] = audit
        built[action] = strip
    for action, source in WALK_SOURCES.items():
        strip = build_walk_atlas(source)
        destination = preview_root / f"{action}.png"
        atomic_write(png_bytes(strip), destination)
        audit = audit_strip(strip, Path(f"{action}.png"))
        render_contact_sheet(audit, contact_root / f"{action}.png")
        audits[action] = audit
        built[action] = strip

    report = {
        "strips": [audit.to_dict() for audit in audits.values()],
        "runtime_metadata": metadata(audits),
    }
    REVIEW_ROOT.mkdir(parents=True, exist_ok=True)
    (REVIEW_ROOT / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    errors = sum(audit.counts["error"] for audit in audits.values())
    warnings = sum(audit.counts["warning"] for audit in audits.values())
    print(f"Built {len(built)} player strip(s): {errors} error(s), {warnings} warning(s)")
    print(f"Review contact sheets: {contact_root}")
    if errors:
        return 1
    if not args.apply:
        print(f"Preview only; runtime assets unchanged: {preview_root}")
        return 0
    for action, strip in built.items():
        if args.idle_only and not (action == "idle" or action.startswith("idle_")):
            continue
        destination = RUNTIME_ROOT / f"{action}.png"
        atomic_write(png_bytes(strip), destination)
        print(f"installed {destination.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
