-- The visible final journey uses the generated town road graph and the
-- existing commute rider/renderer. This transient clock is never saved;
-- Continue safely replays the opening from its first beat.
local Arrival={}
local Routes=require('src.commute.routes')
local Commute=require('src.commute.runtime')
local Rider=require('src.commute.rider')
local Bike=require('src.commute.motorcycle')
local Sites=require('src.commute.sites')
local ScheduledDriving=require('src.commute.scheduled_driving')
local BikeService=require('src.commute.bike_service')
local Residents=require('src.home_residents')
local function length(a,b) return math.sqrt((b.x-a.x)^2+(b.z-a.z)^2) end
local function ease(value)
    value=math.max(0,math.min(1,value))
    return value*value*(3-2*value)
end
local function sample(plan,d)
    d=math.max(0,math.min(plan.length,d))
    for i=2,#plan.points do
        if d<=plan.cumulative[i] or i==#plan.points then
            local a,b=plan.points[i-1],plan.points[i]
            local span=plan.cumulative[i]-plan.cumulative[i-1]
            local t=span>0 and (d-plan.cumulative[i-1])/span or 0
            return a.x+(b.x-a.x)*t,a.z+(b.z-a.z)*t
        end
    end
    local p=plan.points[#plan.points]
    return p.x,p.z
end
function Arrival.plan(world)
    local farm=world.sites and world.sites.byId.farm
    local farmDrive
    for _,path in ipairs(world.roads and world.roads.paths or {}) do
        if path.id=='farm-drive' then farmDrive=path;break end
    end
    if not farm or not farmDrive or not farmDrive.points[#farmDrive.points]
        or not world.roads.destinations.mainland_exit then
        return nil,'The farm arrival road is unavailable.'
    end
    local endpoint=farmDrive.points[#farmDrive.points]
    local planner=Routes.new(world.roads,{destinations={story_farm=endpoint}})
    local route,reason=planner:find('mainland_exit','story_farm')
    if not route or #route.points<2 then return nil,reason or 'No connected route to the farm.' end
    local points=route.points
    local parking=farm.parking
    if length(points[#points],parking)>.05 then
        points[#points+1]={x=parking.x,z=parking.z,h=parking.h}
    end
    local cumulative={[1]=0}
    for i=2,#points do cumulative[i]=cumulative[i-1]+length(points[i-1],points[i]) end
    if cumulative[#points]<20 then return nil,'The farm route is too short to present.' end
    route.length=cumulative[#points]
    local walk={}
    for _,point in ipairs(Sites.farmStory.walk) do
        local x,z=farm:toWorld(point.x,point.z,0)
        walk[#walk+1]={x=x,z=z}
    end
    local terrainPath={}
    for _,point in ipairs(points) do terrainPath[#terrainPath+1]=point end
    for _,point in ipairs(walk) do terrainPath[#terrainPath+1]=point end
    return {points=points,cumulative=cumulative,length=cumulative[#points],walk=walk,
        route=route,terrainPath=terrainPath,farm=farm,crossesBridge=route.crossesBridge}
end
local function sync(R,part)
    local rider=part.rider
    local pose,progress=Rider.pose(rider)
    local actor=Rider.actor(rider)
    part.presentation={pose=pose,progress=progress,speed=actor.speed or 0,
        distance=actor.distance or 0,h=rider.bike.h,vy=rider.bike.vy,
        grounded=rider.bike.grounded,suspension=rider.bike.suspension,
        pitch=rider.bike.pitch,throttle=rider.bike.throttle or 0,
        brake=rider.bike.brake or 0,steer=rider.bike.steering or 0}
    Commute.syncPlayer(R.World.player,part)
end
local function placeRide(R,arrival,pose)
    local rider=Commute.localPart(R).rider
    local x,z=pose.x,pose.z
    local heading=pose.heading
    local speed=math.max(0,pose.speed or 0)
    local previousSpeed=arrival.lastSpeed or 0
    local bike=rider.bike
    bike.x,bike.z,bike.heading=x,z,heading
    bike.speed=speed;bike.vx,bike.vz=math.cos(heading)*speed,math.sin(heading)*speed
    bike.distance=(bike.distance or 0)+math.max(0,(pose.distance or arrival.distance)-arrival.distance)
    bike.h=pose.h or Commute.world(R):supportHeight(x,z)
    bike.vy=0;bike.grounded=true
    bike.throttle=speed>previousSpeed+.05 and .42 or speed>1 and .24 or 0
    bike.brake=speed<previousSpeed-.05 and .45 or 0
    bike.safeX,bike.safeZ,bike.safeHeading=x,z,heading
    rider.ped.x,rider.ped.z,rider.ped.heading=x,z,heading
    arrival.distance=pose.distance or arrival.distance
    arrival.lastSpeed=speed
    sync(R,Commute.localPart(R))
end
function Arrival.finishJourneyFuel(R,arrival)
    local part=Commute.localPart(R)
    local rider=part and part.rider
    if not rider or not rider.bike or not rider.bike.service then return false end
    local fuel=rider.bike.service.fuel or BikeService.tank
    local start=arrival and arrival.fuelStart or fuel
    local low=arrival and arrival.fuelEnd or BikeService.tank*.11
    rider.bike.service.fuel=math.min(fuel,start,low)
    if start>low then
        rider.bike.service.revision=(rider.bike.service.revision or 0)+1
    end
    local residents=R.state.home and R.state.home.residents
    local resident=residents and residents[Residents.key(R.World.player)]
    if resident then
        resident.ridingService=BikeService.copy(rider.bike.service)
        resident.revision=(resident.revision or 0)+1
        R.state.home.revision=(R.state.home.revision or 0)+1
    end
    return true
end
function Arrival.begin(R,state)
    local plan,reason=Arrival.plan(Commute.world(R))
    if not plan then return false,reason end
    local part=Commute.localPart(R)
    if not part then return false,'The Story rider is missing.' end
    local rider=part.rider
    local vehicle={trafficKind='motorcycle',aiKind='motorcycle',driverSkill=55}
    local drivePlan=ScheduledDriving.profile(plan.route,Commute.world(R),vehicle)
    if not drivePlan or drivePlan.duration<=0 then
        return false,'The Story motorcycle route has no safe driving profile.'
    end
    rider.gear.outfit='normal';rider.gear.mounted=false;rider.gear.engine=false
    rider.gear.transition=nil;rider.gear.revision=rider.gear.revision+1
    rider.ped.speed=0;rider.ped.vx=0;rider.ped.vz=0
    rider.bike.distance=0;rider.bike.speed=0;rider.bike.vx=0;rider.bike.vz=0
    rider.bike.throttle=0;rider.bike.brake=0
    local fuelStart=rider.bike.service and rider.bike.service.fuel or BikeService.tank
    state.arrival={plan=plan,drivePlan=drivePlan,vehicle=vehicle,phase='equip',
        distance=0,elapsed=0,walkIndex=1,stalled=0,lastSpeed=0,
        fuelStart=fuelStart,fuelEnd=math.min(fuelStart,BikeService.tank*.11)}
    local initial=ScheduledDriving.sample(plan.route,0,Commute.world(R),vehicle)
    if not initial then state.arrival=nil;return false,'The Story motorcycle route could not be sampled.' end
    placeRide(R,state.arrival,initial)
    Bike.resetContact(rider.bike,Commute.world(R))
    local footX,footZ=Rider.footing(rider,Commute.world(R))
    if footX then rider.ped.x,rider.ped.z=footX,footZ end
    local okay,equipReason=Rider.command(rider,'equip',Commute.world(R))
    if not okay then state.arrival=nil;return false,equipReason end
    sync(R,part)
    state.arrival.visualHeading=initial.heading
    return true
end
local function updateRider(rider,world,input,dt)
    local remaining=dt
    while remaining>1e-6 do
        local step=math.min(.1,remaining)
        Rider.update(rider,input,step,world)
        remaining=remaining-step
    end
end
function Arrival.update(R,state,dt)
    local arrival=state.arrival
    if not arrival then return false end
    local view=R._commute
    local world=Commute.world(R)
    local part=Commute.localPart(R)
    local rider=part.rider
    if not view or not view.renderer or view.loading then
        Commute.update(R,dt,0,0,false,true)
        return false
    end
    -- Do not outrun the streamed ground. On a fresh town or a slow phone this
    -- holds the camera on a finished road section while the next tiles upload.
    if view.renderer.effectiveRadius<24 then
        Commute.update(R,dt,0,0,false,true)
        return false
    end
    if arrival.phase=='equip' or arrival.phase=='mount' or arrival.phase=='ride' then
        local lookAhead=arrival.phase=='ride' and math.min(arrival.drivePlan.length,arrival.distance+13)
            or arrival.distance
        local x,z=sample(arrival.plan,lookAhead)
        if not view.renderer:terrainCoverage(x,z) then
            Commute.update(R,dt,0,0,false,true)
            return false
        end
    end
    arrival.elapsed=arrival.elapsed+dt
    if arrival.phase=='equip' or arrival.phase=='mount' then
        updateRider(rider,world,{},dt)
        if not rider.gear.transition then
            if arrival.phase=='equip' then
                local okay,reason=Rider.command(rider,'mount',world)
                if not okay then return nil,reason or 'The rider could not mount the motorcycle.' end
                arrival.phase='mount'
            else
                rider.gear.engine=true;rider.gear.revision=rider.gear.revision+1
                arrival.phase='ride';arrival.elapsed=0
            end
        end
        sync(R,part)
    elseif arrival.phase=='ride' then
        local progress=math.min(1,arrival.elapsed/arrival.drivePlan.duration)
        local pose=ScheduledDriving.sample(arrival.plan.route,progress,world,arrival.vehicle)
        if not pose then return nil,'The Story motorcycle route could not be sampled.' end
        if pose.speed>.05 then
            local distance=pose.distance or arrival.distance
            local bx,bz=sample(arrival.plan,math.max(0,distance-2.8))
            local ax,az=sample(arrival.plan,math.min(arrival.plan.length,distance+2.8))
            if math.sqrt((ax-bx)^2+(az-bz)^2)>.01 then
                pose.heading=math.atan2(az-bz,ax-bx)
            end
            arrival.visualHeading=pose.heading
        elseif arrival.visualHeading then pose.heading=arrival.visualHeading end
        local driveProgress=pose.progress or progress
        rider.bike.service.fuel=arrival.fuelStart
            +(arrival.fuelEnd-arrival.fuelStart)*ease(driveProgress)
        placeRide(R,arrival,pose)
        if progress>=1 then
            rider.bike.speed=0;rider.bike.vx=0;rider.bike.vz=0
            rider.gear.engine=false
            Bike.resetContact(rider.bike,world)
            local okay=Rider.command(rider,'dismount',world)
            if not okay then return nil,'The farm parking has no safe place to dismount.' end
            arrival.phase='dismount'
            sync(R,part)
        end
    elseif arrival.phase=='dismount' or arrival.phase=='remove' then
        updateRider(rider,world,{},dt)
        if not rider.gear.transition then
            if arrival.phase=='dismount' then
                local okay=Rider.command(rider,'remove',world)
                if not okay then return nil,'The rider could not remove the helmet.' end
                arrival.phase='remove'
            else arrival.phase='walk' end
        end
        sync(R,part)
    elseif arrival.phase=='walk' then
        local target=arrival.plan.walk[arrival.walkIndex]
        if not target then return true end
        local dx,dz=target.x-rider.ped.x,target.z-rider.ped.z
        local beforeX,beforeZ=rider.ped.x,rider.ped.z
        local distance=math.sqrt(dx*dx+dz*dz)
        if distance<.55 then arrival.walkIndex=arrival.walkIndex+1
        else
            updateRider(rider,world,{walkX=dx/distance,walkZ=dz/distance},dt)
            local moved=math.sqrt((rider.ped.x-beforeX)^2+(rider.ped.z-beforeZ)^2)
            arrival.stalled=moved<.01 and arrival.stalled+dt or 0
            if arrival.stalled>2 then return nil,'The porch walk is blocked.' end
        end
        sync(R,part)
        if arrival.walkIndex>#arrival.plan.walk then return true end
    end
    Commute.update(R,dt,0,0,false,true)
    return false
end
function Arrival.progress(state)
    local arrival=state.arrival
    if not arrival then return 0 end
    if arrival.phase=='equip' then return 0 end
    if arrival.phase=='mount' then return .05 end
    if arrival.phase=='ride' then return .05+.80*arrival.distance/arrival.drivePlan.length end
    if arrival.phase=='dismount' then return .86 end
    if arrival.phase=='remove' then return .89 end
    return .9+.1*(arrival.walkIndex-1)/#arrival.plan.walk
end
return Arrival
