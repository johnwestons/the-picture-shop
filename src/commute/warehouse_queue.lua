-- One ordered receiving queue shared by freight and customer pickup trucks.
local Path=require('src.commute.driving_path')
local Footprint=require('src.commute.truck_footprint')
local Queue={SPACING=9}
local overflow=setmetatable({}, {__mode='k'})
local function tailStation(route)
    local site=route.world.sites.byId.warehouse
    local anchors=site.truckQueueAnchors or {}
    local tail=anchors[#anchors] or site.localTruckWaiting or site.design.truckWaiting
    local tx,tz=site:toWorld(tail.x,tail.z,0)
    local station,best=0,math.huge
    for i=2,#route.inward do
        local at=Path.progress(route.inward,i,tx,tz)
        local p=Path.sample(route.inward,route.length,at/route.length)
        local distance=(p.x-tx)^2+(p.z-tz)^2
        if distance<best then station,best=at,distance end
    end
    return station
end
local function anchorFor(route,slot,lanePosition)
    local site=route.world.sites.byId.warehouse
    local anchors=site.truckQueueAnchors or {}
    if anchors[slot] then return anchors[slot] end
    local cached=overflow[route]
    if not cached then cached={};overflow[route]=cached end
    if cached[slot] then return cached[slot] end
    -- Queue beyond the painted apron by extending the same route toward the
    -- road gate. Never clamp overflow slots onto one point: that stacks every
    -- later truck on top of the last valid parking position.
    local station=tailStation(route)-(slot-#anchors)*Queue.SPACING
    local minimumStation=Footprint.halfLength+1
    if station<minimumStation then return nil end
    local p=Path.sample(route.inward,route.length,station/route.length)
    if not p then return nil end
    local lane=lanePosition({},route.inward,p,route.world)
    local points={}
    -- A queue on the approach stays in its own lane at the final stop.
    for i=1,p.pathIndex-1 do
        local original=route.inward[i]
        local blend=math.max(0,1-(station-Path.station(route.inward,i))/12)
        points[#points+1]={x=original.x+(lane.x-p.x)*blend,z=original.z+(lane.z-p.z)*blend,
            h=original.h,speedLimit=original.speedLimit,turnAngle=original.turnAngle}
    end
    points[#points+1]={x=lane.x,z=lane.z,h=p.h}
    local x,z=site:toLocal(lane.x,lane.z)
    local anchor={x=x,z=z,heading=p.heading,points=points,station=station}
    cached[slot]=anchor;return anchor
end
function Queue.capacity(route)
    local site=route and route.world and route.world.sites and route.world.sites.byId.warehouse
    local anchors=site and site.truckQueueAnchors or {}
    if not site or not route.inward or #route.inward<2 or not route.length or route.length<=0 then
        return #anchors
    end
    local station=tailStation(route)
    local minimumStation=Footprint.halfLength+1
    return #anchors+math.max(0,math.floor((station-minimumStation)/Queue.SPACING))
end
function Queue.plan(entries,route,externalBlocked,epoch,lanePosition)
    local waiting={}
    for _,entry in ipairs(entries) do
        local delivery=entry.delivery
        local record=delivery and delivery.route
        if record and not record.transportId and delivery.status~='received'
            and type(record.departedAtEpoch)=='number' and record.departedAtEpoch<=epoch
            and not (record.vehicle and record.vehicle.phase=='offmap') then
            waiting[#waiting+1]=entry
        end
    end
    table.sort(waiting,function(a,b)
        local ar,br=a.delivery.route,b.delivery.route
        local av,bv=ar.vehicle,br.vehicle
        local ac=av and (av.phase=='at_bay' or av.pathTarget=='dock') or false
        local bc=bv and (bv.phase=='at_bay' or bv.pathTarget=='dock') or false
        if ac~=bc then return ac end
        if ar.departedAtEpoch~=br.departedAtEpoch then return ar.departedAtEpoch<br.departedAtEpoch end
        return a.id<b.id
    end)
    local result={}
    for rank,entry in ipairs(waiting) do
        local slot=rank-(externalBlocked and 0 or 1)
        if slot==0 then
            result[entry.delivery.route]={target='dock',anchor=route.world.sites.byId.warehouse.design.truckParking}
        else
            result[entry.delivery.route]={target='waiting-'..slot,
                anchor=anchorFor(route,slot,lanePosition),slot=slot,capacity=Queue.capacity(route)}
        end
    end
    return result
end
return Queue
