local Pages=require('src.commute.truck_turntable_pages')
local KeiPages=require('src.commute.kei_turntable_pages')
local Decals=require('src.commute.truck_decals')
local Footprint=require('src.commute.truck_footprint')
local Truck=require('src.commute.delivery_truck')
local MODEL_ART_SCALE={kei=.67}
local ISO_ART_PITCH=32
local MIN_PITCH_SCALE=.78
local Art={}
Art.__index=Art

local function relativeAngle(camera,heading)
    if camera.firstPerson then return heading-camera.viewHeading end
    return heading+math.rad(camera.yaw or 0)+math.pi*.5
end

-- Tire contact points follow each model's wheelbase and track. Body corners
-- sit well away from the tire centers and can bias the billboard under a
-- rotating camera, particularly on uneven ground.
function Art.wheelContactPoints(actor,world)
    if type(actor)~='table' then return {} end
    local profile=Truck.profile(actor)
    local dims=Footprint.dimensions(actor)
    local halfWheelbase=(profile.wheelbase or 0)*.5
    local halfTrack=dims.halfWidth*.78
    local heading=actor.heading or 0
    local fx,fz=math.cos(heading),math.sin(heading)
    local sx,sz=-fz,fx
    local result={}
    for _,along in ipairs({-halfWheelbase,halfWheelbase}) do
        for _,side in ipairs({-halfTrack,halfTrack}) do
            local x=actor.x+fx*along+sx*side
            local z=actor.z+fz*along+sz*side
            local ground=world and world.supportHeight and world:supportHeight(x,z) or actor.h or 0
            result[#result+1]={x=x,z=z,h=ground,along=along,side=side}
        end
    end
    return result
end

function Art.frame(camera,heading,model,kind)
    -- Choose art from the continuous chassis heading; frame spacing never
    -- changes the heading used for steering, travel, or camera follow.
    local angle=relativeAngle(camera,heading)
    kind=kind or Art.viewKind(camera)
    -- Each vehicle owns its view calibration so a frame-order adjustment to
    -- the kei sheets cannot silently leave them using the box atlas indexer.
    if model=='kei' then return KeiPages.frame(angle,kind) end
    return Pages.frame(angle)
end

-- The truck sprite spans its full chassis around the road anchor. Bias its
-- shared billboard depth to the nearest wheel-contact edge so terrain depth
-- does not cut off the lower tires as it does with an anchor-only depth.
function Art:groundedDepthBias(actor,camera,height,world)
    if actor and actor.grounded==false then return 0 end
    local center=camera:depth(actor.x,actor.z,height)
    local nearest=center
    for _,contact in ipairs(Art.wheelContactPoints(actor,world)) do
        nearest=math.max(nearest,camera:depth(contact.x,contact.z,contact.h))
    end
    local groundScale=math.max(.01,camera:groundScale())
    return math.max(0,nearest-center)/(29*groundScale)
end

-- Perspective billboards also use one depth value for the whole sprite. Move
-- their depth test to the nearest ground point under the truck without moving
-- the sprite itself on screen, so the road cannot crop its near-side tires.
function Art:firstPersonOcclusionTop(actor,camera,height,world)
    if actor and actor.grounded==false then return height end
    local _,_,centerDepth=camera:screen(actor.x,actor.z,height)
    local eyeHeight=camera.eyeHeight
    if type(centerDepth)~='number' or centerDepth<=.15 or type(eyeHeight)~='number'
        or eyeHeight<=height+.05 then return height end
    local nearest=centerDepth
    for _,contact in ipairs(Art.wheelContactPoints(actor,world)) do
        local _,_,depth=camera:screen(contact.x,contact.z,contact.h)
        if type(depth)=='number' and depth>.15 then nearest=math.min(nearest,depth) end
    end
    return math.max(height,eyeHeight-nearest*(eyeHeight-height)/centerDepth)
end

local function drawVehicleShadow(actor,camera,world)
    if actor.grounded==false then return end
    local projection=camera.projectionCamera or camera
    local dims=Footprint.dimensions(actor)
    local centerX,centerY=projection:screen(actor.x,actor.z,actor.h or world:supportHeight(actor.x,actor.z))
    -- This outline follows the truck's overhead silhouette: cargo body behind
    -- the narrower cab for the box truck, and the compact cab/bed for the kei.
    local outline=actor.model=='kei' and {
        {1,.70},{.91,1},{.10,1},{-.08,.72},{-.84,.70},{-1,.52},
        {-1,-.52},{-.84,-.70},{-.08,-.72},{.10,-1},{.91,-1},{1,-.70}
    } or {
        {1,.44},{.94,.64},{.43,.68},{.34,1},{-.84,1},{-1,.82},
        {-1,-.82},{-.84,-1},{.34,-1},{.43,-.68},{.94,-.64},{1,-.44}
    }
    local g=love.graphics
    local roll=projection.firstPerson and (projection.roll or 0) or 0
    local c,s=math.cos(roll),math.sin(roll)
    local scale=camera.zoom or 1
    local heading=actor.heading or 0
    local fx,fz=math.cos(heading),math.sin(heading)
    local sx,sz=-fz,fx
    local points={}
    for _,v in ipairs(outline) do
        local along,side=v[1]*dims.halfLength,v[2]*dims.halfWidth
        local x=actor.x+fx*along+sx*side
        local z=actor.z+fz*along+sz*side
        local ground=world:supportHeight(x,z)
        local px,py=projection:screen(x,z,ground+.018)
        local dx,dy=px-centerX,py-centerY
        -- The billboard is rolled after this helper; counter-roll the ground
        -- projection so the footprint stays registered to the terrain.
        if roll~=0 then dx,dy=dx*c+dy*s,-dx*s+dy*c end
        points[#points+1]=dx;points[#points+1]=dy
    end
    -- Two close silhouettes give the single vehicle-sized shadow a softer,
    -- less sticker-like edge without restoring separate wheel blobs.
    local expanded={}
    for i=1,#points,2 do
        expanded[i]=points[i]*1.035;expanded[i+1]=points[i+1]*1.035
    end
    g.setColor(.025,.024,.020,.10);g.polygon('fill',expanded)
    g.setColor(.025,.024,.020,.16);g.polygon('fill',points)
    g.setColor(1,1,1,1)
end

function Art.viewKind(camera)
    camera=camera or {}
    -- Billboard proxies are firstPerson even when their parent is an outside
    -- view. Choose by the actual camera mode, never elevation or proximity.
    local eye=camera.projectionCamera or camera
    if eye.shoulderPerspective or eye.outsideMode=='shoulder' or eye.shoulderView
        or eye.firstPerson and not eye.includeLocalRider then
        return 'chase'
    end
    return 'isometric'
end

local function projectedSpan(depth,bodyHeight,tilt)
    local pitch=math.rad(tilt)
    local groundScale=math.sin(pitch)/math.sin(math.rad(55))
    local heightScale=math.cos(pitch)/math.cos(math.rad(55))
    return depth*29*groundScale+bodyHeight*22*heightScale
end

-- The isometric sprites were authored from a fixed 32-degree camera. Scale
-- their billboard around its ground pivot to match the chassis span projected
-- by the current camera pitch, without changing its footprint or art scale.
local function pitchScale(actor,camera,kind)
    if kind~='isometric' then return 1 end
    local projection=camera.projectionCamera or camera
    local tilt=tonumber(projection.tilt)
    if not tilt then return 1 end
    local angle=relativeAngle(camera,actor.heading or 0)
    local dims=Footprint.dimensions(actor)
    local depth=dims.halfLength*math.abs(math.cos(angle))
        +dims.halfWidth*math.abs(math.sin(angle))
    -- Kei views share one registered roof-to-tire span. Changing the entire
    -- billboard's Y scale with bearing makes its cab and tires breathe twice
    -- per turn. Respond to camera tilt with one mean footprint depth instead.
    if actor.model=='kei' then depth=(dims.halfLength+dims.halfWidth)*2/math.pi end
    local base=projectedSpan(depth,dims.height,ISO_ART_PITCH)
    local current=projectedSpan(depth,dims.height,tilt)
    -- Keep the sprite pivot on the road while matching its authored ground
    -- plane to both flatter and steeper camera pitches.
    return math.max(MIN_PITCH_SCALE,math.min(1.18,current/base))
end

function Art.new()
    return setmetatable({pages=Pages.new(),keiPages=KeiPages.new(),decals=Decals.new()},Art)
end

-- Screen-space shots use the same calibrated turntables, model proportions,
-- and company markings as the actual vehicle, without a world camera.
function Art:drawSprite(actor,kind,angle,x,y,zoom)
    local frame=actor.model=='kei' and KeiPages.frame(angle,kind) or Pages.frame(angle)
    local pages=actor.model=='kei' and self.keiPages or self.pages
    local image,quad,format=pages:get(kind,frame)
    local scale=format.scale*zoom*(MODEL_ART_SCALE[actor.model] or 1)
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,quad,x,y,0,scale,scale,format.anchorX,format.anchorY)
    if actor.model~='kei' then
        local decal=self.decals:companyImage(actor.company)
            or self.decals.images[actor.livery or 'picture_shop']
        self.decals:drawTurntable(decal,kind,frame,x,y,scale,format)
    end
end

function Art:draw(actor,camera,world,silhouetteMode)
    local h=actor.h or world:supportHeight(actor.x,actor.z)
    local x,y=camera:screen(actor.x,actor.z,h)
    local kind=Art.viewKind(camera,actor,h)
    local frame=Art.frame(camera,actor.heading or 0,actor.model,kind)
    local pages=actor.model=='kei' and self.keiPages or self.pages
    local image,quad,format=pages:get(kind,frame)
    local scale=format.scale*camera.zoom*(MODEL_ART_SCALE[actor.model] or 1)
    local verticalScale=pitchScale(actor,camera,kind)
    love.graphics.setColor(1,1,1,1)
    if not silhouetteMode then drawVehicleShadow(actor,camera,world) end
    love.graphics.draw(image,quad,x,y,0,scale,scale*verticalScale,format.anchorX,format.anchorY)
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
