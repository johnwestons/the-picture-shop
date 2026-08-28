"""Turn the generated work-order sheet's edge checkerboard into true alpha."""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "assets/generated/pallet-work-order-paper-v1.png"


def remove_edge_checkerboard(source: Image.Image) -> Image.Image:
    """Remove only bright, neutral pixels connected to the canvas boundary."""
    rgb = source.convert("RGB")
    width, height = rgb.size
    pixels = rgb.load()
    background = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()

    def is_background(x: int, y: int, edge: bool = False) -> bool:
        red, green, blue = pixels[x, y]
        threshold = 220 if edge else 226
        return min(red, green, blue) >= threshold and max(red, green, blue) - min(red, green, blue) <= 13

    def seed(x: int, y: int) -> None:
        index = y * width + x
        if not background[index] and is_background(x, y, True):
            background[index] = 1
            queue.append((x, y))

    for x in range(width):
        seed(x, 0)
        seed(x, height - 1)
    for y in range(height):
        seed(0, y)
        seed(width - 1, y)

    while queue:
        x, y = queue.popleft()
        for next_x, next_y in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if not (0 <= next_x < width and 0 <= next_y < height):
                continue
            index = next_y * width + next_x
            if not background[index] and is_background(next_x, next_y):
                background[index] = 1
                queue.append((next_x, next_y))

    output = rgb.convert("RGBA")
    output_pixels = output.load()
    for y in range(height):
        row = y * width
        for x in range(width):
            if background[row + x]:
                output_pixels[x, y] = (0, 0, 0, 0)
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    source = args.source if args.source.is_absolute() else ROOT / args.source
    output = args.output if args.output.is_absolute() else ROOT / args.output

    image = remove_edge_checkerboard(Image.open(source))
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output)
    print(f"wrote {output} size={image.size} alpha={image.getchannel('A').getextrema()} bbox={image.getbbox()}")


if __name__ == "__main__":
    main()
