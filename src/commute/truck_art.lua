local Pages=require('src.commute.truck_turntable_pages')
local Decals=require('src.commute.truck_decals')
local Art={}
Art.__index=Art

local function relativeAngle(camera,heading)
    if camera.firstPerson then return heading-camera.viewHeading end
    return heading+math.rad(camera.yaw or 0)+math.pi*.5
end

function Art.frame(camera,heading)
    return Pages.frame(relativeAngle(camera,heading))
end

local function elevation(camera,actor,h)
    local eye=camera.projectionCamera
    if not eye then return camera.tilt or 55 end
    local dx,dz=actor.x-eye.centerX,actor.z-eye.centerZ
    return math.deg(math.atan2(eye.eyeHeight-h-1.35,math.sqrt(dx*dx+dz*dz)))
end

function Art.new()
    return setmetatable({pages=Pages.new(),decals=Decals.new()},Art)
end

function Art:draw(actor,camera,world)
    local h=actor.h or world:supportHeight(actor.x,actor.z)
    local x,y=camera:screen(actor.x,actor.z,h)
    local eye=camera.projectionCamera
    local kind=(camera.localTruckChase or (eye and not eye.includeLocalRider) or elevation(camera,actor,h)<31)
        and 'chase' or 'isometric'
    local frame=Art.frame(camera,actor.heading or 0)
    local image,quad,format=self.pages:get(kind,frame)
    local scale=format.scale*camera.zoom
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,quad,x,y,0,scale,scale,format.anchorX,format.anchorY)
    local decal=self.decals:companyImage(actor.company)
        or self.decals.images[actor.livery or 'picture_shop']
    self.decals:drawTurntable(decal,
        kind,frame,x,y,scale,format)
end

function Art:drawSignals(actor,camera,world,clock)
    if actor.turnSignal~='left' and actor.turnSignal~='right' then return end
    if math.floor((clock or 0)*2.4)%2~=0 then return end
    local g=love.graphics;local heading=actor.heading or 0
    local fx,fz=math.cos(heading),math.sin(heading)
    local sx,sz=-fz,fx
    local side=actor.turnSignal=='left' and -1 or 1
    local eye=camera.projectionCamera
    local baseHeight=actor.h or world:supportHeight(actor.x,actor.z)
    local centerX,centerY
    if eye then centerX,centerY=eye:screen(actor.x,actor.z,baseHeight) end
    for _,forward in ipairs({-1.45,1.35}) do
        local x=actor.x+fx*forward+sx*side*.72
        local z=actor.z+fz*forward+sz*side*.72
        local h=baseHeight+.92
        local px,py=(eye or camera):screen(x,z,h)
        if eye then
            local dx,dy=px-centerX,py-centerY
            local c,s=math.cos(eye.roll),math.sin(eye.roll)
            px,py=dx*c+dy*s,-dx*s+dy*c
        end
        local radius=math.max(2,3.5*camera.zoom)
        g.setColor(.16,.08,.015,.9);g.circle('fill',px,py,radius+1.4*camera.zoom)
        g.setColor(1,.61,.12,.98);g.circle('fill',px,py,radius)
    end
    g.setColor(1,1,1,1)
end

function Art:release()
    self.pages:release()
    self.decals:release()
end

return Art
