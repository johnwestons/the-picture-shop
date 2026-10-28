from __future__ import annotations

import json
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
CHAR = ROOT / 'assets/generated/characters/rabbit-worker'
NORTH = ROOT / 'assets/generated/player-walk-v7/walk_north.png'
OUT = ROOT / 'output/animation-overhaul/player-walk-cross-view-v6'
FRAME = 512
VIEWS = {
    'north-current': NORTH,
    'northeast': CHAR / 'walk_northeast.png',
    'east': CHAR / 'walk.png',
    'southeast': CHAR / 'walk_southeast.png',
    'south': CHAR / 'walk_south.png',
}
IDLES = {
    'north': CHAR / 'idle_north.png',
    'northeast': CHAR / 'idle_northeast.png',
    'east': CHAR / 'idle.png',
    'southeast': CHAR / 'idle_southeast.png',
    'south': CHAR / 'idle_south.png',
}


def mask_bbox(im: Image.Image, rule, y_range: tuple[int, int] | None = None) -> list[int] | None:
    px = im.convert('RGBA').load()
    points = []
    y0, y1 = y_range or (0, im.height)
    for y in range(max(0, y0), min(im.height, y1)):
        for x in range(im.width):
            if rule(*px[x, y]):
                points.append((x, y))
    if not points:
        return None
    return [min(x for x, _ in points), min(y for _, y in points), max(x for x, _ in points) + 1, max(y for _, y in points) + 1]


def measure(im: Image.Image) -> dict:
    rgba = im.convert('RGBA')
    alpha = rgba.getchannel('A').point(lambda v: 255 if v > 16 else 0)
    bbox = alpha.getbbox()
    # Keep the landmark windows away from swinging hands and trouser legs.
    # The earlier 2–48% / 38–78% windows included those limbs and made apparent
    # head/torso widths depend on the stride pose rather than body proportions.
    head_band = (int(bbox[1] + (bbox[3] - bbox[1]) * .02), int(bbox[1] + (bbox[3] - bbox[1]) * .34)) if bbox else None
    torso_band = (int(bbox[1] + (bbox[3] - bbox[1]) * .40), int(bbox[1] + (bbox[3] - bbox[1]) * .64)) if bbox else None
    orange_rule = lambda r, g, b, a: a > 64 and r > 130 and g > 45 and r > g * 1.15 and g > b * 1.10 and b < 145
    blue_rule = lambda r, g, b, a: a > 64 and b > 70 and b > r * 1.25 and g > 35 and b > g * 0.85
    head = mask_bbox(rgba, orange_rule, head_band)
    torso = mask_bbox(rgba, blue_rule, torso_band)
    dark = mask_bbox(rgba, lambda r, g, b, a: a > 64 and max(r, g, b) < 80)
    dark_px = rgba.load()
    dark_count = sum(1 for y in range(im.height) for x in range(im.width)
                     if dark_px[x, y][3] > 64 and max(dark_px[x, y][:3]) < 80)
    def widths_in_band(y0: int, y1: int, rule) -> list[int]:
        pixels = rgba.load()
        widths = []
        for y in range(y0, y1):
            xs = [x for x in range(im.width) if rule(*pixels[x, y])]
            if xs:
                widths.append(max(xs) - min(xs) + 1)
        return widths
    orange_rows = widths_in_band(*(head_band or (0, 0)), orange_rule)
    blue_rows = widths_in_band(*(torso_band or (0, 0)), blue_rule)
    return {
        'visible_bbox_alpha_gt_16': list(bbox) if bbox else None,
        'visible_height_px': bbox[3] - bbox[1] if bbox else 0,
        'upper_orange_head_mask_bbox_proxy': head,
        'middle_blue_clothing_mask_bbox_proxy': torso,
        'dark_ink_mask_bbox_proxy': dark,
        'dark_ink_pixels_gt_alpha_64_and_rgb_lt_80': dark_count,
        'fixed_y_band_orange_max_row_width_proxy': max(orange_rows) if orange_rows else None,
        'fixed_y_band_blue_median_row_width_proxy': sorted(blue_rows)[len(blue_rows) // 2] if blue_rows else None,
    }


def frames(path: Path, count: int) -> list[Image.Image]:
    sheet = Image.open(path).convert('RGBA')
    if sheet.height != FRAME or sheet.width != FRAME * count:
        raise SystemExit(f'{path} dimensions {sheet.size}; expected {(FRAME * count, FRAME)}')
    return [sheet.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(count)]


def draw_cell(canvas: Image.Image, image: Image.Image, x: int, y: int, size: int = 144):
    # Keep source scale proportional; fit the complete 512px frame into the same board cell.
    preview = image.resize((size, size), Image.Resampling.LANCZOS)
    canvas.alpha_composite(preview, (x, y))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--north-strip', type=Path, default=NORTH)
    parser.add_argument('--output-dir', type=Path, default=OUT)
    args = parser.parse_args()
    north = args.north_strip if args.north_strip.is_absolute() else ROOT / args.north_strip
    out = args.output_dir if args.output_dir.is_absolute() else ROOT / args.output_dir
    out.mkdir(parents=True, exist_ok=True)
    views = dict(VIEWS)
    views['north-current'] = north
    report = {'title': 'Rabbit-worker current five-view gait consistency review against ' + str(north.relative_to(ROOT)) + '; source art only, no edits', 'views': {}}
    scale = 128
    label_h = 28
    row_h = scale + label_h
    board = Image.new('RGBA', (9 * scale, len(views) * row_h), (235, 235, 235, 255))
    draw = ImageDraw.Draw(board)
    for view_index, (name, path) in enumerate(views.items()):
        run = frames(path, 8)
        idle_name = 'north' if name == 'north-current' else name
        idle_run = frames(IDLES[idle_name], 2)
        y = view_index * row_h
        draw.text((3, y + 2), f'{name}: idle 1, then gait phases 1–8', fill=(15, 15, 15, 255))
        row_top = y + label_h
        draw_cell(board, idle_run[0], 0, row_top, scale)
        for i, cell in enumerate(run):
            draw_cell(board, cell, (i + 1) * scale, row_top, scale)
        report['views'][name] = {
            'walk_path': str(path.relative_to(ROOT)),
            'idle_path': str(IDLES[idle_name].relative_to(ROOT)),
            'idle_frames': [measure(c) for c in idle_run],
            'walk_frames': [measure(c) for c in run],
        }
        for kind in ('idle_frames', 'walk_frames'):
            records = report['views'][name][kind]
            heights = [r['visible_height_px'] for r in records]
            head_widths = [r['upper_orange_head_mask_bbox_proxy'][2] - r['upper_orange_head_mask_bbox_proxy'][0] for r in records if r['upper_orange_head_mask_bbox_proxy']]
            torso_widths = [r['middle_blue_clothing_mask_bbox_proxy'][2] - r['middle_blue_clothing_mask_bbox_proxy'][0] for r in records if r['middle_blue_clothing_mask_bbox_proxy']]
            ink_ratios = [r['dark_ink_pixels_gt_alpha_64_and_rgb_lt_80'] / max(1, r['visible_height_px'] ** 2) for r in records]
            report['views'][name][kind.replace('_frames', '_summary')] = {
                'visible_height_range_px': [min(heights), max(heights)],
                'median_upper_orange_head_width_proxy_px': sorted(head_widths)[len(head_widths) // 2] if head_widths else None,
                'median_middle_blue_torso_width_proxy_px': sorted(torso_widths)[len(torso_widths) // 2] if torso_widths else None,
                'upper_head_center_span_px': round(max((r['upper_orange_head_mask_bbox_proxy'][0] + r['upper_orange_head_mask_bbox_proxy'][2]) / 2 for r in records if r['upper_orange_head_mask_bbox_proxy']) - min((r['upper_orange_head_mask_bbox_proxy'][0] + r['upper_orange_head_mask_bbox_proxy'][2]) / 2 for r in records if r['upper_orange_head_mask_bbox_proxy']), 2) if any(r['upper_orange_head_mask_bbox_proxy'] for r in records) else None,
                'upper_torso_center_span_px': round(max((r['middle_blue_clothing_mask_bbox_proxy'][0] + r['middle_blue_clothing_mask_bbox_proxy'][2]) / 2 for r in records if r['middle_blue_clothing_mask_bbox_proxy']) - min((r['middle_blue_clothing_mask_bbox_proxy'][0] + r['middle_blue_clothing_mask_bbox_proxy'][2]) / 2 for r in records if r['middle_blue_clothing_mask_bbox_proxy']), 2) if any(r['middle_blue_clothing_mask_bbox_proxy'] for r in records) else None,
                'median_dark_ink_pixels_per_height_squared': round(sorted(ink_ratios)[len(ink_ratios) // 2], 5) if ink_ratios else None,
                'median_fixed_y_orange_head_width_proxy_px': sorted([r['fixed_y_band_orange_max_row_width_proxy'] for r in records if r['fixed_y_band_orange_max_row_width_proxy'] is not None])[len([r['fixed_y_band_orange_max_row_width_proxy'] for r in records if r['fixed_y_band_orange_max_row_width_proxy'] is not None]) // 2] if any(r['fixed_y_band_orange_max_row_width_proxy'] is not None for r in records) else None,
                'median_fixed_y_blue_torso_width_proxy_px': sorted([r['fixed_y_band_blue_median_row_width_proxy'] for r in records if r['fixed_y_band_blue_median_row_width_proxy'] is not None])[len([r['fixed_y_band_blue_median_row_width_proxy'] for r in records if r['fixed_y_band_blue_median_row_width_proxy'] is not None]) // 2] if any(r['fixed_y_band_blue_median_row_width_proxy'] is not None for r in records) else None,
            }
        idle_head = report['views'][name]['idle_summary']['median_upper_orange_head_width_proxy_px']
        walk_head = report['views'][name]['walk_summary']['median_upper_orange_head_width_proxy_px']
        idle_torso = report['views'][name]['idle_summary']['median_middle_blue_torso_width_proxy_px']
        walk_torso = report['views'][name]['walk_summary']['median_middle_blue_torso_width_proxy_px']
        report['views'][name]['walk_vs_idle_landmark_delta_percent'] = {
            'upper_head_width_proxy': round((walk_head / idle_head - 1) * 100, 2) if idle_head else None,
            'middle_torso_width_proxy': round((walk_torso / idle_torso - 1) * 100, 2) if idle_torso else None,
        }
    board.convert('RGB').save(out / 'rabbit-worker-idle-and-five-direction-walk-contact.png')
    north_run = frames(north, 8)
    foot_crop = (112, 300, 405, 488)
    foot_w = foot_crop[2] - foot_crop[0]
    foot_h = foot_crop[3] - foot_crop[1]
    foot_board = Image.new('RGBA', (4 * foot_w, 2 * (foot_h + 22)), (255, 255, 255, 255))
    foot_draw = ImageDraw.Draw(foot_board)
    for i, frame in enumerate(north_run):
        col, row = i % 4, i // 4
        x, y = col * foot_w, row * (foot_h + 22)
        foot_draw.text((x + 3, y + 2), f'North phase {i + 1}', fill=(15, 15, 15, 255))
        crop = frame.crop(foot_crop)
        foot_board.alpha_composite(crop, (x, y + 22))
    foot_board.convert('RGB').save(out / 'north-candidate-native-lower-body-sequence.png')
    (out / 'rabbit-worker-direction-metrics.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('wrote', out / 'rabbit-worker-idle-and-five-direction-walk-contact.png')
    print('wrote', out / 'north-candidate-native-lower-body-sequence.png')
    for name, data in report['views'].items():
        heights = [f['visible_height_px'] for f in data['walk_frames']]
        idle_heights = [f['visible_height_px'] for f in data['idle_frames']]
        print(f"{name}: walk height {min(heights)}-{max(heights)}px; idle {idle_heights}")


if __name__ == '__main__':
    main()
