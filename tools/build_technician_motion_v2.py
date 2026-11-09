"""Stage reviewed technician motion, keeping missing actions explicitly pending.

Rejected gait masters and unselected cells are never installed. New gait and service entries
can join this pack after their anatomy, camera and handedness pass visual review.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
from statistics import median
from PIL import Image, ImageDraw
import build_visitor_character_assets as visitor
from build_worker_action_assets import lua

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"assets/source/technician-motion-v2"
REVIEW=ROOT/"output/animation-overhaul/technician-motion-v2"
VIEWS=("east","southeast","south","southwest","west","northwest","north","northeast")
POSES=["left_contact","left_down","right_passing","right_up","right_contact","right_down","left_passing","left_up"]
CHARACTERS={"mouse":"field-mouse-technician","lizard":"lizard-press-technician"}
REVIEWED_WALK_VIEWS=("north","south","east")

def gif_delays(milliseconds):
    """Distribute GIF's 10 ms quantization instead of shortening every frame."""
    delays=[];elapsed=0;previous=0
    for duration in milliseconds:
        elapsed+=duration
        boundary=round(elapsed/10)*10
        delays.append(boundary-previous)
        previous=boundary
    return delays

def head_width(frame):
    """Use the rigid ear/head span, independent of boot lift and vest shading."""
    box=visitor.bounds(frame);left,top,right,bottom=box
    head=frame.getchannel("A").crop((0,top,frame.width,top+round((bottom-top)*.30)))
    bounds=head.point(lambda a:255 if a>128 else 0).getbbox()
    if not bounds: raise ValueError("Character head reference is missing")
    return bounds[2]-bounds[0]

def walk_sources(species,view):
    if view=="north":
        return [("contacts",2,2,[0,1,2,3],[0,1,4,5]),
                ("right-swing",2,2 if species=="mouse" else 1,[0,1],[2,3]),
                ("left-swing",2,1,[0,1],[6,7])]
    if view=="south":
        return [("left-contacts",2,1,[0,1],[0,1]),
                ("right-contacts",2,2 if species=="mouse" else 1,[0,1],[4,5]),
                ("right-swing",2,1,[0,1],[2,3]),
                ("left-swing",2,1,[0,1],[6,7])]
    if view=="east":
        return [("left-contacts",2,1,[0,1],[0,1]),
                ("right-contacts",2,1,[0,1],[4,5]),
                ("right-swing",2,1,[0,1],[2,3]),
                ("left-swing",2,1,[0,1],[6,7])]
    raise ValueError(f"Unreviewed walk view: {view}")

def source_references(species,view,part):
    if view=="east" and species=="mouse" and part.endswith("contacts"):
        return ["mouse-east-left-swing-v2.png" if part=="left-contacts" else "mouse-east-right-swing.png"]
    if (species,view,part)==("mouse","east","left-swing"):
        return ["mouse-east-left-swing.png"]
    if view=="east" and species=="lizard":
        pose=f"mouse-east-{part}{'' if part=='right-swing' else '-v2'}.png"
        return [pose,"references/lizard-east.png"]
    if (species,view,part)==("lizard","south","left-swing"):
        return ["lizard-south-left-swing.png","lizard-south-right-swing.png"]
    if view=="south" and species=="lizard":
        pose=f"mouse-south-{part}.png" if part!="right-contacts" else "references/mouse-south-right-contacts-selected.png"
        return [pose,"references/lizard-south.png"]
    if view=="north" and species=="lizard" and part=="left-swing":
        return ["mouse-north-left-swing.png","references/lizard-north.png"]
    if view=="north" and species=="mouse" and part=="right-swing":
        return ["mouse-north-contacts.png"]
    return [f"references/{species}-{view}.png"]

def corrected_west_idle(pins,records):
    path=SOURCE/"mouse-west-idle-v2.png"
    digest=hashlib.sha256(path.read_bytes()).hexdigest()
    if pins.get(path.name,digest)!=digest: raise ValueError("Changed reviewed two-ear west idle correction")
    image=Image.open(path).convert("RGBA")
    frames=[image.crop((round(i*image.width/2),0,round((i+1)*image.width/2),image.height)) for i in range(2)]
    records.append({"path":path.name,"sha256":digest,"status":"selected_cells",
        "role":"directional_idle_correction","view":"west","layout":[2,1],"selected_cells":[0,1],
        "prompt":"mouse-west-idle-v2-prompt.txt","references":["references/mouse-west-idle-original-pair.png"],
        "anatomy_review":"Two anatomical ears in both neutral and blink; removed extra rear gray ear inherited from original west reference."})
    return visitor.pack(frames,cleanup_area=16)

def walk(species,view,pins,records):
    definitions=walk_sources(species,view)
    masters=[];heights=[]
    for part,columns,rows,selected,phases in definitions:
        revised=(species,view,part) in (("lizard","south","left-swing"),("mouse","east","left-swing"),
            ("mouse","east","left-contacts"),("mouse","east","right-contacts"))
        name=f"{species}-{view}-{part}{'-v2' if revised else ''}.png"
        path=SOURCE/name;digest=hashlib.sha256(path.read_bytes()).hexdigest()
        if pins.get(name,digest)!=digest: raise ValueError(f"Changed reviewed gait source: {name}")
        image=Image.open(path).convert("RGBA")
        frames=[]
        for index in selected:
            c,r=index%columns,index//columns
            frames.append(visitor.clean_export(image.crop((round(c*image.width/columns),round(r*image.height/rows),
                round((c+1)*image.width/columns),round((r+1)*image.height/rows))),16))
        height=median(head_width(frame) for frame in frames)
        masters.append(frames);heights.append(height)
        records.append({"path":name,"sha256":digest,"status":"selected_cells","role":"walk_"+view,
            "prompt":path.stem+"-prompt.txt","layout":[columns,rows],"selected_cells":selected,
            "phase_indices":phases,"references":source_references(species,view,part),
            "head_reference_width":height})
    ordered=[None]*8
    for definition,frames,height in zip(definitions,masters,heights):
        scale=heights[0]/height
        for phase,frame in zip(definition[4],frames):
            if ordered[phase] is not None: raise ValueError(f"Duplicate gait phase {phase}")
            ordered[phase]=frame.resize((round(frame.width*scale),round(frame.height*scale)),Image.Resampling.LANCZOS)
    if any(frame is None for frame in ordered): raise ValueError("Missing authored gait phase")
    return visitor.pack(ordered,cleanup_area=16)

def build(apply: bool):
    REVIEW.mkdir(parents=True,exist_ok=True)
    visitor.SIZE,visitor.HEIGHT,visitor.WIDTH,visitor.BASELINE=256,192,232,229
    art={"characters":CHARACTERS,"paths":{},"anchors":{},"metrics":{},"frameSize":256}
    records=[]
    manifest_path=SOURCE/"source-manifest.json"
    pinned=json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
    pins={r["path"]:r["sha256"] for r in pinned.get("sources",[]) if r.get("status") in ("selected","selected_cells")}
    for species,character in CHARACTERS.items():
        path=SOURCE/f"{species}-idle.png"
        digest=hashlib.sha256(path.read_bytes()).hexdigest()
        if pins.get(path.name,digest)!=digest: raise ValueError(f"Changed reviewed identity: {path}")
        image=Image.open(path).convert("RGBA")
        cells=[image.crop((round(c*image.width/4),round(r*image.height/4),
                          round((c+1)*image.width/4),round((r+1)*image.height/4)))
               for r in range(4) for c in range(4)]
        order=list(range(8)) if species=="mouse" else [0,1,2,3,4,7,6,5]
        selected_views=dict(zip(VIEWS,order))
        if species=="mouse": selected_views.pop("west")
        records.append({"path":path.name,"sha256":digest,"status":"selected_cells","role":"directional_idle",
                        "prompt":f"{species}-idle-prompt.txt",
                        "layout":[4,4],"view_cells":selected_views,"blink_cell_offset":8,
                        "selected_cells":[cell for base in selected_views.values() for cell in (base,base+8)],
                        "excluded_cells":[4,12] if species=="mouse" else [],
                        "exclusion_reason":"Original west neutral/blink have three ear-shaped lobes; use reviewed v2 pair." if species=="mouse" else None})
        directory=REVIEW/character
        directory.mkdir(parents=True,exist_ok=True)
        art["paths"][character]={};art["anchors"][character]={};art["metrics"][character]={}
        animations={}
        def register(action,strip,role,fps):
            count=strip.width//256
            target=directory/f"{action}.png";strip.save(target,optimize=True)
            anchors=[];metrics=[];frames=[]
            for i in range(count):
                frame=strip.crop((i*256,0,(i+1)*256,256));box=visitor.bounds(frame)
                anchors.append({"x":round(visitor.body_axis(frame,box),2),"y":229});metrics.append(list(box))
                frames.append(frame)
            art["paths"][character][action]=f"assets/generated/technician-motion-v2/{character}/{action}.png"
            art["anchors"][character][action]=anchors;art["metrics"][character][action]=metrics
            animations[action]={"path":target.relative_to(ROOT).as_posix(),"frame_width":256,"frame_height":256,
                "frame_count":count,"loop":True,"role":role,"fps":fps}
            preview=[]
            for frame in frames:
                background=Image.new("RGBA",(256,256),(30,36,42,255));background.alpha_composite(frame)
                preview.append(background.convert("RGB"))
            duration=gif_delays([(2/.65-.14)*1000,140] if role=="directional_idle" else [1000/fps]*count)
            preview[0].save(directory/f"{action}.gif",save_all=True,append_images=preview[1:],loop=0,duration=duration,disposal=2)
            if role=="gait":
                preview[0].save(directory/f"{action}-half-speed.gif",save_all=True,append_images=preview[1:],loop=0,duration=gif_delays([2000/fps]*count),disposal=2)
                sheet=Image.new("RGBA",(4*190,2*220),(30,36,42,255));labels=ImageDraw.Draw(sheet)
                for i,frame in enumerate(frames):
                    x,y=(i%4)*190,(i//4)*220
                    sheet.alpha_composite(frame.resize((190,190)),(x,y+24))
                    labels.text((x+3,y+4),f"{i+1}: {POSES[i]}",fill=(240,220,160))
                sheet.save(directory/f"{action}-contact-sheet.png")
            if apply:
                runtime=ROOT/art["paths"][character][action]
                runtime.parent.mkdir(parents=True,exist_ok=True);runtime.write_bytes(target.read_bytes())
            return frames
        contact=Image.new("RGBA",(8*142,2*166),(30,36,42,255));draw=ImageDraw.Draw(contact)
        for view_index,(view,cell_index) in enumerate(zip(VIEWS,order)):
            action="idle" if view=="east" else "idle_"+view
            strip=(corrected_west_idle(pins,records) if species=="mouse" and view=="west"
                   else visitor.pack([cells[cell_index],cells[cell_index+8]],cleanup_area=16))
            frames=register(action,strip,"directional_idle",.65)
            for frame_index,frame in enumerate(frames):
                contact.alpha_composite(frame.resize((140,140)),(view_index*142,frame_index*166+22))
            draw.text((view_index*142+3,3),view,fill=(240,220,160))
        contact.save(directory/"contact-sheet.png")
        for view in REVIEWED_WALK_VIEWS:
            register("walk" if view=="east" else "walk_"+view,walk(species,view,pins,records),"gait",78/13)
        pending=["walk" if v=="east" else "walk_"+v for v in VIEWS]+["service" if v=="east" else "service_"+v for v in VIEWS]
        spec={"version":1,"character":character,"production_status":"partial_motion_reviewed_remaining_actions_pending",
              "animations":animations,"directions":{v:{"walk_animation":"walk" if v=="east" else "walk_"+v,
                "idle_animation":"idle" if v=="east" else "idle_"+v,"mirror_x":False} for v in VIEWS},
              "gait":{"pose_order":POSES,"pixels_per_frame":13,"base_speed":78,
                "speed_multipliers":[.96,.94,1.04,1.06]*2,"acceleration_multipliers":[.92,.90,1.08,1.10]*2},
              "pending_actions":[action for action in pending if action not in animations],
              "audit":{"alpha_threshold":16,"edge_margin":2,"baseline_tolerance":1,"center_tolerance":10}}
        (directory/"staging-spec.json").write_text(json.dumps(spec,indent=2)+"\n",encoding="utf-8")
        if apply:
            for action,value in spec["animations"].items(): value["path"]=art["paths"][character][action]
            (ROOT/"character-motion"/f"{character}.json").write_text(json.dumps(spec,indent=2)+"\n",encoding="utf-8")
    for path in sorted(SOURCE.glob("*-rejected.png")):
        record={"path":path.name,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
            "prompt":path.stem.removesuffix("-rejected")+"-prompt.txt",
            "status":"rejected","reason":("Opaque painted backdrop and unclear foreground leg order; never runtime art."
                if path.name=="mouse-east-cycle-rejected.png" else "Three-ear anatomy inherited from original west reference, repeated leading leg and little free-arm swing; never runtime art."
                if path.name=="mouse-west-cycle-rejected.png" else "Camera drift, repeated leading foot or diagnostic case changes hands; never runtime art.")}
        if path.name=="mouse-east-cycle-rejected.png":
            record["references"]=["references/mouse-east.png","references/guide-east.png"]
        if path.name=="mouse-west-cycle-rejected.png":
            record["references"]=["references/mouse-west-original.png"]
        records.append(record)
    path=SOURCE/"lizard-south-left-swing.png"
    records.append({"path":path.name,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
        "prompt":path.stem+"-prompt.txt","status":"rejected",
        "reason":"Oversize case in both left-swing cells; replaced by reviewed v2 correction, never runtime art.",
        "references":["mouse-south-left-swing.png","references/lizard-south.png"]})
    path=SOURCE/"mouse-east-left-swing.png"
    records.append({"path":path.name,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
        "prompt":path.stem+"-prompt.txt","status":"rejected",
        "reason":"Second far-leg pose repeats the bent-back passing pose; reviewed v2 advances boot before next contact.",
        "references":["references/mouse-east.png"]})
    for part in ("left-contacts","right-contacts"):
        path=SOURCE/f"mouse-east-{part}.png"
        records.append({"path":path.name,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
            "prompt":path.stem+"-prompt.txt","status":"rejected",
            "reason":"Contact/body proportions produced excessive down/up bob after rigid head-scale alignment; v2 uses swing-pose proportions.",
            "references":["references/mouse-east.png"]})
    for part in ("left-swing","right-swing"):
        path=SOURCE/f"mouse-west-{part}.png"
        if path.exists():
            records.append({"path":path.name,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
                "prompt":path.stem+"-prompt.txt","status":"rejected",
                "reason":"Three-ear anatomy inherited from the original west reference; not eligible for runtime.",
                "references":["references/mouse-west-original.png"]})
    manifest={"version":2,"generator":"OpenAI imagegen (built-in)","sources":records,
              "runtime_status":"directional idles and reviewed north/south/east walks; remaining walk and service sets pending"}
    (REVIEW/"build-report.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    if apply:
        (ROOT/"src/technician_art.lua").write_text("-- Generated by tools/build_technician_motion_v2.py. Partial pack; inspect pending motion actions.\nreturn "+lua(art)+"\n",encoding="utf-8")
        manifest_path.write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    print(f"{'Installed' if apply else 'Staged'} sixteen directional idles and {len(REVIEWED_WALK_VIEWS)*len(CHARACTERS)} north/south/east walks. Other actions remain pending.\n{REVIEW}")

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply","--apply-idles",dest="apply",action="store_true",help="install reviewed strips after inspecting contacts and audit findings")
    build(parser.parse_args().apply)
