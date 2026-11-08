-- One lot layout in world metres for paint, motorcycle spawn and arrival.
-- The drive enters from the positive front axis; stalls face the building.
local Bays={COUNT=4,WAREHOUSE_COUNT=8,WIDTH=1.75,HALF_WIDTH=3.5,REAR=-2.55,OPEN=1.85,BIKE_FORWARD=-.2}

function Bays.count(site)
    return site and site.employeeParking and site.employeeParking.count or Bays.COUNT
end

function Bays.halfWidth(site)
    return site and site.employeeParking and site.employeeParking.halfWidth
        or Bays.COUNT*Bays.WIDTH*.5
end

function Bays.anchor(site)
    if site and site.employeeParking then
        local parking=site.employeeParking
        return site:toWorld(parking.center.x,parking.center.z,0)
    end
    return site.parking.x,site.parking.z,site.parking.h
end

function Bays.point(site,side,forward,row)
    local x,z=Bays.anchor(site)
    local layout=site.employeeParking
    if layout and row then forward=forward+(layout.rowOffsets[row] or 0) end
    return x+site.cos*side+site.front.x*forward,
        z+site.sin*side+site.front.z*forward
end

function Bays.heading(site)
    local front=site and site.front
    -- Parking stalls run along the local front axis; vehicles nose toward the
    -- building, opposite the direction the driveway approaches from.
    if front then return math.atan2(-front.z,-front.x) end
    return site and site.yaw or 0
end

function Bays.slot(site,slot)
    local layout=site and site.employeeParking
    if not layout or not layout.count or layout.count<1 then return slot or 1 end
    slot=math.floor(tonumber(slot) or 1)
    return (slot-1)%layout.count+1
end

function Bays.side(slot,site)
    slot=Bays.slot(site,slot)
    local layout=site and site.employeeParking
    local columns=layout and layout.columns or Bays.COUNT
    local column=layout and (slot-1)%columns+1 or slot
    return -Bays.halfWidth(site)+(column-.5)*Bays.WIDTH
end

function Bays.center(site,slot,forward)
    slot=Bays.slot(site,slot)
    local layout=site and site.employeeParking
    if layout then
        local row=math.floor((slot-1)/layout.columns)+1
        return Bays.point(site,Bays.side(slot,site),forward or Bays.BIKE_FORWARD,row)
    end
    return Bays.point(site,Bays.side(slot,site),forward or Bays.BIKE_FORWARD)
end

function Bays.slotAt(site,x,z)
    local anchorX,anchorZ=Bays.anchor(site)
    local dx,dz=x-anchorX,z-anchorZ
    local side=dx*site.cos+dz*site.sin
    local forward=dx*site.front.x+dz*site.front.z
    local halfWidth=Bays.halfWidth(site)
    local count=Bays.count(site)
    local layout=site.employeeParking
    local row=1;local rear,open=Bays.REAR,Bays.OPEN
    if layout then
        local found
        rear,open=layout.rowRear,layout.rowOpen
        for index,offset in ipairs(layout.rowOffsets) do
            if forward>=offset+rear+.15 and forward<=offset+open-.15 then row=index;found=true;break end
        end
        if not found then return nil end
    elseif forward<Bays.REAR+.35 or forward>Bays.OPEN+.15 then return nil end
    if side<=-halfWidth+.12 or side>=halfWidth-.12 then return nil end
    -- Let the bike stop on a divider without demanding pixel-perfect steering.
    local column=math.floor((side+halfWidth)/Bays.WIDTH)+1
    return math.min(count,(layout and (row-1)*layout.columns or 0)+column)
end

return Bays
