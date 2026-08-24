"""Prepare four complete wrapper directions and repaired press transparency."""

from pathlib import Path
from PIL import Image
from collections import deque

ROOT = Path(__file__).resolve().parents[1]
MACHINES = ROOT / "assets" / "Machines"
GENERATED = ROOT / "assets" / "generated"

def remove_bright_checker(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    pixels = image.load()
    width, height = image.size
    seen = bytearray(width * height)
    queue = deque([(x, 0) for x in range(width)] + [(x, height - 1) for x in range(width)]
        + [(0, y) for y in range(1, height - 1)] + [(width - 1, y) for y in range(1, height - 1)])
    while queue:
        x, y = queue.popleft()
        index = y * width + x
        red, green, blue, alpha = pixels[x, y]
        bright_neutral = max(red, green, blue) - min(red, green, blue) <= 10 and min(red, green, blue) >= 222
        if seen[index] or not bright_neutral:
            continue
        seen[index] = 1
        pixels[x, y] = (red, green, blue, 0)
        if x: queue.append((x - 1, y))
        if x + 1 < width: queue.append((x + 1, y))
        if y: queue.append((x, y - 1))
        if y + 1 < height: queue.append((x, y + 1))
    return image

def fit_frame(image: Image.Image, size: int = 512, margin: int = 26) -> Image.Image:
    cleaned = remove_bright_checker(image)
    bbox = cleaned.getchannel("A").getbbox()
    if not bbox:
        raise ValueError("machine frame is empty after background cleanup")
    subject = cleaned.crop(bbox)
    extent = size - margin * 2
    scale = min(extent / subject.width, extent / subject.height)
    subject = subject.resize((max(1, round(subject.width * scale)), max(1, round(subject.height * scale))), Image.Resampling.LANCZOS)
    frame = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    frame.alpha_composite(subject, ((size - subject.width) // 2, size - subject.height - margin))
    return frame

def wrapper_strip() -> None:
    source = Image.open(MACHINES / "skid-wrapper-directions-source.png").convert("RGBA")
    frames = []
    authored = []
    for index in range(4):
        left = round(index * source.width / 4)
        right = round((index + 1) * source.width / 4)
        authored.append(fit_frame(source.crop((left, 0, right, source.height))))
    # Generated order: SE, SW, NW, NE. Runtime order: NW, NE, SW, SE.
    frames = [authored[index] for index in (2, 3, 1, 0)]
    strip = Image.new("RGBA", (2048, 512), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * 512, 0))
    strip.save(GENERATED / "skid-wrapper-directions-strip.png")

def picture_press() -> None:
    frame = fit_frame(Image.open(MACHINES / "picture-press-transparent-source.png"), 1024)
    frame.save(GENERATED / "picture-press-transparent.png")

if __name__ == "__main__":
    wrapper_strip()
    picture_press()
    print("prepared repaired wrapper directions and picture press transparency")
