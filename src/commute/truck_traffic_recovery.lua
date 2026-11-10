-- Last resort for stationary AI traffic. Move backwards along the current
-- route, never past a delivery stop, and keep the full truck footprint clear.
local Truck=require('src.commute.delivery_truck')
local Path=require('src.commute.driving_path')
local Rules=require('src.commute.traffic_rules')
local Footprint=require('src.commute.truck_footprint')
local Recovery={}

local function trafficClear(vehicle,x,z,heading,world)
    for _,entry in ipairs(world.trafficActors or {}) do
        local other=entry.actor or entry
        if other~=vehicle and other.x and other.z then
            if entry.kind=='vehicle' then
                if Footprint.overlapsTruck(x,z,heading,other.x,other.z,other.heading or 0,
                    vehicle.model,other.model) then return false end
            else
                local dims=Rules.dimensions(other)
                local radius=entry.radius or dims.radius
                if Footprint.overlaps(x,z,math.cos(heading),math.sin(heading),
                    other.x,other.z,other.x,other.z,radius,Footprint.dimensions(vehicle)) then return false end
            end
        end
    end
    return true
end

function Recovery.rescue(vehicle,points,world)
    local length=Path.length(points)
    if length<=0 then return false,'No road route available for recovery' end
    -- The driver may have replanned from its current position after backing
    -- up. Project onto the retained route instead of using that new index.
    local station,best=0,math.huge
    for index=2,#points do
        local a,b=points[index-1],points[index]
        local dx,dz=b.x-a.x,b.z-a.z
        local segment=math.sqrt(dx*dx+dz*dz)
        local along=segment>0 and math.max(0,math.min(segment,
            ((vehicle.x-a.x)*dx+(vehicle.z-a.z)*dz)/segment)) or 0
        local blend=segment>0 and along/segment or 0
        local distance=(vehicle.x-a.x-dx*blend)^2+(vehicle.z-a.z-dz*blend)^2
        if distance<best then best,station=distance,Path.station(points,index-1)+along end
    end
    for _,back in ipairs({8,12,20,32,48,64,80}) do
        local distance=station-back
        if distance>=Footprint.dimensions(vehicle).halfLength+1 then
            local sample=Path.sample(points,length,distance/length)
            local _,road=world.roads:nearest(sample.x,sample.z,true)
            local offset=Rules.laneOffset(road,Rules.drivingSide(world.town),false,vehicle)
            local x,z=Rules.lanePoint(sample,sample.heading,offset)
            if trafficClear(vehicle,x,z,sample.heading,world)
                and not Truck.blocked(world,x,z,sample.heading,vehicle) then
                vehicle.x,vehicle.z,vehicle.heading=x,z,sample.heading
                vehicle.h=world:supportHeight(x,z)
                vehicle.speed,vehicle.throttle,vehicle.brake,vehicle.steering=0,0,0,0
                vehicle.slipAngle,vehicle.pitch,vehicle.acceleration=0,0,0
                vehicle.reverse=false;vehicle.collisionContact=false;vehicle.collisionStun=0
                vehicle.pathIndex=sample.pathIndex
                return true
            end
        end
    end
    return false,'No clear road position behind this truck; retrying without skipping the route'
end

return Recovery
