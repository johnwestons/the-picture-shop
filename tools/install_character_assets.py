"""Preview, review, and install approved Sprite Doctor character strips."""

import argparse
import io
import json
import os
import shutil
import tempfile
from collections import deque
from datetime import datetime
from pathlib import Path
from typing import Sequence

from PIL import Image

from character_sprite_doctor import audit_strip, render_contact_sheet


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "output" / "sprite-doctor" / "approved"
DEST_ROOT = ROOT / "assets" / "generated" / "characters"
REVIEW_ROOT = ROOT / "output" / "sprite-doctor" / "install-review"


def green(pixel: tuple[int, int, int, int]) -> bool:
    red, green_value, blue, alpha = pixel
    return (
        alpha > 0 and green_value > 100
        and green_value > red * 1.28 and green_value > blue * 1.28
        and green_value - max(red, blue) > 24
    )


def neutral(pixel: tuple[int, int, int, int]) -> bool:
    red, green_value, blue, alpha = pixel
    return alpha > 0 and min(red, green_value, blue) > 160 and max(red, green_value, blue) - min(red, green_value, blue) <= 8


def remove_connected_background(frame: Image.Image) -> Image.Image:
    frame = frame.convert("RGBA")
    width, height = frame.size
    pixels = frame.load()
    visited = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()
    perimeter_pixels = [pixels[x, y] for x in range(width) for y in (0, height - 1)]
    perimeter_pixels.extend(pixels[x, y] for y in range(1, height - 1) for x in (0, width - 1))
    remove_neutral = sum(1 for pixel in perimeter_pixels if neutral(pixel)) >= max(
        16, round(len(perimeter_pixels) * 0.20)
    )
    for x in range(width):
        queue.extend(((x, 0), (x, height - 1)))
    for y in range(1, height - 1):
        queue.extend(((0, y), (width - 1, y)))

    while queue:
        x, y = queue.popleft()
        index = y * width + x
        if visited[index] or not (green(pixels[x, y]) or (remove_neutral and neutral(pixels[x, y]))):
            continue
        visited[index] = 1
        for neighbor in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            nx, ny = neighbor
            if 0 <= nx < width and 0 <= ny < height:
                queue.append((nx, ny))

    for y in range(height):
        for x in range(width):
            if visited[y * width + x]:
                red, green_value, blue, _ = pixels[x, y]
                pixels[x, y] = (red, green_value, blue, 0)
    return frame


def prepare_strip(source: Path) -> Image.Image:
    image = Image.open(source).convert("RGBA")
    if image.width % 512 or image.height != 512:
        raise ValueError(f"Doctor output is not a 512px strip: {source} ({image.size})")
    frames = []
    for x in range(0, image.width, 512):
        frame = remove_connected_background(image.crop((x, 0, x + 512, 512)))
        if frame.getchannel("A").getbbox() is None:
            raise ValueError(f"Empty cleaned frame: {source} frame {len(frames) + 1}")
        frames.append(frame)
    result = Image.new("RGBA", image.size, (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        result.alpha_composite(frame, (index * 512, 0))
    return result


def png_bytes(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=False, compress_level=9)
    return buffer.getvalue()


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


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="install after preview and review")
    parser.add_argument(
        "--reviewed-contact-sheets", action="store_true",
        help="confirm every generated contact sheet was visually reviewed before --apply",
    )
    args = parser.parse_args(argv)
    # Approved sets may be grouped one level deeper (for example
    # approved/business-clients/business-cat/idle.png). The immediate parent is
    # always the runtime character key, so recurse without losing that mapping.
    sources = sorted(SOURCE_ROOT.rglob("*.png"))
    prepared: list[tuple[Path, Path, Image.Image, bytes]] = []
    audits = []
    preview_root = REVIEW_ROOT / "preview"
    contacts_root = REVIEW_ROOT / "contact-sheets"
    for source in sources:
        destination = DEST_ROOT / source.parent.name / source.name
        image = prepare_strip(source)
        audit = audit_strip(image, source)
        audits.append(audit)
        content = png_bytes(image)
        prepared.append((source, destination, image, content))
        atomic_write(content, preview_root / source.parent.name / source.name)
        render_contact_sheet(audit, contacts_root / source.parent.name / source.name)

    report = {"strips": [audit.to_dict() for audit in audits]}
    REVIEW_ROOT.mkdir(parents=True, exist_ok=True)
    (REVIEW_ROOT / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    errors = sum(audit.counts["error"] for audit in audits)
    warnings = sum(audit.counts["warning"] for audit in audits)
    print(f"Prepared {len(prepared)} strip(s): {errors} error(s), {warnings} warning(s)")
    print(f"Required contact sheets: {contacts_root}")
    if errors:
        print("Install stopped because one or more prepared strips failed the Sprite Doctor audit.")
        return 1
    if not args.apply:
        print(f"Preview only; runtime assets unchanged. Preview: {preview_root}")
        return 0
    if not args.reviewed_contact_sheets:
        parser.error("review the generated contact sheets, then apply with --reviewed-contact-sheets")

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup_root = ROOT / "output" / "sprite-doctor" / "backups" / stamp
    for _, destination, _, _ in prepared:
        if destination.exists():
            backup = backup_root / destination.relative_to(ROOT)
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(destination, backup)
    for _, destination, _, content in prepared:
        atomic_write(content, destination)
        print(f"installed {destination.relative_to(ROOT)}")
    print(f"Backups: {backup_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
