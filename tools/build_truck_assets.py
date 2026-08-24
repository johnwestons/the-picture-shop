"""Prepare the approved truck and an independent cargo-door animation strip."""
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OPEN_SOURCE = ROOT / "output/truck-open-source.png"
CLOSED_SOURCE = ROOT / "output/truck-closed-source.png"
TRUCK_OUTPUT = ROOT / "assets/generated/delivery-truck-open.png"
DOOR_OUTPUT = ROOT / "assets/generated/truck-cargo-door-strip.png"
PREVIEW_OUTPUT = ROOT / "output/truck-cargo-door-animation-preview.png"

SOURCE_BOX = (130, 0, 1330, 1024)
FRAME_SIZE = 512
INNER_SIZE = (496, 423)
OFFSET = (8, 44)
FRAME_PROGRESS = (0.0, 0.25, 0.50, 0.75, 1.0)

# Closed rear-door aperture in full source coordinates.
TOP_LEFT = (956, 426)
TOP_RIGHT = (1250, 335)
BOTTOM_RIGHT = (1250, 719)
BOTTOM_LEFT = (956, 811)


def normalized_y(left_y: float, right_y: float, x: int) -> float:
    ratio = (x - TOP_LEFT[0]) / (TOP_RIGHT[0] - TOP_LEFT[0])
    return left_y + (right_y - left_y) * ratio


def cargo_mask(progress: float, size: tuple[int, int]) -> Image.Image:
    mask = Image.new("L", size, 0)
    pixels = mask.load()
    if progress >= 1:
        return mask
    for x in range(TOP_LEFT[0], TOP_RIGHT[0] + 1):
        top = normalized_y(TOP_LEFT[1], TOP_RIGHT[1], x)
        bottom = normalized_y(BOTTOM_LEFT[1], BOTTOM_RIGHT[1], x)
        visible_until = top + (bottom - top) * (1 - progress)
        for y in range(max(0, int(top)), min(size[1], int(visible_until) + 1)):
            pixels[x, y] = 255
    return mask


def fit_to_frame(image: Image.Image) -> Image.Image:
    cropped = image.crop(SOURCE_BOX).resize(INNER_SIZE, Image.Resampling.NEAREST)
    frame = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
    frame.alpha_composite(cropped, OFFSET)
    return frame


def main() -> None:
    opened = Image.open(OPEN_SOURCE).convert("RGBA")
    closed = Image.open(CLOSED_SOURCE).convert("RGBA")
    if opened.size != closed.size:
        raise SystemExit(f"truck sources must align: open={opened.size} closed={closed.size}")

    truck = fit_to_frame(opened)
    strip = Image.new("RGBA", (FRAME_SIZE * len(FRAME_PROGRESS), FRAME_SIZE), (0, 0, 0, 0))
    previews = []
    for index, progress in enumerate(FRAME_PROGRESS):
        full_layer = Image.new("RGBA", closed.size, (0, 0, 0, 0))
        mask = cargo_mask(progress, closed.size)
        full_layer.paste(closed, (0, 0), mask)
        layer = fit_to_frame(full_layer)
        strip.alpha_composite(layer, (index * FRAME_SIZE, 0))
        preview = truck.copy()
        preview.alpha_composite(layer)
        previews.append(preview)

    TRUCK_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    PREVIEW_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    truck.save(TRUCK_OUTPUT)
    strip.save(DOOR_OUTPUT)

    gap = 8
    sheet = Image.new("RGBA", (FRAME_SIZE * 5 + gap * 4, FRAME_SIZE), (25, 27, 29, 255))
    for index, preview in enumerate(previews):
        sheet.alpha_composite(preview, (index * (FRAME_SIZE + gap), 0))
    sheet.save(PREVIEW_OUTPUT)
    print(f"wrote {TRUCK_OUTPUT}")
    print(f"wrote {DOOR_OUTPUT}")
    print(f"wrote {PREVIEW_OUTPUT}")


if __name__ == "__main__":
    main()
