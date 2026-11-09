"""Record selected v2 walk source, audit and native-review evidence."""
from hashlib import sha256
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/source/commute-rider-v2'
STAGE = ROOT / 'assets/staging/commute-rider-v2'
REVIEW = ROOT / 'output/commute-rider-v2-review'
REPORT = REVIEW / 'motion-audit/report.json'
SELECTED = {
    'north': ('walk-north-v1.png', 'walk-north-v1-prompt.txt'),
    'northeast': ('walk-northeast-v1.png', 'walk-northeast-v1-prompt.txt'),
    'east': ('walk-east-v1.png', 'walk-east-v1-prompt.txt'),
    'southeast': ('walk-southeast-v2.png', 'walk-southeast-v2-prompt.txt'),
    'south': ('walk-south-v1.png', 'walk-south-v1-prompt.txt'),
}


def digest(path):
    return sha256(path.read_bytes()).hexdigest()


def source_record(path):
    return {'path': str(path.relative_to(ROOT)).replace('\\', '/'), 'sha256': digest(path)}


def main():
    report = json.loads(REPORT.read_text(encoding='utf-8'))
    manifest = json.loads((STAGE / 'manifest.json').read_text(encoding='utf-8'))
    assert report['summary']['errors'] == 0, report['issues']
    assert report['character'] == 'shared-suited-critter-v2'
    assert manifest['directionsStaged'] == ['north', 'northeast', 'east', 'southeast', 'south']
    assert not manifest['missingWalkDirections']
    assert len([name for name in report['animations'] if name['name'].startswith('walk_')]) == 5
    assert len([name for name in report['animations'] if name['name'].startswith('idle_')]) == 5

    sources = {}
    for direction, (filename, prompt_name) in SELECTED.items():
        source = SOURCE / filename
        prompt = SOURCE / prompt_name
        idle_ref = REVIEW / f'idle-reference-{direction}.png'
        staged = manifest['walk'][direction]
        sources[direction] = {
            'image': source_record(source), 'prompt': source_record(prompt),
            'identityReference': source_record(idle_ref),
            'stagedStrip': staged['path'], 'sourceScale': staged['uniformSourceScale'],
            'sourceShaMatchesStage': digest(source) == staged['sourceSha256'],
        }
    rejected_se = SOURCE / 'walk-southeast-v1.png'
    warning_codes = [issue['code'] for issue in report['issues']]
    review = {
        'status': 'staged_unapproved',
        'runtimeIntegrated': False,
        'character': 'shared-suited-critter-v2',
        'identityAndShapeReference': 'assets/source/commute-rider-v2/directional-idle-v1.png',
        'layout': {'walkColumns': 4, 'walkRows': 2, 'directions': list(SELECTED),
                   'phaseOrder': report['motion_profile']['pose_order'],
                   'frameSize': [256, 256], 'targetVisibleHeight': 214,
                   'anchor': [128, 238]},
        'selectedSources': sources,
        'rejectedCandidate': {
            'image': source_record(rejected_se),
            'reason': 'Adjacent SE cells overlapped at their column boundaries, leaving detached fragments in frames 2, 3 and 6. The selected v2 source uses larger transparent gutters and the staged audit reports no detached components.',
            'replacement': 'assets/source/commute-rider-v2/walk-southeast-v2.png',
        },
        'compiler': {
            'path': 'tools/commute_lab/compile_rider_v2.py',
            'manifest': 'assets/staging/commute-rider-v2/manifest.json',
            'motionSpec': 'assets/staging/commute-rider-v2/motion.json',
            'contactSheet': 'output/commute-rider-v2-review/walk-contact.png',
        },
        'automatedAudit': {
            'path': 'output/commute-rider-v2-review/motion-audit/report.json',
            'errors': report['summary']['errors'], 'warnings': report['summary']['warnings'],
            'warningCodes': warning_codes,
            'nominalPoseMilliseconds': report['motion_profile']['nominal_pose_ms'],
            'nominalCycleSeconds': report['motion_profile']['nominal_cycle_seconds'],
            'allTenAnimationsAudited': len(report['animations']) == 10,
        },
        'nativeReview': {
            'viewer': 'tools/commute_lab/rider_v2_review/main.lua',
            'captureScript': 'tools/commute_lab/review_rider_v2_native.ps1',
            'walkCapture': 'output/commute-rider-v2-review/native-walk.png',
            'idleCapture': 'output/commute-rider-v2-review/native-idle.png',
            'renderedAt': '256x256 cells with alpha checkerboard and shared ground-anchor guide',
            'processesExited': True,
        },
        'animatedPreview': {
            'generator': 'tools/commute_lab/review_rider_v2_gifs.py',
            'path': 'output/commute-rider-v2-review/motion-audit/previews-checker',
            'actualCheckerFrameMs': 80, 'halfSpeedCheckerFrameMs': 160,
            'nominalRuntimePoseMs': report['motion_profile']['nominal_pose_ms'],
            'note': 'GIF timing is quantized to 10ms steps; these are review aids, not runtime acceptance.',
        },
        'visualFindings': [
            'The five authored rows show the requested back, back-right three-quarter, right profile, front-right three-quarter and front camera views.',
            'Native-size contact review shows all eight phases per direction, alternating contact halves, compact passing poses, knee-up preparation and counter-swinging arms. Helmet, leather suit and body scale stay consistent with the selected v2 idle.',
            'The LÖVE captures show the staged 214px figures at 1:1 frame size on checker backgrounds; idle and walk feet share the (128, 238) staging anchor.',
            'The source-cell crop audit and motion audit report no clipped edges or detached components for the selected source set.',
        ],
        'knownWarnings': [
            {
                'animation': 'walk_east', 'code': 'center_jitter',
                'reason': 'The audit measures the full alpha bounding-box center, which shifts as arms and stride extend. The compiler explicitly aligns helmet centers, and the native contact shows a stable head/root anchor.',
                'status': 'documented; no tolerance change made',
            }
        ] if 'center_jitter' in warning_codes else [],
        'remaining': [
            'Runtime integration and distance-based walk-frame synchronization remain pending parent coordination.',
            'Walking loop should receive an in-engine movement/collision review before publication.',
        ],
    }
    destination = SOURCE / 'walk-review.json'
    destination.write_text(json.dumps(review, indent=2) + '\n', encoding='utf-8')
    print(f'Wrote staged walk review; audit {report["summary"]["errors"]} errors / {report["summary"]["warnings"]} warnings.')


if __name__ == '__main__':
    main()
