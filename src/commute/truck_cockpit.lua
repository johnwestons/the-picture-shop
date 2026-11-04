-- Driver-eye truck cab art, live instruments, and hit targets placed over the
-- corresponding physical switches in the transparent cab overlay.
local M=require('src.commute.vendor.mathx')
local Cockpit={PATH='assets/commute/truck/cockpit-overlay-v1.png',WIDTH=1536,HEIGHT=1024}
Cockpit.__index=Cockpit

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

function Cockpit.controls(width,height,camera,state)
    state=state or {}
    local x0,y0,scale=transform(width,height)
    local result={}
    for _,spec in ipairs(controls) do
        local x,y
        if camera and camera.firstPerson then
            x=x0+spec.assetX*(1280/Cockpit.WIDTH)*scale
            y=y0+spec.assetY*(880/Cockpit.HEIGHT)*scale
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
        result[#result+1]={action=spec.action,label=spec.label,icon=spec.icon,x=x,y=y,
            visualRadius=15*scale,hitRadius=26*scale,active=active}
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
    return setmetatable({image=image},Cockpit)
end

function Cockpit:draw(truck,width,height)
    if not truck then return end
    local g=love.graphics
    local x,y,scale=transform(width,height)
    g.push('all')
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
end

function Cockpit:release()
    self.image:release()
end

return Cockpit
