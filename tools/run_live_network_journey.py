"""Physical PC/S25 LAN journey. Fixture staging is explicit; commands use real ENet."""
import json, time
from pathlib import Path
from live_device import ROOT, command, adb, DEFAULT_SERIAL, PACKAGE, put

OUT=ROOT/'output/live-gameplay-20261109/network'
OUT.mkdir(parents=True,exist_ok=True)
checks=[]
def call(target,source): return command(target,source,OUT/'commands')
def pc(source): return call('pc',source)
def phone(source): return call('phone',source)
def check(name,condition,detail=None):
    checks.append({'name':name,'passed':bool(condition),'detail':detail})
    (OUT/'summary.json').write_text(json.dumps({'checks':checks},indent=2))
    print(('PASS ' if condition else 'FAIL ')+name,flush=True)
    assert condition,(name,detail)
def wait(fn,predicate=lambda v:bool(v),seconds=15):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        value=fn()
        if predicate(value): return value
        time.sleep(.35)
    raise TimeoutError(value)
def helpers():
    for target in ('pc','phone'): call(target,(ROOT/'tools/live_network_helpers.lua').read_text())
def release():
    phone("if R.multiplayer:workshopInfo() then R.multiplayer:releaseWorkshop('closed') end; R.WorkshopRemoteScreen.clear();R.state.screen='world';return true")
    time.sleep(.4)
def stage(resource):
    release()
    point=pc("local kind="+json.dumps(resource)+";local p=kind=='office_computer' and R.Config.interactables.computer or kind=='truck' and R.World.truck:getInteraction() or R.state[kind=='skid_wrapper' and 'wrapper' or kind];assert(p);local g=assert(R.multiplayer.players[2]);g.x,g.y,g.sceneId=p.x,p.y,'warehouse';return {x=p.x,y=p.y}")
    phone("R.World.player.x=%s;R.World.player.y=%s;R.World.player.sceneId='warehouse';return true"%(point['x'],point['y']))
    time.sleep(.4)
def acquire(resource):
    stage(resource)
    target=resource
    if resource in ('cutter','windmill','skid_wrapper'):
        target=pc('local base='+json.dumps(resource)+';local unit=R.MachineFleet.installedUnits(R.state,R.MachineResource.model(base))[1];return R.MachineResource.forUnit(base,unit.id)')
    phone('R.liveResults={};assert(R.multiplayer:requestWorkshopAcquire('+json.dumps(target)+'));return true')
    result=wait(lambda:phone('return R.liveResults[#R.liveResults]'))
    check('acquire_'+resource,result.get('granted') is True,result)
def action(label,source,accepted=True):
    phone('R.liveResults={};'+source+';return true')
    result=wait(lambda:phone("return R.liveResults[#R.liveResults]"))
    check(label,result.get('accepted') is accepted,result)
    return result
def ws(label,name,args='{}'):
    return action(label,'assert(R.multiplayer:requestWorkshopCommand('+json.dumps(name)+','+args+'))')
def key(label,keyname):return action(label,'R.liveKey('+json.dumps(keyname)+')')
def click(label,expr):return action(label,'R.liveClick('+expr+')')
def deliver_email():
    pc("local p=assert(R.state.clientEmails.pending[1]);local C=R.BusinessCalendar;C.update(R.state,(p.readyAtHours-C.absoluteHours(R.state))/24*R.state.calendar.secondsPerDay+.01);R.JobService.updateClientEmails(R.state);R.multiplayer:markShopDirty(true);return true")
    time.sleep(.6)
def truck(mode):
    release();pc("R.World.truck.mode='%s';R.World.truck.jobId=R.state.jobs.active[1].id;R.World.truck.state='cargo_open';R.World.truck.backingProgress=1;R.World.truck.cargoProgress=1;R.World._state=R.state;return true"%mode)
    acquire('truck')
def stage_pallet(index,where):
    pc("local p=R.state.jobs.active[1].pallets[%d];local x,y=%s;assert(R.PalletState.transition(R.state,p,'on_pallet_jack'));assert(R.PalletState.transition(R.state,p,'warehouse',{world={x=x,y=y,fromX=x,fromY=y,direction='northwest',rotation=1,spawnProgress=1}}));R.multiplayer:markShopDirty(true);return true"%(index,where))
def main():
    helpers()
    check('real_LAN_two_players',phone("return R.multiplayer.ready and R.multiplayer:hudInfo().playerCount==2 and R.multiplayer.networkKind=='lan'"))
    release()
    pc("local fresh=R.State.new();R.state.jobs=fresh.jobs;R.state.clientEmails=fresh.clientEmails;R.state.accountsReceivable=0;R.state.bills=fresh.bills;R.state.calendar=R.BusinessCalendar.dateFromHours(9);R.state.calendar.secondsPerDay=3600;R.state.calendar.elapsed=9/24*3600;R.Machine.reset(R.state);R.Wrapper.reset(R.state);R.World.truck.state='absent';local offer=assert(R.Jobs.createOffer({id='JOB-S25-LIVE',company='S25 Acceptance',sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500},packaging='flat',artworkKey='flower',details={stockDescription='100 lb uncoated cover'}}));assert(R.JobService.requestEstimateDetails(R.state,offer,100));return true")
    deliver_email();acquire('office_computer')
    phone("R.liveTab('estimating');R.liveClick(R.WorkshopRemoteScreen.sharedComputer.rowCenter(1));return true");time.sleep(.6)
    phone("R.liveClick(R.WorkshopRemoteScreen.sharedComputer.textInputCenter('quote'));R.WorkshopRemoteScreen.textinput(tostring(R.state.clientEmails.inbox[1].job.quote.totalPrice));return true")
    click('quote_sent',"R.WorkshopRemoteScreen.sharedComputer.emailButtonCenter('accept')")
    check('quote_requires_reply',pc('return #R.state.jobs.active==0 and #R.state.clientEmails.pending==1'))
    release();deliver_email()
    check('accepted_job_synced',phone("return #R.state.jobs.active==1 and R.state.jobs.active[1].id=='JOB-S25-LIVE' and R.state.activeSlot==nil"))
    truck('delivery');click('unload_stock','R.RuntimeDependencies.TruckInventoryScreen.unloadButtonCenter(1)')
    release();pc("R.World.truck.state='absent';return true")
    stage_pallet(1,'R.RuntimeDependencies.CutterZones.inputAnchor(R.state,R.Config.cutterPlacement)')
    acquire('cutter');phone("R.liveKey('l');return true");key('load_stock','return');time.sleep(2)
    key('rotate_wrong_cut','q');ws('wrong_gauge','set_gauge','{gaugeCentiInch=100}')
    ws('position_wrong_cut','position_paper');time.sleep(2);ws('clamp_wrong_cut','set_clamp','{clamp=true}')
    ws('wrong_cut','guarded_cut');time.sleep(2)
    check('spoil_creates_one_replacement',pc('local j=R.state.jobs.active[1];return #j.pallets==2 and j.pallets[1].damagedSheets==500 and j.pallets[2].initialSheets==500 and R.state.bills.balance>0'))
    key('discard_spoiled_stock','u');truck('delivery');click('unload_replacement','R.RuntimeDependencies.TruckInventoryScreen.unloadButtonCenter(1)')
    release();pc("R.World.truck.state='absent';return true")
    stage_pallet(2,'R.RuntimeDependencies.CutterZones.inputAnchor(R.state,R.Config.cutterPlacement)')
    acquire('cutter');phone("R.liveKey('l');return true");key('load_replacement','return');time.sleep(2)
    for cut in range(1,5):
        target=pc('return R.state.jobs.active[1].pallets[2].paper.cuts[%d]'%cut)
        for _ in range(4):
            if phone('return R.WorkshopRemoteScreen.view.paper.orientation')==target['orientation']:break
            ws('rotate_'+str(cut),'rotate_paper')
        ws('gauge_'+str(cut),'set_gauge','{gaugeCentiInch=%d}'%round(target['gauge']*100))
        ws('position_'+str(cut),'position_paper');time.sleep(2)
        ws('clamp_'+str(cut),'set_clamp','{clamp=true}')
        ws('cut_'+str(cut),'guarded_cut');time.sleep(2)
        if cut==2:
            lease=phone('return R.WorkshopRemoteScreen.leaseId')
            resource=phone('return R.WorkshopRemoteScreen.leaseResourceId')
            check('cutter_lease_live_before_disconnect',pc('return R.workshopAuthority:leaseForResource('+json.dumps(resource)+')~=nil'))
            adb(DEFAULT_SERIAL,'shell','svc','wifi','disable')
            try:
                wait(lambda:pc('return R.workshopAuthority:leaseForResource('+json.dumps(resource)+')==nil and R.multiplayer.players[2]==nil'),seconds=35)
                check('wifi_loss_releases_cutter',True)
            finally:adb(DEFAULT_SERIAL,'shell','svc','wifi','enable')
            wait(lambda:phone('return R.multiplayer.ready'),seconds=65)
            check('automatic_wifi_rejoin',True)
            check('rejoin_has_no_old_lease',phone('return R.multiplayer:workshopInfo()==nil'))
            acquire('cutter')
            check('rejoin_keeps_exactly_two_cuts',phone('return R.WorkshopRemoteScreen.view.paper.activeCut==3 and R.WorkshopRemoteScreen.leaseId~='+json.dumps(lease)))
    check('four_cuts_complete_one_lift',pc('local p=R.state.jobs.active[1].pallets[2];return #p.paper.history==4 and p.completedLifts==1 and p.finishedSheets==500'))
    key('unload_finished_lift','u');time.sleep(2);release()
    stage_pallet(2,'R.state.wrapper.x-60,R.state.wrapper.y');acquire('skid_wrapper')
    before=pc('return R.state.inventory.plasticWrapUses')
    click('wrap_started','760,547')
    wait(lambda:phone('return R.state.jobs.active[1].pallets[2].wrapped'),seconds=30)
    check('wrap_completed_once',phone('return R.state.jobs.active[1].pallets[2].wrapped and R.state.inventory.plasticWrapUses=='+str(before-1)))
    acquire('office_computer');phone("R.liveTab('bills');return true")
    click('pay_spoil_bill','R.WorkshopRemoteScreen.sharedComputer.payBillsCenter()')
    phone("R.liveTab('active');R.liveClick(R.WorkshopRemoteScreen.sharedComputer.rowCenter(1));return true")
    click('inspection','R.WorkshopRemoteScreen.sharedComputer.completeCenter()')
    click('pickup_request','R.WorkshopRemoteScreen.sharedComputer.completeCenter()')
    truck('pickup');click('load_pickup','R.RuntimeDependencies.TruckInventoryScreen.unloadButtonCenter(1)')
    click('release_truck','R.RuntimeDependencies.TruckInventoryScreen.closeDoorCenter()');release()
    wait(lambda:pc('return #R.state.jobs.completed==1'),seconds=30)
    check('job_paid_and_synced',phone('return #R.state.jobs.completed==1 and #R.state.jobs.active==0 and R.state.accountsReceivable==0 and R.state.bills.balance==0'))
    pc('assert(R.saveCurrent(true));return true')
    check('valid_final_save',pc('return R.SaveSchema.snapshot(R.state)~=nil'))
if __name__=='__main__':main()
