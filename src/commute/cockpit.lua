-- Sprite artwork with live instrument graphics. All measurements use a 720px cockpit.
local Bike=require('src.commute.motorcycle')
local M=require('src.commute.vendor.mathx')
local HUD={};HUD.__index=HUD
function HUD.new()
    local self=setmetatable({image=love.graphics.newImage('assets/commute/cockpit/handlebars.png'),fonts={}},HUD)
    self.image:setFilter('linear','linear')
    for _,size in ipairs({10,14,16,24}) do
        self.fonts[size]=love.graphics.newFont(size);self.fonts[size]:setFilter('linear','linear')
    end
    return self
end
function HUD.layout(width,height)
    local scale=math.min(1,width*.72/720,height*.38/300)
    return (width-720*scale)*.5,height-300*scale,scale
end
local buttons={{key='v',x=182,w=148,label='V  AUTO / MANUAL'},
    {key='z',x=336,w=98,label='Z  SHIFT −'},{key='x',x=440,w=98,label='X  SHIFT +'},
    {key='boost',x=18,w=148,label='LSHIFT  BOOST'},
    {key='p',x=552,w=150,label='P  FIRST PERSON'},
    {key='c',x=600,y=204,w=102,label='C CENTER',firstPerson=true},
    {key='i',x=148,w=106,y=184,parked=true,label='I  ENGINE'},
    {key='b',x=260,w=106,y=184,parked=true,label='B  REVERSE'},
    {key='h',x=372,w=106,y=184,parked=true,label='H  LIGHTS'},
    {key='e',x=484,w=106,y=184,parked=true,label='E  GET OFF'}}
function HUD.keyAt(x,y,width,height,bike,visual,camera)
    local ox,oy,scale=HUD.layout(width,height);x,y=(x-ox)/scale,(y-oy)/scale
    local stopped=not bike or (visual and visual.speed or bike.speed or 0)<=.05
    for _,b in ipairs(buttons) do
        local by=b.y or 258
        if (not b.firstPerson or camera and camera.firstPerson) and (not b.parked or stopped)
            and x>=b.x and x<=b.x+b.w and y>=by and y<=by+40 then return b.key end
    end
end
function HUD.telemetry(bike,engine,visual)
    local speed=visual and visual.speed or bike.speed or 0
    local gear=bike.gear or 1
    return {speed=speed,mph=speed*2.236936,gear=gear,mode=bike.transmission or 'automatic',
        reverse=bike.reverse==true,headlight=bike.headlight==true,
        rpm=engine and (bike.reverse and Bike.IDLE_RPM+speed*500 or M.clamp(Bike.REDLINE*speed/Bike.GEARS[gear].speed,Bike.IDLE_RPM,Bike.REDLINE)) or 0,
        grade=(visual and visual.grade or bike.grade or 0)*100,
        throttle=visual and visual.throttle or bike.throttle or 0,
        boost=visual and visual.boost or bike.boosting or false,
        shifting=(visual and visual.shiftTime or bike.shiftTime or 0)>0}
end
function HUD:drawInstruments(t,engine,bike,visual,firstPerson,registration)
    local g=love.graphics
    registration=registration or {cx=360,cy=83.5,r=42,gearX=429,gearY=65,gearW=69,gearScale=1}
    local function label(text,x,y,w,size)
        g.setFont(self.fonts[size]);g.printf(text,x,y,w,'center')
    end
    local cx,cy,r=registration.cx,registration.cy,registration.r
    g.setColor(.85,.85,.69);g.setLineWidth(1)
    for value=0,30,2 do
        local angle=math.rad(135+value*9)
        local major=value%10==0;local inner=r-(major and 7 or 3)
        g.line(cx+math.cos(angle)*inner,cy+math.sin(angle)*inner,cx+math.cos(angle)*r,cy+math.sin(angle)*r)
        if major then label(tostring(value),cx+math.cos(angle)*29-10,cy+math.sin(angle)*29-5,20,10) end
    end
    local angle=math.rad(135+math.min(30,t.mph)*9)
    g.setColor(1,.48,.21);g.setLineWidth(2)
    g.line(cx,cy,cx+math.cos(angle)*35,cy+math.sin(angle)*35);g.circle('fill',cx,cy,3)
    g.setColor(.94,.92,.74);label(('%02d'):format(math.floor(t.mph+.5)),cx-22,cy+11,44,16)
    label('mph',cx-20,cy+29,40,10)
    g.push();g.translate(registration.gearX,registration.gearY);g.scale(registration.gearScale)
    local gearWidth=registration.gearW/registration.gearScale
    g.setColor(engine and .85 or .55,engine and .94 or .58,.67)
    label(t.mode=='manual' and 'MANUAL' or 'AUTO',0,0,gearWidth,10)
    label(t.reverse and 'R' or engine and tostring(t.gear) or '—',0,10,gearWidth,24)
    if t.shifting then g.setColor(1,.7,.3);label('SHIFT',0,40,gearWidth,10) end
    g.pop()
    if firstPerson then
        -- Follow the speedometer's upper curve. The ball shows the actual
        -- bank angle (including recovery), rather than steering input.
        local radius,sweep=r+41,math.rad(50)
        local points={}
        for i=0,32 do
            local a=-math.pi*.5-sweep+2*sweep*i/32
            points[#points+1]=cx+math.cos(a)*radius
            points[#points+1]=cy+math.sin(a)*radius
        end
        g.setColor(.025,.04,.035,.94);g.setLineWidth(7);g.line(points)
        g.setColor(.45,.54,.46,.95);g.setLineWidth(3);g.line(points)
        local lean=visual and visual.lean or bike.lean or 0
        local a=-math.pi*.5+M.clamp(-lean/.36,-1,1)*sweep
        local bx,by=cx+math.cos(a)*radius,cy+math.sin(a)*radius
        g.setColor(.025,.04,.035);g.circle('fill',bx,by,6)
        g.setColor(.98,.68,.31);g.circle('fill',bx,by,4.5)
    end
end
function HUD:draw(bike,engine,width,height,visual,camera,bindings)
    local g=love.graphics;local ox,oy,scale=HUD.layout(width,height)
    local t=HUD.telemetry(bike,engine,visual)
    local firstPerson=camera and camera.firstPerson
    if firstPerson then
        if not self.firstPersonBike then self.firstPersonBike=require('src.commute.first_person_bike').new() end
        self.firstPersonBike:draw(camera,width,height,function(registration)
            self:drawInstruments(t,engine,bike,visual,true,registration)
        end)
    end
    g.push('all');g.translate(ox,oy);g.scale(scale)
    local function label(text,x,y,w,size)
        g.setFont(self.fonts[size]);g.printf(text,x,y,w,'center')
    end
    if not firstPerson then
        g.setColor(1,1,1);g.draw(self.image,0,0,0,720/self.image:getWidth())
        self:drawInstruments(t,engine,bike,visual,false)
    end
    g.setLineWidth(1)
    g.setColor(.025,.04,.035,.94);g.rectangle('fill',174,229,372,71,6)
    g.setColor(.84,.88,.75)
    label(('%d km/h   ·   %d rpm   ·   %+.0f%% grade'):format(t.speed*3.6,t.rpm,t.grade),182,232,356,14)
    g.setColor(.33,.38,.29);g.rectangle('fill',182,251,356,3)
    g.setColor(.66,.77,.40);g.rectangle('fill',182,251,356*t.throttle,3)
    for _,b in ipairs(buttons) do
        if not b.firstPerson or camera and camera.firstPerson then
        local enabled=b.parked and t.speed<=.05 or not b.parked and (b.key=='v' or b.key=='p' or b.key=='c' or b.key=='boost' and t.boost or t.mode=='manual')
        local by=b.y or 258
        local mx,my=g.inverseTransformPoint(love.mouse.getPosition())
        local hover=enabled and mx>=b.x and mx<=b.x+b.w and my>=by and my<=by+40
        g.setColor(hover and .25 or .12,hover and .31 or .17,hover and .20 or .13,.96);g.rectangle('fill',b.x,by,b.w,40,4)
        g.setColor(b.key=='boost' and t.boost and .96 or enabled and .92 or .48,
            b.key=='boost' and t.boost and .68 or enabled and .91 or .54,
            b.key=='boost' and t.boost and .32 or enabled and .73 or .44)
        local text=b.key=='i' and (engine and 'I  ENGINE OFF' or 'I  START')
            or b.key=='b' and (t.reverse and 'B  FORWARD' or 'B  REVERSE')
            or b.key=='h' and (t.headlight and 'H  LIGHTS OFF' or 'H  LIGHTS ON')
            or b.key=='p' and camera and camera.firstPerson and 'P  OUTSIDE VIEW' or b.label
        if bindings then
            local ids={v='transmission',z='shiftDown',x='shiftUp',boost='boost',p='view',c='recenter',i='ignition',b='reverse',h='headlight',e='interact'}
            local hint=require('src.commute.bindings').hint(bindings,ids[b.key])
            text=(hint=='Unbound' and '' or hint..'  ')..text:gsub('^%S+%s+','')
        end
        label(text,b.x,by+11,b.w,b.parked and 10 or 14)
        end
    end
    g.setColor(.9,.92,.75);label(t.speed<=.05 and 'PARKED — click controls or use your bindings' or 'Stop to use parked controls',148,168,442,10)
    g.pop()
end
function HUD:release()
    if self.firstPersonBike then self.firstPersonBike:release() end
    self.image:release();for _,font in pairs(self.fonts) do font:release() end
end
return HUD
