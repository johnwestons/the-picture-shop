"""Contact sheets for the game's native UI render review (Pillow)."""
from pathlib import Path
import argparse
from PIL import Image, ImageDraw, ImageFont

parser = argparse.ArgumentParser()
parser.add_argument('mode', choices=('desktop', 'phone', 'tablet'))
parser.add_argument('--shared', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
folder = root / 'output' / 'ui-readability' / args.mode
if args.shared:
    folder = folder / 'regression' / 'appdata' / 'LOVE' / ('the-picture-shop-test-ui-'+args.mode)
shots = sorted(p for p in folder.glob('*.png') if not p.name.startswith('sheet-'))
font = ImageFont.truetype(str(root / 'assets/fonts/CourierPrime-Bold.ttf'), 18)
for start in range(0, len(shots), 9):
    sheet = Image.new('RGB', (1440, 1098), '#142023')
    for cell, path in enumerate(shots[start:start+9]):
        shot = Image.open(path).convert('RGB')
        shot.thumbnail((480, 339))
        x, y = (cell % 3) * 480, (cell // 3) * 366
        ImageDraw.Draw(sheet).text((x+8, y+4), path.stem, font=font, fill='#ffe392')
        sheet.paste(shot, (x, y+27))
    sheet.save(folder / f'sheet-{start//9+1:02}.png')
print(f'{len(shots)} captures in {(len(shots)+8)//9} review sheets')
