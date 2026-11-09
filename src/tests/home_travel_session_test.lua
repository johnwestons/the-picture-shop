local Session=require("src.net.session")
local Protocol=require("src.net.protocol")
local Harness=require("src.tests.support.network_impairment_harness")
local Flow=require("src.weekend_flow")
local Travel=require("src.home_travel")
local Layout=require("src.home_layouts")
local Schema=require("src.save_schema")
local Test={}
local function player(id,x,y)
    return {id=id,x=x,y=y,sceneId="warehouse",velocityX=0,velocityY=0,intentX=1,intentY=0,moving=false,
        facing=1,animationDistance=0,character="rabbit-worker"}
end
function Test.run(context,check)
    local state=context.State.new();state.home.weekend.phase="ready";state.home.weekend.closedAtHours=44
    local now=0
    local network=Harness.new({maxClients=3,classify=function(bytes) local value=Protocol.decode(bytes);return value and value.type or "invalid" end})
    local host=Session.new({transportFactory=network.factory,clock=function() return now end})
    local hp=player(1,720,202);local guests={};local contexts={};local locals={};local received={}
    local function players()
        local result={hp};for id,p in pairs(host.players) do if id~=1 then result[#result+1]=p end end;return result
    end
    local function command(p,cmd)
        local okay,code,message=Travel.command(state,p,cmd,{world={truck={state="absent"}},players=players})
        if okay then host:markShopDirty() end
        return okay,code,message,"homeTravel"
    end
    local hc={localPlayer=hp,moveRemote=function() end,
        bindResident=function(p,token,players)
            local id,reason=require("src.home_residents").bind(state,p,token,players)
            if id then host:markShopDirty() end
            return id,reason
        end,
        resolveGuestSpawn=function(x,y,id)
            if Travel.guestJoined(state,id) then host:markShopDirty() end
            if hp.sceneId=="home" then local a,b=Layout.spawn(state,id);return a,b,"home" end
            return x+id*20,y
        end,
        getShopSnapshot=function() return {state=assert(Schema.snapshot(state)),player={x=hp.x,y=hp.y,sceneId=hp.sceneId,character=hp.character}} end,
        performInteraction=function(p,kind,cmd)
            if kind=="homeTravel" then return command(p,cmd) end
            if kind=="homeFurniture" then
                local okay,message=require("src.home_furniture").command(state,p,cmd,players())
                if okay then host:markShopDirty() end
                return okay,okay and "changed" or "blocked",message,"homeFurniture"
            end
            if kind=="homeDelivery" then
                local okay,message=require("src.home_shopping").collect(state,p)
                if okay then host:markShopDirty() end
                return okay,okay and "received" or "blocked",message,"homeDelivery"
            end
            if kind=="homeActivity" then
                local okay,code,message=require("src.home_residents").command(state,p,cmd)
                if okay then host:markShopDirty() end
                return okay,code,message,"homeActivity"
            end
        end}
    assert(host:startHost({name="Weekend Host",character="rabbit-worker",addressOptions={socket={dns={
        gethostname=function() return "weekend-host" end,getaddrinfo=function() return {{addr="192.168.1.93"}} end}}}}))
    host.sessionId="weekend-session-test"
    local function pump(count)
        for _=1,count or 8 do
            now=now+.1;network:advanceSteps(1)
            for i,g in pairs(guests) do g:update(.1,contexts[i]) end
            host:update(.1,hc)
            for i,g in pairs(guests) do
                g:update(0,contexts[i])
                for _,event in ipairs(g:drainEvents()) do
                    received[i]=received[i] or {}
                    received[i][event.type]=event
                    if event.type=="ready" then
                        for k,v in pairs(event.spawn) do locals[i][k]=v end
                    end
                end
            end
            host:drainEvents()
        end
    end
    local function join(i)
        local g=Session.new({transportFactory=network.factory,clock=function() return now end})
        guests[i]=g;locals[i]=player(i+1,740,202);contexts[i]={localPlayer=locals[i],inputX=0,inputY=0}
        assert(g:startClient("192.168.1.93:22122",{name="Weekend Guest "..i,character="rabbit-worker",residentToken=string.rep(tostring(i),64)}))
        g.clientNonce="weekend-guest-"..i.."-"..math.floor(now*10)
        pump(10);return g
    end
    for i=1,3 do check("home_travel_session_join_"..i,join(i).ready) end
    for i=1,3 do check("home_session_private_resident_assigned_"..i,guests[i].residentId==host.players[i+1].homeResidentId
        and state.home.residents[guests[i].residentId]~=nil) end
    assert(command(hp,"request"));pump()
    local token=state.home.weekend.travelToken
    for i=1,3 do
        check("home_travel_session_request_replicated_"..i,received[i].shop_state
            and received[i].shop_state.state.home.weekend.travelToken==token)
    end
    assert(guests[1]:requestInteraction("homeTravel","force:"..token));pump()
    check("home_travel_session_guest_cannot_force",received[1].interaction_result
        and not received[1].interaction_result.accepted and hp.sceneId=="warehouse")
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeTravel","ready:"..token));pump()
    check("home_travel_session_duplicate_ready_once",state.home.weekend.readyMask==3)
    assert(guests[2]:requestInteraction("homeTravel","ready:"..token));pump()
    check("home_travel_session_waits_for_fourth_player",not command(hp,"depart:"..token))
    assert(command(hp,"force:"..token));pump(15)
    check("home_travel_session_host_brings_everyone",state.home.weekend.phase=="home" and hp.sceneId=="home")
    for i=1,3 do
        check("home_travel_session_guest_arrives_home_"..i,locals[i].sceneId=="home"
            and require("src.navigation").isWalkable(require("src.shop_rooms").assets(context.assets,"home",state),locals[i].x,locals[i].y,{}))
    end
    check("home_travel_session_departure_replay_rejected",not command(hp,"force:"..token) and state.home.weekend.transition==1)
    local a,b=Layout.toWorld(unpack(Layout.get(state).fixtures.bath.approach))
    for i=2,3 do host.players[i].x,host.players[i].y=a,b end
    local firstResident=state.home.residents[guests[1].residentId]
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeActivity","bathe:bath"));pump()
    check("home_session_duplicate_activity_starts_once",firstResident.activity and firstResident.revision==1)
    assert(guests[2]:requestInteraction("homeActivity","bathe:bath"));pump()
    check("home_session_shared_fixture_rejects_second_guest",received[2].interaction_result and not received[2].interaction_result.accepted)
    assert(guests[1]:requestInteraction("homeActivity","cancel"));pump()
    assert(guests[2]:requestInteraction("homeActivity","bathe:bath"));pump()
    check("home_session_fixture_releases_for_next_guest",received[2].interaction_result.accepted
        and state.home.residents[guests[2].residentId].activity~=nil)
    assert(guests[2]:requestInteraction("homeActivity","cancel"));pump()
    state.home.inventory.basic_meal=2
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeActivity","eat:floor"));pump()
    check("home_session_food_replay_cannot_consume_twice",state.home.inventory.basic_meal==1 and firstResident.activity.kind=="eat")
    assert(guests[1]:requestInteraction("homeActivity","cancel"));pump()
    local returningResident=guests[3].residentId;state.home.residents[returningResident].hunger=42
    local Cargo=require('src.home_bike_cargo')
    firstResident.bikeParkedAtHome=true;firstResident.bikeInventory=Cargo.new()
    firstResident.bikeInventory.items.bread=1
    local cargoTarget=assert(Cargo.target(host.players[2],state))
    host.players[2].x,host.players[2].y=cargoTarget.x,cargoTarget.y
    local breadBefore=state.home.inventory.bread or 0
    local breadAdded=require('src.home_shop_catalog').PRODUCTS.bread.servings
    received[1].interaction_result=nil
    network:duplicateNext('client_to_host',1,1,true)
    assert(guests[1]:requestInteraction('homeActivity','bike:all:0'));pump()
    local unloaded=received[1].interaction_result
    check('home_session_bike_cargo_acknowledged_and_applied_once',unloaded and unloaded.accepted
        and unloaded.code=='unloaded' and unloaded.message:find('unloaded',1,true)
        and state.home.inventory.bread==breadBefore+breadAdded and firstResident.bikeInventory.revision==1
        and received[2].shop_state.state.home.inventory.bread==breadBefore+breadAdded)
    received[1].interaction_result=nil
    assert(guests[1]:requestInteraction('homeActivity','bike:all:0'));pump()
    check('home_session_stale_bike_cargo_replied_without_timeout',received[1].interaction_result
        and not received[1].interaction_result.accepted and received[1].interaction_result.code=='blocked'
        and state.home.inventory.bread==breadBefore+breadAdded)
    host.players[2].x,host.players[2].y=0,0
    received[1].interaction_result=nil
    assert(guests[1]:requestInteraction('homeActivity','bike:all:1'));pump()
    check('home_session_distant_bike_cargo_replied_without_timeout',received[1].interaction_result
        and not received[1].interaction_result.accepted and received[1].interaction_result.code=='blocked')
    local Shopping=require("src.home_shopping")
    assert(Shopping.order(state,hp,{productId="pizza",quantity=1,requestId="session-pizza",expectedRevision=state.home.revision}))
    state.calendar.elapsed=state.calendar.elapsed+.5/24*state.calendar.secondsPerDay
    assert(Shopping.advance(state));host:markShopDirty();pump()
    local delivery=Shopping.target(hp,state)
    host.players[2].x,host.players[2].y=0,0
    assert(guests[1]:requestInteraction("homeDelivery","collect"));pump()
    check("home_session_delivery_checks_host_position",not received[1].interaction_result.accepted and Shopping.waiting(state)==1)
    host.players[2].x,host.players[2].y=delivery.x,delivery.y
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeDelivery","collect"));pump()
    check("home_session_duplicate_delivery_collects_once",received[1].interaction_result.accepted and state.home.inventory.pizza_slice==4
        and received[2].shop_state.state.home.inventory.pizza_slice==4)
    assert(guests[2]:requestInteraction("homeDelivery","collect"));pump()
    check("home_session_second_guest_cannot_collect_again",not received[2].interaction_result.accepted and state.home.inventory.pizza_slice==4)
    local Furniture=require("src.home_furniture")
    state.home.inventory.chair=1;Furniture.materialize(state,false);local chair=state.home.furniture.items[2]
    assert(guests[1]:requestInteraction("homeFurniture","begin:"..chair.id));pump()
    check("home_session_guest_furniture_requires_permission",not received[1].interaction_result.accepted and not chair.editor)
    assert(Furniture.command(state,hp,"permission:move:1",players()))
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeFurniture","begin:"..chair.id));pump()
    check("home_session_furniture_duplicate_begin_reserves_once",chair.editor==guests[1].residentId and state.home.furniture.nextEdit==2)
    assert(guests[2]:requestInteraction("homeFurniture","begin:"..chair.id));pump()
    check("home_session_furniture_edit_contention",not received[2].interaction_result.accepted)
    local token=chair.editToken
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeFurniture","store:"..chair.id..":"..token));pump()
    check("home_session_furniture_duplicate_commit_once",chair.revision==1 and not chair.editor and received[2].shop_state.state.home.furniture.items[2].revision==1)
    state.home.inventory.cup=2;Furniture.materialize(state,false)
    local cupA,cupB=state.home.furniture.items[3],state.home.furniture.items[4]
    local counterX,counterY=Layout.toWorld(unpack(Layout.get(state).laptop.approach))
    host.players[2].x,host.players[2].y=counterX,counterY
    host.players[3].x,host.players[3].y=counterX,counterY
    assert(guests[1]:requestInteraction("homeFurniture","begin:"..cupA.id));pump()
    assert(guests[2]:requestInteraction("homeFurniture","begin:"..cupB.id));pump()
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeFurniture","attach:"..cupA.id..":"..cupA.editToken..":0:2:east"));pump()
    check("home_session_duplicate_surface_attach_once",cupA.parentId==0 and cupA.slot==2 and cupA.revision==1 and not cupA.editor
        and received[2].shop_state.state.home.furniture.items[3].slot==2)
    assert(guests[2]:requestInteraction("homeFurniture","attach:"..cupB.id..":"..cupB.editToken..":0:2:east"));pump()
    check("home_session_surface_slot_contention",not received[2].interaction_result.accepted and cupB.location=="storage" and cupB.revision==0)
    host.players[3].x,host.players[3].y=0,0
    assert(guests[2]:requestInteraction("homeFurniture","attach:"..cupB.id..":"..cupB.editToken..":0:3:east"));pump()
    check("home_session_surface_uses_host_position",not received[2].interaction_result.accepted and cupB.location=="storage")
    assert(guests[2]:requestInteraction("homeFurniture","cancel:"..cupB.id..":"..cupB.editToken));pump()
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeActivity","object:pickup:"..cupA.id..":"..cupA.revision));pump()
    check("home_session_cup_pickup_duplicate_once",cupA.location=="carried" and cupA.revision==2 and cupA.holderId==guests[1].residentId
        and received[2].shop_state.state.home.furniture.items[3].holderId==guests[1].residentId)
    assert(guests[2]:requestInteraction("homeActivity","object:away:"..cupA.id..":"..cupA.revision));pump()
    check("home_session_cup_cannot_be_taken_from_other_resident",not received[2].interaction_result.accepted and cupA.location=="carried")
    local sx,sy=Layout.toWorld(unpack(Layout.get(state).fixtures.sink.approach))
    host.players[2].x,host.players[2].y=sx,sy;host.players[3].x,host.players[3].y=sx,sy
    assert(guests[1]:requestInteraction("homeActivity","cupfill:furniture"..cupA.id));pump()
    assert(guests[2]:requestInteraction("homeActivity","wash:sink"));pump()
    check("home_session_cup_fill_locks_shared_sink",not received[2].interaction_result.accepted and state.home.residents[guests[1].residentId].activity.fixtureId=="sink")
    local Calendar=require("src.business_calendar");local first=Calendar.absoluteHours(state)
    require("src.home_residents").advance(state,players(),first,first+1/60)
    state.calendar.elapsed=state.calendar.elapsed+Calendar.secondsPerDay(state)/1440;host:markShopDirty();pump()
    check("home_session_filled_cup_replicates",cupA.contents.water==1 and received[2].shop_state.state.home.furniture.items[3].contents.water==1)
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeActivity","cupdrink:furniture"..cupA.id));pump()
    check("home_session_cup_drink_consumes_once",cupA.contents.water==0 and cupA.contents.dirty and state.home.residents[guests[1].residentId].activity.kind=="cupdrink")
    assert(guests[1]:requestInteraction("homeActivity","cancel"));pump()
    state.home.inventory.mini_fridge=1;Furniture.materialize(state,false)
    local fridge=state.home.furniture.items[#state.home.furniture.items];fridge.location="floor";fridge.x=768;fridge.y=492
    assert(Furniture.canPlace(state,fridge,players()))
    local fridgeTarget=assert(Furniture.targets(state,hp)["furniture"..fridge.id])
    host.players[2].x,host.players[2].y=fridgeTarget.x,fridgeTarget.y
    host.players[3].x,host.players[3].y=fridgeTarget.x,fridgeTarget.y
    local pantryBefore=state.home.inventory.pizza_slice
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeActivity","object:put:"..fridge.id..":"..fridge.revision..":pizza_slice"));pump()
    check("home_session_fridge_duplicate_transfer_conserves_food",fridge.contents.pizza_slice==1 and state.home.inventory.pizza_slice==pantryBefore-1)
    local take="object:take:"..fridge.id..":"..fridge.revision..":pizza_slice"
    assert(guests[1]:requestInteraction("homeActivity",take));assert(guests[2]:requestInteraction("homeActivity",take));pump()
    check("home_session_two_guests_cannot_take_same_fridge_portion",fridge.contents.pizza_slice==0 and state.home.inventory.pizza_slice==pantryBefore
        and received[1].interaction_result.accepted~=received[2].interaction_result.accepted
        and received[3].shop_state.state.home.furniture.items[#state.home.furniture.items].contents.pizza_slice==0)
    state.home.inventory.desk_lamp=1;Furniture.materialize(state,false)
    local deskLamp=state.home.furniture.items[#state.home.furniture.items]
    deskLamp.location="surface";deskLamp.parentId=0;deskLamp.slot=2;deskLamp.direction="east"
    host.players[2].x,host.players[2].y=counterX,counterY
    local lampRevision=deskLamp.revision
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeActivity","object:on:"..deskLamp.id..":"..lampRevision));pump()
    check("home_session_desk_lamp_switch_replay_once",deskLamp.lit and deskLamp.revision==lampRevision+1
        and received[3].shop_state.state.home.furniture.items[#state.home.furniture.items].lit)
    assert(guests[2]:requestInteraction("homeActivity","object:off:"..deskLamp.id..":"..lampRevision));pump()
    check("home_session_stale_lamp_switch_cannot_undo",not received[2].interaction_result.accepted and deskLamp.lit)
    local lx,ly=Layout.toWorld(unpack(Layout.get(state).fixtures.laundry.approach))
    host.players[2].x,host.players[2].y=lx,ly;host.players[3].x,host.players[3].y=lx,ly
    local laundry=state.home.chores.laundry;local beforeDirty=laundry.dirty
    local function homeMinutes(minutes)
        local start=Calendar.absoluteHours(state)
        require("src.home_residents").advance(state,players(),start,start+minutes/60)
        state.calendar.elapsed=state.calendar.elapsed+Calendar.secondsPerDay(state)/1440*minutes;host:markShopDirty();pump()
    end
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeActivity","loadwash:laundry"));pump()
    assert(guests[2]:requestInteraction("homeActivity","loadwash:laundry"));pump()
    check("home_session_laundry_loading_is_exclusive",not received[2].interaction_result.accepted and laundry.dirty==beforeDirty)
    local Routine=require("src.home_routine_pose")
    local loading=assert(Routine.get(state,host.players[2]))
    for i=1,3 do
        local observerState=require("src.state").new()
        assert(require("src.state").applySharedSnapshot(observerState,received[i].shop_state.state))
        local remote=assert(Routine.get(observerState,{id=2,sceneId="home",character="rabbit-worker",x=lx,y=ly}))
        check("home_session_laundry_pose_observer_"..i,remote.action==loading.action and remote.frame==loading.frame
            and remote.x==loading.x and remote.y==loading.y)
    end
    homeMinutes(5)
    check("home_session_finished_loading_clears_pose",Routine.get(state,host.players[2])==nil)
    check("home_session_duplicate_load_starts_one_cycle",laundry.phase=="washing" and laundry.cycle==1 and laundry.dirty==beforeDirty-1
        and received[3].shop_state.state.home.chores.laundry.phase=="washing")
    homeMinutes(45)
    check("home_session_washer_readiness_replicates_without_free_clothes",laundry.phase=="ready" and laundry.clean==0
        and received[2].shop_state.state.home.chores.laundry.phase=="ready")
    network:duplicateNext("client_to_host",2,1,true)
    assert(guests[2]:requestInteraction("homeActivity","unload:laundry"));pump();homeMinutes(5)
    check("home_session_duplicate_unload_delivers_one_bundle",laundry.phase=="idle" and laundry.clean==1
        and received[1].shop_state.state.home.chores.laundry.clean==1)
    state.home.chores.soil.living=65;host.players[2].intentX,host.players[2].intentY=-1,-1
    assert(guests[1]:requestInteraction("homeActivity","sweep:floor"));pump()
    local sweeping=assert(Routine.get(state,host.players[2]))
    for i=1,3 do
        local observerState=require("src.state").new();assert(require("src.state").applySharedSnapshot(observerState,received[i].shop_state.state))
        local remote=assert(Routine.get(observerState,{id=2,sceneId="home",character="rabbit-worker",x=lx,y=ly,intentX=-1,intentY=-1}))
        check("home_session_sweep_direction_and_phase_"..i,remote.direction=="northwest" and remote.frame==sweeping.frame and remote.action==sweeping.action)
    end
    homeMinutes(8)
    check("home_session_finished_sweep_clears_body_and_tool",Routine.get(state,host.players[2])==nil and state.home.chores.soil.living<26)
    local tx,ty=Layout.spawn(state,1);host.players[2].x,host.players[2].y=tx,ty
    state.home.chores.trash=12
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeActivity","trash:floor"));pump();homeMinutes(1)
    local carrying=assert(Routine.get(state,host.players[2]))
    for i=1,3 do
        local observerState=require("src.state").new();assert(require("src.state").applySharedSnapshot(observerState,received[i].shop_state.state))
        local remote=assert(Routine.get(observerState,{id=2,sceneId="home",character="rabbit-worker",x=tx,y=ty,intentX=-1,intentY=-1}))
        check("home_session_trash_direction_and_phase_"..i,remote.action=="home_trash_northwest" and remote.frame==carrying.frame and remote.frame>=3)
    end
    homeMinutes(4)
    check("home_session_duplicate_trash_finishes_once",state.home.chores.trash==4 and Routine.get(state,host.players[2])==nil
        and received[3].shop_state.state.home.chores.trash==4)
    for _,cleaning in ipairs({{"wipe","sink","kitchen",5,30},{"scrub","bath","bathroom",8,15}}) do
        local kind,target,soil,minutes,remaining=unpack(cleaning)
        local cx,cy=Layout.toWorld(unpack(Layout.get(state).fixtures[target].approach))
        host.players[2].x,host.players[2].y=cx,cy;state.home.chores.soil[soil]=65
        network:duplicateNext("client_to_host",1,1,true)
        assert(guests[1]:requestInteraction("homeActivity",kind..":"..target));pump();homeMinutes(.5)
        local cleaningPose=assert(Routine.get(state,host.players[2]))
        for i=1,3 do
            local observerState=require("src.state").new();assert(require("src.state").applySharedSnapshot(observerState,received[i].shop_state.state))
            local remote=assert(Routine.get(observerState,{id=2,sceneId="home",character="rabbit-worker",x=cx,y=cy}))
            check("home_session_"..kind.."_cloth_and_pose_"..i,remote.action=="home_wipe_"..cleaningPose.direction
                and remote.frame==cleaningPose.frame and remote.x==cleaningPose.x and remote.y==cleaningPose.y)
        end
        homeMinutes(minutes-.5)
        check("home_session_duplicate_"..kind.."_finishes_once",state.home.chores.soil[soil]==remaining
            and Routine.get(state,host.players[2])==nil and received[3].shop_state.state.home.chores.soil[soil]==remaining)
    end
    state.home.inventory.bread=4;state.home.inventory.vegetables=4
    host.players[2].x,host.players[2].y=sx,sy;host.players[3].x,host.players[3].y=sx,sy
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeActivity","prepare:sink"));pump()
    assert(guests[2]:requestInteraction("homeActivity","prepare:sink"));pump()
    check("home_session_cooking_debit_once_and_station_exclusive",state.home.inventory.bread==3 and state.home.inventory.vegetables==3
        and not received[2].interaction_result.accepted)
    homeMinutes(5)
    local cook=state.home.residents[guests[1].residentId];local season="season:"..cook.revision
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeActivity",season));pump()
    check("home_session_cooking_timing_uses_host_clock_and_replicates",cook.activity.cookQuality==3 and cook.activity.cookTended
        and received[3].shop_state.state.home.residents[guests[1].residentId].activity.cookQuality==3)
    assert(guests[2]:requestInteraction("homeActivity",season));pump()
    check("home_session_guest_cannot_tend_someone_elses_batch",not received[2].interaction_result.accepted)
    homeMinutes(5)
    check("home_session_cooking_outputs_once_for_household",state.home.inventory.good_sandwich==2
        and received[2].shop_state.state.home.inventory.good_sandwich==2 and not cook.activity)
    assert(guests[1]:requestInteraction("homeActivity",season));pump()
    check("home_session_completed_cooking_rejects_replayed_timing",not received[1].interaction_result.accepted and state.home.inventory.good_sandwich==2)
    local Sleep=require("src.home_sleep");local Residents=require("src.home_residents")
    state.home.inventory.guest_mat=1;Furniture.materialize(state,false)
    local guestMat
    for _,item in ipairs(state.home.furniture.items) do if item.kind=="guest_mat" then guestMat=item end end
    assert(guestMat,"guest mat did not materialize")
    local matSpot=assert(require("src.tests.home_tables_lamp_test").findSpot(state,"guest_mat",{hp},guestMat.id))
    guestMat.location="floor";guestMat.x,guestMat.y=matSpot.x,matSpot.y
    local matTarget=assert(Furniture.targets(state,host.players[2])["furniture"..guestMat.id])
    host.players[2].x,host.players[2].y=matTarget.x,matTarget.y
    host.players[3].x,host.players[3].y=matTarget.x,matTarget.y
    assert(Residents.command(state,hp,"sleepfloor:floor"))
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeActivity","sleepmat:furniture"..guestMat.id));pump()
    check("home_session_guest_mat_sleep_replicates",Residents.get(state,host.players[2]).activity.kind=="sleepmat"
        and received[2].shop_state.state.home.residents[guests[1].residentId].activity.kind=="sleepmat")
    local Pose=require("src.home_activity_pose")
    local onHost=assert(Pose.get(state,host.players[2]))
    local observer={id=2,sceneId="home",x=host.players[2].x,y=host.players[2].y,character="rabbit-worker"}
    local onGuest=assert(Pose.get({home=received[2].shop_state.state.home},observer))
    check("home_session_mat_pose_matches_without_private_identity",onHost.kind=="sleeping" and onGuest.frame==onHost.frame
        and onGuest.x==onHost.x and onGuest.y==onHost.y and onGuest.item.id==guestMat.id)
    assert(guests[2]:requestInteraction("homeActivity","sleepmat:furniture"..guestMat.id));pump()
    check("home_session_guest_mat_contested_sleep_rejected",not received[2].interaction_result.accepted and not Residents.get(state,host.players[3]).activity)
    assert(guests[2]:requestInteraction("homeActivity","sleepfloor:floor"));pump()
    check("home_session_awake_guest_blocks_shared_sleep",not Sleep.status(state,players()))
    assert(guests[3]:requestInteraction("homeActivity","sleepfloor:floor"));pump()
    check("home_session_all_four_sleep_votes_replicate",Sleep.status(state,players())
        and received[1].shop_state.state.home.residents[guests[3].residentId].activity.kind=="sleepfloor")
    network:duplicateNext("client_to_host",1,1,true)
    assert(guests[1]:requestInteraction("homeActivity","alarm:0"));pump()
    check("home_session_personal_alarm_cannot_change_other_residents",Residents.get(state,host.players[2]).alarmAt~=nil
        and state.home.residents.owner.alarmAt==nil and Residents.get(state,host.players[3]).alarmAt==nil
        and received[2].shop_state.state.home.residents[guests[1].residentId].alarmAt~=nil)
    assert(guests[2]:requestInteraction("homeActivity","cancel"));pump()
    check("home_session_guest_wake_stops_acceleration",not Sleep.status(state,players()) and state.home.residents.owner.activity~=nil)
    assert(Residents.command(state,hp,"cancel"))
    assert(guests[1]:requestInteraction("homeActivity","cancel"));pump()
    assert(guests[3]:requestInteraction("homeActivity","cancel"));pump()
    check("home_session_wake_clears_replicated_pose",Pose.get(state,host.players[2])==nil
        and Pose.get({home=received[2].shop_state.state.home},observer)==nil)
    require("src.tests.support.home_utilities_session").run(state,host,guests,players,pump,network,received,check)
    require("src.tests.support.home_dining_session").run(state,host,guests,players,pump,network,received,check)
    local returningHunger=state.home.residents[returningResident].hunger
    guests[3]:stop("rejoin at home");guests[3]=nil;pump()
    received[3]=nil
    check("home_travel_session_join_at_home",join(3).ready and received[3].ready.spawn.sceneId=="home")
    check("home_session_reconnect_retains_resident_needs",guests[3].residentId==returningResident
        and received[3].ready.state.home.residents[returningResident].hunger==returningHunger)
    state.calendar=require("src.business_calendar").dateFromHours(107)
    state.calendar.elapsed=11/24*state.calendar.secondsPerDay
    hp.x,hp.y=Layout.spawn(state,1)
    assert(command(hp,"request"));pump();token=state.home.weekend.travelToken
    for i=1,3 do assert(guests[i]:requestInteraction("homeTravel","ready:"..token)) end
    pump()
    guests[3]:stop("replace ready guest");guests[3]=nil;pump();join(3)
    check("home_travel_session_new_guest_does_not_inherit_readiness",not Travel.ready(state.home.weekend,4)
        and not command(hp,"depart:"..token))
    assert(guests[3]:requestInteraction("homeTravel","ready:"..token));pump()
    assert(command(hp,"depart:"..token));pump(15)
    check("home_travel_session_all_ready_return",hp.sceneId=="warehouse" and state.home.weekend.transition==2)
    for i=1,3 do check("home_travel_session_guest_back_at_work_"..i,locals[i].sceneId=="warehouse") end
    for _,g in pairs(guests) do g:stop("test complete") end
    host:stop("test complete");network:dispose()
end
return Test
