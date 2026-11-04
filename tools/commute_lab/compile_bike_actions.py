"""Register generated rider poses against the approved, unchanged tire geometry.

Only transparent slicing, uniform resizing and translation are allowed. The
helmet/torso is free to articulate; it is never stretched to match a bbox.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from compile_bike_turning import gutter

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/source/commute-bike-actions-v1'
STAGE=ROOT/'assets/staging/commute-bike-actions-v1'
REVIEW=ROOT/'output/bike-actions-64-review'

def sha(data):return hashlib.sha256(data).hexdigest()
def mask(im):return im.getchannel('A').point(lambda p:255 if p>=24 else 0)

def remove_detached_background(cell):
    """Keep the connected rig plus its antialias border; erase only tiny specks."""
    arr=np.asarray(cell).copy();solid=arr[:,:,3]>=24;parent=[];runs=[];previous=[]
    def find(i):
        while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
        return i
    for y,row in enumerate(solid):
        transitions=np.diff(np.pad(row.astype(np.int8),(1,1)))
        current=[]
        for start,end in zip(np.flatnonzero(transitions==1),np.flatnonzero(transitions==-1)):
            label=len(parent);parent.append(label)
            for ps,pe,pl in previous:
                if pe>=start and ps<=end:parent[find(pl)]=find(label)
            current.append((int(start),int(end),label));runs.append((y,int(start),int(end),label))
        previous=current
    areas={}
    for y,start,end,label in runs:
        root=find(label);areas[root]=areas.get(root,0)+end-start
    main=max(areas,key=areas.get);others=[area for root,area in areas.items() if root!=main]
    assert not others or max(others)<32,('Substantive disconnected pixels need visual review',sorted(others,reverse=True)[:5])
    support=np.zeros(solid.shape,dtype=np.uint8)
    for y,start,end,label in runs:
        if find(label)==main:support[y,start:end]=255
    keep=np.asarray(Image.fromarray(support).filter(ImageFilter.MaxFilter(7)))>0
    removed=int(((arr[:,:,3]>0)&~keep).sum());arr[~keep]=0
    return Image.fromarray(arr),{'detachedBackgroundPixelsRemoved':removed,'largestDetachedSolidArea':max(others,default=0)}

def slice_sheet(path):
    im=Image.open(path).convert('RGBA');w,h=im.size
    assert abs(w/h-1)<.03,(path,im.size)
    alpha=mask(im);assert im.getchannel('A').getextrema()==(0,255),(path,'true alpha required')
    yc=[0]+[gutter(alpha,1,h*i/4) for i in range(1,4)]+[h]
    cells=[]
    for i in range(16):
        row,col=i//4,i%4;y0,y1=yc[row:row+2]
        band=alpha.crop((0,y0,w,y1))
        xc=[0]+[gutter(band,0,w*j/4) for j in range(1,4)]+[w]
        rect=(xc[col],y0,xc[col+1],y1);cell=im.crop(rect);b=mask(cell).getbbox()
        assert b and min(b[0],b[1],cell.width-b[2],cell.height-b[3])>=2,(path,i,b)
        clean,cleanup=remove_detached_background(cell)
        cells.append((clean,rect,cleanup))
    return cells

def lower_center(a,bottom,depth):
    ys,xs=np.nonzero(a[max(0,round(bottom-depth)):bottom])
    return float(xs.mean())

def register(cell,reference):
    a=mask(cell);b=a.getbbox();ref=mask(reference);rb=ref.getbbox()
    target=np.asarray(ref)>=128;bottom=rb[3];region=slice(195,300)
    rx=lower_center(target,bottom,60)
    # Fit the unchanged wheels/chassis, not the moving helmet or torso.
    sw=b[2]-b[0];rw=rb[2]-rb[0]
    estimate=rw/sw
    best=None
    def search(scales,offsets):
        nonlocal best
        for s in scales:
            source=np.asarray(a)>=128;sx=lower_center(source,b[3],60/s)
            scaled=a.resize((round(cell.width*s),round(cell.height*s)),Image.Resampling.BILINEAR)
            y=round(bottom-b[3]*s);x0=round(rx-sx*s)
            for dx in offsets:
                x=x0+dx;t=Image.new('L',(320,320));t.paste(scaled,(x,y))
                candidate=np.asarray(t)>=128;u=(target[region]|candidate[region]).sum()
                score=float((target[region]&candidate[region]).sum()/u) if u else 0
                if best is None or score>best[0]:best=(score,s,x,y)
    search(np.linspace(max(.35,estimate-.2),min(1.6,estimate+.2),25),range(-6,7,3))
    score,s,x,y=best
    search(np.linspace(s-.016,s+.016,9),range(-3,4))
    score,s,x,y=best
    tile=Image.new('RGBA',(320,320))
    tile.alpha_composite(cell.resize((round(cell.width*s),round(cell.height*s)),Image.Resampling.LANCZOS),(x,y))
    box=mask(tile).getbbox();arr=np.asarray(mask(tile))>=128
    assert min(box[0],box[1],320-box[2],320-box[3])>=2,('clipped registered frame',box)
    # Upper-envelope diagnostic only. In deep tucks this band can include
    # shoulder/back, so it must not be used as a helmet-diameter assertion.
    ys,xs=np.nonzero(arr[box[1]:box[1]+24]);width=int(xs.max()-xs.min()+1)
    return tile,{'uniformScale':s,'translation':[x,y],'wheelSilhouetteIoU':score,
        'bbox':box,'helmetTopBandWidth':width,'helmetTop':box[1]}

def crown_width(tile):
    a=np.asarray(mask(tile))>=128;b=mask(tile).getbbox()
    ys,xs=np.nonzero(a[b[1]:b[1]+24])
    return int(xs.max()-xs.min()+1)

def state_metrics(state,records,base):
    rows=sorted((r for r in records if r['state']==state),key=lambda r:r['frame'])
    by_frame={r['frame']:r for r in rows};jumps=[];height_jumps=[];seams=[]
    for r in rows:
        nxt=by_frame.get(r['frame']%64+1)
        if not nxt:continue
        delta=abs(r['helmetTopBandWidth']-nxt['helmetTopBandWidth'])
        dy=abs(r['helmetTop']-nxt['helmetTop'])
        jumps.append(delta);height_jumps.append(dy)
        if delta>4 or dy>8:seams.append({'from':r['frame'],'to':nxt['frame'],'crownWidthChange':delta,'headHeightChange':dy})
    return {'availableViews':len(rows),'minimumWheelIoU':min(r['wheelSilhouetteIoU'] for r in rows),
        'maxAdjacentCrownWidthChange':max(jumps,default=0),'meanAdjacentCrownWidthChange':float(np.mean(jumps)) if jumps else 0,
        'maxAdjacentHeadHeightChange':max(height_jumps,default=0),
        'maxCrownWidthDifferenceFromUpright':max(abs(r['helmetTopBandWidth']-crown_width(base[r['frame']-1])) for r in rows),
        'seamsForReview':seams}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--partial',action='store_true');args=parser.parse_args()
    spec=json.loads((SOURCE/'production.json').read_text())
    upright=Image.open(ROOT/spec['approvedUpright']).convert('RGBA')
    base=[upright.crop((i%8*320,i//8*320,(i%8+1)*320,(i//8+1)*320)) for i in range(64)]
    STAGE.mkdir(parents=True,exist_ok=True);REVIEW.mkdir(parents=True,exist_ok=True)
    states={};records=[];completed=[]
    for job in spec['jobs']:
        path=ROOT/job['source']
        if not path.exists():
            assert args.partial,('Missing source sheet',job['id'])
            continue
        completed.append(job['id']);cells=slice_sheet(path)
        gallery=Image.new('RGBA',(960,8*340),(33,49,51));d=ImageDraw.Draw(gallery)
        for phase,state in enumerate(job['states']):
            frames=states.setdefault(state,[None]*64)
            for n,view in enumerate(job['views']):
                cell,rect,cleanup=cells[phase*8+n];tile,record=register(cell,base[view]);frames[view]=tile
                record.update({'state':state,'frame':view+1,'source':job['source'],
                    'sourceSha256':sha(path.read_bytes()),'sourceRect':rect,'sourceCell':phase*8+n+1})
                record.update(cleanup)
                record['paintLower']=max(155,math.ceil(record['helmetTop']+68))
                records.append(record)
                gallery.alpha_composite(tile,((phase+1)*320,n*340+20))
                d.text(((phase+1)*320+8,n*340+3),state+' / '+str(view+1),fill='white')
                if phase==0:
                    gallery.alpha_composite(base[view],(0,n*340+20));d.text((8,n*340+3),'approved upright / '+str(view+1),fill='white')
        gallery.save(REVIEW/(job['id']+'-registered.png'))
    for state,frames in states.items():
        if any(f is None for f in frames):continue
        assert len({sha(f.tobytes()) for f in frames})==64,(state,'duplicate frames')
        atlas=Image.new('RGBA',(2560,2560));strip=Image.new('RGBA',(20480,320))
        folder=STAGE/'pages';folder.mkdir(exist_ok=True)
        for i,tile in enumerate(frames):
            atlas.alpha_composite(tile,(i%8*320,i//8*320));strip.alpha_composite(tile,(i*320,0))
        atlas.save(STAGE/f'{state}-64.png');strip.save(REVIEW/f'{state}-strip.png')
        for page in range(4):
            image=Image.new('RGBA',(1280,1280))
            for n in range(16):image.alpha_composite(frames[page*16+n],(n%4*320,n//4*320))
            image.save(folder/f'{state}-{page+1}.png')
    summary={state:state_metrics(state,records,base) for state in states}
    report={'version':1,'completedJobs':completed,'expectedJobs':len(spec['jobs']),
        'processing':'only uniform scale/translation registered to the approved tire silhouette; no head-height normalization',
        'stateMetrics':summary,'frames':records}
    (STAGE/'registration.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'completedJobs':len(completed),'expectedJobs':len(spec['jobs']),
        'minimumWheelIoU':min(r['wheelSilhouetteIoU'] for r in records) if records else None,
        'stateMetrics':summary}))

if __name__=='__main__':main()
