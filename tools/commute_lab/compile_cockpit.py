"""Preserve generated alpha; publish a uniformly downsampled cockpit sprite."""
from pathlib import Path
from PIL import Image
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
source = ROOT / 'assets/source/commute-cockpit-v1/source.png'
target = ROOT / 'assets/commute/cockpit/handlebars.png'
image = Image.open(source).convert('RGBA')
assert image.size == (2172, 724)
assert image.getextrema()[3] == (0, 255)
image.resize((1086, 362), Image.Resampling.LANCZOS).save(target)
manifest = {'source': str(source.relative_to(ROOT)), 'prompt': 'assets/source/commute-cockpit-v1/prompt.txt',
            'generator': 'built-in imagegen', 'sourceSha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'runtimeSha256': hashlib.sha256(target.read_bytes()).hexdigest(), 'scale': 0.5,
            'review': 'Transparent handlebar silhouette and blank instrument faces visually reviewed; live overlays reviewed in LÖVE capture.'}
target.with_name('manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
print(target)
