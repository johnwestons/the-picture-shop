local State=require("src.state")
local Schema=require("src.save_schema")
local Employees=require("src.employees")
local Schedule=require("src.employee_schedule")
local Windmill=require("src.windmill")
local Work=require("src.employee_work")
local AI=require("src.employee_ai")
local Jobs=require("src.jobs")
local Fleet=require("src.machine_fleet")
local Calendar=require("src.business_calendar")
local Contracts=require("src.employment_contracts")
local Intent=require("src.office_intent")
local Office=require("src.office_authority")
local Screen=require("src.screens.schedule_screen")
local Test={}
local function hours(state,h)
    state.calendar=Calendar.dateFromTotalDay(math.floor(h/24));state.calendar.elapsed=(h%24)/24*Calendar.secondsPerDay(state)
end
local function hire(state)
    local a=Employees.createApplicant(state,0)
    Employees.requestResume(state,a.id,0);Employees.advance(state,.5)
    local startHour=a.shiftPreference=="night" and 21 or 9
    local endHour=a.shiftPreference=="night" and 5 or 17
    Employees.command(state,{kind="offer_employee",applicationId=a.id,expectedRevision=a.revision,
        wageCents=math.max(2200,a.requestedWage),days=31,startHour=startHour,endHour=endHour},.5)
    Employees.advance(state,1.25)
    assert(Employees.command(state,{kind="hire_employee",applicationId=a.id,expectedRevision=a.revision},1.25))
    local w=state.employment.staff[#state.employment.staff]
    -- Low-skilled workers should skip advanced shared jobs and leave them
    -- available for an employee with the required production skill.
    w.cutterSkill,w.pressSkill,w.wrappingSkill=1,0,0
    w.visible=true;w.clockedIn=true;w.phase="idle";hours(state,9)
    return w
end
local function job(state,id,counts)
    local j=assert(Jobs.createOffer({id=id,company="Schedule client "..id,sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts=counts or {500}}))
    Jobs.accept(j);state.jobs.active[#state.jobs.active+1]=j;return j
end
local function add(state,w,j,m)
    return Employees.command(state,{kind="queue_employee_job",employeeId=w.id,jobId=j.id,machineId=m.id},9)
end
local function deliver(state,j,context)
    for _,p in ipairs(j.pallets) do
        if p.location=="awaiting_delivery" then
            local okay,message=context.PalletLogistics.unload(state,j.id,p.id,
                context.config.palletLogistics.spawnPoints,context.config.palletLogistics.unloadOrigin)
            assert(okay,message)
        end
    end
end
local function markDelivered(j)
    j.status="in_production"
    j.delivery=j.delivery or {}
    j.delivery.status="received"
    for index,p in ipairs(j.pallets) do
        p.location="warehouse";p.status="raw"
        p.world=p.world or {}
        p.world.x,p.world.y=480+index*18,330
        p.world.fromX,p.world.fromY=p.world.x,p.world.y
        p.world.spawnProgress=1
    end
end
local function testTransfersAndPackaging(context,check)
    local transferState=State.new();local transferWorker=hire(transferState)
    transferWorker.cutterSkill=100
    local transferMachine=Fleet.installedUnits(transferState,"polar_115")[1]
    local transferJob=job(transferState,"JOB-OFF-ZONE-CUTTER")
    markDelivered(transferJob)
    local transferX,transferY=context.CutterZones.inputAnchor(
        transferState,context.config.cutterPlacement)
    local transferPallet=transferJob.pallets[1]
    transferPallet.world.x,transferPallet.world.y=transferX+500,transferY
    transferPallet.world.fromX,transferPallet.world.fromY=transferX+500,transferY
    transferPallet.world.spawnProgress=1
    context.machine.reset(transferState)
    local transferQueued=add(transferState,transferWorker,transferJob,transferMachine)
    Schedule.advance(transferState,transferWorker,9.1)
    local resolvedStage,_,_,transferBlocked,transferNeeded=Schedule.resolve(transferState,
        transferWorker,{jobId=transferJob.id,machineId=transferMachine.id},transferPallet.id)
    local transferContext={canClaim=function() return true end,
        operatorPoint=function(_,worker) return {x=worker.x,y=worker.y} end,
        palletApproachPoint=function(pallet) return {x=pallet.world.x,y=pallet.world.y} end,
        machinePalletDropPoint=function(_,_,_,stage)
            if stage=="cutter" then return {x=transferX,y=transferY} end
        end,
        move=function(worker,goal)
            worker.x,worker.y=goal.x,goal.y;worker.moving=false;return true
        end}
    Work.update(transferState,transferWorker,.1,transferContext)
    local carriedForCutter=transferPallet.location=="on_employee"
        and transferWorker.carryingPalletId==transferPallet.id
    Work.update(transferState,transferWorker,.1,transferContext)
    check("schedule_worker_moves_first_off_zone_job_into_cutter_feed_zone",
        transferQueued and carriedForCutter and transferPallet.location=="warehouse"
        and transferWorker.carryingPalletId==nil
        and context.CutterZones.inInputZone(transferState,transferPallet,
            context.config.cutterPlacement),
        "queued="..tostring(transferQueued).." carried="..tostring(carriedForCutter)
            .." location="..tostring(transferPallet.location)
            .." carrier="..tostring(transferWorker.carryingPalletId)
            .." activity="..tostring(transferWorker.activity)
            .." position="..tostring(transferPallet.world.x)..","..tostring(transferPallet.world.y)
            .." stage="..tostring(resolvedStage).." blocked="..tostring(transferBlocked)
            .." transfer="..tostring(transferNeeded)
            .." inZone="..tostring(context.CutterZones.inInputZone(transferState,
                transferPallet,context.config.cutterPlacement)))
    local movedSnapshot=Schema.snapshot(transferState)
    local transferGuest=State.new()
    local movedShared=movedSnapshot and State.applySharedSnapshot(transferGuest,movedSnapshot)
    local guestTransferPallet=movedShared and transferGuest.jobs.active[1].pallets[1]
    check("schedule_repositioned_pallet_syncs_into_multiplayer_guest_state",
        guestTransferPallet and guestTransferPallet.location=="warehouse"
        and context.CutterZones.inInputZone(transferGuest,guestTransferPallet,
            context.config.cutterPlacement))
    local transferCutter=context.machine.forId(transferMachine.id)
    local beganScheduledCut=false
    for _=1,800 do
        Work.update(transferState,transferWorker,.1,transferContext)
        context.machine.updateAll(.1,transferState)
        if transferCutter.step=="cutting" then beganScheduledCut=true;break end
    end
    check("schedule_worker_begins_cutting_after_moving_pallet_into_range",
        beganScheduledCut and transferPallet.location=="at_cutter")
    context.machine.reset(transferState)

    local packagingState=State.new();local packagingWorker=hire(packagingState)
    packagingWorker.cutterSkill,packagingWorker.wrappingSkill=100,60
    local packagingCutter=Fleet.installedUnits(packagingState,"polar_115")[1]
    local waitingWrapJob=job(packagingState,"JOB-WAITING-FOR-WRAP")
    local nextCutJob=job(packagingState,"JOB-CUT-WHILE-WRAP-OUT")
    markDelivered(waitingWrapJob);markDelivered(nextCutJob)
    waitingWrapJob.pallets[1].status="cut"
    waitingWrapJob.pallets[1].location="cutter_output"
    local packagingX,packagingY=context.CutterZones.inputAnchor(
        packagingState,context.config.cutterPlacement)
    local nextCutPallet=nextCutJob.pallets[1]
    nextCutPallet.world.x,nextCutPallet.world.y=packagingX,packagingY
    nextCutPallet.world.fromX,nextCutPallet.world.fromY=packagingX,packagingY
    nextCutPallet.world.spawnProgress=1
    packagingState.inventory.plasticWrapUses=0
    assert(add(packagingState,packagingWorker,waitingWrapJob,packagingCutter))
    assert(add(packagingState,packagingWorker,nextCutJob,packagingCutter))
    local packagingWrapper=Fleet.installedUnits(packagingState,"skid_wrapper")[1]
    context.machine.reset(packagingState);context.wrapper.select(packagingWrapper.id,packagingState)
    context.wrapper.reset(packagingState)
    Schedule.advance(packagingState,packagingWorker,9.1)
    check("schedule_skips_wrap_shortage_and_selects_next_cut_job",
        packagingWorker.assignment and packagingWorker.assignment.jobId==nextCutJob.id
        and packagingWorker.schedule.items[1].jobId==nextCutJob.id
        and packagingWorker.schedule.items[2].jobId==waitingWrapJob.id
        and waitingWrapJob.pallets[1].status=="cut")

    local sharedPackagingState=State.new();local sharedPackagingWorker=hire(sharedPackagingState)
    sharedPackagingWorker.cutterSkill,sharedPackagingWorker.wrappingSkill=100,60
    local sharedPackagingCutter=Fleet.installedUnits(sharedPackagingState,"polar_115")[1]
    local sharedWrapJob=job(sharedPackagingState,"JOB-SHARED-WRAP-STOCKOUT")
    local sharedCutJob=job(sharedPackagingState,"JOB-SHARED-CUT-NEXT")
    sharedWrapJob.packaging="boxed"
    sharedWrapJob.pallets[1].packaging="boxed"
    markDelivered(sharedWrapJob);markDelivered(sharedCutJob)
    sharedWrapJob.pallets[1].status="cut"
    sharedWrapJob.pallets[1].location="cutter_output"
    local sharedX,sharedY=context.CutterZones.inputAnchor(
        sharedPackagingState,context.config.cutterPlacement)
    local sharedCutPallet=sharedCutJob.pallets[1]
    sharedCutPallet.world.x,sharedCutPallet.world.y=sharedX,sharedY
    sharedCutPallet.world.fromX,sharedCutPallet.world.fromY=sharedX,sharedY
    sharedCutPallet.world.spawnProgress=1
    sharedPackagingState.inventory.plasticWrapUses=1
    sharedPackagingState.inventory.stock.shipping_cartons=1
    local sharedWrapIntent=Intent.normalize({kind="queue_team_job",jobId=sharedWrapJob.id,
        machineId=sharedPackagingCutter.id})
    local sharedCutIntent=Intent.normalize({kind="queue_team_job",jobId=sharedCutJob.id,
        machineId=sharedPackagingCutter.id})
    assert(Employees.command(sharedPackagingState,sharedWrapIntent,9))
    assert(Employees.command(sharedPackagingState,sharedCutIntent,9))
    local sharedPackagingWrapper=Fleet.installedUnits(sharedPackagingState,"skid_wrapper")[1]
    context.machine.reset(sharedPackagingState)
    context.wrapper.select(sharedPackagingWrapper.id,sharedPackagingState)
    context.wrapper.reset(sharedPackagingState)
    Schedule.advance(sharedPackagingState,sharedPackagingWorker,9.1)
    local initiallyClaimedWrap=sharedPackagingWorker.assignment
        and sharedPackagingWorker.assignment.jobId==sharedWrapJob.id
    sharedPackagingState.inventory.stock.shipping_cartons=0
    local packagingBlockedContext={palletEmergencyDropPoint=function(_,pallet) return pallet.world end}
    local _,packagingBlock=Work.update(sharedPackagingState,sharedPackagingWorker,.1,
        packagingBlockedContext)
    check("blocked_shared_boxing_yields_team_claim_without_removing_task",
        initiallyClaimedWrap and packagingBlock=="Order a shipping carton before wrapping this boxed pallet"
        and sharedPackagingWorker.assignment==nil and #sharedPackagingWorker.schedule.items==0
        and #sharedPackagingState.employment.teamSchedule.items==2
        and sharedPackagingState.employment.teamSchedule.items[1].jobId==sharedWrapJob.id,
        "initial="..tostring(initiallyClaimedWrap) .." block="..tostring(packagingBlock)
            .." assignment="..tostring(sharedPackagingWorker.assignment and sharedPackagingWorker.assignment.jobId)
            .." local="..#sharedPackagingWorker.schedule.items
            .." team="..#sharedPackagingState.employment.teamSchedule.items
            .." cartons="..sharedPackagingState.inventory.stock.shipping_cartons)
    Schedule.advance(sharedPackagingState,sharedPackagingWorker,9.2)
    local sharedCutClaimed=sharedPackagingWorker.assignment
        and sharedPackagingWorker.assignment.jobId==sharedCutJob.id
    local sharedCutter=context.machine.forId(sharedPackagingCutter.id)
    local sharedWorkContext={canClaim=function() return true end,
        operatorPoint=function(_,worker) return {x=worker.x,y=worker.y} end,
        move=function(worker,goal)
            worker.x,worker.y=goal.x,goal.y;worker.moving=false;return true
        end}
    local startedSharedCut=false
    for _=1,800 do
        Work.update(sharedPackagingState,sharedPackagingWorker,.1,sharedWorkContext)
        context.machine.updateAll(.1,sharedPackagingState)
        if sharedCutter.step=="cutting" then startedSharedCut=true;break end
    end
    check("shared_queue_worker_starts_next_cut_with_packaging_out",
        sharedCutClaimed and startedSharedCut and sharedWrapJob.pallets[1].status=="cut"
        and sharedPackagingState.employment.teamSchedule.items[1].jobId==sharedWrapJob.id)
    local sharedPackagingSnapshot=Schema.snapshot(sharedPackagingState)
    local packagingGuest=State.new()
    local packagingSnapshotApplied=sharedPackagingSnapshot
        and State.applySharedSnapshot(packagingGuest,sharedPackagingSnapshot)
    check("multiplayer_snapshot_syncs_released_wrap_task_and_next_cut_assignment",
        packagingSnapshotApplied and #packagingGuest.employment.teamSchedule.items==2
        and packagingGuest.employment.teamSchedule.items[1].jobId==sharedWrapJob.id
        and packagingGuest.employment.staff[1].assignment.jobId==sharedCutJob.id
        and packagingGuest.employment.staff[1].schedule.items[1].jobId==sharedCutJob.id)
    context.machine.reset(sharedPackagingState);context.wrapper.reset(sharedPackagingState)

    local blockedState=State.new();local blockedWorker=hire(blockedState)
    blockedWorker.cutterSkill=100
    blockedWorker.contract.days,blockedWorker.contract.startHour,blockedWorker.contract.endHour,
        blockedWorker.contract.startDay=127,9,17,0
    blockedWorker.visible=true;blockedWorker.clockedIn=true;blockedWorker.phase="idle"
    local blockedMachine=Fleet.installedUnits(blockedState,"polar_115")[1]
    local inaccessibleJob=job(blockedState,"JOB-ROUTE-BLOCKED")
    local reachableJob=job(blockedState,"JOB-ROUTE-READY")
    markDelivered(inaccessibleJob);markDelivered(reachableJob)
    local blockedX,blockedY=context.CutterZones.inputAnchor(
        blockedState,context.config.cutterPlacement)
    for _,p in ipairs(inaccessibleJob.pallets) do
        p.world.x,p.world.y=blockedX,blockedY;p.world.fromX,p.world.fromY=blockedX,blockedY;p.world.spawnProgress=1
    end
    for _,p in ipairs(reachableJob.pallets) do
        p.world.x,p.world.y=blockedX+28,blockedY;p.world.fromX,p.world.fromY=blockedX+28,blockedY;p.world.spawnProgress=1
    end
    local blockedIntent=Intent.normalize({kind="queue_team_job",jobId=inaccessibleJob.id,
        machineId=blockedMachine.id})
    local reachableIntent=Intent.normalize({kind="queue_team_job",jobId=reachableJob.id,
        machineId=blockedMachine.id})
    assert(Employees.command(blockedState,blockedIntent,9))
    assert(Employees.command(blockedState,reachableIntent,9))
    context.machine.reset(blockedState)
    local blockedCutter=context.machine.forId(blockedMachine.id)
    local blockedContext={canClaim=function() return true end,
        operatorPoint=function(_,worker)
            if worker.assignment and worker.assignment.jobId==inaccessibleJob.id then return nil end
            return {x=worker.x,y=worker.y}
        end,
        idlePoint=function(worker) return {x=worker.x,y=worker.y} end,
        move=function(worker,goal)
            worker.x,worker.y=goal.x,goal.y;worker.moving=false;return true
        end}
    local movedPastBlockedJob=false
    local nextJobCutting=false
    for _=1,2400 do
        AI.worker(blockedState,blockedWorker,.1,9.1,blockedContext)
        context.machine.updateAll(.1,blockedState)
        movedPastBlockedJob=movedPastBlockedJob
            or blockedState.employment.teamSchedule.items[1].jobId==reachableJob.id
        if blockedCutter.step=="cutting" and blockedWorker.assignment
            and blockedWorker.assignment.jobId==reachableJob.id then
            nextJobCutting=true;break
        end
    end
    check("blocked_shared_schedule_job_yields_to_next_cutting_job",
        movedPastBlockedJob and nextJobCutting
        and blockedState.employment.teamSchedule.items[2].jobId==inaccessibleJob.id,
        "activity="..tostring(blockedWorker.activity)
            .." assigned="..tostring(blockedWorker.assignment and blockedWorker.assignment.jobId)
            .." cutter="..tostring(blockedCutter.step))
    context.machine.reset(blockedState);context.wrapper.reset(blockedState)

    local orderState=State.new();local orderWorker=hire(orderState)
    orderWorker.cutterSkill=100
    local orderMachine=Fleet.installedUnits(orderState,"polar_115")[1]
    local multiSkidOrder=job(orderState,"JOB-PRODUCTION-BEFORE-WRAPPING",{500,500})
    markDelivered(multiSkidOrder)
    multiSkidOrder.pallets[1].status="cut"
    multiSkidOrder.pallets[1].location="cutter_output"
    local _,_,orderProductionPallet=Schedule.progress(multiSkidOrder)
    local productionStage,_,productionTarget=Schedule.resolve(orderState,orderWorker,
        {jobId=multiSkidOrder.id,machineId=orderMachine.id},multiSkidOrder.pallets[1].id)
    check("schedule_prioritizes_remaining_production_skids_before_wrapping",
        orderProductionPallet==multiSkidOrder.pallets[2] and productionStage=="cutter"
        and productionTarget==multiSkidOrder.pallets[2])
    multiSkidOrder.pallets[2].status="cut"
    multiSkidOrder.pallets[2].location="cutter_output"
    local wrappingStage,_,wrappingTarget=Schedule.resolve(orderState,orderWorker,
        {jobId=multiSkidOrder.id,machineId=orderMachine.id},multiSkidOrder.pallets[1].id)
    check("schedule_enters_wrapping_after_all_order_skids_finish_production",
        wrappingStage=="wrapping" and wrappingTarget==multiSkidOrder.pallets[1])
end

function Test.run(context,check)
    testTransfersAndPackaging(context,check)
    local state=State.new();local w=hire(state);local m=Fleet.installedUnits(state,"polar_115")[1]
    local a=job(state,"JOB-QUEUE-A",{500,500});local b=job(state,"JOB-QUEUE-B",{1000});local c=job(state,"JOB-QUEUE-C")
    check("schedule_fresh_employee_has_valid_empty_queue",Schema.VERSION==21 and Schedule.valid(w.schedule) and #w.schedule.items==0)
    check("schedule_rejects_job_before_delivery",not add(state,w,a,m) and #w.schedule.items==0)
    local firstSkid,_,skidsRemaining=context.PalletLogistics.unload(state,a.id,a.pallets[1].id,
        context.config.palletLogistics.spawnPoints,context.config.palletLogistics.unloadOrigin)
    local partialTeamIntent=Intent.normalize({kind="queue_team_job",jobId=a.id,machineId=m.id})
    local partialTeamQueued=Employees.command(state,partialTeamIntent,9)
    local partialDirectAssignment=Employees.command(state,{kind="assign_employee",employeeId=w.id,
        jobId=a.id,palletId=a.pallets[1].id,machineId=m.id},9)
    check("schedule_waits_until_every_quoted_skid_is_physically_unloaded",firstSkid and skidsRemaining==1
        and not Schedule.stockArrived(a) and not add(state,w,a,m) and not partialTeamQueued
        and not partialDirectAssignment and #w.schedule.items==0 and #state.employment.teamSchedule.items==0)
    deliver(state,a,context);deliver(state,b,context);deliver(state,c,context)
    check("schedule_typed_add_job_is_supported",Intent.normalize({kind="queue_employee_job",employeeId=w.id,jobId=a.id,machineId=m.id})~=nil and add(state,w,a,m))
    add(state,w,b,m)
    local revision=w.schedule.revision
    add(state,w,a,m)
    check("schedule_duplicate_job_submission_does_not_duplicate_work",#w.schedule.items==2 and w.schedule.revision==revision)
    local first,second=w.schedule.items[1].id,w.schedule.items[2].id
    check("schedule_reorder_moves_whole_job",Employees.command(state,{kind="move_employee_job",employeeId=w.id,itemId=second,expectedRevision=revision,direction=-1},9) and w.schedule.items[1].jobId==b.id)
    check("schedule_stale_reorder_is_rejected",not Employees.command(state,{kind="move_employee_job",employeeId=w.id,itemId=second,expectedRevision=revision,direction=1},9) and w.schedule.items[1].id==second)
    check("schedule_invalid_move_does_not_enter_office_protocol",Intent.normalize({kind="move_employee_job",employeeId=w.id,itemId=second,expectedRevision=1,direction=2})==nil)
    Employees.command(state,{kind="move_employee_job",employeeId=w.id,itemId=second,expectedRevision=w.schedule.revision,direction=1},9)
    add(state,w,c,m)
    local last=w.schedule.items[3].id
    check("schedule_remove_retains_bounded_history",Employees.command(state,{kind="remove_employee_job",employeeId=w.id,itemId=last,expectedRevision=w.schedule.revision},9)
        and #w.schedule.items==2 and w.schedule.history[1].result=="removed")
    local saved=Schema.snapshot(state)
    local reopened=State.new()
    check("schedule_queue_and_order_survive_local_save_reload",saved and Schema.validState(saved) and State.applyLocalSave(reopened,{state=saved,slot=1})
        and #reopened.employment.staff[1].schedule.items==0
        and reopened.employment.teamSchedule.items[1].jobId==a.id
        and reopened.employment.teamSchedule.items[2].jobId==b.id
        and not reopened.employment.staff[1].visible)
    check("schedule_new_team_queue_is_present_and_valid",Schedule.valid(state.employment.teamSchedule,true)
        and #state.employment.teamSchedule.items==0 and Employees.valid(state.employment))
    local teamState=State.new()
    local dayWorker,nightWorker=hire(teamState),hire(teamState)
    dayWorker.contract.days,dayWorker.contract.startHour,dayWorker.contract.endHour,dayWorker.contract.startDay=127,9,17,0
    nightWorker.contract.days,nightWorker.contract.startHour,nightWorker.contract.endHour,nightWorker.contract.startDay=127,21,5,0
    local teamMachine=Fleet.installedUnits(teamState,"polar_115")[1]
    local sharedJob=job(teamState,"JOB-SHARED-SHIFTS")
    deliver(teamState,sharedJob,context)
    local sharedX,sharedY=context.CutterZones.inputAnchor(teamState,context.config.cutterPlacement)
    for _,p in ipairs(sharedJob.pallets) do
        p.world.x,p.world.y=sharedX,sharedY;p.world.fromX,p.world.fromY=sharedX,sharedY;p.world.spawnProgress=1
    end
    local teamIntent=Intent.normalize({kind="queue_team_job",jobId=sharedJob.id,machineId=teamMachine.id})
    local teamAdded,teamMessage=Employees.command(teamState,teamIntent,9)
    check("team_schedule_accepts_one_shared_job",teamAdded and teamMessage:find("shop schedule",1,true)
        and #teamState.employment.teamSchedule.items==1 and Schedule.valid(teamState.employment.teamSchedule,true))
    local teamRevision=teamState.employment.teamSchedule.revision
    local duplicateTeam=Employees.command(teamState,teamIntent,9)
    check("team_schedule_duplicate_add_is_idempotent",duplicateTeam and #teamState.employment.teamSchedule.items==1
        and teamState.employment.teamSchedule.revision==teamRevision)
    check("team_schedule_job_cannot_also_enter_a_personal_queue",
        not add(teamState,dayWorker,sharedJob,teamMachine) and #dayWorker.schedule.items==0)
    local teamSave=Schema.snapshot(teamState)
    local teamReload=State.new()
    check("shared_team_queue_survives_local_save_reload",teamSave and State.applyLocalSave(teamReload,{state=teamSave,slot=1})
        and #teamReload.employment.teamSchedule.items==1
        and teamReload.employment.teamSchedule.items[1].jobId==sharedJob.id)
    check("team_queue_protocol_accepts_shared_actions",Intent.normalize({kind="set_team_schedule",enabled=false})~=nil
        and Intent.normalize({kind="move_team_job",itemId="TEAM-TASK-000001",expectedRevision=1,direction=1})~=nil)
    local teamOfficeState=Schema.copy(teamState)
    local officeCallbacks=0
    local office=Office.command({state=teamOfficeState,save=function() officeCallbacks=officeCallbacks+1 end,
        world={validateNetworkWorkshopAccess=function() return true end}})
    local paused,pauseCode=office.perform({}, {id=2},{officeIntent={kind="set_team_schedule",enabled=false}})
    check("team_queue_host_authority_saves_shared_pause",paused and pauseCode=="completed" and officeCallbacks==1
        and not teamOfficeState.employment.teamSchedule.enabled)
    Employees.command(teamState,{kind="set_team_schedule",enabled=false},22)
    Schedule.advance(teamState,nightWorker,22)
    check("paused_team_queue_keeps_jobs_unclaimed",nightWorker.assignment==nil
        and #teamState.employment.teamSchedule.items==1)
    Employees.command(teamState,{kind="set_team_schedule",enabled=true},22)
    Schedule.advance(teamState,dayWorker,22)
    Schedule.advance(teamState,nightWorker,22)
    check("shared_team_queue_assigns_to_worker_on_another_shift",#teamState.employment.teamSchedule.items==1
        and teamState.employment.teamSchedule.items[1].jobId==sharedJob.id
        and nightWorker.assignment and nightWorker.assignment.jobId==sharedJob.id
        and #nightWorker.schedule.items==1 and nightWorker.schedule.items[1].jobId==sharedJob.id
        and dayWorker.assignment==nil and Schedule.valid(teamState.employment.teamSchedule,true)
        and Employees.valid(teamState.employment))
    Schedule.advance(teamState,dayWorker,22)
    check("shared_team_job_cannot_be_claimed_twice",dayWorker.assignment==nil
        and nightWorker.assignment and nightWorker.assignment.jobId==sharedJob.id
        and #teamState.employment.teamSchedule.items==1)
    nightWorker.assignment=nil
    sharedJob.pallets[1].status="wrapped";sharedJob.pallets[1].wrapped=true
    Schedule.advance(teamState,nightWorker,22)
    check("shared_team_completion_is_recorded_in_team_history",
        #nightWorker.schedule.items==0 and nightWorker.schedule.history[1].result=="complete"
        and #teamState.employment.teamSchedule.history==1
        and teamState.employment.teamSchedule.history[1].id=="TEAM-TASK-000001"
        and teamState.employment.teamSchedule.history[1].workerId==nightWorker.id
        and Schedule.valid(teamState.employment.teamSchedule,true) and Employees.valid(teamState.employment)
        and Schema.snapshot(teamState)~=nil)
    local teamHistoryUi=Screen.new();teamHistoryUi.team=true;teamHistoryUi.view="history"
    love.graphics.push("all");local historyDraw=pcall(Screen.draw,teamState,teamHistoryUi,nil,nil,false,nil,false);love.graphics.pop()
    check("shared_team_history_screen_draws",historyDraw)
    local legacy={version=17,slot=1,createdAt=1,updatedAt=1,player={x=500,y=455},state=Schema.copy(saved)}
    legacy.state.employment.version=1;legacy.state.employment.staff[1].schedule=nil
    legacy.state.employment.teamSchedule=nil
    local migrated=Schema.migrate(legacy)
    check("schedule_v17_save_migrates_contract_and_payroll_without_invented_work",migrated and migrated.version==21 and migrated.state.employment.version==6
        and migrated.state.employment.staff[1].contract.wageCents==2200 and #migrated.state.employment.staff[1].schedule.items==0
        and #migrated.state.employment.teamSchedule.items==0 and legacy.state.employment.staff[1].schedule==nil)
    check("schedule_malformed_employment_rejected_without_migration_crash",Employees.normalize(false,0)==nil and Employees.normalize(17,0)==nil and Employees.normalize("invalid",0)==nil)
    local invalid=Schema.copy(saved);invalid.employment.teamSchedule.items[2].id=invalid.employment.teamSchedule.items[1].id
    check("schedule_duplicate_saved_task_ids_are_rejected",not Schema.validState(invalid) and Schema.snapshot(invalid)==nil)
    invalid=Schema.copy(saved);invalid.employment.teamSchedule.items[1].jobId="bad job id"
    check("schedule_malformed_saved_job_id_is_rejected",not Schema.validState(invalid))
    invalid=Schema.copy(saved);invalid.employment.teamSchedule.items[5]=invalid.employment.teamSchedule.items[2]
    check("schedule_sparse_saved_queue_is_rejected",not Schema.validState(invalid))
    local other=hire(state)
    check("schedule_job_cannot_be_queued_for_two_employees",not add(state,other,a,m) and #other.schedule.items==0)
    check("schedule_manual_assignment_cannot_steal_queued_job",not Employees.command(state,{kind="assign_employee",employeeId=other.id,jobId=a.id,palletId=a.pallets[1].id,machineId=m.id},9))
    c.difficulty="hard"
    check("schedule_low_skill_can_queue_hard_cutter_jobs",Schedule.canQueue(state,w,c.id,m.id))
    c.press={}
    check("schedule_skill_gates_match_cutter_press_and_wrapping_stages",
        not Schedule.skillAllows(w,c,"cutter") and not Schedule.skillAllows(w,c,"press")
        and not Schedule.skillAllows(w,c,"wrapping"))
    c.press=nil
    local hardSkills=Schedule.minimumSkills(c)
    check("schedule_minimum_skill_requirements_match_hard_cutting_job",
        hardSkills.cutter==80 and hardSkills.press==nil and hardSkills.wrapping==70)
    c.difficulty="medium";c.press={};local mediumSkills=Schedule.minimumSkills(c)
    check("schedule_minimum_skill_requirements_include_printing_stage",
        mediumSkills.cutter==50 and mediumSkills.press==60 and mediumSkills.wrapping==50)
    c.press=nil
    c.difficulty="easy"
    check("schedule_easy_cutting_job_has_no_cutter_minimum",
        Schedule.minimumSkills(c).cutter==0 and Schedule.minimumSkills(c).wrapping==25)
    local lowProofState=State.new()
    local lowProof=Windmill.ensure(lowProofState)
    lowProof.status,lowProof.proofQuality,lowProof.artworkVerified="proof",.78,true
    local ownerApproval=Windmill.approveProof(lowProofState)
    local employeeApproval=Windmill.approveProof(lowProofState,true)
    check("low_skill_employee_can_continue_with_lower_quality_proof",
        not ownerApproval and employeeApproval and lowProof.proofApproved
        and lowProof.proofQuality==.78)
    local callbacks=0
    local guestState=Schema.copy(state)
    local guestWorker=guestState.employment.staff[1]
    local office=Office.command({state=guestState,save=function() callbacks=callbacks+1 end,world={validateNetworkWorkshopAccess=function() return true end}})
    local guestQueued,queueCode=office.perform({}, {id=2},{officeIntent={kind="queue_employee_job",employeeId=guestWorker.id,jobId=c.id,machineId=m.id}})
    check("schedule_guest_can_queue_jobs",guestQueued and queueCode=="completed" and callbacks==1
        and guestWorker.schedule.items[3].jobId==c.id)
    local guestPaused,pauseCode=office.perform({}, {id=2},{officeIntent={kind="set_employee_schedule",employeeId=guestWorker.id,enabled=false}})
    check("schedule_guest_can_pause_workers",guestPaused and pauseCode=="completed" and callbacks==2 and not guestWorker.schedule.enabled)
    Employees.command(state,{kind="set_employee_schedule",employeeId=w.id,enabled=false},9)
    check("schedule_paused_queue_does_not_dispatch",not Schedule.advance(state,w,9) and w.assignment==nil and #w.schedule.items==2)
    Employees.command(state,{kind="set_employee_schedule",employeeId=w.id,enabled=true},9)
    check("schedule_off_shift_does_not_dispatch",not Schedule.advance(state,w,17) and w.assignment==nil)
    w.visible=false
    check("schedule_off_site_does_not_dispatch",not Schedule.advance(state,w,9) and w.assignment==nil);w.visible=true
    w.weeks={{week=-3,dueAtHours=0,paidHours=1,earnedCents=2200,paidCents=0,notified=false}}
    check("schedule_overdue_wages_stop_new_dispatch",not Schedule.advance(state,w,9) and w.assignment==nil)
    w.weeks={}
    -- Work that needs pallet transfer stays first in the shared queue for the
    -- assigned worker instead of being skipped as a blocked cutter job.
    AI.worker(state,w,.1,9,{idlePoint=function(actor) return {x=actor.x,y=actor.y} end})
    check("schedule_unstaged_first_job_stays_assigned_for_worker_transfer",
        w.assignment and w.assignment.jobId==a.id and #w.schedule.items==2
        and w.schedule.items[1].jobId==a.id)
    check("schedule_unstaged_first_job_remains_in_original_queue_order",
        not Schedule.isLocked(state,w,w.schedule.items[1]) or w.assignment.scheduleItemId==w.schedule.items[1].id)
    local ix,iy=context.CutterZones.inputAnchor(state,context.config.cutterPlacement)
    local function stage(p)
        p.world.x,p.world.y=ix,iy;p.world.fromX,p.world.fromY=ix,iy;p.world.spawnProgress=1
    end
    for _,j in ipairs({a,b}) do for _,p in ipairs(j.pallets) do stage(p) end end
    w._scheduleRetryAtHours=nil
    a.pallets[1].world.x=ix+240
    a.pallets[1].world.fromX,a.pallets[1].world.fromY=ix+240,iy
    Schedule.advance(state,w,9.1)
    check("schedule_keeps_first_cutter_job_selected_when_its_pallet_needs_moving",
        w.assignment and w.assignment.jobId==a.id
        and w.schedule.items[1].jobId==a.id and w.schedule.items[2].jobId==b.id)
    w.assignment=nil
    stage(a.pallets[1]);w._scheduleRetryAtHours=nil
    context.machine.reset(state)
    Schedule.advance(state,w,9.1)
    local cutter=context.machine.forId(m.id);local oldResolver=cutter.outputResolver
    local outputClear=false
    cutter.setOutputResolver(function()
        if outputClear then return {x=state.wrapper.x+80,y=state.wrapper.y,direction="northwest"} end
        return nil,"Clear output"
    end)
    local wc={canClaim=function() return true end,operatorPoint=function() return {x=700,y=470} end,
        move=function(actor,goal) actor.x,actor.y=goal.x,goal.y;actor.moving=false;return true end}
    for i=1,800 do
        Work.update(state,w,.1,wc);context.machine.updateAll(.1,state)
        if cutter.step=="cutting" then break end
    end
    Employees.command(state,{kind="set_employee_schedule",employeeId=w.id,enabled=false},9)
    AI.worker(state,w,.1,9,{})
    check("schedule_pause_waits_for_running_blade_to_finish",w.assignment and w.reserved and w.stopRequested and not w.schedule.enabled)
    for i=1,100 do context.machine.updateAll(.1,state);if Work.safe(w) then break end end
    AI.worker(state,w,.1,9,{idlePoint=function(actor) return {x=actor.x,y=actor.y} end})
    check("schedule_pause_releases_safely_and_keeps_job_order",w.assignment==nil and not w.reserved and #w.schedule.items==2 and w.schedule.items[1].id==first)
    check("schedule_loaded_job_cannot_be_removed_during_pause",not Employees.command(state,{kind="remove_employee_job",employeeId=w.id,itemId=first,expectedRevision=w.schedule.revision},9))
    Employees.command(state,{kind="set_employee_schedule",employeeId=w.id,enabled=true},9)
    Schedule.advance(state,w,9)
    check("schedule_resume_continues_same_pallet",w.assignment and w.assignment.palletId==a.pallets[1].id and w.assignment.scheduleItemId==first)
    -- This scenario verifies queue completion; give its operator the wrapping skill it needs.
    w.wrappingSkill=50
    local firstWrapObserved,allProductionDoneAtFirstWrap=false,false
    local nextJobStartedEarly,allOrderWrappedBeforeNextJob=false,false
    for i=1,1600 do
        Schedule.advance(state,w,9);Work.update(state,w,.1,wc);context.machine.updateAll(.1,state)
        if cutter.step=="cut_complete" and a.pallets[1].remainingSheets==0 then break end
    end
    check("schedule_blocked_output_does_not_finish_job_or_skip_ahead",a.pallets[1].location=="at_cutter" and #w.schedule.items==2 and w.schedule.items[1].jobId==a.id and #w.schedule.history==1 and w.assignment.jobId==a.id)
    outputClear=true
    local sawNextJob=false
    for i=1,6000 do
        Schedule.advance(state,w,9);Work.update(state,w,.1,wc);context.machine.updateAll(.1,state);context.wrapper.updateAll(.1,state)
        local anyOrderSkidWrapped=false
        local allOrderProductionDone=true
        local allOrderWrapped=true
        for _,orderPallet in ipairs(a.pallets) do
            anyOrderSkidWrapped=anyOrderSkidWrapped or orderPallet.status=="wrapped"
            allOrderProductionDone=allOrderProductionDone
                and (orderPallet.status=="wrapped" or Schedule.stage(a,orderPallet)=="wrapping")
            allOrderWrapped=allOrderWrapped and orderPallet.status=="wrapped"
        end
        if anyOrderSkidWrapped and not firstWrapObserved then
            firstWrapObserved=true
            allProductionDoneAtFirstWrap=allOrderProductionDone
        end
        if w.assignment and w.assignment.jobId==b.id then
            sawNextJob=true
            if not allOrderWrapped then nextJobStartedEarly=true end
            allOrderWrappedBeforeNextJob=allOrderWrapped
        end
        if #w.schedule.items==0 and not w.assignment then break end
    end
    check("schedule_finishes_every_skid_before_wrapping_the_work_order",
        firstWrapObserved and allProductionDoneAtFirstWrap
        and a.pallets[1].finishedSheets==500 and a.pallets[2].finishedSheets==500,
        tostring(firstWrapObserved).." allProduction="..tostring(allProductionDoneAtFirstWrap)
            .." "..a.pallets[1].status.." / "..a.pallets[2].status.." "..cutter.step.." "..w.activity)
    check("schedule_wraps_the_whole_work_order_before_starting_next_job",
        sawNextJob and allOrderWrappedBeforeNextJob and not nextJobStartedEarly)
    check("schedule_automatically_advances_to_next_real_job",sawNextJob and b.pallets[1].finishedSheets==1000 and b.pallets[1].completedLifts==2 and b.pallets[1].status=="wrapped")
    check("schedule_exhausted_queue_records_exactly_one_completion_each",#w.schedule.items==0 and #w.schedule.history==3 and w.schedule.history[2].jobId==a.id and w.schedule.history[3].jobId==b.id
        and w.schedule.history[2].result=="complete" and w.schedule.history[3].result=="complete" and state.inventory.finishedPallets==3)
    Schedule.advance(state,w,9);Schedule.advance(state,w,9)
    check("schedule_completion_cannot_duplicate_stock_or_history",#w.schedule.history==3 and state.inventory.finishedPallets==3 and w.assignment==nil)
    local final=Schema.snapshot(state)
    check("schedule_finished_jobs_survive_save_reload_without_restarting",final and State.applyLocalSave(reopened,{state=final,slot=1}) and #reopened.employment.staff[1].schedule.items==0 and #reopened.employment.staff[1].schedule.history==3)
    cutter.setOutputResolver(oldResolver);context.machine.reset(state)
    -- Closed jobs leave a visible history record; unavailable cutters block
    -- the first job rather than discarding it or silently changing its machine.
    local closed=State.new();local cw=hire(closed);local cm=Fleet.installedUnits(closed,"polar_115")[1]
    local removed=job(closed,"JOB-CANCELLED");local nextJob=job(closed,"JOB-AFTER-CANCEL")
    deliver(closed,removed,context);deliver(closed,nextJob,context)
    local closedX,closedY=context.CutterZones.inputAnchor(closed,context.config.cutterPlacement)
    for _,p in ipairs(nextJob.pallets) do
        p.world.x,p.world.y=closedX,closedY;p.world.fromX,p.world.fromY=closedX,closedY;p.world.spawnProgress=1
    end
    add(closed,cw,removed,cm);add(closed,cw,nextJob,cm);table.remove(closed.jobs.active,1)
    Schedule.advance(closed,cw,9)
    check("schedule_cancelled_job_is_recorded_and_next_job_dispatches",cw.schedule.history[1].result=="unavailable" and cw.assignment.jobId==nextJob.id)
    cw.assignment=nil
    local sold,saleMessage=Fleet.sell(closed,cm.id,"online");assert(sold,saleMessage)
    Schedule.advance(closed,cw,9)
    check("schedule_missing_machine_waits_without_losing_job",cw.assignment==nil and #cw.schedule.items==1 and cw.activity:find("unavailable",1,true),cw.activity.." "..tostring(cw.assignment and cw.assignment.jobId))
    local bounded=State.new();local bw=hire(bounded);local bm=Fleet.installedUnits(bounded,"polar_115")[1]
    local lastAddMessage
    for i=1,17 do local j=job(bounded,"JOB-LIMIT-"..i);markDelivered(j);local added,message=add(bounded,bw,j,bm);if not added then lastAddMessage=message end end
    check("schedule_queue_is_bounded_to_16_jobs",#bw.schedule.items==16 and Schedule.valid(bw.schedule),
        "count="..#bw.schedule.items.." last="..tostring(lastAddMessage))
    -- Exercise actual Computer dispatch, including guests and all views.
    local computer=context.computerScreen.new()
    computer.configureWarehouse({enabled=true})
    computer.enter(bounded)
    local x,y=computer.dropdownCenter();computer.mousepressed(bounded,x,y,1)
    x,y=computer.tabCenter("schedule")
    check("schedule_computer_dropdown_opens_schedule_tab",computer.mousepressed(bounded,x,y,1).action=="tab" and computer.tab=="schedule")
    x,y=computer.tabCenter("warehouse")
    check("schedule_expanded_dropdown_fits_screen",x and y+17.5<644)
    local function draw(name,view,page)
        computer.schedule.view=view;computer.schedule.page=page or 1
        love.graphics.push("all");local okay,errorMessage=pcall(computer.draw,bounded,nil,nil,context.assets);love.graphics.pop()
        check(name,okay,tostring(errorMessage))
    end
    draw("schedule_queue_page_draws","queue");draw("schedule_last_queue_page_draws","queue",4)
    draw("schedule_add_job_page_draws","add");draw("schedule_history_page_draws","history")
    computer.schedule.view="queue";computer.schedule.page=1
    x,y=Screen.buttonCenter("run")
    check("schedule_ui_pause_uses_authoritative_shared_employment_command",
        computer.mousepressed(bounded,x,y,1).action=="employment_changed" and not bounded.employment.teamSchedule.enabled)
    local guestIntents={}
    local guest=context.computerScreen.new({remoteCommand=function(intent) guestIntents[#guestIntents+1]=intent end});guest.tab="schedule"
    check("schedule_guest_ui_submits_shared_schedule_resume",guest.mousepressed(bounded,x,y,1).action=="remote_pending"
        and guestIntents[1] and guestIntents[1].kind=="set_team_schedule" and guestIntents[1].enabled==true
        and not bounded.employment.teamSchedule.enabled)
    check("schedule_ui_exposes_one_day_night_schedule",
        computer.schedule.team==true and Screen.buttonCenter("team")==nil)
    computer.schedule.view="queue"
    draw("schedule_single_shared_queue_draws","queue")
    check("schedule_guest_uses_the_same_day_night_schedule",guest.schedule.team==true
        and Screen.buttonCenter("team")==nil)
    x,y=Screen.buttonCenter("run")
    check("schedule_guest_ui_submits_shared_team_resume",guest.mousepressed(bounded,x,y,1).action=="remote_pending"
        and guestIntents[2] and guestIntents[2].kind=="set_team_schedule" and guestIntents[2].enabled==true)
    local empty=State.new();computer.tab="schedule"
    love.graphics.push("all");local emptyOkay=pcall(computer.draw,empty,nil,nil,context.assets);love.graphics.pop()
    check("schedule_empty_shop_explains_hiring_first",emptyOkay)
    while #bw.schedule.items>0 do
        Employees.command(bounded,{kind="remove_employee_job",employeeId=bw.id,itemId=bw.schedule.items[1].id,expectedRevision=bw.schedule.revision},9)
    end
    for i=1,40 do
        add(bounded,bw,bounded.jobs.active[1],bm)
        Employees.command(bounded,{kind="remove_employee_job",employeeId=bw.id,itemId=bw.schedule.items[1].id,expectedRevision=bw.schedule.revision},9)
    end
    check("schedule_history_retains_latest_32_without_reusing_task_ids",#bw.schedule.history==32 and bw.schedule.history[1].id=="TASK-000025"
        and bw.schedule.history[32].id=="TASK-000056" and bw.schedule.nextId==57 and Schema.snapshot(bounded)~=nil)

    local function shiftTerms(worker,startHour,endHour)
        worker.contract.days=127
        worker.contract.startHour=startHour
        worker.contract.endHour=endHour
        worker.contract.startDay=0
    end
    local function handoff(label,sourceStart,sourceEnd,targetStart,targetEnd,now)
        local handoffState=State.new()
        local outgoing,incoming=hire(handoffState),hire(handoffState)
        shiftTerms(outgoing,sourceStart,sourceEnd);shiftTerms(incoming,targetStart,targetEnd)
        outgoing.x,outgoing.y=645,235
        local handoffMachine=Fleet.installedUnits(handoffState,"polar_115")[1]
        local handoffJob=job(handoffState,"JOB-SHIFT-"..label)
        deliver(handoffState,handoffJob,context)
        assert(add(handoffState,outgoing,handoffJob,handoffMachine))
        local row=outgoing.schedule.items[1]
        outgoing.assignment={jobId=handoffJob.id,palletId=handoffJob.pallets[1].id,
            machineId=handoffMachine.id,scheduleItemId=row.id}
        AI.worker(handoffState,outgoing,.1,now,{})
        local first=incoming.schedule.items[1]
        check("schedule_"..label.."_unfinished_job_rolls_to_next_shift",not outgoing.assignment
            and #outgoing.schedule.items==0 and first and first.jobId==handoffJob.id
            and Schedule.valid(outgoing.schedule) and Schedule.valid(incoming.schedule)
            and Employees.valid(handoffState.employment))
    end
    handoff("day_to_night",9,21,21,9,21)
    handoff("night_to_day",21,9,9,21,33)

    local nightState=State.new()
    local nightWorker=hire(nightState)
    shiftTerms(nightWorker,21,5)
    nightWorker.visible=false;nightWorker.clockedIn=false;nightWorker.phase="hidden"
    local nightMachine=Fleet.installedUnits(nightState,"polar_115")[1]
    local nightJob=job(nightState,"JOB-NIGHT-WORK")
    deliver(nightState,nightJob,context)
    nightWorker.cutterSkill=100
    local nightIntent=Intent.normalize({kind="queue_team_job",jobId=nightJob.id,machineId=nightMachine.id})
    assert(Employees.command(nightState,nightIntent,22))
    local nightX,nightY=context.CutterZones.inputAnchor(nightState,context.config.cutterPlacement)
    for _,p in ipairs(nightJob.pallets) do
        p.world.x,p.world.y=nightX,nightY;p.world.fromX,p.world.fromY=nightX,nightY;p.world.spawnProgress=1
    end
    context.machine.reset(nightState)
    local previousEmployeeOptions=context.world._employeeOptions
    context.world.configureEmployees({players=function() return {} end})
    local navigationContext=context.world.employeeContext(nightState,context.assets)
    local nightTarget=navigationContext.operatorPoint(nightMachine.id,nightWorker)
    context.world.configureEmployees(previousEmployeeOptions)
    local startX,startY=nightWorker.x,nightWorker.y
    if nightTarget then
        for _=1,300 do
            AI.worker(nightState,nightWorker,.1,22,navigationContext)
            if math.sqrt((nightWorker.x-nightTarget.x)^2+(nightWorker.y-nightTarget.y)^2)<5 then break end
        end
    end
    check("night_shift_worker_starts_queue_and_walks_to_cutter",nightTarget~=nil and nightWorker.visible
        and nightWorker.clockedIn and nightWorker.assignment and nightWorker.assignment.jobId==nightJob.id
        and math.sqrt((nightWorker.x-nightTarget.x)^2+(nightWorker.y-nightTarget.y)^2)<5
        and (nightWorker.x~=startX or nightWorker.y~=startY))
    local nightCutter=context.machine.forId(nightMachine.id)
    local nightCutStarted=false
    for _=1,2000 do
        AI.worker(nightState,nightWorker,.1,22,navigationContext)
        context.machine.updateAll(.1,nightState)
        if nightCutter.step=="cutting" then nightCutStarted=true;break end
    end
    check("night_shift_worker_starts_cutting_from_the_shared_schedule",
        nightCutStarted and nightWorker.assignment and nightWorker.assignment.jobId==nightJob.id
        and nightJob.pallets[1].location=="at_cutter",
        "activity="..tostring(nightWorker.activity)
            .." phase="..tostring(nightWorker.phase)
            .." position="..tostring(nightWorker.x)..","..tostring(nightWorker.y)
            .." cutter="..tostring(nightCutter.step))
    context.machine.reset(nightState)
end
return Test
