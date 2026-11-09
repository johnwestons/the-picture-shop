"""Stage v2 directional idle/walk source sheets as review-only strips.

This compiler is intentionally separate from the v1 rider compiler and never
publishes runtime assets. It mechanically crops, uniformly rescales each
direction/action strip, aligns helmet-center X and planted-ground Y, and writes
contact sheets plus a motion spec once all five walk views exist.
"""
import argparse
import hashlib
import json
from pathlib import Path
from statistics import median

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/source/commute-rider-v2'
STAGE = ROOT / 'assets/staging/commute-rider-v2'
REVIEW = ROOT / 'output/commute-rider-v2-review'
DIRECTIONS = ['north', 'northeast', 'east', 'southeast', 'south']
WALK_SOURCE_VERSION = {direction: 'v1' for direction in DIRECTIONS}
WALK_SOURCE_VERSION['southeast'] = 'v2'
FRAME = 256
BASELINE = 238
TARGET_HEIGHT = 214
ALPHA_THRESHOLD = 16
PHASES = [
    'left_contact', 'left_down', 'right_passing', 'right_up',
    'right_contact', 'right_down', 'left_passing', 'left_up',
]
MULTIPLIERS = [.96, .94, 1.04, 1.06, .96, .94, 1.04, 1.06]
ACCELERATION = [.92, .90, 1.08, 1.10, .92, .90, 1.08, 1.10]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lua(value):
    if value is None:
        return 'nil'
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, list):
        return '{' + ','.join(lua(item) for item in value) + '}'
    if isinstance(value, dict):
        return '{' + ','.join('[' + lua(key) + ']=' + lua(item) for key, item in value.items()) + '}'
    raise TypeError(type(value))


def cell(image, col, row, cols, rows):
    width, height = image.size
    rect = (round(col * width / cols), round(row * height / rows),
            round((col + 1) * width / cols), round((row + 1) * height / rows))
    return rect, image.crop(rect)


def alpha_bounds(image):
    return image.getchannel('A').point(lambda value: 255 if value > ALPHA_THRESHOLD else 0).getbbox()


def contact_center(image, bounds):
    """Return a lowest-row shoe-band center for review metadata only."""
    alpha = image.getchannel('A').point(lambda value: 255 if value > ALPHA_THRESHOLD else 0)
    bottom = bounds[3] - 1
    xs = []
    for y in range(max(bounds[1], bottom - 3), bottom + 1):
        row = alpha.crop((0, y, image.width, y + 1)).getbbox()
        if row and row[2] - row[0] >= 4:
            xs.append((row[0] + row[2] - 1) * .5)
    return median(xs) if xs else None


def helmet_center(image, bounds):
    top, bottom = bounds[1], bounds[3]
    crop = image.crop((0, top, image.width, min(bottom, top + round((bottom - top) * .36))))
    head = alpha_bounds(crop)
    if not head:
        raise ValueError('No helmet silhouette in the upper 36% of a frame.')
    return (head[0] + head[2] - 1) * .5


def load_idle_frames(direction):
    image = Image.open(SOURCE / 'directional-idle-v1.png').convert('RGBA')
    col = DIRECTIONS.index(direction)
    cells = [cell(image, col, row, 5, 2) for row in range(2)]
    return [entry[1] for entry in cells], [entry[0] for entry in cells]


def load_walk_frames(direction):
    path = SOURCE / f'walk-{direction}-{WALK_SOURCE_VERSION[direction]}.png'
    image = Image.open(path).convert('RGBA')
    frames = []
    rects = []
    for row in range(2):
        for col in range(4):
            rect, frame = cell(image, col, row, 4, 2)
            rects.append(rect)
            frames.append(frame)
    return path, frames, rects


def compose_strip(name, frames, rects, source_path, role, direction):
    boxes = [alpha_bounds(frame) for frame in frames]
    if any(not box for box in boxes):
        raise ValueError(f'{name} has an empty source frame.')
    scale = TARGET_HEIGHT / median(box[3] - box[1] for box in boxes)
    strip = Image.new('RGBA', (FRAME * len(frames), FRAME))
    records = []
    for index, (source_frame, box, rect) in enumerate(zip(frames, boxes, rects)):
        head_x = helmet_center(source_frame, box)
        # The lowest visible shoe rows are the ground-contact registration. A
        # frame is never resized independently; body bob remains in the pixels.
        ground_y = box[3] - 1
        scaled_size = (round(source_frame.width * scale), round(source_frame.height * scale))
        scaled = source_frame.resize(scaled_size, Image.Resampling.LANCZOS)
        position = (round(FRAME * .5 - head_x * scale), round(BASELINE - ground_y * scale))
        tile = Image.new('RGBA', (FRAME, FRAME))
        tile.alpha_composite(scaled, position)
        bounds = alpha_bounds(tile)
        if not bounds or min(bounds[0], bounds[1], FRAME - bounds[2], FRAME - bounds[3]) < 2:
            raise ValueError(f'{name} frame {index + 1} is clipped or too close to the stage edge: {bounds}')
        strip.alpha_composite(tile, (index * FRAME, 0))
        records.append({
            'sourceRect': list(rect), 'sourceBounds': list(box),
            'visibleSourceHeight': box[3] - box[1], 'helmetCenterX': head_x,
            'sourceGroundY': ground_y, 'sourceSoleBandCenterX': contact_center(source_frame, box),
            'stageBounds': list(bounds), 'stageAnchor': [FRAME // 2, BASELINE],
            'phase': PHASES[index] if role == 'gait' else ('neutral' if index == 0 else 'settle'),
        })
    out_path = STAGE / f'{name}.png'
    strip.save(out_path)
    return {
        'path': out_path.relative_to(ROOT).as_posix(),
        'frame_width': FRAME, 'frame_height': FRAME, 'frame_count': len(frames),
        'loop': True, 'role': role,
        'normalizationHeight': TARGET_HEIGHT, 'uniformSourceScale': round(scale, 6),
        'anchor': [FRAME // 2, BASELINE], 'anchorMethod': 'helmet-center x + lowest visible shoe-row y',
        'source': source_path.relative_to(ROOT).as_posix(), 'sourceSha256': sha(source_path),
        'sha256': sha(out_path), 'frames': records,
    }


def draw_contacts(entries, view, filename):
    cell_count = 2 if view == 'idle' else 8
    cell_w = FRAME
    label_h = 30
    gap_y = 12
    columns = cell_count
    rows = len(entries)
    canvas = Image.new('RGB', (columns * cell_w, rows * (FRAME + label_h + gap_y)), '#526872')
    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype('arial.ttf', 16)
    except OSError:
        font = ImageFont.load_default()
    for row, (direction, strips) in enumerate(entries.items()):
        y = row * (FRAME + label_h + gap_y)
        draw.text((8, y + 6), direction.upper(), font=font, fill='white')
        image = Image.open(STAGE / f'{view}_{direction}.png').convert('RGBA')
        for frame in range(cell_count):
            source = image.crop((frame * FRAME, 0, (frame + 1) * FRAME, FRAME))
            dest = (frame * cell_w, y + label_h)
            canvas.paste(source, dest, source)
            if view == 'walk':
                draw.text((dest[0] + 8, dest[1] + 6), f'{frame + 1} {PHASES[frame]}', font=font, fill='#f7edcb')
            else:
                draw.text((dest[0] + 8, dest[1] + 6), 'neutral' if frame == 0 else 'settle', font=font, fill='#f7edcb')
            draw.line((dest[0], dest[1] + BASELINE, dest[0] + FRAME, dest[1] + BASELINE), fill='#a2c7b9', width=1)
    path = REVIEW / filename
    canvas.save(path)
    return path


def build_motion_spec(idle, walks, sources):
    animations = {}
    for direction, record in idle.items():
        animations[f'idle_{direction}'] = {
            'path': record['path'], 'frame_width': FRAME, 'frame_height': FRAME,
            'frame_count': 2, 'loop': True, 'role': 'directional_idle', 'fps': .65,
            'normalizationHeight': TARGET_HEIGHT, 'uniformSourceScale': record['uniformSourceScale'],
        }
    for direction, record in walks.items():
        animations[f'walk_{direction}'] = {
            'path': record['path'], 'frame_width': FRAME, 'frame_height': FRAME,
            'frame_count': 8, 'loop': True, 'role': 'gait',
            'normalizationHeight': TARGET_HEIGHT, 'uniformSourceScale': record['uniformSourceScale'],
            'source_phase_order': PHASES,
        }
    mapping = {
        d: {'walk_animation': f'walk_{d}', 'idle_animation': f'idle_{d}', 'mirror_x': False}
        for d in DIRECTIONS
    }
    for opposite, authored in [('southwest', 'southeast'), ('west', 'east'), ('northwest', 'northeast')]:
        mapping[opposite] = {'walk_animation': f'walk_{authored}', 'idle_animation': f'idle_{authored}', 'mirror_x': True}
    return {
        'version': 1, 'character': 'shared-suited-critter-v2', 'status': 'staged_unapproved',
        'runtimeIntegrated': False, 'animations': animations, 'directions': mapping,
        'gait': {
            'pose_order': PHASES, 'pixels_per_frame': 6.24, 'base_speed': 81.6,
            'speed_multipliers': MULTIPLIERS, 'acceleration_multipliers': ACCELERATION,
        },
        'audit': {
            'alpha_threshold': ALPHA_THRESHOLD, 'edge_margin': 2,
            'detached_component_ratio': .003, 'baseline_tolerance': 2, 'center_tolerance': 14,
        },
        'runtime': {
            'world_height_metres': 1.35, 'foot_anchor': [FRAME // 2, BASELINE],
            'metres_per_gait_frame': .13,
            'mirror_rationale': 'Shared suit has a centered zipper and no side-specific markings or carried items; motorcycle art is not mirrored.',
        },
        'sources': [
            {'path': path.relative_to(ROOT).as_posix(), 'sha256': sha(path)} for path in sources
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--partial', action='store_true', help='stage available walk directions only; do not write a motion spec')
    args = parser.parse_args()
    STAGE.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    sources = []
    idle_image = SOURCE / 'directional-idle-v1.png'
    if not idle_image.exists():
        raise FileNotFoundError(idle_image)
    sources.append(idle_image)
    idle = {}
    for direction in DIRECTIONS:
        frames, rects = load_idle_frames(direction)
        idle[direction] = compose_strip(f'idle_{direction}', frames, rects, idle_image, 'idle', direction)

    available = [d for d in DIRECTIONS if (SOURCE / f'walk-{d}-{WALK_SOURCE_VERSION[d]}.png').exists()]
    missing = [d for d in DIRECTIONS if d not in available]
    if missing and not args.partial:
        raise FileNotFoundError(f'Missing v2 walk sources for {missing}. Use --partial for staging-only review.')
    if not available:
        raise ValueError('No v2 walk source sheets are available.')
    walks = {}
    for direction in available:
        path, frames, rects = load_walk_frames(direction)
        sources.append(path)
        walks[direction] = compose_strip(f'walk_{direction}', frames, rects, path, 'gait', direction)

    idle_contact = draw_contacts(idle, 'idle', 'idle-contact.png')
    walk_contact = draw_contacts(walks, 'walk', 'walk-contact-partial.png' if missing else 'walk-contact.png')
    manifest = {
        'status': 'partial_review_only' if missing else 'staged_unapproved',
        'runtimeIntegrated': False, 'sourceRoot': SOURCE.relative_to(ROOT).as_posix(),
        'stageRoot': STAGE.relative_to(ROOT).as_posix(), 'frameSize': [FRAME, FRAME],
        'targetVisibleHeight': TARGET_HEIGHT, 'anchor': [FRAME // 2, BASELINE],
        'missingWalkDirections': missing, 'directionsStaged': available,
        'idleContact': idle_contact.relative_to(ROOT).as_posix(),
        'walkContact': walk_contact.relative_to(ROOT).as_posix(),
        'idle': idle, 'walk': walks,
        'pending': [
            'Manual phase/arm/leg review for every direction',
            'Native LÖVE contact and looping review at runtime scale',
            'Motion audit and final all-direction review before any runtime integration',
        ],
    }
    manifest_path = STAGE / 'manifest.json'
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    (REVIEW / 'walk-source-review.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    if missing:
        print(f'Staged {len(idle)} idle directions and {len(walks)} walk directions for partial review; no motion spec written.')
        return
    spec = build_motion_spec(idle, walks, sources)
    spec_path = STAGE / 'motion.json'
    spec_path.write_text(json.dumps(spec, indent=2) + '\n', encoding='utf-8')
    (STAGE / 'motion.lua').write_text('-- Generated by compile_rider_v2.py; staged review art only.\nreturn ' + lua(spec) + '\n', encoding='utf-8')
    print('Staged five v2 idle/walk directions and motion.json; runtime publication remains unapproved.')


if __name__ == '__main__':
    main()
