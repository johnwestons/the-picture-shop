-- Distance, not wall-clock time, advances rubber highlights. Stopped and
-- parked sprites retain their exact authored pixels in every camera mode.
local Regions=require('assets.commute.bike.wheel_regions')
local M=require('src.commute.vendor.mathx')
local Tire={CIRCUMFERENCE=2.05,STOP_SPEED=.06}
local tau=math.pi*2
local function value(actor,visual,key)
    if visual and visual[key]~=nil then return visual[key] end
    return actor and actor[key]
end
function Tire.sample(actor,visual,pose,frame)
    if not actor or pose=='parked' then return nil end
    local speed=math.abs(value(actor,visual,'speed') or 0)
    if speed<=Tire.STOP_SPEED then return nil end
    local rows=Regions[pose=='mounted' and 'upright' or pose]
    local row=rows and rows[frame]
    if not row then return nil end
    local distance=value(actor,visual,'distance') or 0
    local reverse=value(actor,visual,'reverse')==true
    local phase=(distance%Tire.CIRCUMFERENCE)/Tire.CIRCUMFERENCE*tau*(reverse and -1 or 1)
    local angle=(frame-1)*tau/64
    return {wheel1={row[1],row[2],row[3],row[4]},wheel2={row[5],row[6],row[7],row[8]},
        motion={phase,M.smooth((speed-Tire.STOP_SPEED)/.8),math.sin(angle),math.cos(angle)}}
end
return Tire
