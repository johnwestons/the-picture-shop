"""Normalize each authored action to one continuous head/tire-plane profile.

An orthographic rig point follows a low-order yaw curve. Fitting that curve
rejects generator/crop jitter without flattening the deliberate action pose.
The only image transform is still uniform scale plus translation.
"""
import json
import math
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
from compile_bike_actions import ROOT,SOURCE,STAGE,REVIEW,mask,lower_center,remove_detached_background,sha,state_metrics

DEST=STAGE/'matched';OUT=REVIEW/'matched'

def head_profile(state,rows):
    if state.startswith('shift'):return [70.0]*64,[70,0,0,0,0]
    angles=np.arange(64)*math.tau/64
    design=np.column_stack([np.ones(64),np.cos(angles),np.sin(angles),np.cos(2*angles),np.sin(2*angles)])
    values=np.array([r['helmetTop'] for r in rows],dtype=float)
    weights=np.ones(64)
    for _ in range(6):
        coeff=np.linalg.lstsq(design*weights[:,None],values*weights,rcond=None)[0]
        weights=np.minimum(1,4/np.maximum(.01,np.abs(values-design@coeff)))
    return (design@coeff).tolist(),coeff.tolist()

def place(cell,reference,top):
    a=mask(cell);b=a.getbbox();rm=mask(reference);rb=rm.getbbox();bottom=rb[3]
    scale=(bottom-top)/(b[3]-b[1])
    source=np.asarray(a)>=128;target=np.asarray(rm)>=128
    x=round(lower_center(target,bottom,60)-lower_center(source,b[3],60/scale)*scale)
    y=round(bottom-b[3]*scale)
    tile=Image.new('RGBA',(320,320))
    tile.alpha_composite(cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.LANCZOS),(x,y))
    arr=np.asarray(mask(tile))>=128;box=mask(tile).getbbox()
    assert min(box[0],box[1],320-box[2],320-box[3])>=2,('clipped action profile',box)
    ys,xs=np.nonzero(arr[box[1]:box[1]+24]);union=(arr[195:300]|target[195:300]).sum()
    return tile,{'uniformScale':scale,'translation':[x,y],'bbox':box,'helmetTop':box[1],
        'targetHelmetTop':top,'helmetTopBandWidth':int(xs.max()-xs.min()+1),
        'wheelSilhouetteIoU':float((arr[195:300]&target[195:300]).sum()/union),
        'paintLower':max(155,math.ceil(box[1]+68))}

def main():
    DEST.mkdir(parents=True,exist_ok=True);(DEST/'pages').mkdir(exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    spec=json.loads((SOURCE/'production.json').read_text())
    raw=json.loads((STAGE/'registration.json').read_text());upright=Image.open(ROOT/spec['approvedUpright']).convert('RGBA')
    selected={j['source'] for j in spec['jobs']}
    assert all(r['source'] in selected for r in raw['frames']),'Recompile selected sources before profile registration'
    base=[upright.crop((i%8*320,i//8*320,(i%8+1)*320,(i//8+1)*320)) for i in range(64)]
    rows_by_state={}
    for row in raw['frames']:rows_by_state.setdefault(row['state'],[]).append(row)
    curves={};coeffs={};states={}
    for state,rows in rows_by_state.items():
        if len(rows)!=64:continue
        rows.sort(key=lambda r:r['frame']);curves[state],coeffs[state]=head_profile(state,rows);states[state]=[None]*64
    current_path=None;image=None;records=[]
    for original in raw['frames']:
        state=original['state']
        if state not in states:continue
        if original['source']!=current_path:
            current_path=original['source'];image=Image.open(ROOT/current_path).convert('RGBA')
        cell,cleanup=remove_detached_background(image.crop(original['sourceRect']))
        view=original['frame']-1
        tile,record=place(cell,base[view],curves[state][view]);states[state][view]=tile
        record.update({key:original[key] for key in ['state','frame','source','sourceSha256','sourceRect','sourceCell']})
        record.update(cleanup);record['unconstrainedWheelFitIoU']=original['wheelSilhouetteIoU'];records.append(record)
    for state,frames in states.items():
        assert all(f is not None for f in frames) and len({sha(f.tobytes()) for f in frames})==64,(state,'missing/duplicate art')
        atlas=Image.new('RGBA',(2560,2560));strip=Image.new('RGBA',(20480,320))
        gallery=Image.new('RGBA',(1600,1760),(33,49,51));d=ImageDraw.Draw(gallery)
        for i,tile in enumerate(frames):
            atlas.alpha_composite(tile,(i%8*320,i//8*320));strip.alpha_composite(tile,(i*320,0))
            gallery.alpha_composite(tile.resize((184,184),Image.Resampling.LANCZOS),(i%8*200+8,i//8*220+28))
            d.text((i%8*200+8,i//8*220+7),f'{state} {i+1:02} / {i*5.625:g}',fill='white')
        atlas.save(DEST/f'{state}-64.png');strip.save(OUT/f'{state}-strip.png');gallery.save(OUT/f'{state}-64-contact.png')
        for page in range(4):
            packed=Image.new('RGBA',(1280,1280))
            for n in range(16):packed.alpha_composite(frames[page*16+n],(n%4*320,n//4*320))
            packed.save(DEST/'pages'/f'{state}-{page+1}.png')
    metrics={state:state_metrics(state,records,base) for state in states}
    report={'version':1,'completeStates':list(states),'expectedStates':14,'profileCoefficients':coeffs,
        'processing':'Uniform scale and tire-plane placement; robust low-order yaw profile per action, fixed head height for the foot-only gear shift.',
        'metricSemantics':'Legacy helmetTop fields measure the upper rig envelope, which can be shoulder/back in deep tucks. Width fields are review diagnostics, not helmet-diameter acceptance tests.',
        'stateMetrics':metrics,'frames':records}
    (DEST/'registration.json').write_text(json.dumps(report,indent=2)+'\n')
    (OUT/'registration.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'completeStates':len(states),'stateMetrics':metrics}))

if __name__=='__main__':main()
