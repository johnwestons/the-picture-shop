"""Normalize reviewed ImageGen employee pushing and chair atlases without replacing old art."""
from pathlib import Path
import json
import hashlib
from PIL import Image, ImageDraw, ImageOps
import build_visitor_character_assets as visitor
from build_worker_action_assets import lua

ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / 'output/employee-motion-v2'
CHARACTERS = ('cat-worker', 'tinker-fox-worker', 'ferret-engineer-worker')
VIEWS = ('east', 'northeast', 'north', 'southeast', 'south')
SOUTH_PROMPT = ("Create a NEW narrow horizontal eight frame sprite strip for the exact {character} character in the reference. "
    "Eight equal-sized columns, ONE ROW ONLY. Transparent background. Exact same face, clothes, goggles/scarf, tail, chunky game sprite style as reference. "
    "ALL EIGHT DRAWINGS show the full-body STANDING character facing straight SOUTH toward the camera while WALKING and PUSHING a pallet jack handle. "
    "The jack is NOT drawn. Both hands reach FORWARD toward the camera at stomach level, gloves gripping an imaginary handle, elbows extended in front of body; "
    "hands are NOT resting on the thighs. Long standing legs support the body, NO SITTING, NO CHAIR, NO CROUCHED POSES. "
    "Draw real eight phase walk gait: left foot contact forward, left weight down, right foot passing, right knee lift, right foot contact forward, "
    "right weight down, left foot passing, left knee lift. Clearly different foot positions and alternating feet, shoulders stay level, planted foot at shared baseline. "
    "Keep body height and width identical across all eight frames. Plenty of transparent margin inside EACH cell. No text, no shadows, no props, no outline boxes. "
    "This is missing front-view pushing art used alongside the five-view reference sheet. Preserve identity exactly.")

def build():
    REVIEW.mkdir(parents=True, exist_ok=True)
    art = {'anchors': {}, 'metrics': {}, 'hands': {}}
    manifest = []
    manifest_path=ROOT / 'assets/source/employee-motion-v2/source-manifest.json'
    pinned={record['character']:record for record in json.loads(manifest_path.read_text())} if manifest_path.exists() else {}
    visitor.SIZE, visitor.HEIGHT, visitor.WIDTH, visitor.BASELINE = 256, 192, 232, 229
    for character in CHARACTERS:
        source = ROOT / 'assets/source/employee-motion-v2' / (character + '.png')
        atlas = Image.open(source).convert('RGBA')
        bands = {'cat-worker': [(0,182),(182,366),(366,547),(547,724),(724,906),(906,1086)],
                 'tinker-fox-worker':[(35,235),(235,435),(435,636),(636,837),(837,1046),(1046,1250)],
                 'ferret-engineer-worker':[(35,220),(220,425),(425,633),(633,833),(833,1045),(1045,1260)]}[character]
        cells = [atlas.crop((round(col * atlas.width / 8), bands[row][0],
                            round((col + 1) * atlas.width / 8), bands[row][1]))
                 for row in range(6) for col in range(8)]
        if character == 'ferret-engineer-worker':
            cells[24:32] = [ImageOps.mirror(cell) for cell in cells[24:32]]
        if character == 'tinker-fox-worker':
            # East cell 2 contains a detached glove fragment from its neighbor.
            # The complete worker is the other, much larger connected component.
            cells[1]=visitor.clean_export(cells[1],800)
        south_source=ROOT / 'assets/source/employee-motion-v2' / (character+'-south.png')
        source_digest=hashlib.sha256(source.read_bytes()).hexdigest()
        south_digest=hashlib.sha256(south_source.read_bytes()).hexdigest()
        approved=pinned.get(character)
        if approved and (approved['sha256']!=source_digest or approved.get('south_sha256',south_digest)!=south_digest):
            raise ValueError('Source differs from reviewed manifest: '+character)
        south=Image.open(south_source).convert('RGBA')
        south_cells=[visitor.clean_export(south.crop((round(i*south.width/8),0,
                     round((i+1)*south.width/8),south.height)),80) for i in range(8)]
        old_height=max(visitor.bounds(cell)[3]-visitor.bounds(cell)[1] for cell in cells[32:40])
        new_height=max(visitor.bounds(cell)[3]-visitor.bounds(cell)[1] for cell in south_cells)
        # The supplemental atlas has a different export resolution; resample the
        # entire loop once to the same source body size before packing all views.
        ratio=old_height/new_height
        cells[32:40]=[cell.resize((round(cell.width*ratio),round(cell.height*ratio)),Image.Resampling.LANCZOS)
                      for cell in south_cells]
        # A single scale across views and chair poses preserves body proportions.
        strip = visitor.pack(cells, cleanup_area=300)
        frames = [strip.crop((index*256, 0, (index+1)*256, 256)) for index in range(48)]
        runtime = ROOT / 'assets/generated/employee-motion-v2' / character
        runtime.mkdir(parents=True, exist_ok=True)
        for field in art: art[field][character] = {}
        spec = json.loads((ROOT / 'character-motion' / (character + '.json')).read_text())
        # Audit the staging specification before registering these runtime actions.
        staging_spec = dict(spec, animations=dict(spec['animations']))
        actions = [(('push' if view == 'east' else 'push_' + view), frames[row*8:row*8+8])
                   for row, view in enumerate(VIEWS)]
        actions += [('chair_east', frames[40:44]), ('chair_west', frames[44:48])]
        contact = Image.new('RGBA', (8*128, 7*148), (32, 39, 42, 255))
        draw = ImageDraw.Draw(contact)
        for row, (action, sequence) in enumerate(actions):
            out = Image.new('RGBA', (len(sequence)*256, 256))
            anchors, metrics, hands = [], [], []
            for i, frame in enumerate(sequence):
                out.alpha_composite(frame, (i*256, 0))
                box = visitor.bounds(frame)
                anchors.append({'x': round(visitor.body_axis(frame, box), 2), 'y': box[3]})
                metrics.append(list(box))
                view = 'east' if action == 'push' else action.removeprefix('push_')
                fractions = {'east': (.87,.52), 'northeast': (.82,.48), 'north': (.50,.48),
                             'southeast': (.80,.57), 'south': (.50,.60)}
                hx, hy = fractions.get(view, (.5,.5))
                hands.append({'x': round(box[0]+(box[2]-box[0])*hx, 2),
                              'y': round(box[1]+(box[3]-box[1])*hy, 2)})
                contact.alpha_composite(frame.resize((128,128)), (i*128, row*148+20))
            draw.text((4, row*148+3), action, fill=(243,218,136))
            path = runtime / (action + '.png')
            out.save(path, optimize=True)
            art['anchors'][character][action] = anchors
            art['metrics'][character][action] = metrics
            art['hands'][character][action] = hands
            definition = {'path':path.relative_to(ROOT).as_posix(), 'frame_width':256,
                          'frame_height':256, 'frame_count':len(sequence), 'loop':action.startswith('push'),
                          'role':'gait' if action.startswith('push') else 'seated',
                          'fps':11.2 if action.startswith('push') else .65}
            spec['animations'][action] = definition
            staging_spec['animations'][action] = definition
            sequence[0].save(REVIEW / (character+'-'+action+'.gif'), save_all=True,
                             append_images=sequence[1:], duration=89 if action.startswith('push') else 700,
                             loop=0, disposal=2)
        spec['employee_transport'] = {'pixels_per_frame':10, 'phases':8,
            'base_speed':112,'loaded_speed':82,
            'directions':'authored5_mirrored8', 'standing_height':192,
            'stationary_frame':2, 'chair_actions':['chair_east','chair_west'],
            'chair_frames':{'entry':1,'rest':2,'blink':3,'exit':4}}
        spec.get('worker_action_contract', {}).pop('future_pallet_jack_action', None)
        (ROOT / 'character-motion' / (character+'.json')).write_text(json.dumps(spec,indent=2)+'\n')
        (REVIEW / (character+'-spec.json')).write_text(json.dumps(staging_spec,indent=2)+'\n')
        contact.save(REVIEW / (character+'-contact.png'))
        manifest.append({'character':character,'source':source.relative_to(ROOT).as_posix(),
                         'sha256':source_digest,'south_source':south_source.relative_to(ROOT).as_posix(),
                         'south_sha256':south_digest,'row_bands':bands,
                         'layout':{'columns':8,'rows':6},'generator':'built-in image_gen'})
    (ROOT / 'src/employee_motion_art.lua').write_text('-- Generated by tools/build_employee_motion_v2.py\nreturn '+lua(art)+'\n')
    manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
    prompts_path=manifest_path.with_name('prompts.json')
    prompts=json.loads(prompts_path.read_text())
    prompts['south_corrections']={character:SOUTH_PROMPT.format(character=character) for character in CHARACTERS}
    prompts_path.write_text(json.dumps(prompts,indent=2)+'\n')
    print('Built 21 employee motion strips; previews in '+str(REVIEW))

if __name__ == '__main__': build()
