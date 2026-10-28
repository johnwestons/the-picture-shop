from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'output/animation-overhaul/luna-player/consistent-north-v1/north-consistent-v1-full8-native.png'
OUT_DIR = ROOT / 'assets/source/animation-overhaul-luna-player-v1/consistent-north-v2'
OUT = OUT_DIR / 'north-v2-phase7-compact-pass-legs-only-pose-guide.png'
RECORD = OUT_DIR / 'north-v2-phase7-pose-guide-provenance.json'
EXPECTED_SOURCE_SHA256 = 'd5b243c9aa6ea7b16530df184fdc26561c247e8657aec3cf07700e8309eb9291'
FRAME = 512
PHASE3_FRAME = 2
ROI = (154, 355, 358, 466)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f'Missing pose-guide source: {SOURCE}')
    source_sha = sha(SOURCE)
    if source_sha != EXPECTED_SOURCE_SHA256:
        raise SystemExit('Pose-guide source changed; refusing to use stale crop coordinates.')
    sheet = Image.open(SOURCE).convert('RGBA')
    if sheet.size != (FRAME * 8, FRAME):
        raise SystemExit(f'Unexpected source dimensions: {sheet.size}')
    x0, y0, x1, y1 = ROI
    phase3 = sheet.crop((PHASE3_FRAME * FRAME + x0, y0, PHASE3_FRAME * FRAME + x1, y1))
    # This is a pose-only lower-leg role guide. Mirroring the two symmetric trouser legs
    # swaps the compact passing owner while leaving all production art untouched.
    phase7_pose_role = ImageOps.mirror(phase3)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    phase7_pose_role.save(OUT)
    RECORD.write_text(json.dumps({
        'title': 'North phase-7 compact-pass lower-leg pose guide; not production art',
        'source': str(SOURCE.relative_to(ROOT)),
        'source_sha256': source_sha,
        'source_phase': 3,
        'source_phase_role': 'right compact passing with left support',
        'crop_xyxy_within_phase': list(ROI),
        'transformation': 'horizontal mirror of trouser-and-boot pose-role crop only; no production frame was mirrored or edited',
        'output': str(OUT.relative_to(ROOT)),
        'output_sha256': sha(OUT),
        'scope_note': 'Reference shows lower-leg pose and owner only; do not copy style, upper body, tools, or clothing details from this guide.'
    }, indent=2), encoding='utf-8')
    print('wrote', OUT)
    print('source sha256', source_sha)
    print('guide sha256', sha(OUT))


if __name__ == '__main__':
    main()
