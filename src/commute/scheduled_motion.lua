-- Saved progress for scheduled riders. The timetable chooses departures; only
-- host simulation advances a pose. Blocked time is discarded, never caught up.
local Bike=require('src.commute.motorcycle')
local Rules=require('src.commute.traffic_rules')
local Motion={}
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<1e12 end
local function copyPose(p)
    return {x=p.x,z=p.z,h=p.h or 0,heading=p.heading,speed=p.speed or 0,
        progress=p.progress or 0,parked=p.parked==true}
end
function Motion.valid(m,duration)
    if m==nil then return true end
    if type(m)~='table' or not finite(m.elapsed) or m.elapsed<0 or m.elapsed>duration
        or m.target~=nil and (not finite(m.target) or m.target<m.elapsed or m.target>duration)
        or not finite(m.stopSeconds or 0) or (m.stopSeconds or 0)<0 or (m.stopSeconds or 0)>2
        or not finite(m.lastStop or 0) or (m.lastStop or 0)<0
        or type(m.bike)~='table' then return false end
    local b=m.bike
    return finite(b.x) and finite(b.z) and b.x>=0 and b.x<=512 and b.z>=0 and b.z<=512
        and finite(b.h) and finite(b.heading) and finite(b.speed) and b.speed>=0 and b.speed<=Bike.MAX_SPEED+.001
        and finite(b.progress) and b.progress>=0 and b.progress<=1 and type(b.parked)=='boolean'
end
function Motion.pending(journey)
    return journey and journey.motion and (journey.motion.target~=nil
        or journey.motion.elapsed<journey.arriveAtHours-journey.departAtHours-1e-9) or false
end
function Motion.sample(journey,hours,world,route,fromSlot,toSlot,sample)
    local m=journey.motion
    if not m then return sample(journey,hours,world,route,fromSlot,toSlot) end
    local result=sample(journey,journey.departAtHours+m.elapsed,world,route,fromSlot,toSlot)
    if result then result.bike=copyPose(m.bike) end
    return result
end
function Motion.update(journey,hours,dt,hourRate,world,route,fromSlot,toSlot,actor,sample)
    if dt<=0 or not route then return false end
    local duration=journey.arriveAtHours-journey.departAtHours
    if not journey.motion then
        -- Older saves keep their current visible position; subsequent updates
        -- use saved progress even if the original arrival time has passed.
        local elapsed=math.max(0,math.min(duration,hours-journey.departAtHours))
        local initial=sample(journey,journey.departAtHours+elapsed,world,route,fromSlot,toSlot)
        if not initial then return false end
        journey.motion={elapsed=elapsed,bike=copyPose(initial.bike)}
        journey.motion.bike.speed=0
    end
    local m=journey.motion
    if (m.stopSeconds or 0)>0 then
        m.stopSeconds=math.max(0,m.stopSeconds-dt);m.bike.speed=0;return true
    end
    local target=m.target or math.min(duration,m.elapsed+dt*math.max(0,hourRate))
    local nextPose=sample(journey,journey.departAtHours+target,world,route,fromSlot,toSlot)
    if not nextPose then return false end
    local desired=nextPose.bike;local current=m.bike
    -- Do not skip a stop sign when the business clock is accelerated.
    local stopStation
    if nextPose.stage=='riding' and desired.progress>current.progress then
        local plan=require('src.commute.scheduled_driving').profile(route,world)
        for _,node in ipairs(plan and plan.nodes or {}) do
            if node.stop and node.station>(m.lastStop or -1)+.001
                and node.station>=current.progress*plan.length-.001 and node.station<=desired.progress*plan.length then
                desired={x=node.x,z=node.z,h=node.h,heading=desired.heading,
                    progress=node.station/plan.length,parked=false}
                stopStation=node.station;break
            end
        end
    end
    local dx,dz=desired.x-current.x,desired.z-current.z
    local distance=math.sqrt(dx*dx+dz*dz)
    local limit=Bike.MAX_SPEED
    if not desired.parked then
        local _,segment=world.roads:sample(current.x,current.z)
        limit=Rules.limitForTraffic(actor,limit,world.trafficActors,segment,world.trafficActorIndex)
        limit=math.min(limit,current.speed+Bike.ACCELERATION*dt)
    end
    local advance=math.min(distance,math.max(0,limit)*dt)
    local f=distance>1e-8 and advance/distance or 1
    local nx,nz=current.x+dx*f,current.z+dz*f
    local h=world:supportHeight(current.x,current.z)
    local blocked=false
    if distance>1e-8 then
        if world.sweepTrafficObstacles then
            blocked=world.sweepTrafficObstacles(current.x,current.z,nx,nz,Bike.RADIUS+.12,h,h+Bike.COLLISION_HEIGHT,actor)~=nil
        end
        if not blocked and world.sweepObstacles then
            blocked=world:sweepObstacles(current.x,current.z,nx,nz,Bike.RADIUS,h,h+Bike.COLLISION_HEIGHT)~=nil
        end
        if not blocked and world.roads and world.roads.blocked then
            for i=1,math.max(1,math.ceil(advance/.2)) do
                local t=f*i/math.max(1,math.ceil(advance/.2))
                if world.roads:blocked(world,current.x+dx*t,current.z+dz*t) then blocked=true;break end
            end
        end
    end
    if blocked then current.speed=0;m.target=target;return true end
    current.x,current.z,current.h=nx,nz,world:supportHeight(nx,nz)
    current.heading=distance>1e-8 and math.atan2(dz,dx) or desired.heading
    current.speed=advance/dt
    current.progress=current.progress+(desired.progress-current.progress)*f
    current.parked=desired.parked and distance<1e-6
    if f>=1-1e-8 then
        if stopStation then m.lastStop=stopStation;m.stopSeconds=Rules.STOP_DWELL_SECONDS;m.target=target
        else m.elapsed=target;m.target=nil;current.parked=desired.parked end
    elseif not stopStation then
        -- Credit the fraction actually travelled this frame. Holding a tiny
        -- fixed target until the next frame repeatedly reports a near-zero
        -- final step, resetting acceleration and making 60 Hz riders crawl.
        -- Blocked frames return above without earning any clock progress.
        m.elapsed=m.elapsed+(target-m.elapsed)*f
        m.target=nil
    else m.target=target end
    return true
end
return Motion
