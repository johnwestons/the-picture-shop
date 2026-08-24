"""Prepare the user's approved warehouse reference at the runtime sprite size."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r"C:\Users\johnw\AppData\Local\Temp\codex-clipboard-9561f9aa-8bc8-4f4d-a7fd-6f320d3ea9e6.png")
OUTPUT = ROOT / "assets" / "generated" / "warehouse-layout-final.png"
MASK_SOURCE = ROOT / "assets" / "generated" / "warehouse-layout-v4-walkmask.png"
MASK_OUTPUT = ROOT / "assets" / "generated" / "warehouse-layout-final-walkmask.png"
CANVAS = (1536, 1024)


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    bounds = source.getchannel("A").getbbox()
    if not bounds:
        raise ValueError("Warehouse reference has no visible pixels")

    cropped = source.crop(bounds)
    if cropped.width != CANVAS[0]:
        raise ValueError(f"Unexpected reference width: {cropped.size}")
    if cropped.height > CANVAS[1]:
        raise ValueError(f"Reference is taller than runtime canvas: {cropped.size}")

    result = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    offset_y = (CANVAS[1] - cropped.height) // 2
    result.alpha_composite(cropped, (0, offset_y))
    result.save(OUTPUT)

    mask = Image.open(MASK_SOURCE).convert("RGBA")
    if mask.size != CANVAS:
        raise ValueError(f"Walkmask size mismatch: {mask.size}")
    mask.save(MASK_OUTPUT)


if __name__ == "__main__":
    main()
