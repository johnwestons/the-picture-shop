"""Package native procedural-effect captures into reviewable animations."""
from pathlib import Path
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/bike-motion-fx-review'

def gif(frames,path,duration):
    palette=frames[len(frames)//2].quantize(colors=128)
    converted=[frame.quantize(palette=palette,dither=Image.Dither.NONE) for frame in frames]
    converted[0].save(path,save_all=True,append_images=converted[1:],duration=duration,loop=0,optimize=False)

def main():
    frames=[Image.open(OUT/f'particles-{i:03}.png').convert('RGB') for i in range(1,97)]
    gif(frames,OUT/'bike-motion-fx.gif',40)
    tire=[]
    for tick in range(32):
        sheet=Image.new('RGB',(1280,350),(32,48,51));d=ImageDraw.Draw(sheet)
        for column,frame in enumerate([1,17,33,49]):
            image=Image.open(OUT/f'tire-roll-{frame:02}-{tick:02}.png').convert('RGBA')
            sheet.paste(image,(column*320,30),image)
            d.text((column*320+10,10),['Rear','Right','Front','Left'][column]+' / moving tire cue',fill=(238,230,202))
        tire.append(sheet)
    gif(tire,OUT/'tire-motion-closeup.gif',45)
    print('Saved bike-motion-fx.gif and tire-motion-closeup.gif from native draw frames')

if __name__=='__main__':main()
