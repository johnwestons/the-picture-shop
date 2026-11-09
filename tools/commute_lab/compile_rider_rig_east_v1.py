from pathlib import Path
from collections import deque
from hashlib import sha256
import json
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'assets/source/commute-rider-rig-east-v1/parts-atlas-v1.png'
OUT=ROOT/'assets/staging/commute-rider-rig-east-v1'
PAD=18
SPECS=[
 ('body',lambda b:b[0]<450 and b[1]<550,'Helmet, torso, pelvis'),
 ('upper_arm_near',lambda b:450<=b[0]<900 and b[1]<480,'Near upper arm'),
 ('upper_arm_far',lambda b:b[0]>=900 and b[1]<480,'Far upper arm'),
 ('forearm_glove_near',lambda b:b[0]<450 and 500<=b[1]<850,'Near forearm and glove'),
 ('forearm_glove_far',lambda b:450<=b[0]<900 and 500<=b[1]<850,'Far forearm and glove'),
 ('thigh_near',lambda b:b[0]>=900 and 480<=b[1]<850,'Near thigh'),
 ('thigh_far',lambda b:b[0]<450 and b[1]>=850,'Far thigh'),
 ('shin_boot_near',lambda b:450<=b[0]<900 and b[1]>=850,'Near shin and boot'),
 ('shin_boot_far',lambda b:b[0]>=900 and b[1]>=850,'Far shin and boot')]
def find_components(im):
 a=im.getchannel('A').load(); w,h=im.size; seen=bytearray(w*h); out=[]
 for y in range(h):
  for x in range(w):
   i=y*w+x
   if seen[i] or a[x,y]==0: continue
   seen[i]=1; todo=[i]; n=0; x0=x1=x; y0=y1=y
   while todo:
    k=todo.pop(); yy,xx=divmod(k,w); n+=1
    x0=min(x0,xx);x1=max(x1,xx);y0=min(y0,yy);y1=max(y1,yy)
    for ny in range(max(0,yy-1),min(h,yy+2)):
     for nx in range(max(0,xx-1),min(w,xx+2)):
      ni=ny*w+nx
      if not seen[ni] and a[nx,ny]>0:seen[ni]=1;todo.append(ni)
   if n>1000:out.append({'areaPx':n,'bboxPx':[x0,y0,x1+1,y1+1]})
 return out
OUT.mkdir(parents=True,exist_ok=True);(OUT/'parts').mkdir(exist_ok=True)
im=Image.open(SRC).convert('RGBA'); comps=find_components(im)
if len(comps)!=9: raise SystemExit(f'Expected 9 parts, got {len(comps)}')
parts=[]
for name,pred,label in SPECS:
 matches=[c for c in comps if pred(c['bboxPx'])]
 if len(matches)!=1:raise SystemExit(f'{name}: expected one match, got {len(matches)}')
 c=matches[0];x0,y0,x1,y1=c['bboxPx'];box=[max(0,x0-PAD),max(0,y0-PAD),min(im.width,x1+PAD),min(im.height,y1+PAD)]
 c.update({'name':name,'label':label,'cropBoxPx':box,'path':f'parts/{name}.png'})
 im.crop(tuple(box)).save(OUT/c['path']);parts.append(c)
# Review-only contact sheet; staged art parts are unchanged mechanical crops.
CW,CH=400,430; board=Image.new('RGBA',(CW*3,CH*3),(39,43,50,255));d=ImageDraw.Draw(board)
try:font=ImageFont.truetype('arial.ttf',18);small=ImageFont.truetype('arial.ttf',13)
except OSError:font=small=ImageFont.load_default()
for i,c in enumerate(parts):
 row,col=divmod(i,3);x=col*CW;y=row*CH;d.rectangle((x+2,y+2,x+CW-3,y+CH-3),fill=(50,55,64,255),outline=(115,124,138,255))
 art=Image.open(OUT/c['path']).convert('RGBA');scale=min((CW-24)/art.width,(CH-62)/art.height);sz=(round(art.width*scale),round(art.height*scale));art=art.resize(sz,Image.Resampling.LANCZOS);board.alpha_composite(art,(x+(CW-sz[0])//2,y+6+(CH-62-sz[1])//2));d.text((x+10,y+CH-48),c['name'],font=font,fill=(245,247,251,255));d.text((x+10,y+CH-24),f"bbox {c['bboxPx']}",font=small,fill=(187,196,209,255))
board.convert('RGB').save(OUT/'parts-contact.png')
manifest={'assetId':'commute-rider-rig-east-v1','historicalStatus':'retired_user_rejected_articulated_sprites','sourceImage':str(SRC.relative_to(ROOT)).replace('\\','/'),'sourceDimensionsPx':list(im.size),'sourceSha256':sha256(SRC.read_bytes()).hexdigest(),'extraction':'alpha-connected-component mechanical crops; no pixels repainted','paddingPx':PAD,'parts':parts}
(OUT/'parts-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf8')
print('Restored nine-part staging from immutable source atlas.')
