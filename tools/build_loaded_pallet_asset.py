"""Build fixed four-direction loaded customer-pallet sprites from the approved source."""

from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "output" / "loaded-pallet-directions-source.png"
GENERATED = ROOT / "assets" / "generated"
OUTPUT = ROOT / "output"
FRAME = 256


def clean_crop(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    alpha = image.getchannel("A").point(lambda value: 0 if value < 72 else value)
    image.putalpha(alpha)
    bounds = alpha.getbbox()
    if not bounds:
        raise ValueError("loaded-pallet direction cell is empty")
    return image.crop(bounds)


def frame_for(image: Image.Image) -> Image.Image:
    scale = min(238 / image.width, 238 / image.height)
    image = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.NEAREST)
    frame = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    frame.alpha_composite(image, ((FRAME - image.width) // 2, FRAME - image.height - 8))
    return frame


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    half_x, half_y = source.width // 2, source.height // 2
    cells = [
        (0, 0, half_x, half_y),
        (half_x, 0, source.width, half_y),
        (0, half_y, half_x, source.height),
        (half_x, half_y, source.width, source.height),
    ]
    frames = [frame_for(clean_crop(source.crop(cell))) for cell in cells]
    strip = Image.new("RGBA", (FRAME * 4, FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME, 0))
    strip.save(GENERATED / "loaded-paper-pallet-directions-strip.png")
    frames[0].save(GENERATED / "loaded-paper-pallet.png")

    preview = Image.new("RGBA", (FRAME * 4, FRAME), (22, 27, 31, 255))
    preview.alpha_composite(strip, (0, 0))
    preview.save(OUTPUT / "loaded-paper-pallet-directions-preview.png")


if __name__ == "__main__":
    main()
