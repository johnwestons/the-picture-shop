"""Pack original generated RGBA poses; preserve art, align soles, audit gutters."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import numpy as np
from build_basketball_actions import components

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/source/critter-kombat-v2'
OUTPUT = ROOT / 'assets/generated/critter-kombat-v2'
REVIEW = ROOT / 'output/critter-kombat-v2'
CELL, BASELINE, HEIGHT = 256, 240, 180


def isolate(sprite):
    # Bounding rectangles can overlap a neighbouring raised hand. Keep only
    # this pose's connected original pixels, with one pixel of alpha fringe.
    alpha = np.asarray(sprite.getchannel('A'))
    todo = alpha > 20
    height, width = todo.shape
    largest = []
    for y in range(height):
        for x in np.flatnonzero(todo[y]):
            if not todo[y, x]: continue
            stack, pixels = [(x, y)], []
            todo[y, x] = False
            while stack:
                px, py = stack.pop(); pixels.append((px, py))
                for nx, ny in ((px-1, py), (px+1, py), (px, py-1), (px, py+1)):
                    if 0 <= nx < width and 0 <= ny < height and todo[ny, nx]:
                        todo[ny, nx] = False; stack.append((nx, ny))
            if len(pixels) > len(largest): largest = pixels
    mask = np.zeros((height, width), dtype=np.uint8)
    for x, y in largest: mask[y, x] = 255
    mask = Image.fromarray(mask).filter(ImageFilter.MaxFilter(3))
    sprite.putalpha(ImageChops.multiply(sprite.getchannel('A'), mask))
    return sprite


def build(character, sheet):
    key = f'{character}-{sheet}'
    source = Image.open(SOURCE / f'{key}.png').convert('RGBA')
    cols, rows = (6, 4) if sheet == 'attacks' else (4, 6)
    found = sorted(components(source.getchannel('A')))
    assert len(found) == 24, (key, len(found), 'expected 24 separate complete poses')
    cells = []
    for row in range(rows):
        for _, _, box, _ in sorted(found[row * cols:(row + 1) * cols], key=lambda p: p[1]):
            cells.append(isolate(source.crop(box)))
    scale = HEIGHT / cells[0].height
    atlas = Image.new('RGBA', (CELL * cols, CELL * rows))
    bounds = []
    for index, sprite in enumerate(cells):
        size = tuple(round(n * scale) for n in sprite.size)
        sprite = sprite.resize(size, Image.Resampling.NEAREST)
        feet = sprite.getchannel('A').crop((0, size[1] - 12, size[0], size[1]))
        box = feet.point(lambda a: 255 if a > 80 else 0).getbbox()
        center = (box[0] + box[2]) / 2 if box else size[0] / 2
        if sheet == 'support' and index == 21: center = size[0] / 2
        px, py = round(CELL / 2 - center), BASELINE - size[1]
        px = max(8, min(px, CELL - size[0] - 8))
        assert px >= 8 and py >= 8 and px + size[0] <= CELL - 8, (key, index, size, px, py)
        atlas.alpha_composite(sprite, (index % cols * CELL + px, index // cols * CELL + py))
        bounds.append([px, py, px + size[0], BASELINE])
    atlas.save(OUTPUT / f'{key}.png', optimize=True)
    review = Image.new('RGBA', atlas.size, (35, 44, 52, 255)); review.alpha_composite(atlas)
    draw = ImageDraw.Draw(review)
    for index in range(24):
        x, y = index % cols * CELL, index // cols * CELL
        draw.line((x, y + BASELINE, x + CELL, y + BASELINE), fill=(64, 165, 143))
        draw.text((x + 6, y + 5), str(index + 1), fill='white')
    review.thumbnail((1152, 1152), Image.Resampling.NEAREST)
    review.convert('RGB').save(REVIEW / f'{key}-contact.png')
    return {'source_size': list(source.size), 'columns': cols, 'rows': rows, 'frames': 24,
            'cell': CELL, 'anchor': [128, BASELINE], 'standing_height': HEIGHT, 'bounds': bounds}


if __name__ == '__main__':
    OUTPUT.mkdir(parents=True, exist_ok=True); REVIEW.mkdir(parents=True, exist_ok=True)
    manifest = {f'{c}-{s}': build(c, s) for c in ('mouse', 'fox') for s in ('attacks', 'support')}
    (OUTPUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Packed 96 transparent fighter poses; all have safe gutters and grounded anchors.')
