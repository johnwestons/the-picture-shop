"""Pin Critter Party's published flora/ground library without changing its source.

Source/staging fauna candidates are deliberately outside this environment import.
All transforms are namespace/path changes or explicitly bounded source excerpts.
"""
from pathlib import Path
import hashlib, json, re
root = Path(__file__).resolve().parents[2]
source = root.parent / 'Critter Party'
pairs = [('src/ground.glsl','src/commute/vendor/ground.glsl'),
         ('src/ground_textures.lua','src/commute/ground_textures.lua')]
for name in ['ground-desktop-v1.png','ground-mobile-v1.png','manifest.json']:
    pairs.append((f'assets/terrain/runtime/{name}', f'assets/commute/terrain/{name}'))
for source_dir,destination_dir in [
    ('assets/sprites/lifecycle','assets/commute/plants'),
    ('assets/sprites/runtime-atlas','assets/commute/plant-atlas'),
    ('assets/sprites/environmental','assets/commute/scenery/environmental'),
]:
    for path in sorted((source/source_dir).rglob('*')):
        if path.is_file():
            pairs.append((path.relative_to(source).as_posix(),destination_dir+'/'+path.relative_to(source/source_dir).as_posix()))
for path in sorted((source/'assets/terrain').glob('*')):
    if path.is_file():
        pairs.append((path.relative_to(source).as_posix(),'assets/commute/terrain/source/'+path.name))
for path in sorted((source/'assets/sprites').glob('*.png')):
    if re.match(r'^(rock|log|twig|leaf-litter|stone-clutter)(-v\d+)?\.png$',path.name):
        pairs.append((path.relative_to(source).as_posix(),'assets/commute/scenery/'+path.name))
for name in ['plant_sprites','plant_variants','plant_atlas_layout','plant_motion','lifecycle']:
    pairs.append((f'src/{name}.lua',f'src/commute/vendor/{name}.lua'))
# Pure plant definitions and appearance rules, excluding wildlife consumption,
# plant damage simulation, calendar stepping and Species/animal dependencies.
flora=(source/'src/flora.lua').read_text(encoding='utf-8')
flora_data=flora[flora.index('local Flora='):flora.index('local function winter')]
flora_data="local M=require('src.mathx')\nlocal Life=require('src.lifecycle')\n"+flora_data
flora_data+=flora[flora.index('local function winter'):flora.index('-- Presentation follows')]
flora_data+=flora[flora.index('function Flora.isDormant'):flora.index('function Flora.initialize')]
flora_data+=flora[flora.index('function Flora.appearance'):flora.index('function Flora.collisionRadius')]
flora_data+='return Flora\n'
pairs.append(('src/flora.lua','src/commute/vendor/flora.lua'))
# Reuse all five stable habitat-weighted candidate passes, excluding CP's
# world cache, wildlife population and persistent ecology implementation.
stream=(source/'src/streamed_world.lua').read_text(encoding='utf-8')
candidates="local M=require('src.mathx')\nlocal Stream={}\n"
candidates+=stream[stream.index('local extraChances='):stream.index('local function copyState')]
candidates+=stream[stream.index('local function radius'):stream.index('function Stream.new')]
candidates+=stream[stream.index('function Stream:candidate'):stream.index('function Stream:acceptCandidate')]
candidates+='return Stream\n'
pairs.append(('src/streamed_world.lua','src/commute/vendor/plant_candidates.lua'))
records=[]
for src,dst in pairs:
    data=(source/src).read_bytes()
    recipe='byte-identical copy'
    if dst.endswith('/flora.lua'):
        data=flora_data.encode();recipe='plant catalog, dormancy, appearance and visual functions only'
    if dst.endswith('/plant_candidates.lua'):
        data=candidates.encode();recipe='five candidate methods, chance tables and blocker radii only'
    if dst.endswith('.lua'):
        for name in ['mathx','ground_materials','flora','lifecycle','plant_variants','plant_atlas_layout']:
            data=data.replace(('src.'+name).encode(),('src.commute.vendor.'+name).encode())
        data=data.replace(b"assets/terrain/runtime/",b"assets/commute/terrain/")
        data=data.replace(b"src/ground.glsl",b"src/commute/vendor/ground.glsl")
        data=data.replace(b'assets/sprites/lifecycle/',b'assets/commute/plants/')
        data=data.replace(b'assets/sprites/runtime-atlas/',b'assets/commute/plant-atlas/')
        data=data.replace(b'assets/sprites/',b'assets/commute/scenery/')
        recipe+='; commute namespace and asset paths'
    target=root/dst
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_bytes(data)
    records.append(dict(source=src,destination=dst,recipe=recipe,bytes=len(data),sourceSha256=hashlib.sha256((source/src).read_bytes()).hexdigest(),sha256=hashlib.sha256(data).hexdigest()))
summary=dict(plantSpecies=22,lifecycleStates=12,alternateForms=8,groundMaterials=16,
    atlasPages=json.loads((source/'assets/sprites/runtime-atlas/manifest.json').read_text())['pageCount'])
(root/'docs/commute-art-source.json').write_text(json.dumps(dict(sourceProject='Critter Party',summary=summary,files=records),indent=2)+'\n')
print(f'Pinned {len(records)} environment files ({sum(r["bytes"] for r in records)/1024**2:.1f} MiB); source project untouched.')
print(json.dumps(summary))
