-- Clock-derived pedestrian and vehicle phases for NPC commutes. Walking uses
-- the character's authored walk sheets; boarding and leaving use its idle pose.
local Bays=require('src.commute.parking_bays')
local Driving=require('src.commute.scheduled_driving')
local Journey={WALK_HOURS=.04,BOARD_HOURS=.015,WALK_SPEED=1.3}

local function clamp(value,low,high)return math.max(low,math.min(high,value))end
local function lerp(a,b,t)return a+(b-a)*t end
local function point(site,anchor)
    if not site or not anchor then return nil end
    return {x=anchor.x,z=anchor.z}
end
local function parkedPoint(site,slot)
    if not site then return nil end
    local x,z=Bays.center(site,slot)
    return {x=x,z=z}
end
local function stepAside(bay,site)
    if not bay or not site then return bay end
    local layout=site.employeeParking
    if layout and layout.walkSide then
        return {x=bay.x+site.cos*layout.walkSide*.72,
            z=bay.z+site.sin*layout.walkSide*.72}
    end
    local heading=site.yaw or 0
    return {x=bay.x-math.sin(heading)*.72,z=bay.z+math.cos(heading)*.72}
end
local function face(a,b,fallback)
    if not a or not b then return fallback or 0 end
    local dx,dz=b.x-a.x,b.z-a.z
    if dx*dx+dz*dz<1e-8 then return fallback or 0 end
    return math.atan2(dz,dx)
end
local function walker(world,from,to,progress,walking,distance,headingFallback)
    if not from or not to then return nil end
    progress=clamp(progress,0,1)
    local x,z=lerp(from.x,to.x,progress),lerp(from.z,to.z,progress)
    return {x=x,z=z,h=world:supportHeight(x,z),heading=face(from,to,headingFallback),
        speed=walking and Journey.WALK_SPEED or 0,
        distance=walking and distance*progress or 0,
        moving=walking==true}
end

-- Returns the motorcycle pose and, during the short access stages, an authored
-- character actor. A missing site means the endpoint is off-map (for example,
-- an employee commuting from the city), so no fake doorstep is introduced.
function Journey.sample(journey,hours,world,route,fromSlot,toSlot)
    if type(journey)~='table' or not world or not route then return nil end
    local duration=journey.arriveAtHours-journey.departAtHours
    if duration<=0 then return nil end
    local sites=world.sites and world.sites.byId or {}
    local origin=sites[journey.fromId]
    local destination=sites[journey.toId]
    local originBay=parkedPoint(origin,fromSlot)
    local destinationBay=parkedPoint(destination,toSlot)
    local originFoot=stepAside(originBay,origin)
    local destinationFoot=stepAside(destinationBay,destination)
    local originDoor=origin and point(origin,origin.door)
    local destinationDoor=destination and point(destination,destination.door)
    local outWalk=origin and math.min(Journey.WALK_HOURS,duration*.1) or 0
    local board=origin and math.min(Journey.BOARD_HOURS,duration*.05) or 0
    local leave=destination and math.min(Journey.BOARD_HOURS,duration*.05) or 0
    local inWalk=destination and math.min(Journey.WALK_HOURS,duration*.1) or 0
    local transition=outWalk+board+leave+inWalk
    if transition>=duration then
        local factor=duration*.5/math.max(transition,1e-8)
        outWalk,board,leave,inWalk=outWalk*factor,board*factor,leave*factor,inWalk*factor
    end
    local elapsed=clamp(hours-journey.departAtHours,0,duration)
    local rideStart=outWalk+board
    local rideEnd=duration-leave-inWalk
    local stage,walkActor,bikePose
    if outWalk>0 and elapsed<outWalk then
        stage='walk_to_vehicle'
        walkActor=walker(world,originDoor,originFoot,elapsed/outWalk,true,
            math.sqrt((originFoot.x-originDoor.x)^2+(originFoot.z-originDoor.z)^2),origin.yaw)
        bikePose={x=originBay.x,z=originBay.z,heading=Bays.heading(origin),parked=true,progress=0}
    elseif board>0 and elapsed<rideStart then
        stage='mounting'
        walkActor=walker(world,originFoot,originFoot,0,false,0,origin.yaw)
        bikePose={x=originBay.x,z=originBay.z,heading=Bays.heading(origin),parked=true,progress=0}
    elseif elapsed<rideEnd then
        stage='riding'
        local progress=clamp((elapsed-rideStart)/math.max(rideEnd-rideStart,1e-8),0,1)
        bikePose=Driving.sample(route,progress,world)
        if not bikePose then return nil end
        bikePose.parked=false
    elseif leave>0 and elapsed<rideEnd+leave then
        stage='dismounting'
        walkActor=walker(world,destinationFoot,destinationFoot,0,false,0,destination.yaw)
        bikePose={x=destinationBay.x,z=destinationBay.z,heading=Bays.heading(destination),
            parked=true,progress=1}
    elseif inWalk>0 then
        stage='walk_to_destination'
        local progress=clamp((elapsed-rideEnd-leave)/math.max(inWalk,1e-8),0,1)
        walkActor=walker(world,destinationFoot,destinationDoor,progress,true,
            math.sqrt((destinationDoor.x-destinationFoot.x)^2+(destinationDoor.z-destinationFoot.z)^2),destination.yaw)
        bikePose={x=destinationBay.x,z=destinationBay.z,heading=Bays.heading(destination),
            parked=true,progress=1}
    else
        stage='riding'
        bikePose=Driving.sample(route,1,world)
        if not bikePose then return nil end
        bikePose.parked=false;bikePose.progress=1
    end
    if walkActor then
        walkActor.h=world:supportHeight(walkActor.x,walkActor.z)
        if stage=='walk_to_destination' then
            walkActor.distance=(math.sqrt((destinationDoor.x-destinationFoot.x)^2
                +(destinationDoor.z-destinationFoot.z)^2))
                *clamp((elapsed-rideEnd-leave)/math.max(inWalk,1e-8),0,1)
        elseif stage=='walk_to_vehicle' then
            walkActor.distance=(math.sqrt((originFoot.x-originDoor.x)^2
                +(originFoot.z-originDoor.z)^2))*clamp(elapsed/math.max(outWalk,1e-8),0,1)
        end
    end
    return {stage=stage,bike=bikePose,walker=walkActor}
end

return Journey
