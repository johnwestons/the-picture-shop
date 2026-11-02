"""Noncreative sprite packing: retain generated RGBA, slice at empty gutters,
use one uniform source scale, and register at the midpoint of tire contacts.
No painting, inpainting, silhouette deformation or mirrored vehicle views.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import hashlib, json

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/source/commute-bike-v1'
STAGE=ROOT/'assets/staging/commute-bike-v1'
REVIEW=ROOT/'output/commute-bike-review'
STAGE.mkdir(parents=True,exist_ok=True);REVIEW.mkdir(parents=True,exist_ok=True)
DIRECTIONS=['north','northeast','east','southeast','south','southwest','west','northwest']
# Reviewed source-space midpoint of front/rear tire ground contacts. The far
# tire is occluded in straight front/rear views; anchors follow the same plane.
ANCHORS={
    'parked':[(250,345),(673,364),(1123,376),(1554,367),(244,743),(644,752),(1088,794),(1532,772)],
    'mounted':[(244,368),(665,399),(1117,417),(1552,401),(244,764),(642,780),(1089,802),(1538,786)],
}
FRAME=256;ANCHOR=(128,210);SCALE=.50

def gutter(alpha,axis,target,radius):
    length=alpha.width if axis==0 else alpha.height
    empty=[]
    for v in range(max(1,int(target-radius)),min(length-1,int(target+radius))):
        crop=alpha.crop((v,0,v+1,alpha.height) if axis==0 else (0,v,alpha.width,v+1))
        if crop.getbbox() is None: empty.append(v)
    if not empty: raise ValueError(f'No safe transparent gutter near {target}')
    return min(empty,key=lambda v:abs(v-target))

manifest={'version':1,'status':'staged_for_review','frameSize':FRAME,'anchor':list(ANCHOR),
    'directions':DIRECTIONS,'runtimeScale':.46,'mirror':False,'animations':{},'sources':[]}
gallery=Image.new('RGBA',(8*160,2*174),(54,64,53,255));draw=ImageDraw.Draw(gallery)
for row,state in enumerate(['parked','mounted']):
    source=SOURCE/f'{state}-directions-source.png';image=Image.open(source).convert('RGBA')
    assert image.size==(1774,887),f'Review import geometry for {source}: {image.size}'
    alpha=image.getchannel('A').point(lambda a:255 if a>=16 else 0)
    middle=gutter(alpha,1,image.height/2,60)
    atlas=Image.new('RGBA',(FRAME*8,FRAME));cells=[]
    for source_row,(y0,y1) in enumerate([(0,middle),(middle,image.height)]):
        band=alpha.crop((0,y0,image.width,y1))
        cuts=[0]+[gutter(band,0,image.width*n/4,80) for n in (1,2,3)]+[image.width]
        for col in range(4):
            index=source_row*4+col;direction=DIRECTIONS[index]
            rect=(cuts[col],y0,cuts[col+1],y1);cell=image.crop(rect)
            ax,ay=ANCHORS[state][index]
            rendered=cell.resize((round(cell.width*SCALE),round(cell.height*SCALE)),Image.Resampling.LANCZOS)
            x=round(ANCHOR[0]-(ax-rect[0])*SCALE);y=round(ANCHOR[1]-(ay-rect[1])*SCALE)
            frame=Image.new('RGBA',(FRAME,FRAME));frame.alpha_composite(rendered,(x,y))
            box=frame.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
            assert box and min(box[0],box[1],FRAME-box[2],FRAME-box[3])>=3,(state,direction,'clipping',box)
            atlas.alpha_composite(frame,(index*FRAME,0))
            native=frame.resize((118,118),Image.Resampling.LANCZOS)
            gallery.alpha_composite(native,(index*160+21,row*174+34))
            draw.text((index*160+8,row*174+8),state+' / '+direction,fill='white')
            px=index*160+21+ANCHOR[0]*.46;py=row*174+34+ANCHOR[1]*.46
            draw.line((px-3,py,px+3,py),fill=(245,220,140));draw.line((px,py-3,px,py+3),fill=(245,220,140))
            cells.append({'direction':direction,'sourceRect':list(rect),'sourceAnchor':[ax,ay],'bbox':list(box)})
    path=STAGE/f'{state}.png';atlas.save(path)
    manifest['animations'][state]={'path':path.relative_to(ROOT).as_posix(),'frames':8,'cells':cells,
        'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    manifest['sources'].append({'path':source.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(source.read_bytes()).hexdigest()})
(STAGE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
gallery.save(REVIEW/'parked-mounted-native.png')
print('Staged 16 vehicle views with tire-contact registration. Native contact sheet requires visual approval.')
