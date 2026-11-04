"""Pack generated turntable RGBA without repainting, mirroring or morphing.

Source images remain immutable. Empty-gutter slicing and tire-plane registration
are recorded so the atlas, labeled review sheet and loop can be reproduced.
"""
import hashlib
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/source/commute-bike-turning-v1/upright-32-source.png'
STAGE=ROOT/'assets/staging/commute-bike-turning-v1'
REVIEW=ROOT/'output/bike-turning-review'
FRAME=320
ANCHOR=(160,260)

def gutter(alpha,axis,target,radius=26):
    limit=alpha.width if axis==0 else alpha.height
    choices=[]
    for v in range(max(1,round(target)-radius),min(limit-1,round(target)+radius)):
        line=(v,0,v+1,alpha.height) if axis==0 else (0,v,alpha.width,v+1)
        if alpha.crop(line).getbbox() is None: choices.append(v)
    assert choices,('No empty gutter',axis,target)
    return min(choices,key=lambda v:abs(v-target))

def main():
    STAGE.mkdir(parents=True,exist_ok=True)
    REVIEW.mkdir(parents=True,exist_ok=True)
    image=Image.open(SOURCE).convert('RGBA')
    w,h=image.size
    assert w==h*2,(w,h)
    alpha=image.getchannel('A').point(lambda a:255 if a>=16 else 0)
    rowcuts=[0]+[gutter(alpha,1,h*r/4) for r in range(1,4)]+[h]
    atlas=Image.new('RGBA',(FRAME*8,FRAME*4))
    strip=Image.new('RGBA',(FRAME*32,FRAME))
    gallery=Image.new('RGBA',(8*200,4*216),(35,48,51,255))
    draw=ImageDraw.Draw(gallery)
    frames=[]
    previews=[]
    hashes=set()
    for i in range(32):
        row,col=i//8,i%8
        y0,y1=rowcuts[row:row+2]
        band=alpha.crop((0,y0,w,y1))
        cuts=[0]+[gutter(band,0,w*c/8) for c in range(1,8)]+[w]
        rect=(cuts[col],y0,cuts[col+1],y1)
        cell=image.crop(rect)
        cw,ch=cell.size
        bounds=cell.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
        assert bounds and min(bounds[0],bounds[1],cw-bounds[2],ch-bounds[3])>=2,(i,bounds)
        digest=hashlib.sha256(cell.tobytes()).hexdigest()
        assert digest not in hashes,('Duplicate view',i)
        hashes.add(digest)
        # The near tire extends below the tire-plane midpoint in end-on views.
        # Register the upright helmet above the tire plane. Correct generator
        # scale drift with uniform per-cell resizing, never axis deformation.
        angle=i*math.tau/32
        source_anchor=((bounds[0]+bounds[2])*.5,bounds[3]-22*abs(math.cos(angle)))
        scale=190/(source_anchor[1]-bounds[1])
        rendered=cell.resize((round(cw*scale),round(ch*scale)),Image.Resampling.LANCZOS)
        tile=Image.new('RGBA',(FRAME,FRAME))
        tile.alpha_composite(rendered,(round(ANCHOR[0]-source_anchor[0]*scale),
                                      round(ANCHOR[1]-source_anchor[1]*scale)))
        box=tile.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
        assert min(box[0],box[1],FRAME-box[2],FRAME-box[3])>=3,(i,box)
        atlas.alpha_composite(tile,(i%8*FRAME,i//8*FRAME))
        strip.alpha_composite(tile,(i*FRAME,0))
        native=tile.resize((184,184),Image.Resampling.LANCZOS)
        gx,gy=i%8*200,i//8*216
        gallery.alpha_composite(native,(gx+8,gy+27))
        draw.text((gx+8,gy+7),f'{i+1:02} / {i*11.25:g} deg',fill='white')
        ax,ay=gx+8+160*184/320,gy+27+260*184/320
        draw.line((ax-5,ay,ax+5,ay),fill='#ffda83')
        draw.line((ax,ay-5,ax,ay+5),fill='#ffda83')
        preview=Image.new('RGBA',(320,348),(35,48,51,255))
        preview.alpha_composite(tile,(0,20))
        ImageDraw.Draw(preview).text((8,6),f'{i+1:02} / {i*11.25:g} degrees from rear',fill='white')
        previews.append(preview.convert('RGB'))
        frames.append({'frame':i+1,'yawFromRearDegrees':i*11.25,'sourceRect':rect,
                       'sourceAnchor':source_anchor,'uniformScale':scale,'bbox':box,'sha256':digest})
    atlas.save(STAGE/'mounted-upright-32.png')
    strip.save(REVIEW/'upright-32-strip.png')
    gallery.save(REVIEW/'upright-32-contact-sheet.png')
    previews[0].save(REVIEW/'upright-32-loop.gif',save_all=True,append_images=previews[1:],
                     duration=100,loop=0,disposal=2)
    manifest={'version':1,'character':'commute-motorcycle-rider','specType':'vehicle_pose',
        'status':'staged_for_visual_review','frameCount':32,'frameSize':FRAME,'columns':8,
        'anchor':ANCHOR,'runtimeScale':.46,'headHeightAboveAnchor':190,'mirror':False,
        'source':SOURCE.relative_to(ROOT).as_posix(),
        'sourceSha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'frames':frames}
    (STAGE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    audit={'version':1,'character':'commute-motorcycle-upright-turntable',
        'animations':{'upright':{'path':'output/bike-turning-review/upright-32-strip.png',
            'frame_width':320,'frame_height':320,'frame_count':32,'role':'vehicle_direction_views',
            'fps':10,'loop':True}},
        'applicability':{'walkGait':False,'reason':'Vehicle yaw views; not walking or idle strips.',
                         'expectedBundledAuditorSchemaErrors':['missing_directions','missing_gait']},
        'audit':{'alpha_threshold':16,'edge_margin':2,'baseline_tolerance':30,'center_tolerance':30}}
    (REVIEW/'vehicle-motion.json').write_text(json.dumps(audit,indent=2)+'\n')
    print('Staged 32 unique upright views; visual review required before integration.')

if __name__=='__main__': main()
