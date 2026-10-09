"""Render the live layered forklift art for a visual registration review.

This is a diagnostic contact sheet. It does not modify source sprites or saves.
"""

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/warehouse-expansion-v1/forklift-layer-study"
OUTPUT = ROOT / "output/warehouse-expansion-v1/forklift-layer-review.png"
SCALE = 0.29  # Twice the in-game source scale for easier inspection.
CELL_W, CELL_H = 440, 360
DIRECTIONS = [
    ("east", "east", 1, (720, 955), (720, 955), 1, 0, 185, 483, None, None),
    ("west", "east", -1, (720, 955), (720, 955), 1, 0, 185, 483, None, None),
    ("southeast", "southeast", 1, (630, 850), (630, 850), .8, 150, 75, 480, None, None),
    ("southwest", "southeast", -1, (630, 850), (630, 850), .8, 150, 75, 480, None, None),
    ("south", "south", 1, (768, 965), (782, 792), .65, 0, 0, 846, None, None),
    ("north", "north", 1, (768, 990), (768, 990), .55, 0, -700, 400, 70, 480),
    ("northeast", "northeast", 1, (680, 890), (680, 890), .8, 265, 150, 563, None, None),
    ("northwest", "northeast", -1, (680, 890), (680, 890), .8, 265, 150, 563, None, None),
]


def paste_layer(canvas, filename, x, y, scale, mirror=1, clip_top=None, clip_bottom=None):
    art = Image.open(SOURCE / filename).convert("RGBA")
    art = art.resize((round(art.width * scale), round(art.height * scale)), Image.Resampling.LANCZOS)
    if mirror == -1:
        art = art.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    layer = Image.new("RGBA", canvas.size)
    layer.alpha_composite(art, (round(x), round(y)))
    if clip_top is not None:
        layer.paste((0, 0, 0, 0), (0, 0, canvas.width, round(clip_top)))
    if clip_bottom is not None:
        layer.paste((0, 0, 0, 0), (0, round(clip_bottom), canvas.width, canvas.height))
    canvas.alpha_composite(layer)


def main():
    canvas = Image.new("RGBA", (CELL_W * 4, CELL_H * 4), (38, 40, 42, 255))
    draw = ImageDraw.Draw(canvas)
    for index, (name, stem, mirror, body_origin, fork_origin, fork_scale,
                fork_x, fork_low, fork_travel, clip_top_source, clip_bottom_source) in enumerate(DIRECTIONS):
        for height_index, height in enumerate((0, 1)):
            column, row = index % 4, (index // 4) * 2 + height_index
            left, top = column * CELL_W, row * CELL_H
            center_x, baseline = left + CELL_W // 2, top + 290
            draw.rectangle((left, top, left + CELL_W - 1, top + CELL_H - 1), outline=(90, 90, 90))
            draw.text((left + 12, top + 10), f"{name.upper()}  {'GROUND' if height == 0 else 'HIGH'}", fill=(255, 220, 130))
            body_path = f"{stem}-fixed-manned-v1.png"
            carriage_version = "v3" if stem == "east" else "v2" if stem in ("northeast", "north", "southeast") else "v1"
            carriage_path = f"{stem}-carriage-{carriage_version}.png"
            body_width = round(1536 * SCALE)
            body_left = center_x - body_origin[0] * SCALE if mirror == 1 else center_x - (1536 - body_origin[0]) * SCALE
            body_top = baseline - body_origin[1] * SCALE
            paste_layer(canvas, body_path, body_left, body_top, SCALE, mirror)
            carriage_scale = SCALE * fork_scale
            shift = fork_low - fork_travel * height
            fork_left = center_x + mirror * fork_x * carriage_scale - (fork_origin[0] if mirror == 1 else 1536 - fork_origin[0]) * carriage_scale
            fork_top = baseline + shift * carriage_scale - fork_origin[1] * carriage_scale
            clip_top = baseline + (clip_top_source - body_origin[1]) * SCALE if clip_top_source else None
            clip_bottom = baseline + (clip_bottom_source - body_origin[1]) * SCALE if clip_bottom_source else None
            paste_layer(canvas, carriage_path, fork_left, fork_top, carriage_scale, mirror, clip_top, clip_bottom)
            draw.line((left + 20, baseline, left + CELL_W - 20, baseline), fill=(98, 165, 170), width=1)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
