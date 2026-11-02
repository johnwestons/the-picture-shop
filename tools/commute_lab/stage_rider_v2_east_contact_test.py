"""Stage two generated east contact-pose experiments for isolated visual review."""
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/source/commute-rider-v2'
STAGE = ROOT / 'assets/staging/commute-rider-v2-east-contact-test'
REVIEW = ROOT / 'output/commute-rider-v2-review/east-candidates'
FRAME = 256
BASELINE = 238
TARGET_HEIGHT = 214
ALPHA_THRESHOLD = 16
POSES = [
    ('left-contact', 'walk-east-left-contact-v2.png', 'walk-east-left-contact-v2-prompt.txt'),
    ('right-contact-edit', 'walk-east-right-contact-edit-v2.png', 'walk-east-right-contact-edit-v2-prompt.txt'),
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def box(image):
    alpha = image.getchannel('A').point(lambda value: 255 if value > ALPHA_THRESHOLD else 0)
    return alpha.getbbox()


def helmet_center(image, bounds):
    top, bottom = bounds[1], bounds[3]
    cap = image.crop((0, top, image.width, min(bottom, top + round((bottom - top) * .36))))
    found = box(cap)
    if not found:
        raise ValueError('Missing helmet silhouette in the top band.')
    return (found[0] + found[2] - 1) * .5


def main():
    STAGE.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    strip = Image.new('RGBA', (FRAME * len(POSES), FRAME))
    records = []
    for index, (label, image_name, prompt_name) in enumerate(POSES):
        source_path = SOURCE / image_name
        prompt_path = SOURCE / prompt_name
        image = Image.open(source_path).convert('RGBA')
        bounds = box(image)
        if not bounds:
            raise ValueError(f'{image_name} has no visible pixels.')
        scale = TARGET_HEIGHT / (bounds[3] - bounds[1])
        head_x = helmet_center(image, bounds)
        ground_y = bounds[3] - 1
        size = (round(image.width * scale), round(image.height * scale))
        scaled = image.resize(size, Image.Resampling.LANCZOS)
        position = (round(FRAME * .5 - head_x * scale), round(BASELINE - ground_y * scale))
        tile = Image.new('RGBA', (FRAME, FRAME))
        tile.alpha_composite(scaled, position)
        staged_bounds = box(tile)
        if not staged_bounds or min(staged_bounds[0], staged_bounds[1], FRAME - staged_bounds[2], FRAME - staged_bounds[3]) < 2:
            raise ValueError(f'{image_name} clips after staging: {staged_bounds}')
        strip.alpha_composite(tile, (index * FRAME, 0))
        records.append({
            'pose': label, 'source': source_path.relative_to(ROOT).as_posix(),
            'sourceSha256': sha(source_path), 'prompt': prompt_path.relative_to(ROOT).as_posix(),
            'promptSha256': sha(prompt_path), 'sourceBounds': list(bounds),
            'stageBounds': list(staged_bounds), 'uniformScale': round(scale, 6),
            'stageAnchor': [FRAME // 2, BASELINE], 'phaseApproved': False,
        })
    strip_path = STAGE / 'east-contact-pair.png'
    strip.save(strip_path)
    manifest = {
        'status': 'isolated_pose_test_unapproved', 'runtimeIntegrated': False,
        'direction': 'east', 'frameSize': [FRAME, FRAME], 'targetVisibleHeight': TARGET_HEIGHT,
        'anchor': [FRAME // 2, BASELINE], 'stagedStrip': strip_path.relative_to(ROOT).as_posix(),
        'stagedSha256': sha(strip_path), 'poses': records,
        'manualFinding': 'The edited right-contact candidate moves the forward knee/boot to the near-side leg, but the forward screen-right arm still appears to match the left-contact reference. This pair is not accepted as a gait sequence.',
        'pending': ['Verify limb side labels at native scale', 'Generate distinct passing/up poses', 'Review counter-swing before any integration'],
    }
    (STAGE / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')

    try:
        font = ImageFont.truetype('arial.ttf', 16)
    except OSError:
        font = ImageFont.load_default()
    board = Image.new('RGB', (FRAME * 2, FRAME + 32), '#526872')
    draw = ImageDraw.Draw(board)
    for index, (label, _, _) in enumerate(POSES):
        tile = strip.crop((index * FRAME, 0, (index + 1) * FRAME, FRAME))
        board.paste(tile, (index * FRAME, 32), tile)
        draw.text((index * FRAME + 6, 7), label, font=font, fill='white')
        draw.line((index * FRAME, 32 + BASELINE, (index + 1) * FRAME, 32 + BASELINE), fill='#a2c7b9', width=1)
    review_path = REVIEW / 'east-contact-pair-native-size.png'
    board.save(review_path)
    review = {
        'status': 'unapproved', 'runtimeIntegrated': False,
        'stagedManifest': (STAGE / 'manifest.json').relative_to(ROOT).as_posix(),
        'nativeSizeReviewBoard': review_path.relative_to(ROOT).as_posix(),
        'poses': records, 'finding': manifest['manualFinding'],
        'note': 'Mechanical crop/normalization and static visual inspection only; no gait acceptance claim.',
    }
    (REVIEW / 'east-contact-pair-review.json').write_text(json.dumps(review, indent=2) + '\n', encoding='utf-8')
    print(f'Staged east contact pair for isolated review: {strip_path.relative_to(ROOT).as_posix()}')


if __name__ == '__main__':
    main()
