"""Physical LAN press production from a validated, already-cut stock fixture."""
import json,time
import run_live_network_journey as N
from live_device import ROOT,adb,DEFAULT_SERIAL
N.OUT=ROOT/'output/live-gameplay-20261109/press';N.OUT.mkdir(exist_ok=True);N.checks=[]
pc,phone,check,wait,ws=N.pc,N.phone,N.check,N.wait,N.ws
N.helpers();N.release()
pc("""for _,id in ipairs({"raw_press_plates","negative_film","plate_adhesive","plate_chemistry","black_ink","color_ink","tympan_sheets","press_wash"}) do R.state.inventory.stock[id]=10 end;R.state.jobs.active={};R.state.accountsReceivable=0;local j=assert(R.Jobs.createOffer({id='S25-PRESS',company='Physical Press Test',sourceSize={width=10,height=15},finishedSize={width=5,height=7},sheetCounts={500},packaging='flat',artworkKey='flower',press={colors=1,coverage=.35,artworkSize={width=4.25,height=6.25},colorSequence={'Black'},requestedCopies={450}},details={stockDescription='80 lb uncoated cover'}}));assert(R.JobService.acceptOffer(R.state,j,os.time()));local p=j.pallets[1];for i=1,4 do p.paper.orientation=p.paper.cuts[i].orientation;assert(R.PaperWork.applyCut(p.paper,p.paper.cuts[i].gauge,i,100,100)) end;p.status='cut';p.completedLifts=1;p.remainingSheets=0;p.finishedSheets=500;assert(R.PalletState.transition(R.state,p,'warehouse',{world={x=R.state.windmill.x-60,y=R.state.windmill.y+30,direction='northwest',rotation=1,spawnProgress=1}}));R.PlateService.ensureJob(j);local s,e=R.SaveSchema.snapshot(R.state);assert(s,e);R.multiplayer:markShopDirty(true);return true""")
N.acquire('windmill')
plate=phone('return R.state.jobs.active[1].press.plates[1].id')
ws('begin_plate','begin_plate','{plateId='+json.dumps(plate)+'}')
# Input bot watches the same replicated timing marker as the visible GUI.
phone("""local poll=R.liveDevicePoll;R.liveDevicePoll=function(dt) poll(dt);local marker=R.WorkshopRemoteScreen.view and R.WorkshopRemoteScreen.view.plateMarkerPermille;if R.livePlate and marker and marker>=640 and marker<=700 then local p=R.livePlate;R.livePlate=nil;assert(R.multiplayer:requestWorkshopCommand('process_plate',{plateId=p})) end end;return true""")
for i in range(4):N.action('plate_step_'+str(i+1),'R.livePlate='+json.dumps(plate))
check('plate_mounted',pc('return R.state.jobs.active[1].press.plates[1].mounted'))
pallet=phone('return R.state.jobs.active[1].pallets[1].id')
ws('load_print_stock','load_pallet','{palletId='+json.dumps(pallet)+'}')
sequences={'chase':['align','align','square','square','tighten','tighten'],
 'packing':['layer','layer','layer','smooth','smooth','clamp'],
 'rollers':['left_up','left_up','right_down','right_down'],
 'ink':['key_1','key_1','key_2','key_2','key_2','key_2','key_3','ductor'],
 'feeder':['prepare','suction_up','air_down','test','test','test'],
 'register':['left','left','left','down','down','test']}
for task,actions in sequences.items():
    ws('open_'+task,'begin_setup','{setupTask='+json.dumps(task)+'}')
    for i,action in enumerate(actions):ws(task+'_'+str(i+1),'setup_action','{setupAction='+json.dumps(action)+'}')
check('six_setups_completed',pc('return R.Windmill.setupComplete(R.state)'))
for action in ('toggle_motor','toggle_feeder','toggle_impression','take_proof','verify_artwork','approve_proof','start_run'):ws(action,action)
(N.OUT/'production.png').write_bytes(adb(DEFAULT_SERIAL,'exec-out','screencap','-p',binary=True))
ws('emergency_stop','emergency_stop')
before=pc('return R.Windmill.ensure(R.state).counter')
time.sleep(1)
check('emergency_stops_feed',pc('local p=R.Windmill.ensure(R.state);return not p.motor and not p.feeder and p.counter=='+str(before)))
ws('reset_emergency','reset_safety')
for action in ('toggle_motor','toggle_feeder','toggle_impression','start_run'):ws('resume_'+action,action)
wait(lambda:pc("return R.Windmill.ensure(R.state).status=='pass_complete'"),seconds=35)
check('exact_450_sheet_target',phone('return R.WorkshopRemoteScreen.view.goodSheets==450'))
ws('clean_unload','clean_unload')
check('print_pass_recorded_once',phone('local p=R.state.jobs.active[1].pallets[1];return p.press.completedColors==1 and #p.press.passHistory==1 and p.finishedSheets==450'))
N.release()
check('valid_print_save',pc('local s,e=R.SaveSchema.snapshot(R.state);assert(s,e);assert(R.saveCurrent(true));return true'))
