"""Mechanically crop and record the generated v2 geared-idle source for review."""
from hashlib import sha256
import json
from pathlib import Path
from statistics import median

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / 'assets/source/commute-rider-v2'
REVIEW_DIR = ROOT / 'output/commute-rider-v2-review'
SHEET = SOURCE_DIR / 'directional-idle-v1.png'
PROMPT = SOURCE_DIR / 'directional-idle-v1-prompt.txt'
REFS = [
    REVIEW_DIR / 'suitup-proportion-reference.png',
    REVIEW_DIR / 'helmet-final-reference.png',
]
DIRECTIONS = ['north', 'northeast', 'east', 'southeast', 'south']
ROWS = ['neutral', 'settle']
ALPHA_THRESHOLD = 16
CONTACT_GAP = 42
BG = '#657982'


def digest(path):
    return sha256(path.read_bytes()).hexdigest()


def grid_cell(sheet, col, row):
    width, height = sheet.size
    rect = (round(col * width / 5), round(row * height / 2),
            round((col + 1) * width / 5), round((row + 1) * height / 2))
    return rect, sheet.crop(rect)


def ground_x(alpha, bounds):
    y = bounds[3] - 1
    centers = []
    for row_y in range(max(bounds[1], y - 15), y + 1):
        run = alpha.crop((0, row_y, alpha.width, row_y + 1)).getbbox()
        if run and run[2] - run[0] >= 4:
            centers.append((run[0] + run[2] - 1) * 0.5)
    return median(centers) if centers else None


def main():
    REVIEW_DIR.mkdir(parents=True, exist_ok=True)
    sheet = Image.open(SHEET).convert('RGBA')
    assert sheet.width >= 5 and sheet.height >= 2
    cell_width = round(sheet.width / 5)
    cell_height = round(sheet.height / 2)
    canvas = Image.new('RGB', (sheet.width, 2 * (cell_height + CONTACT_GAP)), BG)
    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype('arial.ttf', 19)
    except OSError:
        font = ImageFont.load_default()
    records = []
    baseline_rows = [[], []]
    for row, row_name in enumerate(ROWS):
        for col, direction in enumerate(DIRECTIONS):
            rect, cell = grid_cell(sheet, col, row)
            if row_name == 'neutral':
                cell.save(REVIEW_DIR / f'idle-reference-{direction}.png')
            alpha = cell.getchannel('A').point(lambda v: 255 if v > ALPHA_THRESHOLD else 0)
            bounds = alpha.getbbox()
            assert bounds, (row_name, direction, 'empty cell')
            edge_boxes = [
                (0, 0, cell.width, 1), (0, cell.height - 1, cell.width, cell.height),
                (0, 0, 1, cell.height), (cell.width - 1, 0, cell.width, cell.height),
            ]
            clipped = any(alpha.crop(box).getbbox() for box in edge_boxes)
            contact_y = bounds[3] - 1
            baseline_rows[row].append(contact_y)
            offset_x = col * cell_width + (cell_width - cell.width) // 2
            offset_y = row * (cell_height + CONTACT_GAP) + CONTACT_GAP
            canvas.paste(BG, (offset_x, offset_y, offset_x + cell.width, offset_y + cell.height))
            canvas.paste(cell, (offset_x, offset_y), cell)
            draw.text((col * cell_width + 12, row * (cell_height + CONTACT_GAP) + 10),
                      f'{direction.upper()} / {row_name}', font=font, fill='white')
            records.append({
                'direction': direction,
                'pose': row_name,
                'sourceRect': list(rect),
                'cellSize': list(cell.size),
                'alphaBoundsThreshold16': list(bounds),
                'visibleSize': [bounds[2] - bounds[0], bounds[3] - bounds[1]],
                'groundContactY': contact_y,
                'groundBandCenterX': ground_x(alpha, bounds),
                'edgeClippedAtThreshold16': clipped,
            })
    canvas.save(REVIEW_DIR / 'directional-idle-contact.png')
    deltas = [baseline_rows[0][i] - baseline_rows[1][i] for i in range(5)]
    review = {
        'status': 'source_visual_review_candidate',
        'generator': 'built-in imagegen',
        'runtimeIntegrated': False,
        'sourceSheet': str(SHEET.relative_to(ROOT)).replace('\\', '/'),
        'sourceSha256': digest(SHEET),
        'prompt': str(PROMPT.relative_to(ROOT)).replace('\\', '/'),
        'promptSha256': digest(PROMPT),
        'references': [
            {'path': str(path.relative_to(ROOT)).replace('\\', '/'), 'sha256': digest(path)}
            for path in REFS
        ],
        'layout': {
            'columns': DIRECTIONS,
            'rows': ROWS,
            'sheetSize': list(sheet.size),
            'alphaThreshold': ALPHA_THRESHOLD,
            'cropping': 'mechanical equal-cell crop using rounded fifths/two halves; no painting, retouching or per-cell resizing',
            'contactSheet': str((REVIEW_DIR / 'directional-idle-contact.png').relative_to(ROOT)).replace('\\', '/'),
        },
        'checks': {
            'allTenCellsNonEmpty': len(records) == 10,
            'allCellsWithinMarginsAtThreshold16': not any(item['edgeClippedAtThreshold16'] for item in records),
            'neutralGroundContactYByDirection': baseline_rows[0],
            'settleGroundContactYByDirection': baseline_rows[1],
            'neutralMinusSettleGroundY': deltas,
            'neutralSettleBaselineMatchesWithoutRegistration': all(delta == 0 for delta in deltas),
        },
        'visualReview': {
            'observations': [
                'The five columns read as distinct back, back-right three-quarter, right profile, front-right three-quarter and front facings.',
                'All ten poses use a closed opaque visor, enclosed helmet, brown one-piece leathers, gloves and broad boots; no species features are exposed.',
                'The body silhouette retains the suit-up reference long torso and legs; helmet size is proportionate to the body rather than a large mascot head.',
                'Each second-row pose makes a small settle adjustment while preserving its column facing.',
            ],
            'remaining': [
                f'Settle row soles sit {deltas} source pixels above neutral row soles. The downstream compiler must register planted soles; do not play the raw rows without anchor alignment.',
                'Native LÖVE scale/contact comparison and runtime integration remain pending parent coordination.',
            ],
        },
        'frames': records,
    }
    (SOURCE_DIR / 'review.json').write_text(json.dumps(review, indent=2) + '\n', encoding='utf-8')
    print('Reviewed ten source cells; contact sheet and source-only measurements written.')
    print('Neutral minus settle sole rows:', deltas)


if __name__ == '__main__':
    main()
