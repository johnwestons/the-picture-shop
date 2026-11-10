local Network=require('src.commute.delivery_traffic')
local Town=require('src.commute.town')
local Truck=require('src.commute.delivery_truck')
local Path=require('src.commute.driving_path')
local Footprint=require('src.commute.truck_footprint')
local Watchdog=require('src.ai_watchdog')
local Recovery=require('src.commute.truck_traffic_recovery')
local Service=require('src.job_service')
local Test={}

local function straight(world)
    for _,road in ipairs(world.roads.paths) do
        if road.lanes==2 and not road.oneWay and road.role~='drive'
            and road.surface~='dirt' and road.width>=6 then
            for station=30,road.length-30,5 do
                local a=Path.sample(road.points,road.length,(station-25)/road.length)
                local b=Path.sample(road.points,road.length,(station+25)/road.length)
                if math.abs(math.atan2(math.sin(a.heading-b.heading),math.cos(a.heading-b.heading)))<.03 then
                    local points={}
                    local aligned=true
                    for offset=-25,25,2.5 do
                        local point=Path.sample(road.points,road.length,(station+offset)/road.length)
                        aligned=aligned and math.abs(math.atan2(math.sin(a.heading-point.heading),
                            math.cos(a.heading-point.heading)))<.03
                        points[#points+1]=point
                    end
                    if aligned then return points end
                end
            end
        end
    end
end

local function pair(world,points)
    local length=Path.length(points)
    local a,b=Path.sample(points,length,.42),Path.sample(points,length,.58)
    local first,second=Truck.new(a.x,a.z,a.heading),Truck.new(b.x,b.z,b.heading+math.pi)
    first.trafficId='head-on-A';second.trafficId='head-on-B'
    first.h,second.h=world:supportHeight(first.x,first.z),world:supportHeight(second.x,second.z)
    local reverse={}
    for i=#points,1,-1 do reverse[#reverse+1]={x=points[i].x,z=points[i].z,h=points[i].h} end
    first.pathIndex=a.pathIndex;second.pathIndex=Path.indexAtDistance(reverse,length*.42)
    world.trafficActors={{actor=first,id=first.trafficId,kind='vehicle'},
        {actor=second,id=second.trafficId,kind='vehicle'}}
    world.vehicleObstacles=function(x,z,heading,subject)
        for _,entry in ipairs(world.trafficActors) do
            local other=entry.actor
            if other~=subject and Footprint.overlapsTruck(x,z,heading,other.x,other.z,other.heading) then return true end
        end
        return false
    end
    return first,second,reverse
end

local function dispatchCases(check,town,world,epoch)
    local state={calendar={secondsPerDay=300},jobs={active={},completed={}}}
    for i=1,4 do
        state.jobs.active[i]={id='PICKUP-'..i,status='ready_for_pickup',pickup={status='awaiting_schedule',dispatchAtHours=105}}
    end
    Network.update(state,town,105,epoch,world)
    local dispatched=0
    for _,job in ipairs(state.jobs.active) do
        if job.pickup.roadDelivery.route.departedAtEpoch then dispatched=dispatched+1 end
    end
    local first=state.jobs.active[1]
    local fourth=state.jobs.active[4].pickup.roadDelivery
    check('customer_pickups_start_with_one_spaced_departure',dispatched==1
        and fourth.route.departedAtEpoch==nil)
    for i=1,3 do Network.update(state,town,106,epoch+i*Network.DISPATCH_HEADWAY_SECONDS,world) end
    check('customer_pickups_can_have_more_than_three_trucks_en_route',
        fourth.route.departedAtEpoch==epoch+3*Network.DISPATCH_HEADWAY_SECONDS
        and first.pickup.status=='awaiting_schedule')

    local freight={id='FREIGHT',delivery={status='pending_arrival',readyAtHours=0},
        pallets={{id='CARGO',location='awaiting_delivery'}}}
    state={calendar={secondsPerDay=300},jobs={active={freight,{id='PICKUP',status='ready_for_pickup',
        pickup={status='awaiting_schedule',dispatchAtHours=105}}},completed={}}}
    Network.update(state,town,105,epoch,world)
    Network.update(state,town,105,epoch+Network.DISPATCH_HEADWAY_SECONDS,world)
    local pickup=state.jobs.active[2].pickup.roadDelivery
    check('customer_pickup_does_not_merge_into_an_inbound_freight_truck',
        pickup.route.departedAtEpoch==epoch+Network.DISPATCH_HEADWAY_SECONDS and pickup.route.transportId==nil
        and freight.delivery.route.transportId==nil)

    local legacy={id='LEGACY',status='pickup_in_progress',pickup={status='loading'}}
    state={calendar={secondsPerDay=300},jobs={active={legacy},completed={}}}
    Network.update(state,town,105,epoch,world)
    Network.simulate(state,town,.1,epoch,world)
    check('legacy_pickup_already_loading_restores_exterior_at_the_bay',Network.pickupArrived(legacy)
        and legacy.pickup.status=='loading')
end

function Test.run(check,town)
    town=town or assert(Town.generate(712345))
    local world=Town.world(town)
    local epoch=1700000000
    dispatchCases(check,town,world,epoch)
    local state=require('src.state').new()
    state.money=321;state.calendar.secondsPerDay=300
    local Jobs=require('src.jobs')
    local job=assert(Jobs.createOffer({id='CUSTOMER-PICKUP',company='Juniper Trail Outfitters',
        sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500}}))
    Jobs.accept(job);job.status='in_production';job.delivery={status='received'}
    job.outboundDelivery={transport='customer'}
    local pallet=job.pallets[1]
    pallet.location,pallet.status,pallet.wrapped,pallet.remainingSheets='warehouse','wrapped',true,0
    local employee={id='EMPLOYEE-DELIVERY',status='ready_for_pickup',pickup={status='awaiting_schedule',driverMode='employee'}}
    state.jobs={active={job,employee},completed={}}
    assert(Service.requestPickup(state,job,epoch))
    Network.update(state,town,105,epoch,world)
    local road=job.pickup.roadDelivery
    check('customer_pickup_dispatches_its_own_empty_road_truck',road and road.customerPickup
        and road.route.departedAtEpoch==epoch and road.route.transportId==nil and employee.pickup.roadDelivery==nil)
    check('customer_pickup_waits_for_physical_road_arrival',not Network.pickupArrived(job)
        and Service.nextPickup(state,Network.pickupArrived)==nil)
    Network.simulate(state,town,.1,epoch,world)
    local visible=false
    for _,entry in ipairs(Network.actors(state,town,105,epoch,world)) do
        visible=visible or entry.id=='CUSTOMER-PICKUP:pickup' and entry.phase=='approaching'
            and entry.actor.company==job.company
    end
    check('customer_pickup_is_visible_on_commute_terrain',visible)
    local arrived=false
    for step=1,6500 do
        Network.simulate(state,town,.1,epoch+step*.1,world)
        if Network.pickupArrived(job) then arrived=true;break end
    end
    check('customer_pickup_drives_from_gate_to_loading_bay',arrived,
        road and road.route.vehicle and ('phase='..road.route.vehicle.phase..' index='..tostring(road.route.vehicle.pathIndex)))
    check('customer_pickup_road_arrival_preserves_cargo_and_payment',state.money==321
        and job.pallets[1].location=='warehouse' and job.delivery.status=='received' and job.pickup.status=='awaiting_schedule')
    local validation={}
    require('src.save_schema.primitives').install(validation)
    require('src.save_schema.paper').install(validation)
    local Codec=require('src.net.codec')
    local restored=assert(Codec.decode(assert(Codec.encode(job.pickup))))
    check('customer_pickup_route_survives_save_and_network_roundtrip',validation.pickup(restored)
        and restored.roadDelivery.route.vehicle.phase==road.route.vehicle.phase)
    restored.roadDelivery.route.vehicle.x=0/0
    check('customer_pickup_rejects_invalid_saved_vehicle',not validation.pickup(restored))
    local waiting={id='WAITING-PICKUP',status='ready_for_pickup',pickup={status='awaiting_schedule',
        roadDelivery={status='pending_arrival',route={departedAtEpoch=epoch}}}}
    table.insert(state.jobs.active,1,waiting)
    check('customer_pickup_at_dock_is_not_blocked_by_an_earlier_pending_job',
        Service.nextPickup(state,Network.pickupArrived)==job)
    table.remove(state.jobs.active,1)
    assert(Service.schedulePickup(job,epoch+650))
    check('customer_pickup_cannot_complete_before_pallets_are_loaded',not Service.completePickup(state,job.id,epoch+650))
    assert(Service.loadForPickup(state,job.id,pallet.id,epoch+660))
    local paid=Service.completePickup(state,job.id,epoch+700)
    local money=state.money
    check('customer_pickup_loads_archives_and_pays_exactly_once',paid and state.jobs.completed[1]==job
        and job.status=='completed' and pallet.location=='none' and money==321+job.quote.totalPrice
        and not Service.completePickup(state,job.id,epoch+701) and state.money==money)
    Network.update(state,town,102,epoch+700,world)
    Network.simulate(state,town,.1,epoch+700,world)
    local departing=false
    for _,entry in ipairs(Network.actors(state,town,102,epoch+700,world)) do
        departing=departing or entry.id=='CUSTOMER-PICKUP:pickup' and entry.phase=='departing'
    end
    check('completed_customer_pickup_keeps_visible_return_trip',departing and road.returnRoute~=nil)
    local departed=false
    for step=1,6500 do
        Network.simulate(state,town,.1,epoch+700+step*.1,world)
        if road.returnRoute.vehicle.phase=='offmap' then departed=true;break end
    end
    check('customer_pickup_return_reaches_town_exit',departed)

    world=Town.world(town);world.infrastructure.fixtures={}
    local points=assert(straight(world),'straight road fixture required')
    local first,second,reverse=pair(world,points)
    local trafficState={};local doneA,doneB,backed=false,false,false
    local collision=false
    for _=1,2400 do
        if not doneA then doneA=Network.driveRoute(first,points,.05,world,'head-on-forward',trafficState) end
        if not doneB then doneB=Network.driveRoute(second,reverse,.05,world,'head-on-return',trafficState) end
        backed=backed or first.reverse or second.reverse
        collision=collision or Footprint.overlapsTruck(first.x,first.z,first.heading,second.x,second.z,second.heading)
        if doneA and doneB then break end
    end
    check('head_on_trucks_back_up_and_both_complete_routes',doneA and doneB and backed and not collision,
        ('finished=%s/%s backed=%s collision=%s A=%.2f,%.2f h%.2f speed%.3f idx%d end=%.2f,%.2f events=%s'):format(
            tostring(doneA),tostring(doneB),tostring(backed),tostring(collision),first.x,first.z,first.heading,
            first.speed,first.pathIndex,points[#points].x,points[#points].z,
            tostring(Watchdog.snapshot(trafficState).events[#Watchdog.snapshot(trafficState).events]
                and Watchdog.snapshot(trafficState).events[#Watchdog.snapshot(trafficState).events].action)))

    first,second,reverse=pair(world,points)
    local Rules=require('src.commute.traffic_rules')
    local originalUpdate,originalLimit=Truck.update,Rules.limitForTraffic
    local blockedState={};local oldX,oldZ=first.x,first.z
    Truck.update=function()return 0 end
    Rules.limitForTraffic=function()return 0,true end
    local blockedPoints,replanned=points,false
    local okay,err=pcall(function()
        for _=1,550 do
            Network.driveRoute(first,blockedPoints,.1,world,'blocked-road',blockedState)
            if first.replanRoute and not replanned then
                -- Inbound deliveries replan from their current position after
                -- reversing. That must not discard the road behind the jam.
                blockedPoints={{x=first.x,z=first.z,h=first.h},points[#points]}
                first.pathIndex=2;first.replanRoute=nil;replanned=true
            end
        end
    end)
    Truck.update,Rules.limitForTraffic=originalUpdate,originalLimit
    local rescueEvent=false
    for _,event in ipairs(Watchdog.snapshot(blockedState).events) do
        rescueEvent=rescueEvent or event.attempt and event.attempt>=3 and event.action:find('Rescue moved',1,true)~=nil
    end
    check('stationary_traffic_wait_survives_replans_and_escalates_to_safe_rescue',okay and replanned and rescueEvent
        and (first.x-oldX)^2+(first.z-oldZ)^2>4 and not Truck.blocked(world,first.x,first.z,first.heading,first),tostring(err))
    local px,pz=first.x,first.z
    local obstacles=world.vehicleObstacles
    world.vehicleObstacles=function()return true end
    local rescued=Recovery.rescue(first,points,world)
    world.vehicleObstacles=obstacles
    check('traffic_rescue_refuses_occupied_positions',not rescued and first.x==px and first.z==pz)
    world.trafficActors={world.trafficActors[1]}
    local resumed=false
    for _=1,1600 do if Network.driveRoute(first,points,.05,world,'blocked-road',blockedState) then resumed=true;break end end
    check('rescued_truck_resumes_and_finishes_original_route',resumed and #Watchdog.snapshot(blockedState).active==0)
end

return Test
