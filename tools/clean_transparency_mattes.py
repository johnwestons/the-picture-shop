"""Preview or apply narrowly scoped alpha cleanup for known sprite mattes."""

from __future__ import annotations

import argparse
import io
import os
import shutil
import tempfile
from datetime import datetime
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CHARACTERS = ROOT / "assets" / "generated" / "characters"
PLAYER_IDLE = CHARACTERS / "rabbit-worker" / "idle.png"
CAT_SIT = CHARACTERS / "business-cat" / "sit.png"
PALLET_JACK = ROOT / "assets" / "generated" / "pallet-jack-directions-strip.png"
REVIEW = ROOT / "output" / "transparency-cleanup"
CAT_EYE_BOXES = ((200, 150, 232, 187), (250, 150, 288, 187))


def png_bytes(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=False, compress_level=9)
    return buffer.getvalue()


def atomic_write(destination: Path, content: bytes) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.", suffix=".tmp", dir=destination.parent
    )
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


def neutral(pixel: tuple[int, int, int, int], minimum: int, spread: int) -> bool:
    red, green, blue, alpha = pixel
    return alpha > 0 and min(red, green, blue) >= minimum \
        and max(red, green, blue) - min(red, green, blue) <= spread


def clear_player_leg_matte(image: Image.Image) -> tuple[Image.Image, int]:
    """Clear the two enclosed neutral wedges without touching the clothing."""
    result = image.convert("RGBA")
    pixels = result.load()
    removed = 0
    for frame in range(2):
        left = frame * 512 + 245
        for y in range(385, 445):
            for x in range(left, left + 35):
                if neutral(pixels[x, y], minimum=80, spread=45):
                    red, green, blue, _ = pixels[x, y]
                    pixels[x, y] = red, green, blue, 0
                    removed += 1
    return result, removed


def clear_connected_edge_matte(frame: Image.Image) -> tuple[Image.Image, int]:
    """Remove only the first two neutral fringe layers beside transparency."""
    result = frame.convert("RGBA")
    width, height = result.size
    pixels = result.load()
    candidates = {
        (x, y)
        for y in range(height)
        for x in range(width)
        if neutral(pixels[x, y], minimum=130, spread=35)
    }
    removed: set[tuple[int, int]] = set()
    frontier = {
        (x, y)
        for x, y in candidates
        if any(
            pixels[nx, ny][3] == 0
            for nx in range(max(0, x - 1), min(width, x + 2))
            for ny in range(max(0, y - 1), min(height, y + 2))
        )
    }
    for _ in range(2):
        if not frontier:
            break
        removed.update(frontier)
        next_frontier: set[tuple[int, int]] = set()
        for x, y in frontier:
            for nx in range(max(0, x - 1), min(width, x + 2)):
                for ny in range(max(0, y - 1), min(height, y + 2)):
                    if (nx, ny) in candidates and (nx, ny) not in removed:
                        next_frontier.add((nx, ny))
        frontier = next_frontier
    for x, y in removed:
        red, green, blue, _ = pixels[x, y]
        pixels[x, y] = red, green, blue, 0
    return result, len(removed)


def restore_cat_eye_whites(image: Image.Image, reference: Image.Image) -> tuple[Image.Image, int]:
    """Restore enclosed sclera from a matching pre-cleanup strip."""
    result = image.convert("RGBA")
    source = reference.convert("RGBA")
    if result.size != source.size or result.size != (1024, 512):
        raise ValueError("business-cat eye restoration requires matching 1024x512 strips")
    pixels = result.load()
    source_pixels = source.load()
    restored = 0
    for frame_index in range(2):
        offset = frame_index * 512
        for left, top, right, bottom in CAT_EYE_BOXES:
            for y in range(top, bottom):
                for local_x in range(left, right):
                    x = offset + local_x
                    source_pixel = source_pixels[x, y]
                    if pixels[x, y][3] == 0 and neutral(source_pixel, minimum=145, spread=85):
                        pixels[x, y] = source_pixel
                        restored += 1
    return result, restored


def clear_insignificant_islands(frame: Image.Image) -> tuple[Image.Image, int]:
    """Drop invisible alpha dust without deleting disconnected sprite details."""
    result = frame.convert("RGBA")
    width, height = result.size
    pixels = result.load()
    removed = 0
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            if 0 < alpha <= 16:
                pixels[x, y] = red, green, blue, 0
                removed += 1

    return result, removed


def clear_cat_sit_matte(image: Image.Image) -> tuple[Image.Image, int]:
    source = image.convert("RGBA")
    result = Image.new("RGBA", source.size, (0, 0, 0, 0))
    removed = 0
    for frame_index in range(2):
        frame = source.crop((frame_index * 512, 0, (frame_index + 1) * 512, 512))
        cleaned, count = clear_connected_edge_matte(frame)
        cleaned, dust_count = clear_insignificant_islands(cleaned)
        for left, top, right, bottom in CAT_EYE_BOXES:
            eye = source.crop((frame_index * 512 + left, top,
                frame_index * 512 + right, bottom))
            cleaned.alpha_composite(eye, (left, top))
        result.alpha_composite(cleaned, (frame_index * 512, 0))
        removed += count + dust_count
    return result, removed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="replace runtime assets after review")
    args = parser.parse_args()

    player_source = Image.open(PLAYER_IDLE).convert("RGBA")
    cat_source = Image.open(CAT_SIT).convert("RGBA")
    player, player_removed = clear_player_leg_matte(player_source)
    cat, cat_removed = clear_cat_sit_matte(cat_source)
    outputs = [(PLAYER_IDLE, player), (CAT_SIT, cat)]

    preview = REVIEW / "preview"
    for source, image in outputs:
        relative = source.relative_to(ROOT / "assets" / "generated")
        atomic_write(preview / relative, png_bytes(image))

    jack = Image.open(PALLET_JACK).convert("RGBA")
    if jack.size != (2048, 256) or jack.getchannel("A").getextrema()[0] != 0:
        raise ValueError("Pallet-jack transparency contract is not valid")
    print(f"Preview ready: player alpha pixels removed={player_removed}, cat alpha pixels removed={cat_removed}")
    print(f"Pallet-jack loop verified transparent: {PALLET_JACK.relative_to(ROOT)}")
    print(f"Review: {preview}")
    if not args.apply:
        return 0

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup = REVIEW / "backups" / stamp
    for source, image in outputs:
        relative = source.relative_to(ROOT)
        backup_path = backup / relative
        backup_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, backup_path)
        atomic_write(source, png_bytes(image))
        print(f"Installed: {relative}")
    print(f"Backups: {backup}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
