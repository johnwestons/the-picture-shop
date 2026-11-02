"""Build a mechanical, same-visible-height proportion reference for rider v2."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/commute-rider-v2-review'
OUT.mkdir(parents=True, exist_ok=True)
IDLE_V2 = ROOT / 'assets/source/commute-rider-v2/directional-idle-v1.png'
IDLE_V2_SIZE = Image.open(IDLE_V2).size
IDLE_V2_SE_NEUTRAL = (round(3 * IDLE_V2_SIZE[0] / 5), 0,
                      round(4 * IDLE_V2_SIZE[0] / 5), round(IDLE_V2_SIZE[1] / 2))

SOURCES = [
    ('Normal rabbit\nselected worker idle', ROOT / 'assets/generated/characters/rabbit-worker/idle_southeast.png', (0, 0, 512, 512)),
    ('Suit-up body\nzipper closed, ears exposed', ROOT / 'assets/source/commute-gear-actions-v1/equip-suit-alpha-v2.png', (1152, 512, 1536, 1024)),
    ('Final geared\nhelmet closed, ears enclosed', ROOT / 'assets/source/commute-gear-actions-v1/gloves-helmet-source-v1.png', (1152, 495, 1536, 1024)),
    ('New geared idle\nSE neutral, v2 source', IDLE_V2, IDLE_V2_SE_NEUTRAL),
]

PANEL_W = 380
PANEL_H = 590
CANVAS = (PANEL_W * len(SOURCES), PANEL_H)
TARGET_H = 420
BASELINE = 498
BG = '#edf0ee'
INK = '#25323a'

board = Image.new('RGB', CANVAS, BG)
draw = ImageDraw.Draw(board)
try:
    font = ImageFont.truetype('arial.ttf', 17)
    small = ImageFont.truetype('arial.ttf', 13)
except OSError:
    font = ImageFont.load_default()
    small = ImageFont.load_default()

records = []
for index, (label, path, rect) in enumerate(SOURCES):
    source = Image.open(path).convert('RGBA').crop(rect)
    bounds = source.getchannel('A').point(lambda alpha: 255 if alpha > 16 else 0).getbbox()
    if not bounds:
        raise ValueError(f'No visible pixels: {path}')
    figure = source.crop(bounds)
    if index == 1:
        figure.save(OUT / 'suitup-proportion-reference.png')
    elif index == 2:
        figure.save(OUT / 'helmet-final-reference.png')
    scale = TARGET_H / figure.height
    resized = figure.resize((round(figure.width * scale), TARGET_H), Image.Resampling.LANCZOS)
    x = index * PANEL_W + (PANEL_W - resized.width) // 2
    y = BASELINE - TARGET_H
    board.paste(resized, (x, y), resized)
    draw.line((index * PANEL_W + 20, BASELINE, (index + 1) * PANEL_W - 20, BASELINE), fill='#87969c', width=1)
    draw.multiline_text((index * PANEL_W + 16, 20), label, font=font, fill=INK, spacing=3)
    metric = f'Visible source {figure.width} x {figure.height}px; uniform scale {scale:.3f}'
    draw.text((index * PANEL_W + 16, 544), metric, font=small, fill='#526169')
    records.append({
        'label': label.replace('\n', ' '), 'source': str(path.relative_to(ROOT)),
        'sourceRect': list(rect), 'alphaBoundsWithinCell': list(bounds),
        'visibleSizeBeforeResize': [figure.width, figure.height],
        'uniformScaleTo420pxVisibleHeight': round(scale, 4),
    })

draw.text((16, 572), 'Mechanical crop + uniform visible-height resize; soles aligned. Compare helmet/head, shoulders, torso, hips, legs and boots.', font=small, fill=INK)
board.save(OUT / 'proportion-reference.png')
(OUT / 'proportion-reference.json').write_text(json.dumps({
    'status': 'reference_only', 'visibleHeightPixels': TARGET_H, 'baselineY': BASELINE,
    'method': f'Crop source pose, crop alpha bbox, uniformly resize height to {TARGET_H}px, align lowest visible row.',
    'records': records,
}, indent=2) + '\n', encoding='utf-8')
