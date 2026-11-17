local State=require("src.state")
local Schema=require("src.save_schema")
local Employees=require("src.employees")
local Calendar=require("src.business_calendar")
local Fleet=require("src.machine_fleet")
local AI=require("src.employee_ai")
local Schedule=require("src.employee_schedule")
local Work=require("src.employee_work")
local Jobs=require("src.jobs")
local Config=require("src.config")
local Machine=require("src.machine")
local Jack=require("src.pallet_jack")
local Jacks=require("src.pallet_jack_fleet")
local Pallets=require("src.pallet_state")
local Test={}

local function hours(state,h)
    state.calendar=Calendar.dateFromTotalDay(math.floor(h/24))
    state.calendar.secondsPerDay=300;state.calendar.elapsed=h%24/24*300
end
local function hire(state)
    local a=assert(Employees.createApplicant(state,0));a.shiftPreference="flexible"
    assert(Employees.requestResume(state,a.id,0));Employees.advance(state,.5)
    assert(Employees.command(state,{kind="offer_employee",applicationId=a.id,expectedRevision=a.revision,
        wageCents=math.max(3000,a.requestedWage),days=127,startHour=9,endHour=17},.5))
    Employees.advance(state,1.25)
    assert(Employees.command(state,{kind="hire_employee",applicationId=a.id,expectedRevision=a.revision},1.25))
    local w=state.employment.staff[#state.employment.staff]
    w.contract.startDay=0;w.visible=true;w.clockedIn=true;w.phase="idle";w.x=480;w.y=350
    w.cutterSkill,w.pressSkill,w.wrappingSkill=60,60,60
    hours(state,9.1);return w
end
local function fixture()
    local state=State.new()
    for _,machine in ipairs(Fleet.installedUnits(state,"polar_115")) do Machine.forId(machine.id).reset(state) end
    for _,machine in ipairs(Fleet.installedUnits(state,"skid_wrapper")) do
        Fleet.withUnit(state,machine.id,function()require("src.wrapper").forId(machine.id).reset(state)end)
    end
    return state,hire(state)
end
local function context(state,goal)
    return require("src.tests.employee_transport_context")({state=state,
        canClaim=function()return true end,
        operatorPoint=function(_,w)return goal or {x=w.x,y=w.y} end,
        idlePoint=function(w)return {x=w.x,y=w.y} end,
        seat=function()end,freeSeat=function()end},state)
end
local function startTraining(state,w,skill)
    return Employees.command(state,{kind="train_employee",employeeId=w.id,skill=skill or "cutter"},9.1)
end
local function tick(state,w,ctx,count)
    for _=1,count or 10 do AI.worker(state,w,.1,9.1,ctx or context(state)) end
end
local function reload(state,shared)
    local saved=assert(Schema.snapshot(state),"audit fixture must be a valid save")
    local restored=State.new()
    if shared then assert(State.applySharedSnapshot(restored,saved))
    else assert(State.applyLocalSave(restored,{state=saved,slot=nil})) end
    return restored,restored.employment.staff[1]
end
local function printJob(state)
    state.money=100000
    local okay,press=Fleet.buy(state,"dealer",3);assert(okay,press)
    local job=assert(Jobs.createOffer({id="JOB-AUDIT-DRYING",company="Audit print client",
        sourceSize={width=10,height=15},finishedSize={width=5,height=7},sheetCounts={1050,1050},
        packaging="flat",difficulty="easy",artworkKey="flower",press={colors=2,coverage=.35,
            artworkSize={width=4.25,height=6.25},colorSequence={"Black","Red"},requestedCopies={1000,1000}}}))
    assert(Jobs.accept(job));state.jobs.active={job};job.status="in_production";job.delivery={status="received"}
    local cutter=Fleet.installedUnits(state,"polar_115")[1]
    local x,y
    Fleet.withUnit(state,cutter.id,function()x,y=require("src.cutter_zones").inputAnchor(state,Config.cutterPlacement)end)
    for _,p in ipairs(job.pallets) do
        p.location="warehouse";p.world={x=x,y=y,fromX=x,fromY=y,spawnProgress=1,direction="northwest",rotation=1}
    end
    local first,second=job.pallets[1],job.pallets[2]
    first.status,first.location="cut","press_output";first.paper.status="complete"
    local pose=press.world or state.windmill
    first.world.x,first.world.y=pose.x-60,pose.y+30
    first.world.fromX,first.world.fromY=first.world.x,first.world.y
    first.remainingSheets=0;first.finishedSheets=first.initialSheets
    first.press.status="drying";first.press.completedColors=1;first.press.dryUntilHours=12
    local stock=state.inventory.stock
    stock.raw_press_plates,stock.negative_film,stock.plate_adhesive,stock.plate_chemistry=10,10,10,10
    stock.black_ink,stock.color_ink,stock.tympan_sheets,stock.press_wash=10,10,10,10
    return job,cutter,press,first,second
end
local function production(check)
    local state,w=fixture()
    local job,cutter,press,first,second=printJob(state)
    local row={jobId=job.id,machineId="auto"}
    local stockBefore=state.inventory.stock.raw_press_plates
    local stage,machine,pallet,reason=Schedule.resolve(state,w,row)
    check("employee_audit_ready_skid_passes_drying_skid",stage=="cutter" and machine==cutter and pallet==second and not reason)
    assert(Employees.command(state,{kind="queue_employee_job",employeeId=w.id,jobId=job.id,machineId="auto"},9.1))
    Schedule.advance(state,w,9.1)
    check("employee_audit_queue_assigns_ready_skid",w.assignment and w.assignment.palletId==second.id)
    -- Explicit/active work stays on its pallet until Work safely yields it.
    local _,_,preferred,blocked=Schedule.resolve(state,w,row,first.id)
    check("employee_audit_explicit_drying_assignment_stays_attached",preferred==first and blocked~=nil)
    w.assignment.palletId=first.id;w.assignment.machineId=press.id;w.assignment.machineModel="heidelberg_10x15"
    Work.update(state,w,.1,context(state))
    Schedule.advance(state,w,9.2)
    check("employee_audit_blocked_assignment_safely_retries_same_job",w.assignment and w.assignment.palletId==second.id
        and #w.schedule.items==1 and first.press.completedColors==1)
    local other=hire(state);other.pressSkill=100
    check("employee_audit_second_worker_cannot_steal_queued_job",not Schedule.canQueue(state,other,job.id,"auto"))
    other.assignment={machineId=cutter.id,machineModel="polar_115",palletId=second.id,jobId=job.id}
    local _,busyMachine=Schedule.resolve(state,w,row)
    check("employee_audit_fallback_respects_other_worker_reservation",busyMachine==nil)
    other.assignment=nil
    w.assignment=nil
    local restored,rw=reload(state)
    local _,rm,rp=Schedule.resolve(restored,rw,row)
    check("employee_audit_ready_skid_selection_survives_reload",rm and rp.id==second.id)
    hours(state,12.1)
    local resumedStage,resumedMachine,resumed=Schedule.resolve(state,w,row)
    check("employee_audit_delayed_skid_resumes_after_drying",resumedStage=="press" and resumedMachine==press and resumed==first)
    state.inventory.stock.raw_press_plates=0
    local _,supplyMachine,supplyPallet=Schedule.resolve(state,w,row)
    check("employee_audit_missing_prepress_supplies_allows_ready_cutting",supplyMachine==cutter and supplyPallet==second)
    state.inventory.stock.raw_press_plates=stockBefore
    check("employee_audit_resolving_does_not_consume_or_complete_stock",second.remainingSheets==second.initialSheets
        and first.press.completedColors==1 and first.press.status=="drying" and #job.pallets==2)
    -- A carried load is never abandoned just because another skid is runnable.
    local jack=Jack.ensure(state,Config.palletJack)
    assert(Jack.mountEmployee(state,Config.palletJack,w.id))
    assert(Pallets.transition(state,first,"on_pallet_jack",{jackId=jack.id}))
    first.press.dryUntilHours=20
    local _,_,loaded=Schedule.resolve(state,w,row)
    check("employee_audit_loaded_jack_pins_current_skid",loaded==first and jack.carriedPalletId==first.id)
end
local function trainingAvailability(check)
    for _,skill in ipairs({"cutter","press","wrapping"}) do
        local state,w=fixture()
        if skill=="press" then state.money=100000;assert(Fleet.buy(state,"dealer",3)) end
        local model=skill=="cutter" and "polar_115" or skill=="press" and "heidelberg_10x15" or "skid_wrapper"
        local machine=assert(Fleet.installedUnits(state,model)[1])
        assert(startTraining(state,w,skill))
        local initial=w.training.remainingHours
        state.warehouse.condition.powerConnected=false
        tick(state,w)
        check("employee_audit_"..skill.."_training_requires_power",w.training.remainingHours==initial and not w._trainingMachineId
            and w.activity:find("power",1,true)~=nil)
        state.warehouse.condition.powerConnected=true
        if skill=="cutter" then machine.maintenance.cutter.bladeRemoved=true
        elseif skill=="press" then machine.variables.safetyCircuit=0
        else for key in pairs(machine.variables) do machine.variables[key]=0 end end
        tick(state,w)
        check("employee_audit_"..skill.."_training_requires_operable_machine",w.training.remainingHours==initial and w.phase=="idle")
        if skill=="cutter" then machine.maintenance.cutter.bladeRemoved=false end
        for key in pairs(machine.variables) do machine.variables[key]=100 end
        local ctx=context(state);ctx.canClaim=function()return false end
        tick(state,w,ctx)
        check("employee_audit_"..skill.."_training_respects_player",w.training.remainingHours==initial)
        ctx.canClaim=function()return true end
        local other=hire(state)
        other.training={skill=skill,target=85,remainingHours=4};other._trainingMachineId=machine.id
        tick(state,w,ctx)
        check("employee_audit_"..skill.."_training_respects_employee",w.training.remainingHours==initial)
        other.training=nil;other._trainingMachineId=nil
        tick(state,w,ctx)
        check("employee_audit_"..skill.."_training_resumes_after_repair",w.training.remainingHours<initial and w._trainingMachineId==machine.id)
        local earned=w.training.remainingHours
        state.warehouse.condition.powerConnected=false
        tick(state,w,ctx)
        check("employee_audit_"..skill.."_training_preserves_progress_during_outage",w.training.remainingHours==earned
            and not w._trainingMachineId)
        state.warehouse.condition.powerConnected=true
        local restored,rw=reload(state,true)
        check("employee_audit_"..skill.."_training_progress_survives_snapshot",rw.training.remainingHours==earned)
        rw.training.remainingHours=.05
        tick(restored,rw,context(restored))
        local field=skill=="cutter" and "cutterSkill" or skill=="press" and "pressSkill" or "wrappingSkill"
        check("employee_audit_"..skill.."_training_completes_after_resume",not rw.training and rw[field]==85)
    end
    local state,w=fixture();assert(startTraining(state,w))
    local machine=Fleet.installedUnits(state,"polar_115")[1]
    local runtime=Machine.forId(machine.id);runtime.step="cutting"
    tick(state,w)
    check("employee_audit_training_does_not_overlap_live_cutter",w.training.remainingHours==4 and not w._trainingMachineId)
    runtime.reset(state)
    machine.maintenance.cutter.technicianStatus="servicing"
    tick(state,w)
    check("employee_audit_training_waits_for_blade_technician",w.training.remainingHours==4 and not w._trainingMachineId)
    local pressState,pw=fixture();pressState.money=100000;assert(Fleet.buy(pressState,"dealer",3))
    assert(startTraining(pressState,pw,"press"))
    local press=Fleet.installedUnits(pressState,"heidelberg_10x15")[1]
    Fleet.withUnit(pressState,press.id,function()require("src.windmill").ensure(pressState).status="production" end)
    tick(pressState,pw)
    check("employee_audit_training_does_not_overlap_live_press",pw.training.remainingHours==4 and not pw._trainingMachineId)
    local wrapState,ww=fixture();assert(startTraining(wrapState,ww,"wrapping"))
    local wrapper=Fleet.installedUnits(wrapState,"skid_wrapper")[1]
    local wrapping=require("src.wrapper").forId(wrapper.id);wrapping.step="wrapping"
    tick(wrapState,ww)
    check("employee_audit_training_does_not_overlap_live_wrapper",ww.training.remainingHours==4 and not ww._trainingMachineId)
    wrapping.step="idle";wrapping.reset(wrapState)
end
local function trainingTransport(check)
    local state,w=fixture();local ctx=context(state)
    local jack=Jack.ensure(state,Config.palletJack);jack.x,jack.y=400,350
    assert(Jack.mountEmployee(state,Config.palletJack,w.id))
    w.x,w.y=Jack.operatorPosition(state,Config.palletJack)
    ctx.jackParkingPoint=function()return {x=440,y=350}end
    assert(startTraining(state,w))
    local initial=w.training.remainingHours
    tick(state,w,ctx,1)
    check("employee_audit_training_waits_during_jack_parking",Jacks.owned(state,w.id) and w.training.remainingHours==initial)
    for _=1,100 do tick(state,w,ctx,1);if not Jacks.owned(state,w.id) then break end end
    local other={id="AUDIT-OTHER",x=440,y=350}
    check("employee_audit_training_parks_and_releases_empty_jack",not Jacks.owned(state,w.id)
        and math.abs(jack.x-440)<5 and Jacks.employee(state,other)~=nil)
    tick(state,w,ctx)
    check("employee_audit_training_starts_after_parking",w.training.remainingHours<initial)
    assert(Employees.command(state,{kind="cancel_employee_training",employeeId=w.id},9.1))
    check("employee_audit_cancel_training_leaves_jack_available",not w.training and not Jacks.owned(state,w.id))
    -- Room travel must not bypass the equipment handoff at the start of AI.worker.
    assert(Jack.mountEmployee(state,Config.palletJack,w.id))
    w.sceneId="storage";jack.sceneId="storage"
    local traveled=false;ctx.travelScene=function()traveled=true;return true,true end
    assert(startTraining(state,w));tick(state,w,ctx,1)
    check("employee_audit_training_parks_before_room_travel",not traveled and not Jacks.owned(state,w.id))
    assert(Employees.command(state,{kind="cancel_employee_training",employeeId=w.id},9.1))
    w.sceneId="warehouse";jack.sceneId="warehouse";ctx.travelScene=nil
    local job=assert(Jobs.createOffer({id="JOB-AUDIT-LOAD",company="Load client",
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500}}))
    assert(Jobs.accept(job));state.jobs.active={job}
    local pallet=job.pallets[1];pallet.location="warehouse"
    pallet.world={x=400,y=350,fromX=400,fromY=350,spawnProgress=1,direction="east",rotation=1}
    assert(Jack.mountEmployee(state,Config.palletJack,w.id))
    assert(Pallets.transition(state,pallet,"on_pallet_jack",{jackId=jack.id}))
    check("employee_audit_training_rejects_loaded_duty_change",not startTraining(state,w)
        and jack.carriedPalletId==pallet.id and Jacks.owned(state,w.id)==jack)
    -- Recover legacy saves that already combined a course with a loaded jack.
    w.training={skill="cutter",target=85,remainingHours=4}
    ctx.jackEmergencyDropPoint=nil
    tick(state,w,ctx,1)
    check("employee_audit_legacy_training_releases_operator_preserving_load",not Jacks.owned(state,w.id)
        and jack.carriedPalletId==pallet.id and pallet.location=="on_pallet_jack" and Jacks.validate(state))
    local restored,rw=reload(state)
    check("employee_audit_loaded_training_recovery_survives_reload",restored.palletJack.carriedPalletId==pallet.id
        and restored.jobs.active[1].pallets[1].remainingSheets==500 and rw.training.remainingHours==4)
    AI.worker(restored,rw,.1,17.1,context(restored))
    check("employee_audit_shift_end_preserves_released_jack_load",restored.palletJack.carriedPalletId==pallet.id and not rw.clockedIn)
end
local function closedAttendance(check)
    local state,w=fixture()
    w.visible=false;w.clockedIn=false;w.phase="hidden";w.sceneId=nil
    w.commuteState=require("src.commute.employee_commute").journey(w.commuteProfile,"commuting_to_work",8)
    w.commuteState.motion={elapsed=.4,bike={x=100,z=100,h=0,heading=0,speed=0,progress=.4,parked=false}}
    assert(require("src.commute.employee_commute").validState(w.commuteState,w.commuteProfile))
    AI.worker(state,w,.1,9.1,context(state));AI.updateClosedShop(state,9.1,9.2)
    check("employee_audit_pending_commute_stays_outside_unpaid",not w.visible and not w.clockedIn and w.laborTotals.shopCents==0)
    local restored,rw=reload(state)
    AI.updateClosedShop(restored,9.2,16)
    check("employee_audit_pending_commute_survives_reload_fast_forward",not rw.visible and not rw.clockedIn and rw.laborTotals.shopCents==0)
    rw.commuteState.motion.elapsed=rw.commuteState.arriveAtHours-rw.commuteState.departAtHours
    AI.updateClosedShop(restored,16,16.1)
    check("employee_audit_arrived_worker_waits_and_earns_wages",rw.visible and rw.clockedIn and rw.phase=="waiting"
        and math.abs(rw.laborTotals.shopCents-rw.contract.wageCents*.1)<.001)
    AI.updateClosedShop(restored,16.1,18)
    check("employee_audit_closed_shop_pay_clips_to_shift_end",not rw.visible and not rw.clockedIn
        and math.abs(rw.laborTotals.shopCents-rw.contract.wageCents)<.001)
end
function Test.run(_,check)
    production(check)
    trainingAvailability(check)
    trainingTransport(check)
    closedAttendance(check)
end
return Test
