"""Create an offline placement preview without loading or changing game saves."""

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets/generated/breakroom-games-v1"
OUTPUT = ROOT / "output/breakroom-portable-goal-preview.png"
REACTIONS = ROOT / "output/breakroom-portable-goal-reactions.png"


def prop(canvas, name, x, y, mirror=False):
    image = Image.open(ASSETS / name).convert("RGBA")
    if mirror:
        image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    canvas.alpha_composite(image, (round(x - image.width / 2), round(y - image.height)))


def main():
    room = Image.open(ROOT / "assets/generated/shop-breakroom-games-v1.png").convert("RGBA")
    room = room.resize((960, 678), Image.Resampling.LANCZOS)
    prop(room, "air-hockey-table.png", 465, 417)
    prop(room, "basketball-goal-idle.png", 90, 500)
    prop(room, "critter-kombat-cabinet.png", 887, 430, mirror=True)
    prop(room, "basketball.png", 240, 315)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    room.convert("RGB").save(OUTPUT)
    sheet = Image.new("RGBA", (720, 300), (34, 37, 38, 255))
    labels = (("idle", "AT REST"), ("rim", "RIM HIT"), ("score", "MADE BASKET"))
    draw = ImageDraw.Draw(sheet)
    for index, (pose, label) in enumerate(labels):
        sprite = Image.open(ASSETS / f"basketball-goal-{pose}.png").convert("RGBA")
        sheet.alpha_composite(sprite, (index * 240 + 43, 32))
        draw.text((index * 240 + 78, 274), label, fill=(245, 216, 142))
    sheet.convert("RGB").save(REACTIONS)
    print(OUTPUT)
    print(REACTIONS)


if __name__ == "__main__":
    main()
