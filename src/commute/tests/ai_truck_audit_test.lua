local State=require('src.state')
local Town=require('src.commute.town')
local Traffic=require('src.commute.delivery_traffic')
local Truck=require('src.commute.delivery_truck')
local Motion=require('src.commute.company_truck_motion')
local Service=require('src.commute.truck_service')
local Roadside=require('src.commute.truck_roadside')
local Codec=require('src.net.codec')
local Test={}
local function clone(value)
    local limits={maxBytes=2000000,maxEntries=100000,maxDepth=64}
    return assert(Codec.decode(assert(Codec.encode(value,limits)),limits))
end
local function clean(world)
    world.vehicleObstacles=nil;world.sweepTrafficObstacles=nil
    world.trafficActorIndex=nil;world.trafficActors=nil
end
local function receiving(check)
    local Calendar=require('src.business_calendar')
    local Procurement=require('src.procurement')
    local Jobs=require('src.jobs')
    local state=State.new();state.money=100000
    state.calendar.elapsed=9.5/24*Calendar.secondsPerDay(state)
    assert(Procurement.buy(state,1,1,'computer'))
    state.procurement.shipments[2]=clone(state.procurement.shipments[1])
    state.procurement.shipments[2].id='SECOND-SUPPLY'
    local enroute,arrived=state.procurement.shipments[1],state.procurement.shipments[2]
    for _,order in ipairs({enroute,arrived}) do
        order.delivery.expectedAtHours=0;order.delivery.route={vehicle={phase='approaching'}}
    end
    local job=assert(Jobs.createOffer({id='CLIENT-AT-DOCK',company='Client',sourceSize={width=20,height=16},
        finishedSize={width=10,height=8},sheetCounts={500}}))
    assert(Jobs.accept(job));job.delivery={status='pending_arrival',readyAtHours=0,route={vehicle={phase='at_bay'}}}
    state.jobs.active={job}
    local truck={state='absent',schedule=function(self,id) self.selected=id;self.state='scheduled';return true end}
    local R={World={truck=truck},JobService=require('src.job_service'),BusinessCalendar=Calendar,
        MachineFleet=require('src.machine_fleet'),Procurement=Procurement,PalletLogistics=require('src.pallet_logistics')}
    require('src.world.simulation').install(R)
    check('receiving_overdue_enroute_supply_does_not_block_client_at_dock',R.scheduleTruck(state) and truck.selected==job.id)
    job.delivery.route.vehicle.phase='approaching';arrived.delivery.route.vehicle.phase='at_bay';truck.state='absent'
    check('receiving_selects_later_physically_arrived_supply',R.scheduleTruck(state) and truck.selected==arrived.id)
    check('procurement_default_selection_remains_compatible',Procurement.nextInbound(state)==enroute)
end
local function expiredReturn(check,seed,grouped)
    local town=assert(Town.generate(seed));local world=Town.world(town);local site=world.sites.byId.warehouse
    local state=State.new();state.home.town=town;state.calendar.secondsPerDay=300
    local body=Truck.new(site.truckParking.x,site.truckParking.z,site.yaw)
    body.phase='at_bay';body.pathTarget='dock';body.pathIndex=2
    local delivery={status='received',route={roadTownId=town.id,departedAtEpoch=1000,arrivedAtEpoch=1200,vehicle=body}}
    state.jobs.completed={{id='DONE-1',company='Freight',status='completed',delivery=delivery}}
    if grouped then
        state.jobs.completed[2]={id='DONE-2',company='Freight',status='completed',delivery={status='received',
            route={roadTownId=town.id,departedAtEpoch=1000,arrivedAtEpoch=1200,transportId='DONE-1',vehicle=body}}}
    end
    Traffic.update(state,town,105,1300,world)
    local resume=assert(delivery.returnRoute.arrivedAtEpoch)+86400
    state.jobs.completed=clone(state.jobs.completed)
    delivery=state.jobs.completed[1].delivery
    state.jobs.active={{id='NEXT-1',company='Next pickup',status='pickup_in_progress',
        pickup={status='loading',dispatchAtHours=105}}}
    Traffic.update(state,town,105,resume,world)
    local suffix=seed..(grouped and '_grouped' or '_single')
    -- A player occupying the departure must keep the original dock lease.
    world.vehicleObstacles=function()return true end
    require('src.commute.warehouse_yard').recover(delivery.route.vehicle,nil,world,state)
    check('expired_return_does_not_release_dock_without_departure_'..suffix,delivery.route.vehicle.phase=='at_bay')
    clean(world)
    for step=1,6500 do
        Traffic.simulate(state,town,.1,resume+step*.1,world)
        if step==20 then
            state.jobs.completed=clone(state.jobs.completed)
            Traffic.update(state,town,105,resume+step*.1,world)
            delivery=state.jobs.completed[1].delivery
        end
        if delivery.returnRoute.vehicle and delivery.returnRoute.vehicle.phase=='offmap'
            and Traffic.pickupArrived(state.jobs.active[1]) then break end
    end
    local nextRoute=state.jobs.active[1].pickup.roadDelivery.route
    check('expired_saved_return_physically_exits_'..suffix,delivery.returnRoute.vehicle
        and delivery.route.vehicle.phase=='offmap' and delivery.returnRoute.vehicle.phase=='offmap')
    check('expired_return_releases_dock_for_next_pickup_'..suffix,nextRoute.vehicle and nextRoute.vehicle.phase=='at_bay')
    check('return_preserves_received_status_and_customer_cargo_'..suffix,delivery.status=='received'
        and state.jobs.active[1].pickup.status=='loading')
    if grouped then
        local follower=state.jobs.completed[2].delivery
        check('expired_return_preserves_one_shared_carrier_'..suffix,follower.route.transportId=='DONE-1'
            and follower.route.vehicle==delivery.route.vehicle and follower.status=='received')
    end
    clean(world)
end
local function disabled(check,seed,model,kind)
    local town=assert(Town.generate(seed));local world=Town.world(town)
    local state=State.new();state.home.town=town;state.money=100000
    local motion=Motion.start(assert(require('src.commute.trip').truckParking(world,{fuelLiters=60},model)),world)
    local v=motion.vehicle;v.service=Service.new()
    if kind=='fuel' then v.fuel=0;v.engine=false
    elseif kind=='failure' then
        v.service.mechanicalFailure=true;v.service.failureType='oil_pressure';v.service.oilMiles=2000;v.engine=false
    else v.engine=false end
    local company=require('src.company_delivery_driver').ensure(state)
    company.vehicleModel=model;company.exterior=motion
    company.deliveryRun={status='driving',manifest={jobId='DO-NOT-COMPLETE'}}
    local manifest=assert(Codec.encode(company.deliveryRun));local initialFuel=v.fuel
    local suffix=seed..'_'..model..'_'..kind
    local x,z=v.x,v.z
    for _=1,150 do Motion.update(motion,world,.1,state) end
    check('disabled_company_truck_never_teleports_'..suffix,v.x==x and v.z==z and motion.phase=='reverse_out')
    check('disabled_truck_does_not_complete_or_consume_cargo_'..suffix,Codec.encode(company.deliveryRun)==manifest and v.fuel==initialFuel)
    local moved=Motion.recover(motion,world,state)
    check('disabled_truck_rejects_geometric_recovery_'..suffix,not moved and v.x==x and v.z==z)
    motion=clone(motion);company.exterior=motion;v=motion.vehicle
    for _=1,100 do Motion.update(motion,world,.1,state) end
    check('disabled_saved_truck_stays_in_place_'..suffix,Motion.valid(motion) and v.x==x and v.z==z)
    local quote=Roadside.quote(v,true);local before=state.money
    if quote.priceCents>0 then
        state.money=0
        check('unaffordable_roadside_service_changes_nothing_'..suffix,not Roadside.service(state,v,company)
            and v.engine==false and v.fuel==initialFuel and v.x==x and v.z==z)
        state.money=before
    end
    local serviced=Traffic.debugUnstick(state,'company-yard:'..model)
    check('explicit_service_repairs_and_refuels_in_place_'..suffix,serviced and v.x==x and v.z==z
        and v.engine and v.fuel>0 and not v.service.mechanicalFailure
        and math.abs(state.money-(before-quote.priceCents/100))<.00001 and Codec.encode(company.deliveryRun)==manifest)
    for _=1,200 do Motion.update(motion,world,.1,state) end
    check('serviced_truck_resumes_same_run_'..suffix,(v.x-x)^2+(v.z-z)^2>.1
        and Codec.encode(company.deliveryRun)==manifest and Service.valid(v.service))
    clean(world)
end
local function disabledYard(check)
    local town=assert(Town.generate(712345));local world=Town.world(town);local site=world.sites.byId.warehouse
    local Yard=require('src.commute.warehouse_yard')
    for _,stage in ipairs({'reverse','setup_stop','exit','exit_stop'}) do
        local outbound=stage=='exit' or stage=='exit_stop'
        local x,z=site:toWorld(20,0,0);local v=Truck.new(x,z,site.yaw)
        v.phase='approaching';v.engine=false;v.fuel=0
        v.yard={version=1,target=outbound and 'outbound' or 'dock',stage=stage,wait=0,pause=0,recoveries=0}
        local state=State.new();local assignment={target='dock',anchor=site.design.truckParking,permitted=true}
        for _=1,150 do Yard.update(v,assignment,world,.1,state,outbound and 'outbound' or 'inbound') end
        check('disabled_yard_truck_does_not_advance_'..stage,v.x==x and v.z==z
            and v.phase~='at_bay' and v.yard.stage~='released' and v.yard.recoveries==0)
        check('disabled_yard_rejects_manual_geometry_recovery_'..stage,not Yard.recover(v,assignment,world,state)
            and not Yard.unstick(v,assignment,world,state,outbound and 'outbound' or 'inbound'))
    end
    clean(world)
end
local function disabledCarrierReturn(check)
    local town=assert(Town.generate(712345));local world=Town.world(town);local site=world.sites.byId.warehouse
    local state=State.new();state.home.town=town
    local v=Truck.new(site.truckParking.x,site.truckParking.z,site.yaw)
    v.phase='at_bay';v.engine=false;v.fuel=0;v.service=Service.new()
    v.service.mechanicalFailure=true;v.service.failureType='oil_pressure'
    local delivery={status='received',route={roadTownId=town.id,departedAtEpoch=1000,arrivedAtEpoch=1200,vehicle=v}}
    state.jobs.completed={{id='FAILED-CARRIER',company='Carrier',status='completed',delivery=delivery}}
    Traffic.update(state,town,105,1300,world)
    for i=1,120 do Traffic.simulate(state,town,.1,1300+i*.1,world) end
    local outbound=delivery.returnRoute.vehicle
    check('empty_return_preserves_carrier_fuel_and_failure',outbound and outbound.fuel==0 and outbound.engine==false
        and outbound.service.mechanicalFailure and outbound.x==v.x and outbound.z==v.z and outbound.phase~='offmap')
    local paid=state.money
    local serviced=Traffic.debugUnstick(state,'delivery-yard:FAILED-CARRIER:return')
    check('external_carrier_can_service_its_own_truck_in_place',serviced and state.money==paid
        and outbound.x==v.x and outbound.z==v.z and outbound.fuel>0 and not outbound.service.mechanicalFailure)
    for i=1,600 do Traffic.simulate(state,town,.1,1312+i*.1,world) end
    check('serviced_carrier_releases_dock_without_changing_receipt',delivery.status=='received'
        and (outbound.x-v.x)^2+(outbound.z-v.z)^2>25)
    clean(world)
end
function Test.run(check)
    receiving(check)
    disabledYard(check)
    disabledCarrierReturn(check)
    local Departure=require('src.commute.delivery_departure')
    check('expired_legacy_return_without_physical_dock_owner_stays_finished',not Departure.pending({
        returnRoute={departedAtEpoch=10,arrivedAtEpoch=20}},100))
    for _,seed in ipairs({712345,712346,43127}) do
        expiredReturn(check,seed,false);expiredReturn(check,seed,true)
        for _,model in ipairs({'box','kei'}) do
            for _,kind in ipairs({'fuel','failure','ignition'}) do disabled(check,seed,model,kind) end
        end
    end
end
return Test
