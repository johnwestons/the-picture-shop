-- Exact critically damped spring: continuous velocity when the target changes,
-- with the same response at different frame rates for a held target.
local D={}
function D.spring(value,target,velocity,smoothTime,dt)
    if dt<=0 then return value,velocity or 0 end
    local omega=2/math.max(.001,smoothTime)
    local offset=value-target
    local travel=(velocity or 0)+omega*offset
    local decay=math.exp(-omega*dt)
    return target+(offset+travel*dt)*decay,((velocity or 0)-omega*travel*dt)*decay
end
function D.angle(value,target,velocity,smoothTime,dt)
    local delta=(target-value+math.pi)%(2*math.pi)-math.pi
    return D.spring(value,value+delta,velocity,smoothTime,dt)
end
return D
