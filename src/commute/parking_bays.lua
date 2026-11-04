-- One lot layout in world metres for paint, motorcycle spawn and arrival.
-- The drive enters from the positive front axis; stalls face the building.
local Bays={COUNT=4,WIDTH=1.75,HALF_WIDTH=3.5,REAR=-2.55,OPEN=1.85,BIKE_FORWARD=-.2}

function Bays.point(site,side,forward)
    local pad=site.parking
    return pad.x+site.cos*side+site.front.x*forward,
        pad.z+site.sin*side+site.front.z*forward
end

function Bays.side(slot)
    return -Bays.HALF_WIDTH+(slot-.5)*Bays.WIDTH
end

function Bays.center(site,slot,forward)
    return Bays.point(site,Bays.side(slot),forward or Bays.BIKE_FORWARD)
end

function Bays.slotAt(site,x,z)
    local dx,dz=x-site.parking.x,z-site.parking.z
    local side=dx*site.cos+dz*site.sin
    local forward=dx*site.front.x+dz*site.front.z
    if side<=-Bays.HALF_WIDTH+.12 or side>=Bays.HALF_WIDTH-.12
        or forward<Bays.REAR+.35 or forward>Bays.OPEN+.15 then return nil end
    -- Let the bike stop on a divider without demanding pixel-perfect steering.
    return math.min(Bays.COUNT,math.floor((side+Bays.HALF_WIDTH)/Bays.WIDTH)+1)
end

return Bays
