"""Assemble a preview from actual native runtime draw captures, without repainting."""
import json
import math
from PIL import Image,ImageDraw
from compile_bike_actions import REVIEW

PANELS=[('upright','Upright'),('boost','Acceleration'),('brake','Hard braking'),('turnLeft','Left lean'),
    ('turnRight','Right lean'),('aero','Tuck'),('shift','Gear shift'),('impact','Impact brace')]

def main():
    coverage=json.loads((REVIEW/'native-draw-coverage.json').read_text())
    assert len(coverage['poses'])==15
    for state,rows in coverage['poses'].items():
        assert len(rows)==64 and all(r['state']==state and r['frame']==r['drawnFrame'] and r['count']==1 and r['alpha']==1 for r in rows)
    images={}
    for state in coverage['poses']:
        images[state]=[Image.open(REVIEW/f'native-{state}-{i:02}.png').convert('RGB').crop((32,70,288,310)) for i in range(1,65)]
    frames=[]
    for n in range(128):
        canvas=Image.new('RGB',(1024,544),(33,49,51));d=ImageDraw.Draw(canvas)
        view=n//2
        for panel,(action,label) in enumerate(PANELS):
            # A slow review cycle visits both authored stages and returns upright.
            weight=max(0,math.sin(n/128*math.tau*2))
            state='upright' if action=='upright' or weight<.25 else action+'Mid' if weight<.75 else action
            x=panel%4*256;y=panel//4*272
            canvas.paste(images[state][view],(x,y+32));d.text((x+12,y+8),label+' / '+f'{view+1:02}',fill=(245,234,203))
        frames.append(canvas)
    palette=frames[16].quantize(colors=128)
    converted=[im.quantize(palette=palette,dither=Image.Dither.NONE) for im in frames]
    converted[0].save(REVIEW/'native-actions-64.gif',save_all=True,append_images=converted[1:],duration=70,loop=0,optimize=False)
    frames[24].save(REVIEW/'native-actions-preview.png')
    print('Verified 960 native draw captures; saved native-actions-64.gif and native-actions-preview.png')

if __name__=='__main__':main()
