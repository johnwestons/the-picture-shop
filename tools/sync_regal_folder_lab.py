"""Refresh the browser test bench from the game's authoritative folder assets."""
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'sites/regal-folder-lab/dist'
SOURCE = ROOT / 'src/regal_folder_game.lua'
metadata_path = DEST / 'source.json'
if metadata_path.exists() and json.loads(metadata_path.read_text()).get('experimental'):
    raise SystemExit('Test-page balance experiments are active. Keep the Site rules; promote or replace them only when the user requests it.')
DEST.mkdir(parents=True, exist_ok=True)
(DEST / 'assets').mkdir(exist_ok=True)
shutil.copy2(SOURCE, DEST / 'folder.lua')
shutil.copy2(ROOT / 'assets/generated/regal-moll-folder-v2/regal-moll-eight-angles.png', DEST / 'assets/folder.png')
shutil.copy2(ROOT / 'assets/fonts/VT323-Regular.ttf', DEST / 'assets/VT323-Regular.ttf')
(DEST / 'source.json').write_text(json.dumps({
    'path': 'src/regal_folder_game.lua',
    'sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    'sprite': 'assets/generated/regal-moll-folder-v2/regal-moll-eight-angles.png',
    'runtime': 'Fengari 0.1.4 (Lua 5.3); game module copied without modification',
}, indent=2) + '\n')
print('Folder test bench synchronized with game source.')
