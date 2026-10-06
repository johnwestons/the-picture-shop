"""Reuse Mouse Frontier's reviewed strips; source masters stay byte-for-byte.

Locomotion comes from its complete eight-phase motion specifications, rather
than its older four-frame Fox export. Existing hand and seated gestures come
from that project's character animation directory. No poses are synthesized.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
from PIL import Image
from build_visitor_character_assets import bounds, body_axis

ROOT=Path(__file__).resolve().parents[1]
CHARACTERS={'tinker-fox':'tinker-fox-worker','ferret-engineer':'ferret-engineer-worker'}

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def lua(value):
    if isinstance(value,dict): return '{ '+', '.join(f'[{json.dumps(k)}] = {lua(v)}' for k,v in value.items())+' }'
    if isinstance(value,list): return '{ '+', '.join(lua(v) for v in value)+' }'
    return str(value)

def build(mouse):
    source=ROOT/'assets/source/mouse-frontier-workers'
    source.mkdir(parents=True,exist_ok=True)
    records=[];anchors={};metrics={}
    for origin,character in CHARACTERS.items():
        spec=json.loads((mouse/f'character-motion/{origin}.json').read_text(encoding='utf-8'))
        target=ROOT/'assets/generated/characters'/character
        target.mkdir(parents=True,exist_ok=True)
        staged=source/origin;staged.mkdir(parents=True,exist_ok=True)
        strips={};runtime_spec=json.loads(json.dumps(spec));runtime_spec['character']=character
        runtime_spec['animations']={}
        for key,definition in spec['animations'].items():
            action=Path(definition['path']).stem
            strips[action]=(mouse/definition['path'],definition['frame_count'],definition['role'])
        # Fox's empty-hand reach is used for cutter controls; Ferret's existing
        # tool-use gesture fits his engineer role. Keep combat out of game rules.
        strips['operate']=(mouse/f'assets/sprites/character-animations/{origin}'/('melee.png' if origin=='tinker-fox' else 'use.png'),3,'action')
        strips['rest']=(mouse/f'assets/sprites/character-animations/{origin}/sit.png',2,'action')
        anchors[character]={};metrics[character]={}
        for action,(original,count,role) in strips.items():
            master=staged/f'{action}.png'
            if master.exists() and master.read_bytes()!=original.read_bytes():
                raise ValueError(f'Existing source master changed: {master}')
            if not master.exists(): shutil.copyfile(original,master)
            image=Image.open(master).convert('RGBA')
            assert image.size==(512*count,512),(original,image.size,count)
            source_count=count
            # Legacy work/rest strips repeat one approved pose. Export that
            # pose once; repeated cells must not masquerade as new animation.
            if role=='action' and all(image.crop((i*512,0,(i+1)*512,512)).tobytes()==image.crop((0,0,512,512)).tobytes() for i in range(count)):
                image=image.crop((0,0,512,512));count=1
            output=image.resize((256*count,256),Image.Resampling.LANCZOS)
            path=target/f'{action}.png';output.save(path,optimize=True)
            a=[];m=[]
            for index in range(count):
                frame=output.crop((256*index,0,256*(index+1),256))
                box=bounds(frame);a.append({'x':round(body_axis(frame,box),2),'y':box[3]});m.append(list(box))
            anchors[character][action]=a;metrics[character][action]=m
            key=action+'_east' if action in ('idle','walk') else action
            runtime_spec['animations'][key]={'path':path.relative_to(ROOT).as_posix(),'frame_width':256,'frame_height':256,
                'frame_count':count,'loop':True,'role':role,'fps':.65 if role=='directional_idle' else 72/13}
            records.append({'character':character,'action':action,'origin_project':'Mouse Frontier 8.10',
                'origin':original.relative_to(mouse).as_posix(),'source':master.relative_to(ROOT).as_posix(),
                'source_sha256':digest(master),'runtime':path.relative_to(ROOT).as_posix(),
                'runtime_sha256':digest(path),'frames':count,'source_frames':source_count})
        runtime_spec['gait']['pixels_per_frame']=13;runtime_spec['gait']['base_speed']=72
        runtime_spec['audit'].update(baseline_tolerance=6,center_tolerance=14)
        runtime_spec['source_project']='Mouse Frontier 8.10'
        runtime_spec['work_actions']={'operate':'Original empty-hand reach' if origin=='tinker-fox' else 'Original tool-use gesture',
            'rest':'Original seated animation'}
        (ROOT/f'character-motion/{character}.json').write_text(json.dumps(runtime_spec,indent=2)+'\n',encoding='utf-8')
    # Confirm Radio Cat's current masters really are the complete Mouse pack.
    for master in sorted((ROOT/'assets/source/cat-worker-v1/locomotion').glob('*.png')):
        original=mouse/'output/character-motion/radio-cat/runtime'/master.name
        assert master.read_bytes()==original.read_bytes(),f'Radio Cat source mismatch: {master}'
        records.append({'character':'cat-worker','action':master.stem,'origin_project':'Mouse Frontier 8.10',
            'origin':original.relative_to(mouse).as_posix(),'source':master.relative_to(ROOT).as_posix(),
            'source_sha256':digest(master),'runtime':f'assets/generated/characters/cat-worker/{master.name}',
            'runtime_sha256':digest(ROOT/f'assets/generated/characters/cat-worker/{master.name}')})
    for filename,data in [('mouse_worker_anchors.lua',anchors),('mouse_worker_metrics.lua',metrics)]:
        (ROOT/'src'/filename).write_text('-- Generated by tools/import_mouse_frontier_workers.py.\nreturn '+lua(data)+'\n',encoding='utf-8')
    (source/'source-manifest.json').write_text(json.dumps({'version':1,'sources':records},indent=2)+'\n',encoding='utf-8')
    print(f'Reused {len(records)} verified Mouse Frontier strips, including Radio Cat.')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--mouse-project',type=Path,required=True)
    build(parser.parse_args().mouse_project.resolve())
