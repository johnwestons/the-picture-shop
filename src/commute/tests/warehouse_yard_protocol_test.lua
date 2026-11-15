local Town=require('src.commute.town')
local Truck=require('src.commute.delivery_truck')
local Network=require('src.commute.delivery_traffic')
local Yard=require('src.commute.warehouse_yard')
local Rail=require('src.commute.yard_rail')
local Watchdog=require('src.ai_watchdog')
local Footprint=require('src.commute.truck_footprint')
local Codec=require('src.net.codec')
local Test={}
local EPOCH=1700000000
local function fixture(seed,count)
    local town=assert(Town.generate(seed));local world=Town.world(town)
    local site=world.sites.byId.warehouse
    local state={home={town=town},jobs={active={},completed={}}}
    local deliveries={}
    for i=1,count do
        local anchor=site.truckQueueWorldAnchors[i]
        local truck=Truck.new(anchor.x,anchor.z,site.yaw-math.pi/2,'plain')
        truck.h=world:supportHeight(truck.x,truck.z);truck.phase='waiting_bay';truck.pathTarget='waiting-'..i
        local delivery={status='pending_arrival',customerPickup=i==2 or nil,
            route={roadTownId=town.id,departedAtEpoch=EPOCH+i,arrivedAtEpoch=EPOCH+1000,vehicle=truck}}
        deliveries[i]=delivery
        state.jobs.active[i]=i==2 and {id='PICKUP',pickup={roadDelivery=delivery}}
            or {id='FREIGHT-'..i,delivery=delivery}
    end
    return state,town,world,deliveries,site
end
local function tick(state,town,world,time)
    Network.simulate(state,town,.1,time,world)
end
local function clone(value)
    local limits={maxBytes=65536,maxEntries=4096}
    return assert(Codec.decode(assert(Codec.encode(value,limits)),limits))
end
function Test.run(check)
    do
        local _,_,world,_,site=fixture(712345,1)
        local x,z=site:toWorld(20,0,0)
        local tx,tz=site:toWorld(10,0,0)
        local points={{x=x,z=z},{x=tx,z=tz}}
        for _,offset in ipairs({0,.5}) do
            local minimum,maximum,withinLimit=math.huge,0,true
            for _,fps in ipairs({30,60,120,240}) do
                local sx,sz=site:toWorld(20,offset,0)
                local vehicle=Truck.new(sx,sz,site.yaw)
                local rail={station=0}
                for _=1,fps*2 do
                    Rail.step(vehicle,rail,points,1/fps,world,{reverse=true,speed=1.2})
                    withinLimit=withinLimit and vehicle.speed<=1.2+1e-6
                end
                minimum=math.min(minimum,vehicle.distance);maximum=math.max(maximum,vehicle.distance)
            end
            check('yard_speed_limit_is_independent_of_frame_rate_offset_'..offset,
                withinLimit and minimum>1.8 and maximum-minimum<.05,
                ('limit=%s min=%.4f max=%.4f'):format(tostring(withinLimit),minimum,maximum))
        end
    end
    for _,seed in ipairs({712345,712346,43127}) do
        local state,town,world,deliveries,site=fixture(seed,3)
        local time=EPOCH+10;local order={};local overlaps=false;local leaseBroken=false
        local stopSeen,setupSeen,reverseSeen=false,false,false
        for expected=1,3 do
            local delivery=deliveries[expected]
            local truck=delivery.route.vehicle
            for _=1,1800 do
                time=time+.1;tick(state,town,world,time)
                local atDock=0
                for _,d in ipairs(deliveries) do if d.route.vehicle.phase=='at_bay' then atDock=atDock+1 end end
                leaseBroken=leaseBroken or atDock>1
                if truck.yard then
                    stopSeen=stopSeen or truck.yard.stage=='queue_stop'
                    setupSeen=setupSeen or truck.yard.stage=='setup_stop'
                    reverseSeen=reverseSeen or truck.yard.stage=='reverse'
                    if truck.yard.stage=='reverse' then
                        local _,z=site:toLocal(truck.x,truck.z)
                        leaseBroken=leaseBroken or math.abs(z)>.001 or math.abs(math.sin(truck.heading-site.yaw))>.001
                    end
                end
                if truck.phase=='at_bay' then order[#order+1]=expected;break end
            end
            check('yard_serves_reserved_truck_'..seed..'_'..expected,truck.phase=='at_bay',
                tostring(truck.yard and truck.yard.stage)..'/'..truck.phase)
            -- Receiving/signature may finish before a return route is created.
            -- The dock must remain occupied throughout that handoff.
            delivery.status='received'
            for _=1,20 do time=time+.1;tick(state,town,world,time) end
            for i=expected+1,3 do leaseBroken=leaseBroken or Yard.committed(deliveries[i].route.vehicle) end
            delivery.returnRoute={roadTownId=town.id,departedAtEpoch=time,arrivedAtEpoch=time+500}
            local exit
            for _=1,900 do
                time=time+.1;tick(state,town,world,time)
                exit=delivery.returnRoute.vehicle
                if exit and exit.yard and exit.yard.stage=='released' then break end
                for i=expected+1,3 do
                    local follower=deliveries[i].route.vehicle
                    leaseBroken=leaseBroken or Yard.committed(follower)
                    if exit then overlaps=overlaps or Footprint.overlapsTruck(exit.x,exit.z,exit.heading,
                        follower.x,follower.z,follower.heading,exit.model,follower.model) end
                end
            end
            check('yard_exit_clears_before_next_dock_lease_'..seed..'_'..expected,
                exit and exit.yard and exit.yard.stage=='released' and not leaseBroken and not overlaps)
            -- The normal road driver is tested separately; remove this departed
            -- truck after the strict protocol has released it onto its lane.
            exit.phase='offmap'
        end
        check('yard_mixed_freight_and_pickup_follow_fifo_'..seed,table.concat(order,',')=='1,2,3')
        check('yard_enforces_queue_stop_setup_stop_and_straight_reverse_'..seed,
            stopSeen and setupSeen and reverseSeen and not leaseBroken)
        local events={}
        for _,event in ipairs(Watchdog.snapshot(state).events) do events[#events+1]=event.subject..'/'..event.stage..'/'..event.reason..'/'..event.action end
        check('yard_normal_queue_and_service_need_no_recovery_'..seed,#events==0,table.concat(events,'; '))
    end
    local state,town,world,deliveries,site=fixture(712345,1)
    local truck=deliveries[1].route.vehicle
    local normalUpdate=Truck.update;local roadCalls=0
    Truck.update=function(...)roadCalls=roadCalls+1;return normalUpdate(...)end
    local ran,reason=pcall(function()
        for i=1,1000 do tick(state,town,world,EPOCH+10+i*.1);if truck.phase=='at_bay' then break end end
    end)
    Truck.update=normalUpdate
    check('yard_takes_control_from_general_driving_ai',ran and truck.phase=='at_bay' and roadCalls==0,tostring(reason))

    state,town,world,deliveries,site=fixture(712345,1)
    truck=deliveries[1].route.vehicle
    truck.x,truck.z=site:toWorld(20,0,0);truck.heading=site.yaw;truck.phase='approaching'
    truck.yard={version=1,target='dock',stage='reverse',wait=0,pause=0,recoveries=0}
    local obstruction=Truck.new(select(1,site:toWorld(15.5,0,0)),select(2,site:toWorld(15.5,0,0)),site.yaw)
    state.home.commute={participants={},truck=obstruction,aiMotorcycles={}}
    local firstX,firstZ=truck.x,truck.z
    for i=1,30 do tick(state,town,world,EPOCH+10+i*.1) end
    check('yard_obstruction_stops_before_watchdog_teleport',truck.phase~='at_bay'
        and truck.speed==0 and not truck.collisionContact and truck.yard.recoveries==0)
    deliveries[1].route.vehicle=clone(truck);truck=deliveries[1].route.vehicle
    local validation={};require('src.save_schema.primitives').install(validation)
    require('src.save_schema.paper').install(validation)
    check('yard_saved_reservation_and_stall_timer_validate',validation.delivery(deliveries[1])
        and truck.yard.wait>0 and Yard.valid(truck.yard))
    for i=1,120 do tick(state,town,world,EPOCH+13+i*.1);if truck.phase=='at_bay' then break end end
    check('yard_watchdog_teleports_to_clear_reserved_dock_after_reload',truck.phase=='at_bay'
        and truck.yard.recoveries==1 and (truck.x-firstX)^2+(truck.z-firstZ)^2>25
        and not Footprint.overlapsTruck(truck.x,truck.z,truck.heading,obstruction.x,obstruction.z,obstruction.heading))
    check('yard_recovery_does_not_complete_cargo_or_sign_receipt',deliveries[1].status=='pending_arrival')
    local logged=false
    for _,event in ipairs(Watchdog.snapshot(state).events) do
        logged=logged or event.status=='RECOVERED' and event.action=='Teleported truck to its clear reserved protocol checkpoint'
    end
    check('yard_recovery_is_visible_in_watchdog',logged)
    local broken=clone(truck.yard);broken.rail={station=-1}
    check('yard_rejects_invalid_saved_progress',not Yard.valid(broken))
    broken=clone(truck.yard);broken.target='waiting-2';broken.stage='docked'
    check('yard_rejects_queue_stop_claiming_dock_ownership',not Yard.valid(broken))

    -- Deliberately freeze the new controller. Recovery must complete the step
    -- without permitting a second truck to steal the same dock reservation.
    state,town,world,deliveries=fixture(712345,2)
    truck=deliveries[1].route.vehicle
    for i=1,20 do tick(state,town,world,EPOCH+10+i*.1) end
    local step=Rail.step
    Rail.step=function()return false,0,'injected controller stall'end
    for i=1,100 do tick(state,town,world,EPOCH+10+i*.1) end
    Rail.step=step
    check('yard_watchdog_recovers_frozen_controller_to_checkpoint',truck.yard and truck.yard.recoveries>0)
    for i=1,1000 do tick(state,town,world,EPOCH+20+i*.1);if truck.phase=='at_bay' then break end end
    check('yard_resumes_after_controller_stall_without_reordering',truck.phase=='at_bay'
        and deliveries[2].route.vehicle.phase~='at_bay')
    local x,z=truck.x,truck.z
    local allowed=Yard.unstick(truck,{target='outbound',permitted=false},world,state,'outbound')
    check('yard_manual_unstick_cannot_steal_exit_reservation',not allowed and truck.x==x and truck.z==z)

    state,town,world,deliveries=fixture(712345,1)
    truck=deliveries[1].route.vehicle
    for i=1,25 do tick(state,town,world,EPOCH+10+i*.1) end
    local issue='delivery-yard:FREIGHT-1'
    Watchdog.note(state,issue,{status='STALLED',system='Shop yard protocol',reason='Injected manual recovery test'})
    check('yard_watchdog_offers_manual_protocol_recovery',Network.debugUnstickAvailable(state,issue))
    local moved,message=Network.debugUnstick(state,issue)
    check('yard_manual_recovery_uses_reserved_checkpoint',moved and truck.yard.target=='dock'
        and truck.yard.recoveries==1,tostring(message))

    -- Older saves may have received freight but no exterior truck yet.
    -- Restore at most one departure, and only after its full footprint clears.
    state,town,world,deliveries,site=fixture(712345,3)
    for i=1,2 do
        local delivery=deliveries[i]
        delivery.status='received';delivery.route.vehicle=nil
        delivery.returnRoute={roadTownId=town.id,departedAtEpoch=EPOCH+i,arrivedAtEpoch=EPOCH+500}
    end
    local x,z=site:toWorld(site.design.truckParking.x,site.design.truckParking.z,0)
    state.home.commute={participants={},truck=Truck.new(x,z,site.yaw),aiMotorcycles={}}
    tick(state,town,world,EPOCH+10)
    check('yard_restored_departure_waits_for_clear_spawn',not deliveries[1].returnRoute.vehicle
        and not deliveries[2].returnRoute.vehicle and not Yard.committed(deliveries[3].route.vehicle))
    state.home.commute.truck=nil
    tick(state,town,world,EPOCH+10.1)
    check('yard_restores_only_the_reserved_departure',deliveries[1].returnRoute.vehicle~=nil
        and deliveries[2].returnRoute.vehicle==nil and not Yard.committed(deliveries[3].route.vehicle))
end
return Test
