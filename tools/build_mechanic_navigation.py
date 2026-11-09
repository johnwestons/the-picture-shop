"""Bake the approved mechanic walkmask into a small runtime navigation grid."""
from pathlib import Path
import hashlib
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
FOLDER=ROOT/'assets/generated/mechanic-shop-v1'
MASK=FOLDER/'walkmask.png'
CELL=8
POLYGONS=[[(642,280),(797,337),(784,397),(644,341)],
 [(105,405),(188,387),(299,449),(296,557),(112,453)],
 [(550,464),(650,426),(753,490),(650,603),(548,553)],
 [(708,225),(900,286),(895,355),(784,300),(710,294)],
 [(437,166),(536,162),(549,216),(454,237)]]
ELLIPSES=[(300,337,82,30),(457,411,87,34)]
def inside(x,y,polygon):
 result=False
 j=len(polygon)-1
 for i,(px,py) in enumerate(polygon):
  qx,qy=polygon[j]
  if (py>y)!=(qy>y) and x<(qx-px)*(y-py)/(qy-py)+px: result=not result
  j=i
 return result
def main():
 image=Image.open(MASK).convert('RGB');width,height=image.size
 assert (width,height)==(1536,1024)
 def free(x,y):
  if not 0<=x<960 or not 0<=y<678:return False
  rgb=image.getpixel((int(x/960*width),int(y/678*height)))
  if min(rgb)<=229:return False
  if any(((x-cx)/rx)**2+((y-cy)/ry)**2<=1 for cx,cy,rx,ry in ELLIPSES):return False
  return not any(inside(x,y,p)for p in POLYGONS)
 rows=[]
 for row in range(85):
  y=(row+.5)*CELL
  rows.append(''.join('1' if all(free(x+dx,y+dy)for dx,dy in [(-6,0),(0,2),(6,0)])else'0' for x in [(col+.5)*CELL for col in range(120)]))
 result='-- Derived from the approved white walkmask plus visible furniture footprints.\nreturn {cell=8,width=960,height=678,columns=120,rows=85,sourceSha256="'+hashlib.sha256(MASK.read_bytes()).hexdigest()+'",grid={\n'
 result+=''.join('    "'+row+'",\n'for row in rows)+'}}\n'
 (FOLDER/'navigation.lua').write_text(result)
 for x,y in [(620,280),(700,430),(350,390),(640,248),(666,407)]:
  assert rows[int(y/CELL)][int(x/CELL)]=='1',(x,y,'blocked landmark')
 print('MECHANIC_NAVIGATION_READY',sum(row.count('1')for row in rows),'walkable cells')
if __name__=='__main__':main()
