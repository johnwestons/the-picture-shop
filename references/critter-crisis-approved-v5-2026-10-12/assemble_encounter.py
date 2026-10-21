from pathlib import Path
import json
import base64
root = Path(__file__).parent
dest = root / 'critter-crisis-encounter-preview.html'
text = dest.read_text(encoding='utf-8')
old = (root / 'critter-crisis-phone-preview.html').read_text(encoding='utf-8')
asset_line = next(line for line in old.splitlines() if line.strip().startswith('const assets='))
assets = asset_line.strip().removeprefix('const assets=').removesuffix(';')
asset_map = json.loads(assets)
weapon_atlas = root / 'weapon-rewards-v4.webp'
if weapon_atlas.exists():
    asset_map['weapons'] = 'data:image/webp;base64,' + base64.b64encode(weapon_atlas.read_bytes()).decode('ascii')
assets = json.dumps(asset_map, separators=(',', ':'))
script = (root / 'encounter-preview.js').read_text(encoding='utf-8').replace('__CC_ASSET_DATA__', assets)
prefix = text.split('<script>', 1)[0].replace('cc-phone-proposal', 'cc-reference-proposal')
dest.write_text(prefix + '<script>\n' + script + '\n</script>\n', encoding='utf-8')
assert dest.stat().st_size < 1_000_000
print(json.dumps({'bytes':dest.stat().st_size,'assets':len(json.loads(assets)),'path':str(dest)}))
