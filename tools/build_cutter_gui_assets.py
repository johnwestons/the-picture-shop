"""Install the approved cutter source and build aligned pixel-art control overlays."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "output" / "polar-cutter-console-source.png"
GENERATED = ROOT / "assets" / "generated"
FRAME = 128


def button_frame(color: tuple[int, int, int], pressed: bool) -> Image.Image:
    image = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    y = 12 if not pressed else 19
    draw.rectangle((14, y + 8, 114, y + 102), fill=(65, 69, 74, 255), outline=(18, 20, 23, 255), width=5)
    draw.rectangle((21, y + 15, 107, y + 95), fill=(142, 147, 151, 255), outline=(205, 209, 211, 255), width=3)
    shadow = tuple(max(0, channel - 75) for channel in color)
    draw.ellipse((31, y + 25, 97, y + 91), fill=shadow + (255,), outline=(16, 17, 19, 255), width=5)
    draw.ellipse((35, y + 20, 93, y + 78), fill=color + (255,), outline=(245, 210, 65, 255) if color[0] > 150 else (12, 14, 16, 255), width=4)
    if color[0] < 150:
        draw.polygon(((64, y + 34), (56, y + 47), (61, y + 47), (61, y + 64), (67, y + 64), (67, y + 47), (72, y + 47)), fill=(240, 243, 239, 255))
        draw.polygon(((49, y + 62), (64, y + 78), (79, y + 62), (73, y + 62), (64, y + 70), (55, y + 62)), fill=(240, 243, 239, 255))
    return image


def build_buttons() -> None:
    frames = [
        button_frame((45, 50, 56), False),
        button_frame((45, 50, 56), True),
        button_frame((225, 38, 35), False),
        button_frame((225, 38, 35), True),
    ]
    strip = Image.new("RGBA", (FRAME * len(frames), FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME, 0))
    strip.save(GENERATED / "cutter-control-buttons-strip.png")


def build_motion_strip(name: str, kind: str) -> None:
    frame_width, frame_height, count = 768, 512, 5
    strip = Image.new("RGBA", (frame_width * count, frame_height), (0, 0, 0, 0))
    for index in range(count):
        frame = Image.new("RGBA", (frame_width, frame_height), (0, 0, 0, 0))
        draw = ImageDraw.Draw(frame)
        amount = index / (count - 1)
        if kind == "clamp":
            y = round(188 + amount * 58)
            draw.rectangle((188, y, 580, y + 23), fill=(72, 77, 82, 255), outline=(18, 20, 23, 255), width=4)
            draw.rectangle((201, y + 4, 567, y + 10), fill=(190, 197, 200, 255))
            draw.rectangle((214, y + 19, 554, y + 29), fill=(35, 38, 41, 230))
        else:
            travel = amount if amount <= 0.5 else 1 - amount
            y = round(183 + travel * 2 * 88)
            draw.polygon(((182, y), (586, y), (570, y + 18), (198, y + 18)), fill=(205, 211, 214, 255), outline=(20, 22, 24, 255))
            draw.line((202, y + 14, 566, y + 14), fill=(242, 248, 250, 255), width=3)
        strip.alpha_composite(frame, (index * frame_width, 0))
    strip.save(GENERATED / name)


def main() -> None:
    GENERATED.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE).convert("RGBA")
    source.save(GENERATED / "polar-operator-console.png")
    build_buttons()
    build_motion_strip("cutter-clamp-strip.png", "clamp")
    build_motion_strip("cutter-blade-strip.png", "blade")


if __name__ == "__main__":
    main()
