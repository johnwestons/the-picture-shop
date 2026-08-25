"""Build the eight-direction Polar cutter strip used on the shop floor."""

from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CORNER_SOURCE = ROOT / "output" / "polar-cutter-four-directions-final-source.png"
INTERMEDIATE_SOURCE = ROOT / "output" / "polar-cutter-intermediate-directions-source.png"
GENERATED = ROOT / "assets" / "generated"
OUTPUT = ROOT / "output"
FRAME = 512


def remove_bright_checker(image: Image.Image) -> Image.Image:
    """Remove a connected white/light-gray checkerboard exported as pixels."""
    image = image.convert("RGBA")
    pixels = image.load()
    width, height = image.size
    visited = bytearray(width * height)
    queue = deque(
        [(x, 0) for x in range(width)]
        + [(x, height - 1) for x in range(width)]
        + [(0, y) for y in range(1, height - 1)]
        + [(width - 1, y) for y in range(1, height - 1)]
    )
    while queue:
        x, y = queue.popleft()
        offset = y * width + x
        red, green, blue, alpha = pixels[x, y]
        bright_neutral = alpha > 0 and min(red, green, blue) >= 232 \
            and max(red, green, blue) - min(red, green, blue) <= 12
        if visited[offset] or not bright_neutral:
            continue
        visited[offset] = 1
        pixels[x, y] = (red, green, blue, 0)
        if x:
            queue.append((x - 1, y))
        if x + 1 < width:
            queue.append((x + 1, y))
        if y:
            queue.append((x, y - 1))
        if y + 1 < height:
            queue.append((x, y + 1))
    return image


def significant_components(image: Image.Image, keep_detached: bool = True) -> Image.Image:
    image = image.convert("RGBA")
    alpha = image.getchannel("A")
    pixels = alpha.load()
    width, height = image.size
    visited = bytearray(width * height)
    components: list[list[tuple[int, int]]] = []
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
            components.append(component)
    if not components:
        raise ValueError("cutter direction cell is empty")
    largest_size = max(len(component) for component in components)
    if keep_detached:
        kept = [component for component in components
                if len(component) >= max(64, largest_size // 500)]
    else:
        kept = [max(components, key=len)]
    mask = Image.new("L", image.size, 0)
    mask_pixels = mask.load()
    for component in kept:
        for x, y in component:
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


def corner_frames() -> list[Image.Image]:
    source = Image.open(CORNER_SOURCE).convert("RGBA")
    width, height = source.size
    middle_x, middle_y = width // 2, height // 2
    regions = [
        (0, 0, middle_x, middle_y + 48),
        (middle_x, 0, width, middle_y + 48),
        (0, middle_y - 32, middle_x, height),
        (middle_x, middle_y - 32, width, height),
    ]
    return [frame_for(significant_components(source.crop(box), keep_detached=False)) for box in regions]


def intermediate_frames() -> list[Image.Image]:
    source = remove_bright_checker(Image.open(INTERMEDIATE_SOURCE))
    width, height = source.size
    overlap_x = round(width * 0.1)
    overlap_y = round(height * 0.04)
    regions = [
        (0, 0, width // 2 + overlap_x, height // 2 + overlap_y),
        (width // 2 - overlap_x, 0, width, height // 2 + overlap_y),
        (0, height // 2 - overlap_y, width // 2 + overlap_x, height),
        (width // 2 - overlap_x, height // 2 - overlap_y, width, height),
    ]
    return [frame_for(significant_components(source.crop(box), keep_detached=False)) for box in regions]


def main() -> None:
    # Corner source order: NW, NE, SW, SE.
    # Intermediate source order: N, E, S, W.
    corners = corner_frames()
    intermediates = intermediate_frames()
    frames = [
        corners[0], intermediates[0], corners[1], intermediates[1],
        corners[3], intermediates[2], corners[2], intermediates[3],
    ]
    strip = Image.new("RGBA", (FRAME * len(frames), FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * FRAME, 0))
    strip.save(GENERATED / "polar-cutter-directions-strip.png")

    preview = Image.new("RGBA", (FRAME * 4, FRAME * 2), (22, 27, 31, 255))
    for index, frame in enumerate(frames):
        preview.alpha_composite(frame, ((index % 4) * FRAME, (index // 4) * FRAME))
    preview.save(OUTPUT / "polar-cutter-directions-preview.png")


if __name__ == "__main__":
    main()
