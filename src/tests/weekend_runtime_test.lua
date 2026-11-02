local Flow=require("src.weekend_flow")
local Calendar=require("src.business_calendar")
local Weekend=require("src.weekend_runtime")
local Travel=require("src.home_travel")
local Test={}
function Test.run(context,check)
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
    local due=job.deadline.dueAtHours
    state.money=10000;state.inventory.prints=200
    for _=1,200 do assert(require("src.shop").sellPrint(state)) end
    local cutter=R.Machine.forId("MCH-0001");cutter.step="loading";cutter.progress=0
    local jack=state.palletJack;jack.operating=true;jack.operatorPlayerId=1
    R.App.update(.6)
    check("weekend_runtime_reaches_closing",state.home.weekend.phase=="closing")
    for _=1,80 do R.App.update(.1) end
    check("weekend_runtime_finishes_existing_cut_step",cutter.step=="loaded",cutter.step)
    check("weekend_runtime_waits_for_player_parking",state.home.weekend.phase=="closing"
        and #require("src.shop_shutdown").checklist(state,R.World)>0)
    R.PalletJack.forceRelease(state,R.Config.palletJack)
    R.App.update(.1)
    check("weekend_runtime_ready_after_parking",state.home.weekend.phase=="ready",state.message)
    local paid=state.home.balanceCents
    check("weekend_runtime_shutdown_transfers_personal_pay",paid>30000 and #state.home.finance.history==1
        and state.home.finance.history[1].costs.revenue==240000)
    local earned=0;for _,row in ipairs(worker.weeks) do earned=earned+row.earnedCents end
    check("weekend_runtime_worker_finishes_paid_work",earned>0 and not worker.clockedIn)
    local at=Calendar.absoluteHours(state);R.App.update(2)
    check("weekend_runtime_clock_held_at_exit",Calendar.absoluteHours(state)==at)
    local host=R.World.player;host.id=1;host.x,host.y=400,450
    check("weekend_runtime_rejects_remote_departure",not Weekend.command(R,host,"request"))
    local door=Travel.target(host,state);host.x,host.y=door.x,door.y
    state.screen="world"
    R.World.updateNetworkPlayer(0,0,0,R.Assets,state,door.hoverX,door.hoverY)
    check("weekend_runtime_exterior_door_selectable",R.World.getInteraction() and R.World.getInteraction().kind=="homeTravel",
        R.World.getInteraction() and R.World.getInteraction().kind or "no selection")
    check("weekend_runtime_opens_exit_controls",require("src.home_travel_controls").keypressed("e",R)
        and state.screen=="home_travel")
    check("weekend_runtime_travel_panel_fits_mobile",R.App.officeFitsScreen() and not R.App.cameraTransformsUi())
    require("src.home_travel_controls").mousepressed(200,440,1,R)
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
    assert(R.Save.flush());local saved=assert(R.Save.load(3))
    check("weekend_runtime_save_contains_travel_and_location",saved.player.sceneId=="home" and saved.state.home.weekend.phase=="home")
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
    travelControls.keypressed('return',R);local returnToken=state.home.weekend.travelToken
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
return Test
