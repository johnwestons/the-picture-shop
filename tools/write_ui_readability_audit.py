"""Summarize the native UI review evidence without claiming device coverage."""
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / 'output' / 'ui-readability'


def result(folder):
    report = folder / 'smoke.rpt'
    lines = report.read_text(encoding='utf-8').splitlines()
    assert 'SMOKE_OK' in lines, f'Unsuccessful review: {report}'
    return {'passed': True, 'checks': sum(line.startswith('PASS ') for line in lines),
            'report': report.relative_to(ROOT).as_posix()}


runs = {}
for mode, dimensions in [('desktop', [960, 678]), ('phone', [832, 384]), ('tablet', [1024, 768])]:
    folder = REVIEW / mode
    run = result(folder)
    run['window_pixels'] = dimensions
    run['layout_platform'] = {'desktop': 'Windows', 'phone': 'Android simulation', 'tablet': 'iOS simulation'}[mode]
    run['screens'] = [line.split()[1] for line in (folder / 'stdout.txt').read_text(encoding='utf-8').splitlines()
                      if line.startswith('UI_CAPTURE ')]
    run['capture_count'] = len(run['screens'])
    run['text_geometry'] = (folder / 'text-layout.tsv').relative_to(ROOT).as_posix()
    runs[mode] = run
runs['regression'] = result(REVIEW / 'desktop' / 'regression')
shared = REVIEW / 'desktop' / 'regression' / 'appdata' / 'LOVE' / 'the-picture-shop-test-ui-desktop'
runs['regression']['shared_gui_captures'] = sorted(path.stem.removeprefix('gui-parity-') for path in shared.glob('gui-parity-*.png'))
for mode in ['desktop', 'mobile']:
    runs['hud_' + mode] = result(ROOT / 'output' / 'scene-hud-review' / mode)

audit = {
    'generated_utc': datetime.now(timezone.utc).isoformat(),
    'scope': 'UI typography, readability, layout and navigation pass in the source workspace',
    'font': {'family': 'Courier Prime', 'weights': ['regular', 'bold'],
             'fallbacks': ['Noto Sans Symbols', 'Noto Sans Symbols 2', 'LOVE default'],
             'licenses': 'Bundled OFL licenses in assets/fonts',
             'logical_sizes': {'caption': 12, 'compact': 14, 'body': 16, 'button': 16, 'heading': 20, 'title': 26}},
    'layout_rules': [
        'Use src/screens/typography.lua for UI fonts; do not create per-screen default fonts.',
        'Wrap longer body text and reserve its measured line height; scroll long job details above fixed actions.',
        'Use UTF-8-safe ellipses for bounded one-line summaries; expose details in the full ticket or notice.',
        'Keep calendar and both balances in a backed status panel across warehouse, home and travel.',
        'Compact very large HUD balances instead of clipping the second account; financial pages retain full values.',
        'Wide mobile office drawing and pointer coordinates share the same transform.',
        'Keep notices clear of the commute minimap, with identical drawing and hit-test bounds.',
    ],
    'improvements': [
        'Shared typewriter typography, smooth filtering, symbol coverage and high-contrast panel palette.',
        'Warehouse/home/travel HUD spacing, balances, objective, prompts and employee speech bubbles.',
        'Enlarged mobile office content and navigation; remote office uses the same layout.',
        'Job detail scrolling, finance tables, shopping, inventory, machine listings and receipt layouts.',
        'Machine service cards, mechanic comparison columns, grocery quantity controls and store balances.',
        'Map destination list spacing, notification placement, update-note clipping and wrapped release notes.',
        'Menu, options, character colors, home routines/appliances and arcade text review.',
    ],
    'validation': runs,
    'commands': [
        './tools/review_ui_readability.ps1 -Mode desktop',
        './tools/review_ui_readability.ps1 -Mode phone',
        './tools/review_ui_readability.ps1 -Mode tablet',
        './tools/review_ui_readability.ps1 -Mode desktop -Regression',
        './tools/review_scene_hud.ps1',
        './tools/review_scene_hud.ps1 -Mobile',
        'python tools/build_ui_review_sheets.py phone',
        'python tools/write_ui_readability_audit.py',
    ],
    'limits': [
        'Native LOVE rendering on Windows. Android/iOS profiles simulate OS layout selection and viewport dimensions.',
        'No physical S25 or iPad testing, APK/IPA packaging, installation, publishing or Git push in this pass.',
        'Representative screens and populated shared-machine states were reviewed; screenshots do not prove every dynamic content combination.',
        'Scene artwork, logos, printed decals and appliance dial artwork retain their intentional art typography.',
        'Test runners reset only their isolated test identities. Synthetic render fixtures are not saved as playable shops.',
    ],
}
destination = ROOT / 'docs' / 'ui-readability-audit.json'
destination.write_text(json.dumps(audit, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'audit': str(destination), 'screen_states_per_profile': runs['phone']['capture_count'],
                  'shared_gui_states': len(runs['regression']['shared_gui_captures']),
                  'checks': {name: run['checks'] for name, run in runs.items()}}))
