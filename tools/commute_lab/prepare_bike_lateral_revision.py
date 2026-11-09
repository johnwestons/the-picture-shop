"""Remove ambiguous viewer-left phrasing from the authored coronal lean poses."""
import json
import math
from prepare_bike_actions import ROOT,SOURCE
from prepare_bike_action_prompts import FACINGS

def main():
    path=SOURCE/'production.json';spec=json.loads(path.read_text())
    for job in spec['jobs']:
        if job['action'] not in ['turnLeft','turnRight']:continue
        side='LEFT' if job['action']=='turnLeft' else 'RIGHT';sign=-1 if side=='LEFT' else 1
        offsets=[round(sign*.45*math.cos(v*math.tau/64),3) for v in job['views']]
        mild=[round(v*.2/.45,3) for v in offsets]
        prompt=(
            'Use case: precise-object-edit. Edit Image1, the exact approved4-column by4-row motorcycle/rider template, '
            'into TWO stages of a PURE SIDEWAYS BODY LEAN toward the rider physical '+side+'. '
            'Image2 fixes identity, proportions and materials. Keep all sixteen cells in their EXACT existing yaw angles and row-major positions. '
            'Upper2rows: same8directions, MILD lean. Lower2rows: same8directions repeated, FULL lean. '
            'This template covers only '+FACINGS[job['block']]+'. It is NOT a full turnaround.\n'
            'Critical physical direction: this is a CORONAL SIDEWAYS lean, not a forward tuck, acceleration hunch, looking sideways or bending only the neck. '
            'Torso, shoulders, neck and helmet lean together into the turn while hips remain on the same saddle. '
            'Do NOT move the rider forward or backward along the bike. In true profile views the sideways motion goes into/out of the camera plane, '
            'so the helmet stays at the SAME horizontal location as its upright reference. In REAR view the rider LEFT is screen LEFT; '
            'in FRONT view the rider LEFT is screen RIGHT. The rider RIGHT is the opposite.\n'
            'Precise projection guide: for each of the eight corresponding views in Image1, move the helmet CENTRE horizontally relative to '
            'that SAME cell upright helmet centre by the following fractions of the unchanged helmet diameter D. '
            'Negative means SCREEN LEFT, positive means SCREEN RIGHT, zero means no horizontal movement. '
            f'Upper8 cells MILD offsets: {mild}. Lower8 cells FULL offsets: {offsets}. '
            'These offsets are deliberately small, about a quarter of a helmet width for mild and half a helmet width for full at end-on angles. '
            'Articulate the entire upper body naturally to make those positions plausible; do not just translate a disconnected head or rotate the head on the neck. '
            'The inside knee opens slightly on physical '+side+', while both hands stay on the SAME grips and both boots stay on the SAME pegs.\n'
            'Keep the MOTORCYCLE UNCHANGED: wheel positions, tire size, wheelbase, chassis, saddle, lights, bars, mirrors, rack, chain and exhaust geometry '
            'match each corresponding original cell exactly. Chassis and wheels stay level; runtime applies the bank to the whole rig. '
            'No yaw or steering change, wheel motion, mirrored parts, forward crouch, neck-only tilt or motorcycle rotation. '
            'Same slim brown padded-leather rider, round bronze helmet/black visor, olive-bronze dual-sport bike, same helmet diameter and physical body dimensions. '
            'Preserve the established rich fine hand-painted game-sprite detail and palette. Fixed orthographic camera, light and scale in every cell.\n'
            'Output exactly16 complete crisp sprites,4columns by4rows, square high-resolution PNG with TRUE transparency, clear empty gutters and safe margins. '
            'No haze, matte, halo, colored fringe, loose pixels, background, shadows, text or grid. Both stages must clearly lean toward the correct PHYSICAL '
            +side+' side and remain matched in size.')
        job.setdefault('previousSource',job['source'])
        job['source']=f"assets/source/commute-bike-actions-v1/{job['id']}-lateral-v2-source.png"
        job['promptPath']=f"assets/source/commute-bike-actions-v1/{job['id']}-lateral-v2.prompt.txt"
        job['references']=[job['template'],'assets/source/commute-bike-turning-v3/identity-transparent.png']
        job['status']='pending_lateral_revision'
        job['refinement']='Explicit camera projection of physical lateral lean, with invariant fore/aft rider position.'
        (ROOT/job['promptPath']).write_text(prompt+'\n')
    path.write_text(json.dumps(spec,indent=2)+'\n')
    print('Sixteen lean-sheet revisions prepared; original source drafts preserved')

if __name__=='__main__':main()
