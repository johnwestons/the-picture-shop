-- The visible final journey uses the generated town road graph and the
-- existing commute rider/renderer. This transient clock is never saved;
-- Continue safely replays the opening from its first beat.
local Arrival={}
local Routes=require('src.commute.routes')
local Commute=require('src.commute.runtime')
local Rider=require('src.commute.rider')
local Bike=require('src.commute.motorcycle')
local Sites=require('src.commute.sites')
local function length(a,b) return math.sqrt((b.x-a.x)^2+(b.z-a.z)^2) end
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
    local walk={}
    for _,point in ipairs(Sites.farmStory.walk) do
        local x,z=farm:toWorld(point.x,point.z,0)
        walk[#walk+1]={x=x,z=z}
    end
    local terrainPath={}
    for _,point in ipairs(points) do terrainPath[#terrainPath+1]=point end
    for _,point in ipairs(walk) do terrainPath[#terrainPath+1]=point end
    return {points=points,cumulative=cumulative,length=cumulative[#points],walk=walk,
        terrainPath=terrainPath,farm=farm,crossesBridge=route.crossesBridge}
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
local function placeRide(R,arrival,d,dt)
    local rider=Commute.localPart(R).rider
    local x,z=sample(arrival.plan,d)
    local ax,az=sample(arrival.plan,math.max(0,d-1.5))
    local bx,bz=sample(arrival.plan,math.min(arrival.plan.length,d+1.5))
    local heading=math.atan2(bz-az,bx-ax)
    local moved=math.max(0,d-arrival.distance)
    local speed=dt>0 and moved/dt or 0
    local bike=rider.bike
    bike.x,bike.z,bike.heading=x,z,heading
    bike.speed=speed;bike.vx,bike.vz=math.cos(heading)*speed,math.sin(heading)*speed
    bike.distance=(bike.distance or 0)+moved
    bike.h=Commute.world(R):supportHeight(x,z)
    bike.vy=0;bike.grounded=true;bike.throttle=speed>1 and .48 or 0
    bike.brake=arrival.plan.length-d<15 and .4 or 0
    bike.safeX,bike.safeZ,bike.safeHeading=x,z,heading
    rider.ped.x,rider.ped.z,rider.ped.heading=x,z,heading
    arrival.distance=d
    sync(R,Commute.localPart(R))
end
function Arrival.begin(R,state)
    local plan,reason=Arrival.plan(Commute.world(R))
    if not plan then return false,reason end
    local part=Commute.localPart(R)
    if not part then return false,'The Story rider is missing.' end
    local rider=part.rider
    rider.gear.outfit='geared';rider.gear.mounted=true;rider.gear.engine=true
    rider.gear.transition=nil;rider.gear.revision=rider.gear.revision+1
    rider.bike.distance=0;rider.bike.speed=0
    state.arrival={plan=plan,phase='ride',distance=0,elapsed=0,walkIndex=1,stalled=0}
    placeRide(R,state.arrival,0,0)
    Bike.resetContact(rider.bike,Commute.world(R))
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
    if arrival.phase=='ride' then
        local lookAhead=math.min(arrival.plan.length,arrival.distance+13)
        local x,z=sample(arrival.plan,lookAhead)
        if not view.renderer:terrainCoverage(x,z) then
            Commute.update(R,dt,0,0,false,true)
            return false
        end
    end
    arrival.elapsed=arrival.elapsed+dt
    if arrival.phase=='ride' then
        local remaining=arrival.plan.length-arrival.distance
        local speed=math.min(16,math.sqrt(math.max(0,remaining)*8))
            *math.min(1,(arrival.elapsed+.4)/2)
        local distance=math.min(arrival.plan.length,arrival.distance+speed*dt)
        placeRide(R,arrival,distance,dt)
        if distance>=arrival.plan.length-.01 then
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
    if arrival.phase=='ride' then return .85*arrival.distance/arrival.plan.length end
    if arrival.phase=='dismount' then return .86 end
    if arrival.phase=='remove' then return .89 end
    return .9+.1*(arrival.walkIndex-1)/#arrival.plan.walk
end
return Arrival
