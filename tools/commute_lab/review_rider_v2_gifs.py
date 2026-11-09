"""Make checker-backed 1x and half-speed previews from staged v2 walk strips."""
from pathlib import Path
from PIL import Image, ImageDraw
import json

ROOT = Path(__file__).resolve().parents[2]
STAGE = ROOT / 'assets/staging/commute-rider-v2'
OUT = ROOT / 'output/commute-rider-v2-review/motion-audit/previews-checker'
DIRECTIONS = ['north', 'northeast', 'east', 'southeast', 'south']
FRAME = 256
ACTUAL_MS = 80


def checker_frame(tile):
    base = Image.new('RGBA', (FRAME, FRAME), '#dfe3e0')
    draw = ImageDraw.Draw(base)
    for y in range(0, FRAME, 16):
        for x in range(0, FRAME, 16):
            if (x // 16 + y // 16) % 2:
                draw.rectangle((x, y, x + 15, y + 15), fill='#c4ccca')
    base.alpha_composite(tile.convert('RGBA'))
    return base.convert('RGB')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    results = {}
    for direction in DIRECTIONS:
        strip = Image.open(STAGE / f'walk_{direction}.png').convert('RGBA')
        assert strip.size == (FRAME * 8, FRAME)
        frames = [checker_frame(strip.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME))) for i in range(8)]
        for label, duration in [('actual', ACTUAL_MS), ('half', ACTUAL_MS * 2)]:
            path = OUT / f'walk_{direction}_{label}_checker.gif'
            frames[0].save(path, save_all=True, append_images=frames[1:], duration=duration,
                           loop=0, optimize=False)
            results[f'{direction}_{label}'] = {
                'path': str(path.relative_to(ROOT)).replace('\\', '/'),
                'frames': 8, 'requestedFrameDurationMs': duration,
                'frameSize': [FRAME, FRAME], 'checkerBackground': True,
            }
    (OUT / 'manifest.json').write_text(json.dumps({
        'status': 'review_preview', 'nominalPoseDurationMs': 1000 * 6.24 / 81.6,
        'gifQuantizedActualMs': ACTUAL_MS, 'halfSpeedMs': ACTUAL_MS * 2,
        'results': results,
    }, indent=2) + '\n', encoding='utf-8')
    print(f'Wrote 1x and half-speed checker GIFs for {len(DIRECTIONS)} directions.')


if __name__ == '__main__':
    main()
