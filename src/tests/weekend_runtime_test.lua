local Flow=require("src.weekend_flow")
local Calendar=require("src.business_calendar")
local Weekend=require("src.weekend_runtime")
local Travel=require("src.home_travel")
local Test={}
local function run(context,check)
    local R=context.appRuntime
    if not R then return end
    local previous={};for k,v in pairs(R.state) do previous[k]=v end
    local previousPlayer=R.World.snapshot();local oldSpeed=R.App.gameClockSpeed
    assert(R.startGame(R.Save.newGame(3),"smoke"))
    local state=R.state;state.employment.recruiting=false
    local Employees=require("src.employees")
    local applicant=Employees.createApplicant(state,0)
    Employees.requestResume(state,applicant.id,0);Employees.advance(state,.5)
    local shiftStart=applicant.shiftPreference=="day" and 12 or 18
    assert(Employees.command(state,{kind="offer_employee",applicationId=applicant.id,expectedRevision=applicant.revision,
        wageCents=math.max(2200,applicant.requestedWage),days=31,startHour=shiftStart,endHour=(shiftStart+8)%24},.5))
    Employees.advance(state,1.25)
    assert(Employees.command(state,{kind="hire_employee",applicationId=applicant.id,expectedRevision=applicant.revision},1.25))
    local worker=state.employment.staff[1]
    worker.visible=true;worker.clockedIn=true;worker.phase="idle";worker.x,worker.y=720,230
    state.calendar=Calendar.dateFromHours(43.99);state.calendar.elapsed=19.99/24*Calendar.secondsPerDay(state)
    state.employment.lastAtHours=43.99
    state.screen="computer"
    local job=assert(R.Jobs.createOffer({id="JOB-WEEKEND-RUNTIME",company="Weekend Test",sourceSize={width=20,height=16},
        finishedSize={width=10,height=8},sheetCounts={500},packaging="flat",details={dueDate="Five business days"}}))
    assert(R.JobService.acceptOffer(state,job,100))
    assert(R.World.truck:schedule(job.id,"delivery"))
    job.delivery.status="scheduled"
    local due=job.deadline.dueAtHours
    state.money=10000;state.inventory.prints=200
    for _=1,200 do assert(require("src.shop").sellPrint(state)) end
    local cutter=R.Machine.forId("MCH-0001");cutter.step="loading";cutter.progress=0
    local readyJob=assert(R.Jobs.createOffer({id="JOB-FRIDAY-PICKUP",company="Late Pickup",
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500},packaging="flat"}))
    assert(R.JobService.acceptOffer(state,readyJob,100))
    readyJob.status="in_production";readyJob.delivery.status="received"
    local pickupPallet=readyJob.pallets[1]
    pickupPallet.location="warehouse";pickupPallet.status="wrapped"
    pickupPallet.wrapped=true;pickupPallet.remainingSheets=0
    pickupPallet.world={x=400,y=500,sceneId="warehouse",direction="northwest",spawnProgress=1}
    worker.assignment={jobId=readyJob.id,palletId=pickupPallet.id,
        machineId="MCH-0001",machineModel="polar_115"}
    worker.reserved=true;worker.phase="working"
    local jack=state.palletJack;jack.operating=true;jack.operatorPlayerId=1
    R.App.update(.6)
    check("weekend_runtime_reaches_closing",state.home.weekend.phase=="closing")
    check("weekend_runtime_worker_keeps_current_assignment_during_cycle",
        worker.visible and worker.clockedIn and worker.assignment~=nil)
    for _=1,80 do R.App.update(.1) end
    check("weekend_runtime_finishes_existing_cut_step",cutter.step=="loaded",cutter.step)
    check("weekend_runtime_waits_for_player_parking",state.home.weekend.phase=="closing"
        and #require("src.shop_shutdown").checklist(state,R.World)>0)
    R.PalletJack.forceRelease(state,R.Config.palletJack)
    R.App.update(.1)
    check("weekend_runtime_stays_playable_after_parking",state.home.weekend.phase=="closing")
    for _=1,240 do
        if not worker.visible then break end
        R.App.update(.1)
    end
    check("weekend_runtime_worker_walks_out",not worker.visible and worker.phase=="hidden",
        tostring(worker.activity).." / "..tostring(worker.phase).." / "..tostring(worker.assignment and worker.assignment.jobId)
            .." / "..tostring(worker.clockedIn).." / "..tostring(cutter.step))
    local cutterUnit=R.MachineFleet.installedUnits(state,"polar_115")[1]
    local cutterPlace=cutterUnit and cutterUnit.world
        or require("src.cutter_placement").ensure(state,R.Config.cutterPlacement)
    check("weekend_runtime_guest_can_use_cutter_while_closing",
        R.World.validateNetworkWorkshopAccess({id=2,x=cutterPlace.x,y=cutterPlace.y,
            sceneId="warehouse"},state,"cutter"))
    local host=R.World.player;host.id=1
    local door=Travel.target(host,state);host.x,host.y=door.x,door.y
    check("weekend_runtime_inbound_truck_waits_at_dock",R.World.truck.mode=="delivery"
        and R.World.truck.state=="parked_closed",R.World.truck.state)
    local inboundDriverService=require("src.warehouse_delivery_driver")
    local signature=assert(inboundDriverService.interaction(state))
    host.x,host.y=signature.x,signature.y
    check("weekend_runtime_player_signs_inbound_delivery",R.World.signDelivery(state,host))
    for _=1,200 do
        local visit=inboundDriverService.matching(state,job.id)
        if visit and visit.driverReturned then break end
        R.App.update(.1)
    end
    check("weekend_runtime_driver_returns_to_truck",inboundDriverService.matching(state,job.id).driverReturned)
    host.x,host.y=door.x,door.y
    assert(R.World.toggleTruckCargoDoor(state))
    for _=1,15 do R.App.update(.1) end
    check("weekend_runtime_can_unload_after_shift",R.World.unloadTruckPallet(state,job.pallets[1].id))
    check("weekend_runtime_close_inbound_truck",R.World.closeTruckAfterUnload(state))
    for _=1,80 do
        if R.World.truck.state=="absent" and R.World.bayDoor.state=="closed" then break end
        R.App.update(.1)
    end
    check("weekend_runtime_inbound_truck_departs_and_dock_closes",R.World.truck.state=="absent"
        and R.World.bayDoor.state=="closed" and job.delivery.status=="received",
        table.concat({tostring(R.World.truck.state),tostring(R.World.truck.x),tostring(R.World.truck.y),
            tostring(R.World.truck.speed),tostring(R.World.bayDoor.state),tostring(job.delivery.status),
            tostring(state.home.weekend.phase),tostring(state.message)}," / "))
    check("weekend_runtime_can_call_friday_pickup",R.JobService.requestPickup(state,readyJob,os.time()))
    R.App.update(.1)
    check("weekend_runtime_schedules_pickup_while_closing",R.World.truck.mode=="pickup"
        and readyJob.status=="pickup_in_progress",R.World.truck.state)
    check("weekend_runtime_docked_truck_blocks_departure",not Weekend.command(R,host,"request")
        and state.home.weekend.phase=="closing")
    for _=1,100 do
        if R.World.truck.state=="parked_closed" then break end
        R.App.update(.1)
    end
    check("weekend_runtime_pickup_parks_after_shift",R.World.truck.state=="parked_closed",R.World.truck.state)
    local cargoTarget=assert(R.World.truck:getInteraction())
    local guest={id=2,x=cargoTarget.x,y=cargoTarget.y,sceneId="warehouse"}
    local guestOpened=R.World.performNetworkInteraction(guest,state,"truckCargoDoor","open")
    check("weekend_runtime_guest_can_open_friday_truck",guestOpened
        and R.World.truck.state=="cargo_opening",R.World.truck.state)
    for _=1,15 do R.App.update(.1) end
    check("weekend_runtime_pickup_cargo_opens",R.World.truck.state=="cargo_open",R.World.truck.state)
    check("weekend_runtime_player_loads_after_shift",R.World.loadPickupPallet(state,pickupPallet.id))
    for _=1,80 do
        if R.World.truck.state=="absent" and R.World.bayDoor.state=="closed" then break end
        R.App.update(.1)
    end
    check("weekend_runtime_pickup_departs_and_dock_closes",R.World.truck.state=="absent"
        and R.World.bayDoor.state=="closed" and readyJob.status=="completed",
        R.World.truck.state.." / "..R.World.bayDoor.state)
    check("weekend_runtime_player_can_choose_when_to_finish",state.home.weekend.phase=="closing")
    check("weekend_runtime_ready_at_front_door",Weekend.command(R,host,"request")
        and state.home.weekend.phase=="ready",state.message)
    check("weekend_runtime_closed_dock_cannot_reopen",not R.World.toggleBayDoor(state,"warehouse")
        and R.World.bayDoor.state=="closed")
    local paid=state.home.balanceCents
    check("weekend_runtime_shutdown_transfers_personal_pay",paid>30000 and #state.home.finance.history==1
        and state.home.finance.history[1].costs.revenue>=240000)
    local earned=0;for _,row in ipairs(worker.weeks) do earned=earned+row.earnedCents end
    check("weekend_runtime_worker_finishes_paid_work",earned>0 and not worker.clockedIn)
    local at=Calendar.absoluteHours(state);R.App.update(2)
    check("weekend_runtime_clock_held_at_exit",Calendar.absoluteHours(state)==at)
    host.x,host.y=400,450
    check("weekend_runtime_rejects_remote_departure",not Weekend.command(R,host,"request"))
    host.x,host.y=door.x,door.y
    state.screen="world"
    R.World.updateNetworkPlayer(0,0,0,R.Assets,state,door.hoverX,door.hoverY)
    check("weekend_runtime_exterior_door_selectable",R.World.getInteraction() and R.World.getInteraction().kind=="homeTravel",
        R.World.getInteraction() and R.World.getInteraction().kind or "no selection")
    check("weekend_runtime_opens_exit_controls",require("src.home_travel_controls").keypressed("e",R)
        and state.screen=="home_travel")
    check("weekend_runtime_travel_panel_fits_mobile",R.App.officeFitsScreen() and not R.App.cameraTransformsUi())
    check("weekend_runtime_request_is_already_open",state.home.weekend.travelToken~=nil)
    local token=state.home.weekend.travelToken
    local folder=os.getenv("PICTURE_SHOP_HOME_PREVIEW_DIR")
    if folder then
        local canvas=love.graphics.newCanvas(960,678)
        love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
        require("src.home_travel_controls").draw(R);love.graphics.pop()
        local data=canvas:newImageData();local bytes=data:encode("png")
        local file=assert(io.open(folder.."/weekend-travel.png","wb"));file:write(bytes:getString());file:close()
        bytes:release();data:release();canvas:release()
    end
    check("weekend_runtime_request_is_durable",token and require("src.save_schema").validState(assert(require("src.save_schema").snapshot(state))))
    require("src.home_travel_controls").keypressed("return",R)
    check("weekend_runtime_front_door_to_apartment",state.home.weekend.phase=="home" and host.sceneId=="home"
        and state.screen=="world")
    local arrived=state.home.residents.owner
    check("weekend_runtime_friday_arrival_has_low_needs_and_dirty_clothes",arrived.hunger<=30
        and arrived.thirst<=25 and arrived.hygiene<=18 and arrived.energy<=12 and arrived.dirtyClothes)
    assert(R.Save.flush());local saved=assert(R.Save.load(3))
    check("weekend_runtime_save_contains_travel_and_location",saved.player.sceneId=="home" and saved.state.home.weekend.phase=="home")
    check("weekend_runtime_friday_condition_is_saved",saved.state.home.residents.owner.dirtyClothes
        and saved.state.home.residents.owner.energy==arrived.energy)
    check("weekend_runtime_payout_saved_with_both_accounts",saved.state.home.balanceCents==paid
        and saved.state.money==state.money and #saved.state.home.finance.history==1)
    local Residents=require("src.home_residents");local Layout=require("src.home_layouts")
    local Controls=require("src.home_activity_controls")
    local sink=Layout.get(state).fixtures.sink
    host.x,host.y=Layout.toWorld(unpack(sink.approach))
    local hoverX,hoverY=Layout.toWorld(sink.x,sink.y)
    state.home.residents.owner.thirst=30
    R.World.updateNetworkPlayer(0,0,0,R.Assets,state,hoverX,hoverY)
    check("home_runtime_fixture_is_selectable",R.World.getInteraction() and R.World.getInteraction().kind=="homeActivity")
    check("home_runtime_fixture_keyboard_opens_routines",Controls.keypressed("e",R)
        and state.screen=="home_activity" and Controls.target=="sink" and R.App.officeFitsScreen())
    Controls.mousepressed(250,320,1,R)
    check("home_runtime_touch_starts_drinking",state.home.residents.owner.activity and state.home.residents.owner.activity.kind=="drink")
    if folder then
        local canvas=love.graphics.newCanvas(960,678)
        love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear();Controls.draw(R);love.graphics.pop()
        local data=canvas:newImageData();local bytes=data:encode("png")
        local file=assert(io.open(folder.."/home-routines.png","wb"));file:write(bytes:getString());file:close()
        bytes:release();data:release();canvas:release()
    end
    R.App.update(Calendar.secondsPerDay(state)/24*2/60)
    check("home_runtime_timed_drink_restores_local_thirst",state.home.residents.owner.thirst>99 and not state.home.residents.owner.activity)
    Controls.keypressed("escape",R)
    if folder then
        local canvas=love.graphics.newCanvas(960,678)
        love.graphics.push("all");love.graphics.setCanvas(canvas);love.graphics.clear()
        R.World.draw(R.Assets,R.CharacterAssets,state,nil,nil,{})
        require("src.screens.hud").draw(state,R.World.prompt(),R.Assets,nil,nil,false,false,nil,false,false,nil,"home",host)
        love.graphics.pop()
        local data=canvas:newImageData();local bytes=data:encode("png")
        local file=assert(io.open(folder.."/home-needs-hud.png","wb"));file:write(bytes:getString());file:close()
        bytes:release();data:release();canvas:release()
        check("home_runtime_hud_touch_opens_personal_routines",Controls.mousepressed(40,130,1,R) and state.screen=="home_activity")
        Controls.keypressed("escape",R)
    end
    Controls.keypressed("h",R);Controls.keypressed("1",R)
    check("home_runtime_floor_rest_needs_no_bed",state.home.residents.owner.activity and state.home.residents.owner.activity.kind=="rest")
    Controls.keypressed("backspace",R)
    check("home_runtime_floor_rest_can_stop",not state.home.residents.owner.activity)
    Controls.keypressed("escape",R)
    local foodSpent=require("src.tests.support.home_food_runtime").run(R,check)
    local truckTimer,visitorTimer=R.World.truck.timer,R.World.customer.timer
    require('src.tests.support.weekend_playthrough').run(R,check)
    check("weekend_runtime_calendar_advances_at_home",Calendar.absoluteHours(state)>=104)
    check("weekend_runtime_shop_stays_frozen",R.World.truck.timer==truckTimer and R.World.customer.timer==visitorTimer
        and cutter.step=="loaded" and job.deadline.dueAtHours==due and job.pallets[1].remainingSheets==500)
    check("weekend_runtime_employee_checkpoint_skips_closed_time",state.employment.lastAtHours==Calendar.absoluteHours(state))
    local afterEarned=0;for _,row in ipairs(worker.weeks) do afterEarned=afterEarned+row.earnedCents end
    check("weekend_runtime_no_phantom_weekend_wages",afterEarned==earned)
    local pizzaRemaining=state.home.inventory.pizza_slice
    assert(R.saveCurrent(true));local homeSave=assert(R.Save.load(3))
    local savedTime=Calendar.absoluteHours(state)
    assert(R.startGame(homeSave,"smoke"))
    check("weekend_runtime_reload_resumes_at_home_without_offline_time",host.sceneId=="home"
        and state.home.weekend.phase=="home" and math.abs(Calendar.absoluteHours(state)-savedTime)<.000001)
    check("weekend_runtime_reload_does_not_repeat_pay",state.home.balanceCents==paid-foodSpent and #state.home.finance.history==1)
    check("home_food_runtime_reload_preserves_order_and_remaining_food",state.home.inventory.pizza_slice==pizzaRemaining
        and state.home.shopping.orders[1].status=="collected")
    check("home_runtime_needs_survive_reload_without_offline_decay",state.home.residents.owner.thirst==homeSave.state.home.residents.owner.thirst)
    local remaining=107-Calendar.absoluteHours(state)
    R.App.update(remaining*Calendar.secondsPerDay(state)/24)
    local homeDoor=Travel.target(host,state);host.x,host.y=homeDoor.x,homeDoor.y
    state.screen='world'
    R.World.updateNetworkPlayer(0,0,0,R.Assets,state,homeDoor.hoverX,homeDoor.hoverY)
    check('weekend_playthrough_monday_return_door_selectable',R.World.getInteraction()
        and R.World.getInteraction().kind=='homeTravel')
    local travelControls=require('src.home_travel_controls')
    assert(travelControls.keypressed('e',R) and state.screen=='home_travel')
    travelControls.keypressed('w',R);local returnToken=state.home.weekend.travelToken
    check('weekend_playthrough_monday_return_requested',returnToken~=nil)
    travelControls.keypressed('return',R)
    check("weekend_runtime_monday_return",host.sceneId=="warehouse" and state.home.weekend.phase=="working"
        and math.abs(Calendar.absoluteHours(state)-107)<.000001)
    check("weekend_runtime_return_preserves_unfinished_job",#state.jobs.active==1 and state.jobs.active[1].id==job.id)
    check("weekend_runtime_old_travel_rejected",not Weekend.command(R,host,"force:"..token))
    assert(R.Save.flush());assert(R.Save.delete(3))
    for k in pairs(state) do state[k]=nil end;for k,v in pairs(previous) do state[k]=v end
    R.World.load(previousPlayer);R.World._state=state;R.Machine.reset();R.Wrapper.clearInstances()
    R.App.gameClockSpeed=oldSpeed;R._weekendScene,R._weekendPromptToken=nil,nil
end
-- This fixture isolates the weekly business/home lifecycle using the retained
-- direct-transition compatibility path. Physical exterior journeys, seeded
-- save/load and all four apartment entrances have their own acceptance suite.
function Test.run(context,check)
    local Commute=require('src.commute.runtime');local enabled=Commute.enabled
    Commute.enabled=function()return false end
    local okay,reason=xpcall(function()run(context,check) end,debug.traceback)
    Commute.enabled=enabled
    if not okay then error(reason,0) end
end
return Test
