"""Normalize the generated machine-delivery flatbed variants for the truck renderer."""
from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    "loaded": ROOT / "output/machine-delivery-flatbed-loaded-source.png",
    "empty": ROOT / "output/machine-delivery-flatbed-empty-source.png",
}
OUTPUTS = {
    "loaded": ROOT / "assets/generated/machine-delivery-flatbed-loaded.png",
    "empty": ROOT / "assets/generated/machine-delivery-flatbed-empty.png",
}

FRAME_SIZE = 512
TARGET_LEFT = 25
TARGET_RIGHT = 487
TARGET_BOTTOM = 454
TARGET_MAX_HEIGHT = 408


def remove_checkerboard(source: Image.Image) -> Image.Image:
    """Remove the generator's edge-connected light neutral checkerboard matte."""
    rgb = source.convert("RGB")
    width, height = rgb.size
    pixels = rgb.load()
    background = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()

    def candidate(x: int, y: int, edge: bool = False) -> bool:
        red, green, blue = pixels[x, y]
        low, high = min(red, green, blue), max(red, green, blue)
        # The checkerboard is a lightly textured 234/254 gray. A slightly
        # wider threshold at the image edge reliably seeds every background
        # region without crossing the truck's dark outline.
        return low >= (205 if edge else 215) and high - low <= 13

    def seed(x: int, y: int) -> None:
        index = y * width + x
        if not background[index] and candidate(x, y, True):
            background[index] = 1
            queue.append((x, y))

    for x in range(width):
        seed(x, 0)
        seed(x, height - 1)
    for y in range(height):
        seed(0, y)
        seed(width - 1, y)

    while queue:
        x, y = queue.popleft()
        for next_x, next_y in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if not (0 <= next_x < width and 0 <= next_y < height):
                continue
            index = next_y * width + next_x
            if not background[index] and candidate(next_x, next_y):
                background[index] = 1
                queue.append((next_x, next_y))

    rgba = rgb.convert("RGBA")
    output = rgba.load()
    for y in range(height):
        row = y * width
        for x in range(width):
            if background[row + x]:
                output[x, y] = (0, 0, 0, 0)

    # Peel away the light matte fringe immediately touching transparency.
    for _ in range(3):
        transparent = rgba.getchannel("A")
        alpha = transparent.load()
        remove: list[tuple[int, int]] = []
        for y in range(1, height - 1):
            for x in range(1, width - 1):
                if alpha[x, y] == 0:
                    continue
                red, green, blue, _ = output[x, y]
                if min(red, green, blue) < 180 or max(red, green, blue) - min(red, green, blue) > 16:
                    continue
                if (alpha[x - 1, y] == 0 or alpha[x + 1, y] == 0
                        or alpha[x, y - 1] == 0 or alpha[x, y + 1] == 0):
                    remove.append((x, y))
        for x, y in remove:
            output[x, y] = (0, 0, 0, 0)
    return rgba


def main() -> None:
    cleaned = {name: remove_checkerboard(Image.open(path)) for name, path in SOURCES.items()}
    boxes = [image.getbbox() for image in cleaned.values()]
    if any(box is None for box in boxes):
        raise SystemExit("flatbed source became empty during background removal")
    union = (
        min(box[0] for box in boxes),
        min(box[1] for box in boxes),
        max(box[2] for box in boxes),
        max(box[3] for box in boxes),
    )
    source_width, source_height = union[2] - union[0], union[3] - union[1]
    scale = min((TARGET_RIGHT - TARGET_LEFT) / source_width, TARGET_MAX_HEIGHT / source_height)
    target_size = (round(source_width * scale), round(source_height * scale))
    offset = (TARGET_LEFT, TARGET_BOTTOM - target_size[1])

    for name, image in cleaned.items():
        sprite = image.crop(union).resize(target_size, Image.Resampling.LANCZOS)
        frame = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        frame.alpha_composite(sprite, offset)
        OUTPUTS[name].parent.mkdir(parents=True, exist_ok=True)
        frame.save(OUTPUTS[name])
        print(f"wrote {OUTPUTS[name]} bbox={frame.getbbox()}")


if __name__ == "__main__":
    main()
