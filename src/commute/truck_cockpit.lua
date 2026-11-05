-- Driver-eye truck cab art, live instruments, and hit targets placed over the
-- corresponding physical switches in the transparent cab overlay.
local M=require('src.commute.vendor.mathx')
local FP=require('src.commute.first_person_camera')
local Body=require('src.commute.first_person_bike')
local Cockpit={PATH='assets/commute/truck/cockpit-overlay-v1.png',WIDTH=1536,HEIGHT=1024}
Cockpit.__index=Cockpit
local INTERIOR='assets/commute/truck/interior-v1/'
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
    {action='ignition',label='IGN',icon='ignition',x=154,y=785,assetX=185,assetY=913},
    {action='headlight',label='LIGHTS',icon='headlight',x=154,y=752,assetX=185,assetY=874},
    {action='beam',label='BEAM',icon='beam',x=582,y=707,assetX=698,assetY=823},
    {action='signalLeft',label='LEFT',icon='signalLeft',x=426,y=707,assetX=511,assetY=823},
    {action='signalRight',label='RIGHT',icon='signalRight',x=489,y=707,assetX=587,assetY=823},
}

local function transform(width,height)
    local scale=math.min(width/1280,height/880)
    return (width-1280*scale)*.5,(height-880*scale)*.5,scale
end

-- Unproject the authored forward view onto a plane fixed to the cab.
-- Both the textured dashboard and its switches use these chassis coordinates.
local focal=640/math.tan(math.rad(FP.FOV)*.5)
local function cabPoint(u,v)
    local up=(440-v*880)/focal
    local c,s=math.cos(FP.NEUTRAL_PITCH),math.sin(FP.NEUTRAL_PITCH)
    return c-up*s,FP.EYE_HEIGHT+s+up*c,(u*1280-640)/focal
end
local function cabEye(camera)
    if camera and camera.viewHeading and camera.bikeHeading then
        local eye=Body.camera(camera)
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
    local fBack,fFront=-1.55,1.25
    local halfWidth,side=1.45,1.12
    local low,high=.08,2.68
    local function p(f,up,right,u,v)return {f,up,right,u,v}end
    return {
        panel(images.rear,{
            p(fBack,high,halfWidth,0,0),p(fBack,high,-halfWidth,1,0),
            p(fBack,low,-halfWidth,1,1),p(fBack,low,halfWidth,0,1)},
            {fBack,0,1.38}),
        -- The doors share a texture; opposite UV orientations keep the latch
        -- at the rear edge of each physical door.
        panel(images.door,{
            p(fBack,high,side,0,0),p(fFront,high,side,1,0),
            p(fFront,low,side,1,1),p(fBack,low,side,0,1)},
            {0,side,1.38}),
        panel(images.door,{
            p(fFront,high,-side,0,0),p(fBack,high,-side,1,0),
            p(fBack,low,-side,1,1),p(fFront,low,-side,0,1)},
            {0,-side,1.38}),
        panel(images.floor,{
            p(fFront,.025,-halfWidth,0,0),p(fFront,.025,halfWidth,1,0),
            p(fBack,.025,halfWidth,1,1),p(fBack,.025,-halfWidth,0,1)},
            {-.15,0,.025}),
        panel(images.roof,{
            p(fBack,2.72,-halfWidth,0,0),p(fBack,2.72,halfWidth,1,0),
            p(fFront,2.72,halfWidth,1,1),p(fFront,2.72,-halfWidth,0,1)},
            {-.15,0,2.72}),
        panel(images.seat,{
            p(-.35,1.48, .52,0,0),p(-.35,1.48,-.52,1,0),
            p(-.35,.12,-.52,1,1),p(-.35,.12, .52,0,1)},
            {-.35,0,.8}),
    }
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
    g.push('all');g.translate(x,y);g.scale(scale)
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
    for _,spec in ipairs(controls) do
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
        if not eye or depth>=FP.NEAR and x>=0 and x<=width and y>=0 and y<=height then
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
    for key,file in pairs({rear='rear-wall.png',door='side-door.png',floor='floorboard.png',
        roof='headliner.png',seat='driver-seat.png'}) do
        interiorImages[key]=g.newImage(INTERIOR..file)
        interiorImages[key]:setFilter('linear','linear')
    end
    return setmetatable({image=image,panel=panel,mesh=mesh,shader=shader,
        interiorImages=interiorImages,interiorPanels=interiorPanels(interiorImages),
        interiorShader=g.newShader(love.filesystem.read('src/commute/perspective.glsl')..'\n'..cabShaderSource)},Cockpit)
end

function Cockpit:draw(truck,width,height,camera)
    if not truck then return end
    local g=love.graphics
    local x,y,scale=0,0,1
    g.push('all')
    g.setCanvas(self.panel);g.origin();g.setScissor();g.setShader();g.setBlendMode('alpha')
    g.clear(0,0,0,0)
    g.setColor(1,1,1,1)
    g.draw(self.image,x,y,0,(1280/Cockpit.WIDTH)*scale,(880/Cockpit.HEIGHT)*scale)

    -- Compact digital readout sits just above the wheel and remains legible
    -- when the general HUD is hidden.
    local panelX,panelY,panelW,panelH=x+508*scale,y+666*scale,264*scale,40*scale
    g.setColor(.025,.045,.04,.94);g.rectangle('fill',panelX,panelY,panelW,panelH,5*scale)
    g.setColor(.30,.43,.36,.95);g.setLineWidth(math.max(.8,scale));g.rectangle('line',panelX,panelY,panelW,panelH,5*scale)
    local mph=(truck.speed or 0)*2.236936
    g.setColor(.96,.85,.51,1);g.printf(('SPEED  %02d MPH'):format(math.floor(mph+.5)),panelX+10*scale,panelY+7*scale,116*scale,'left')
    g.setColor(truck.engine==false and .78 or .40,truck.engine==false and .53 or .90,.53,1)
    g.printf(truck.engine==false and 'ENGINE OFF' or 'ENGINE RUN',panelX+132*scale,panelY+7*scale,122*scale,'right')

    local function lamp(cx,cy,on,label)
        g.setColor(on and 1 or .27,on and .70 or .31,on and .20 or .24,on and .96 or .8)
        g.circle('fill',cx,cy,3.3*scale)
        g.setColor(.78,.84,.73,.88);g.print(label,cx+6*scale,cy-6*scale)
    end
    lamp(panelX+17*scale,panelY+31*scale,truck.headlight==true,'HEADLIGHT')
    lamp(panelX+106*scale,panelY+31*scale,truck.headlightHighBeam==true,'HIGH')
    lamp(panelX+166*scale,panelY+31*scale,truck.turnSignal=='left','L')
    lamp(panelX+205*scale,panelY+31*scale,truck.turnSignal=='right','R')
    g.pop()
    drawInterior(self,camera,width,height)
    g.push('all')
    x,y,scale=transform(width,height)
    g.translate(x,y);g.scale(scale)
    g.setColor(1,1,1);g.setMeshCullMode('none');g.setDepthMode('always',false)
    g.setBlendMode('alpha','premultiplied')
    FP.send(cabEye(camera),self.shader);g.setShader(self.shader);g.draw(self.mesh)
    g.pop()
end

function Cockpit:release()
    self.image:release()
    self.mesh:release();self.panel:release();self.shader:release()
    self.interiorShader:release()
    for _,entry in ipairs(self.interiorPanels) do entry.mesh:release() end
    for _,image in pairs(self.interiorImages) do image:release() end
end

return Cockpit
