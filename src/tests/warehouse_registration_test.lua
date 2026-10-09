local Config=require("src.config")
local Map=require("src.warehouse_registration")
local Rooms=require("src.shop_rooms")
local Layout=require("src.warehouse_layout")
local State=require("src.state")
local Calendar=require("src.business_calendar")
local Employees=require("src.employees")
local AI=require("src.employee_ai")
local Navigator=require("src.npc_navigation")
local Navigation=require("src.navigation")
local Customer=require("src.customer")
local Jack=require("src.pallet_jack")
local Fleet=require("src.machine_fleet")
local Machine=require("src.machine")
local Pallets=require("src.pallet_state")
local Jobs=require("src.jobs")
local Pose=require("src.employee_pose")
local Speech=require("src.employee_speech")
local Test={}
local function hours(state,value)
    state.calendar=Calendar.dateFromTotalDay(math.floor(value/24))
    state.calendar.elapsed=(value%24)/24*Calendar.secondsPerDay(state)
end
local function hire(state)
    local app=assert(Employees.createApplicant(state,0))
    app.shiftPreference="flexible"
    Employees.requestResume(state,app.id,0);Employees.advance(state,.5)
    assert(Employees.command(state,{kind="offer_employee",applicationId=app.id,expectedRevision=app.revision,
        wageCents=3000,days=31,startHour=9,endHour=17},.5))
    Employees.advance(state,1.25)
    assert(Employees.command(state,{kind="hire_employee",applicationId=app.id,expectedRevision=app.revision},1.25))
    local w=state.employment.staff[#state.employment.staff]
    w.visible,w.clockedIn,w.phase=true,true,"idle"
    w.x,w.y,w.breaksTaken=620,480,7
    state.employment.recruiting=false
    return w
end
local function depart(state,worker,ctx,startHours)
    local safe=true
    for tick=1,600 do
        local now=(startHours or 17)+tick*.1*24/Calendar.secondsPerDay(state)
        hours(state,now);AI.worker(state,worker,.1,now,ctx)
        if not worker.visible then return true,safe end
        safe=safe and Navigation.isWalkable(ctx.assets,worker.x,worker.y,ctx.obstacles(worker))
    end
    return false,safe
end
local function capture(context,state,name,overlay)
    local canvas=love.graphics.newCanvas(960,678)
    love.graphics.push("all");love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(0,0,0,1)
    context.world.draw(context.assets,context.characterAssets,state,nil,nil,{})
    if overlay then overlay() end
    love.graphics.pop()
    local data=canvas:newImageData();local bytes=data:encode("png"):getString();data:release();canvas:release()
    local output=os.getenv("PICTURE_SHOP_ALIGNMENT_CAPTURE_DIR")
    if output then local f=assert(io.open(output.."/"..name..".png","wb"));f:write(bytes);f:close() end
end
local function controls(context,check)
    local world=context.world
    local state=State.new();state.employment.recruiting=false;state.screen="world"
    local ctx=world.employeeContext(state,context.assets)
    for _,kind in ipairs({"computer","workPhone","shopClock","jukebox"}) do
        local point=Config.interactables[kind]
        local actor={x=Config.player.spawnX,y=Config.player.spawnY}
        local arrived=false
        for _=1,200 do arrived=Navigator.travel(actor,point,7.2,.1,ctx);if arrived then break end end
        check("warehouse_registration_reaches_"..kind,arrived,kind)
        world.player.x,world.player.y=point.x,point.y
        world.selectedInteraction=nil
        world.update(0,0,0,context.assets,state,point.hoverX,point.hoverY)
        local selected=world.getInteraction()
        check("warehouse_registration_visible_"..kind.."_selects_correct_action",
            selected and selected.kind==kind and selected.hovered,selected and selected.kind)
    end
    for _,point in ipairs({Map.entrance,Map.dock,Map.truck.interaction}) do
        check("warehouse_registration_floor_contact_"..point.x.."_"..point.y,
            Navigation.isWalkable(ctx.assets,point.x,point.y,ctx.obstacles(world.player)))
    end
    for _,kind in ipairs({"cutter","wrapper","windmill"}) do
        local c=Config[kind.."Placement"]
        check("warehouse_registration_default_"..kind.."_fits_floor",
            Navigation.isAreaWalkable(ctx.assets,c.spawnX,c.spawnY,c.collisionHalfWidth,c.collisionHalfHeight))
    end
    for index,point in ipairs(Config.palletLogistics.spawnPoints) do
        check("warehouse_registration_receiving_pallet_"..index.."_fits_floor",
            Navigation.isAreaWalkable(ctx.assets,point.x,point.y,33,11))
    end
    local copy=Map.obstacles();copy[1].halfWidth=900;copy[#copy+1]={x=400,y=400,radius=100}
    check("warehouse_registration_collision_queries_do_not_mutate_scenery",
        Map.obstacles()[1].halfWidth==Map.furniture[1].halfWidth and #Map.obstacles()==#Map.furniture)
    for index,point in ipairs({{773,183},{811,212},{899,214},{922,205}}) do
        check("warehouse_registration_furniture_"..index.."_blocks_walking",
            not Navigation.isWalkable(ctx.assets,point[1],point[2],Map.obstacles()))
    end
    for _,kind in ipairs({"storage","breakroom","floor"}) do
        local roomState=State.new()
        roomState.warehouse.bays.front_left.status,roomState.warehouse.bays.front_left.optionId="complete",kind
        local adapted=Rooms.assets(context.assets,"front_left",roomState)
        check("warehouse_registration_"..kind.."_uses_its_floor",adapted._shopRoomKind==kind
            and adapted==Rooms.assets(adapted,"front_left",roomState)
            and Navigation.isWalkable(adapted,Rooms.exit.x,Rooms.exit.y,Rooms.obstacles(roomState,"front_left")))
        if kind~="floor" then
            local point=kind=="storage" and Rooms.shelves or Rooms.rest
            local player={x=point.x,y=point.y,sceneId="front_left"}
            local selected=require("src.interaction").select(player,Rooms.targets(player,roomState),point.hoverX,point.hoverY)
            check("warehouse_registration_visible_"..kind.."_furniture_selects_action",selected and selected.hovered
                and selected.kind==(kind=="storage" and "roomStock" or "roomRest"))
        end
    end
    world.player.x,world.player.y=423,282;world.selectedInteraction=nil
    local shelf=Layout.rackPoint("warehouse-rack",1,3)
    world.update(0,0,0,context.assets,state,shelf.x,shelf.y)
    check("warehouse_registration_visible_base_shelf_selects_action",world.getInteraction()
        and world.getInteraction().kind=="palletRack" and world.getInteraction().hovered)
    world.player.x,world.player.y=909,241;world.selectedInteraction=nil
    hours(state,12);world.update(0,0,0,context.assets,state,909,175)
    capture(context,state,"warehouse-calibrated")
    capture(context,state,"warehouse-contacts",function()
        love.graphics.setLineWidth(1)
        local font=love.graphics.newFont(10);love.graphics.setFont(font)
        for _,row in ipairs({{"Entrance",Map.entrance},{"Computer",Config.interactables.computer},
            {"Phone",Config.interactables.workPhone},{"Clock",Config.interactables.shopClock},
            {"Radio",Config.interactables.jukebox},{"Dock",Map.dock}}) do
            local p=row[2];love.graphics.setColor(.2,.95,.8,1);love.graphics.circle("line",p.x,p.y,5)
            love.graphics.line(p.x,p.y,p.hoverX,p.hoverY);love.graphics.circle("line",p.hoverX,p.hoverY,5)
            local labelY=p.y+8+(row[1]=="Phone" and 18 or row[1]=="Computer" and 36 or 0)
            love.graphics.setColor(0,0,0,.85);love.graphics.rectangle("fill",p.x-28,labelY-1,64,14)
            love.graphics.setColor(1,1,1,1);love.graphics.print(row[1],p.x-25,labelY)
        end
        love.graphics.setColor(.95,.6,.2,.8)
        local edge=Map.floorEdges.warehouse
        for i=2,#edge do love.graphics.line(edge[i-1][1],edge[i-1][2],edge[i][1],edge[i][2]) end
        for _,o in ipairs(Layout.obstacles(state)) do
            if o.halfWidth then love.graphics.rectangle("line",o.x-o.halfWidth,o.y-o.halfHeight,2*o.halfWidth,2*o.halfHeight)
            else love.graphics.circle("line",o.x,o.y,o.radius) end
        end
        font:release()
    end)
    world.player.x,world.player.y=500,455;world.selectedInteraction=nil
    for index=1,4 do
        local visitor=Customer.new(Config.customer)
        for _=2,index do visitor:reset(false) end
        visitor.timer=0;world.customer=visitor
        local visitorContext=world.employeeContext(state,context.assets)
        for _=1,250 do visitor:update(.1,nil,false,.1,visitorContext);if visitor.state=="waiting" then break end end
        check("warehouse_registration_seated_visitor_"..index.."_reaches_art_contact",visitor.state=="waiting")
        capture(context,state,"warehouse-seat-"..index)
    end
    world.customer=Customer.new(Config.customer)
    world.bayDoor.state,world.bayDoor.progress="open",1
    world.truck.state,world.truck.backingProgress,world.truck.cargoProgress="cargo_open",1,1
    world.truck.mode,world.truck.jobId="delivery","DOCK-REGISTRATION"
    capture(context,state,"warehouse-truck-dock")
    world.bayDoor:reset();world.truck:reset()
end
local function departures(context,check)
    local world=context.world
    world.player.x,world.player.y=100,600
    for index,start in ipairs({{620,480},{520,560},{688,214}}) do
        local state=State.new();local w=hire(state)
        w.x,w.y=start[1],start[2]
        if index==3 then w.phase,w.seatBay,w.breakKind="break","front_right","rest" end
        local arrived,safe=depart(state,w,world.employeeContext(state,context.assets))
        check("warehouse_employee_shift_end_leaves_from_"..index,arrived and w.phase=="hidden" and not w.clockedIn,
            w.phase.." at "..w.x..","..w.y)
        check("warehouse_employee_exit_route_"..index.."_stays_on_floor",safe)
        check("warehouse_employee_exit_"..index.."_disappears_from_guest_poses",#Pose.capture(Employees.actors(state))==0)
    end
    local state=State.new();local w=hire(state)
    world.player.x,world.player.y=Map.entrance.x,Map.entrance.y
    local arrived,safe=depart(state,w,world.employeeContext(state,context.assets))
    check("warehouse_employee_uses_free_door_contact_when_player_blocks_center",arrived and safe
        and (w.x-Map.entrance.x)^2+(w.y-Map.entrance.y)^2<=30^2)
    world.player.x,world.player.y=100,600
    state=State.new();w=hire(state)
    local ctx=world.employeeContext(state,context.assets)
    local normal=ctx.obstacles;local barrier=true
    ctx.obstacles=function(actor)
        local list=normal(actor)
        if barrier then list[#list+1]={x=690,y=195,halfWidth=60,halfHeight=60} end
        return list
    end
    for tick=1,60 do AI.worker(state,w,.1,17+tick*.002,ctx) end
    check("warehouse_employee_blocked_exit_waits_and_requests_clearance",w.visible and w.phase=="leaving"
        and w.activity:find("blocked",1,true)~=nil and Speech.code({worker=w,actor=w})==17)
    barrier=false;arrived,safe=depart(state,w,ctx,17.12)
    check("warehouse_employee_recovers_when_exit_is_cleared",arrived and safe)
    state=State.new();local workers={}
    for i=1,Employees.MAX_STAFF do
        local worker=hire(state);worker.x,worker.y=430+(i-1)*30,580;workers[i]=worker
    end
    ctx=world.employeeContext(state,context.assets)
    for tick=1,600 do
        for _,worker in ipairs(workers) do AI.worker(state,worker,.1,17+tick*.002,ctx) end
        if #Employees.actors(state)==0 then break end
    end
    check("warehouse_full_roster_leaves_without_blocking_each_other",#Employees.actors(state)==0)
    state=State.new();w=hire(state)
    local machine=Fleet.installedUnits(state,"polar_115")[1]
    local runtime=Machine.forId(machine.id);runtime.reset(state);runtime.step="cutting"
    w.assignment={machineId=machine.id,machineModel=machine.modelId};w.reserved=true
    w.phase="working";ctx=world.employeeContext(state,context.assets)
    AI.worker(state,w,.1,17.1,ctx)
    check("warehouse_employee_finishes_safe_cycle_before_departure",w.visible and w.clockedIn
        and w.phase=="working" and w.activity=="Finishing safe machine cycle")
    runtime.step="idle";arrived=depart(state,w,ctx)
    check("warehouse_employee_leaves_after_machine_becomes_safe",arrived and not w.reserved)
    runtime.reset(state)
    state=State.new();w=hire(state)
    local job=assert(Jobs.createOffer({id="JOB-SHIFT-EXIT",company="Exit QA",sourceSize={width=20,height=16},
        finishedSize={width=10,height=8},sheetCounts={500}}))
    Jobs.accept(job);state.jobs.active={job}
    local pallet=job.pallets[1];pallet.location="warehouse";pallet.world={x=570,y=550,spawnProgress=1}
    w.x,w.y=600,540
    assert(Jack.mountEmployee(state,Config.palletJack,w.id));assert(Jack.lift(state,Config.palletJack,pallet.id))
    w.phase="pushing";arrived=depart(state,w,world.employeeContext(state,context.assets))
    check("warehouse_employee_parks_loaded_jack_and_leaves_safely",arrived and not state.palletJack.operating
        and not state.palletJack.operatorEmployeeId and pallet.location=="warehouse" and Pallets.validate(state))
    state=State.new();w=hire(state);state.screen="world"
    hours(state,17);state.employment.lastAtHours=17
    world.customer.timer,world.vendor.timer=1000,1000
    for _=1,400 do
        Calendar.update(state,.1);world.update(.1,0,0,context.assets,state,nil,nil,.1)
        if not w.visible then break end
    end
    check("warehouse_live_simulation_shift_end_removes_worker",not w.visible and w.phase=="hidden" and not w.clockedIn)
end
local function applicant(context,check)
    local state=State.new();state.employment.recruiting=false
    local app=assert(Employees.createApplicant(state,0));local ctx=context.world.employeeContext(state,context.assets)
    state.employment.recruiting=false;state.employment.lastAtHours=8;hours(state,8)
    for tick=1,200 do hours(state,8+tick*.002);AI.update(state,.1,ctx);if app.actor.phase=="waiting" then break end end
    check("warehouse_applicant_reaches_new_reception",app.actor.phase=="waiting"
        and app.actor.x==Map.reception.x and app.actor.y==Map.reception.y)
    local previousState=context.world._state
    local previousX,previousY=context.world.player.x,context.world.player.y
    local previousSelection=context.world.selectedInteraction
    context.world._state=state
    context.world.player.x,context.world.player.y=app.actor.x,app.actor.y
    context.world.selectedInteraction=nil
    local selected=context.world.interactionAt(app.actor.x,app.actor.y,false)
    check("warehouse_applicant_interaction_uses_world_context",
        selected and selected.kind=="applicant" and selected.target.applicationId==app.id,
        selected and selected.kind)
    context.world._state=previousState
    context.world.player.x,context.world.player.y=previousX,previousY
    context.world.selectedInteraction=previousSelection
    Employees.requestResume(state,app.id,Calendar.absoluteHours(state))
    for tick=1,200 do Calendar.update(state,.1);AI.update(state,.1,ctx);if not app.actor.visible then break end end
    check("warehouse_applicant_uses_same_new_exit",not app.actor.visible and app.actor.phase=="hidden")
end
function Test.run(context,check)
    local world=context.world
    local fields={"player","customer","vendor","truck","bayDoor","_state","_assets","selectedInteraction","_employeeOptions"}
    local before={};for _,key in ipairs(fields) do before[key]=world[key] end
    world.player={id=1,x=100,y=600,sceneId="warehouse",character="rabbit-worker",idleClock=0,animationDistance=0,
        facing=1,intentX=0,intentY=-1,velocityX=0,velocityY=0,moving=false,interactionClock=0}
    world.customer,world.vendor=Customer.new(Config.customer),Customer.new(Config.vendor)
    world.truck=require("src.truck").new(Config.truck);world.bayDoor=require("src.bay_door").new(Config.loadingBay)
    world._employeeOptions={}
    local okay,reason=xpcall(function() controls(context,check);departures(context,check);applicant(context,check) end,debug.traceback)
    for _,key in ipairs(fields) do world[key]=before[key] end
    assert(okay,reason)
end
return Test
