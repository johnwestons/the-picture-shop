"""Build deterministic loading-bay animation layers from approved artwork.

The warehouse stays as the closed-door base. Each strip frame contains only
the portion of the approved open-bay edit that should replace the shutter,
so every pixel outside the doorway remains untouched at runtime.
"""
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ORIGINAL = ROOT / "assets/generated/warehouse-layout-final.png"
OPEN_SOURCE = ROOT / "output/loading-bay-open-generated.png"
STRIP_OUTPUT = ROOT / "assets/generated/loading-bay-door-strip.png"
PREVIEW_OUTPUT = ROOT / "output/loading-bay-animation-preview.png"

CROP_X, CROP_Y = 200, 170
FRAME_WIDTH, FRAME_HEIGHT = 260, 260
FRAME_PROGRESS = (0.0, 0.25, 0.50, 0.75, 1.0)

# Door aperture in crop-local pixels: top-left, top-right, bottom-right,
# bottom-left. These points sit inside the steel frame and yellow bollards.
TOP_LEFT = (20, 55)
TOP_RIGHT = (232, 17)
BOTTOM_RIGHT = (232, 203)
BOTTOM_LEFT = (20, 242)


def edge_y(left_y: float, right_y: float, x: int) -> float:
    ratio = (x - TOP_LEFT[0]) / (TOP_RIGHT[0] - TOP_LEFT[0])
    return left_y + (right_y - left_y) * ratio


def reveal_mask(progress: float) -> Image.Image:
    mask = Image.new("L", (FRAME_WIDTH, FRAME_HEIGHT), 0)
    pixels = mask.load()
    if progress <= 0:
        return mask
    for x in range(TOP_LEFT[0], TOP_RIGHT[0] + 1):
        top = edge_y(TOP_LEFT[1], TOP_RIGHT[1], x)
        bottom = edge_y(BOTTOM_LEFT[1], BOTTOM_RIGHT[1], x)
        reveal_from = bottom - (bottom - top) * progress
        for y in range(max(0, int(reveal_from)), min(FRAME_HEIGHT, int(bottom) + 1)):
            pixels[x, y] = 255
    return mask


def main() -> None:
    original = Image.open(ORIGINAL).convert("RGBA")
    opened = Image.open(OPEN_SOURCE).convert("RGBA")
    if original.size != opened.size:
        width_delta = abs(original.width - opened.width)
        height_delta = abs(original.height - opened.height)
        if width_delta > 2 or height_delta > 2:
            raise SystemExit(f"open artwork {opened.size} must match warehouse {original.size}")
        opened = opened.resize(original.size, Image.Resampling.NEAREST)

    box = (CROP_X, CROP_Y, CROP_X + FRAME_WIDTH, CROP_Y + FRAME_HEIGHT)
    original_crop = original.crop(box)
    open_crop = opened.crop(box)
    strip = Image.new("RGBA", (FRAME_WIDTH * len(FRAME_PROGRESS), FRAME_HEIGHT), (0, 0, 0, 0))
    previews = []

    for index, progress in enumerate(FRAME_PROGRESS):
        mask = reveal_mask(progress)
        layer = Image.new("RGBA", (FRAME_WIDTH, FRAME_HEIGHT), (0, 0, 0, 0))
        layer.paste(open_crop, (0, 0), mask)
        strip.paste(layer, (index * FRAME_WIDTH, 0), layer)

        preview = original_crop.copy()
        preview.alpha_composite(layer)
        previews.append(preview)

    STRIP_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    PREVIEW_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    strip.save(STRIP_OUTPUT)

    gap = 8
    preview_sheet = Image.new(
        "RGBA",
        (FRAME_WIDTH * len(previews) + gap * (len(previews) - 1), FRAME_HEIGHT),
        (24, 25, 27, 255),
    )
    for index, preview in enumerate(previews):
        preview_sheet.alpha_composite(preview, (index * (FRAME_WIDTH + gap), 0))
    preview_sheet.save(PREVIEW_OUTPUT)
    print(f"wrote {STRIP_OUTPUT}")
    print(f"wrote {PREVIEW_OUTPUT}")


if __name__ == "__main__":
    main()
