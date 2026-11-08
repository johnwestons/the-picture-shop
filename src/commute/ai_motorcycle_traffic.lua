-- Small host-simulated motorcycle traffic that uses the live road network and
-- the same route follower as delivery trucks.
local Bike=require('src.commute.motorcycle')
local Damage=require('src.commute.bike_damage')
local Routes=require('src.commute.routes')
local DrivingPath=require('src.commute.driving_path')
local AIWatchdog=require('src.ai_watchdog')
local Traffic={MAX_BIKES=2,MAX_ROUTE_PAIRS=2,HALF_LENGTH=.65,HALF_WIDTH=.38,HEIGHT=1.55,
    CRASH_RECOVERY_DELAY=1.25}

-- Keep generated route geometry only while its road graph is in use. Town IDs
-- are strings and would otherwise retain every rerolled town's route points.
local routeCache=setmetatable({}, {__mode='k'})
local rescueFailures=setmetatable({}, {__mode='k'})
local BIKE_FIELDS={'x','z','heading','speed','distance','h','pitch','lean','steering',
    'throttle','brake','gear','transmission','reverse','damage','collisionContact',
    'collisionKind','collisionId','impactPulse','impactStrength','rescueCount',
    'safeX','safeZ','safeHeading'}
local DESTINATIONS={'warehouse','gas-station','mechanic','grocery','general-store',
    'diner','coffee-shop','brick-walkup','garden','courtyard','corner'}

local function finite(value)
    return type(value)=='number' and value==value and math.abs(value)<math.huge
end
local function integer(value,minimum,maximum)
    return finite(value) and value%1==0 and value>=minimum and value<=maximum
end
local function validCrashPending(pending)
    if pending==nil then return true end
    if type(pending)~='table' or not finite(pending.dx) or not finite(pending.dz)
        or not finite(pending.nx) or not finite(pending.nz) or not finite(pending.speed)
        or not finite(pending.severity) or pending.speed<0 or pending.speed>Bike.MAX_SPEED
        or pending.severity<0 or pending.severity>1
        or type(pending.kind)~='string' or #pending.kind>40 then return false end
    local directionLength=math.sqrt(pending.dx*pending.dx+pending.dz*pending.dz)
    local normalLength=math.sqrt(pending.nx*pending.nx+pending.nz*pending.nz)
    return directionLength>.9 and directionLength<1.1 and normalLength>.9 and normalLength<1.1
end
local function validRescueHistory(history)
    if history==nil then return true end
    if type(history)~='table' or #history>6 then return false end
    local count=0
    for index,point in pairs(history) do
        count=count+1
        if not integer(index,1,6) or type(point)~='table'
            or not finite(point.x) or point.x<0 or point.x>512
            or not finite(point.z) or point.z<0 or point.z>512 then return false end
    end
    return count==#history
end
local function validSavedBikeState(bike)
    if type(bike)~='table' or not finite(bike.x) or not finite(bike.z)
        or bike.x<0 or bike.x>512 or bike.z<0 or bike.z>512
        or not finite(bike.heading) or math.abs(bike.heading)>math.pi*4
        or not finite(bike.speed) or bike.speed<0 or bike.speed>Bike.MAX_SPEED then return false end
    if bike.h~=nil and (not finite(bike.h) or bike.h< -2 or bike.h>100)
        or bike.distance~=nil and (not finite(bike.distance) or bike.distance<0 or bike.distance>1e12)
        or bike.gear~=nil and not integer(bike.gear,1,#Bike.GEARS)
        or bike.transmission~=nil and bike.transmission~='automatic' and bike.transmission~='manual'
        or bike.reverse~=nil and type(bike.reverse)~='boolean'
        or bike.damage~=nil and not Damage.valid(bike.damage)
        or bike.collisionContact~=nil and type(bike.collisionContact)~='boolean'
        or bike.collisionKind~=nil and (type(bike.collisionKind)~='string' or #bike.collisionKind>40)
        or bike.collisionId~=nil and not (type(bike.collisionId)=='string' and #bike.collisionId<=80
            or finite(bike.collisionId))
        or bike.impactPulse~=nil and (not finite(bike.impactPulse) or bike.impactPulse<0
            or bike.impactPulse>Bike.IMPACT_DURATION)
        or bike.impactStrength~=nil and (not finite(bike.impactStrength)
            or bike.impactStrength<0 or bike.impactStrength>1)
        or bike.rescueCount~=nil and not integer(bike.rescueCount,0,1000000000)
        or bike.safeX~=nil and (not finite(bike.safeX) or bike.safeX<0 or bike.safeX>512)
        or bike.safeZ~=nil and (not finite(bike.safeZ) or bike.safeZ<0 or bike.safeZ>512)
        or bike.safeHeading~=nil and (not finite(bike.safeHeading) or math.abs(bike.safeHeading)>math.pi*4)
        or (bike.safeX==nil)~=(bike.safeZ==nil)
        or not validCrashPending(bike.crashPending)
        or not validRescueHistory(bike.rescueHistory) then return false end
    return true
end
local function pairRoutes(world)
    local cacheKey=world.roads
    local cached=routeCache[cacheKey]
    if cached~=nil then return cached or nil end
    local drivingMap=world.roads.drivingMap
    local mapDistances,mapDestinationIndex={},{}
    if drivingMap and drivingMap.version==2 then
        for index,id in ipairs(drivingMap.destinations or {}) do mapDestinationIndex[id]=index end
        for _,route in ipairs(drivingMap.routes or {}) do
            local from,to=drivingMap.destinations[route.from],drivingMap.destinations[route.to]
            if from and to and finite(route.length) then
                mapDistances[from]=mapDistances[from] or {}
                mapDistances[from][to]=route.length
                if route.bidirectional then
                    mapDistances[to]=mapDistances[to] or {}
                    mapDistances[to][from]=route.length
                end
            end
        end
    end
    local canScoreFromMap=drivingMap and drivingMap.version==2
    if canScoreFromMap then
        for first=1,#DESTINATIONS do
            local from=DESTINATIONS[first]
            if world.roads.destinations[from] then
                for second=first+1,#DESTINATIONS do
                    local to=DESTINATIONS[second]
                    if world.roads.destinations[to]
                        and (not mapDestinationIndex[from] or not mapDestinationIndex[to]
                            or not mapDistances[from] or not mapDistances[from][to]
                            or not mapDistances[to] or not mapDistances[to][from]) then
                        canScoreFromMap=false
                        break
                    end
                end
            end
            if not canScoreFromMap then break end
        end
    end
    local planner=not canScoreFromMap and Routes.new(world.roads,{pavedOnly=true}) or nil
    local candidates={}
    for first=1,#DESTINATIONS do
        local from=DESTINATIONS[first]
        if world.roads.destinations[from] then
            for second=first+1,#DESTINATIONS do
                local to=DESTINATIONS[second]
                if world.roads.destinations[to] then
                    local outLength,inLength
                    if canScoreFromMap then
                        outLength,inLength=mapDistances[from][to],mapDistances[to][from]
                    else
                        local outward=planner:find(from,to)
                        local inward=planner:find(to,from)
                        outLength=outward and (outward.length or DrivingPath.length(outward.points))
                        inLength=inward and (inward.length or DrivingPath.length(inward.points))
                    end
                    if outLength and inLength then
                        local score=outLength+inLength
                        if outLength>=28 and inLength>=28 then
                            candidates[#candidates+1]={from=from,to=to,score=score}
                        end
                    end
                end
            end
        end
    end
    table.sort(candidates,function(a,b)
        if a.score~=b.score then return a.score>b.score end
        if a.from~=b.from then return a.from<b.from end
        return a.to<b.to
    end)
    local orderedCandidates,seenCandidates={},{}
    local function addCandidate(candidate)
        if candidate and not seenCandidates[candidate] then
            seenCandidates[candidate]=true;orderedCandidates[#orderedCandidates+1]=candidate
        end
    end
    addCandidate(candidates[1])
    local firstCandidate=candidates[1]
    local distinctCandidate
    if firstCandidate then
        for _,candidate in ipairs(candidates) do
            if candidate.from~=firstCandidate.from and candidate.from~=firstCandidate.to
                and candidate.to~=firstCandidate.from and candidate.to~=firstCandidate.to then
                distinctCandidate=candidate;break
            end
        end
    end
    addCandidate(distinctCandidate)
    for _,candidate in ipairs(candidates) do addCandidate(candidate) end
    local routes={pairCount=0}
    if #orderedCandidates>0 then
        planner=planner or Routes.new(world.roads,{pavedOnly=true,savedRoutesOnly=true})
        for _,candidate in ipairs(orderedCandidates) do
            if routes.pairCount>=Traffic.MAX_ROUTE_PAIRS then break end
            local outward=planner:find(candidate.from,candidate.to)
            local inward=planner:find(candidate.to,candidate.from)
            if outward and inward then
                local first=routes.pairCount*2+1
                routes[first]={from=candidate.from,to=candidate.to,
                    points=outward.points,length=outward.length}
                routes[first+1]={from=candidate.to,to=candidate.from,
                    points=inward.points,length=inward.length}
                routes.pairCount=routes.pairCount+1
                routes.score=(routes.score or 0)+candidate.score
            end
        end
    end
    routeCache[cacheKey]=#routes>0 and routes or false
    return routeCache[cacheKey] or nil
end
function Traffic.valid(agents)
    if agents==nil then return true end
    if type(agents)~='table' or #agents>Traffic.MAX_BIKES then return false end
    local count,ids=0,{}
    for index,agent in pairs(agents) do
        count=count+1
        local bike=type(agent)=='table' and agent.bike
        if not integer(index,1,Traffic.MAX_BIKES) or type(agent)~='table'
            or type(agent.id)~='string' or #agent.id>40 or ids[agent.id]
            or not integer(agent.routeId,1,Traffic.MAX_ROUTE_PAIRS*2) or not integer(agent.pathIndex,2,4096)
            or not finite(agent.dwell or 0) or (agent.dwell or 0)<0 or (agent.dwell or 0)>2
            or not finite(agent.recoveryTime or 0) or (agent.recoveryTime or 0)<0
            or (agent.recoveryTime or 0)>Traffic.CRASH_RECOVERY_DELAY
            or not validSavedBikeState(bike) then return false end
        ids[agent.id]=true
    end
    return count==#agents
end

function Traffic.snapshot(agents)
    if agents==nil then return nil end
    local result={}
    for index,agent in ipairs(agents) do
        local actor=agent.bike
        local bike={}
        for _,field in ipairs(BIKE_FIELDS) do bike[field]=actor[field] end
        local pending=actor.crashPending
        if pending then
            bike.crashPending={dx=pending.dx,dz=pending.dz,speed=pending.speed,
                nx=pending.nx,nz=pending.nz,severity=pending.severity,kind=pending.kind}
        end
        if actor.rescueHistory then
            bike.rescueHistory={}
            for historyIndex,point in ipairs(actor.rescueHistory) do
                bike.rescueHistory[historyIndex]={x=point.x,z=point.z}
            end
        end
        result[index]={id=agent.id,routeId=agent.routeId,pathIndex=agent.pathIndex,
            dwell=agent.dwell or 0,recoveryTime=agent.recoveryTime or 0,bike=bike}
    end
    return result
end

local function hydrateBike(saved,world,id)
    if saved._aiHydrated then return saved end
    local bike=Bike.new(saved.x,saved.z,saved.heading)
    for _,field in ipairs(BIKE_FIELDS) do
        if saved[field]~=nil then bike[field]=saved[field] end
    end
    local pending=saved.crashPending
    if pending then
        bike.crashPending={dx=pending.dx,dz=pending.dz,speed=pending.speed,
            nx=pending.nx,nz=pending.nz,severity=pending.severity,kind=pending.kind}
    end
    if saved.rescueHistory then
        bike.rescueHistory={}
        for index,point in ipairs(saved.rescueHistory) do
            bike.rescueHistory[index]={x=point.x,z=point.z}
        end
    end
    bike.aiKind='motorcycle';bike.trafficKind='motorcycle';bike.driverSkill=48
    bike.trafficId=id
    Bike.resetContact(bike,world)
    Bike.resetHorizontal(bike)
    bike._aiHydrated=true
    return bike
end
local function nearestRouteIndex(points,x,z)
    local nearestIndex,nearestDistance=2,math.huge
    for index=2,#points do
        local point=points[index]
        local dx,dz=point.x-x,point.z-z
        local distance=dx*dx+dz*dz
        if distance<nearestDistance then nearestIndex,nearestDistance=index,distance end
    end
    return nearestIndex
end
local function recoverCrashedAgent(agent,route,world,dt,watchdogState)
    local bike=agent.bike
    agent.recoveryTime=math.max(0,(agent.recoveryTime>0 and agent.recoveryTime
        or Traffic.CRASH_RECOVERY_DELAY)-dt)
    local rescued,rescueReason=false,nil
    if agent.recoveryTime<=0 then
        rescued,rescueReason=Bike.rescue(bike,world)
        if rescued then
            agent.pathIndex=nearestRouteIndex(route.points,bike.x,bike.z)
            bike.pathIndex=agent.pathIndex;bike.pathTarget=nil
            agent.recoveryTime=0
            rescueFailures[bike]=0
            AIWatchdog.note(watchdogState,'motorcycle-crash:'..tostring(agent.id),{
                status='RECOVERED',system='Road traffic',subject='AI motorcycle '..tostring(agent.id),
                stage='crash_recovery',reason='Motorcycle could not continue after a crash',
                action='Placed at a collision-checked clear road point and resumed its route',
                x=bike.x,z=bike.z,visible=bike.visible~=false,scope='world-simulation'})
        else
            agent.recoveryTime=Traffic.CRASH_RECOVERY_DELAY
            rescueFailures[bike]=(rescueFailures[bike] or 0)+1
            if rescueFailures[bike]==1 or rescueFailures[bike]%3==0 then
                AIWatchdog.note(watchdogState,'motorcycle-crash:'..tostring(agent.id),{
                    status='STALLED',system='Road traffic',subject='AI motorcycle '..tostring(agent.id),
                    stage='crash_recovery',reason='No collision-safe road position was available',
                    action='Kept the rider stopped and scheduled another safe recovery attempt',
                    detail=tostring(rescueReason or 'Recovery area remained blocked'),
                    x=bike.x,z=bike.z,visible=bike.visible~=false,scope='world-simulation'})
            end
        end
    end
    if world.trafficActorIndex then world.trafficActorIndex:update(bike) end
    return rescued
end

function Traffic.ensure(commute,world)
    if type(commute)~='table' or not world then return false end
    local agents=commute.aiMotorcycles
    -- Empty commute traffic is intentional. A schedule or other gameplay
    -- system must create a journey before motorcycle road traffic is active.
    if type(agents)~='table' or #agents==0 then return false end
    local routes=pairRoutes(world)
    if not routes then commute.aiMotorcycles={};return false end
    for index,agent in ipairs(agents) do
        agent.bike=hydrateBike(agent.bike,world,'ai-'..agent.id)
        agent.bike.pathIndex=agent.pathIndex
        agent.recoveryTime=agent.recoveryTime or 0
        if not routes[agent.routeId] then
            agent.routeId=routes.pairCount>=index and (index-1)*2+1 or index
            if not routes[agent.routeId] then agent.routeId=1 end
            agent.pathIndex=2
        end
    end
    return false
end

function Traffic.routes(world)
    return pairRoutes(world)
end

function Traffic.update(commute,world,dt,driveRoute,watchdogState)
    if type(commute)~='table' or not world or type(driveRoute)~='function' then return false,false end
    local changed=Traffic.ensure(commute,world)
    local routes=pairRoutes(world)
    local agents=commute.aiMotorcycles or {}
    if not routes or #agents==0 then return changed,false end
    local moving=false
    for _,agent in ipairs(agents) do
        local bike=agent.bike
        bike.pathIndex=agent.pathIndex
        bike.trafficId='ai-'..agent.id
        if bike.crashPending then
            changed=recoverCrashedAgent(agent,routes[agent.routeId],world,dt,watchdogState) or changed
        elseif agent.dwell>0 then
            agent.recoveryTime=0
            world.activeTrafficBike=bike
            Bike.update(bike,{throttle=0,brake=1,steer=0},dt,world)
            world.activeTrafficBike=nil
            if world.trafficActorIndex then world.trafficActorIndex:update(bike) end
            agent.dwell=math.max(0,agent.dwell-dt)
            moving=moving or bike.speed>.05
        else
            agent.recoveryTime=0
            local route=routes[agent.routeId]
            local arrived=driveRoute(bike,route.points,math.min(.1,dt),world,
                ('ai-motorcycle:%d'):format(agent.routeId))
            agent.pathIndex=bike.pathIndex or agent.pathIndex
            if arrived then
                agent.routeId=agent.routeId%2==1 and agent.routeId+1 or agent.routeId-1
                agent.pathIndex=2;agent.dwell=.45;bike.pathTarget=nil
                bike.speed=0;Bike.resetHorizontal(bike)
                changed=true
            end
            moving=moving or bike.speed>.05
        end
    end
    return changed,moving
end

function Traffic.actors(commute)
    local result={}
    for _,agent in ipairs(commute and commute.aiMotorcycles or {}) do
        local bike=agent.bike
        if type(bike)=='table' then
            bike.aiKind='motorcycle';bike.trafficKind='motorcycle';bike.trafficId='ai-'..agent.id
            result[#result+1]={id='ai-'..agent.id,actor=bike,bike=true,
                deliveryBike=true,phase='riding',label='Motorcycle traffic'}
        end
    end
    return result
end

return Traffic
