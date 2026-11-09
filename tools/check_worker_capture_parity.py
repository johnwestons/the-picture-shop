"""Compare the worker body region in deterministic host/guest review captures."""
import json
import math
from pathlib import Path
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
CAPTURES = ROOT / "output/animation-overhaul/engine"
rows = []
for host in sorted(CAPTURES.glob("*-host-contact-*.png")):
    guest = host.with_name(host.name.replace("-host-contact-", "-guest-contact-"))
    a, b = Image.open(host).convert("RGB"), Image.open(guest).convert("RGB")
    assert a.size == b.size
    scale = min(a.width / 960, a.height / 678)
    x, y = (a.width - 960 * scale) / 2, (a.height - 678 * scale) / 2
    box = (math.floor(x + 550 * scale), math.floor(y + 375 * scale),
           math.ceil(x + 960 * scale), math.ceil(y + 570 * scale))
    diff = ImageChops.difference(a.crop(box), b.crop(box))
    rows.append({"host": host.name, "guest": guest.name, "body_crop": box,
                 "identical": diff.getbbox() is None, "difference_bounds": diff.getbbox()})
report = {
    "region": "World rectangle (550,375)-(960,570), transformed per viewport. Includes workers; excludes changing wall clock/office lights. Production operator positions quantized to existing wire precision 0.01px for deterministic comparison.",
    "pairs": len(rows), "identical": sum(row["identical"] for row in rows), "results": rows,
}
path = ROOT / "output/animation-overhaul/work-v2-host-guest-image-parity.json"
path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(f"Worker body pixel parity: {report['identical']}/{len(rows)} host/guest pairs")
assert len(rows) == 96 and all(row["identical"] for row in rows)
