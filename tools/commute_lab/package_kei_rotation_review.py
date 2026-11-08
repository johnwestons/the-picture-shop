"""Package the LÖVE-rendered comparison frames without changing the sprites."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'output/kei-scale-repair'
frames = [Image.open(OUTPUT / f'rotation-{i:03}.png').convert('RGB') for i in range(120)]
frames[0].save(OUTPUT / 'kei-rotation-comparison.gif', save_all=True,
               append_images=frames[1:], duration=50, loop=0, optimize=False)
fixed = []
for frame in frames:
    preview = Image.new('RGB', (840, 340))
    preview.paste(frame.crop((420, 0, 840, 340)), (0, 0))
    preview.paste(frame.crop((420, 340, 840, 680)), (420, 0))
    fixed.append(preview)
fixed[0].save(OUTPUT / 'kei-rotation-fixed.gif', save_all=True,
              append_images=fixed[1:], duration=50, loop=0, optimize=False)
for view, y in [('isometric', 0), ('chase', 340)]:
    sheet = Image.new('RGB', (1200, 720), (59, 69, 74))
    draw = ImageDraw.Draw(sheet)
    for i in range(12):
        cell = frames[i * 10].crop((420, y, 840, y + 340))
        cell.thumbnail((300, 240))
        sheet.paste(cell, ((i % 4) * 300, (i // 4) * 240))
    sheet.save(OUTPUT / f'{view}-rendered-contact.png')
print(OUTPUT / 'kei-rotation-comparison.gif')
