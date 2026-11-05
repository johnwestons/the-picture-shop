-- Authored vehicle billboards. All left/right views are drawn
-- independently: the exhaust and chain must never trade sides via mirroring.
local Art={SCALE=.46,FRAME=320,COLUMNS=4,ROWS=4,FRAME_COUNT=16,ATLAS_WIDTH=1280,ATLAS_HEIGHT=1280,ANCHOR_X=160,ANCHOR_Y=260}
Art.UPRIGHT_FRAME_COUNT=64
Art.UPRIGHT_COLUMNS=8
Art.UPRIGHT_ROWS=8
Art.UPRIGHT_ATLAS_WIDTH=Art.FRAME*Art.UPRIGHT_COLUMNS
Art.UPRIGHT_ATLAS_HEIGHT=Art.FRAME*Art.UPRIGHT_ROWS
Art.UPRIGHT_PATH='assets/commute/bike/mounted-upright-64-v2.png'
Art.__index=Art
Art.directions={'north','north-northeast','northeast','east-northeast',
    'east','east-southeast','southeast','south-southeast',
    'south','south-southwest','southwest','west-southwest',
    'west','west-northwest','northwest','north-northwest'}
local PaintArt=require('src.commute.bike_paint_art')
local Bike=require('src.commute.motorcycle')
local M=require('src.commute.vendor.mathx')
local Pages=require('src.commute.bike_action_pages')
local Pose=require('src.commute.bike_action_pose')
local Wheels=require('assets.commute.bike.wheel_regions')
Art.ACTION_STATES=Pages.states
Art.MOUNTED_FRAME_COUNT=64
local indices={};for i,name in ipairs(Art.directions) do indices[name]=i end
function Art.frame(camera,heading,frameCount)
    if frameCount==8 then
        return (assert(indices[camera:headingDirection(heading)],'Unknown motorcycle heading')+1)/2
    end
    if not frameCount or frameCount==16 then
        return assert(indices[camera:headingDirection16(heading)],'Unknown motorcycle heading')
    end
    local relative
    if camera.firstPerson then relative=heading-(camera.viewHeading or 0)-math.pi*.5
    else relative=heading+math.rad(camera.yaw or 0) end
    local step=math.pi*2/frameCount
    return math.floor((relative+math.pi*.5)/step+.5)%frameCount+1
end
Art.DIRECTION_COUNT=64
function Art.bank(actor,camera,rawLean,limit)
    local relative=camera.firstPerson and (actor.heading-(camera.viewHeading or 0)-math.pi*.5)
        or actor.heading+math.rad(camera.yaw or 0)
    limit=limit or .16
    return M.clamp(rawLean,-limit,limit)*math.sin(relative)
end
-- The atlas already shows a level wheelbase in each direction. Rotate only
-- the difference introduced by pitch, measured in this camera's projection.
function Art.pitchRotation(actor,camera,height,pitch)
    if not pitch or math.abs(pitch)<1e-6 then return 0 end
    local side=camera.firstPerson and math.sin(actor.heading-(camera.viewHeading or 0))
        or math.cos(actor.heading+math.rad(camera.yaw or 0))
    -- The two wheels overlap in the end-on views. A nose-up bike seen from
    -- behind must not tip sideways when its screen-space wheelbase vanishes.
    local weight=M.smooth((math.abs(side)-math.sin(math.pi/16))/.25)
    if weight==0 then return 0 end
    local projection=camera.projectionCamera or camera
    local dx=math.cos(actor.heading)*Bike.WHEELBASE*.5
    local dz=math.sin(actor.heading)*Bike.WHEELBASE*.5
    local rise=math.tan(pitch)*Bike.WHEELBASE*.5
    local x,y=projection:screen(actor.x,actor.z,height)
    local flatX,flatY,flatDepth=projection:screen(actor.x+dx,actor.z+dz,height)
    local raisedX,raisedY,raisedDepth=projection:screen(actor.x+dx,actor.z+dz,height+rise)
    if flatDepth and (flatDepth<.15 or raisedDepth<.15) then return 0 end
    flatX,flatY=flatX-x,flatY-y
    raisedX,raisedY=raisedX-x,raisedY-y
    local length2=flatX*flatX+flatY*flatY
    local cross=flatX*raisedY-flatY*raisedX
    local dot=flatX*raisedX+flatY*raisedY
    return weight*math.atan2(cross,math.max(dot,.25*length2))
end
local function spriteRotation(actor,camera,height,parked,presentation)
    local chassisPitch=presentation and presentation.pitch or actor.pitch
    if chassisPitch==nil then chassisPitch=math.atan(presentation and presentation.grade or actor.grade or 0) end
    local pitch=Art.pitchRotation(actor,camera,height,chassisPitch)
    if parked then return pitch end
    local lean=presentation and presentation.lean or actor.lean or 0
    local fixed=not camera.firstPerson and camera.outsideMode~='follow'
    return Art.bank(actor,camera,lean,fixed and .3 or .16)+pitch
end
local function lowestTireArc(state,frame,rotation)
    local stateWheels=Wheels[state]
    local row=stateWheels and stateWheels[frame]
    if not row then return 0 end
    local s,c=math.sin(rotation),math.cos(rotation)
    local lowest=-math.huge
    for i=1,5,4 do
        local rx,ry=row[i+2],row[i+3]
        if ry>0 then
            local center=s*(row[i]-Art.ANCHOR_X)+c*(row[i+1]-Art.ANCHOR_Y)
            lowest=math.max(lowest,center+math.sqrt((rx*s)^2+(ry*c)^2))
        end
    end
    return lowest==-math.huge and 0 or math.max(0,lowest)
end
-- Convert the authored tire contact edge below the sprite pivot into an
-- equivalent depth offset. This keeps the billboard's ground-contact pixels
-- in front of the terrain depth buffer without changing its screen position.
function Art:groundedDepthBias(actor,camera,height,presentation)
    local state=Pose.select(actor,presentation)
    local frame=Art.frame(camera,actor.heading,64)
    local rotation=spriteRotation(actor,camera,height,false,presentation)
    local lowest=lowestTireArc(state,frame,rotation)
    local groundScale=math.max(.01,camera:groundScale())
    return (lowest+1)*Art.SCALE*22*camera:heightScale()
        /(29*29*groundScale*groundScale)
end
function Art.new()
    local parked='assets/commute/bike/parked-16.png'
    assert(love.filesystem.getInfo(parked,'file'),'Missing parked motorcycle atlas: '..parked)
    assert(love.filesystem.getInfo(Art.UPRIGHT_PATH,'file'),'Missing upright motorcycle turntable: '..Art.UPRIGHT_PATH)
    local self=setmetatable({images={},quads={},uprightQuads={},frameCount=64,parkedFrameCount=16,atlasHeight=1280},Art)
    self.actionPages=Pages.new()
    PaintArt.prewarm()
    for state,path in pairs({parked=parked,upright=Art.UPRIGHT_PATH}) do
        local image=love.graphics.newImage(path)
        local size=state=='upright' and 2560 or 1280
        assert(image:getWidth()==size and image:getHeight()==size,'Invalid motorcycle atlas: '..path)
        image:setFilter('linear','linear');self.images[state]=image
    end
    for i=0,15 do self.quads[i+1]=love.graphics.newQuad(i%4*320,math.floor(i/4)*320,320,320,1280,1280) end
    for i=0,63 do self.uprightQuads[i+1]=love.graphics.newQuad(i%8*320,math.floor(i/8)*320,320,320,2560,2560) end
    return self
end
Art.action=Pose.action
Art.pose=Pose.select
function Art:resolve(state,frame)
    if state=='mounted' then state='upright' end
    if state=='parked' then return self.images.parked,self.quads[frame] end
    if state=='upright' then return self.images.upright,self.uprightQuads[frame] end
    return self.actionPages:get(state,frame)
end
function Art:describe(image,quad)
    if image==self.images.parked or image==self.images.upright then
        local upright=image==self.images.upright
        local x,y=quad:getViewport()
        return {state=upright and 'upright' or 'parked',frame=y/320*(upright and 8 or 4)+x/320+1}
    end
    return self.actionPages:describe(image,quad)
end
function Art:draw(actor,camera,world,parked,presentation)
    local height=presentation and presentation.h or actor.h or world:supportHeight(actor.x,actor.z)
    local x,y=camera:screen(actor.x,actor.z,height)
    local frame=Art.frame(camera,actor.heading,parked and 16 or 64)
    local state,action,turnBlend
    local lean=presentation and presentation.lean
    if lean==nil then lean=actor.lean or 0 end
    local rotation=spriteRotation(actor,camera,height,parked,presentation)
    if parked then state='parked'
    else
        state,action,turnBlend=Pose.select(actor,presentation)
        if self.actionPages then
            -- Warm one family per rider. Warming overridden tuck/turn/action
            -- poses together can churn the bounded cache with four riders.
            local warm=state~='upright' and state or action
            if not warm and turnBlend>.05 then warm=lean>=0 and 'turnLeft' or 'turnRight' end
            local speed=presentation and presentation.speed or actor.speed or 0
            if not warm and speed>Bike.TUCK_START_SPEED-.3 then warm='aero' end
            if warm then self.actionPages:prepare(warm,frame) end
        end
    end
    local image,quad=self:resolve(state,frame)
    local g=love.graphics;local scale=Art.SCALE*camera.zoom
    if not parked and camera.projectionCamera and camera.projectionCamera.includeLocalRider then
        -- The shared pivot is at the wheelbase midpoint. Align the lowest
        -- rotated tire arc to the surface in the over-the-shoulder view.
        local lowest=lowestTireArc(state,frame,rotation)
        -- Region coordinates identify pixel centers; include the filtered edge.
        y=y-(lowest+1)*scale
    end
    g.setColor(1,1,1,1)
    PaintArt.draw(image,quad,actor.paintId,x,y,rotation,scale,scale,Art.ANCHOR_X,Art.ANCHOR_Y,frame,state,actor,presentation)
    g.setColor(1,1,1)
    return y
end
function Art:release()
    for _,image in pairs(self.images) do image:release() end
    for _,quad in ipairs(self.quads) do quad:release() end
    for _,quad in ipairs(self.uprightQuads) do quad:release() end
    self.actionPages:release()
    self.images={};self.quads={};self.uprightQuads={}
end
return Art
