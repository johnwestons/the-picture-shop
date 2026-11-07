local Pages=require('src.commute.truck_turntable_pages')
local KeiPages=require('src.commute.kei_turntable_pages')
local Decals=require('src.commute.truck_decals')
local Footprint=require('src.commute.truck_footprint')
local Camera=require('src.commute.camera')
local MODEL_ART_SCALE={kei=.67}
local Art={}
Art.__index=Art

local function relativeAngle(camera,heading)
    if camera.firstPerson then return heading-camera.viewHeading end
    return heading+math.rad(camera.yaw or 0)+math.pi*.5
end

function Art.frame(camera,heading,model)
    local angle=relativeAngle(camera,heading)
    -- Each vehicle owns its view calibration so a frame-order adjustment to
    -- the kei sheets cannot silently leave them using the box atlas indexer.
    if model=='kei' then return KeiPages.frame(angle) end
    return Pages.frame(angle)
end

-- The truck sprite spans its full chassis around the road anchor. Bias its
-- shared billboard depth to the nearest wheel-contact edge so terrain depth
-- does not cut off the lower tires as it does with an anchor-only depth.
function Art:groundedDepthBias(actor,camera,height,world)
    local dims=Footprint.dimensions(actor)
    local heading=actor.heading or 0
    local fx,fz=math.cos(heading),math.sin(heading)
    local sx,sz=-fz,fx
    local center=camera:depth(actor.x,actor.z,height)
    local nearest=center
    for _,along in ipairs({-dims.halfLength,dims.halfLength}) do
        for _,side in ipairs({-dims.halfWidth,dims.halfWidth}) do
            local x=actor.x+fx*along+sx*side
            local z=actor.z+fz*along+sz*side
            local ground=world and world.supportHeight and world:supportHeight(x,z) or height
            nearest=math.max(nearest,camera:depth(x,z,ground))
        end
    end
    local groundScale=math.max(.01,camera:groundScale())
    return math.max(0,nearest-center)/(29*groundScale)
end

-- Perspective billboards also use one depth value for the whole sprite. Move
-- their depth test to the nearest ground point under the truck without moving
-- the sprite itself on screen, so the road cannot crop its near-side tires.
function Art:firstPersonOcclusionTop(actor,camera,height,world)
    local dims=Footprint.dimensions(actor)
    local _,_,centerDepth=camera:screen(actor.x,actor.z,height)
    local eyeHeight=camera.eyeHeight
    if type(centerDepth)~='number' or centerDepth<=.15 or type(eyeHeight)~='number'
        or eyeHeight<=height+.05 then return height end
    local nearest=centerDepth
    local heading=actor.heading or 0
    local fx,fz=math.cos(heading),math.sin(heading)
    local sx,sz=-fz,fx
    for _,along in ipairs({-dims.halfLength,dims.halfLength}) do
        for _,side in ipairs({-dims.halfWidth,dims.halfWidth}) do
            local x=actor.x+fx*along+sx*side
            local z=actor.z+fz*along+sz*side
            local ground=world and world.supportHeight and world:supportHeight(x,z) or height
            local _,_,depth=camera:screen(x,z,ground)
            if type(depth)=='number' and depth>.15 then nearest=math.min(nearest,depth) end
        end
    end
    return math.max(height,eyeHeight-nearest*(eyeHeight-height)/centerDepth)
end

local function elevation(camera,actor,h)
    local eye=camera.projectionCamera
    if not eye then return camera.tilt or 55 end
    local dx,dz=actor.x-eye.centerX,actor.z-eye.centerZ
    return math.deg(math.atan2(eye.eyeHeight-h-1.35,math.sqrt(dx*dx+dz*dz)))
end

local function isNearby(camera,actor)
    local focus=camera.lastActor
    if not focus or focus==actor or type(camera.centerX)~='number' or type(camera.centerZ)~='number' then
        return false
    end
    -- A camera following the truck itself is still an orbit view. This
    -- exception is for another vehicle the player has walked up to.
    if type(focus.x)=='number' and type(focus.z)=='number'
        and (focus.x-actor.x)^2+(focus.z-actor.z)^2<.01 then return false end
    local dx,dz=actor.x-camera.centerX,actor.z-camera.centerZ
    return dx*dx+dz*dz<=(Footprint.dimensions(actor).radius+1)^2
end

function Art.viewKind(camera,actor,h)
    camera=camera or {}
    if camera.localTruckChase or camera.outsideMode=='shoulder' or camera.shoulderView then
        return 'chase'
    end
    local eye=camera.projectionCamera
    if eye then
        if not eye.includeLocalRider or eye.shoulderPerspective then return 'chase' end
        return elevation(camera,actor,h)<31 and 'chase' or 'isometric'
    end
    if isNearby(camera,actor) then return 'chase' end
    -- In free orbit, the low-angle art is only appropriate at the camera's
    -- lowest reachable tilt. Keep the top-down set through the rest of the
    -- orbit; perspective close/shoulder views keep their own angle test above.
    return (camera.tilt or Camera.TILT_DEFAULT)<=Camera.TILT_MIN and 'chase' or 'isometric'
end

function Art.new()
    return setmetatable({pages=Pages.new(),keiPages=KeiPages.new(),decals=Decals.new()},Art)
end

function Art:draw(actor,camera,world,silhouetteMode)
    local h=actor.h or world:supportHeight(actor.x,actor.z)
    local x,y=camera:screen(actor.x,actor.z,h)
    local kind=Art.viewKind(camera,actor,h)
    local frame=Art.frame(camera,actor.heading or 0,actor.model)
    local pages=actor.model=='kei' and self.keiPages or self.pages
    local image,quad,format=pages:get(kind,frame)
    local scale=format.scale*camera.zoom*(MODEL_ART_SCALE[actor.model] or 1)
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,quad,x,y,0,scale,scale,format.anchorX,format.anchorY)
    if not silhouetteMode and actor.model~='kei' then
        local decal=self.decals:companyImage(actor.company)
            or self.decals.images[actor.livery or 'picture_shop']
        self.decals:drawTurntable(decal,
            kind,frame,x,y,scale,format)
    end
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
    local dims=Footprint.dimensions(actor)
    for _,forward in ipairs({-dims.halfLength*.72,dims.halfLength*.72}) do
        local x=actor.x+fx*forward+sx*side*dims.halfWidth*.72
        local z=actor.z+fz*forward+sz*side*dims.halfWidth*.72
        local h=baseHeight+dims.height*.32
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
    self.keiPages:release()
    self.decals:release()
end

return Art
