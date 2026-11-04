"""Persist exact built-in ImageGen edit prompts; schedule pose studies first."""
import json
from pathlib import Path
from prepare_bike_actions import ROOT,SOURCE

PILOTS={'boost':2,'brake':2,'turnLeft':0,'turnRight':0,'aero':2,'shift':6,'impact':2}
FACINGS=[
    'REAR through REAR-RIGHT; backs and tail lights remain visible in all eight cells, never the front/chest',
    'REAR-RIGHT through nearly RIGHT PROFILE; still the rear hemisphere, not front views',
    'RIGHT PROFILE through FRONT-RIGHT; chest/front become gradually more visible, never back views',
    'FRONT-RIGHT through nearly straight FRONT; chest and headlamp face toward camera',
    'straight FRONT through FRONT-LEFT; chest and headlamp visible, no backs',
    'FRONT-LEFT through nearly LEFT PROFILE; never back views',
    'LEFT PROFILE through REAR-LEFT; backs become gradually more visible, never right-side views',
    'REAR-LEFT through nearly straight REAR; backs and tail lights visible, never fronts']

def main():
    spec=json.loads((SOURCE/'production.json').read_text())
    for job in spec['jobs']:
        action=spec['actions'][job['action']];block=job['block']
        pilot=PILOTS[job['action']];job['pilot']=block==pilot
        refs=[job['template'],'assets/source/commute-bike-turning-v3/identity-transparent.png']
        guide=''
        if not job['pilot']:
            refs.append(f"assets/source/commute-bike-actions-v1/{job['action']}-{pilot:02}-source.png")
            guide=' Image3 is the reviewed ACTION POSE/QUALITY guide from a different angle group: match its mild/full articulation and invariant physical proportions, but NEVER copy its yaw angles; Image1 alone fixes all sixteen specific views.'
        prompt=(
            'Use case: precise-object-edit. Production asset: high-quality hand-painted motorcycle-rider action sprite atlas.\n'
            'Image1 is the EDIT TARGET: an approved4-column by4-row sprite template, sixteen complete sprites. '
            'Image2 is an identity/material reference ONLY.'+guide+'\n'
            f"Edit the rider pose in every cell of Image1 for {action['title'].upper()}. "
            'Keep exactly sixteen sprites in exactly the same4x4 layout. Upper two rows are eight consecutive directions in the MILD/MIDPOINT stage; '
            'lower two rows repeat those EXACT SAME eight directions in the FULL stage. Read row-major within each half. '
            f"Preserve EACH cell specific yaw angle from Image1: only {FACINGS[block]}, eight tiny yaw increments covering about40degrees, NOT a generic full turnaround. "
            'Corresponding upper/lower cells have identical views and identical motorcycles.\n'+action['pose']+'\n'
            'Keep the approved slim rider identity, SAME unchanged round helmet diameter, SAME torso and limb dimensions, brown padded leather suit, '
            'bronze helmet with black visor, olive-bronze dual-sport motorcycle, rack, exhaust and chain on their true physical sides. '
            'Preserve MOTORCYCLE geometry exactly: wheel centres, tire diameter, wheelbase, chassis, saddle, lights, mirrors and handlebars stay the same. '
            'No yaw/perspective change, steering, deformation or wheel motion. Only physically plausible rider articulation changes. '
            'Preserve the fine painted texture and warm bronze/olive/brown palette, with crisp fine detail. Fixed orthographic camera, lighting and model scale. '
            'Critical: helmet and wheels never grow or shrink between cells or action stages.\n'
            'Output high-resolution square PNG, ideally2048x2048, exactly4 columns by4 rows, one complete cutout per cell. '
            'Use cell area generously like Image1 while leaving clear empty gutters and safe edges. TRUE transparent background, clean antialiased edges, '
            'no matte, haze, halos, colored fringe, detached specks, shadows, scenery, text or grid lines. '
            'Do not copy the same upright pose sixteen times: upper two rows show the mild action and lower two rows its visibly stronger full action. '
            'Never mirror physical sides; natural occlusion is correct.')
        path=SOURCE/(job['id']+'.prompt.txt')
        if not path.exists():path.write_text(prompt+'\n')
        job['promptPath']=path.relative_to(ROOT).as_posix();job['references']=refs
    (SOURCE/'production.json').write_text(json.dumps(spec,indent=2)+'\n')
    print('56 exact prompts and reference lists saved; seven pose studies scheduled first')

if __name__=='__main__':main()
