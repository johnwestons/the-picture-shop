local Rooms=require("src.shop_rooms")
local Layout=require("src.warehouse_layout")
local State=require("src.state")
local Schema=require("src.save_schema")
local Storage=require("src.pallet_storage")
local Upgrades=require("src.warehouse_upgrades")
local Procurement=require("src.procurement")
local Config=require("src.config")
local Protocol=require("src.net.protocol")
local Codec=require("src.net.codec")
local Session=require("src.net.session")
local Harness=require("src.tests.support.network_impairment_harness")
local Gameplay=require("src.warehouse_gameplay")
local Jack=require("src.pallet_jack")
local Rack=require("src.screens.pallet_rack_screen")
local Controls=require("src.shop_room_controls")
local Test={}
local function complete(state,id,kind,number)
    local now=(number-1)*100
    assert(Upgrades.purchase(state,id,kind,"ROOM-"..id,now))
    Upgrades.update(state,now)
    local project=string.format("WUP-%04d",number)
    Upgrades.update(state,now,{noticeDeliveredProjectId=project,noticeCallId="CALL-"..number})
    Upgrades.update(state,now+2,{workerArrivedProjectId=project})
    Upgrades.update(state,now+98)
    Upgrades.update(state,now+98,{workerReleasedProjectId=project})
    if kind=="storage" then state.storage.racks[id.."-rack"]=Storage.rackDefinition(id) end
end
local function fixture()
    local state=State.new();state.money=50000
    complete(state,"front_left","storage",1)
    complete(state,"front_right","breakroom",2)
    return state
end
local function player(id,x,y)
    return {id=id,x=x,y=y,sceneId="warehouse",velocityX=0,velocityY=0,intentX=0,intentY=0,
        moving=false,facing=1,animationDistance=0,character="rabbit-worker",speed=155}
end
local function nearEntrance(id) return player(id,Rooms.entrance.x,Rooms.entrance.y+20) end
local function capture(context,state,sceneId,name,pose,overlay)
    local world=context.world
    local before={};for k,v in pairs(world.player) do before[k]=v end
    local oldState,oldSelection=world._state,world.selectedInteraction
    world.player.sceneId,world.player.x,world.player.y=sceneId,pose and pose.x or 500,pose and pose.y or 380
    world.player.resting=pose and pose.resting or false
    world._state=state;world.selectedInteraction=nil
    local canvas=love.graphics.newCanvas(960,678)
    love.graphics.push("all");love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(0,0,0,1)
    world.draw(context.assets,context.characterAssets,state,nil,nil,{})
    if overlay then overlay() end
    love.graphics.pop()
    local bytes=canvas:newImageData():encode("png"):getString()
    local source=love.filesystem.getSource()
    local output=os.getenv("PICTURE_SHOP_ROOM_CAPTURE_DIR") or (not source:match("%.love$") and source.."/.stabilization")
    if output then
        local file=assert(io.open(output.."/"..name..".png","wb"));file:write(bytes);file:close()
    end
    canvas:release()
    for k in pairs(world.player) do world.player[k]=nil end
    for k,v in pairs(before) do world.player[k]=v end
    world._state,world.selectedInteraction=oldState,oldSelection
end
local function stock(state)
    local okay,order=Procurement.buy(state,4,1);assert(okay)
    assert(Procurement.unload(state,order.id,order.pallets[1].id,Config.palletLogistics.spawnPoints,Config.palletLogistics.unloadOrigin))
    local pallet=order.pallets[1]
    pallet.world={x=Rooms.entrance.x,y=Rooms.entrance.y+70,spawnProgress=1}
    return pallet
end
local function baseShelves(context,test)
    local oldAssets=context.world._assets
    context.world._assets=context.assets
    for column=1,5 do
        local state=State.new();state.money=50000
        local p=stock(state)
        local point=Layout.rackPoint("warehouse-rack",1,column)
        local jack=state.palletJack
        jack.x,jack.y,jack.direction=point.x,point.groundY+65,"north"
        jack.operating,jack.operatorPlayerId,jack.carriedPalletId=true,1,p.id
        p.location="on_pallet_jack"
        local x,y=Jack.operatorPosition(state,Config.palletJack)
        local worker=player(1,x,y)
        local access=context.world.warehouseRackContext(worker,state,"warehouse-rack",1,column)
        local okay,code=context.world.warehouseCommand(worker,state,{kind="store",requestId="BASE-STORE",expectedRevision=0,
            vehicle="pallet_jack",palletId=p.id,rackId="warehouse-rack",row=1,column=column})
        local screen=Rack.new("warehouse-rack",{context=function() return access end,onIntent=function() return true end})
        screen.selected={row=1,column=column}
        test("base_shelf_"..column.."_physically_stores_and_gui_retrieves",okay and p.location=="rack"
            and Gameplay.nearRack(worker,state)=="warehouse-rack" and screen:view(state).canRetrieve,code)
        test("base_shelf_"..column.."_roundtrip",context.world.warehouseCommand(worker,state,{kind="retrieve",requestId="BASE-TAKE",
            expectedRevision=1,vehicle="pallet_jack",palletId=p.id,rackId="warehouse-rack",row=1,column=column})
            and jack.carriedPalletId==p.id and p.location=="on_pallet_jack" and Storage.validate(state))
    end
    context.world._assets=oldAssets
end
local function menuTests(context,state,test)
    local p=nearEntrance(1)
    local saves=0
    local runtime={state=state,World={player=p,getInteraction=function() return {kind="shopEntrance"} end,
        performNetworkInteraction=function(player,shop,kind,command) return Rooms.perform(player,shop,kind,command,{obstacles=function() return {} end}) end},
        multiplayer={isClient=function() return false end},saveCurrent=function() saves=saves+1 end}
    runtime.toPointerCoordinates=function(x,y) return x,y end
    require("src.runtime.pointer_dispatch").install(runtime)
    state.screen="world"
    Controls.keypressed("e",runtime)
    test("keyboard_opens_front_entrance_menu",state.screen=="shop_rooms")
    capture(context,state,"warehouse","shop-entrance-menu",nil,function() Controls.draw(runtime) end)
    runtime.dispatchMousePressed(350,258,1)
    test("desktop_pointer_row_enters_only_selected_room",state.screen=="world" and p.sceneId=="front_left")
    p.x,p.y=Rooms.shelves.x,Rooms.shelves.y
    runtime.World.getInteraction=function() return {kind="roomStock"} end
    stock(state)
    Controls.keypressed("e",runtime);Controls.keypressed("return",runtime)
    test("stock_menu_stores_and_uses_save_boundary",saves==1)
    capture(context,state,"front_left","storage-room-stock-menu",nil,function() Controls.draw(runtime) end)
    Controls.mousepressed(350,258,1,runtime)
    test("stock_menu_touch_retrieval_is_saved",saves==2)
    Controls.keypressed("escape",runtime)
    local Camera=require("src.runtime.camera")
    runtime.App={mobileCamera={isEnabled=function() return true end}}
    Camera.install(runtime)
    state.screen="shop_rooms"
    test("room_menu_fits_mobile_screen_without_camera_pan",runtime.App.officeFitsScreen() and not runtime.App.cameraTransformsUi())
    local Viewport=require("src.viewport")
    local dimensions,safeArea=love.graphics.getDimensions,love.window.getSafeArea
    for _,size in ipairs({{1920,1080},{1280,720},{844,390},{390,844}}) do
        love.graphics.getDimensions=function() return size[1],size[2] end
        love.window.getSafeArea=function() return 12,8,size[1]-24,size[2]-16 end
        local ox,oy,scale=Viewport.transform(960,678,true)
        local x,y=Viewport.toGame(ox+350*scale,oy+258*scale,960,678,true)
        test("room_menu_fits_and_touch_maps_"..size[1].."x"..size[2],ox>=12 and oy>=8
            and ox+960*scale<=size[1]-12 and oy+678*scale<=size[2]-8 and math.abs(x-350)<.001 and math.abs(y-258)<.001)
    end
    love.graphics.getDimensions,love.window.getSafeArea=dimensions,safeArea
    state.screen="world"
    test("warehouse_shortcuts_cannot_cross_scenes",Controls.keypressed("l",runtime) and Controls.keypressed("m",runtime))
end
local function liveSimulation(context,test)
    local world=context.world
    local fields={"player","bayDoor","truck","customer","vendor","_state","_assets","selectedInteraction","placementSelection"}
    local old={};for _,k in ipairs(fields) do old[k]=world[k] end
    world.player={}
    world.bayDoor=require("src.bay_door").new(Config.loadingBay)
    world.truck=require("src.truck").new(Config.truck)
    world.customer=require("src.customer").new(Config.customer)
    world.vendor=require("src.customer").new(Config.vendor)
    world.load({id=1,x=500,y=380,sceneId="front_right",character="rabbit-worker"})
    local state=fixture();state.screen="world";state.calendar.weekday=4;state.employment.recruiting=false
    world.customer.timer,world.vendor.timer=0,1000
    assert(world.truck:schedule("room-simulation-truck","delivery"))
    for _=1,160 do world.update(.1,0,0,context.assets,state,nil,nil,.1) end
    test("host_in_break_room_keeps_warehouse_truck_moving",world.truck.state=="parked_closed",world.truck.state)
    test("host_in_break_room_keeps_reception_visitors_moving",world.customer.state=="waiting",world.customer.state)
    test("warehouse_simulation_does_not_move_host_between_scenes",world.player.sceneId=="front_right"
        and world.player.x==500 and world.player.y==380)
    local restPoint=world.employeeContext(state,context.assets).seat("front_right")
    test("employee_breakroom_route_uses_front_entrance",restPoint and restPoint.bayId=="front_right"
        and restPoint.x==Rooms.entrance.x)
    for _,k in ipairs(fields) do world[k]=old[k] end
end
function Test.run(context,check)
    local function test(name,value,detail) check("shop_rooms_"..name,value,detail) end
    local state=fixture()
    local adapted=Rooms.assets(context.assets,"warehouse")
    local repeated=adapted
    for _=1,1000 do repeated=Gameplay.assets(repeated,state) end
    test("navigation_adapter_is_stable_over_long_sessions",repeated==adapted
        and rawget(repeated,"_shopRoomSource")==context.assets)
    local roomAssets=Rooms.assets(repeated,"front_left")
    test("scene_masks_reuse_cache_without_nesting",Rooms.assets(roomAssets,"warehouse")==adapted
        and Rooms.assets(context.assets,"front_left")==roomAssets
        and roomAssets.getData("walkmask")==Rooms.assets(adapted,"front_left").getData("walkmask"))
    baseShelves(context,test)
    liveSimulation(context,test)
    test("playable_rabbit_has_registered_seated_sprite",context.characterAssets.hasAction("rabbit-worker","sit"))
    test("selected_art_is_runtime_background",Config.paths.warehouse=="assets/generated/warehouse-open-office-v1.png")
    for _,kind in ipairs({"storage","breakroom","floor"}) do
        local im=love.image.newImageData(Rooms.paths[kind]);local w,h=im:getDimensions();im:release()
        test(kind.."_has_real_full_size_sprite",w==1536 and h==1024)
    end
    test("floor_edges_and_open_office_are_walkable",Rooms.walkable(20,590) and Rooms.walkable(940,610)
        and Rooms.walkable(Config.interactables.computer.x,Config.interactables.computer.y))
    test("rear_rack_and_walls_are_blocked",not Rooms.walkable(390,80) and not Rooms.walkable(615,170))
    test("upgrades_do_not_reserve_warehouse_floor",not Layout.isReserved(state,100,570)
        and not Layout.isReserved(state,860,570))
    test("base_shelves_exist_without_purchase",State.new().storage.racks["warehouse-rack"]~=nil)
    local a,b=nearEntrance(1),nearEntrance(2)
    test("one_player_enters_storage",Rooms.transition(a,state,"front_left"))
    test("other_player_stays_in_warehouse",a.sceneId=="front_left" and b.sceneId=="warehouse" and not Rooms.sameScene(a,b))
    test("different_player_enters_breakroom",Rooms.transition(b,state,"front_right"))
    test("players_are_in_independent_rooms",a.sceneId=="front_left" and b.sceneId=="front_right")
    a.x,a.y=500,400
    test("teleport_requires_exit_proximity",not Rooms.transition(a,state,"warehouse"))
    a.x,a.y=Rooms.exit.x,Rooms.exit.y
    test("exit_returns_only_that_player",Rooms.transition(a,state,"warehouse") and b.sceneId=="front_right")
    local locked=State.new();local c=nearEntrance(3)
    test("unpurchased_rooms_reject_entry",not Rooms.transition(c,locked,"front_left"))
    c.x,c.y=500,500
    test("warehouse_room_entry_checks_host_position",not Rooms.transition(c,state,"front_left"))
    c=nearEntrance(3);state.palletJack.operating=true;state.palletJack.operatorPlayerId=3
    test("vehicles_must_be_parked_before_travel",not Rooms.transition(c,state,"front_left"))
    state.palletJack.operating=false;state.palletJack.operatorPlayerId=nil
    local okay,order=Procurement.buy(state,4,1);assert(okay)
    assert(Procurement.unload(state,order.id,order.pallets[1].id,Config.palletLogistics.spawnPoints,Config.palletLogistics.unloadOrigin))
    local pallet=order.pallets[1];pallet.world={x=Rooms.entrance.x,y=Rooms.entrance.y+70,spawnProgress=1}
    local count=pallet.quantity
    a.sceneId,a.x,a.y="front_left",Rooms.shelves.x,Rooms.shelves.y
    test("stock_transfer_uses_existing_pallet",Rooms.perform(a,state,"roomStock","store:"..pallet.id)
        and pallet.location=="rack" and pallet.storage.rackId=="front_left-rack" and pallet.quantity==count)
    local revision=state.storage.revision
    test("duplicate_store_has_no_second_mutation",Rooms.perform(a,state,"roomStock","store:"..pallet.id)
        and state.storage.revision==revision and #Rooms.stockItems(state,"front_left")==1)
    test("different_room_cannot_retrieve_stock",not Rooms.perform(b,state,"roomStock","retrieve:"..pallet.id))
    test("blocked_retrieval_is_atomic",not Rooms.perform(a,state,"roomStock","retrieve:"..pallet.id,
        {obstacles=function() return {{x=Rooms.entrance.x,y=Rooms.entrance.y+100,halfWidth=400,halfHeight=200}} end})
        and pallet.location=="rack" and state.storage.revision==revision)
    state.storage.revision=2147483647
    test("revision_limit_rejects_mutation",not Rooms.perform(a,state,"roomStock","retrieve:"..pallet.id) and pallet.location=="rack")
    state.storage.revision=revision
    test("stored_pallet_ownership_is_valid",Storage.validate(state))
    local saved=Schema.snapshot(state);local loaded=State.new();local valid,errors=State.applySave(loaded,{state=saved})
    test("stock_and_rooms_survive_save_reload",valid and loaded.procurement.orders[1].pallets[1].storage.rackId=="front_left-rack",errors and table.concat(errors,"; "))
    test("stock_retrieval_preserves_quantity",Rooms.perform(a,state,"roomStock","retrieve:"..pallet.id,{obstacles=function() return {} end})
        and pallet.location=="warehouse" and pallet.storage==nil and pallet.quantity==count)
    test("second_retrieval_is_rejected",not Rooms.perform(a,state,"roomStock","retrieve:"..pallet.id))
    local Jobs=require("src.jobs")
    local legacyJob=assert(Jobs.createOffer({id="ROOM-LEGACY",company="Legacy shelved job",
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500}}))
    Jobs.accept(legacyJob);state.jobs.active[#state.jobs.active+1]=legacyJob
    local legacyPallet=legacyJob.pallets[1]
    legacyPallet.location,legacyPallet.storage,legacyPallet.world="rack",{rackId="front_left-rack",row=1,column=1},nil
    test("legacy_customer_stock_can_be_retrieved_from_converted_room",Rooms.perform(a,state,"roomStock","retrieve:"..legacyPallet.id,{obstacles=function() return {} end})
        and legacyPallet.location=="warehouse" and Storage.validate(state))
    legacyPallet.world={x=Rooms.entrance.x,y=Rooms.entrance.y+70}
    test("new_customer_stock_stays_on_base_shelves",not Rooms.perform(a,state,"roomStock","store:"..legacyPallet.id)
        and legacyPallet.location=="warehouse")
    b.x,b.y=Rooms.rest.x,Rooms.rest.y
    test("breakroom_rest_is_authoritative",Rooms.perform(b,state,"roomRest","rest") and b.resting)
    test("breakroom_seating_uses_chair_contact",b.x==Rooms.seats[2].x and b.y==Rooms.seats[2].y)
    local chairUser=player(3,Rooms.seats[3].x,Rooms.seats[3].y);chairUser.sceneId="front_right";chairUser.resting=true
    local newcomer=player(3,Rooms.rest.x,Rooms.rest.y);newcomer.sceneId="front_right"
    test("occupied_chair_uses_another_seat",Rooms.perform(newcomer,state,"roomRest","rest",{players=function() return {chairUser} end})
        and newcomer.x~=chairUser.x)
    context.world.updateRemotePlayer(b,.1,1,0,context.assets,state)
    test("movement_stands_on_walkable_floor",not b.resting and Rooms.walkable(b.x,b.y,b.sceneId))
    test("other_scene_cannot_operate_machine",not context.world.validateNetworkWorkshopAccess(b,state,"cutter"))
    local wire=assert(Protocol.encode("snapshot",{sessionId="ROOMS",serverTick=1,
        players=Codec.array({{id=2,name="Guest",sceneId="front_right",resting=true,x=100,y=270,
            velocityX=0,velocityY=0,intentX=0,intentY=0,moving=false,facing=1,animationDistance=0,
            character="rabbit-worker",inputSequence=0}})}))
    local decoded=assert(Protocol.decode(wire))
    test("scene_and_rest_survive_wire_validation",decoded.payload.players[1].sceneId=="front_right" and decoded.payload.players[1].resting)
    local network=Harness.new({maxClients=1,classify=function(bytes) local e=Protocol.decode(bytes);return e and e.type or "invalid" end})
    local now=0
    local function clock() return now end
    local host=Session.new({transportFactory=network.factory,clock=clock});local guest=Session.new({transportFactory=network.factory,clock=clock})
    local hp,gp=nearEntrance(1),nearEntrance(2)
    local hc={localPlayer=hp,moveRemote=function(p,dt,x,y) context.world.updateRemotePlayer(p,dt,x,y,context.assets,state) end,
        resolveGuestSpawn=function() return Rooms.entrance.x,Rooms.entrance.y+20 end,
        getShopSnapshot=function() return {state=Schema.snapshot(state),player={x=hp.x,y=hp.y,character=hp.character}} end,
        performInteraction=function(p,kind,command) return context.world.performNetworkInteraction(p,state,kind,command) end}
    local gc={localPlayer=gp,inputX=0,inputY=0}
    assert(host:startHost({name="Room Host",character="rabbit-worker",localPlayer=hp,
        addressOptions={socket={dns={gethostname=function() return "host" end,toip=function() return "192.168.1.2" end}}}}))
    assert(guest:startClient("192.168.1.2:22122",{name="Room Guest",character="rabbit-worker"}))
    local function pump(n)
        for _=1,n do now=now+.1;network:advanceSteps(1);host:update(.1,hc);guest:update(.1,gc) end
    end
    pump(12)
    test("real_session_guest_is_ready",guest.ready)
    assert(Rooms.transition(hp,state,"front_right"));host:_syncLocalPlayer(hp)
    assert(guest:requestInteraction("shopRoom","front_left"));pump(10)
    test("host_and_guest_replicate_different_scenes",hp.sceneId=="front_right" and gp.sceneId=="front_left"
        and host.players[2].sceneId=="front_left" and guest.players[1].sceneId=="front_right")
    test("room_spawn_snaps_without_cross_scene_smoothing",gp.x==Rooms.exit.x and gp.y==Rooms.exit.y+38)
    gc.inputX,gc.inputY=1,1;pump(12)
    test("guest_can_walk_inside_room_while_host_stays",gp.x>Rooms.exit.x+20 and hp.sceneId=="front_right")
    test("cross_scene_high_five_is_rejected",not host:_createHighFive(1,2))
    gc.inputX,gc.inputY=0,0
    host.players[2].x,host.players[2].y=Rooms.shelves.x,Rooms.shelves.y
    local netStock=stock(state)
    assert(guest:requestInteraction("roomStock","store:"..netStock.id));pump(12)
    local validStock,stockErrors=Storage.validate(state)
    local replies={};for _,event in ipairs(guest:drainEvents()) do if event.type=="interaction_result" then replies[#replies+1]=event.code or event.message or "reply" end end
    test("guest_stock_transfer_runs_on_host",netStock.location=="rack" and validStock,
        netStock.location.." / "..table.concat(replies,",").." / "..table.concat(stockErrors or {},","))
    revision=state.storage.revision
    assert(guest:requestInteraction("roomStock","store:"..netStock.id));pump(12)
    test("reliable_repeated_stock_request_preserves_single_owner",state.storage.revision==revision and netStock.location=="rack")
    host:stop("test complete");guest:stop("test complete");network:dispose()
    local renderState=fixture()
    for i=1,10 do
        local load=stock(renderState)
        load.location="rack";load.storage={rackId="warehouse-rack",row=i<=5 and 1 or 2,column=(i-1)%5+1}
        load.world=Layout.rackPoint("warehouse-rack",load.storage.row,load.storage.column)
        local roomLoad=stock(renderState)
        local sitter=player(1,Rooms.shelves.x,Rooms.shelves.y);sitter.sceneId="front_left"
        assert(Rooms.transfer(sitter,renderState,"store",roomLoad.id))
    end
    local overflow=stock(renderState)
    local stockWorker=player(1,Rooms.shelves.x,Rooms.shelves.y);stockWorker.sceneId="front_left"
    local stockRevision=renderState.storage.revision
    local stored,fullCode=Rooms.transfer(stockWorker,renderState,"store",overflow.id)
    test("full_storage_room_rejects_eleventh_pallet_atomically",not stored and fullCode=="room_full"
        and overflow.location=="warehouse" and renderState.storage.revision==stockRevision)
    renderState.storage.revision=-1
    stored,fullCode=Rooms.transfer(stockWorker,renderState,"store",overflow.id)
    test("invalid_stock_registry_cannot_be_mutated",not stored and fullCode=="invalid_state" and overflow.location=="warehouse")
    renderState.storage.revision=stockRevision
    capture(context,renderState,"warehouse","warehouse-integrated")
    capture(context,renderState,"front_left","storage-room-integrated")
    capture(context,renderState,"front_right","break-room-integrated",{x=Rooms.seats[1].x,y=Rooms.seats[1].y,resting=true})
    local progress=context.world.bayDoor.progress
    context.world.bayDoor.progress=1
    capture(context,renderState,"warehouse","warehouse-open-dock")
    context.world.bayDoor.progress=progress
    menuTests(context,fixture(),test)
    test("all_scenes_render_without_errors",true)
end
return Test
