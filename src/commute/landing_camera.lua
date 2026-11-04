-- Predict a landing from actual travel, independently of the chassis attitude.
-- This is a camera hint only; it never changes the motorcycle or terrain.
local M=require('src.commute.vendor.mathx')
local Landing={MAX_TIME=3,STEP=.12,GRAVITY=9.81}
function Landing.target(world,actor,visual)
    visual=visual or actor
    local grounded=visual.grounded
    if grounded==nil then grounded=actor.grounded end
    if grounded~=false then return nil end
    local height=M.finite(visual.h) and visual.h or actor.h
    if not M.finite(height) then return nil end
    local speed=visual.speed or actor.speed or 0
    local sign=actor.reverse and -1 or 1
    local vx=M.finite(visual.vx) and visual.vx or actor.vx
    local vz=M.finite(visual.vz) and visual.vz or actor.vz
    if not M.finite(vx) then vx=math.cos(actor.heading or 0)*speed*sign end
    if not M.finite(vz) then vz=math.sin(actor.heading or 0)*speed*sign end
    -- Older network snapshots carry scalar speed but no horizontal velocity.
    if vx*vx+vz*vz<.0001 and speed>.1 then
        vx=math.cos(actor.heading or 0)*speed*sign
        vz=math.sin(actor.heading or 0)*speed*sign
    end
    local vy=M.finite(visual.vy) and visual.vy or actor.vy or 0
    local support=world.supportHeight or world.height
    local function sample(t)
        local x,z=actor.x+vx*t,actor.z+vz*t
        local bounds=world.bounds
        if bounds then
            x=M.clamp(x,bounds.minX or 0,bounds.maxX or world.size or 512)
            z=M.clamp(z,bounds.minZ or 0,bounds.maxZ or world.size or 512)
        elseif world.size then x=M.clamp(x,0,world.size);z=M.clamp(z,0,world.size) end
        return x,z,support(world,x,z)
    end
    local previous=0
    for step=1,math.ceil(Landing.MAX_TIME/Landing.STEP) do
        local t=step*Landing.STEP
        local x,z,ground=sample(t)
        if vy-Landing.GRAVITY*t<0 and height+vy*t-.5*Landing.GRAVITY*t*t<=ground then
            local lo,hi=previous,t
            for _=1,5 do
                local mid=(lo+hi)*.5
                local _,_,h=sample(mid)
                if height+vy*mid-.5*Landing.GRAVITY*mid*mid>h then lo=mid else hi=mid end
            end
            x,z,ground=sample((lo+hi)*.5)
            return {x=x,z=z,h=ground,time=(lo+hi)*.5}
        end
        previous=t
    end
    local x,z,ground=sample(Landing.MAX_TIME)
    return {x=x,z=z,h=ground,time=Landing.MAX_TIME}
end
return Landing
