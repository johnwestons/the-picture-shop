from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "output" / "manual-mockups"
OUTPUT = ROOT / "assets" / "generated" / "heidelberg-operator-handbook-atlas-v2.png"
CELL = 512
PADDING = 12

# Help-page order: safety/controls, stock, chase, packing, rollers, ink,
# feeder suction, register, washup, and lubrication/service.
FILES = [
    "pixel-press-controls-gloves-v1.png",
    "pixel-feed-stock-gloves-v1.png",
    "pixel-chase-lockup-gloves-v1.png",
    "pixel-packing-clamp-gloves-mockup-v1.png",
    "pixel-form-rollers-gloves-v1.png",
    "pixel-ink-flow-gloves-v1.png",
    "pixel-sucker-bar-gloves-v1.png",
    "pixel-register-guide-gloves-v1.png",
    "pixel-washup-gloves-v1.png",
    "pixel-lubrication-gloves-v1.png",
]


def fitted(image: Image.Image) -> Image.Image:
    image = image.convert("RGB")
    limit = CELL - PADDING * 2
    scale = min(limit / image.width, limit / image.height)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    return image.resize(size, Image.Resampling.NEAREST)


OUTPUT.parent.mkdir(parents=True, exist_ok=True)
atlas = Image.new("RGB", (CELL * 5, CELL * 2), "#eee8da")
for index, filename in enumerate(FILES):
    with Image.open(SOURCE / filename) as source:
        image = fitted(source)
    x = (index % 5) * CELL + (CELL - image.width) // 2
    y = (index // 5) * CELL + (CELL - image.height) // 2
    atlas.paste(image, (x, y))
atlas.save(OUTPUT, optimize=True)
