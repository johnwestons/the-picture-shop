from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/source/animation-overhaul-luna-player-v1/consistent-north-v2/north-consistent-v2-generated-raw.png'
OUT_DIR = ROOT / 'assets/source/animation-overhaul-luna-player-v1/consistent-north-v2'
OUT = OUT_DIR / 'north-v2-phase7-clean-compact-pass-legs-only-pose-guide.png'
RECORD = OUT_DIR / 'north-v2-phase7-clean-pose-guide-provenance.json'
DIAGNOSTIC = ROOT / 'output/animation-overhaul/luna-player/consistent-north-v2/north-v2-phase7-clean-pose-guide-white-diagnostic.png'
EXPECTED_SOURCE_SHA256 = '0fce24948744ba68d614af1e5a994b88659c05e5f840a54e80c5d0df661c63f7'
CELL = (384, 512)
PHASE3 = 2
ROI = (0, 360, 384, 489)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    source_sha = sha(SOURCE)
    if source_sha != EXPECTED_SOURCE_SHA256:
        raise SystemExit(f'V2 raw source changed; expected {EXPECTED_SOURCE_SHA256}, got {source_sha}')
    sheet = Image.open(SOURCE).convert('RGBA')
    if sheet.size != (CELL[0] * 4, CELL[1] * 2):
        raise SystemExit(f'Unexpected V2 source dimensions: {sheet.size}')
    col, row = PHASE3 % 4, PHASE3 // 4
    x0, y0, x1, y1 = ROI
    crop = sheet.crop((col * CELL[0] + x0, row * CELL[1] + y0,
                       col * CELL[0] + x1, row * CELL[1] + y1))
    guide = ImageOps.mirror(crop)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    guide.save(OUT)
    white = Image.new('RGBA', guide.size, (255, 255, 255, 255))
    white.alpha_composite(guide)
    DIAGNOSTIC.parent.mkdir(parents=True, exist_ok=True)
    white.convert('RGB').save(DIAGNOSTIC)
    RECORD.write_text(json.dumps({
        'title': 'Clean lower-leg pose guide for north phase 7; not production art',
        'source': str(SOURCE.relative_to(ROOT)),
        'source_sha256': source_sha,
        'source_dimensions_px': list(sheet.size),
        'source_phase': 3,
        'source_role': 'right compact passing with left support',
        'crop_xyxy_within_source_cell': list(ROI),
        'transformation': 'mirror lower-leg crop only to show phase-7 opposite owner; source image is transparent and has no bright-red silhouette fringe',
        'output': str(OUT.relative_to(ROOT)),
        'output_sha256': sha(OUT),
        'white_background_diagnostic': str(DIAGNOSTIC.relative_to(ROOT)),
        'scope_note': 'Use only for pose/owner/amplitude. Do not copy the drawing style or restore this mirrored crop as production art.'
    }, indent=2), encoding='utf-8')
    print('wrote', OUT)
    print('source sha256', source_sha)
    print('guide sha256', sha(OUT))


if __name__ == '__main__':
    main()
