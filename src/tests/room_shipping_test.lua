local State=require("src.state")
local Upgrades=require("src.warehouse_upgrades")
local Bays=require("src.room_loading_bays")
local Rooms=require("src.shop_rooms")
local Config=require("src.config")
local Employees=require("src.employees")
local Fleet=require("src.pallet_jack_fleet")
local Jack=require("src.pallet_jack")
local Jobs=require("src.jobs")
local Service=require("src.job_service")
local Shipping=require("src.employee_shipping")
local Pallets=require("src.pallet_state")
local Truck=require("src.truck")
local RoomRenderer=require("src.room_loading_bay_renderer")
local Test={}
local function saveCapture(name,draw)
    local directory=os.getenv("PICTURE_SHOP_ROOM_SHIPPING_CAPTURE_DIR")
    if not directory then return end
    local canvas=love.graphics.newCanvas(960,678)
    love.graphics.push("all");love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(0,0,0,1)
    draw();love.graphics.setCanvas();love.graphics.pop()
    local data=canvas:newImageData();local bytes=data:encode("png"):getString();data:release()
    local f=assert(io.open(directory.."/"..name..".png","wb"));f:write(bytes);f:close();canvas:release()
end
local function complete(s,id,kind,n)
    local now=(n-1)*100
    assert(Upgrades.purchase(s,id,kind,"SHIP-ROOM-"..id,now))
    local project="WUP-000"..n
    Upgrades.update(s,now)
    Upgrades.update(s,now,{noticeDeliveredProjectId=project,noticeCallId="SHIP-CALL-"..n})
    Upgrades.update(s,now+2,{workerArrivedProjectId=project})
    Upgrades.update(s,now+98)
    Upgrades.update(s,now+98,{workerReleasedProjectId=project})
    if kind=="storage" then s.storage.racks[id.."-rack"]=require("src.pallet_storage").rackDefinition(id) end
end
local function shop()
    local s=State.new();s.money=100000
    complete(s,"front_left","storage",1);complete(s,"front_right","floor",2)
    return s
end
local function close(a,b) return math.abs(a-b)<1e-9 end
local function truckProgressCase(truck,state,rawProgress,expectedProgress)
    truck.state,truck.backingProgress=state,rawProgress
    local progress=truck:visualTravelProgress()
    local room=RoomRenderer.truckTransform(truck)
    local world=truck:transform()
    local config=Config.truck
    return close(progress,expectedProgress) and close(room.progress,expectedProgress)
        and close(room.x,726+(1-expectedProgress)*120)
        and close(room.y,332-(1-expectedProgress)*95) and close(room.scale,.76)
        and close(world.x,config.start.x+(config.parked.x-config.start.x)*expectedProgress)
        and close(world.y,config.start.y+(config.parked.y-config.start.y)*expectedProgress)
        and close(world.scale,config.start.scale+(config.parked.scale-config.start.scale)*expectedProgress)
end
local function truckVisualTravel(check)
    local truck=Truck.new(Config.truck)
    local arrival=true
    for _,sample in ipairs({{0,0},{.25,.15625},{1,1}}) do
        arrival=truckProgressCase(truck,"backing",sample[1],sample[2]) and arrival
    end
    check("room_truck_warehouse_share_eased_arrival_progress",arrival)

    local departure=true
    for _,sample in ipairs({{1,1},{.75,.84375},{0,0}}) do
        departure=truckProgressCase(truck,"departing",sample[1],sample[2]) and departure
    end
    check("room_truck_warehouse_share_eased_departure_progress",departure)

    local function progress(raw)
        truck.state,truck.backingProgress="backing",raw
        return truck:visualTravelProgress()
    end
    local startFirst=progress(.01)-progress(0)
    local startNext=progress(.02)-progress(.01)
    local endPrevious=progress(.99)-progress(.98)
    local endLast=progress(1)-progress(.99)
    check("room_truck_visual_travel_eases_in_and_out_at_both_ends",
        startFirst<startNext and endLast<endPrevious)

    truck.state,truck.backingProgress="backing",-1
    local low=truck:visualTravelProgress()
    truck.backingProgress=2
    local high=truck:visualTravelProgress()
    truck.state,truck.backingProgress="absent",1
    local absent=truck:visualTravelProgress()
    truck.state,truck.backingProgress="parked_closed",0
    local parked=truck:visualTravelProgress()
    check("room_truck_visual_travel_clamps_progress_and_preserves_state_endpoints",
        close(low,0) and close(high,1) and close(absent,0) and close(parked,1))
end
local function hire(s)
    local a=assert(Employees.createApplicant(s,0));a.shiftPreference="flexible"
    Employees.requestResume(s,a.id,0);Employees.advance(s,.5)
    assert(Employees.command(s,{kind="offer_employee",applicationId=a.id,expectedRevision=a.revision,
        wageCents=math.max(2400,a.requestedWage),days=31,startHour=9,endHour=17},.5))
    Employees.advance(s,1.25)
    assert(Employees.command(s,{kind="hire_employee",applicationId=a.id,expectedRevision=a.revision},1.25))
    local w=s.employment.staff[#s.employment.staff]
    w.visible,w.clockedIn,w.phase=true,true,"idle";w.x,w.y=560,550
    return w
end
local function job(s,id,scene)
    local j=assert(Jobs.createOffer({id=id,company="Loading bay QA",sourceSize={width=20,height=16},
        finishedSize={width=10,height=8},sheetCounts={500,500}}))
    Jobs.accept(j);j.status,j.delivery="in_production",{status="received"}
    s.jobs.active[#s.jobs.active+1]=j
    for n,p in ipairs(j.pallets) do
        p.location,p.status,p.wrapped,p.remainingSheets="warehouse","wrapped",true,0
        p.world={x=400+(n-1)*160,y=500,sceneId=scene or "warehouse",direction="northwest",spawnProgress=1}
    end
    assert(Service.requestPickup(s,j,100));return j
end
local function purchases(context,check)
    local s=shop();local money=s.money
    local ok=Bays.purchase(s,"front_left","GARAGE-A")
    local ok2=Bays.purchase(s,"front_right","GARAGE-B")
    local replay,_,code=Bays.purchase(s,"front_left","GARAGE-A")
    check("room_shipping_both_room_types_can_buy_garage_doors_once",ok and ok2 and replay and code=="replayed"
        and s.money==money-2*Bays.PRICE and Upgrades.validate(s.warehouse))
    local poor=shop();poor.money=0
    check("room_shipping_garage_purchase_rejects_unbuilt_wrong_room_and_no_cash",
        not Bays.purchase(State.new(),"front_left","LOCKED") and not Bays.purchase(poor,"front_left","POOR")
        and not Bays.purchase(s,"front_right","GARAGE-A") and poor.money==0)
    assert(context.save.save(3,s,context.world.snapshot()))
    local payload=assert(context.save.load(3))
    local loaded=State.new();assert(State.applySave(loaded,payload));context.save.delete(3)
    check("room_shipping_garage_doors_and_receipts_survive_disk_save",Bays.owns(loaded,"front_left")
        and Bays.owns(loaded,"front_right") and loaded.money==s.money and Upgrades.validate(loaded.warehouse))
    local Computer=require("src.screens.computer_screen").new()
    local Authority=require("src.office_authority").command({state=poor,warehouseEnabled=true,
        world={validateNetworkWorkshopAccess=function() return true end},save=function() end})
    poor.money=5000
    Computer.configureWarehouse({enabled=true,command=function(intent)
        return Authority.perform(nil,{id=1},{officeIntent=intent}) end})
    local view=Computer.warehouseView(poor)
    check("room_shipping_critter_net_lists_eligible_garage_purchase",view.bays[1].garageAvailable and not view.bays[1].garageOwned
        and Computer.warehouseButtonCenter("front_left","garage_door")~=nil)
    Computer.tab="warehouse"
    local x,y=Computer.warehouseButtonCenter("front_left","garage_door")
    local review=Computer.mousepressed(poor,x,y,1)
    x,y=Computer.warehouseButtonCenter("confirm")
    local bought=Computer.mousepressed(poor,x,y,1)
    check("room_shipping_critter_net_confirm_installs_at_host_price",review and review.action=="warehouse_confirmation"
        and bought and bought.action=="warehouse_purchased" and Bays.owns(poor,"front_left") and poor.money==5000-Bays.PRICE)
    saveCapture("critter-net",function() Computer.draw(poor,nil,nil,context.assets) end)
end
local function routes(context,check,scene)
    local s=shop();assert(Bays.purchase(s,scene,"GARAGE-"..scene))
    local w1,w2=hire(s),hire(s)
    Fleet.add(s,"SHIP-JACK-2",{x=510,y=575})
    local j=job(s,"SHIP-"..scene,scene)
    local other=job(s,"OTHER-"..scene)
    local world=context.world
    world.load();world.player.x,world.player.y=930,640
    world.player.sceneId="warehouse"
    world.configureEmployees({players=function() return {} end,canClaim=function() return false end,
        canLoadTruck=function() return true end})
    assert(world.truck:schedule(j.id,"pickup",Bays.pickupScene(s,j)))
    Service.schedulePickup(j,101);j.pickup.sceneId=scene
    world.truck.state,world.truck.backingProgress,world.truck.cargoProgress="cargo_open",1,1
    world.doorForScene(scene).state,world.doorForScene(scene).progress="open",1
    local ctx=world.employeeContext(s,context.assets)
    local simultaneous,crossed=false,false
    for _=1,3600 do
        Shipping.update(s,w1,.1,ctx);Shipping.update(s,w2,.1,ctx)
        if Fleet.owned(s,w1.id) and Fleet.owned(s,w2.id) then simultaneous=true end
        if (w1.sceneId or "warehouse")==scene or (w2.sceneId or "warehouse")==scene then crossed=true end
        if Service.remainingPickup(s,j.id)==0 then break end
    end
    local details=string.format("remaining=%d truck=%s pickup=%s / %s %.1f,%.1f %s / %s %.1f,%.1f %s / %s / %s",
        Service.remainingPickup(s,j.id),tostring(world.truck.sceneId),tostring(j.pickup and j.pickup.sceneId),
        w1.activity,w1.x,w1.y,w1.sceneId or "warehouse",
        w2.activity,w2.x,w2.y,w2.sceneId or "warehouse",
        tostring(j.pallets[1].world and j.pallets[1].world.sceneId or "none")..":"..j.pallets[1].location,
        tostring(j.pallets[2].world and j.pallets[2].world.sceneId or "none")..":"..j.pallets[2].location)
    check("room_shipping_two_employees_drive_loaded_jacks_through_"..scene,simultaneous and crossed
        and Service.remainingPickup(s,j.id)==0,details)
    check("room_shipping_correct_truck_manifest_"..scene,other.pallets[1].location=="warehouse"
        and other.pallets[2].location=="warehouse" and Pallets.validate(s))
    local capture=os.getenv("PICTURE_SHOP_ROOM_SHIPPING_CAPTURE_DIR")
    if capture then
        world._state=s;world.player.sceneId=scene;world.player.x,world.player.y=600,420
        local function draw() world.draw(context.assets,context.characterAssets,s,nil,nil,{}) end
        saveCapture(scene,draw)
        world.doorForScene(scene).state,world.doorForScene(scene).progress="closed",0
        saveCapture(scene.."-closed",draw)
        world.doorForScene(scene).state,world.doorForScene(scene).progress="open",1
    end
    world.player.sceneId="warehouse";world.player.x,world.player.y=930,640
    for _=1,1800 do
        Shipping.update(s,w1,.1,ctx);Shipping.update(s,w2,.1,ctx)
        if not Fleet.owned(s,w1.id) and not Fleet.owned(s,w2.id)
            and w1.sceneId=="warehouse" and w2.sceneId=="warehouse" then break end
    end
    check("room_shipping_jacks_return_and_park_after_"..scene,w1.sceneId=="warehouse" and w2.sceneId=="warehouse"
        and not Fleet.owned(s,w1.id) and not Fleet.owned(s,w2.id),w1.activity.." / "..w2.activity)
end
local function doorways(context,check)
    local s=shop();local j=job(s,"SHIP-DOORWAY")
    local jack=s.palletJack
    jack.sceneId="warehouse"
    jack.x,jack.y,jack.operating,jack.operatorPlayerId=648,250,true,1
    local p=j.pallets[1]
    p.location,p.world.x,p.world.y="on_pallet_jack",jack.x,jack.y
    jack.carriedPalletId=p.id
    local player={id=1,x=648,y=240,sceneId="warehouse"}
    local noEntry={assets=context.assets,obstacles=function() return {
        {x=100,y=321,halfWidth=180,halfHeight=180}} end}
    local denied,code=Rooms.transition(player,s,"front_left",noEntry)
    check("room_shipping_blocked_doorway_keeps_loaded_jack_and_skid_together",not denied and code=="doorway_blocked"
        and jack.sceneId=="warehouse" and jack.x==648 and p.world.x==648 and p.location=="on_pallet_jack",
        tostring(denied).." / "..tostring(code).." / "..tostring(jack.sceneId).." / "..jack.x.." / "..p.world.x)
    local access={assets=context.assets,obstacles=function() return {} end}
    local entered=Rooms.transition(player,s,"front_left",access)
    check("room_shipping_player_loaded_jack_lands_on_clear_room_floor",entered and jack.sceneId=="front_left"
        and p.world.sceneId=="front_left" and require("src.navigation").isAreaWalkable(
            Rooms.assets(context.assets,"front_left",s),jack.x,jack.y,
            Config.palletJack.loadedCollisionHalfWidth,Config.palletJack.loadedCollisionHalfHeight))
    player.x,player.y=Rooms.exit.x,Rooms.exit.y+20
    jack.x,jack.y=Rooms.exit.x,Rooms.exit.y+35
    check("room_shipping_loaded_jack_can_return_through_same_door",Rooms.transition(player,s,"warehouse",access)
        and jack.sceneId=="warehouse" and p.world.sceneId=="warehouse" and Pallets.validate(s))
end
local function wire(context,check)
    local world=context.world
    local s=shop();assert(Bays.purchase(s,"front_right","WIRE-DOOR"))
    local w=hire(s);w.sceneId,w.phase,w.x,w.y="front_right","pushing",830,360
    world.load();world._state=s
    world.truck:schedule("WIRE-PICKUP","pickup","front_right")
    world.roomDoors.front_right:open();world.roomDoors.front_right:update(.45)
    local snapshot=world.environmentSnapshot()
    snapshot.sessionId,snapshot.serverTick="room-docks-wire",7
    local Protocol=require("src.net.protocol")
    local packet,err=Protocol.encode("environment_snapshot",snapshot)
    local decoded=packet and Protocol.decode(packet)
    local client=require("src.net.session").new()
    client.mode,client.ready,client.sessionId="client",true,snapshot.sessionId
    if decoded then client:_handleClientEnvelope(decoded) end
    local event=client:drainEvents()[1]
    world.roomDoors.front_right:reset();world.truck:reset()
    local applied=event and world.applyEnvironmentSnapshot(event.bayDoor,event.truck,event.employees,s,event.technician,event.roomDoors)
    check("room_shipping_dock_truck_and_employee_scene_reach_guest",applied and #packet<=Protocol.MAX_PACKET_BYTES
        and world.truck.sceneId=="front_right" and world.roomDoors.front_right.state=="opening"
        and s._employeePoses[w.id].sceneId=="front_right",err)
    snapshot.roomDoors.front_right.progress=2
    check("room_shipping_wire_rejects_invalid_door_progress",not Protocol.encode("environment_snapshot",snapshot))
    local valid=snapshot.roomDoors.front_left
    check("room_shipping_malformed_door_update_is_atomic",not world.applyEnvironmentSnapshot(
        snapshot.bayDoor,snapshot.truck,nil,s,nil,{front_left=valid,front_right=valid,invalid=valid})
        and world.roomDoors.front_right.state=="opening")
end
local function fullCycle(context,check)
    local s=shop();assert(Bays.purchase(s,"front_right","CYCLE-GARAGE"))
    local w=hire(s);local j=job(s,"SHIP-FULL-CYCLE","front_right")
    s.palletJack.x,s.palletJack.y=200,600
    Fleet.add(s,"CYCLE-EXTRA-JACK",{x=560,y=520})
    local Calendar=require("src.business_calendar")
    s.calendar.elapsed=Calendar.secondsPerDay(s)*9.5/24
    s.employment.lastAtHours=Calendar.absoluteHours(s)
    w.shiftDay,w.breaksTaken=0,3
    local world=context.world
    world.load();world.player.x,world.player.y=930,640
    local blocked=true
    world.configureEmployees({players=function() return {} end,canClaim=function() return false end,
        canLoadTruck=function() return not blocked end})
    for _=1,100 do
        Calendar.update(s,.1);world.updateSimulation(.1,context.assets,s,.1)
    end
    check("room_shipping_ready_room_job_schedules_correct_room_truck",j.status=="pickup_in_progress"
        and world.truck.jobId==j.id and world.truck.sceneId=="front_right",
        string.format("job=%s pickup=%s truck=%s/%s worker=%s scene=%s pallet=%s:%s/%s",
            tostring(j.status),tostring(j.pickup and j.pickup.status),tostring(world.truck.jobId),
            tostring(world.truck.sceneId),w.activity,tostring(w.sceneId),tostring(j.pallets[1].location),
            tostring(j.pallets[1].status),tostring(j.pallets[1].world and j.pallets[1].world.sceneId)))
    check("room_shipping_waits_while_player_uses_manifest",j.pallets[1].location=="warehouse"
        and j.pallets[2].location=="warehouse" and not Fleet.owned(s,w.id))
    blocked=false
    local resumedLoad,resumedTruck=false,false
    for _=1,3600 do
        Calendar.update(s,.1);world.updateSimulation(.1,context.assets,s,.1)
        if #s.jobs.completed>0 then break end
        local loaded=Fleet.owned(s,w.id)
        local inTransit=not resumedLoad and loaded and loaded.carriedPalletId and loaded.sceneId=="front_right"
        local allLoaded=not resumedTruck and Service.remainingPickup(s,j.id)==0
        if inTransit or allLoaded then
            assert(context.save.save(3,s,world.snapshot()))
            local payload=assert(context.save.load(3))
            s=State.new();assert(State.applySave(s,payload));context.save.delete(3)
            w=s.employment.staff[1]
            world.load();world.player.x,world.player.y=930,640
            if inTransit then resumedLoad=true end
            if allLoaded then resumedTruck=true end
        end
    end
    check("room_shipping_reload_resumes_loaded_room_jack_and_loaded_truck",resumedLoad and resumedTruck)
    check("room_shipping_full_host_cycle_loads_departs_and_archives_once",#s.jobs.completed==1
        and #s.jobs.active==0 and world.truck.state=="absent" and Pallets.validate(s),
        w.activity.." / "..world.truck.state.." / remaining="..Service.remainingPickup(s,j.id))
    local money=s.money
    for _=1,30 do Calendar.update(s,.1);world.updateSimulation(.1,context.assets,s,.1) end
    check("room_shipping_departure_does_not_pay_twice",s.money==money and #s.jobs.completed==1)
end
local function loadingGuards(context,check)
    local s=shop();local w=hire(s)
    local j,other=job(s,"GUARD-RIGHT-TRUCK"),job(s,"GUARD-WRONG-TRUCK")
    local world=context.world;world.load()
    world.truck:schedule(j.id,"pickup","front_left");Service.schedulePickup(j,101)
    world.truck.state,world.truck.cargoProgress,world.truck.backingProgress="cargo_open",1,1
    local jack=Jack.ensure(s,Config.palletJack)
    jack.x,jack.y,jack.sceneId=851,386,"front_left"
    w.sceneId,w.x,w.y="front_left",851,400
    jack.operating,jack.operatorEmployeeId=true,w.id
    local wrong=other.pallets[1]
    wrong.location="on_pallet_jack";jack.carriedPalletId=wrong.id
    local blocked=false
    world.configureEmployees({canLoadTruck=function() return not blocked end})
    local refused=not world.loadEmployeePickup(s,w,wrong.id)
    check("room_shipping_wrong_job_is_never_transferred_to_truck",refused and wrong.location=="on_pallet_jack"
        and jack.carriedPalletId==wrong.id and j.pallets[1].location=="warehouse")
    wrong.location="warehouse"
    local p=j.pallets[1];p.location="on_pallet_jack";jack.carriedPalletId=p.id
    jack.sceneId="warehouse"
    local wrongScene=not world.loadEmployeePickup(s,w,p.id)
    jack.sceneId,jack.x,jack.y="front_left",400,500
    local far=not world.loadEmployeePickup(s,w,p.id)
    jack.x,jack.y,blocked=851,386,true
    local leased=not world.loadEmployeePickup(s,w,p.id)
    check("room_shipping_load_rechecks_room_range_and_player_manifest_lease",wrongScene and far and leased
        and p.location=="on_pallet_jack" and jack.carriedPalletId==p.id)
    blocked=false
    check("room_shipping_verified_truck_load_releases_only_its_jack",world.loadEmployeePickup(s,w,p.id)
        and p.location=="outbound_truck" and not jack.carriedPalletId and jack.operatorEmployeeId==w.id)
    check("room_shipping_floor_manifest_cannot_load_from_another_room",not world.loadPickupPallet(s,j.pallets[2].id)
        and j.pallets[2].location=="warehouse")
    local okay,code=world.validateNetworkWorkshopAccess({id=2,x=851,y=310,sceneId="front_right"},s,"truck")
    check("room_shipping_guest_must_use_the_trucks_actual_room",not okay and code=="wrong_scene")
end
function Test.run(context,check)
    local world=context.world
    local oldOptions=world._employeeOptions
    local oldState=world._state
    local oldPlayer={};for k,v in pairs(world.player) do oldPlayer[k]=v end
    truckVisualTravel(check)
    purchases(context,check)
    routes(context,check,"front_left");routes(context,check,"front_right")
    doorways(context,check);wire(context,check);fullCycle(context,check);loadingGuards(context,check)
    world.load();world.configureEmployees(oldOptions);world._state=oldState
    for k in pairs(world.player) do world.player[k]=nil end
    for k,v in pairs(oldPlayer) do world.player[k]=v end
end
return Test
