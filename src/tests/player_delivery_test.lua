local Test={}
local function capture(name,draw)
    local directory=os.getenv('PICTURE_SHOP_PLAYER_DELIVERY_CAPTURE')
    if not directory then return end
    local canvas=love.graphics.newCanvas(960,678)
    love.graphics.push('all');love.graphics.setCanvas(canvas);love.graphics.clear(.02,.03,.04,1)
    draw();love.graphics.setCanvas();love.graphics.pop()
    local data=canvas:newImageData();local bytes=data:encode('png')
    local file=assert(io.open(directory..'/'..name..'.png','wb'));file:write(bytes:getString());file:close()
    bytes:release();data:release();canvas:release()
end
function Test.run(context,check)
    local State=require('src.state')
    local Jobs=require('src.jobs')
    local Service=require('src.job_service')
    local Run=require('src.commute.delivery_run')
    local Trip=require('src.commute.trip')
    local Free=require('src.commute.free_travel')
    local Loading=require('src.player_delivery_loading')
    local Schema=require('src.save_schema')
    local C=require('src.commute.runtime')
    local Town=require('src.commute.town')
    local state=State.new()
    state.calendar.elapsed=require('src.business_calendar').secondsPerDay(state)*9/24
    state.home.town=assert(Town.generate(712345))
    state.home.townCharacters=require('src.commute.town_characters').defaultState(state.home.town)
    local world=Town.world(state.home.town)
    local warehouse=context.world or require('src.world')
    warehouse.load();warehouse._state=state;warehouse._employeeOptions={}
    local site=world.sites.byId.warehouse
    local function job(id,company,counts,destination)
        local value=assert(Jobs.createOffer({id=id,company=company,customerDestination=destination,
            sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts=counts}))
        Jobs.accept(value);value.status='in_production';value.delivery={status='received'}
        state.jobs.active[#state.jobs.active+1]=value
        for _,p in ipairs(value.pallets) do
            p.location,p.status,p.wrapped,p.remainingSheets='warehouse','wrapped',true,0
            p.finishedSheets=p.initialSheets;p.completedLifts=p.requiredLifts
            p.world={x=400,y=500,sceneId='warehouse',direction='northwest',spawnProgress=1}
            state.inventory.finishedPallets=(state.inventory.finishedPallets or 0)+1
        end
        assert(Service.requestPickup(state,value,100,'player'))
        return value
    end
    local localJob=job('PLAYER-LOCAL','Town Grocery',{500,500},'grocery')
    local cityOne=job('PLAYER-CITY-1','Blue Ridge Packaging',{500})
    local cityTwo=job('PLAYER-CITY-2','Northstar Bindery',{500})
    local secondLocal=job('PLAYER-LOCAL-2','Town Diner',{500},'diner')
    localJob.outboundDelivery={transport='customer'}
    check('player_delivery_cannot_claim_customer_arranged_transport',not Run.build(state,{localJob.id},world,'player'))
    localJob.outboundDelivery=nil
    local run=assert(Run.build(state,{cityOne.id,localJob.id,cityTwo.id,secondLocal.id},world,'player'))
    check('player_delivery_local_address_survives_quote_and_orders_before_city',
        localJob.customerDestination=='grocery' and run.stops[1].kind=='town'
        and run.stops[2].id=='diner' and run.stops[3].kind=='city' and run.palletCount==5)
    local player={id=1,homeResidentId='owner',sceneId='warehouse',character='rabbit-worker'}
    local entered,t=Free.enter(state,player,world,run,{player});assert(entered,t)
    local beforeUnloaded=state.money
    check('player_delivery_incomplete_pallet_manifest_cannot_complete_or_pay',
        not Run.completeStop(state,run.stops[1]) and state.money==beforeUnloaded and #state.jobs.completed==0)
    player.sceneId='commute'
    local truck=t.truck
    local function align()
        truck.x,truck.z,truck.h=site.truckParking.x,site.truckParking.z,site.truckParking.h
        truck.heading=site.yaw;truck.speed=0
    end
    align();truck.heading=site.yaw+math.pi
    check('player_delivery_rejects_nose_in_loading',not Trip.truckAtLoadingBay(world,truck)
        and not Loading.sync(state,warehouse.truck,warehouse.bayDoor))
    align()
    assert(Loading.sync(state,warehouse.truck,warehouse.bayDoor))
    check('player_delivery_docked_truck_is_same_manifest_inside',warehouse.truck.playerDelivery
        and warehouse.truck.jobId==cityOne.id and warehouse.truck.mode=='pickup')
    local function tick(seconds)
        for _=1,math.ceil(seconds/.1) do warehouse.updateSimulation(.1,context.assets,state,.1) end
    end
    tick(1)
    local function openCargo()
        if warehouse.truck.state=='parked_closed' then assert(warehouse.toggleTruckCargoDoor(state)) end
        tick(1)
    end
    openCargo()
    -- One player uses the normal warehouse manifest. The employee uses a jack.
    assert(warehouse.loadPickupPallet(state,cityOne.pallets[1].id));tick(.1)
    local part=t.participants.owner
    part.rider.ped.x,part.rider.ped.z=truck.x,truck.z
    local outsideLoad=Trip.command(state,player,t.token,'load_delivery',world)
    check('player_delivery_outdoor_action_cannot_bulk_load_pallets',not outsideLoad
        and select(1,Run.loadingProgress(state,run))==1)
    assert(Trip.command(state,player,t.token,'truck',world))
    local x,z=truck.x,truck.z
    for _=1,20 do Trip.update(state,player,{drive=-1,steer=0},.1,world) end
    check('player_delivery_cannot_drive_away_partially_loaded',truck.x==x and truck.z==z and truck.speed==0)
    assert(Trip.command(state,player,t.token,'truck',world))
    part.rider.ped.x,part.rider.ped.z,part.rider.ped.speed=site.door.x,site.door.z,0
    local doorRuntime={state=state,World={player=player},Config=context.Config or require('src.config'),
        _commute={world=world}}
    C.perform(doorRuntime,'worldAction')
    check('player_delivery_world_action_enters_warehouse_instead_of_overriding_with_loading',
        doorRuntime._commute.doorTransition and doorRuntime._commute.doorTransition.action=='arrive')
    assert(Free.leave(state,player,t.token,'warehouse',world));player.sceneId='warehouse'
    check('player_delivery_can_enter_warehouse_without_losing_manifest',t.deliveryRun==run
        and t.deliveryDriver=='owner' and not t.participants.owner and Trip.valid(Trip.snapshot(t),state.home))
    local jack=state.palletJack
    local target=warehouse.truck:getInteraction()
    local pallet=localJob.pallets[1]
    jack.x,jack.y,jack.sceneId=target.x,target.y,'warehouse'
    jack.operating=true;jack.operatorEmployeeId='DELIVERY-LOADER';jack.operatorPlayerId=nil
    jack.carriedPalletId=pallet.id;pallet.location='on_pallet_jack'
    pallet.world.x,pallet.world.y=jack.x,jack.y
    assert(warehouse.loadEmployeePickup(state,{id='DELIVERY-LOADER'},pallet.id));tick(.1)
    check('player_delivery_employee_loading_updates_same_manifest',pallet.location=='outbound_truck'
        and jack.carriedPalletId==nil and select(1,Run.loadingProgress(state,run))==2)
    jack.operatorEmployeeId=nil;jack.operating=false
    -- Continue using a player's pallet jack, then the final manifest row.
    pallet=localJob.pallets[2]
    jack.operating=true;jack.operatorPlayerId=1;jack.carriedPalletId=pallet.id
    pallet.location='on_pallet_jack';pallet.world.x,pallet.world.y=jack.x,jack.y
    local jackRow=require('src.truck_authority').view(state,warehouse,1).items[3]
    capture('loading-manifest',function()
        require('src.screens.truck_inventory_screen').draw(state,warehouse,context.assets,0,0)
    end)
    local manifestScreen=require('src.screens.truck_inventory_screen')
    local clickX,clickY=manifestScreen.unloadButtonCenter(3)
    local clicked=manifestScreen.mousepressed(state,warehouse,clickX,clickY,1)
    check('player_delivery_player_jack_load_is_available_on_desktop_touch_and_remote_manifest',
        jackRow.available and clicked and clicked.action=='loaded' and pallet.location=='outbound_truck')
    tick(.1)
    jack.operating=false;jack.operatorPlayerId=nil
    local saved=assert(Schema.snapshot(state))
    check('player_delivery_partial_loading_saves_while_driver_is_indoors',Schema.validState(saved))
    assert(context.save.save(3,state,warehouse.snapshot()))
    local payload=assert(context.save.load(3));context.save.delete(3)
    state=State.new();assert(State.applySave(state,payload))
    state.home.commute=assert(Trip.restore(state.home.commute,world))
    t=state.home.commute;run=t.deliveryRun;truck=t.truck
    localJob=select(1,Service.pickupInventory(state,localJob.id))
    cityOne=select(1,Service.pickupInventory(state,cityOne.id))
    cityTwo=select(1,Service.pickupInventory(state,cityTwo.id))
    warehouse.load();warehouse._state=state
    assert(Loading.sync(state,warehouse.truck,warehouse.bayDoor));openCargo()
    check('player_delivery_reload_preserves_loaded_cargo_and_resumes_remaining_manifest',
        select(1,Run.loadingProgress(state,run))==3 and warehouse.truck.jobId==cityTwo.id
        and t.deliveryDriver=='owner' and truck.owner=='owner')
    local oldRoads=Trip.snapshot(t)
    oldRoads.mapVersion=require('src.commute.roads').VERSION+1
    local migrated=assert(Trip.restore(oldRoads,world))
    check('player_delivery_road_migration_retains_the_indoor_drivers_truck_reservation',
        Trip.valid(migrated,state.home) and migrated.truck.owner=='owner' and migrated.deliveryDriver=='owner')
    assert(warehouse.loadPickupPallet(state,cityTwo.pallets[1].id))
    assert(warehouse.loadPickupPallet(state,secondLocal.pallets[1].id))
    local money=state.money
    tick(3)
    check('player_delivery_ready_only_after_all_pallets_and_cargo_secured',run.status=='driving'
        and warehouse.truck.state=='parked_closed' and #state.jobs.completed==0 and state.money==money
        and state.message:find('GPS:',1,true)~=nil)
    local okay,resumed=Free.enter(state,player,world,nil,{player});assert(okay,resumed)
    player.sceneId='commute';part=t.participants.owner
    local R={state=state,World={player=player},_commute={world=world}}
    check('player_delivery_resume_keeps_gps_on_local_customer',C.activeWaypoint(R)=='grocery')
    part.rider.ped.x,part.rider.ped.z=truck.x,truck.z
    assert(Trip.command(state,player,t.token,'truck',world))
    local store=world.sites.byId.grocery
    truck.x,truck.z=store.parking.x,store.parking.z;truck.speed=0
    assert(Trip.command(state,player,t.token,'truck',world))
    part.rider.ped.x,part.rider.ped.z,part.rider.ped.speed=store.door.x,store.door.z,0
    local delivered,message=Trip.command(state,player,t.token,'deliver_stop',world)
    check('player_delivery_local_stop_completes_and_updates_gps',delivered and #state.jobs.completed==1
        and C.activeWaypoint(R)=='diner' and message:find('Delivered 2',1,true)~=nil)
    local paid=state.money
    assert(Run.completeStop(state,run.stops[1]))
    check('player_delivery_retry_cannot_pay_for_same_job_twice',state.money==paid)
    part.rider.ped.x,part.rider.ped.z=truck.x,truck.z
    assert(Trip.command(state,player,t.token,'truck',world))
    store=world.sites.byId.diner
    truck.x,truck.z=store.parking.x,store.parking.z;truck.speed=0
    assert(Trip.command(state,player,t.token,'truck',world))
    part.rider.ped.x,part.rider.ped.z,part.rider.ped.speed=store.door.x,store.door.z,0
    check('player_delivery_second_town_stop_advances_navigation_to_city',
        Trip.command(state,player,t.token,'deliver_stop',world) and #state.jobs.completed==2
        and C.activeWaypoint(R)=='mainland_exit')
    part.rider.ped.x,part.rider.ped.z=truck.x,truck.z
    assert(Trip.command(state,player,t.token,'truck',world))
    local gate=world.mainlandExit;local dx,dz=math.cos(gate.heading),math.sin(gate.heading)
    truck.x,truck.z=gate.x-dx*12,gate.z-dz*12;truck.heading=gate.heading;truck.speed=1
    state.calendar.elapsed=require('src.business_calendar').secondsPerDay(state)*20/24
    Trip.update(state,player,{drive=-1,steer=0},.1,world)
    check('player_delivery_closed_city_gate_keeps_player_in_town_with_cargo',run.status=='driving'
        and #state.jobs.completed==2 and truck.speed==0)
    state.calendar.elapsed=require('src.business_calendar').secondsPerDay(state)*9/24
    truck.x,truck.z=gate.x-dx*12,gate.z-dz*12;truck.heading=gate.heading;truck.speed=1
    Trip.update(state,player,{drive=-1,steer=0},.1,world)
    check('player_delivery_bridge_starts_city_montage',run.status=='offmap' and run.cutsceneEndsAtEpoch>os.time())
    capture('city-delivery-montage',function()
        require('src.commute.city_delivery_scene').draw(960,678,run,truck,nil,.9)
    end)
    local bridgeSave=assert(Schema.snapshot(state))
    local bridgeTrip=assert(Trip.restore(bridgeSave.home.commute,world))
    check('player_delivery_bridge_montage_saves_and_restores_with_truck_control',
        Schema.validState(bridgeSave) and Trip.valid(bridgeTrip,state.home)
        and bridgeTrip.participants.owner.rider.truck==bridgeTrip.truck)
    local beforeClosed=state.money
    state.calendar.elapsed=require('src.business_calendar').secondsPerDay(state)*20/24
    run.cutsceneEndsAtEpoch=os.time()-1
    Trip.update(state,player,{},.1,world)
    check('player_delivery_closing_during_trip_returns_undelivered_pallets_without_softlock',run.status=='driving'
        and run.stopIndex==3 and #state.jobs.completed==2 and state.money==beforeClosed)
    state.calendar.elapsed=require('src.business_calendar').secondsPerDay(state)*9/24
    truck.x,truck.z=gate.x-dx*12,gate.z-dz*12;truck.heading=gate.heading;truck.speed=1
    Trip.update(state,player,{drive=-1,steer=0},.1,world)
    local originalObstacles=world.vehicleObstacles
    world.vehicleObstacles=function()return true end
    run.cutsceneEndsAtEpoch=os.time()-1
    Trip.update(state,player,{},.1,world)
    check('player_delivery_city_return_waits_for_a_clear_lane',run.status=='offmap' and #state.jobs.completed==2)
    world.vehicleObstacles=originalObstacles
    run.cutsceneEndsAtEpoch=os.time()-1
    Trip.update(state,player,{},.1,world)
    check('player_delivery_single_city_trip_delivers_remaining_manifest',#state.jobs.completed==4
        and not t.deliveryRun and not t.deliveryDriver and state.message:find('2 pallets delivered',1,true)~=nil)
    check('player_delivery_returns_on_bridge_facing_town',math.cos(truck.heading-gate.heading)<-.99
        and math.sqrt((truck.x-gate.x)^2+(truck.z-gate.z)^2)>=8-.01)
    check('player_delivery_completed_route_releases_gps_and_preserves_truck_control',Trip.valid(Trip.snapshot(t),state.home)
        and part.rider.vehicle=='truck' and truck.driver=='owner' and C.activeWaypoint(R)~='mainland_exit')
    local home=world.sites.byId[state.home.apartmentId]
    truck.x,truck.z,truck.speed=home.parking.x,home.parking.z,0
    assert(Trip.command(state,player,t.token,'truck',world))
    part.rider.ped.x,part.rider.ped.z,part.rider.ped.speed=home.door.x,home.door.z,0
    C.perform(R,'worldAction')
    check('player_delivery_home_entrance_action_is_restored_after_completion',R._commute.doorTransition
        and R._commute.doorTransition.action=='enterhome'
        and R._commute.doorTransition.buildingId==state.home.apartmentId)
    check('player_delivery_can_go_home_without_returning_truck_to_shop',Free.leave(state,player,t.token,state.home.apartmentId,world))

    -- Let the real employee controller collect a skid, drive its pallet jack,
    -- load the player's docked truck, and secure it without a manual load call.
    state=State.new();state.home.town=assert(Town.generate(712345))
    state.home.townCharacters=require('src.commute.town_characters').defaultState(state.home.town)
    local employeeJob=job('PLAYER-EMPLOYEE-LOAD','Town Grocery',{500},'grocery')
    local employeeJobTwo=job('PLAYER-EMPLOYEE-LOAD-2','Northstar Bindery',{500})
    employeeJobTwo.pallets[1].world.x=560
    local Employees=require('src.employees')
    local applicant=assert(Employees.createApplicant(state,0));applicant.shiftPreference='flexible'
    Employees.requestResume(state,applicant.id,0);Employees.advance(state,.5)
    assert(Employees.command(state,{kind='offer_employee',applicationId=applicant.id,expectedRevision=applicant.revision,
        wageCents=math.max(2400,applicant.requestedWage),days=31,startHour=9,endHour=17},.5))
    Employees.advance(state,1.25)
    assert(Employees.command(state,{kind='hire_employee',applicationId=applicant.id,expectedRevision=applicant.revision},1.25))
    local worker=state.employment.staff[1]
    worker.visible,worker.clockedIn,worker.phase,worker.x,worker.y=true,true,'idle',560,550
    worker.shiftDay,worker.breaksTaken=0,3
    local Calendar=require('src.business_calendar')
    state.calendar.elapsed=Calendar.secondsPerDay(state)*9.5/24
    state.employment.lastAtHours=Calendar.absoluteHours(state)
    player.sceneId='warehouse'
    run=assert(Run.build(state,{employeeJob.id,employeeJobTwo.id},world,'player'))
    assert(Free.enter(state,player,world,run,{player}));player.sceneId='commute'
    t=state.home.commute
    local employeePart=t.participants.owner
    employeePart.rider.ped.x,employeePart.rider.ped.z=t.keiTruck.x,t.keiTruck.z
    assert(Trip.command(state,player,t.token,'truck',world))
    truck=t.keiTruck;align()
    -- The shorter truck's rear doors reach the same dock with its cab closer.
    truck.x,truck.z=truck.x-site.cos*.98,truck.z-site.sin*.98
    assert(Trip.command(state,player,t.token,'truck',world))
    check('player_delivery_kei_uses_rear_door_alignment_and_its_own_manifest',
        t.deliveryVehicleModel=='kei' and t.truck.owner==nil and Trip.truckAtLoadingBay(world,truck))
    state.palletJack.x,state.palletJack.y=200,600
    warehouse.load();warehouse.player.x,warehouse.player.y=930,640
    warehouse.configureEmployees({players=function()return {} end,canClaim=function()return false end})
    local droveJack=false
    for _=1,3600 do
        Calendar.update(state,.1);warehouse.updateSimulation(.1,context.assets,state,.1)
        local owned=require('src.pallet_jack_fleet').owned(state,worker.id)
        droveJack=droveJack or owned and owned.carriedPalletId==employeeJob.pallets[1].id
        if run.status=='driving' then break end
    end
    check('player_delivery_employee_ai_collects_and_loads_the_docked_truck',droveJack and run.status=='driving'
        and employeeJob.pallets[1].location=='outbound_truck'
        and employeeJobTwo.pallets[1].location=='outbound_truck' and #state.jobs.completed==0,
        worker.activity..' / '..warehouse.truck.state..' / '..employeeJob.pallets[1].location)
    warehouse.configureEmployees({})
    warehouse.load()
end
return Test
