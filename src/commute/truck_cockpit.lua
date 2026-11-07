-- Driver-eye truck cab art, live instruments, and hit targets placed over the
-- corresponding physical switches in the transparent cab overlay.
local FP=require('src.commute.first_person_camera')
local Body=require('src.commute.first_person_bike')
local Cockpit={PATH='assets/commute/truck/cockpit-overlay-v2.png',WIDTH=1536,HEIGHT=1024}
Cockpit.__index=Cockpit
local INTERIOR='assets/commute/truck/interior-v2/'
local CAB={back=-1.55,front=1.25,halfWidth=1.45,floor=.025,roof=2.72}
local cabFormat={{'VertexPosition','float',3},{'VertexTexCoord','float',2}}
local cabShaderSource=[[#ifdef VERTEX
vec4 position(mat4 projection,vec4 vertex) { return riderProjection(projection,vertex.xyz); }
#endif
#ifdef PIXEL
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 pixel) {
    vec4 surface=Texel(tex,uv)*color;
    if(surface.a<.02) discard;
    return surface;
}
#endif
]]

local controls={
    {action='ignition',label='IGN',icon='ignition',x=154,y=785,assetX=202,assetY=470},
    {action='headlight',label='LIGHTS',icon='headlight',x=154,y=752,assetX=338,assetY=482},
    {action='beam',label='BEAM',icon='beam',x=582,y=707,assetX=655,assetY=482},
    {action='signalLeft',label='LEFT',icon='signalLeft',x=426,y=707,assetX=492,assetY=433},
    {action='signalRight',label='RIGHT',icon='signalRight',x=489,y=707,assetX=516,assetY=433},
    {action='radioPrevious',label='PREV',icon='reverse',assetX=864,assetY=540},
    {action='radioPlay',label='PLAY',icon='ignition',assetX=919,assetY=540},
    {action='radioNext',label='NEXT',icon='shift',assetX=974,assetY=540},
    {action='radioMute',label='MUTE',icon='headlight',assetX=1007,assetY=505},
}

local function transform(width,height)
    local scale=math.min(width/1280,height/880)
    return (width-1280*scale)*.5,(height-880*scale)*.5,scale
end

-- Unproject the authored forward view onto a plane fixed to the cab.
-- Both the textured dashboard and its switches use these chassis coordinates.
local focal=640/math.tan(math.rad(FP.FOV)*.5)
-- The windshield/dash plane pitches down from the player's higher seat eye,
-- keeping the dashboard low in frame while leaving the center windshield open.
local CAB_FRONT_PITCH=FP.NEUTRAL_PITCH-math.rad(4)
local function cabPoint(u,v)
    local up=(440-v*880)/focal
    local c,s=math.cos(CAB_FRONT_PITCH),math.sin(CAB_FRONT_PITCH)
    return c-up*s,FP.EYE_HEIGHT+s+up*c,(u*1280-640)/focal
end
local function cabEye(camera)
    if camera and camera.viewHeading and camera.bikeHeading then
        local eye=Body.camera(camera)
        -- The truck's world camera sits in the driver's side seat. Body.camera
        -- is centered for a motorcycle, so preserve the truck's lateral seat
        -- offset when projecting the cab around that eye.
        if camera.localVehicle=='truck' then
            eye.centerZ=camera.truckCabSide or FP.TRUCK_SEAT_SIDE
        end
        eye.viewCenterX,eye.viewCenterY=camera.viewCenterX,camera.viewCenterY
        eye.roll=eye.roll-(camera.barSteer or 0)*.055
        return eye
    end
    return {centerX=0,centerZ=0,eyeHeight=FP.EYE_HEIGHT,viewHeading=0,viewPitch=FP.NEUTRAL_PITCH,roll=0,focal=focal}
end

local function panel(image,points,center)
    local vertices={}
    for _,index in ipairs({1,2,3,1,3,4}) do
        local p=points[index]
        vertices[#vertices+1]={p[1],p[2],p[3],p[4],p[5]}
    end
    local mesh=love.graphics.newMesh(cabFormat,vertices,'triangles','static')
    mesh:setTexture(image)
    return {mesh=mesh,center=center}
end

local function interiorPanels(images)
    -- Every cabin face shares its four edge coordinates. Keeping the floor,
    -- roof, doors, and rear wall on this one section prevents open seams when
    -- the camera turns around inside the textured cab.
    local fBack,fFront=CAB.back,CAB.front
    local halfWidth=CAB.halfWidth
    local low,high=CAB.floor,CAB.roof
    local function p(f,up,right,u,v)return {f,up,right,u,v}end
    local function front(u,v,texU,texV)
        local f,up,right=cabPoint(u,v)
        return p(f,up,right,texU or u,texV or v)
    end
    local function seat(right,mirror)
        local half=.34
        local upperRight=mirror and 1 or 0
        local upperLeft=mirror and 0 or 1
        return panel(images.seat,{
            p(-.35,1.48,right+half,upperRight,0),p(-.35,1.48,right-half,upperLeft,0),
            p(-.35,.12,right-half,upperLeft,1),p(-.35,.12,right+half,upperRight,1)},
            {-.35,right,.8})
    end
    return {
        -- The animated front view is intentionally kept at its authored scale.
        -- These four trim pieces bridge its screen-sized edges to the real cab
        -- shell, closing the windshield header, firewall, and A-pillar seams.
        panel(images.roof,{
            p(fFront,high,-halfWidth,0,0),p(fFront,high,halfWidth,1,0),
            front(1,0,1,1),front(0,0,0,1)},
            {fFront,0,(high+2.24)*.5}),
        panel(images.floor,{
            front(0,1,0,0),front(1,1,1,0),
            p(fFront,low,halfWidth,1,1),p(fFront,low,-halfWidth,0,1)},
            {fFront,0,(low+1.05)*.5}),
        panel(images.door,{
            front(0,0,0,0),p(fFront,high,-halfWidth,.06,0),
            p(fFront,low,-halfWidth,.06,1),front(0,1,0,1)},
            {fFront,-(halfWidth+.87)*.5,(low+high)*.5}),
        panel(images.door,{
            front(1,0,1,0),p(fFront,high,halfWidth,.94,0),
            p(fFront,low,halfWidth,.94,1),front(1,1,1,1)},
            {fFront,(halfWidth+.87)*.5,(low+high)*.5}),
        panel(images.rear,{
            p(fBack,high,halfWidth,0,0),p(fBack,high,-halfWidth,1,0),
            p(fBack,low,-halfWidth,1,1),p(fBack,low,halfWidth,0,1)},
            {fBack,0,(low+high)*.5}),
        -- The doors share a texture; opposite UV orientations keep the latch
        -- at the rear edge of each physical door.
        panel(images.door,{
            p(fBack,high,halfWidth,0,0),p(fFront,high,halfWidth,1,0),
            p(fFront,low,halfWidth,1,1),p(fBack,low,halfWidth,0,1)},
            {0,halfWidth,(low+high)*.5}),
        panel(images.door,{
            p(fFront,high,-halfWidth,0,0),p(fBack,high,-halfWidth,1,0),
            p(fBack,low,-halfWidth,1,1),p(fFront,low,-halfWidth,0,1)},
            {0,-halfWidth,(low+high)*.5}),
        panel(images.floor,{
            p(fFront,low,-halfWidth,0,0),p(fFront,low,halfWidth,1,0),
            p(fBack,low,halfWidth,1,1),p(fBack,low,-halfWidth,0,1)},
            {-.15,0,low}),
        panel(images.roof,{
            p(fBack,high,-halfWidth,0,0),p(fBack,high,halfWidth,1,0),
            p(fFront,high,halfWidth,1,1),p(fFront,high,-halfWidth,0,1)},
            {-.15,0,high}),
        -- Keep the driver seat under the steering column and its passenger
        -- mate beside it so a rearward look reads as a cab, not one centered chair.
        seat(-.38,false),seat(.38,true),
    }
end

local function clamp(value,lo,hi)return math.max(lo,math.min(hi,value))end
local function drawNeedle(g,cx,cy,length,value)
    local angle=math.rad(135+clamp(value,0,1)*270)
    local x,y=cx+math.cos(angle)*length,cy+math.sin(angle)*length
    g.setLineWidth(4);g.setColor(.045,.035,.027,.9);g.line(cx+1,cy+2,x+1,y+2)
    g.setLineWidth(2.3);g.setColor(.86,.31,.20,1);g.line(cx,cy,x,y)
    g.setColor(.72,.64,.49,1);g.circle('fill',cx,cy,3.7)
    g.setColor(.15,.13,.11,1);g.circle('fill',cx,cy,1.8)
end
local function drawArrow(g,x,y,direction,lit)
    if lit then g.setColor(1,.67,.16,1) else g.setColor(.18,.24,.18,.82) end
    local tip=x+direction*7
    g.setLineWidth(lit and 3 or 2)
    g.line(x-direction*6,y,tip,y)
    g.line(tip,y,tip-direction*4,y-4)
    g.line(tip,y,tip-direction*4,y+4)
end
local function drawAligned(g,image,sourceX,sourceY,targetX,targetY,angle)
    g.draw(image,targetX,targetY,angle,1,1,sourceX,sourceY)
end

local function drawInterior(view,camera,width,height)
    local eye=cabEye(camera)
    local visible={}
    for _,entry in ipairs(view.interiorPanels) do
        local _,_,depth=FP.coordinates(eye,entry.center[1],entry.center[2],entry.center[3])
        visible[#visible+1]={entry=entry,depth=depth}
    end
    -- Draw the closed cab from far to near so each turn reveals the right wall.
    table.sort(visible,function(a,b)return a.depth>b.depth end)
    local g=love.graphics;local x,y,scale=transform(width,height)
    -- Cab panels are full-view meshes drawn through the commute's nested
    -- scale transform; clear the inherited screen-space scissor first.
    g.push('all');g.setScissor();g.translate(x,y);g.scale(scale)
    g.setMeshCullMode('none');g.setDepthMode('always',false);g.setBlendMode('alpha')
    g.setColor(1,1,1,1);FP.send(eye,view.interiorShader);g.setShader(view.interiorShader)
    for _,item in ipairs(visible) do g.draw(item.entry.mesh) end
    g.pop()
end

function Cockpit.controls(width,height,camera,state)
    state=state or {}
    local x0,y0,scale=transform(width,height)
    local result={}
    local eye=camera and camera.firstPerson and cabEye(camera)
    local radio=require('src.jukebox')
    for _,spec in ipairs(controls) do
        local radioControl=spec.action:sub(1,5)=='radio'
        local x,y,depth
        if eye then
            local forward,up,right=cabPoint(spec.assetX/Cockpit.WIDTH,spec.assetY/Cockpit.HEIGHT)
            x,y,depth=FP.screen(eye,forward,right,up)
            x,y=x0+x*scale,y0+y*scale
        else
            local index=#result
            x=x0+(510+index*66)*scale
            y=y0+764*scale
        end
        local active=(spec.action=='ignition' and state.engine==true)
            or (spec.action=='headlight' and state.headlight==true)
            or (spec.action=='beam' and state.headlightHighBeam==true)
            or (spec.action=='signalLeft' and state.turnSignal=='left')
            or (spec.action=='signalRight' and state.turnSignal=='right')
            or (spec.action=='radioPlay' and radio.active and not radio.paused)
            or (spec.action=='radioMute' and radio.muted==true)
        if (not radioControl or eye) and (not eye or depth>=FP.NEAR and x>=0 and x<=width and y>=0 and y<=height) then
            result[#result+1]={action=spec.action,label=spec.label,icon=spec.icon,x=x,y=y,
            visualRadius=15*scale,hitRadius=26*scale,active=active}
        end
    end
    return result
end

function Cockpit.new()
    local g=love.graphics
    assert(love.filesystem.getInfo(Cockpit.PATH,'file'),'Missing delivery truck cab overlay: '..Cockpit.PATH)
    local image=g.newImage(Cockpit.PATH)
    assert(image:getWidth()==Cockpit.WIDTH and image:getHeight()==Cockpit.HEIGHT,
        'Invalid delivery truck cab overlay: '..Cockpit.PATH)
    image:setFilter('linear','linear')
    local layers={}
    for key,file in pairs({wheel='steering-wheel.png',accelerator='accelerator-pedal.png',brake='brake-pedal.png'}) do
        layers[key]=g.newImage(INTERIOR..file)
        assert(layers[key]:getWidth()==Cockpit.WIDTH and layers[key]:getHeight()==Cockpit.HEIGHT,
            'Invalid delivery truck cab layer: '..INTERIOR..file)
        layers[key]:setFilter('linear','linear')
    end
    local vertices={}
    for _,uv in ipairs({{0,0},{1,0},{1,1},{0,1}}) do
        local x,y,z=cabPoint(uv[1],uv[2])
        vertices[#vertices+1]={x,y,z,uv[1],uv[2]}
    end
    local mesh=g.newMesh({{'VertexPosition','float',3},{'VertexTexCoord','float',2}},vertices,'fan','static')
    -- The cab texture has a fixed authored resolution regardless of phone DPI.
    local panel=g.newCanvas(1280,880,{dpiscale=1})
    mesh:setTexture(panel)
    local shader=g.newShader(love.filesystem.read('src/commute/perspective.glsl')..[[
#ifdef VERTEX
vec4 position(mat4 projection,vec4 vertex) { return riderProjection(projection,vertex.xyz); }
#endif
]])
    local interiorImages={}
    for key,file in pairs({rear=INTERIOR..'rear-wall.png',door=INTERIOR..'side-door.png',
        floor=INTERIOR..'floorboard.png',roof='assets/commute/truck/interior-v1/headliner.png',
        seat='assets/commute/truck/interior-v1/driver-seat.png'}) do
        interiorImages[key]=g.newImage(file)
        interiorImages[key]:setFilter('linear','linear')
    end
    return setmetatable({image=image,panel=panel,mesh=mesh,shader=shader,
        wheel=layers.wheel,accelerator=layers.accelerator,brake=layers.brake,
        displaySteering=0,displayThrottle=0,displayBrake=0,
        interiorImages=interiorImages,interiorPanels=interiorPanels(interiorImages),
        interiorShader=g.newShader(love.filesystem.read('src/commute/perspective.glsl')..'\n'..cabShaderSource)},Cockpit)
end

function Cockpit:draw(truck,width,height,camera)
    if not truck then return end
    local g=love.graphics
    local x,y,scale=0,0,1
    local sx,sy=1280/Cockpit.WIDTH,880/Cockpit.HEIGHT
    local dt=love.timer and love.timer.getDelta and love.timer.getDelta() or 1/60
    local blend=1-math.exp(-math.min(.1,math.max(0,dt))*15)
    self.displaySteering=self.displaySteering+((truck.steering or 0)-self.displaySteering)*blend
    self.displayThrottle=self.displayThrottle+((truck.throttle or 0)-self.displayThrottle)*blend
    self.displayBrake=self.displayBrake+((truck.brake or 0)-self.displayBrake)*blend
    g.push('all')
    g.setCanvas(self.panel);g.origin();g.setScissor();g.setShader();g.setBlendMode('alpha')
    g.clear(0,0,0,0)
    g.setColor(1,1,1,1)
    g.draw(self.image,x,y,0,sx*scale,sy*scale)
    g.push();g.scale(sx*scale,sy*scale)
    -- The illustrated gauge faces stay crisp while their needles follow truck telemetry.
    local speedRatio=clamp(((truck.speed or 0)*2.236936)/60,0,1)
    local engineLoad=truck.engine==false and 0 or clamp(.13+(truck.throttle or 0)*.62+speedRatio*.24,0,1)
    drawNeedle(g,402,441,50,speedRatio)
    drawNeedle(g,585,441,50,engineLoad)
    local fuel=clamp((truck.fuel or require('src.commute.delivery_truck').TANK_LITERS)
        /require('src.commute.delivery_truck').TANK_LITERS,0,1)
    g.setColor(.055,.075,.06,.96);g.rectangle('fill',374,491,236,19,3)
    g.setColor(.84,.87,.72,1);g.print('FUEL',380,493,0,.52,.52)
    g.setColor(fuel<=.2 and 1 or .44,fuel<=.2 and .37 or .79,fuel<=.2 and .24 or .48,1)
    g.rectangle('fill',424,496,155*fuel,8,2)
    g.setColor(.88,.87,.74,1);g.printf(('%d L'):format(math.floor((truck.fuel or 0)+.5)),580,493,30,'right',0,.48,.48)
    local blink=math.floor((love.timer and love.timer.getTime and love.timer.getTime() or 0)*2)%2==0
    drawArrow(g,493,418,-1,truck.turnSignal=='left' and blink)
    drawArrow(g,512,418,1,truck.turnSignal=='right' and blink)
    g.setColor(truck.headlight and .31 or .13,truck.headlight and .91 or .18,truck.headlight and .55 or .16,1)
    g.circle('fill',493,472,3)
    g.setColor(truck.headlightHighBeam and .34 or .13,truck.headlightHighBeam and .70 or .18,
        truck.headlightHighBeam and 1 or .16,1)
    g.circle('fill',508,472,3)
    local radio=require('src.jukebox').displayState()
    g.setColor(.30,.88,.62,1)
    g.print(('FM 01   %02d/%02d'):format(radio.trackIndex,radio.trackCount),854,492,0,.43,.43)
    g.setColor(radio.muted and .75 or .84,radio.muted and .49 or .91,radio.muted and .36 or .70,1)
    local track=(radio.title or 'VIBES FM'):upper():sub(1,17)
    g.print(radio.muted and 'MUTED' or radio.active and not radio.paused and track or 'RADIO OFF',854,509,0,.43,.43)
    -- The wide left pedal is the brake; the narrow right pedal is the accelerator.
    -- Their top pivots remain fixed while the plates press in response to input.
    drawAligned(g,self.brake,624,765,480,765-self.displayBrake*2,-self.displayBrake*.11)
    drawAligned(g,self.accelerator,644,765,644,765-self.displayThrottle*2,-self.displayThrottle*.11)
    drawAligned(g,self.wheel,480,568,480,568,self.displaySteering*.76)
    g.pop()
    g.pop()
    drawInterior(self,camera,width,height)
    g.push('all');g.setScissor()
    x,y,scale=transform(width,height)
    g.translate(x,y);g.scale(scale)
    g.setColor(1,1,1);g.setMeshCullMode('none');g.setDepthMode('always',false)
    g.setBlendMode('alpha','premultiplied')
    FP.send(cabEye(camera),self.shader);g.setShader(self.shader);g.draw(self.mesh)
    g.pop()
end

function Cockpit:release()
    self.image:release()
    self.wheel:release();self.accelerator:release();self.brake:release()
    self.mesh:release();self.panel:release();self.shader:release()
    self.interiorShader:release()
    for _,entry in ipairs(self.interiorPanels) do entry.mesh:release() end
    for _,image in pairs(self.interiorImages) do image:release() end
end

return Cockpit
