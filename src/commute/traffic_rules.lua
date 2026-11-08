-- Shared local-road rules for autonomous delivery vehicles. Town road speed
-- and driver skill are deliberately separate from off-map city trip estimates.
local Rules={NORMAL_TOWN_SPEED=8.6,STOP_DWELL_SECONDS=1.0,
    MIN_FOLLOW_GAP=2.6,FOLLOW_HEADWAY=1.15,BRAKE_DECELERATION=2.2,
    INTERACTION_RADIUS=32,MAX_PASS_CLOSING_SPEED=48,PASS_SEARCH_MARGIN=8}
local Footprint=require('src.commute.truck_footprint')
local motorcycleDimensions={halfLength=.65,halfWidth=.38,radius=.76,height=1.55}

local function clamp(value,lo,hi)return math.max(lo,math.min(hi,value))end
local function finite(value)return type(value)=='number' and value==value and math.abs(value)<math.huge end
function Rules.dimensions(actor)
    if actor and (actor.trafficKind=='motorcycle' or actor.aiKind=='motorcycle') then
        return motorcycleDimensions
    end
    return Footprint.dimensions(actor)
end
function Rules.brakeDeceleration(actor)
    return actor and (actor.trafficKind=='motorcycle' or actor.aiKind=='motorcycle') and 4.5
        or Rules.BRAKE_DECELERATION
end

function Rules.drivingSide(town)
    local rules=town and town.trafficRules
    local side=town and town.trafficSide or type(rules)=='table' and rules.drivingSide
    return side=='left' and 'left' or 'right'
end

function Rules.laneOffset(segment,drivingSide,leftTurn,vehicle)
    -- Bridge decks are narrow and have a hard rail immediately beyond the
    -- paved edge. Keep the vehicle centered there instead of carrying a road
    -- lane offset into the guardrail clearance.
    if not segment or segment.bridge or segment.junction
        or segment.surface=='dirt' or segment.role=='drive' then return 0 end
    local lanes=segment.lanes or 0
    local width=segment.width or 0
    if width<=0 then return 0 end
    if segment.turnLane and leftTurn then return 0 end
    if lanes<2 then
        local motorcycle=vehicle and (vehicle.trafficKind=='motorcycle' or vehicle.aiKind=='motorcycle')
        if motorcycle and not segment.oneWay and lanes==1 then
            -- On an undivided two-way street, ride in the right half instead
            -- of straddling the center. Keep a bike-width margin from the curb.
            local offset=math.max(0,width*.5-Rules.dimensions(vehicle).halfWidth-.35)
            return drivingSide=='left' and -offset or offset
        end
        return 0
    end
    local laneWidth=width/lanes
    local centerOffset=lanes>=3 and laneWidth*(lanes-1)*.5 or laneWidth*.5
    return drivingSide=='left' and -centerOffset or centerOffset
end

function Rules.lanePoint(point,heading,offset,blend)
    local lateral=offset*(blend or 1)
    -- Town maps use positive Z toward the bottom of the overhead map, so the
    -- right side of an eastbound route is +Z (the road segment's left normal).
    return point.x-math.sin(heading)*lateral,point.z+math.cos(heading)*lateral
end

function Rules.driverTownSpeed(vehicle)
    local skill=vehicle and tonumber(vehicle.driverSkill)
    -- A below-baseline local driver is cautious; skill at or above baseline
    -- reaches ordinary town speed but never gains a speed bonus on the map.
    local factor=skill and (.70+.30*clamp(skill/55,0,1)) or 1
    return Rules.NORMAL_TOWN_SPEED*factor
end

local function followingSpeedLimit(vehicle,leadSpeed,desired,speed,clearance)
    local freeDistance=math.max(0,clearance-Rules.MIN_FOLLOW_GAP)
    local headway=clamp(freeDistance/(math.max(1.5,speed)*Rules.FOLLOW_HEADWAY),0,1)
    local headwaySpeed=leadSpeed+(desired-leadSpeed)*headway
    local brakingSpeed=leadSpeed+math.sqrt(2*Rules.brakeDeceleration(vehicle)*freeDistance)
    return math.min(headwaySpeed,brakingSpeed)
end

function Rules.actorBlocksJunction(vehicle,other,kind,junctionX,junctionZ,junctionRadius)
    if not vehicle or not other or other==vehicle or not finite(other.x) or not finite(other.z)
        or not finite(junctionX) or not finite(junctionZ) or not finite(junctionRadius) then return false end
    local dx,dz=junctionX-other.x,junctionZ-other.z
    local distanceSquared=dx*dx+dz*dz
    local occupiedRadius=math.max(0,junctionRadius)+Rules.dimensions(vehicle).radius
    if distanceSquared<occupiedRadius*occupiedRadius then return true end
    local otherSpeed=finite(other.speed) and math.max(0,other.speed) or 0
    if kind~='pedestrian' and otherSpeed<=.35 then return false end
    local approachRadius=occupiedRadius+math.min(6,otherSpeed*.8)
    if distanceSquared>=approachRadius*approachRadius then return false end
    local distance=math.sqrt(distanceSquared)
    local heading=finite(other.heading) and other.heading or 0
    local toward=(dx*math.cos(heading)+dz*math.sin(heading))/math.max(.01,distance)
    return toward>.4
end

local function actorDimensions(entry)
    local actor=entry.actor or entry
    if entry.halfLength or entry.halfWidth then
        return entry.halfLength or .35,entry.halfWidth or .35
    end
    if actor.model or actor.trafficKind=='motorcycle' or actor.aiKind=='motorcycle' then
        local dimensions=Rules.dimensions(actor)
        return dimensions.halfLength,dimensions.halfWidth
    end
    return .35,entry.radius or .35
end

local function projectedDimensions(entry,actor,heading)
    local halfLength,halfWidth=actorDimensions(entry)
    local difference=finite(actor.heading) and actor.heading-heading or 0
    local along,across=math.abs(math.cos(difference)),math.abs(math.sin(difference))
    return halfLength*along+halfWidth*across,halfLength*across+halfWidth*along
end

local function estimatedPassSeconds(vehicle,forward,blockerLength)
    local dimensions=Rules.dimensions(vehicle)
    local passSpeed=math.max(3,(finite(vehicle.speed) and vehicle.speed or 0)*.65)
    local clearanceDistance=math.max(0,forward+dimensions.halfLength+blockerLength+2)
    return clamp(clearanceDistance/passSpeed+1.5,.5,8)
end

function Rules.passLookaheadSeconds(vehicle,forward,blocker)
    if not vehicle or not blocker or not finite(forward) then return 0 end
    local heading=vehicle.heading or 0
    local blockerDimensions=Rules.dimensions(blocker)
    local blockerLength=projectedDimensions({halfLength=blockerDimensions.halfLength,
        halfWidth=blockerDimensions.halfWidth},blocker,heading)
    return estimatedPassSeconds(vehicle,forward,blockerLength)
end

local function visitActors(actors,actorIndex,x,z,radius,callback)
    if actorIndex then
        return actorIndex:forEachCircle(x,z,radius,function(entry,_,actor)
            return callback(entry,actor)
        end)
    end
    local radius2=radius*radius
    for _,entry in ipairs(actors or {}) do
        local actor=entry.actor or entry
        if finite(actor.x) and finite(actor.z)
            and (actor.x-x)^2+(actor.z-z)^2<=radius2
            and callback(entry,actor)==false then return false end
    end
    return true
end

local function visitLaneCorridor(actors,actorIndex,vehicle,heading,lateralOffset,
    longitudinalRadius,lateralRadius,callback)
    local fx,fz=math.cos(heading),math.sin(heading)
    local centerX,centerZ=vehicle.x-fz*lateralOffset,vehicle.z+fx*lateralOffset
    local searchLength=longitudinalRadius+8
    local function visit(entry,other)
        other=other or entry.actor or entry
        if not finite(other.x) or not finite(other.z) then return end
        local dx,dz=other.x-vehicle.x,other.z-vehicle.z
        local forward,lateral=dx*fx+dz*fz,-dx*fz+dz*fx
        if math.abs(forward)<=searchLength and math.abs(lateral-lateralOffset)<=lateralRadius then
            return callback(entry,other,forward,lateral)
        end
    end
    if actorIndex and actorIndex.forEachOrientedBox then
        return actorIndex:forEachOrientedBox(centerX,centerZ,heading,searchLength,lateralRadius,
            function(entry,_,other)return visit(entry,other) end)
    end
    if actorIndex and actorIndex.forEachBox then
        local xRadius=math.abs(fx)*searchLength+math.abs(fz)*lateralRadius
        local zRadius=math.abs(fz)*searchLength+math.abs(fx)*lateralRadius
        return actorIndex:forEachBox(centerX-xRadius,centerZ-zRadius,centerX+xRadius,centerZ+zRadius,
            function(entry,_,other)return visit(entry,other) end)
    end
    for _,entry in ipairs(actors or {}) do
        if visit(entry,entry.actor or entry)==false then return false end
    end
    return true
end

function Rules.laneClear(vehicle,segment,targetOffset,currentOffset,actors,actorIndex,ignoredActor,lookaheadSeconds)
    if not vehicle or not segment or segment.junction or segment.surface=='dirt'
        or segment.role=='drive' or segment.lanes~=2 or not finite(segment.width) then return false end
    local dimensions=Rules.dimensions(vehicle)
    local delta=(targetOffset or 0)-(currentOffset or 0)
    local heading=vehicle.heading or 0
    local lookahead=finite(lookaheadSeconds) and clamp(lookaheadSeconds,0,8) or 0
    local queryRadius=lookahead>0
        and math.max(Rules.INTERACTION_RADIUS,
            Rules.MAX_PASS_CLOSING_SPEED*lookahead+Rules.PASS_SEARCH_MARGIN) or Rules.INTERACTION_RADIUS
    local ownSpeed=math.max(3,finite(vehicle.speed) and vehicle.speed or 0)
    local clear=true
    local laneWidth=segment.width/segment.lanes
    local lateralRadius=math.abs(delta)+dimensions.halfWidth+laneWidth*.5+3.6
    visitLaneCorridor(actors,actorIndex,vehicle,heading,delta,queryRadius,lateralRadius,
        function(entry,other,forward,lateral)
            if other==vehicle or other==ignoredActor
                or not finite(other.x) or not finite(other.z) then return end
            local otherLength,otherWidth=projectedDimensions(entry,other,heading)
            local longitudinallyClose=forward+otherLength> -dimensions.halfLength-1.5
                and forward-otherLength<20+dimensions.halfLength
            if math.abs(lateral-delta)<dimensions.halfWidth+otherWidth+.4 then
                if longitudinallyClose then
                    clear=false
                    return false
                end
                if lookahead>0 then
                    local otherSpeed=finite(other.speed) and math.max(0,other.speed) or 0
                    local otherHeading=finite(other.heading) and other.heading or heading
                    local relativeSpeed=otherSpeed*math.cos(otherHeading-heading)-ownSpeed
                    local closingSpeed=forward>0 and -relativeSpeed or relativeSpeed
                    local clearance=math.abs(forward)-dimensions.halfLength-otherLength-.5
                    if clearance>0 and closingSpeed>0 and clearance/closingSpeed<=lookahead then
                        clear=false
                        return false
                    end
                end
            end
        end)
    return clear
end

-- Give an active pass a last clear strip of pavement when an oncoming road
-- user appears after the vehicle can no longer merge behind the blocker.
function Rules.passEscapeOffset(vehicle,segment,passingOffset,currentOffset,actors,actorIndex,
    ignoredActor,lookaheadSeconds)
    if not vehicle or not segment or segment.junction or segment.surface=='dirt'
        or segment.role=='drive' or segment.oneWay or segment.lanes~=2 or not finite(segment.width) then
        return nil
    end
    local dimensions=Rules.dimensions(vehicle)
    local side=(passingOffset or 0)<0 and -1 or 1
    local edgeClearance=dimensions.halfWidth+.1
    local edgeDistance=segment.width*.5-edgeClearance
    local edgeOffset=side*edgeDistance
    if edgeDistance<=0 or math.abs(edgeOffset-(passingOffset or 0))
        <dimensions.halfWidth*2+.4 then return nil end
    if not Rules.laneClear(vehicle,segment,edgeOffset,currentOffset,actors,actorIndex,
        ignoredActor,lookaheadSeconds) then return nil end
    return edgeOffset
end

-- Pass a stopped road user only when the other lane stays clear for the time
-- needed to get around it. Otherwise the ordinary traffic limit makes it yield.
function Rules.passLaneOffset(vehicle,segment,laneOffset,actors,actorIndex)
    if not vehicle or not segment or segment.junction or segment.surface=='dirt'
        or segment.role=='drive' or segment.oneWay or segment.lanes~=2
        or not finite(segment.width) or segment.width<6 or math.abs(laneOffset or 0)<.15 then return nil end
    local laneWidth=segment.width/segment.lanes
    local dimensions=Rules.dimensions(vehicle)
    local side=laneOffset>0 and -1 or 1
    local candidateOffset=laneOffset+side*laneWidth
    local candidateDelta=candidateOffset-laneOffset
    if math.abs(candidateOffset)+dimensions.halfWidth+.22>segment.width*.5 then return nil end
    local heading=vehicle.heading or 0
    local fx,fz=math.cos(heading),math.sin(heading)
    local blocker,bestForward,blockerLength
    visitActors(actors,actorIndex,vehicle.x,vehicle.z,Rules.INTERACTION_RADIUS,
        function(entry,other)
            if other==vehicle or entry.kind=='pedestrian' or not finite(other.x) or not finite(other.z) then
                return
            end
            local dx,dz=other.x-vehicle.x,other.z-vehicle.z
            local forward,lateral=dx*fx+dz*fz,-dx*fz+dz*fx
            local otherLength,otherWidth=projectedDimensions(entry,other,heading)
            if (other.speed or 0)<.45 and forward>dimensions.halfLength+otherLength+.4
                and forward<16 and math.abs(lateral)<laneWidth*.5+otherWidth
                and (not bestForward or forward<bestForward) then
                blocker,bestForward,blockerLength=other,forward,otherLength
            end
        end)
    if not blocker then return nil end

    local passDuration=estimatedPassSeconds(vehicle,bestForward,blockerLength)
    if not Rules.laneClear(vehicle,segment,candidateOffset,laneOffset,actors,actorIndex,
        blocker,passDuration) then return nil end
    local dx,dz=blocker.x-vehicle.x,blocker.z-vehicle.z
    local lateral=-dx*fz+dz*fx
    local _,blockerWidth=projectedDimensions({actor=blocker},blocker,heading)
    if math.abs(lateral-candidateDelta)<dimensions.halfWidth+blockerWidth+.35 then return nil end
    return candidateOffset,blocker
end

function Rules.limitForTraffic(vehicle,desired,actors,segment,actorIndex,passingActor)
    local heading=vehicle.heading or 0
    local fx,fz=math.cos(heading),math.sin(heading)
    local speed=vehicle.speed or 0
    local baseDesired=desired
    local laneWidth=segment and segment.lanes and segment.lanes>=2 and segment.width
        and segment.width/segment.lanes or 2.4
    local sameLaneTolerance=clamp(laneWidth*.38,.85,1.35)
    local ownDimensions=Rules.dimensions(vehicle)
    local ownHalfLength,ownHalfWidth=ownDimensions.halfLength,ownDimensions.halfWidth
    local yieldOnNarrowRoad=false
    local function consider(entry,other)
        other=other or entry.actor or entry
        if other~=vehicle and finite(other.x) and finite(other.z) then
            local dx,dz=other.x-vehicle.x,other.z-vehicle.z
            local forward=dx*fx+dz*fz
            local lateral=-dx*fz+dz*fx
            local otherHalfLength,otherHalfWidth=actorDimensions(entry)
            local kind=entry.kind or 'vehicle'
            if other==passingActor then
                local _,projectedWidth=projectedDimensions(entry,other,heading)
                if math.abs(lateral)<ownHalfWidth+projectedWidth+.4 then
                    desired=math.min(desired,3.0)
                end
            elseif kind=='pedestrian' then
                if forward>0 and math.abs(lateral)<ownHalfWidth+otherHalfWidth+.35 then
                    local clearance=forward-ownHalfLength-otherHalfLength
                    desired=math.min(desired,followingSpeedLimit(vehicle,
                        math.max(0,other.speed or 0),baseDesired,speed,clearance))
                end
            elseif finite(other.heading) then
                local projectedLength,projectedWidth=projectedDimensions(entry,other,heading)
                local laneHalfWidth=segment and segment.lanes and segment.lanes>=2 and segment.width
                    and segment.width/segment.lanes*.5 or (segment and segment.width or 4.2)*.5
                local alignment=math.cos(other.heading-heading)
                local otherSpeed=math.max(0,other.speed or 0)
                if otherSpeed<.2 and forward>ownHalfLength+projectedLength
                    and forward<Rules.INTERACTION_RADIUS
                    and math.abs(lateral)<laneHalfWidth+projectedWidth then
                    local clearance=forward-ownHalfLength-projectedLength
                    desired=math.min(desired,followingSpeedLimit(vehicle,otherSpeed,
                        baseDesired,speed,clearance))
                    if clearance<=Rules.MIN_FOLLOW_GAP then yieldOnNarrowRoad=true;return false end
                elseif alignment>.65 and forward>0 and math.abs(lateral)<sameLaneTolerance then
                    local clearance=forward-ownHalfLength-projectedLength
                    desired=math.min(desired,followingSpeedLimit(vehicle,otherSpeed,
                        baseDesired,speed,clearance))
                elseif alignment<-.65 and forward>0 and segment and (segment.lanes or 1)<2
                    and not segment.oneWay
                    and math.abs(lateral)<(segment.width or 4.2)*.5+ownHalfWidth+otherHalfWidth then
                    local hasPriority=entry.isPlayer==true
                        or entry.id~=nil and vehicle.trafficId~=nil
                            and tostring(entry.id)<tostring(vehicle.trafficId)
                    if hasPriority then yieldOnNarrowRoad=true;return false end
                end
            end
        end
    end
    if actorIndex then
        actorIndex:forEachCircle(vehicle.x,vehicle.z,Rules.INTERACTION_RADIUS,
            function(entry,_,other)return consider(entry,other) end)
    else
        for _,entry in ipairs(actors or {}) do
            if consider(entry)==false then break end
        end
    end
    if yieldOnNarrowRoad then return 0,true end
    return desired,false
end

return Rules
