"""Check frame/phase parity in the production-renderer jack capture fixtures."""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
DIRECTORY=ROOT/"output/animation-overhaul/engine"
rows=[]
for host in sorted(DIRECTORY.glob("*-jack-host-*-pose.json")):
    guest=host.with_name(host.name.replace("-jack-host-","-jack-guest-"))
    a,b=json.loads(host.read_text()),json.loads(guest.read_text())
    rows.append({"host":host.name,"guest":guest.name,
        "single_opaque_pose":len(a["samples"])==len(b["samples"])==1
            and a["samples"][0]["weight"]==b["samples"][0]["weight"]==1,
        "matching_frame":a["samples"][0]["frame"]==b["samples"][0]["frame"],
        "phase_error":abs(a["distance"]%80-b["distance"]%80),
        "heading_error":abs(a["heading"]%(6.283185307179586)-b["heading"]%(6.283185307179586))})
report={"pairs":len(rows),"matching":sum(row["single_opaque_pose"] and row["matching_frame"] for row in rows),
    "maximum_phase_error":max((row["phase_error"] for row in rows),default=None),"results":rows}
path=ROOT/"output/animation-overhaul/jack-pose-parity.json"
path.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
print(f"Jack pose parity: {report['matching']}/{len(rows)} host/guest samples")
assert len(rows)==32 and all(row["single_opaque_pose"] and row["matching_frame"]
    and row["phase_error"]<=.0051 and row["heading_error"]<=.000051 for row in rows)
