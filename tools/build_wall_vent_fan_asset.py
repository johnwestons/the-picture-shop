"""Normalize the generated wall-vent concept into a fixed 3-frame game strip."""

from pathlib import Path
import sys

from PIL import Image


CELL = 96
PADDING = 4


def alpha_bbox(image: Image.Image):
    alpha = image.getchannel("A")
    return alpha.getbbox()


def normalize_frame(frame: Image.Image) -> Image.Image:
    bbox = alpha_bbox(frame)
    if bbox is None:
        raise ValueError("generated fan frame has no visible pixels")
    visible = frame.crop(bbox)
    available = CELL - PADDING * 2
    scale = min(available / visible.width, available / visible.height)
    size = (max(1, round(visible.width * scale)), max(1, round(visible.height * scale)))
    visible = visible.resize(size, Image.Resampling.LANCZOS)
    output = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    x = (CELL - visible.width) // 2
    y = CELL - PADDING - visible.height
    output.alpha_composite(visible, (x, y))
    return output


def main(source_name: str, destination_name: str) -> None:
    source = Image.open(source_name).convert("RGBA")
    if source.width % 3 != 0:
        raise ValueError("source image must contain three equal horizontal cells")
    source_cell = source.width // 3
    strip = Image.new("RGBA", (CELL * 3, CELL), (0, 0, 0, 0))
    for index in range(3):
        frame = source.crop((index * source_cell, 0, (index + 1) * source_cell, source.height))
        strip.alpha_composite(normalize_frame(frame), (index * CELL, 0))
    destination = Path(destination_name)
    destination.parent.mkdir(parents=True, exist_ok=True)
    strip.save(destination, optimize=True)
    print(f"saved {destination} ({strip.width}x{strip.height}, RGBA)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: build_wall_vent_fan_asset.py SOURCE DESTINATION")
    main(sys.argv[1], sys.argv[2])
