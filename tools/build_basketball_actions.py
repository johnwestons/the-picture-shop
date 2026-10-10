"""Pack generated transparent action poses with a common foot anchor.

Only trims, rescales and packs original RGBA; never repaints source art.
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/source/basketball-actions-v2'
OUTPUT = ROOT / 'assets/generated/basketball-actions-v2'
REVIEW = ROOT / 'output/basketball-v2'
CELL, BASELINE, HEIGHT = 256, 240, 196


def components(alpha):
    mask = np.asarray(alpha) > 20
    height, width = mask.shape
    found = []
    for y in range(height):
        for x in np.flatnonzero(mask[y]):
            if not mask[y, x]:
                continue
            stack, area = [(x, y)], 0
            mask[y, x] = False
            left = right = x
            top = bottom = y
            while stack:
                px, py = stack.pop()
                area += 1
                left, right = min(left, px), max(right, px)
                top, bottom = min(top, py), max(bottom, py)
                for nx, ny in ((px-1, py), (px+1, py), (px, py-1), (px, py+1)):
                    if 0 <= nx < width and 0 <= ny < height and mask[ny, nx]:
                        mask[ny, nx] = False
                        stack.append((nx, ny))
            if area > 5000:
                found.append(((top + bottom) / 2, (left + right) / 2,
                              (max(0, left-2), max(0, top-2), min(width, right+3),
                               min(height, bottom+3)), area))
    return found


def build(direction):
    source = Image.open(SOURCE / f'{direction}.png').convert('RGBA')
    width, height = source.size
    # Generated rows need not stop exactly at mathematical cell boundaries.
    # Locate full, disconnected poses before cropping: splitting the original
    # by equal rectangles would sever ears and bring neighboring feet along.
    found = components(source.getchannel('A'))
    assert len(found) == 24, (direction, len(found), 'expected 24 complete poses')
    # Row order is determined by clusters of four complete pose centroids.
    found.sort()
    cells = []
    for row in range(6):
        for _, _, box, area in sorted(found[row * 4:row * 4 + 4], key=lambda p: p[1]):
            cells.append(source.crop(box))
    scale = HEIGHT / cells[0].height
    atlas = Image.new('RGBA', (CELL * 4, CELL * 6))
    bounds = []
    for index, sprite in enumerate(cells):
        size = tuple(round(n * scale) for n in sprite.size)
        sprite = sprite.resize(size, Image.Resampling.LANCZOS)
        # Shoe contact is the stable anchor; raised hands must not shift it.
        feet = sprite.getchannel('A').crop((0, size[1] - 15, size[0], size[1]))
        foot_box = feet.point(lambda a: 255 if a > 80 else 0).getbbox()
        center = (foot_box[0] + foot_box[2]) / 2 if foot_box else size[0] / 2
        px, py = round(CELL / 2 - center), BASELINE - size[1]
        assert px >= 8 and py >= 8 and px + size[0] <= CELL - 8, (direction, index, size)
        atlas.alpha_composite(sprite, (index % 4 * CELL + px, index // 4 * CELL + py))
        bounds.append([px, py, px + size[0], BASELINE])
    atlas.save(OUTPUT / f'{direction}.png', optimize=True)
    review = Image.new('RGBA', atlas.size, (40, 47, 54, 255))
    review.alpha_composite(atlas)
    draw = ImageDraw.Draw(review)
    for index in range(24):
        x, y = index % 4 * CELL, index // 4 * CELL
        draw.line((x, y + BASELINE, x + CELL, y + BASELINE), fill=(78, 170, 159))
        draw.text((x + 6, y + 5), str(index + 1), fill='white')
    review.convert('RGB').save(REVIEW / f'{direction}-contact.png')
    return {'source_size': [width, height], 'cell': CELL, 'foot_anchor': [128, BASELINE],
            'standing_height': HEIGHT, 'frames': 24, 'bounds': bounds}


if __name__ == '__main__':
    OUTPUT.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    manifest = {direction: build(direction) for direction in
                ('north', 'northeast', 'east', 'southeast', 'south')}
    (OUTPUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Packed 120 transparent poses; all have safe gutters and foot anchors.')
