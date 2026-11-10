local Test={}
function Test.run(context,check)
    local Session=require('src.net.session')
    local Protocol=require('src.net.protocol')
    local Harness=require('src.tests.support.network_impairment_harness')
    local Residents=require('src.home_residents')
    local Travel=require('src.home_travel')
    local Trip=require('src.commute.trip')
    local C=require('src.commute.runtime')
    local Schema=require('src.save_schema')
    local state=context.State.new()
    state.calendar.elapsed=require('src.business_calendar').secondsPerDay(state)*10/24
    state.home.town=assert(require('src.commute.town').generate(712345))
    state.home.townCharacters=require('src.commute.town_characters').defaultState(state.home.town)
    local now=0
    local network=Harness.new({maxClients=3,classify=function(bytes)local v=Protocol.decode(bytes);return v and v.type or 'invalid' end})
    local host=Session.new({transportFactory=network.factory,clock=function()return now end})
    local function player(id)
        return {id=id,x=300,y=335,sceneId='warehouse',velocityX=0,velocityY=0,intentX=1,intentY=0,
            moving=false,facing=1,animationDistance=0,character='rabbit-worker'}
    end
    local hp=player(1)
    local R={state=state,multiplayer=host,World={player=hp},Config=context.Config or require('src.config'),saveCurrent=function()end}
    R.World.resolveNetworkSpawn=function(x,y,id)return x+(id-1)*20,y end
    local world=C.world(R)
    local guests,locals,contexts,received={},{},{},{}
    local function players()return require('src.weekend_runtime').players(R)end
    local function depart(p,cmd)
        local okay,code,message=Travel.command(state,p,cmd,{players=players,commuteWorld=world,world={truck={state='absent'}}})
        if okay then host:markShopDirty() end
        return okay,code,message,'homeTravel'
    end
    local hc={localPlayer=hp,moveRemote=function(p,dt,x,y)
        if not state.home.commute or not state.home.commute.participants[Residents.key(p)] then
            p.x=p.x+x*dt*50;p.y=p.y+y*dt*50
        end
    end,bindResident=function(p,token,connected)
        local id,reason=Residents.bind(state,p,token,connected)
        if id then local okay,why=C.bind(R,p,connected);if not okay then return nil,why end;host:markShopDirty() end
        return id,reason
    end,resolveGuestSpawn=function(x,y,id)return x+id*20,y end,
        getShopSnapshot=function()return {state=assert(Schema.snapshot(state)),player={x=hp.x,y=hp.y,sceneId=hp.sceneId,character=hp.character}}end,
        performInteraction=function(p,kind,cmd)
            if kind=='homeTravel' then return depart(p,cmd) end
            if kind=='commute' then return C.command(R,p,cmd) end
        end}
    assert(host:startHost({name='Independent Host',character=hp.character,addressOptions={socket={dns={
        gethostname=function()return 'scene-host'end,getaddrinfo=function()return {{addr='192.168.1.93'}}end}}}}))
    host.sessionId='independent-scenes'
    local function pump(n)
        for _=1,n or 8 do
            now=now+.1;network:advanceSteps(1)
            for i,g in pairs(guests) do g:update(.1,contexts[i]) end
            host:update(.1,hc)
            -- Exercise the real outdoor authority with an indoor host: no renderer.
            C.update(R,.1,0,0,false)
            for i,g in pairs(guests) do
                g:update(0,contexts[i])
                for _,e in ipairs(g:drainEvents()) do
                    received[i]=received[i] or {};received[i][e.type]=e
                    if e.type=='ready' then for k,v in pairs(e.spawn) do locals[i][k]=v end end
                end
            end
            host:drainEvents()
        end
    end
    local function join(i,credential)
        local g=Session.new({transportFactory=network.factory,clock=function()return now end})
        guests[i]=g;locals[i]=player(i+1);contexts[i]={localPlayer=locals[i],inputX=0,inputY=0}
        assert(g:startClient('192.168.1.93:22122',{name='Guest '..i,character=hp.character,residentToken=string.rep(tostring(credential or i),64)}))
        g.clientNonce='independent-'..i..'-'..math.floor(now*10);pump(10)
        assert(g.ready,('Guest %d failed to join: %s'):format(i,tostring(g.status)))
        return g
    end
    for i=1,3 do join(i) end
    local function entrance(p)
        local target=assert(Travel.target(p,state));p.x,p.y=target.x,target.y
    end
    local p2,p3,p4=host.players[2],host.players[3],host.players[4]
    p4.sceneId='front_left'
    entrance(p2);state.screen='computer'
    network:duplicateNext('client_to_host',1,1,true)
    assert(guests[1]:requestInteraction('homeTravel','explore'));pump()
    local t=assert(state.home.commute);local token=t.token
    local part=t.participants[guests[1].residentId]
    check('independent_guest_departure_keeps_other_scenes',received[1].interaction_result.accepted
        and p2.sceneId=='commute' and hp.sceneId=='warehouse' and p3.sceneId=='warehouse' and p4.sceneId=='front_left')
    check('independent_host_keeps_menu_and_skips_outdoor_gpu',state.screen=='computer' and not R._commute.renderer and not C.active(R))
    check('independent_guest_only_trip_validates_and_replicates',Trip.valid(t,state.home)
        and not t.participants.owner and received[2].shop_state.state.home.commute.independent)
    local x3=p3.x;contexts[2].inputX=1;pump(5);contexts[2].inputX=0
    check('independent_indoor_remote_moves_during_outing',p3.x>x3)
    entrance(p3);assert(guests[2]:requestInteraction('homeTravel','explore'));pump()
    check('independent_second_departure_joins_same_town',t==state.home.commute and t.token==token
        and t.participants[guests[2].residentId] and p4.sceneId=='front_left')
    local home=state.home.apartmentId
    local function park(part,dest)
        local a=assert(Trip.parking(world,dest,part.slot));local door=world.sites.byId[dest].door
        local r=part.rider;r.bike.x,r.bike.z,r.bike.speed=a.x,a.z,0
        r.ped.x,r.ped.z,r.ped.speed=door.x,door.z,0
        r.gear.mounted=false;r.gear.engine=false;r.gear.transition=nil
    end
    park(part,home);C.syncPlayer(p2,part)
    assert(guests[1]:requestInteraction('commute','arrive:'..token));pump()
    check('independent_guest_enters_home_without_waiting',p2.sceneId=='home' and p3.sceneId=='commute'
        and hp.sceneId=='warehouse' and t.participants[guests[1].residentId]==nil)
    check('independent_apartment_remains_usable',require('src.weekend_flow').atHome(state)
        and state.home.residents[guests[1].residentId].bikeParkedAtHome)
    check('independent_apartment_activity_works_while_another_travels',Residents.command(state,p2,'rest:floor'))
    check('independent_sleep_cannot_accelerate_away_players',not require('src.home_sleep').status(state,players()))
    assert(Residents.command(state,p2,'cancel'))
    local durable=assert(Schema.snapshot(state))
    check('independent_mixed_scenes_save_roundtrip',require('src.home').valid(durable.home)
        and durable.home.residents[guests[1].residentId].sceneId=='home'
        and Trip.restore(durable.home.commute,world)~=nil)
    -- An invalid door request and another rider's force request cannot teleport anyone.
    assert(guests[2]:requestInteraction('commute','force:'..token));pump()
    check('independent_force_cannot_pull_other_players',not received[2].interaction_result.accepted
        and p2.sceneId=='home' and hp.sceneId=='warehouse' and p4.sceneId=='front_left')
    local shopper=t.participants[guests[2].residentId]
    local store=world.sites.byId.grocery
    shopper.rider.ped.x,shopper.rider.ped.z,shopper.rider.ped.speed=store.door.x,store.door.z,0
    shopper.rider.bike.x,shopper.rider.bike.z,shopper.rider.bike.speed=store.parking.x,store.parking.z,0
    C.syncPlayer(p3,shopper)
    assert(guests[2]:requestInteraction('commute','grocery:'..token));pump()
    check('independent_four_distinct_locations_replicate',p3.sceneId=='grocery' and locals[2].sceneId=='grocery'
        and p2.sceneId=='home' and hp.sceneId=='warehouse' and p4.sceneId=='front_left')
    local groceryX=p3.x;contexts[2].inputX=1;pump(5);contexts[2].inputX=0;pump()
    check('independent_grocery_movement_is_host_authoritative',p3.x>groceryX and p3.x==shopper.interiorPose.x
        and math.abs(locals[2].x-p3.x)<1 and shopper.rider.ped.x==store.door.x)
    check('independent_grocery_save_valid',require('src.home').valid(assert(Schema.snapshot(state)).home))
    local insideId=guests[1].residentId
    guests[1]:stop();pump();join(1)
    check('independent_reconnect_restores_personal_interior',guests[1].residentId==insideId
        and host.players[2].sceneId=='home' and locals[1].sceneId=='home' and hp.sceneId=='warehouse')
    local before=state.home.revision
    local outsideId=guests[2].residentId
    guests[2]:stop();pump();join(2)
    check('independent_reconnect_restores_store_participant',guests[2].residentId==outsideId
        and host.players[3].sceneId=='grocery' and state.home.revision>=before)
    assert(guests[2]:requestInteraction('commute','exitgrocery:'..token));pump()
    check('independent_store_exit_does_not_move_other_players',host.players[3].sceneId=='commute'
        and host.players[2].sceneId=='home' and hp.sceneId=='warehouse')
    -- The delivery driver is a guest; the host never leaves its shop menu.
    local Jobs=require('src.jobs');local Service=require('src.job_service')
    local job=assert(Jobs.createOffer({id='INDEPENDENT-DELIVERY',company='Town Grocery',
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500}}))
    Jobs.accept(job);job.status,job.delivery='in_production',{status='received'}
    state.jobs.active[#state.jobs.active+1]=job
    for _,pallet in ipairs(job.pallets) do
        pallet.location,pallet.status,pallet.wrapped,pallet.remainingSheets='warehouse','wrapped',true,0
        pallet.world={x=400,y=500,sceneId='warehouse',direction='northwest',spawnProgress=1}
    end
    assert(Service.requestPickup(state,job,100,'player'))
    p4.sceneId='warehouse';entrance(p4)
    assert(guests[3]:requestInteraction('homeTravel','delivery:'..job.id));pump()
    local driver=t.participants[guests[3].residentId]
    check('independent_guest_plans_delivery_without_group_travel',driver and t.deliveryDriver==guests[3].residentId
        and hp.sceneId=='warehouse' and host.players[2].sceneId=='home' and host.players[3].sceneId=='commute')
    local bay=world.sites.byId.warehouse
    local parking=bay.design.truckParking
    t.truck.x,t.truck.z=bay:toWorld(parking.x,parking.z,0)
    t.truck.speed=0;t.truck.heading=bay.yaw
    check('independent_delivery_truck_reaches_loading_bay',Trip.truckAtLoadingBay(world,t.truck))
    driver.rider.ped.x,driver.rider.ped.z=t.truck.x,t.truck.z
    C.syncPlayer(p4,driver)
    assert(guests[3]:requestInteraction('commute','load_delivery:'..token));pump()
    check('independent_driver_cannot_bulk_load_from_outside',not received[3].interaction_result.accepted
        and t.deliveryRun.status=='loading')
    local warehouse=context.world or require('src.world')
    warehouse.load();warehouse._state=state;warehouse._employeeOptions={}
    assert(require('src.player_delivery_loading').sync(state,warehouse.truck,warehouse.bayDoor))
    for _=1,10 do warehouse.updateSimulation(.1,context.assets,state,.1) end
    assert(warehouse.toggleTruckCargoDoor(state))
    for _=1,10 do warehouse.updateSimulation(.1,context.assets,state,.1) end
    assert(warehouse.loadPickupPallet(state,job.pallets[1].id))
    for _=1,30 do warehouse.updateSimulation(.1,context.assets,state,.1) end
    check('independent_indoor_loader_loads_shared_manifest',hp.sceneId=='warehouse'
        and t.deliveryRun.status=='driving' and job.pickup.status=='player_delivery',
        ('accepted=%s run=%s pickup=%s mode=%s'):format(
            tostring(received[3].interaction_result.accepted),
            tostring(t.deliveryRun and t.deliveryRun.status),tostring(job.pickup.status),
            tostring(job.pickup.driverMode)))
    assert(guests[3]:requestInteraction('commute','truck:'..token));pump()
    local truckX,truckZ=t.truck.x,t.truck.z
    contexts[3].inputY=-1;pump(6);contexts[3].inputY=0
    check('independent_guest_truck_moves_while_host_is_indoors',driver.rider.vehicle=='truck'
        and math.abs(t.truck.x-truckX)+math.abs(t.truck.z-truckZ)>.05 and hp.sceneId=='warehouse')
    local bystander=t.participants[guests[2].residentId]
    bystander.rider.ped.x,bystander.rider.ped.z=t.keiTruck.x,t.keiTruck.z
    C.syncPlayer(p3,bystander)
    assert(guests[2]:requestInteraction('commute','truck:'..token));pump()
    check('independent_box_and_kei_trucks_have_distinct_drivers',received[2].interaction_result.accepted
        and t.truck.driver==guests[3].residentId and t.keiTruck.driver==guests[2].residentId
        and bystander.rider.truck==t.keiTruck and bystander.rider.truck.model=='kei')
    -- Exercise delivery authority at a stop, then the actual warehouse entrance.
    t.truck.speed=0;t.truck.x,t.truck.z=store.parking.x,store.parking.z
    assert(guests[3]:requestInteraction('commute','truck:'..token));pump()
    driver.rider.ped.x,driver.rider.ped.z,driver.rider.ped.speed=store.door.x,store.door.z,0
    assert(guests[3]:requestInteraction('commute','deliver_stop:'..token));pump()
    check('independent_delivery_completes_in_shared_shop',received[3].interaction_result.accepted
        and not t.deliveryRun and #state.jobs.completed==1 and driver.destination==state.home.apartmentId)
    t.truck.x,t.truck.z,t.truck.speed=t.truck.homeX,t.truck.homeZ,0
    local warehouseDoor=world.sites.byId.warehouse.door
    driver.rider.ped.x,driver.rider.ped.z,driver.rider.ped.speed=warehouseDoor.x,warehouseDoor.z,0
    assert(guests[3]:requestInteraction('commute','cancel:'..token));pump()
    check('independent_delivery_return_preserves_other_locations',p4.sceneId=='warehouse' and not t.deliveryRun
        and t.participants[outsideId] and host.players[2].sceneId=='home' and hp.sceneId=='warehouse')
    check('independent_shared_calendar_advances',require('src.weekend_flow').limitCalendarStep(state,.1)==.1)
    local oldJourney=t.participants[outsideId]
    guests[2]:stop();pump();join(2,4)
    local newcomer=host.players[3]
    check('independent_reused_slot_does_not_adopt_offline_journey',newcomer.homeResidentId~=outsideId
        and newcomer.sceneId=='warehouse' and t.participants[outsideId]==oldJourney)
    entrance(newcomer);assert(guests[2]:requestInteraction('homeTravel','explore'));pump()
    check('independent_new_resident_can_travel_in_reused_slot',newcomer.sceneId=='commute'
        and t.participants[newcomer.homeResidentId]~=oldJourney and Trip.valid(t,state.home))
    guests[3]:stop();pump();join(3,2)
    check('independent_outdoor_resident_reconnects_in_different_slot',guests[3].residentId==outsideId
        and host.players[4].sceneId=='commute' and t.participants[outsideId].slot==4
        and newcomer.sceneId=='commute' and Trip.valid(t,state.home))
    local startLog=#network.log;local samples={}
    for i=1,100 do local start=love.timer.getTime();pump(1);samples[i]=(love.timer.getTime()-start)*1000 end
    table.sort(samples)
    local bytes,packets=0,0
    for i=startLog+1,#network.log do local entry=network.log[i]
        if entry.direction=='host_to_client' then bytes=bytes+(entry.bytes or 0);packets=packets+1 end
    end
    print(('INDEPENDENT_SCENES 10s host-to-three-guests bytes=%d packets=%d harness_step_ms median=%.3f p95=%.3f max=%.3f')
        :format(bytes,packets,samples[50],samples[95],samples[100]))
    check('independent_indoor_host_never_allocates_outdoor_renderer',not R._commute.renderer and not R._commute.camera)
    for _,g in pairs(guests) do g:stop() end
    host:stop();C.release(R);warehouse.load()
end
return Test
