"""Deterministic runtime sizing of the authored break-room source sprites."""
from pathlib import Path
from shutil import copyfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/breakroom-minigames-v1"
OUTPUT = ROOT / "assets/generated/breakroom-games-v1"
OUTPUT.mkdir(parents=True, exist_ok=True)


def load(name):
    return Image.open(SOURCE / name).convert("RGBA")


def trim(image, threshold=8):
    alpha = image.getchannel("A").point(lambda a: 255 if a > threshold else 0)
    box = alpha.getbbox()
    return image.crop(box) if box else image


def fit(image, width=None, height=None):
    if width is None:
        width = round(image.width * height / image.height)
    if height is None:
        height = round(image.height * width / image.width)
    return image.resize((width, height), Image.Resampling.LANCZOS)


for source, target, size in [
    ("world-air-hockey-table-v1.png", "air-hockey-table.png", (204, None)),
    ("world-basketball-v1.png", "basketball.png", (24, 24)),
    ("world-critter-kombat-cabinet-v1.png", "critter-kombat-cabinet.png", (91, None)),
    ("gui-air-hockey-rink-v1.png", "air-hockey-rink.png", (800, 400)),
]:
    img = trim(load(source))
    img = fit(img, width=size[0], height=size[1])
    img.save(OUTPUT / target, optimize=True)

# All three goal poses share one crop and one resize. A net or rim reaction can
# then swap frames without shifting the heavy wheeled base or backboard.
goal_sources = {
    "idle": load("world-basketball-portable-idle-v1.png"),
    "rim": load("world-basketball-portable-rim-v1.png"),
    "score": load("world-basketball-portable-score-v1.png"),
}
boxes = [image.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
         for image in goal_sources.values()]
goal_box = (min(box[0] for box in boxes), min(box[1] for box in boxes),
            max(box[2] for box in boxes), max(box[3] for box in boxes))
goal_height = 235
goal_width = round((goal_box[2] - goal_box[0]) * goal_height / (goal_box[3] - goal_box[1]))
for pose, image in goal_sources.items():
    image.crop(goal_box).resize((goal_width, goal_height), Image.Resampling.LANCZOS).save(
        OUTPUT / f"basketball-goal-{pose}.png", optimize=True)

pieces = load("gui-air-hockey-pieces-atlas-v1.png")
cell = pieces.width // 3
for i, name in enumerate(("orange-striker", "teal-striker", "puck")):
    sprite = trim(pieces.crop((i * cell, 0, (i + 1) * cell, pieces.height)))
    fit(sprite, width=54 if i < 2 else 30).save(OUTPUT / (name + ".png"), optimize=True)

fit(load("gui-critter-kombat-rail-yard-v1.png"), width=800, height=450).save(
    OUTPUT / "critter-kombat-rail-yard.png", optimize=True)

# Preserve the five ImageGen action atlases byte-for-byte. Westward views use
# the same intentional horizontal mirroring as the established walk rig.
for direction in ("north", "northeast", "east", "southeast", "south"):
    name = f"basketball-actions-{direction}.png"
    copyfile(SOURCE / name, OUTPUT / name)
for fighter in ("fox", "mouse"):
    name = f"critter-kombat-{fighter}-actions.png"
    copyfile(SOURCE / name, OUTPUT / name)

copyfile(SOURCE / "shop-breakroom-clear-wall-v1.png",
         ROOT / "assets/generated/shop-breakroom-games-v1.png")
