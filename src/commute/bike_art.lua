-- Authored vehicle billboards. All left/right views are drawn
-- independently: the exhaust and chain must never trade sides via mirroring.
local Art={SCALE=.46,FRAME=320,COLUMNS=4,ROWS=4,FRAME_COUNT=16,ATLAS_WIDTH=1280,ATLAS_HEIGHT=1280,ANCHOR_X=160,ANCHOR_Y=260}
Art.__index=Art
Art.directions={'north','north-northeast','northeast','east-northeast',
    'east','east-southeast','southeast','south-southeast',
    'south','south-southwest','southwest','west-southwest',
    'west','west-northwest','northwest','north-northwest'}
local PaintArt=require('src.commute.bike_paint_art')
local Bike=require('src.commute.motorcycle')
local M=require('src.commute.vendor.mathx')
local RidingAnimation=require('src.commute.riding_animation')
local indices={};for i,name in ipairs(Art.directions) do indices[name]=i end
function Art.frame(camera,heading,frameCount)
    if frameCount==8 then
        return (assert(indices[camera:headingDirection(heading)],'Unknown motorcycle heading')+1)/2
    end
    return assert(indices[camera:headingDirection16(heading)],'Unknown motorcycle heading')
end
function Art.frameBlend(camera,heading,frameCount)
    frameCount=frameCount or Art.FRAME_COUNT
    local relative
    if camera.firstPerson then relative=heading-(camera.viewHeading or 0)
    else relative=heading+math.rad(camera.yaw or 0) end
    local step=math.pi*2/frameCount
    local position=((relative+math.pi*.5)/step)%frameCount
    local base=math.floor(position)
    return base+1,(base+1)%frameCount+1,position-base
end
Art.DIRECTION_COUNT=16
function Art.bank(actor,camera,rawLean)
    local relative=camera.firstPerson and (actor.heading-(camera.viewHeading or 0)-math.pi*.5)
        or actor.heading+math.rad(camera.yaw or 0)
    return M.clamp(rawLean,-.16,.16)*math.sin(relative)
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
function Art.new()
    local self=setmetatable({images={},quads={}},Art)
    local files={parked='parked',mounted='mounted',aero='mounted-aero-tuck',
        aeroMid='mounted-aero-tuck-transition',
        boost='mounted-acceleration-response',shift='mounted-gear-shift',
        boostMid='mounted-boost-transition',shiftMid='mounted-gear-shift-transition',
        impact='mounted-impact-brace',impactMid='mounted-impact-transition',
        turnLeft='mounted-hard-turn-left',turnRight='mounted-hard-turn-right',
        turnLeftMid='mounted-turn-left-transition',turnRightMid='mounted-turn-right-transition'}
    -- A missing pose is a packaging error, never permission to drop directions.
    local suffix='-16'
    for _,file in pairs(files) do
        local path='assets/commute/bike/'..file..suffix..'.png'
        assert(love.filesystem.getInfo(path,'file'),'Missing sixteen-view motorcycle atlas: '..path)
    end
    self.frameCount=Art.FRAME_COUNT;self.atlasHeight=Art.ATLAS_HEIGHT
    PaintArt.prewarm()
    for state,file in pairs(files) do
        local path='assets/commute/bike/'..file..suffix..'.png'
        local image=love.graphics.newImage(path)
        assert(image:getWidth()==Art.ATLAS_WIDTH and image:getHeight()==self.atlasHeight,'Invalid motorcycle atlas: '..path)
        image:setFilter('linear','linear');self.images[state]=image
    end
    for i=1,self.frameCount do
        self.quads[i]=love.graphics.newQuad((i-1)%Art.COLUMNS*Art.FRAME,
            math.floor((i-1)/Art.COLUMNS)*Art.FRAME,Art.FRAME,Art.FRAME,Art.ATLAS_WIDTH,self.atlasHeight)
    end
    return self
end
local function pulseWeight(timeLeft,duration)
    if timeLeft<=0 then return 0 end
    local progress=1-M.clamp(timeLeft/duration,0,1)
    return math.sin(progress*math.pi)
end
local function transitionWeights(progress)
    progress=M.clamp(progress,0,1)
    if progress<.5 then
        local middle=M.smooth(progress*2)
        return 1-middle,middle,0
    end
    local target=M.smooth((progress-.5)*2)
    return 0,1-target,target
end
function Art.action(actor,presentation,turnBlend)
    local view=presentation or actor
    local impact=view.impactPulse or 0
    if impact>0 then
        return 'impact',pulseWeight(impact,Bike.IMPACT_DURATION)*M.clamp(view.impactStrength or 0,0,1)
    end
    local kind,remaining
    if presentation and presentation.ridingAction~=nil then
        kind,remaining=presentation.ridingAction,presentation.ridingActionTime
    elseif not presentation and actor.ridingAnimation then
        kind,remaining=RidingAnimation.sample(actor)
    else
        -- Compatible with old network snapshots; boost must not be overridden
        -- by a physical torque-cut timer even without sequenced pose metadata.
        if (view.boostPulse or 0)>0 then return 'boost',pulseWeight(view.boostPulse,Bike.BOOST_PULSE) end
        if (view.shiftTime or 0)>0 then return 'shift',pulseWeight(view.shiftTime,Bike.SHIFT_TIME)*(1-(turnBlend or 0)) end
        return nil,0
    end
    if kind=='idle' then return nil,0 end
    local weight=pulseWeight(remaining or 0,RidingAnimation.durations[kind])
    if kind=='shift' then weight=weight*(1-(turnBlend or 0)) end
    return kind,weight
end
function Art:draw(actor,camera,world,parked,presentation,blendDirections)
    local height=presentation and presentation.h or actor.h or world:supportHeight(actor.x,actor.z)
    local x,y=camera:screen(actor.x,actor.z,height)
    local chassisPitch=presentation and presentation.pitch or actor.pitch
    if chassisPitch==nil then chassisPitch=math.atan(presentation and presentation.grade or actor.grade or 0) end
    local pitch=Art.pitchRotation(actor,camera,height,chassisPitch)
    local frame,nextFrame,directionBlend=Art.frameBlend(camera,actor.heading,self.frameCount)
    if blendDirections==false then frame=Art.frame(camera,actor.heading,self.frameCount);nextFrame=frame;directionBlend=0 end
    local g=love.graphics
    local scale=Art.SCALE*camera.zoom
    local function drawFrame(state,alpha,rotation,frameIndex)
        if alpha<=.001 then return end
        g.setColor(1,1,1,alpha)
        if actor.paintId and actor.paintId~='bronze' then
            PaintArt.draw(self.images[state],self.quads[frameIndex],actor.paintId,x,y,rotation,scale,scale,
                Art.ANCHOR_X,Art.ANCHOR_Y,self.frameCount==8 and frameIndex*2-1 or frameIndex,state)
        else
            g.draw(self.images[state],self.quads[frameIndex],x,y,rotation,scale,scale,Art.ANCHOR_X,Art.ANCHOR_Y)
        end
    end
    local function drawState(state,alpha,rotation)
        drawFrame(state,alpha*(1-directionBlend),rotation,frame)
        if directionBlend>.001 then drawFrame(state,alpha*directionBlend,rotation,nextFrame) end
    end
    if parked then
        drawState('parked',1,pitch)
        g.setColor(1,1,1)
        return
    end

    local visualPresentation=presentation
    presentation=presentation or {}
    local speed=presentation.speed or actor.speed or 0
    local rawLean=presentation.lean or actor.lean or 0
    local lean=Art.bank(actor,camera,rawLean)+pitch
    local turnBlend=M.smooth((math.abs(rawLean)-.15)/.15)
    local turnState,turnMid=rawLean>=0 and 'turnLeft' or 'turnRight',
        rawLean>=0 and 'turnLeftMid' or 'turnRightMid'
    local tuck=M.smooth((speed-Bike.TUCK_START_SPEED)/(Bike.BOOST_MAX_SPEED-Bike.TUCK_START_SPEED))
    local tuckFrom,tuckMid,tuckTo=transitionWeights(tuck)
    local turnFrom,turnMiddle,turnTo=transitionWeights(turnBlend)
    local action,actionWeight=Art.action(actor,visualPresentation,turnBlend)
    local actionMid=action and action..'Mid'
    local actionFrom,actionMiddle,actionTo=transitionWeights(actionWeight)
    drawState('mounted',tuckFrom*turnFrom*actionFrom,lean)
    drawState('aeroMid',tuckMid*turnFrom*actionFrom,lean)
    drawState('aero',tuckTo*turnFrom*actionFrom,lean)
    drawState(turnMid,turnMiddle*actionFrom,lean)
    drawState(turnState,turnTo*actionFrom,lean)
    drawState(actionMid,actionMiddle,lean)
    drawState(action,actionTo,lean)
    g.setColor(1,1,1)
end
function Art:release()
    for _,image in pairs(self.images) do image:release() end
    for _,quad in ipairs(self.quads) do quad:release() end
    self.images={};self.quads={}
end
return Art
