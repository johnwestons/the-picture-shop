local P=require('src.commute.prediction')
local Rider=require('src.commute.rider')
local Bike=require('src.commute.motorcycle')
local Truck=require('src.commute.delivery_truck')
local Traffic=require('src.commute.delivery_traffic')
local Trip=require('src.commute.trip')
local R=require('src.net.shop_replication')
local Test={}
local function world()
    return {height=function()return 0 end,supportHeight=function()return 0,'road'end,
        roads={sample=function()return 0,{width=40}end,nearest=function()return 0,{width=40}end,
            blocked=function()return false end}}
end
local function fixture(mode,obstacle)
    local state=require('src.state').new()
    local rider=Rider.new(100,100,0,{version=1,outfit=mode=='bike' and 'geared' or 'normal',
        mounted=mode=='bike',engine=mode=='bike',revision=0})
    local part={slot=1,arrived=false,rider=rider}
    local trip={version=1,token=51,independent=true,participants={owner=part}}
    state.home.commute=trip
    local w=world()
    if mode=='box' or mode=='kei' then
        rider.vehicle='truck';rider.truck=Truck.new(100,100,0,nil,mode);rider.truck.driver='owner'
        rider.truck.speed=1.2
        trip[mode=='box' and 'truck' or 'keiTruck']=rider.truck
    else rider.bike.speed=1.2;Bike.resetHorizontal(rider.bike);Bike.resetContact(rider.bike,w) end
    if obstacle then
        local model=mode=='box' and 'kei' or 'box'
        local ownRadius=(mode=='box' or mode=='kei') and require('src.commute.truck_footprint').dimensions(mode).halfLength or Bike.RADIUS
        local x=100+ownRadius+require('src.commute.truck_footprint').dimensions(model).halfLength+.15
        local other=Truck.new(x,100,0,nil,model);other.engine=false
        trip[model=='box' and 'truck' or 'keiTruck']=other
    end
    return state,part,w
end
local function rebind(state)
    local trip=state.home.commute;local rider=trip.participants.owner.rider
    if rider.vehicle=='truck'then rider.truck=rider.truck.model=='kei' and trip.keiTruck or trip.truck end
    return trip.participants.owner
end

function Test.run(check)
    for _,mode in ipairs({'bike','box','kei'})do
        local host,part,hostWorld=fixture(mode,true)
        local client=R.copy(host);local durable=rebind(client);local clientWorld=world()
        local before=R.copy(client)
        local player={id=1,homeResidentId='owner'}
        local matches,contacts=true,0
        for _=1,180 do
            Traffic.installVehicleObstacles(host,hostWorld)
            Trip.update(host,player,P.controls(part.rider,0,-.15,false),1/60,hostWorld)
            hostWorld.vehicleObstacles=nil;hostWorld.sweepTrafficObstacles=nil
            P.step(player,durable,51,1/60,0,-.15,false,clientWorld,client)
            matches=matches and P.matches(P.capture(part,51),P.captureLocal(player))
            if Rider.actor(part.rider).collisionContact then contacts=contacts+1 end
        end
        check('prediction_stationary_truck_collision_matches_host_'..mode,matches and contacts>120,
            'contacts='..contacts..' host x='..Rider.actor(part.rider).x..' predicted x='..Rider.actor(player._predictedCommute.rider).x)
        check('prediction_collision_does_not_mutate_shared_state_'..mode,R.equal(client,before))
        check('prediction_collision_callbacks_do_not_leak_'..mode,clientWorld.vehicleObstacles==nil
            and clientWorld.sweepTrafficObstacles==nil)
        local clear,clearPart,clearWorld=fixture(mode,false)
        local free={id=1}
        for _=1,120 do P.step(free,clearPart,51,1/60,0,-.3,false,clearWorld,clear)end
        check('prediction_clone_does_not_collide_with_own_authoritative_body_'..mode,
            Rider.actor(free._predictedCommute.rider).x>102
                and not Rider.actor(free._predictedCommute.rider).collisionContact)
    end
    local state,part,w=fixture('bike',false)
    state.home.commute.aiMotorcycles={{id=17,bike=Bike.new(103,100,0)}}
    local ai=state.home.commute.aiMotorcycles[1].bike
    local delivery=Truck.new(120,100,0,nil,'box');delivery.phase='approaching'
    state.procurement.shipments={{id=91,delivery={status='in_transit',route={vehicle=delivery}}}}
    local before=R.copy(state);local events=state.calendar.customEvents
    local oldVehicles=function()return 'old vehicles'end
    local oldSweep=function()return 'old sweep'end
    w.vehicleObstacles,w.sweepTrafficObstacles=oldVehicles,oldSweep
    local first,second
    Traffic.withPredictionObstacles(state,w,part.rider,nil,function()
        first=w.sweepTrafficObstacles(100,100,104,100,Bike.RADIUS,0,1.2)
        local outerVehicles,outerSweep=w.vehicleObstacles,w.sweepTrafficObstacles
        Traffic.withPredictionObstacles(state,w,part.rider,nil,function()end)
        check('prediction_nested_obstacle_scope_restores_outer_callbacks',
            w.vehicleObstacles==outerVehicles and w.sweepTrafficObstacles==outerSweep)
    end)
    ai.z=110
    Traffic.withPredictionObstacles(state,w,part.rider,nil,function()
        second=w.sweepTrafficObstacles(100,100,104,100,Bike.RADIUS,0,1.2)
    end)
    ai.z=100
    check('prediction_obstacles_use_latest_replicated_pose_each_step',first~=nil and second==nil)
    local movingState,movingPart,movingWorld=fixture('bike',true)
    local subject=movingPart.rider.bike
    local parked=movingState.home.commute.truck
    local originalHit,frame=Traffic.withPredictionObstacles(movingState,movingWorld,
        movingPart.rider,nil,function()
            return movingWorld.sweepTrafficObstacles(100,100,106,100,Bike.RADIUS,0,1.2)
        end,nil,subject)
    parked.x=parked.x+12
    local replayedHit=Traffic.withPredictionObstacles(movingState,movingWorld,
        movingPart.rider,nil,function()
            return movingWorld.sweepTrafficObstacles(100,100,106,100,Bike.RADIUS,0,1.2)
        end,frame,subject)
    local currentHit=Traffic.withPredictionObstacles(movingState,movingWorld,
        movingPart.rider,nil,function()
            return movingWorld.sweepTrafficObstacles(100,100,106,100,Bike.RADIUS,0,1.2)
        end,nil,subject)
    check('prediction_replay_uses_original_moving_truck_pose',frame and originalHit
        and replayedHit and math.abs(originalHit-replayedHit)<1e-8 and currentHit==nil)
    check('prediction_obstacle_gather_is_read_only_for_ai_deliveries_and_calendar',R.equal(state,before)
        and state.calendar.customEvents==events and ai.trafficId==nil and delivery.trafficId==nil)
    state.procurement.shipments[1].delivery.route.transportId='missing'
    before=R.copy(state)
    Traffic.withPredictionObstacles(state,w,part.rider,nil,function()
        check('prediction_orphan_delivery_stays_collidable_without_repairing_saved_link',
            w.vehicleObstacles(120,100,0,Truck.new(120,100,0,nil,'kei'))==true)
    end)
    check('prediction_does_not_repair_orphan_transport_links',R.equal(state,before))
    local okay,err=pcall(Traffic.withPredictionObstacles,state,w,part.rider,nil,function()error('scope-test')end)
    check('prediction_obstacle_scope_restores_callbacks_after_error',not okay and tostring(err):find('scope%-test')
        and w.vehicleObstacles==oldVehicles and w.sweepTrafficObstacles==oldSweep)
    -- A walking clone is excluded too, while nearby other residents remain.
    part.rider.gear.mounted=false;part.rider.gear.engine=false
    part.rider.ped.x,part.rider.ped.z=100,100
    local other=Rider.new(103,100,0,{version=1,outfit='normal',mounted=false,engine=false,revision=0})
    other.ped.x,other.ped.z=103,100
    state.home.commute.participants.guest={slot=2,rider=other}
    state.home.commute.aiMotorcycles={};state.procurement.shipments={}
    Traffic.withPredictionObstacles(state,w,part.rider,nil,function()
        check('prediction_pedestrian_alias_exclusion_keeps_other_residents',
            w.sweepTrafficObstacles(100,100,100.2,100,.32,0,1.7)==nil
                and w.sweepTrafficObstacles(100,100,104,100,.32,0,1.7)~=nil)
    end)
end
return Test
