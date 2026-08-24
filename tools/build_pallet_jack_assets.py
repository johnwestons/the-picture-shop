"""Build fixed four-direction empty and loaded pallet-jack strips."""

from pathlib import Path
from collections import deque
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "output" / "pallet-jack-directions-source.png"
PALLET_STRIP = ROOT / "assets" / "generated" / "loaded-paper-pallet-directions-strip.png"
GENERATED = ROOT / "assets" / "generated"
OUTPUT = ROOT / "output"
FRAME = 256


def clean_crop(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    alpha = image.getchannel("A").point(lambda value: 0 if value < 72 else value)
    image.putalpha(alpha)
    bounds = alpha.getbbox()
    if not bounds:
        raise ValueError("directional cell is empty")
    return image.crop(bounds)


def largest_component(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    width, height = image.size
    alpha = image.getchannel("A")
    pixels = alpha.load()
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
    mask = Image.new("L", image.size, 0)
    mask_pixels = mask.load()
    for x, y in largest:
        mask_pixels[x, y] = pixels[x, y]
    image.putalpha(mask)
    return image


def fit(image: Image.Image, maximum: int) -> Image.Image:
    scale = min(maximum / image.width, maximum / image.height)
    return image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.NEAREST)


def centered_frame(image: Image.Image) -> Image.Image:
    frame = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    frame.alpha_composite(image, ((FRAME - image.width) // 2, FRAME - image.height - 8))
    return frame


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    regions = [
        (0, 0, 768, 480),
        (768, 0, 1536, 480),
        (0, 420, 768, 1024),
        (768, 420, 1536, 1024),
    ]
    empty_frames = [centered_frame(fit(clean_crop(largest_component(source.crop(box))), 238)) for box in regions]
    pallet_strip = Image.open(PALLET_STRIP).convert("RGBA")
    pallets = [fit(clean_crop(pallet_strip.crop((index * FRAME, 0, (index + 1) * FRAME, FRAME))), 124)
        for index in range(4)]
    pallet_positions = [(28, 95), (110, 95), (35, 124), (104, 124)]
    loaded_frames = []
    for index, empty in enumerate(empty_frames):
        loaded = empty.copy()
        loaded.alpha_composite(pallets[index], pallet_positions[index])
        loaded_frames.append(loaded)

    empty_strip = Image.new("RGBA", (FRAME * 4, FRAME), (0, 0, 0, 0))
    loaded_strip = Image.new("RGBA", (FRAME * 4, FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(empty_frames):
        empty_strip.alpha_composite(frame, (index * FRAME, 0))
        loaded_strip.alpha_composite(loaded_frames[index], (index * FRAME, 0))
    empty_strip.save(GENERATED / "pallet-jack-directions-strip.png")
    loaded_strip.save(GENERATED / "pallet-jack-loaded-directions-strip.png")

    preview = Image.new("RGBA", (FRAME * 4, FRAME * 2), (22, 27, 31, 255))
    preview.alpha_composite(empty_strip, (0, 0))
    preview.alpha_composite(loaded_strip, (0, FRAME))
    preview.save(OUTPUT / "pallet-jack-directions-preview.png")


if __name__ == "__main__":
    main()
