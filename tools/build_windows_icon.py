"""Build the Windows tester icon from the approved launcher artwork."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()

    with Image.open(args.source) as opened:
        source = opened.convert("RGBA")
    scale = min(0.88 * 256 / source.width, 0.88 * 256 / source.height)
    resized = source.resize(
        (max(1, round(source.width * scale)), max(1, round(source.height * scale))),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    canvas.alpha_composite(
        resized,
        ((canvas.width - resized.width) // 2, (canvas.height - resized.height) // 2),
    )
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(
        args.destination,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


if __name__ == "__main__":
    main()
