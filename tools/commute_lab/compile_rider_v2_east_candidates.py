"""Mechanically crop east-only v2 walk candidates into isolated review stages.

This tool never edits the shared rider staging set or runtime files. It crops
the two generated 4x2 sheets and applies the same uniform 214px normalization
and provisional helmet/ground anchoring used by the v2 review compiler.
"""
import hashlib
import json
from pathlib import Path
from statistics import median

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/source/commute-rider-v2'
STAGING = ROOT / 'assets/staging'
REVIEW = ROOT / 'output/commute-rider-v2-review/east-candidates'
FRAME = 256
BASELINE = 238
TARGET_HEIGHT = 214
ALPHA_THRESHOLD = 16


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def crop_cell(image, col, row):
    width, height = image.size
    rect = (round(col * width / 4), round(row * height / 2),
            round((col + 1) * width / 4), round((row + 1) * height / 2))
    return rect, image.crop(rect)


def bounds(image):
    alpha = image.getchannel('A').point(lambda value: 255 if value > ALPHA_THRESHOLD else 0)
    return alpha.getbbox()


def helmet_center(image, box):
    top, bottom = box[1], box[3]
    part = image.crop((0, top, image.width, min(bottom, top + round((bottom - top) * .36))))
    head = bounds(part)
    if not head:
        raise ValueError('Could not locate the top helmet silhouette.')
    return (head[0] + head[2] - 1) * .5


def stage(candidate, source_name):
    source_path = SOURCE / source_name
    image = Image.open(source_path).convert('RGBA')
    frames, rects = [], []
    for row in range(2):
        for col in range(4):
            rect, frame = crop_cell(image, col, row)
            frames.append(frame)
            rects.append(rect)
    boxes = [bounds(frame) for frame in frames]
    if any(not box for box in boxes):
        raise ValueError(f'{source_name} contains an empty source cell.')
    scale = TARGET_HEIGHT / median(box[3] - box[1] for box in boxes)
    strip = Image.new('RGBA', (FRAME * 8, FRAME))
    records = []
    for i, (frame, box, rect) in enumerate(zip(frames, boxes, rects)):
        head_x = helmet_center(frame, box)
        ground_y = box[3] - 1
        size = (round(frame.width * scale), round(frame.height * scale))
        scaled = frame.resize(size, Image.Resampling.LANCZOS)
        position = (round(FRAME * .5 - head_x * scale), round(BASELINE - ground_y * scale))
        tile = Image.new('RGBA', (FRAME, FRAME))
        tile.alpha_composite(scaled, position)
        tile_box = bounds(tile)
        if not tile_box or min(tile_box[0], tile_box[1], FRAME - tile_box[2], FRAME - tile_box[3]) < 2:
            raise ValueError(f'{source_name}, frame {i+1} is clipped or too near the stage edge: {tile_box}')
        strip.alpha_composite(tile, (i * FRAME, 0))
        records.append({
            'frame': i + 1, 'sourceRect': list(rect), 'sourceBounds': list(box),
            'stageBounds': list(tile_box), 'helmetCenterX': head_x,
            'lowestSourceY': ground_y, 'stageAnchor': [FRAME // 2, BASELINE],
        })

    stage_dir = STAGING / f'commute-rider-v2-east-{candidate}'
    stage_dir.mkdir(parents=True, exist_ok=True)
    strip_path = stage_dir / 'walk_east_candidate.png'
    strip.save(strip_path)
    manifest = {
        'status': 'isolated_candidate_review_only', 'runtimeIntegrated': False,
        'candidate': candidate, 'direction': 'east', 'frameSize': [FRAME, FRAME],
        'frameCount': 8, 'targetVisibleHeight': TARGET_HEIGHT,
        'anchor': [FRAME // 2, BASELINE],
        'anchorMethod': 'provisional helmet-center x + lowest-alpha-row y',
        'source': source_path.relative_to(ROOT).as_posix(), 'sourceSha256': sha(source_path),
        'stagedStrip': strip_path.relative_to(ROOT).as_posix(),
        'stagedSha256': sha(strip_path), 'uniformScale': round(scale, 6),
        'frames': records,
        'pending': [
            'Manual near/right and far/left support/swing review for every pose',
            'Opposite contact, passing and up-pose comparison',
            'Native LÖVE review; no runtime acceptance',
        ],
    }
    (stage_dir / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    return candidate, strip_path, manifest


def contacts(entries):
    REVIEW.mkdir(parents=True, exist_ok=True)
    labels = ['1 left_contact', '2 left_down', '3 right_passing', '4 right_up',
              '5 right_contact', '6 right_down', '7 left_passing', '8 left_up']
    try:
        font = ImageFont.truetype('arial.ttf', 15)
    except OSError:
        font = ImageFont.load_default()
    canvas = Image.new('RGB', (FRAME * 8, (FRAME + 26) * len(entries)), '#526872')
    draw = ImageDraw.Draw(canvas)
    for row, (candidate, path, _) in enumerate(entries):
        strip = Image.open(path).convert('RGBA')
        y = row * (FRAME + 26)
        draw.text((8, y + 5), candidate.upper(), font=font, fill='white')
        for i, label in enumerate(labels):
            crop = strip.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME))
            x = i * FRAME
            canvas.paste(crop, (x, y + 26), crop)
            draw.text((x + 6, y + 6), label, font=font, fill='#f7edcb')
            draw.line((x, y + 26 + BASELINE, x + FRAME, y + 26 + BASELINE), fill='#a2c7b9', width=1)
    path = REVIEW / 'east-candidates-contact.png'
    canvas.save(path)
    return path


def main():
    entries = [
        stage('alt1', 'walk-east-v2-alt1.png'),
        stage('alt2', 'walk-east-v2-alt2.png'),
    ]
    contact = contacts(entries)
    report = {
        'status': 'candidate_comparison_unapproved', 'runtimeIntegrated': False,
        'direction': 'east', 'phaseOrder': [
            'left_contact', 'left_down', 'right_passing', 'right_up',
            'right_contact', 'right_down', 'left_passing', 'left_up',
        ],
        'contactSheet': contact.relative_to(ROOT).as_posix(),
        'candidates': [manifest for _, _, manifest in entries],
        'note': 'Compiler output is a mechanical crop/normalization only. No phase or gait claim is implied.',
    }
    (REVIEW / 'compiler-review.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(f'Staged {len(entries)} isolated east candidates; review only; contact={contact.relative_to(ROOT).as_posix()}')


if __name__ == '__main__':
    main()
