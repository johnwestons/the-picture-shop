-- Damage is stored in whole percentage points. Impact speed is the velocity
-- lost into the obstacle's surface, measured in world metres per second.
local M = require('src.commute.vendor.mathx')
local Damage = {MAX=100, LIMP_SPEED=2.2352, SAFE_SPEED=3, EJECTION_SPEED=11.5}

function Damage.valid(value)
    return value == nil or M.finite(value) and value % 1 == 0 and value >= 0 and value <= Damage.MAX
end

function Damage.speedLimit(healthyLimit, damage)
    return M.lerp(healthyLimit, Damage.LIMP_SPEED, (damage or 0) / Damage.MAX)
end

function Damage.impact(bike, speed, nx, nz, vx, vz, kind)
    local excess = math.max(speed - Damage.SAFE_SPEED, 0)
    local points = math.floor(excess * (.6 + .42 * excess) + .5)
    bike.damage = math.min(Damage.MAX, (bike.damage or 0) + points)
    if speed >= Damage.EJECTION_SPEED then
        local travelSpeed = M.length(vx, vz)
        bike.crashPending = {
            dx=vx / travelSpeed, dz=vz / travelSpeed, speed=speed, nx=nx, nz=nz,
            severity=M.clamp(speed / 20, 0, 1), kind=kind
        }
    end
end

return Damage
