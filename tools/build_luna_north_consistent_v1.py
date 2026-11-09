from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from statistics import median
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / 'assets/source/animation-overhaul-luna-player-v1/consistent-north-v1'
OUTPUT_DIR = ROOT / 'output/animation-overhaul/luna-player/consistent-north-v1'
RAW = SOURCE_DIR / 'north-consistent-v1-generated.png'
PROMPT = SOURCE_DIR / 'north-consistent-v1-exact-prompt.txt'
GUIDE = SOURCE_DIR / 'north-lower-body-pose-role-guides.png'
K5_MASTER = ROOT / 'assets/source/animation-overhaul-luna-player-v1/pose-corrections-v1/north-canonical-05-trial-06-generated.png'
K5_PROPOSAL = ROOT / 'output/animation-overhaul/luna-player/pose-corrections-v1/north-phase5-trial06-8frame-proposal.png'
V3_POSE_BOARD = ROOT / 'output/animation-overhaul/luna-player/pose-corrections-v1/north-v3-k03trial03-k04trial02-k07trial01-proposal.png'
NATIVE = OUTPUT_DIR / 'north-consistent-v1-full8-native.png'
CONTACT = OUTPUT_DIR / 'north-consistent-v1-full8-contact.png'
GIF = OUTPUT_DIR / 'north-consistent-v1-64worldpx-timed.gif'
AUDIT = OUTPUT_DIR / 'north-consistent-v1-phase-owner-body-width-audit.json'
FRAME = 512
GROUND_Y = 465
HEAD_CENTER_X = 256
GLOBAL_SCALE = 1.0  # raw 443-444 px cells already match the accepted ~416 px visible height
ALPHA_THRESHOLD = 16
COL_BOUNDS = [0, 443, 887, 1330, 1774]
ROW_BOUNDS = [0, 443, 887]
PHASES = [
    {'phase': 1, 'role': 'left contact', 'owner': 'anatomical-left/viewer-left lead; right trailing heel low'},
    {'phase': 2, 'role': 'left weight-down', 'owner': 'left support; right heel release near ground'},
    {'phase': 3, 'role': 'right passing', 'owner': 'right ankle low under pelvis; left support flat'},
    {'phase': 4, 'role': 'right knee-up recovery', 'owner': 'right knee bent and lifted; left support'},
    {'phase': 5, 'role': 'right contact', 'owner': 'anatomical-right/viewer-right lead; left trailing heel low'},
    {'phase': 6, 'role': 'right weight-down', 'owner': 'right support; left heel release near ground'},
    {'phase': 7, 'role': 'left passing', 'owner': 'left ankle low under pelvis; right support flat'},
    {'phase': 8, 'role': 'left knee-up recovery', 'owner': 'left knee bent and lifted; right support'},
]
EXPECTED_RAW_SHA256 = '55a59f161f064b1f22f9f90859a34526c80b64aaa6a54362dda16a3167ef7573'
EXPECTED_K5_SHA256 = 'd8f4220f356bc5069ab10252b641d839f54e9023451dce2e487b03a89bc72c83'


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bbox16(image: Image.Image):
    return image.convert('RGBA').getchannel('A').point(lambda v: 255 if v > ALPHA_THRESHOLD else 0).getbbox()


def orange(r, g, b, a):
    return a > 64 and r > 130 and g > 45 and r > g * 1.20 and g > b * 1.10 and b < 125


def blue(r, g, b, a):
    return a > 64 and b > 70 and b > r * 1.25 and g > 35 and b > g * 0.90


def row_widths(image: Image.Image, y0: int, y1: int, predicate):
    p = image.convert('RGBA').load()
    widths = []
    for y in range(max(0, y0), min(image.height, y1)):
        xs = [x for x in range(image.width) if predicate(*p[x, y])]
        if xs:
            widths.append({'y': y, 'width': max(xs) - min(xs) + 1, 'x_min': min(xs), 'x_max': max(xs)})
    return widths


def measure(image: Image.Image):
    alpha_bbox = bbox16(image)
    hrows = row_widths(image, 170, 250, orange)
    trows = row_widths(image, 245, 335, blue)
    # This is a consistent row-span proxy, not a segmentation claim about exact tailoring seams.
    head_max = max(hrows, key=lambda r: r['width']) if hrows else None
    torso_values = [r['width'] for r in trows]
    torso_max = max(trows, key=lambda r: r['width']) if trows else None
    a = image.convert('RGBA').load()
    red_edge_count = 0
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, alpha = a[x, y]
            # Omit the expected red tool area on the pouch; count bright-red pixels elsewhere.
            if alpha > 64 and r > 160 and g < 80 and b < 95 and not (x > 285 and 230 < y < 330):
                red_edge_count += 1
    return {
        'alpha_bbox_threshold_16': alpha_bbox,
        'visible_height_px': (alpha_bbox[3] - alpha_bbox[1]) if alpha_bbox else 0,
        'orange_head_band_y170_249_max_row_width_px': head_max,
        'blue_overall_band_y245_334_median_row_width_px': median(torso_values) if torso_values else None,
        'blue_overall_band_y245_334_max_row_width_px': torso_max,
        'bright_red_pixels_outside_expected_tool_roi': red_edge_count,
    }


def dark_roi_measure(image: Image.Image, box):
    x0, y0, x1, y1 = box
    p = image.convert('RGBA').load()
    points = []
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, a = p[x, y]
            if a > 64 and max(r, g, b) < 80:
                points.append((x, y))
    bbox = None if not points else [min(x for x, _ in points), min(y for _, y in points), max(x for x, _ in points) + 1, max(y for _, y in points) + 1]
    return {
        'roi_xyxy': list(box),
        'dark_pixel_bbox_proxy': bbox,
        'dark_pixel_count': len(points),
        'roi_area_px': (x1 - x0) * (y1 - y0),
        'dark_pixel_share_of_roi_percent': round(100 * len(points) / ((x1 - x0) * (y1 - y0)), 2),
    }


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    if sha(RAW) != EXPECTED_RAW_SHA256:
        raise SystemExit('Raw source hash mismatch; refusing to rebuild.')
    if sha(K5_MASTER) != EXPECTED_K5_SHA256:
        raise SystemExit('Accepted K5 raw-master hash mismatch; refusing to proceed.')
    if Image.open(RAW).size != (1774, 887):
        raise SystemExit(f'Unexpected raw sheet dimensions: {Image.open(RAW).size}')
    src = Image.open(RAW).convert('RGBA')
    frames = []
    transforms = []
    for i in range(8):
        row, col = divmod(i, 4)
        tile = src.crop((COL_BOUNDS[col], ROW_BOUNDS[row], COL_BOUNDS[col + 1], ROW_BOUNDS[row + 1]))
        if GLOBAL_SCALE != 1.0:
            tile = tile.resize((round(tile.width * GLOBAL_SCALE), round(tile.height * GLOBAL_SCALE)), Image.Resampling.LANCZOS)
        tb = bbox16(tile)
        if tb is None:
            raise SystemExit(f'Empty source cell {i+1}')
        p = tile.load()
        head_xs = []
        for y in range(90, min(230, tile.height)):
            for x in range(tile.width):
                if orange(*p[x, y]):
                    head_xs.append(x)
        if not head_xs:
            raise SystemExit(f'No orange head anchor in source cell {i+1}')
        anchor_x = sum(head_xs) / len(head_xs)
        dx = round(HEAD_CENTER_X - anchor_x)
        dy = GROUND_Y - (tb[3] - 1)
        cell = Image.new('RGBA', (FRAME, FRAME), (0, 0, 0, 0))
        cell.alpha_composite(tile, (dx, dy))
        if bbox16(cell) is None:
            raise SystemExit(f'Cell {i+1} disappeared after rigid registration')
        frames.append(cell)
        transforms.append({
            'phase': i + 1, 'source_crop_xyxy': [COL_BOUNDS[col], ROW_BOUNDS[row], COL_BOUNDS[col + 1], ROW_BOUNDS[row + 1]],
            'source_cell_size_px': list(tile.size), 'uniform_scale': GLOBAL_SCALE,
            'translation_xy_px': [dx, dy], 'head_anchor_center_x_source_px': round(anchor_x, 3),
            'registered_bbox_threshold_16': bbox16(cell),
        })
    strip = Image.new('RGBA', (FRAME * 8, FRAME), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        strip.alpha_composite(frame, (i * FRAME, 0))
    strip.save(NATIVE)
    contact = Image.new('RGBA', (FRAME * 4, FRAME * 2), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        row, col = divmod(i, 4)
        contact.alpha_composite(frame, (col * FRAME, row * FRAME))
    contact.save(CONTACT)
    # Convert to transparent 64x64 GIF cells with a common repeated 130 ms phase duration.
    gif_frames = []
    for frame in frames:
        small = frame.resize((64, 64), Image.Resampling.LANCZOS).convert('RGBA')
        alpha = small.getchannel('A')
        indexed = small.convert('RGB').quantize(colors=255, method=Image.Quantize.MEDIANCUT)
        pix = indexed.load(); ap = alpha.load()
        for y in range(64):
            for x in range(64):
                if ap[x, y] <= 96:
                    pix[x, y] = 255
        palette = indexed.getpalette() or []
        palette.extend([0] * (768 - len(palette)))
        for j in range(765, 768):
            palette[j] = 0
        indexed.putpalette(palette[:768])
        gif_frames.append(indexed)
    gif_frames[0].save(GIF, save_all=True, append_images=gif_frames[1:], duration=130, loop=0, transparency=255, disposal=2, optimize=False)

    k5_sheet = Image.open(K5_PROPOSAL).convert('RGBA')
    k5 = k5_sheet.crop((4 * FRAME, 0, 5 * FRAME, FRAME))
    candidate_metrics = [measure(frame) for frame in frames]
    k5_metrics = measure(k5)
    head_widths = [m['orange_head_band_y170_249_max_row_width_px']['width'] if m['orange_head_band_y170_249_max_row_width_px'] else None for m in candidate_metrics]
    torso_widths = [m['blue_overall_band_y245_334_max_row_width_px']['width'] if m['blue_overall_band_y245_334_max_row_width_px'] else None for m in candidate_metrics]
    reference_head = k5_metrics['orange_head_band_y170_249_max_row_width_px']['width'] if k5_metrics['orange_head_band_y170_249_max_row_width_px'] else None
    reference_torso = k5_metrics['blue_overall_band_y245_334_max_row_width_px']['width'] if k5_metrics['blue_overall_band_y245_334_max_row_width_px'] else None
    # Fixed inspection regions around the two passing feet. This dark-pixel proxy includes
    # some ink/boot shading, so it supports the visual finding rather than replacing it.
    sole_comparison = {
        'method': 'alpha>64 and all RGB channels <80 in manually selected foot ROIs; rough sole-facing proxy, not exact boot segmentation',
        'phase3_right_passing': dark_roi_measure(frames[2], (270, 400, 315, 435)),
        'phase7_left_passing': dark_roi_measure(frames[6], (195, 410, 255, 466)),
    }
    gif_check = Image.open(GIF)
    gif_durations = []
    for frame_index in range(gif_check.n_frames):
        gif_check.seek(frame_index)
        gif_durations.append(gif_check.info.get('duration'))
    audit = {
        'title': 'Luna rabbit-worker North consistent-eight candidate audit; staged only, not accepted for runtime',
        'generation': {'tool': 'built-in image_gen', 'generation_id': 'exec-e097ec7c-9db5-4d8b-b44f-ddaf19fa33df', 'cached_output_path': r'C:\Users\johnw\.codex\generated_images\01a17bec-a216-72b3-ac73-5e56d3da1c90\exec-e097ec7c-9db5-4d8b-b44f-ddaf19fa33df.png'},
        'provenance': {
            'raw_path': str(RAW.relative_to(ROOT)), 'raw_sha256': sha(RAW), 'raw_dimensions_px': list(src.size),
            'prompt_path': str(PROMPT.relative_to(ROOT)), 'prompt_sha256': sha(PROMPT),
            'identity_style_reference': str(K5_MASTER.relative_to(ROOT)), 'identity_style_reference_sha256': sha(K5_MASTER),
            'pose_role_reference': str(GUIDE.relative_to(ROOT)), 'pose_role_reference_sha256': sha(GUIDE),
            'pose_guide_parent': str(V3_POSE_BOARD.relative_to(ROOT)), 'pose_guide_parent_sha256': sha(V3_POSE_BOARD),
            'reference_roles': {'K5 raw master': 'only full-character identity/style/proportion/camera reference', 'lower-body guide': 'phase/leg/foot role only; upper-body style explicitly excluded'},
        },
        'processing': {'cell_order': '4 columns by 2 rows; row-major phases 1..8', 'integer_grid_x_boundaries': COL_BOUNDS, 'integer_grid_y_boundaries': ROW_BOUNDS, 'scale_policy': 'one shared full-master scale; no per-cell resampling; scale=1.0', 'registration_policy': 'per-cell rigid translation only: center orange-head anchor at x=256 and visible alpha bottom at y=465; no deformation, compositing, or per-cell scale', 'alpha_threshold_for_bounds': ALPHA_THRESHOLD, 'phase_transforms': transforms},
        'phase_owner_audit': [
            {**PHASES[0], 'visual_finding': 'Viewer-left lead appears planted; viewer-right trailing boot shows a broad rear sole.'},
            {**PHASES[1], 'visual_finding': 'Both boots look nearly flat and symmetric; weight-down compression is very subtle and may be underplayed.'},
            {**PHASES[2], 'visual_finding': 'Viewer-right foot is compact and low under the pelvis; sole view is narrower than in phase 7.'},
            {**PHASES[3], 'visual_finding': 'Viewer-right knee-up recovery is distinct; raised boot still exposes a fairly broad sole.'},
            {**PHASES[4], 'visual_finding': 'Viewer-right lead appears planted; viewer-left trailing boot has a broad rear sole.'},
            {**PHASES[5], 'visual_finding': 'Both boots look nearly flat and symmetric; weight-down compression is very subtle and may be underplayed.'},
            {**PHASES[6], 'visual_finding': 'Viewer-left boot is lifted, but broad sole faces camera; this reads closer to recovery than a compact passing phase.'},
            {**PHASES[7], 'visual_finding': 'Viewer-left knee-up recovery is distinct; raised boot exposes a broad sole.'},
        ],
        'body_width_comparison': {
            'measurement_note': 'Color-mask row-span proxies measured at the same registered 512x512 scale; use as consistency indicators, not tailoring-seam segmentation.',
            'accepted_K5_reference_cell_metrics': k5_metrics,
            'candidate_phase_metrics': candidate_metrics,
            'candidate_head_widths_px': head_widths, 'accepted_K5_head_width_px': reference_head,
            'candidate_head_width_median_px': median([x for x in head_widths if x is not None]),
            'candidate_torso_widths_px': torso_widths, 'accepted_K5_torso_max_row_width_px': reference_torso,
            'candidate_torso_width_median_px': median([x for x in torso_widths if x is not None]),
            'head_width_delta_percent_vs_K5': round((median([x for x in head_widths if x is not None]) / reference_head - 1) * 100, 2) if reference_head else None,
            'torso_width_delta_percent_vs_K5': round((median([x for x in torso_widths if x is not None]) / reference_torso - 1) * 100, 2) if reference_torso else None,
        },
        'passing_sole_comparison': sole_comparison,
        'timed_preview_check': {'frame_count': gif_check.n_frames, 'frame_size_px': list(gif_check.size), 'durations_ms': gif_durations, 'expected_duration_ms_per_frame': 130},
        'anatomy_and_artifact_review': {'visible_ears': '2 in every frame by visual review', 'arms_legs_boots': '2 of each in every frame by visual review', 'pouch_and_tools': 'right-hip pouch with red/yellow tools visible throughout', 'red_edge_artifact': 'thin bright-red fringe is visible around many silhouettes in raw output; preserved unchanged and counts recorded per frame; candidate not approved as clean style match', 'passing_feet': 'phase 7 has broad camera-facing sole; not accepted as compact pass'},
        'outputs': {str(p.relative_to(ROOT)): sha(p) for p in [NATIVE, CONTACT, GIF]},
        'acceptance': 'Staged for root review only. Head and torso widths remain close to accepted K5 at one shared scale; the silhouette still has an obvious red fringe, phase 7 has a broad camera-facing sole instead of a compact pass, and weight-down compression/release in phases 2 and 6 is subtle.'
    }
    AUDIT.write_text(json.dumps(audit, indent=2), encoding='utf-8')
    print('wrote', NATIVE, CONTACT, GIF, AUDIT)
    print('raw', sha(RAW), 'native', sha(NATIVE), 'contact', sha(CONTACT), 'gif', sha(GIF))
    print('K5 head/torso', reference_head, reference_torso)
    print('candidate head', head_widths, 'median', median(head_widths))
    print('candidate torso', torso_widths, 'median', median(torso_widths))
    print('head_delta_pct', audit['body_width_comparison']['head_width_delta_percent_vs_K5'], 'torso_delta_pct', audit['body_width_comparison']['torso_width_delta_percent_vs_K5'])
    print('bbox', [m['alpha_bbox_threshold_16'] for m in candidate_metrics])
    print('red-fringe counts', [m['bright_red_pixels_outside_expected_tool_roi'] for m in candidate_metrics])

if __name__ == '__main__':
    main()
