-- Uses App.update, real EmployeeAI navigation, machine safety controls and
-- payroll. Only fixture placement/time is artificial; no worker teleports or
-- production functions are replaced during the measured simulation.
local Calendar=require("src.business_calendar")
local Employees=require("src.employees")
local Schema=require("src.save_schema")
local Fleet=require("src.machine_fleet")
local Fixture={}
local function hours(s,h)
    s.calendar=Calendar.dateFromHours(h)
    s.calendar.elapsed=(h%24)/24*Calendar.secondsPerDay(s)
end
function Fixture.setup(R,unattended)
    assert(R.startGame(R.Save.newGame(3),"background-probe"))
    local s=R.state;s.activeSlot=nil;s.screen="computer";s.employment.recruiting=false;s.money=100000
    local a=assert(Employees.createApplicant(s,0));assert(Employees.requestResume(s,a.id,0))
    Employees.advance(s,.5)
    assert(Employees.command(s,{kind="offer_employee",applicationId=a.id,expectedRevision=a.revision,
        wageCents=10000,days=31,startHour=9,endHour=17},.5))
    Employees.advance(s,1.25)
    assert(Employees.command(s,{kind="hire_employee",applicationId=a.id,expectedRevision=a.revision},1.25))
    local worker=s.employment.staff[1]
    local machine=Fleet.installedUnits(s,"polar_115")[1]
    local job=assert(R.Jobs.createOffer({id="JOB-BACKGROUND-PRODUCTION",company="Background acceptance",
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500}}))
    R.Jobs.accept(job);s.jobs.active[1]=job;job.status="in_production";job.delivery={status="received"}
    local pallet=job.pallets[1]
    local x,y=require("src.cutter_zones").inputAnchor(s,R.Config.cutterPlacement)
    pallet.location="warehouse";pallet.status="raw"
    pallet.world={x=x,y=y,fromX=x,fromY=y,spawnProgress=1,direction="northwest"}
    hours(s,9.25);s.employment.lastAtHours=9.25
    worker.visible=true;worker.clockedIn=true;worker.phase="idle";worker.shiftDay=0;worker.breaksTaken=7
    worker.cutterSkill,worker.pressSkill,worker.wrappingSkill=100,100,100
    R.World.player.x,R.World.player.y=740,620
    R.World.player.sceneId=unattended and "home" or "warehouse"
    if unattended then s.home.visit={kind="outing",scene="home"} end
    -- Both CPU rows keep the same open-menu path after fixture placement.
    R._weekendScene=R.World.player.sceneId
    local context=R.World.employeeContext(s,R.Assets)
    local point=assert(context.operatorPoint(machine.id,worker),"Real cutter contact must exist")
    worker.x,worker.y=point.x,point.y
    R.Machine.reset(s)
    assert(Employees.command(s,{kind="assign_employee",employeeId=worker.id,jobId=job.id,
        palletId=pallet.id,machineId=machine.id},9.25))
    R.World.customer.timer=10000;R.World.vendor.timer=10000
    R.App.gameClockSpeed=1
    return worker,job,pallet,machine
end
function Fixture.run(R,unattended,frames)
    local worker,job,pallet,machine=Fixture.setup(R,unattended)
    local samples={};collectgarbage("collect")
    local firstDone
    for index=1,frames or 3600 do
        local start=love.timer.getTime();R.App.update(1/60)
        samples[index]=(love.timer.getTime()-start)*1000
        if not firstDone and pallet.finishedSheets==500 then firstDone=index/60 end
    end
    -- The owner entering the shop flushes only its final partial interval.
    local before=R.World.backgroundSimulationStats()
    R.World.player.sceneId="warehouse";R.state.home.visit=nil;R.App.update(0)
    local earned,hoursPaid=0,0
    for _,row in ipairs(worker.weeks) do earned=earned+row.earnedCents;hoursPaid=hoursPaid+row.paidHours end
    table.sort(samples);local total=0;for _,ms in ipairs(samples)do total=total+ms end
    return {mode=unattended and "unattended" or "observed",samples=#samples,mean_ms=total/#samples,
        p95_ms=samples[math.ceil(#samples*.95)],max_ms=samples[#samples],world_steps=before.steps,
        background_steps=before.backgroundSteps,pending_before_return=before.pendingGame,
        pending_after_return=R.World.backgroundSimulationStats().pendingGame,
        calendar=Calendar.absoluteHours(R.state),earned_cents=earned,paid_hours=hoursPaid,money=R.state.money,
        completed_lifts=pallet.completedLifts,finished_sheets=pallet.finishedSheets,remaining_sheets=pallet.remainingSheets,
        cut_history=pallet.paper and #pallet.paper.history or 0,first_finished_seconds=firstDone,
        machine_step=R.Machine.forId(machine.id).step,worker_activity=worker.activity,worker_phase=worker.phase,
        inventory=Schema.copy(R.state.inventory),assignment=worker.assignment and worker.assignment.jobId}
end
function Fixture.verify(R,check,rows)
    local previous=Schema.copy(R.state);local player=R.World.snapshot();local speed=R.App.gameClockSpeed
    local oldScene,oldPrompt=R._weekendScene,R._weekendPromptToken
    local okay,reason=xpcall(function()
        local observed=Fixture.run(R,false);local unattended=Fixture.run(R,true)
        if rows then rows[#rows+1]=observed;rows[#rows+1]=unattended end
        local function near(a,b) return math.abs(a-b)<1e-5 end
        check("background_real_employee_finishes_cutter_job",observed.finished_sheets==500 and unattended.finished_sheets==500,
            observed.machine_step.."/"..unattended.machine_step.." "..tostring(unattended.worker_activity))
        check("background_real_cut_history_and_stock_match",observed.completed_lifts==unattended.completed_lifts
            and observed.cut_history==unattended.cut_history and observed.remaining_sheets==unattended.remaining_sheets)
        check("background_real_employee_wages_and_clock_match",near(observed.earned_cents,unattended.earned_cents)
            and near(observed.paid_hours,unattended.paid_hours) and near(observed.calendar,unattended.calendar),
            observed.earned_cents.."/"..unattended.earned_cents)
        check("background_real_services_reduce_calls",unattended.world_steps<observed.world_steps*.3 and unattended.background_steps>0,
            observed.world_steps.."/"..unattended.world_steps)
        check("background_real_return_has_no_unapplied_work",unattended.pending_after_return==0)
        check("background_real_finance_and_finished_inventory_match",observed.money==unattended.money
            and observed.inventory.finishedPallets==unattended.inventory.finishedPallets)
        local before=R.World.backgroundSimulationStats().steps
        local wasRemote=R.multiplayer.remotePlayers
        R.multiplayer.remotePlayers=function()return {{id=2,sceneId="front_left",x=300,y=300}} end
        R.World.player.sceneId="home";R.state.home.visit={kind="outing",scene="home"}
        local okayGuest,guestError=pcall(R.App.update,.01)
        R.multiplayer.remotePlayers=wasRemote
        check("background_runtime_human_guest_in_shop_keeps_full_cadence",okayGuest
            and not R.World.backgroundSimulationStats().background
            and R.World.backgroundSimulationStats().steps==before+1,tostring(guestError))
        local oldClient=R.multiplayer.isClient;local beforeHours=Calendar.absoluteHours(R.state)
        before=R.World.backgroundSimulationStats().steps
        R.multiplayer.isClient=function()return true end
        local okayClient,clientError=pcall(R.App.update,.25)
        R.multiplayer.isClient=oldClient
        check("background_runtime_client_does_not_advance_authoritative_services",okayClient
            and Calendar.absoluteHours(R.state)==beforeHours
            and R.World.backgroundSimulationStats().steps==before,tostring(clientError))
        local openingWorker,openingJob,openingPallet,openingMachine=Fixture.setup(R,true)
        local Flow=require("src.weekend_flow");local state=R.state
        local returnAt=Flow.returnAtHours(state.home.weekend)
        state.home.weekend.phase="ready";state.home.weekend.closedAtHours=state.home.weekend.closesAtHours
        hours(state,returnAt);state.calendar.elapsed=state.calendar.elapsed-.02
        state.employment.lastAtHours=returnAt-.5
        openingWorker.visible=false;openingWorker.clockedIn=false;openingWorker.phase="hidden"
        openingWorker.contract.startHour=7;openingWorker.contract.endHour=15
        R.App.update(.05)
        check("background_runtime_monday_boundary_keeps_closed_interval_out_of_production",
            near(Calendar.absoluteHours(state),returnAt) and state.home.weekend.phase=="working"
            and near(state.employment.lastAtHours,returnAt) and not openingWorker.clockedIn
            and R.World.backgroundSimulationStats().steps==0 and openingPallet.completedLifts==0,
            string.format("now=%.10f target=%.10f phase=%s last=%.10f clocked=%s steps=%d lifts=%s",
                Calendar.absoluteHours(state),returnAt,state.home.weekend.phase,state.employment.lastAtHours,
                tostring(openingWorker.clockedIn),R.World.backgroundSimulationStats().steps,tostring(openingPallet.completedLifts)))
        local earned=0;for _,week in ipairs(openingWorker.weeks) do earned=earned+week.earnedCents end
        check("background_runtime_monday_creates_no_closed_hour_wages",earned==0)
        R.App.update(0);R.App.update(.07)
        check("background_runtime_monday_retained_time_runs_real_open_shop",
            near(Calendar.absoluteHours(state),returnAt+.1*24/Calendar.secondsPerDay(state))
            and R.World.backgroundSimulationStats().backgroundSteps==1 and not openingWorker.clockedIn
            and near(state.employment.lastAtHours,Calendar.absoluteHours(state))
            and not R.World.hasBackgroundClockDebt(),
            string.format("now=%.10f expected=%.10f bgsteps=%d clocked=%s debt=%s activity=%s",
                Calendar.absoluteHours(state),returnAt+.1*24/Calendar.secondsPerDay(state),
                R.World.backgroundSimulationStats().backgroundSteps,tostring(openingWorker.clockedIn),
                tostring(R.World.hasBackgroundClockDebt()),tostring(openingWorker.activity)))
        local opens=math.floor(returnAt/24)*24+require("src.business_hours").OPEN_HOUR
        local untilOpen=math.ceil((opens+.02-Calendar.absoluteHours(state))*Calendar.secondsPerDay(state)/24*60)
        for _=1,untilOpen do R.App.update(1/60) end
        earned=0;for _,week in ipairs(openingWorker.weeks) do earned=earned+week.earnedCents end
        check("background_runtime_monday_employee_waits_until_actual_opening_then_works",openingWorker.clockedIn
            and earned>0 and earned<1000 and Calendar.absoluteHours(state)>opens,
            string.format("now=%.8f earned=%.8f clocked=%s phase=%s activity=%s last=%.8f",Calendar.absoluteHours(state),earned,
                tostring(openingWorker.clockedIn),openingWorker.phase,tostring(openingWorker.activity),state.employment.lastAtHours))
        Fixture.setup(R,true);R.App.update(1)
        local Sleep=require("src.home_sleep");local oldCalendarStep=Sleep.calendarStep;local accelerated=false
        state=R.state;state.home.weekend.phase="ready";state.home.weekend.closedAtHours=state.home.weekend.closesAtHours
        hours(state,95);state.employment.lastAtHours=95
        Sleep.calendarStep=function()accelerated=true;return 1000 end
        local sleepOkay,sleepError=pcall(R.App.update,1/60)
        Sleep.calendarStep=oldCalendarStep
        check("background_runtime_sleep_acceleration_waits_for_existing_clock_debt",sleepOkay and not accelerated
            and Calendar.absoluteHours(state)<95.01 and R.World.hasBackgroundClockDebt(),tostring(sleepError))


    end,debug.traceback)
    for k in pairs(R.state)do R.state[k]=nil end
    for k,v in pairs(previous)do R.state[k]=v end
    R.World.load(player);R.World._state=R.state;R.Machine.reset();R.Wrapper.clearInstances();R.App.gameClockSpeed=speed
    R._weekendScene,R._weekendPromptToken=oldScene,oldPrompt
    if not okay then error(reason,0) end
end
return Fixture
