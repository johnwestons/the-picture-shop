-- Independent screen-ray sampling for the terrain acceptance probe. It asks
-- where actual world ground should project, not which chunks the renderer
-- decided to request. Audit time is recorded separately from frame timing.
local FP=require('src.commute.first_person_camera')
local Audit={}
local function surface(world,x,z)
    local height=(world.supportHeight or world.height)(world,x,z)
    return math.max(0,height)
end
local function inside(world,x,z)
    return x>=0 and z>=0 and x<world.size and z<world.size
end
local function perspectiveHit(camera,world,sx,sy)
    local screenRight=(sx-640)/camera.focal
    local screenUp=(440-sy)/camera.focal
    local cr,sr=math.cos(camera.roll),math.sin(camera.roll)
    local right,up=screenRight*cr-screenUp*sr,screenUp*cr+screenRight*sr
    local cp,sp=math.cos(camera.viewPitch),math.sin(camera.viewPitch)
    local forward=cp-up*sp
    local dh=up*cp+sp
    local c,s=math.cos(camera.viewHeading),math.sin(camera.viewHeading)
    local dx,dz=c*forward-s*right,s*forward+c*right
    local function sample(depth)
        local x,z=camera.centerX+dx*depth,camera.centerZ+dz*depth
        if not inside(world,x,z) then return nil end
        return camera.eyeHeight+dh*depth-surface(world,x,z),x,z
    end
    local lastDepth,lastValue=FP.NEAR,sample(FP.NEAR)
    for depth=FP.NEAR+.5,FP.FAR,.5 do
        local value,x,z=sample(depth)
        if value and lastValue and lastValue>0 and value<=0 then
            local lo,hi=lastDepth,depth
            for _=1,14 do
                local mid=(lo+hi)*.5;local v=sample(mid)
                if v and v>0 then lo=mid else hi=mid end
            end
            local d=(lo+hi)*.5
            return camera.centerX+dx*d,camera.centerZ+dz*d
        end
        lastDepth,lastValue=depth,value
    end
end
function Audit.samples(camera,world,columns,rows)
    local samples={}
    for iy=0,(rows or 5)-1 do for ix=0,(columns or 7)-1 do
        local sx=24+ix*(1280-48)/((columns or 7)-1)
        local sy=24+iy*(880-48)/((rows or 5)-1)
        local x,z
        if camera.firstPerson then x,z=perspectiveHit(camera,world,sx,sy)
        else x,z=camera:screenToWorld(sx,sy) end
        if x and inside(world,x,z) then
            local px,py,depth=camera:screen(x,z,surface(world,x,z))
            -- Outside picking can clamp a ray that misses the finite world.
            -- Reprojection rejects those points instead of inventing coverage.
            if math.abs(px-sx)<2 and math.abs(py-sy)<2 and (not depth or depth<FP.FAR) then
                samples[#samples+1]={x=x,z=z,screen_x=sx,screen_y=sy}
            end
        end
    end end
    return samples
end
return Audit
