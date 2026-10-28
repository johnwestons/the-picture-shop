"""Compare actual host/guest gait selection and worker pixels in engine captures."""
import argparse
import json
import math
from pathlib import Path
from PIL import Image,ImageChops

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("--captures",type=Path,default=ROOT/"output/animation-overhaul/engine")
args=parser.parse_args()
rows=[]
for host in sorted(args.captures.glob("*-cat-worker-walk-south-host-*-pose.json")):
    guest=host.with_name(host.name.replace("-host-","-guest-"))
    a,b=json.loads(host.read_text()),json.loads(guest.read_text())
    host_image=host.with_name(host.name.replace("-pose.json",".png"))
    guest_image=guest.with_name(guest.name.replace("-pose.json",".png"))
    left,right=Image.open(host_image).convert("RGB"),Image.open(guest_image).convert("RGB")
    assert left.size==right.size
    scale=min(left.width/960,left.height/678)
    ox,oy=(left.width-960*scale)/2,(left.height-678*scale)/2
    x,y=a["x"],a["y"]
    box=(math.floor(ox+(x-55)*scale),math.floor(oy+(y-90)*scale),
         math.ceil(ox+(x+55)*scale),math.ceil(oy+(y+5)*scale))
    diff=ImageChops.difference(left.crop(box),right.crop(box))
    rows.append({"host":host.name,"guest":guest.name,"phase":a["frame"],
        "pose_identical":a==b,"body_identical":diff.getbbox() is None,
        "body_crop":box,"difference_bounds":diff.getbbox()})
report={"pairs":len(rows),"pose_matches":sum(r["pose_identical"] for r in rows),
    "body_matches":sum(r["body_identical"] for r in rows),"results":rows}
(args.captures/"employee-walk-parity.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
print(f"Employee gait parity: {report['pose_matches']}/{len(rows)} poses; {report['body_matches']}/{len(rows)} body captures")
assert len(rows)==16 and all(r["pose_identical"] and r["body_identical"] for r in rows)
