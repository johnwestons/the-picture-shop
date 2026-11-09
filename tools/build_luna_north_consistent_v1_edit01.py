from __future__ import annotations
import hashlib, json, sys
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont
from statistics import median

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import build_luna_north_consistent_v1 as base
SRC = ROOT / 'assets/source/animation-overhaul-luna-player-v1/consistent-north-v1'
OUT = ROOT / 'output/animation-overhaul/luna-player/consistent-north-v1'
ORIGINAL_RAW = SRC / 'north-consistent-v1-generated.png'
EDIT_RAW = SRC / 'north-consistent-v1-edit-trial-01-generated.png'
PROMPT = SRC / 'north-consistent-v1-edit-trial-01-exact-prompt.txt'
ROLE_REF = SRC / 'north-consistent-v1-k3-lowerbody-role-ref.png'
ORIGINAL_NATIVE = OUT / 'north-consistent-v1-full8-native.png'
AUDIT_V1 = OUT / 'north-consistent-v1-phase-owner-body-width-audit.json'
EDIT_NATIVE = OUT / 'north-consistent-v1-edit-trial-01-full8-native.png'
EDIT_CONTACT = OUT / 'north-consistent-v1-edit-trial-01-after-contact.png'
PAIRED = OUT / 'north-consistent-v1-edit-trial-01-before-after-contact.png'
K7_PAIR = OUT / 'north-consistent-v1-edit-trial-01-phase7-before-after.png'
EDIT_GIF = OUT / 'north-consistent-v1-edit-trial-01-64worldpx-timed.gif'
AUDIT = OUT / 'north-consistent-v1-edit-trial-01-comparison-audit.json'
EXPECTED_ORIGINAL_HASH = '55a59f161f064b1f22f9f90859a34526c80b64aaa6a54362dda16a3167ef7573'
EXPECTED_EDIT_HASH = '0b7c679af195fb8b86d376a7afe3d789b7066d2a51007dc3e7f9754f70754be3'
FRAME = 512
COL = [0,443,887,1330,1774]
ROW = [0,443,887]


def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def make_frames(raw_path, transforms):
    im=Image.open(raw_path).convert('RGBA')
    frames=[]
    for i in range(8):
        r,c=divmod(i,4)
        tile=im.crop((COL[c],ROW[r],COL[c+1],ROW[r+1]))
        tr=transforms[i]
        cell=Image.new('RGBA',(FRAME,FRAME),(0,0,0,0))
        cell.alpha_composite(tile, tuple(tr['translation_xy_px']))
        frames.append(cell)
    return frames

def strip_from(frames):
    out=Image.new('RGBA',(FRAME*8,FRAME),(0,0,0,0))
    for i,f in enumerate(frames):out.alpha_composite(f,(i*FRAME,0))
    return out

def contact_from(frames):
    out=Image.new('RGBA',(FRAME*4,FRAME*2),(0,0,0,0))
    for i,f in enumerate(frames):
        r,c=divmod(i,4);out.alpha_composite(f,(c*FRAME,r*FRAME))
    return out

def save_gif(frames,path):
    gs=[]
    for f in frames:
        small=f.resize((64,64),Image.Resampling.LANCZOS).convert('RGBA')
        alpha=small.getchannel('A');idx=small.convert('RGB').quantize(colors=255,method=Image.Quantize.MEDIANCUT)
        p=idx.load();ap=alpha.load()
        for y in range(64):
            for x in range(64):
                if ap[x,y]<=96:p[x,y]=255
        palette=idx.getpalette() or [];palette.extend([0]*(768-len(palette)))
        idx.putpalette(palette[:768]);gs.append(idx)
    gs[0].save(path,save_all=True,append_images=gs[1:],duration=130,loop=0,transparency=255,disposal=2,optimize=False)

def diff_summary(before,after):
    d=ImageChops.difference(before,after)
    rgb=d.convert('RGB'); pix=rgb.load(); n=0
    for y in range(FRAME):
        for x in range(FRAME):
            if pix[x,y] != (0,0,0):n+=1
    bbox=rgb.getbbox()
    ba=before.getchannel('A').point(lambda v:255 if v>16 else 0)
    aa=after.getchannel('A').point(lambda v:255 if v>16 else 0)
    da=ImageChops.difference(ba,aa)
    return {'changed_rgba_pixels':n,'changed_rgba_percent_of_cell':round(n/(FRAME*FRAME)*100,2),'difference_bbox':bbox,'alpha_occupancy_changed_pixels':sum(1 for v in da.getdata() if v>0)}

def main():
    if sha(ORIGINAL_RAW)!=EXPECTED_ORIGINAL_HASH:raise SystemExit('Original source changed; refusing comparison.')
    if sha(EDIT_RAW)!=EXPECTED_EDIT_HASH:raise SystemExit('Edit source hash changed; refusing comparison.')
    if Image.open(ORIGINAL_RAW).size!=(1774,887) or Image.open(EDIT_RAW).size!=(1774,887):raise SystemExit('Unexpected 4x2 sheet dimensions.')
    previous=json.loads(AUDIT_V1.read_text(encoding='utf-8'))
    transforms=previous['processing']['phase_transforms']
    before=make_frames(ORIGINAL_RAW,transforms)
    after=make_frames(EDIT_RAW,transforms)
    strip_from(after).save(EDIT_NATIVE)
    contact_from(after).save(EDIT_CONTACT)
    # 4 columns x 4 rows: old phases 1-4, old 5-8, edited 1-4, edited 5-8.
    paired=Image.new('RGBA',(FRAME*4,FRAME*4+64),(0,0,0,0))
    draw=ImageDraw.Draw(paired)
    draw.text((8,4),'BEFORE: phases 1-4',fill=(220,220,220,255))
    draw.text((8,FRAME+20),'BEFORE: phases 5-8',fill=(220,220,220,255))
    draw.text((8,FRAME*2+36),'EDIT: phases 1-4',fill=(220,220,220,255))
    draw.text((8,FRAME*3+52),'EDIT: phases 5-8',fill=(220,220,220,255))
    # Use 16 px header bands and 512 px cells, with no scaling.
    paired=Image.new('RGBA',(FRAME*4,FRAME*4+64),(0,0,0,255))
    draw=ImageDraw.Draw(paired)
    for row,label,fs in [(0,'BEFORE · phases 1–4',before[:4]),(1,'BEFORE · phases 5–8',before[4:]),(2,'EDIT · phases 1–4',after[:4]),(3,'EDIT · phases 5–8',after[4:])]:
        y=row*(FRAME+16)
        draw.text((8,y),label,fill=(230,230,230,255))
        for c,f in enumerate(fs):paired.alpha_composite(f,(c*FRAME,y+16))
    paired.save(PAIRED)
    # Phase 7 before/after lower-body detail at original pixel scale.
    before7=before[6].crop((155,270,370,466))
    after7=after[6].crop((155,270,370,466))
    k7=Image.new('RGBA',(430,196),(0,0,0,255));k7.alpha_composite(before7,(0,0));k7.alpha_composite(after7,(215,0));k7.save(K7_PAIR)
    save_gif(after,EDIT_GIF)
    phase_diffs=[diff_summary(before[i],after[i]) for i in range(8)]
    before_metrics=[base.measure(f) for f in before]
    after_metrics=[base.measure(f) for f in after]
    before_head=[m['orange_head_band_y170_249_max_row_width_px']['width'] for m in before_metrics]
    after_head=[m['orange_head_band_y170_249_max_row_width_px']['width'] for m in after_metrics]
    before_torso=[m['blue_overall_band_y245_334_max_row_width_px']['width'] for m in before_metrics]
    after_torso=[m['blue_overall_band_y245_334_max_row_width_px']['width'] for m in after_metrics]
    before_height=[m['visible_height_px'] for m in before_metrics]
    after_height=[m['visible_height_px'] for m in after_metrics]
    red_before=sum(m['bright_red_pixels_outside_expected_tool_roi'] for m in before_metrics)
    red_after=sum(m['bright_red_pixels_outside_expected_tool_roi'] for m in after_metrics)
    sole_before=base.dark_roi_measure(before[6],(195,410,255,466))
    sole_after=base.dark_roi_measure(after[6],(195,410,255,466))
    gif=Image.open(EDIT_GIF); durations=[]
    for i in range(gif.n_frames):gif.seek(i);durations.append(gif.info.get('duration'))
    role_ref_bbox=base.bbox16(Image.open(ROLE_REF).convert('RGBA'))
    audit={
      'title':'North rabbit-worker edit trial 01; staged comparison only, not runtime-approved',
      'generation':{'tool':'built-in image_gen edit','generation_id':'exec-e816e81f-e41e-40f0-a812-3f7de6a586d6','cached_output_path':r'C:\Users\johnw\.codex\generated_images\01a17bec-a216-72b3-ac73-5e56d3da1c90\exec-e816e81f-e41e-40f0-a812-3f7de6a586d6.png'},
      'provenance':{
        'original_raw_path':str(ORIGINAL_RAW.relative_to(ROOT)),'original_raw_sha256':sha(ORIGINAL_RAW),
        'edited_raw_path':str(EDIT_RAW.relative_to(ROOT)),'edited_raw_sha256':sha(EDIT_RAW),'edited_raw_dimensions_px':list(Image.open(EDIT_RAW).size),
        'exact_prompt_path':str(PROMPT.relative_to(ROOT)),'exact_prompt_sha256':sha(PROMPT),
        'primary_edit_target_role':'original full 4x2 master: sole identity, style, camera, grid and scale reference',
        'primary_edit_target_path':str(ORIGINAL_RAW.relative_to(ROOT)),
        'phase3_lowerbody_role_reference':str(ROLE_REF.relative_to(ROOT)),'phase3_lowerbody_role_reference_sha256':sha(ROLE_REF),'phase3_lowerbody_role_reference_alpha_bbox':role_ref_bbox,
        'pose_reference_role':'unannotated lower-body crop of new phase 3 only; opposite-owner passing amplitude/sole presentation, not mirrored; no upper-body style role',
        'generation_raw_sha256_pinned':EXPECTED_EDIT_HASH,
      },
      'comparison_processing':{
        'cell_order':'4 columns x 2 rows, row-major; identical original grid and translations reused for before and after',
        'grid_x_bounds':COL,'grid_y_bounds':ROW,'uniform_scale':1.0,
        'registration':'fixed per-phase translations from original v1 master to maintain direct before/after comparison; no resize, warp, compositing or retiming',
        'timed_gif':{'frame_count':gif.n_frames,'frame_size_px':list(gif.size),'durations_ms':durations},
      },
      'body_width_and_bounds_before':[{'phase':i+1,**before_metrics[i]} for i in range(8)],
      'body_width_and_bounds_after':[{'phase':i+1,**after_metrics[i]} for i in range(8)],
      'aggregate_body_comparison':{
        'head_width_median_px_before_after':[median(before_head),median(after_head)],
        'torso_width_median_px_before_after':[median(before_torso),median(after_torso)],
        'visible_height_median_px_before_after':[median(before_height),median(after_height)],
        'mean_changed_pixels_percent_across_all_cells':round(sum(d['changed_rgba_percent_of_cell'] for d in phase_diffs)/8,2),
        'changed_pixels_percent_range':[
          min(d['changed_rgba_percent_of_cell'] for d in phase_diffs),
          max(d['changed_rgba_percent_of_cell'] for d in phase_diffs),
        ],
      },
      'per_phase_change_summary':[{'phase':i+1,**phase_diffs[i]} for i in range(8)],
      'phase_owner_audit':[
       {'phase':1,'owner':'left contact/right trailing low sole','after':'contact owner still reads; pose visibly redrawn slightly'},
       {'phase':2,'owner':'left weight-down/right heel release','after':'both feet remain near-neutral; subtle load/release still underplayed'},
       {'phase':3,'owner':'right compact pass/left support','after':'right pass still reads compact; comparison-role phase'},
       {'phase':4,'owner':'right knee-up recovery/left support','after':'knee-up remains distinct'},
       {'phase':5,'owner':'right contact/left trailing low sole','after':'contact owner remains; pose visibly redrawn slightly'},
       {'phase':6,'owner':'right weight-down/left heel release','after':'both feet remain near-neutral; subtle load/release still underplayed'},
       {'phase':7,'owner':'left compact low pass/right support','after':'free left boot is more flexed/lifted but still reads as recovery with a visible broad sole; not a confirmed low pass'},
       {'phase':8,'owner':'left knee-up recovery/right support','after':'knee-up remains distinct'},
      ],
      'fringe_review':{
        'before_bright_red_pixel_counts_outside_tool_roi':[m['bright_red_pixels_outside_expected_tool_roi'] for m in before_metrics],
        'after_bright_red_pixel_counts_outside_tool_roi':[m['bright_red_pixels_outside_expected_tool_roi'] for m in after_metrics],
        'total_before':red_before,'total_after':red_after,'total_percent_change':round((red_after/red_before-1)*100,2),
        'finding':'The edit did not remove the bright-red fringe. It remains visually obvious around most outlines and ear tips in every phase.'
      },
      'phase7_sole_proxy_same_roi_before_after':{
        'method':'alpha>64 and all RGB channels <80 in fixed screen-left boot ROI [195,410,255,466]; rough proxy only',
        'before':sole_before,'after':sole_after,
        'finding':'The dark region is smaller/narrower after the edit, but a substantial visible face remains and the foot is raised like recovery rather than a low pass.'
      },
      'anatomy_review':{'visible_ears':'two per phase by visual review','arms_legs_boots':'two each per phase by visual review','pouch_tools':'right-side pouch with actual red and yellow tools remains visible','alpha':'both raw sheets have real alpha range 0..255; fringe is opaque/semopaque colored pixels, not a background matte'},
      'visual_findings':{
        'phase7_still_broad':'The dark sole face is narrower than before by the fixed-ROI proxy, but it remains visibly broad enough that this is not a clean narrow-edge pass; more decisively, the foot still reads as raised recovery rather than a low compact pass.',
        'changes_outside_phase7':'ImageGen redrew parts of all eight cells; per-phase changed-pixel and alpha-occupancy counts are listed. The other seven remain same identity and approximate positions but are not pixel-preserved.',
        'identity_scale':'All eight retain similar head/torso size and the same character; exact color-mask head/torso measurements before/after are in the per-phase arrays.'
      },
      'outputs':{str(p.relative_to(ROOT)):sha(p) for p in [EDIT_NATIVE,EDIT_CONTACT,PAIRED,K7_PAIR,EDIT_GIF]},
      'acceptance':'Staged for root review only. Red-fringe cleanup failed; phase 7 still reads broad-sole recovery rather than compact pass. No further generation or runtime changes.'
    }
    AUDIT.write_text(json.dumps(audit,indent=2),encoding='utf-8')
    print('edited raw',sha(EDIT_RAW))
    print('prompt',sha(PROMPT),'role ref',sha(ROLE_REF))
    print('outputs',json.dumps(audit['outputs'],indent=2))
    print('red before',[m['bright_red_pixels_outside_expected_tool_roi'] for m in before_metrics])
    print('red after',[m['bright_red_pixels_outside_expected_tool_roi'] for m in after_metrics])
    print('per-phase changed%',[d['changed_rgba_percent_of_cell'] for d in phase_diffs])
    print('gif',gif.n_frames,gif.size,durations)

if __name__=='__main__':main()
