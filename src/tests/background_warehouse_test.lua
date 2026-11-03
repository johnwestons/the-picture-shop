local Background=require("src.background_warehouse")
local Calendar=require("src.business_calendar")
local Test={}
local function near(a,b) return math.abs(a-b)<1e-7 end
function Test.run(context,check)
    local bg=Background.new();local state={};bg:ensure(state);bg.background=true
    local calls,game,motion=0,0,0
    local function run(g,m) calls=calls+1;game=game+g;motion=motion+m;return true end
    for _=1,60 do bg:advance(state,10/60,1/60,run) end
    check("background_cadence_ten_real_updates_preserves_all_elapsed",calls==10 and near(game,10) and near(motion,1))
    check("background_cadence_reports_actual_world_steps",bg:stats().calls==60 and bg:stats().backgroundSteps==10)
    bg:advance(state,.02,.02,run);bg:flush(run)
    check("background_return_flushes_remainder_once",calls==11 and near(game,10.02) and not bg:flush(run))
    bg.background=false;bg:advance(state,0,0,run)
    check("background_foreground_zero_dt_reconciles_without_clock",calls==12 and near(game,10.02))
    bg:reset(state);local g,m=bg:clock(state,25,2.5,true)
    check("background_long_frame_has_bounded_game_and_real_step",near(g,1) and near(m,.1) and near(bg.debtGame,24))
    game,motion=g,m
    for _=1,24 do g,m=bg:clock(state,0,0,false);game,motion=game+g,motion+m end
    check("background_live_debt_drains_exactly_after_return",near(game,25) and near(motion,2.5) and near(bg.debtGame,0) and #bg.queue==0)
    g,m=bg:clock(state,0,0,false)
    check("background_debt_never_replays_or_uses_offline_time",g==0 and m==0)
    game,motion=bg:clock(state,2,.2,true)
    g,m=bg:clock(state,.3,.3,true);game,motion=game+g,motion+m
    while #bg.queue>0 do g,m=bg:clock(state,0,0,false);game,motion=game+g,motion+m end
    -- Two 10x slices are consumed before the later ordinary-speed slice.
    check("background_speed_changes_keep_ordered_elapsed_ratios",near(game,2.3) and near(motion,.5))
    bg:reset(state)
    g,m=bg:clock(state,2,.2,false,.5)
    check("background_reopen_boundary_retains_unspent_live_clock",near(g,.5) and near(m,.05)
        and near(bg.debtGame,1.5) and bg:hasDebt())
    g,m=bg:clock(state,0,0,true)
    local nextGame,nextMotion=bg:clock(state,0,0,true)
    check("background_after_reopen_preserves_every_production_second",near(g+nextGame,1.5)
        and near(m+nextMotion,.15) and not bg:hasDebt())
    bg:clock(state,50,5,true);bg:advance(state,.01,.01,run)
    bg:ensure({})
    check("background_new_session_clears_private_debt_and_pending",bg.debtGame==0 and bg.pendingGame==0 and not bg.background)
    check("background_no_human_inside_allows_cadence",Background.unattended({sceneId="commute"},{{sceneId="home"}}))
    for _,scene in ipairs({"warehouse","front_left","front_right","unknown"}) do
        check("background_guest_in_"..scene.."_retains_full_cadence",not Background.unattended({sceneId="commute"},{{sceneId=scene}}))
    end
    check("background_local_and_unknown_player_retains_full_cadence",not Background.unattended({},{}))
    check("background_clock_boundary_detects_minute_day_and_due_time",Background.crossesMinute(9+59.99/60,.1,1200)
        and Background.crossesMinute(23.9999,.1,1200) and not Background.crossesMinute(9,.1,1200))
    -- Exercise the public World cadence wrapper with the original service
    -- chain intact; instrumented services record the calendar they receive.
    local State=require("src.state");local Flow=require("src.weekend_flow")
    local s=State.new();s.calendar=Calendar.dateFromHours(9);s.calendar.elapsed=9/24*Calendar.secondsPerDay(s);s.employment.recruiting=false
    local seen={};local stepCount=0
    local door={state="closed",update=function()end}
    local visitor={update=function()end,isPresent=function()return false end}
    local R={World={player={sceneId="commute"},roomDoors={},bayDoor=door,customer=visitor,vendor=visitor,
        truck={state="absent",mode="delivery"},employeeContext=function()return{} end},
        Config={palletLogistics={}},BusinessCalendar=Calendar,
        WarehouseGameplay={assets=function(a)return a end},
        PalletLogistics={update=function()stepCount=stepCount+1 end},
        Procurement={category=function()return{character="cat",salesman="Test",name="Test"}end},
        Technician={update=function()end},EmployeeAI={receptionOccupied=function()return false end,
        update=function(_,dt,c)seen[#seen+1]={at=Calendar.absoluteHours(s),dt=dt,background=c.background}end}}
    require("src.world.simulation").install(R);R.updateTruck=function()return false end
    for _=1,2 do
        local dt=R.World.beginSimulationFrame(s,.02,.02,true,{})
        Calendar.update(s,dt);R.World.updateSimulation(dt,{},s,.02)
    end
    check("background_world_defers_short_frames",stepCount==0)
    local oldAt=Calendar.absoluteHours(s)
    R.World.beginSimulationFrame(s,.02,.02,false,{})
    check("background_return_resync_before_current_calendar",stepCount==1 and near(seen[1].dt,.04) and near(seen[1].at,oldAt))
    R.World.updateSimulation(0,{},s,0)
    check("background_return_restores_original_services",stepCount==2 and not seen[2].background)
    s.calendar=Calendar.dateFromHours(9+59.95/60)
    s.calendar.elapsed=(9+59.95/60)/24*Calendar.secondsPerDay(s)
    R.World.beginSimulationFrame(s,.01,.01,true,{})
    Calendar.update(s,.01);R.World.updateSimulation(.01,{},s,.01)
    oldAt=Calendar.absoluteHours(s)
    R.World.beginSimulationFrame(s,.1,.1,true,{})
    check("background_minute_cutoff_flushes_old_work_before_new_day_rules",stepCount==3 and near(seen[3].at,oldAt) and near(seen[3].dt,.01), tostring(stepCount).." at="..oldAt.." seen="..tostring(seen[3] and seen[3].at))
    s.home.weekend.phase="closing"
    R.World.beginSimulationFrame(s,.01,.01,true,{})
    Calendar.update(s,.01);R.World.updateSimulation(.01,{},s,.01)
    check("background_shutdown_uses_full_cadence",stepCount==4 and not seen[4].background)
    s.home.weekend.phase="ready"
    R.World.beginSimulationFrame(s,.1,.1,true,{})
    R.World.updateSimulation(.1,{},s,.1)
    check("background_closed_shop_cannot_generate_work",stepCount==4)
    s.home.visit={kind="outing",scene="home"}
    local reopening=Flow.returnAtHours(s.home.weekend)
    s.calendar=Calendar.dateFromHours(reopening)
    s.calendar.elapsed=(reopening%24)/24*Calendar.secondsPerDay(s)-.05
    local reopeningStep=R.World.beginSimulationFrame(s,.2,.2,true,{})
    Calendar.update(s,reopeningStep);Flow.update(s,false)
    check("background_world_reopens_exactly_before_spending_later_credit",near(Calendar.absoluteHours(s),reopening)
        and s.home.weekend.phase=="working" and R.World.hasBackgroundClockDebt())
    R.World.updateSimulation(reopeningStep,{},s,.2)
    check("background_reopening_does_not_replay_closed_interval_as_work",stepCount==4)
    local nextStep=R.World.beginSimulationFrame(s,0,0,true,{})
    check("background_world_reopened_production_receives_retained_credit",near(nextStep,.1)
        and R.World.backgroundSimulationStats().debtGame>.049)
    local paidState=State.new();local Service=require("src.job_service")
    paidState.calendar.elapsed=23.999/24*Calendar.secondsPerDay(paidState)
    local job=assert(require("src.jobs").createOffer({id="BACKGROUND-PICKUP",company="Cadence test",
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500}}))
    require("src.jobs").accept(job);paidState.jobs.active[1]=job
    job.status="pickup_in_progress";job.pickup={status="departing"}
    local pallet=job.pallets[1];pallet.location="outbound_truck";pallet.status="loaded_for_pickup"
    paidState.accountsReceivable=job.quote.totalPrice
    local paidWorld={truck={mode="pickup",jobId=job.id,state="departing",sceneId="warehouse",update=function()return "departed" end},
        bayDoor={state="closed"},roomDoors={}}
    local paymentRuntime={World=paidWorld,JobService=Service,
        Procurement={orderById=function()end},MachineFleet={orderById=function()end}}
    require("src.world.simulation").install(paymentRuntime)
    paymentRuntime.scheduleTruck=function()return false end
    local wallet=paidState.money
    paymentRuntime.updateTruck(.1,.1,paidState)
    paymentRuntime.updateTruck(.1,.1,paidState)
    check("background_original_truck_completion_pays_exactly_once",#paidState.jobs.completed==1
        and #paidState.jobs.active==0 and paidState.money==wallet+job.quote.totalPrice and paidState.accountsReceivable==0)
    check("background_pickup_uses_authoritative_pre_boundary_calendar",math.abs(job.completedAtHours-23.999)<1e-7)
    if context and context.appRuntime then
        require("src.tests.support.background_warehouse_fixture").verify(context.appRuntime,check)
    end
end
return Test
