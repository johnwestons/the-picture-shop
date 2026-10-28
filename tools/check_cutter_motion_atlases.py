"""Verify the existing cutter layers support rigid continuous translation."""
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    "blade": ("1160536e96f84369753d0e13fdd609606d7b60459967541e422c1a3cb76d5b6e", [0,44,88,44,0]),
    "clamp": ("70853ebaa70675f41001d61a06442d706b2074b50f13ba71accdcb39d6942ff1", [0,14,29,44,58]),
}
records = []
for name, (expected_hash, offsets) in SOURCES.items():
    path = ROOT / f"assets/generated/cutter-{name}-strip.png"
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest == expected_hash, f"Re-review altered {name} atlas before using its translation registration"
    image = Image.open(path).convert("RGBA")
    assert image.size == (3840,512)
    cells = [image.crop((i*768,0,(i+1)*768,512)) for i in range(5)]
    bounds = [cell.getchannel("A").getbbox() for cell in cells]
    shapes = [cell.crop(box) for cell,box in zip(cells,bounds)]
    assert all(shape.size==shapes[0].size and shape.tobytes()==shapes[0].tobytes() for shape in shapes)
    assert [box[1]-bounds[0][1] for box in bounds] == offsets
    assert all(box[0]==bounds[0][0] for box in bounds)
    records.append({"layer": name, "path": path.relative_to(ROOT).as_posix(), "sha256": digest,
        "frame_bounds": bounds, "source_y_offsets": offsets,
        "all_visible_shapes_pixel_identical": True,
        "runtime_policy": "Draw original cell1 once, translated continuously; no cross-fading or resampling of the source file."})
output = ROOT / "output/animation-overhaul/cutter-motion-atlas-registration.json"
output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps(records,indent=2)+"\n",encoding="utf-8")
print("PASS: both cutter layers are exact rigid translations; source files unchanged")
