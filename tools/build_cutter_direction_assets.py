"""Build the four-direction Polar cutter strip used on the shop floor."""

from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "output" / "polar-cutter-four-directions-final-source.png"
GENERATED = ROOT / "assets" / "generated"
OUTPUT = ROOT / "output"
FRAME = 512


def largest_component(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    alpha = image.getchannel("A")
    pixels = alpha.load()
    width, height = image.size
    visited = bytearray(width * height)
    largest: list[tuple[int, int]] = []
    for y in range(height):
        for x in range(width):
            offset = y * width + x
            if visited[offset] or pixels[x, y] < 72:
                continue
            queue = deque([(x, y)])
            visited[offset] = 1
            component: list[tuple[int, int]] = []
            while queue:
                px, py = queue.popleft()
                component.append((px, py))
                for ny in range(max(0, py - 1), min(height, py + 2)):
                    for nx in range(max(0, px - 1), min(width, px + 2)):
                        item = ny * width + nx
                        if not visited[item] and pixels[nx, ny] >= 72:
                            visited[item] = 1
                            queue.append((nx, ny))
            if len(component) > len(largest):
                largest = component
    if not largest:
        raise ValueError("cutter direction cell is empty")
    mask = Image.new("L", image.size, 0)
    mask_pixels = mask.load()
    for x, y in largest:
        mask_pixels[x, y] = pixels[x, y]
    image.putalpha(mask)
    bounds = mask.getbbox()
    return image.crop(bounds)


def frame_for(image: Image.Image) -> Image.Image:
    maximum = 488
    scale = min(maximum / image.width, maximum / image.height)
    image = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.NEAREST,
    )
    frame = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    frame.alpha_composite(image, ((FRAME - image.width) // 2, FRAME - image.height - 8))
    return frame


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    width, height = source.size
    middle_x, middle_y = width // 2, height // 2
    regions = [
        (0, 0, middle_x, middle_y + 48),
        (middle_x, 0, width, middle_y + 48),
        (0, middle_y - 32, middle_x, height),
        (middle_x, middle_y - 32, width, height),
    ]
    frames = [frame_for(largest_component(source.crop(box))) for box in regions]
    strip = Image.new("RGBA", (FRAME * 4, FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME, 0))
    strip.save(GENERATED / "polar-cutter-directions-strip.png")

    preview = Image.new("RGBA", (FRAME * 2, FRAME * 2), (22, 27, 31, 255))
    for index, frame in enumerate(frames):
        preview.alpha_composite(frame, ((index % 2) * FRAME, (index // 2) * FRAME))
    preview.save(OUTPUT / "polar-cutter-directions-preview.png")


if __name__ == "__main__":
    main()
