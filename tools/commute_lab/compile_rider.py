"""Extract generated sprite cells into staged strips for the motion audit.

Immutable sources retain the original alpha. This only slices, scales uniformly
per strip and aligns helmet center / boot-contact baseline; no painted repairs.
"""
import hashlib
import json
from pathlib import Path
from statistics import median
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/source/commute-rider-v1'
STAGE = ROOT / 'assets/staging/commute-rider-v1'
STAGE.mkdir(parents=True, exist_ok=True)
DIRECTIONS = ['north', 'northeast', 'east', 'southeast', 'south']
FRAME, BASELINE, HEIGHT = 256, 232, 196

def cell(image, col, row, cols, rows):
    w, h = image.size
    return image.crop((round(col*w/cols), round(row*h/rows),
                       round((col+1)*w/cols), round((row+1)*h/rows)))

def bounds(image):
    return image.getchannel('A').point(lambda a: 255 if a >= 16 else 0).getbbox()

def strip(name, frames):
    boxes = [bounds(im) for im in frames]
    scale = HEIGHT / median(box[3]-box[1] for box in boxes)
    out = Image.new('RGBA', (FRAME*len(frames), FRAME))
    for i, (im, box) in enumerate(zip(frames, boxes)):
        # Align to helmet rather than swinging hands/feet. Keep the generated
        # pose's own body height/bob instead of scaling every frame separately.
        helmet = im.crop((0, box[1], im.width, box[1]+round((box[3]-box[1])*.35)))
        head = bounds(helmet)
        center = (head[0]+head[2])*.5
        size = (round(im.width*scale), round(im.height*scale))
        rendered = im.resize(size, Image.Resampling.LANCZOS)
        x, y = round(FRAME*.5-center*scale), round(BASELINE-box[3]*scale)
        target = Image.new('RGBA', (FRAME, FRAME));target.alpha_composite(rendered, (x, y))
        out.alpha_composite(target, (i*FRAME, 0))
    out.save(STAGE / (name+'.png'))
    return {'path': (STAGE / (name+'.png')).relative_to(ROOT).as_posix(),
            'frame_width': FRAME, 'frame_height': FRAME, 'frame_count': len(frames), 'loop': True}

idle = Image.open(SOURCE / 'directional-idle-source.png').convert('RGBA')
animations = {}
for col, direction in enumerate(DIRECTIONS):
    name='idle_'+direction
    animations[name]=dict(strip(name,[cell(idle,col,row,5,2) for row in range(2)]),
                          role='directional_idle',fps=.65)
    walk_file=({'north':'walk-north-repair-v4.png','east':'walk-east-guide-v3.png'}).get(direction,'walk-'+direction+'-source.png')
    walk=Image.open(SOURCE / walk_file).convert('RGBA')
    name='walk_'+direction
    # The front-view source puts each knee-up before the same foot's contact,
    # rather than before the opposite half. Swap only those two source poses.
    order=[0,1,2,7,4,5,6,3] if direction=='south' else [0,1,2,7,4,5,6,7] if direction=='east' else list(range(8))
    frames=[cell(walk,i%4,i//4,4,2) for i in order]
    if direction=='east':
        # v3 frame8 has the near knee forward and near arm back: right-up.
        # v4 frame8 instead has near support behind / far knee forward: left-up.
        # Preserve the six good v3 phases; no pixel-painting or duplicate phases.
        repair=Image.open(SOURCE / 'walk-east-guide-v4.png').convert('RGBA')
        frames[7]=cell(repair,3,1,4,2)
    animations[name]=dict(strip(name,frames), role='gait',
                          source_frame_order=[i+1 for i in order],source_file=walk_file)
    if direction=='east':
        animations[name]['source_frame_files']=[walk_file]*7+['walk-east-guide-v4.png']

mapping={d:{'walk_animation':'walk_'+d,'idle_animation':'idle_'+d,'mirror_x':False} for d in DIRECTIONS}
for opposite, authored in [('southwest','southeast'),('west','east'),('northwest','northeast')]:
    mapping[opposite]={'walk_animation':'walk_'+authored,'idle_animation':'idle_'+authored,'mirror_x':True}
spec={'version':1,'character':'shared-suited-critter','status':'staged_for_review',
      'animations':animations,'directions':mapping,
      'gait':{'pose_order':['left_contact','left_down','right_passing','right_up','right_contact','right_down','left_passing','left_up'],
              'pixels_per_frame':6.24,'base_speed':81.6,
              'speed_multipliers':[.96,.94,1.04,1.06,.96,.94,1.04,1.06],
              'acceleration_multipliers':[.92,.90,1.08,1.10,.92,.90,1.08,1.10]},
      'audit':{'alpha_threshold':16,'edge_margin':2,'detached_component_ratio':.003,'baseline_tolerance':3,'center_tolerance':14},
      'runtime':{'world_height_metres':1.35,'foot_anchor':[128,232],'metres_per_gait_frame':.13,
                 'mirror_rationale':'Shared suit is symmetric, without badges or side-specific accessories. Motorcycle is not mirrored.'},
      'sources':[{ 'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
                 for p in sorted(SOURCE.glob('*.png'))]}
(STAGE / 'motion.json').write_text(json.dumps(spec,indent=2)+'\n',encoding='utf-8')
print('Staged ten directional idle/walk strips and motion.json; runtime publication requires audit and visual review.')
