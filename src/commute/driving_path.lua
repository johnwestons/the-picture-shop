-- Shared geometry for autonomous vehicle route following. Route point arrays
-- are immutable after construction, so their measurements can be reused by
-- every driver that follows the same route.
local Path={}
local cache=setmetatable({}, {__mode='k'})

local function wrap(angle)
    return math.atan2(math.sin(angle),math.cos(angle))
end

function Path.turnSpeed(angle)
    angle=math.abs(angle)
    if angle<.22 then return 8.6 end
    if angle<.42 then return 7.1 end
    if angle<.70 then return 5.8 end
    if angle<1.05 then return 4.5 end
    if angle<1.55 then return 3.4 end
    return 2.7
end

local function distance(a,b)
    local dx,dz=b.x-a.x,b.z-a.z
    return math.sqrt(dx*dx+dz*dz)
end

local function metrics(points)
    local saved=cache[points]
    if saved then return saved end
    local count=#points
    local segments,cumulative,suffix={},{[1]=0},{}
    local total=0
    for index=2,count do
        local length=distance(points[index-1],points[index])
        segments[index]=length
        total=total+length
        cumulative[index]=total
    end
    suffix[count]=0
    for index=count,2,-1 do suffix[index]=segments[index]+(suffix[index+1] or 0) end
    local speedLimits={}
    local hasAuthoredSpeedLimit=false
    local hasTurnGuidance=false
    for index=2,count do
        if points[index].speedLimit~=nil or points[index].turnAngle~=nil then
            hasTurnGuidance=true
        end
        if points[index].speedLimit~=nil then hasAuthoredSpeedLimit=true end
    end
    for index=2,count do
        local speed=points[index].speedLimit
        if speed==nil and not hasAuthoredSpeedLimit and index<count then
            local before,at,after=points[index-1],points[index],points[index+1]
            local incoming=math.atan2(at.z-before.z,at.x-before.x)
            local outgoing=math.atan2(after.z-at.z,after.x-at.x)
            local angle=wrap(outgoing-incoming)
            if math.abs(angle)>=.22 then speed=Path.turnSpeed(angle) end
        end
        if speed then
            speedLimits[#speedLimits+1]={index=index,
                distanceBefore=cumulative[index-1] or 0,speed=speed}
        end
    end
    saved={total=total,segments=segments,cumulative=cumulative,suffix=suffix,
        speedLimits=speedLimits,hasTurnGuidance=hasTurnGuidance}
    cache[points]=saved
    return saved
end

function Path.length(points)
    if type(points)~='table' or #points<2 then return 0 end
    return metrics(points).total
end

function Path.sample(points,length,progress)
    if type(points)~='table' or #points<2 then return nil end
    local data=metrics(points)
    local total=type(length)=='number' and length or data.total
    local wanted=math.max(0,math.min(1,progress or 0))*total
    local lo,hi=2,#points
    while lo<hi do
        local mid=math.floor((lo+hi)*.5)
        if (data.cumulative[mid] or data.total)>=wanted then hi=mid else lo=mid+1 end
    end
    local index=lo
    local before,at=points[index-1],points[index]
    local segment=data.segments[index] or 0
    local walked=data.cumulative[index-1] or 0
    local blend=segment>1e-8 and math.max(0,math.min(1,(wanted-walked)/segment)) or 1
    local beforeH,atH=before.h or at.h or 0,at.h or before.h or 0
    return {x=before.x+(at.x-before.x)*blend,z=before.z+(at.z-before.z)*blend,
        h=beforeH+(atH-beforeH)*blend,heading=math.atan2(at.z-before.z,at.x-before.x),
        pathIndex=index}
end

function Path.lookAhead(points,x,z,startIndex,wantedDistance,projectToRoute)
    if type(points)~='table' or #points<2 then return nil end
    local data=metrics(points)
    local first=math.max(2,math.min(#points,startIndex or 2))
    local before,at=points[first-1],points[first]
    local ax,az=x,z
    if projectToRoute then
        local dx,dz=at.x-before.x,at.z-before.z
        local length2=dx*dx+dz*dz
        local blend=length2>1e-8 and math.max(0,math.min(1,
            ((x-before.x)*dx+(z-before.z)*dz)/length2)) or 1
        ax,az=before.x+dx*blend,before.z+dz*blend
    end
    local remaining=math.max(0,wantedDistance or 0)
    for index=first,#points do
        local at=points[index]
        local dx,dz=at.x-ax,at.z-az
        local segment=index==first and math.sqrt(dx*dx+dz*dz) or data.segments[index]
        if segment>1e-7 and remaining<=segment then
            local blend=remaining/segment
            return {x=ax+dx*blend,z=az+dz*blend},math.atan2(dz,dx)
        end
        remaining=remaining-(segment>1e-7 and segment or 0)
        ax,az=at.x,at.z
    end
    local before,last=points[#points-1],points[#points]
    return last,math.atan2(last.z-before.z,last.x-before.x)
end

function Path.remaining(points,index,x,z)
    if type(points)~='table' or #points<2 then return 0,0 end
    local data=metrics(points)
    index=math.max(2,math.min(#points,index or 2))
    local waypoint=points[index]
    local dx,dz=waypoint.x-x,waypoint.z-z
    local waypointDistance=math.sqrt(dx*dx+dz*dz)
    return waypointDistance+(data.suffix[index+1] or 0),waypointDistance
end

function Path.station(points,index)
    if type(points)~='table' or #points<2 then return 0 end
    local data=metrics(points)
    index=math.max(1,math.min(#points,math.floor(index or 1)))
    return data.cumulative[index] or data.total
end

function Path.speedLimits(points)
    if type(points)~='table' or #points<2 then return {} end
    return metrics(points).speedLimits
end

function Path.hasTurnGuidance(points)
    if type(points)~='table' or #points<2 then return false end
    return metrics(points).hasTurnGuidance
end

function Path.indexAtDistance(points,wantedDistance)
    if type(points)~='table' or #points<2 then return nil end
    local data=metrics(points)
    local wanted=math.max(0,wantedDistance or 0)
    if wanted>data.total then return #points end
    local lo,hi=2,#points
    while lo<hi do
        local mid=math.floor((lo+hi)*.5)
        if (data.cumulative[mid] or data.total)>=wanted then hi=mid else lo=mid+1 end
    end
    return lo
end

return Path
