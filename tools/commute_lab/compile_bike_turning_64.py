"""Interleave 32 generated midpoint views with the approved 32, losslessly.

This packs RGBA sprites only: no painted repairs, mirrored views, morphing or
alpha crossfades. All odd frames preserve the existing runtime pixels exactly.
"""
import hashlib
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw
from compile_bike_turning import gutter

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/source/commute-bike-turning-v2/upright-between-32-paired-source.png'
BASE=ROOT/'assets/commute/bike/mounted-upright-32.png'
STAGE=ROOT/'assets/staging/commute-bike-turning-v2'
REVIEW=ROOT/'output/bike-turning-64-review'
FRAME=320
ANCHOR=(160,260)

def sha(data): return hashlib.sha256(data).hexdigest()

def main():
    STAGE.mkdir(parents=True,exist_ok=True);REVIEW.mkdir(parents=True,exist_ok=True)
    image=Image.open(SOURCE).convert('RGBA');base=Image.open(BASE).convert('RGBA')
    assert base.size==(2560,1280),base.size
    w,h=image.size;assert w==2*h,(w,h)
    alpha=image.getchannel('A');assert alpha.getextrema()==(0,255),'Source must have real transparency'
    mask=alpha.point(lambda a:255 if a>=16 else 0)
    rows=[0]+[gutter(mask,1,h*r/4) for r in range(1,4)]+[h]
    tiles=[];records=[]
    for i in range(32):
        previous=base.crop((i%8*FRAME,i//8*FRAME,(i%8+1)*FRAME,(i//8+1)*FRAME))
        tiles.append(previous)
        records.append({'frame':2*i+1,'yawFromRearDegrees':i*11.25,'source':'approved32',
                        'sourceCell':i+1,'sha256':sha(previous.tobytes())})
        y0,y1=rows[i//8:i//8+2]
        band=mask.crop((0,y0,w,y1))
        cuts=[0]+[gutter(band,0,w*c/8) for c in range(1,8)]+[w]
        rect=(cuts[i%8],y0,cuts[i%8+1],y1)
        cell=image.crop(rect);cw,ch=cell.size
        bounds=cell.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
        assert bounds and min(bounds[0],bounds[1],cw-bounds[2],ch-bounds[3])>=2,(i,bounds)
        following=(i+1)%32
        next_tile=base.crop((following%8*320,following//8*320,(following%8+1)*320,(following//8+1)*320))
        adjacent=[v.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox() for v in (previous,next_tile)]
        # Correct generator scale/registration drift against BOTH approved
        # neighbors. Their interpolated head and tire extents define this
        # intermediate view, using uniform scaling rather than deformation.
        target_top=sum(b[1] for b in adjacent)*.5
        target_bottom=sum(b[3] for b in adjacent)*.5
        target_center=sum((b[0]+b[2])*.5 for b in adjacent)*.5
        scale=(target_bottom-target_top)/(bounds[3]-bounds[1])
        source_anchor=((bounds[0]+bounds[2])*.5,bounds[1]+(260-target_top)/scale)
        rendered=cell.resize((round(cw*scale),round(ch*scale)),Image.Resampling.LANCZOS)
        tile=Image.new('RGBA',(FRAME,FRAME))
        tile.alpha_composite(rendered,(round(target_center-source_anchor[0]*scale),round(260-source_anchor[1]*scale)))
        bounds=tile.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
        assert bounds and min(bounds[0],bounds[1],320-bounds[2],320-bounds[3])>=3,(i,bounds)
        tiles.append(tile)
        records.append({'frame':2*i+2,'yawFromRearDegrees':i*11.25+5.625,
            'source':'generatedMidpoint32','sourceCell':i+1,'sourceRect':rect,
            'sourceAnchor':source_anchor,'uniformScale':scale,'adjacentHeadTop':target_top,
            'adjacentTireBottom':target_bottom,'sha256':sha(tile.tobytes())})
    assert len({sha(tile.tobytes()) for tile in tiles})==64,'Duplicate turntable pixels'
    atlas=Image.new('RGBA',(2560,2560));strip=Image.new('RGBA',(FRAME*64,FRAME))
    gallery=Image.new('RGBA',(1600,8*216),(35,48,51,255));draw=ImageDraw.Draw(gallery)
    previews=[]
    for i,tile in enumerate(tiles):
        atlas.alpha_composite(tile,(i%8*320,i//8*320));strip.alpha_composite(tile,(i*320,0))
        gx,gy=i%8*200,i//8*216
        gallery.alpha_composite(tile.resize((184,184),Image.Resampling.LANCZOS),(gx+8,gy+27))
        draw.text((gx+8,gy+7),f'{i+1:02} / {i*5.625:g} deg / '+('old' if i%2==0 else 'NEW'),fill='white')
        ax,ay=gx+8+160*184/320,gy+27+260*184/320
        draw.line((ax-5,ay,ax+5,ay),fill='#ffda83');draw.line((ax,ay-5,ax,ay+5),fill='#ffda83')
        records[i]['bbox']=tile.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
        preview=Image.new('RGBA',(320,348),(35,48,51,255));preview.alpha_composite(tile,(0,20))
        ImageDraw.Draw(preview).text((8,6),f'{i+1:02} / {i*5.625:g} degrees',fill='white')
        previews.append(preview.convert('RGB'))
        if i%2==0:
            j=i//2
            assert tile.tobytes()==base.crop((j%8*320,j//8*320,(j%8+1)*320,(j//8+1)*320)).tobytes()
    for i in range(32):
        dense=i*2
        assert atlas.crop((dense%8*320,dense//8*320,(dense%8+1)*320,(dense//8+1)*320)).tobytes()==tiles[dense].tobytes()
    atlas.save(STAGE/'mounted-upright-64.png');strip.save(REVIEW/'upright-64-strip.png')
    gallery.save(REVIEW/'upright-64-contact-sheet.png')
    previews[0].save(REVIEW/'upright-64-loop.gif',save_all=True,append_images=previews[1:],duration=80,loop=0,disposal=2)
    manifest={'version':2,'character':'commute-motorcycle-rider','specType':'vehicle_pose',
        'status':'staged_for_visual_review','frameCount':64,'frameSize':320,'columns':8,'rows':8,
        'anchor':ANCHOR,'runtimeScale':.46,'mirror':False,'preservedOriginalFrames':32,
        'source':SOURCE.relative_to(ROOT).as_posix(),'sourceSha256':sha(SOURCE.read_bytes()),
        'base':BASE.relative_to(ROOT).as_posix(),'baseSha256':sha(BASE.read_bytes()),'frames':records}
    (STAGE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    audit={'version':1,'character':'commute-motorcycle-upright-64-turntable',
        'animations':{'upright':{'path':'output/bike-turning-64-review/upright-64-strip.png',
            'frame_width':320,'frame_height':320,'frame_count':64,'role':'vehicle_direction_views','fps':12.5,'loop':True}},
        'applicability':{'walkGait':False,'reason':'Vehicle yaw views; not walking or idle strips.',
            'expectedBundledAuditorSchemaErrors':['missing_directions','missing_gait']},
        'audit':{'alpha_threshold':16,'edge_margin':2,'baseline_tolerance':30,'center_tolerance':30}}
    (REVIEW/'vehicle-motion.json').write_text(json.dumps(audit,indent=2)+'\n')
    print('Staged 64 unique views, including all 32 original frames unchanged. Review required.')

if __name__=='__main__': main()
