"""Remove a generated warehouse preview's connected checkerboard border."""

from collections import deque
import argparse
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "assets" / "generated" / "warehouse-layout-v2.png"


def is_checker(pixel: tuple[int, int, int]) -> bool:
    red, green, blue = pixel
    return max(pixel) - min(pixel) <= 8 and sum(pixel) // 3 >= 220


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    source_path = parser.parse_args().source
    if not source_path.is_absolute():
        source_path = ROOT / source_path
    source = Image.open(source_path).convert("RGB")
    width, height = source.size
    pixels = source.load()
    visited = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()

    for x in range(width):
        queue.extend(((x, 0), (x, height - 1)))
    for y in range(1, height - 1):
        queue.extend(((0, y), (width - 1, y)))

    while queue:
        x, y = queue.popleft()
        index = y * width + x
        if visited[index] or not is_checker(pixels[x, y]):
            continue
        visited[index] = 1
        if x:
            queue.append((x - 1, y))
        if x + 1 < width:
            queue.append((x + 1, y))
        if y:
            queue.append((x, y - 1))
        if y + 1 < height:
            queue.append((x, y + 1))

    alpha = Image.new("L", (width, height), 255)
    alpha.putdata([0 if value else 255 for value in visited])
    result = source.convert("RGBA")
    result.putalpha(alpha)
    result.save(source_path)


if __name__ == "__main__":
    main()
