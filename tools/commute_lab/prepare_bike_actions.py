"""Prepare exact-view edit references and a resumable action-art job manifest."""
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/source/commute-bike-actions-v1'
UPRIGHT=ROOT/'assets/commute/bike/mounted-upright-64-v2.png'
ACTIONS={
    'boost':{'title':'acceleration response','states':['boostMid','boost'],
        'pose':'The rider responds to strong acceleration: hips stay on the SAME saddle, knees grip the tank, elbows bend and the upper torso inclines slightly FORWARD to brace against the pull. Mild stage has a small 5-degree torso inclination; full stage has a clear 12-degree forward torso inclination with helmet a little lower and forward. Both hands hold the SAME handlebars and both boots stay on their SAME pegs. No wheelie or moving wheels.'},
    'brake':{'title':'hard-braking brace','states':['brakeMid','brake'],
        'pose':'The rider braces against HARD BRAKING: hips shift subtly BACK on the SAME saddle, knees grip the tank, arms straighten slightly but remain bent and hands stay on the SAME grips. Mild stage begins this brace; full stage has a clear rearward weight shift, torso more upright/back and shoulders behind their neutral position. Both boots remain on their SAME pegs. Do not confuse this with a forward acceleration tuck; no stoppie or lifted wheel.'},
    'turnLeft':{'title':'left cornering body lean','states':['turnLeftMid','turnLeft'],
        'pose':'The rider shifts weight and leans toward the PHYSICAL LEFT side of the bike, the rider own left, not viewer left. Mild stage: torso and helmet shift gently left with slight elbow asymmetry; full stage: torso and head clearly shift LEFT over the left side of the saddle and the left knee opens slightly for cornering. Hips stay seated, both hands stay on the same grips and both boots remain on pegs. Keep both wheel contact points and the chassis level in the image; runtime banks the entire rig continuously. No turning handlebars or changing yaw. Left lean is independent authored anatomy, never mirrored right lean.'},
    'turnRight':{'title':'right cornering body lean','states':['turnRightMid','turnRight'],
        'pose':'The rider shifts weight and leans toward the PHYSICAL RIGHT side of the bike, the rider own right, not viewer right. Mild stage: torso and helmet shift gently right with slight elbow asymmetry; full stage: torso and head clearly shift RIGHT over the right side of the saddle and the right knee opens slightly for cornering. Hips stay seated, both hands stay on the same grips and both boots remain on pegs. Keep both wheel contact points and the chassis level in the image; runtime banks the entire rig continuously. No turning handlebars or changing yaw. Right lean is independent authored anatomy, never mirrored left lean.'},
    'aero':{'title':'aerodynamic tuck','states':['aeroMid','aero'],
        'pose':'The rider folds into an aerodynamic TUCK over the tank, while hips stay on the SAME saddle, knees grip the tank, hands hold their SAME handlebar grips and boots stay on their SAME pegs. Mild stage: torso inclines 15 degrees forward and helmet lowers; full stage: torso inclines 30 degrees forward and helmet is lower/forward, with elbows tucked in. This is a moderate plausible touring-bike tuck, not a racing crouch with head touching the tank. Motorcycle and wheel contact points remain unchanged.'},
    'shift':{'title':'left-foot gear-shift gesture','states':['shiftMid','shift'],
        'pose':'The rider makes a subtle physical LEFT-FOOT gear-shift gesture. Upper body stays almost exactly in the approved upright seated riding posture, same hands on grips and right foot on its peg. Mild stage: left ankle prepares and the toe rises slightly toward the gear lever. Full stage: LEFT boot toe clearly lifts a small amount at the lever, left ankle flexes and left knee bends subtly while heel remains near the peg. The action is visible on the LEFT side views, naturally occluded on right-side views; do not swap the gesture to the right foot to make it visible. No whole-body leaning or changing bike geometry.'},
    'impact':{'title':'collision impact brace','states':['impactMid','impact'],
        'pose':'The rider briefly compresses FORWARD into an IMPACT BRACE: hips stay seated on the SAME saddle, knees grip the tank, shoulders hunch, elbows fold more sharply and helmet lowers toward the handlebar area. Mild stage: gentle start of compression. Full stage: clear compact protective crouch, forward and down a little more than the acceleration pose, while both hands stay on their same grips and both boots stay on the same pegs. No ejection, crash damage, extra limbs, wheel motion or deformation of the motorcycle.'}
}

def main():
    SOURCE.mkdir(parents=True,exist_ok=True)
    im=Image.open(UPRIGHT).convert('RGBA')
    for block in range(8):
        template=Image.new('RGBA',(1280,1280))
        for phase in range(2):
            for local in range(8):
                i=block*8+local
                tile=im.crop((i%8*320,i//8*320,(i%8+1)*320,(i//8+1)*320))
                # Enlarge the whole approved rig uniformly in the generation
                # reference to use more source pixels, preserving handedness.
                larger=tile.resize((384,384),Image.Resampling.LANCZOS)
                framed=Image.new('RGBA',(320,320));framed.alpha_composite(larger,(-32,-39))
                template.alpha_composite(framed,(local%4*320,(phase*2+local//4)*320))
        template.save(SOURCE/f'views-{block:02}-paired-template.png')
    jobs=[]
    for name,action in ACTIONS.items():
        for block in range(8):
            jobs.append({'id':f'{name}-{block:02}','action':name,'block':block,
                'template':f'assets/source/commute-bike-actions-v1/views-{block:02}-paired-template.png',
                'source':f'assets/source/commute-bike-actions-v1/{name}-{block:02}-source.png',
                'columns':4,'rows':4,'states':action['states'],'views':list(range(block*8,block*8+8)),
                'status':'pending'})
    spec={'version':1,'approvedUpright':UPRIGHT.relative_to(ROOT).as_posix(),
        'approvedUprightSha256':hashlib.sha256(UPRIGHT.read_bytes()).hexdigest(),
        'frameCount':64,'frameSize':320,'anchor':[160,260],
        'sourceLayout':'4 columns by4 rows; upper8 cells midpoint, lower8 cells full; same8 consecutive directions repeated',
        'actions':ACTIONS,'jobs':jobs}
    (SOURCE/'production.json').write_text(json.dumps(spec,indent=2)+'\n')
    print(f'{len(ACTIONS)} actions / {len(jobs)} paired-sheet jobs / {len(jobs)*16} authored cells')

if __name__=='__main__':main()
