"""Pack a newly authored 64-view set with one continuous size/anchor contract.

Only transparent slicing, uniform resizing and placement are performed here.
The old interleaved atlas remains available for independent before/after QA.
"""
import hashlib
import json
import math
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from compile_bike_turning import gutter

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/source/commute-bike-turning-v3'
STAGE=ROOT/'assets/staging/commute-bike-turning-v3'
REVIEW=ROOT/'output/bike-turning-quality-review'
FRAME=320

def digest(data): return hashlib.sha256(data).hexdigest()

def helmet_width(tile):
    a=np.asarray(tile)[:,:,3]>=16
    ys,xs=np.nonzero(a[70:106])
    return int(xs.max()-xs.min()+1)

def metrics(tiles):
    masks=[np.asarray(t)[:,:,3]>=16 for t in tiles]
    widths=[helmet_width(t) for t in tiles]
    distances=[float(1-(masks[i]&masks[(i+1)%64]).sum()/(masks[i]|masks[(i+1)%64]).sum()) for i in range(64)]
    return {'helmetBandWidths':widths,'maxAdjacentHelmetWidthChange':max(abs(widths[i]-widths[(i+1)%64]) for i in range(64)),
        'meanAdjacentHelmetWidthChange':float(np.mean([abs(widths[i]-widths[(i+1)%64]) for i in range(64)])),
        'meanHelmetWidthSecondDifference':float(np.mean([abs(widths[(i-1)%64]-2*widths[i]+widths[(i+1)%64]) for i in range(64)])),
        'meanSilhouetteChange':float(np.mean(distances)),'p95SilhouetteChange':float(np.percentile(distances,95)),
        'wrapSilhouetteChange':distances[-1]}

def main():
    STAGE.mkdir(parents=True,exist_ok=True);REVIEW.mkdir(parents=True,exist_ok=True)
    spec=json.loads((SOURCE/'source-sheets.json').read_text())
    cells=[None]*64;records=[None]*64
    for sheet in spec['sheets']:
        path=ROOT/sheet['path'];im=Image.open(path).convert('RGBA')
        w,h=im.size;cols,rows=sheet['columns'],sheet['rows']
        assert abs(w/h-cols/rows)<.05,(path,im.size)
        a=im.getchannel('A');assert a.getextrema()==(0,255),'Real alpha required'
        mask=a.point(lambda p:255 if p>=16 else 0)
        yc=[0]+[gutter(mask,1,h*i/rows) for i in range(1,rows)]+[h]
        for n,view in enumerate(sheet['views']):
            if view is None: continue
            row,col=n//cols,n%cols;y0,y1=yc[row:row+2]
            band=mask.crop((0,y0,w,y1));xc=[0]+[gutter(band,0,w*i/cols) for i in range(1,cols)]+[w]
            rect=(xc[col],y0,xc[col+1],y1);cell=im.crop(rect)
            b=cell.getchannel('A').point(lambda p:255 if p>=16 else 0).getbbox()
            assert b and min(b[0],b[1],cell.width-b[2],cell.height-b[3])>=2,(view,b)
            theta=math.tau*view/64
            target_bottom=260+26*abs(math.cos(theta))
            scale=(target_bottom-70)/(b[3]-b[1])
            resized=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.LANCZOS)
            tile=Image.new('RGBA',(320,320))
            tile.alpha_composite(resized,(round(160-(b[0]+b[2])*.5*scale),round(70-b[1]*scale)))
            box=tile.getchannel('A').point(lambda p:255 if p>=16 else 0).getbbox()
            assert min(box[0],box[1],320-box[2],320-box[3])>=3,(view,box)
            assert cells[view] is None,('Duplicate view mapping',view)
            cells[view]=tile
            records[view]={'frame':view+1,'yawFromRearDegrees':view*5.625,'source':sheet['path'],
                'sourceSha256':digest(path.read_bytes()),'sourceCell':n+1,'sourceRect':rect,
                'uniformScale':scale,'sourceObjectHeight':b[3]-b[1],
                'bbox':box,'helmetBandWidth':helmet_width(tile)}
    assert all(t is not None for t in cells),'Missing view'
    assert len({digest(t.tobytes()) for t in cells})==64,'Duplicate sprite pixels'
    atlas=Image.new('RGBA',(2560,2560));strip=Image.new('RGBA',(64*320,320))
    gallery=Image.new('RGBA',(1600,1728),(35,48,51,255));d=ImageDraw.Draw(gallery)
    for i,tile in enumerate(cells):
        atlas.alpha_composite(tile,(i%8*320,i//8*320));strip.alpha_composite(tile,(i*320,0))
        gallery.alpha_composite(tile.resize((184,184),Image.Resampling.LANCZOS),(i%8*200+8,i//8*216+27))
        d.text((i%8*200+8,i//8*216+7),f'{i+1:02} / {i*5.625:g} deg',fill='white')
    name='mounted-upright-64-v2.png';atlas.save(STAGE/name)
    strip.save(REVIEW/'upright-64-strip.png');gallery.save(REVIEW/'upright-64-contact-sheet.png')
    old=Image.open(ROOT/'assets/commute/bike/mounted-upright-64.png').convert('RGBA')
    previous=[old.crop((i%8*320,i//8*320,(i%8+1)*320,(i//8+1)*320)) for i in range(64)]
    before,after=metrics(previous),metrics(cells)
    acceptance={
        'all64Regenerated':all(digest(cells[i].tobytes())!=digest(previous[i].tobytes()) for i in range(64)),
        'lowerWorstSizeJump':after['maxAdjacentHelmetWidthChange']<before['maxAdjacentHelmetWidthChange'],
        'lowerAverageSizeJump':after['meanAdjacentHelmetWidthChange']<=.7*before['meanAdjacentHelmetWidthChange'],
        'lowerSizePulse':after['meanHelmetWidthSecondDifference']<=.7*before['meanHelmetWidthSecondDifference'],
        'lowerMeanSilhouetteChange':after['meanSilhouetteChange']<before['meanSilhouetteChange'],
        'lowerP95SilhouetteChange':after['p95SilhouetteChange']<before['p95SilhouetteChange'],
        'lowerWrapChange':after['wrapSilhouetteChange']<before['wrapSilhouetteChange'],
        'higherResolutionSources':min(f['sourceObjectHeight'] for f in records)>=250}
    report={'before':before,'after':after,'targetHeadTop':70,'targetGroundAnchor':[160,260],
        'normalization':'Uniform scale only; fixed head height with continuous projected tire-depth extent.',
        'qualityAcceptance':acceptance,'runtimeSha256':digest((STAGE/name).read_bytes()),'frames':records}
    (STAGE/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    (REVIEW/'size-and-transition-audit.json').write_text(json.dumps(report,indent=2)+'\n')
    audit={'version':1,'character':'commute-motorcycle-regenerated-64',
        'animations':{'upright':{'path':'output/bike-turning-quality-review/upright-64-strip.png',
            'frame_width':320,'frame_height':320,'frame_count':64,'role':'vehicle_direction_views','fps':12.5,'loop':True}},
        'applicability':{'walkGait':False,'expectedBundledAuditorSchemaErrors':['missing_directions','missing_gait']},
        'audit':{'alpha_threshold':16,'edge_margin':2,'baseline_tolerance':30,'center_tolerance':30}}
    (REVIEW/'vehicle-motion.json').write_text(json.dumps(audit,indent=2)+'\n')
    print(json.dumps({'before':before,'after':after,
        'minimumSourceObjectHeight':min(f['sourceObjectHeight'] for f in records),
        'qualityAcceptance':acceptance},indent=2))
    assert all(acceptance.values()),'Staged set did not meet before/after quality gates; do not publish'

if __name__=='__main__':main()
