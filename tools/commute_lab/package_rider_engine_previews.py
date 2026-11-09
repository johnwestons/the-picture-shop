#!/usr/bin/env python3
"""Package production-renderer captures into compact in-game rider previews."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
CAPTURES = ROOT / "output/commute-rider-v3-engine-review/suited-walk"
OUTPUT = ROOT / "output/commute-rider-v3-engine-review/previews"
DIRECTIONS = ("north", "northeast", "east", "southeast", "south")
CROP = (420, 452, 520, 560)


def capture(direction: str, frame: int) -> Image.Image:
    path = CAPTURES / (
        f"desktop-suited-rider-suited-walk-host-{direction}-{frame}-{frame}.png"
    )
    image = Image.open(path).convert("RGB")
    return image.crop(CROP)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    font = ImageFont.load_default()
    scale = 2
    thumb_width, thumb_height = (CROP[2] - CROP[0]) * scale, (CROP[3] - CROP[1]) * scale
    margin, header = 8, 20
    sheet = Image.new("RGB", (margin + (thumb_width + margin) * 8,
                               header + margin + (thumb_height + header + margin) * 5),
                      (21, 26, 30))
    draw = ImageDraw.Draw(sheet)

    for row, direction in enumerate(DIRECTIONS):
        sequence = []
        y = header + margin + row * (thumb_height + header + margin)
        draw.text((margin, y - header + 2), f"Walk {direction}", font=font, fill=(238, 210, 130))
        for frame in range(1, 9):
            image = capture(direction, frame).resize((thumb_width, thumb_height), Image.Resampling.NEAREST)
            x = margin + (frame - 1) * (thumb_width + margin)
            sheet.paste(image, (x, y))
            sequence.append(capture(direction, frame).resize((thumb_width, thumb_height), Image.Resampling.NEAREST))
        sequence[0].save(OUTPUT / f"walk_{direction}.gif", save_all=True,
                         append_images=sequence[1:], duration=129, loop=0, optimize=True)

    sheet.save(OUTPUT / "walk-contact-sheet.png", optimize=True)
    print(f"Created five in-game gait loops and one contact sheet in {OUTPUT}")


if __name__ == "__main__":
    main()
