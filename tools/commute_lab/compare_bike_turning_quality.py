"""Compare the two 64-view sets captured through the production LÖVE draw path."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[2]
BEFORE=ROOT/'output/bike-turning-64-review'
AFTER=ROOT/'output/bike-turning-quality-review'

def main():
    pairs=[];turn=[]
    for i in range(1,129):
        old=Image.open(BEFORE/f'native-turn-{i:03}.png').convert('RGB')
        new=Image.open(AFTER/f'native-turn-{i:03}.png').convert('RGB')
        assert old.size==new.size==(320,320)
        comparison=Image.new('RGB',(640,350),(33,49,51))
        comparison.paste(old,(0,30));comparison.paste(new,(320,30))
        d=ImageDraw.Draw(comparison)
        d.text((12,10),'Previous 64 views',fill='white')
        d.text((332,10),'Regenerated 64 views',fill='white')
        pairs.append(comparison)
        turn.append(new)
    for name,frames in [('native-before-after.gif',pairs),('native-regenerated-turn.gif',turn)]:
        # Fixed palette prevents per-frame GIF palette shimmer from disguising
        # the actual sprite transitions we are reviewing.
        montage=Image.new('RGB',(640,350*16))
        for i,f in enumerate(pairs[::8]):montage.paste(f,(0,i*350))
        palette=montage.quantize(colors=256)
        indexed=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
        indexed[0].save(AFTER/name,save_all=True,append_images=indexed[1:],duration=70,loop=0,disposal=2)
    pairs[0].save(AFTER/'native-before-after-rear.png')
    pairs[64].save(AFTER/'native-before-after-front.png')
    print(json.dumps({'framesPerRotation':128,'directionViews':64,
        'capture':'production Art.draw, one opaque sprite per heading',
        'outputs':['native-before-after.gif','native-regenerated-turn.gif']}))

if __name__=='__main__':main()
