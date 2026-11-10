-- Transient vehicle presentation travels with the driver's realtime pose.
-- Ownership, cargo, fuel and collisions remain in the authoritative trip.
local Motion={}
local fields={'heading','speed','steer','brake','throttle','h','pitch'}

function Motion.snapshot(part,token)
    local rider=part and part.rider
    local truck=rider and rider.vehicle=='truck' and rider.truck
    if not truck or part.interior or part.arrived then return nil end
    return {token=token,model=truck.model or 'box',heading=truck.heading,speed=truck.speed or 0,
        steer=truck.steering or 0,brake=truck.brake or 0,throttle=truck.throttle or 0,
        reverse=truck.reverse==true,h=truck.h or 0,pitch=truck.pitch or 0}
end

function Motion.update(player,dt)
    local target=player._truckMotion
    if not target or not player._targetRecord or player._targetRecord.sceneId~='commute' then
        player._visualTruckMotion=nil
        return
    end
    local visual=player._visualTruckMotion
    if not visual or visual.token~=target.token or visual.model~=target.model then
        visual={}
        for key,value in pairs(target) do visual[key]=value end
        player._visualTruckMotion=visual
        return
    end
    local alpha=1-math.exp(-20*math.max(0,dt))
    for _,key in ipairs(fields) do
        local delta=target[key]-visual[key]
        if key=='heading' then delta=math.atan2(math.sin(delta),math.cos(delta)) end
        visual[key]=visual[key]+delta*alpha
    end
    visual.reverse=target.reverse
end

function Motion.apply(truck,player,token)
    local motion=player._visualTruckMotion
    if not motion or motion.token~=token or motion.model~=(truck.model or 'box') then return false end
    for _,key in ipairs(fields) do
        if key~='steer' then truck[key]=motion[key] end
    end
    truck.steering=motion.steer
    truck.reverse=motion.reverse
    return true
end

return Motion
