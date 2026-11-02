"""Read-only verification of the pinned environment import and GPU page sizes."""
from pathlib import Path
import hashlib
import json
import struct

root=Path(__file__).resolve().parents[2]
manifest=json.loads((root/'docs/commute-art-source.json').read_text())
errors=[]
pngs=0
for record in manifest['files']:
    path=root/record['destination']
    if not path.is_file():
        errors.append('Missing '+record['destination'])
        continue
    data=path.read_bytes()
    if hashlib.sha256(data).hexdigest()!=record['sha256']:
        errors.append('Hash mismatch '+record['destination'])
    if path.suffix=='.png':
        pngs+=1
        if data[:8]!=b'\x89PNG\r\n\x1a\n':
            errors.append('Invalid PNG '+record['destination'])
            continue
        width,height=struct.unpack('>II',data[16:24])
        if '/plant-atlas/' in record['destination'] and (width,height)!=(520,260):
            errors.append('Unexpected runtime atlas dimensions '+record['destination'])
        if '/plants/motion/' in record['destination'] and max(width,height)>2048:
            errors.append('Oversized motion texture '+record['destination'])
result={**manifest['summary'],'files':len(manifest['files']),'pngs':pngs,
    'bytes':sum(r['bytes'] for r in manifest['files']),'errors':errors}
output=root/'output/commute-environment-audit.json'
output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
raise SystemExit(bool(errors))
