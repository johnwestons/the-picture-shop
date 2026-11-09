"""Mechanical full-body contact comparison; never paints or assembles body parts."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/source/commute-rider-v2'
OUT = ROOT / 'output/commute-rider-v2-review'
NAMES = ['walk-east-left-contact-v1.png', 'walk-east-right-contact-v3.png']


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    images = [Image.open(SOURCE / name).convert('RGBA') for name in NAMES]
    boxes = [im.getchannel('A').point(lambda a: 255 if a >= 16 else 0).getbbox() for im in images]
    assert all(boxes), 'Empty full-body contact image'
    scale = 900 / max(box[3] - box[1] for box in boxes)
    canvas = Image.new('RGBA', (1600, 1080), (236, 233, 224, 255))
    draw = ImageDraw.Draw(canvas)
    observations = []
    for i, (name, im, box) in enumerate(zip(NAMES, images, boxes)):
        size = (round((box[2]-box[0])*scale), round((box[3]-box[1])*scale))
        assert size[0] <= 760, 'Widen the comparison panel; do not clip a boot'
        tile = im.crop(box).resize(size, Image.Resampling.LANCZOS)
        canvas.alpha_composite(tile, (i*800+(800-size[0])//2, 1000-size[1]))
        draw.text((i*800+25, 20), name+' / common source scale', fill=(30, 40, 45))
        draw.line((i*800+20, 1000, i*800+780, 1000), fill=(100,125,130), width=2)
        observations.append({'source': name, 'alphaThreshold': 16, 'bounds': box,
                             'visibleHeight': box[3]-box[1], 'commonScale': scale})
    canvas.save(OUT / 'east-contact-v1-v3-common-scale.png')
    (OUT / 'east-contact-v1-v3-common-scale.json').write_text(json.dumps(observations, indent=2)+'\n')
    print('Full-body comparison saved; frame/foot-phase acceptance remains a visual review.')


if __name__ == '__main__':
    main()
