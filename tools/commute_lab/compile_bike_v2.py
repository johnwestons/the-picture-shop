"""Pack proportion-corrected mounted sprites; preserve the original parked bike.

Uses original RGBA sources, empty gutters, uniform scale and recorded tire-plane
anchors. A 4x2 atlas leaves room above the saddle without shrinking the bike.
"""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
STAGE = ROOT / 'assets/staging/commute-bike-v2'
REVIEW = ROOT / 'output/commute-bike-v2-review'
FRAME = 320
ANCHOR = (160, 260)
DIRECTIONS = ['north', 'northeast', 'east', 'southeast', 'south', 'southwest', 'west', 'northwest']
SOURCES = {
    'parked': ('assets/source/commute-bike-v1/parked-directions-source.png', .5,
               [(250,345),(673,364),(1123,376),(1554,367),(244,743),(644,752),(1088,794),(1532,772)]),
    'mounted': ('assets/source/commute-bike-v2/mounted-directions-source.png', .53,
                [(190,410),(584,447),(978,465),(1371,451),(187,888),(538,921),(936,933),(1345,901)]),
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def gutter(alpha, axis, target, radius=80):
    length = alpha.width if axis == 0 else alpha.height
    choices = []
    for value in range(max(1, int(target-radius)), min(length-1, int(target+radius))):
        rect = (value,0,value+1,alpha.height) if axis == 0 else (0,value,alpha.width,value+1)
        if alpha.crop(rect).getbbox() is None:
            choices.append(value)
    assert choices, ('No clear gutter', axis, target)
    return min(choices, key=lambda value: abs(value-target))


def main():
    STAGE.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    manifest = {'version':2, 'status':'staged_for_review', 'frameSize':FRAME,
                'atlasSize':[FRAME*4, FRAME*2], 'columns':4, 'anchor':list(ANCHOR),
                'directions':DIRECTIONS, 'runtimeScale':.46, 'mirror':False,
                'riderReference':'assets/source/commute-rider-v2/directional-idle-v1.png',
                'riderReferenceSha256':sha(ROOT/'assets/source/commute-rider-v2/directional-idle-v1.png'),
                'animations':{}, 'sources':[]}
    gallery = Image.new('RGBA',(8*180,2*190),(64,80,75,255))
    draw = ImageDraw.Draw(gallery)
    for row,(state,(source_path,scale,anchors)) in enumerate(SOURCES.items()):
        source = ROOT/source_path
        image = Image.open(source).convert('RGBA')
        alpha = image.getchannel('A').point(lambda a:255 if a>=16 else 0)
        mid = gutter(alpha,1,image.height/2)
        atlas = Image.new('RGBA',(FRAME*4,FRAME*2))
        cells = []
        for source_row,(top,bottom) in enumerate([(0,mid),(mid,image.height)]):
            band = alpha.crop((0,top,image.width,bottom))
            cuts = [0]+[gutter(band,0,image.width*n/4) for n in (1,2,3)]+[image.width]
            for col in range(4):
                index = source_row*4+col
                rect = (cuts[col],top,cuts[col+1],bottom)
                crop = image.crop(rect)
                ax,ay = anchors[index]
                rendered = crop.resize((round(crop.width*scale),round(crop.height*scale)),Image.Resampling.LANCZOS)
                position = (round(ANCHOR[0]-(ax-rect[0])*scale),round(ANCHOR[1]-(ay-top)*scale))
                tile = Image.new('RGBA',(FRAME,FRAME))
                tile.alpha_composite(rendered,position)
                bounds = tile.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
                assert bounds and min(bounds[0],bounds[1],FRAME-bounds[2],FRAME-bounds[3])>=3,(state,index,bounds)
                atlas.alpha_composite(tile,(col*FRAME,source_row*FRAME))
                native = tile.resize((round(FRAME*.46),round(FRAME*.46)),Image.Resampling.LANCZOS)
                gallery.alpha_composite(native,(index*180+16,row*190+28))
                draw.text((index*180+6,row*190+6),state+' / '+DIRECTIONS[index],fill='white')
                cells.append({'direction':DIRECTIONS[index],'sourceRect':list(rect),
                              'sourceAnchor':[ax,ay],'bbox':list(bounds)})
        target = STAGE/(state+'.png')
        atlas.save(target)
        manifest['animations'][state] = {'path':target.relative_to(ROOT).as_posix(),
                                         'frames':8,'cells':cells,'sha256':sha(target)}
        manifest['sources'].append({'path':source_path,'sha256':sha(source),'uniformScale':scale})
    gallery.save(REVIEW/'parked-mounted-native.png')
    (STAGE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print('Packed 16 vehicle views into 1280x640 atlases; 320px cells preserve rider headroom. Staged only.')


if __name__ == '__main__':
    main()
