local State=require("src.state")
local Schema=require("src.save_schema")
local Employees=require("src.employees")
local Schedule=require("src.employee_schedule")
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
    Employees.command(state,{kind="offer_employee",applicationId=a.id,expectedRevision=a.revision,wageCents=2200,days=31,startHour=9,endHour=17},.5)
    Employees.advance(state,1.25)
    assert(Employees.command(state,{kind="hire_employee",applicationId=a.id,expectedRevision=a.revision},1.25))
    local w=state.employment.staff[#state.employment.staff]
    -- This schedule fixture represents a worker already trained for the full
    -- cutter-to-shipping workflow.
    w.pressSkill,w.wrappingSkill=60,50
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
function Test.run(context,check)
    local state=State.new();local w=hire(state);local m=Fleet.installedUnits(state,"polar_115")[1]
    local a=job(state,"JOB-QUEUE-A",{500,500});local b=job(state,"JOB-QUEUE-B",{1000});local c=job(state,"JOB-QUEUE-C")
    check("schedule_fresh_employee_has_valid_empty_queue",Schema.VERSION==21 and Schedule.valid(w.schedule) and #w.schedule.items==0)
    check("schedule_rejects_job_before_delivery",not add(state,w,a,m) and #w.schedule.items==0)
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
        and reopened.employment.staff[1].schedule.items[1].id==first and reopened.employment.staff[1].schedule.items[2].id==second
        and not reopened.employment.staff[1].visible)
    local legacy={version=17,slot=1,createdAt=1,updatedAt=1,player={x=500,y=455},state=Schema.copy(saved)}
    legacy.state.employment.version=1;legacy.state.employment.staff[1].schedule=nil
    local migrated=Schema.migrate(legacy)
    check("schedule_v17_save_migrates_contract_and_payroll_without_invented_work",migrated and migrated.version==21 and migrated.state.employment.version==6
        and migrated.state.employment.staff[1].contract.wageCents==2200 and #migrated.state.employment.staff[1].schedule.items==0
        and legacy.state.employment.staff[1].schedule==nil)
    check("schedule_malformed_employment_rejected_without_migration_crash",Employees.normalize(false,0)==nil and Employees.normalize(17,0)==nil and Employees.normalize("invalid",0)==nil)
    local invalid=Schema.copy(saved);invalid.employment.staff[1].schedule.items[2].id=first
    check("schedule_duplicate_saved_task_ids_are_rejected",not Schema.validState(invalid) and Schema.snapshot(invalid)==nil)
    invalid=Schema.copy(saved);invalid.employment.staff[1].schedule.items[1].jobId="bad job id"
    check("schedule_malformed_saved_job_id_is_rejected",not Schema.validState(invalid))
    invalid=Schema.copy(saved);invalid.employment.staff[1].schedule.items[5]=invalid.employment.staff[1].schedule.items[2]
    check("schedule_sparse_saved_queue_is_rejected",not Schema.validState(invalid))
    local other=hire(state)
    check("schedule_job_cannot_be_queued_for_two_employees",not add(state,other,a,m) and #other.schedule.items==0)
    check("schedule_manual_assignment_cannot_steal_queued_job",not Employees.command(state,{kind="assign_employee",employeeId=other.id,jobId=a.id,palletId=a.pallets[1].id,machineId=m.id},9))
    c.difficulty="hard"
    check("schedule_skill_requirement_applies_when_adding",not add(state,w,c,m));c.difficulty="easy"
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
    -- Blocked work stays queued while the worker waits at its selected cutter.
    AI.worker(state,w,.1,9,{idlePoint=function(actor) return {x=actor.x,y=actor.y} end})
    check("schedule_unstaged_job_waits_without_false_assignment",w.assignment==nil and w._waitingMachineId==m.id
        and w.activity=="Stage the assigned pallet beside the selected cutter" and #w.schedule.items==2)
    check("schedule_unstaged_job_remains_editable",not Schedule.isLocked(state,w,w.schedule.items[1]))
    local ix,iy=context.CutterZones.inputAnchor(state,context.config.cutterPlacement)
    local function stage(p)
        p.world.x,p.world.y=ix,iy;p.world.fromX,p.world.fromY=ix,iy;p.world.spawnProgress=1
    end
    for _,j in ipairs({a,b}) do for _,p in ipairs(j.pallets) do stage(p) end end
    w._scheduleRetryAtHours=nil
    a.pallets[1].world.x=ix+240
    Schedule.advance(state,w,9.1)
    check("schedule_skips_blocked_first_job_for_ready_next_job",w.assignment and w.assignment.jobId==b.id
        and w.schedule.items[1].jobId==b.id and w.schedule.items[2].jobId==a.id)
    w.assignment=nil
    w.schedule.items[1],w.schedule.items[2]=w.schedule.items[2],w.schedule.items[1]
    w.schedule.revision=w.schedule.revision+1
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
    local firstPalletCheckpoint=false
    for i=1,1600 do
        Schedule.advance(state,w,9);Work.update(state,w,.1,wc);context.machine.updateAll(.1,state)
        if cutter.step=="cut_complete" and a.pallets[1].remainingSheets==0 then break end
    end
    check("schedule_blocked_output_does_not_finish_job_or_skip_ahead",a.pallets[1].location=="at_cutter" and #w.schedule.items==2 and w.schedule.items[1].jobId==a.id and #w.schedule.history==1 and w.assignment.jobId==a.id)
    outputClear=true
    local sawNextJob=false
    for i=1,3000 do
        Schedule.advance(state,w,9);Work.update(state,w,.1,wc);context.machine.updateAll(.1,state);context.wrapper.updateAll(.1,state)
        if a.pallets[1].status=="cut" and a.pallets[2].status~="cut" then
            firstPalletCheckpoint=firstPalletCheckpoint or #w.schedule.items==2 and w.schedule.items[1].jobId==a.id
        end
        if w.assignment and w.assignment.jobId==b.id then sawNextJob=true end
        if #w.schedule.items==0 and not w.assignment then break end
    end
    check("schedule_finishes_every_pallet_before_next_job",firstPalletCheckpoint and a.pallets[1].finishedSheets==500 and a.pallets[2].finishedSheets==500,
        tostring(firstPalletCheckpoint).." "..a.pallets[1].status.." "..a.pallets[1].location.." "
            ..tostring(a.pallets[1].world and a.pallets[1].world.x)..","..tostring(a.pallets[1].world and a.pallets[1].world.y)
            .." wrapper="..tostring(state.wrapper.x)..","..tostring(state.wrapper.y).." "
            ..a.pallets[2].status.." "..cutter.step.." "..w.activity)
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
    check("schedule_ui_pause_uses_authoritative_employment_command",computer.mousepressed(bounded,x,y,1).action=="employment_changed" and not bw.schedule.enabled)
    local guestIntents={}
    local guest=context.computerScreen.new({remoteCommand=function(intent) guestIntents[#guestIntents+1]=intent end});guest.tab="schedule"
    check("schedule_guest_ui_submits_pause_or_resume",guest.mousepressed(bounded,x,y,1).action=="remote_pending"
        and guestIntents[1] and guestIntents[1].kind=="set_employee_schedule" and not bw.schedule.enabled)
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
    assert(add(nightState,nightWorker,nightJob,nightMachine))
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
    context.machine.reset(nightState)
end
return Test
