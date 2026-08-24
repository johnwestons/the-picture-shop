"""Install sprite-doctor previews after removing connected checkerboard residue."""

from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "output" / "sprite-doctor" / "approved"
DEST_ROOT = ROOT / "assets" / "generated" / "characters"


def neutral(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, _ = pixel
    return max(red, green, blue) - min(red, green, blue) <= 6


def remove_connected_background(frame: Image.Image) -> Image.Image:
    frame = frame.convert("RGBA")
    width, height = frame.size
    pixels = frame.load()
    visited = bytearray(width * height)
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        queue.extend(((x, 0), (x, height - 1)))
    for y in range(1, height - 1):
        queue.extend(((0, y), (width - 1, y)))

    while queue:
        x, y = queue.popleft()
        index = y * width + x
        if visited[index] or not neutral(pixels[x, y]):
            continue
        visited[index] = 1
        for neighbor in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            nx, ny = neighbor
            if 0 <= nx < width and 0 <= ny < height:
                queue.append((nx, ny))

    for y in range(height):
        for x in range(width):
            if visited[y * width + x]:
                red, green, blue, _ = pixels[x, y]
                pixels[x, y] = (red, green, blue, 0)
    return frame


def clean_strip(source: Path, destination: Path) -> None:
    image = Image.open(source).convert("RGBA")
    if image.width % 512 or image.height != 512:
        raise ValueError(f"Doctor output is not a 512px strip: {source} ({image.size})")
    frames = []
    for x in range(0, image.width, 512):
        frame = remove_connected_background(image.crop((x, 0, x + 512, 512)))
        if frame.getchannel("A").getbbox() is None:
            raise ValueError(f"Empty cleaned frame: {source} frame {len(frames) + 1}")
        frames.append(frame)
    result = Image.new("RGBA", image.size, (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        result.alpha_composite(frame, (index * 512, 0))
    destination.parent.mkdir(parents=True, exist_ok=True)
    result.save(destination)


def main() -> None:
    for source in SOURCE_ROOT.glob("*/*.png"):
        destination = DEST_ROOT / source.parent.name / source.name
        clean_strip(source, destination)
        print(f"installed {destination.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
