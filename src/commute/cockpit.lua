-- Sprite artwork with live instrument graphics. All measurements use a 720px cockpit.
local Bike=require('src.commute.motorcycle')
local M=require('src.commute.vendor.mathx')
local Gauge=require('src.commute.fuel_gauge')
local Service=require('src.commute.bike_service')
local Status=require('src.screens.player_status')
local HUD={MAX_MPH=80,CONDITION_BIKE_FRAME=5,CARD_X=18,CARD_Y=72,CARD_WIDTH=242,CARD_HEIGHT=82};HUD.__index=HUD
function HUD.syncLayout(R)
    local _,bounds
    if R.optionsAccessLayout then _,bounds=R.optionsAccessLayout() end
    bounds=bounds or {left=0,right=R.Config and R.Config.baseWidth or require('src.config').baseWidth}
    local rect=Status.layout(bounds)
    HUD.CARD_Y=rect.y+rect.height+6
end
local outsideInstruments={cx=360,cy=83.5,r=42,gearX=429,gearY=65,gearW=69,gearScale=1,
    fuelX=267,fuelY=87,fuelR=20}
function HUD.conditionLabel(bike)
    local damage=bike.damage or 0
    if damage==0 then return '' end
    if damage==100 then return '  ·  Bike condition 0% (5 mph)' end
    return ('  ·  Bike condition %d%%'):format(100-damage)
end
-- The message is optional. The desktop key hint takes one extra line before
-- the first clickable control. Drawing and hit testing share this layout.
function HUD.infoLayout(mobile,note)
    local noteY=HUD.CARD_Y+HUD.CARD_HEIGHT+6
    local hintY=noteY+(note and note~='' and 33 or 0)
    return noteY,hintY,hintY+(mobile and 0 or 21)
end
function HUD.drawCondition(bike,x,y,bikeArt)
    local g=love.graphics;local damage=M.clamp((bike and bike.damage or 0)/100,0,1)
    local condition=math.floor((1-damage)*100+.5)
    local fuel,fraction,low,beam=Gauge.read(bike)
    local miles=bike.service and bike.service.miles or 0
    local width=HUD.CARD_WIDTH
    g.push('all');g.setFont(require('src.screens.typography').get(14))
    g.setColor(.025,.04,.035,.9);g.rectangle('fill',x,y,width,HUD.CARD_HEIGHT,6)
    g.setColor(.34,.40,.34,.9);g.setLineWidth(1);g.rectangle('line',x,y,width,HUD.CARD_HEIGHT,6)
    if bikeArt then
        local image,quad=bikeArt:resolve('parked',HUD.CONDITION_BIKE_FRAME)
        g.setColor(1,1,1,1)
        g.draw(image,quad,x-2,y-4,0,42/320,42/320)
    end
    local conditionText='CONDITION '..condition..'%'..(condition==0 and ' · 5 mph' or '')
    g.setColor(.94,.93,.82);Status.printLine(conditionText,x+34,y+5,128)
    g.setColor(.83,.9,.84);Status.printLine(('%.1f mi'):format(miles),x+170,y+5,66)
    g.setColor(.19,.22,.19);g.rectangle('fill',x+34,y+23,width-42,5,2)
    g.setColor(damage>.7 and .92 or .65,damage>.7 and .45 or .77,.45)
    g.rectangle('fill',x+34,y+23,(width-42)*(1-damage),5,2)
    g.setColor(.92,.91,.80);g.print('FUEL',x+8,y+33)
    g.printf(('%.1f / %.1f L'):format(fuel,Service.tank),x+62,y+33,width-70,'right')
    g.setColor(.19,.22,.19);g.rectangle('fill',x+8,y+50,width-16,5,2)
    g.setColor(low and 1 or .88,low and .54 or .76,.34);g.rectangle('fill',x+8,y+50,(width-16)*fraction,5,2)
    g.setColor(beam=='off' and .67 or .84,.85,beam=='high' and 1 or .73);g.print(Gauge.beamLabels[beam],x+8,y+59)
    if low then g.setColor(1,.67,.28);g.printf('LOW FUEL',x+98,y+59,width-106,'right') end
    g.pop()
end
function HUD.riderHint(rider,visual)
    if rider.gear.mounted and not rider.gear.engine then
        if rider.bike.service and rider.bike.service.fuel<=0 then return 'Out of fuel. Walk to the gas station for a refill.' end
        if require('src.commute.bike_service').rough(rider.bike)>.1 then return 'Engine stopped. Use the ignition to restart and visit the gas station for service.' end
    end
    if rider.ped.crash or visual and visual.pose=='crash' then
        return 'Thrown from the bike. Get back on your feet, then walk over and remount.'
    end
    if rider.gear.mounted and (visual or rider.bike).grounded==false then
        return 'Airborne  ·  Throttle lifts the front wheel. Brake helps level the bike.'
    end
end
function HUD.new()
    local self=setmetatable({image=love.graphics.newImage('assets/commute/cockpit/handlebars-fuel-v2.png'),fonts={}},HUD)
    self.image:setFilter('linear','linear')
    for _,size in ipairs({10,14,16,24}) do
        self.fonts[size]=require('src.screens.typography').get(size);self.fonts[size]:setFilter('linear','linear')
    end
    return self
end
-- Eager use is optional so callers can put cold artwork/target creation in a
-- visible loading phase. The ordinary draw path retains lazy compatibility.
function HUD:prewarmFirstPerson()
    if not self.firstPersonBike then self.firstPersonBike=require('src.commute.first_person_bike').new() end
    return self.firstPersonBike
end
function HUD.layout(width,height)
    local scale=math.min(1.25,width*.64/720,height*.32/230)
    return (width-720*scale)*.5,height-230*scale,scale
end
-- Registration on the rubber grip in the 720-pixel outside cockpit artwork.
local eyeGrip={{action='grip',firstPersonX=874,firstPersonY=299}}
function HUD.throttleGrip(width,height,camera)
    if camera and camera.firstPerson then
        local grip=require('src.commute.first_person_bike').projectControls(camera,width,height,eyeGrip)[1]
        if grip then return grip.x,grip.y,M.clamp(grip.visualRadius/9.92,.5,1.25) end
        return nil
    end
    local ox,oy,scale=HUD.layout(width,height)
    return ox+652*scale,oy+156*scale,scale
end
HUD.handlebarControlSpecs={
    {action='horn',outsideX=150,outsideY=144,firstPersonX=247,firstPersonY=264},
    {action='beam',outsideX=171,outsideY=132,firstPersonX=252,firstPersonY=298},
    {action='ignition',outsideX=556,outsideY=132,firstPersonX=770,firstPersonY=265},
    {action='headlight',outsideX=578,outsideY=148,firstPersonX=770,firstPersonY=300},
}
function HUD.handlebarControls(width,height,camera)
    if camera and camera.firstPerson then
        return require('src.commute.first_person_bike').projectControls(camera,width,height,HUD.handlebarControlSpecs)
    end
    local ox,oy,scale=HUD.layout(width,height);local result={}
    for _,spec in ipairs(HUD.handlebarControlSpecs) do
        result[#result+1]={action=spec.action,x=ox+spec.outsideX*scale,y=oy+spec.outsideY*scale,
            visualRadius=8*scale}
    end
    return result
end
function HUD.keyAt(x,y,width,height,bike,visual,camera)
    -- Retained for compatibility; actions now use the shared visible button layout.
end
function HUD.telemetry(bike,engine,visual)
    local speed=visual and visual.speed or bike.speed or 0
    local gear=bike.gear or 1
    local fuel,fraction,low,beam=Gauge.read(bike)
    return {speed=speed,mph=speed*2.236936,gear=gear,mode=bike.transmission or 'automatic',
        fuel=fuel,fuelFraction=fraction,lowFuel=low,beam=beam,
        reverse=bike.reverse==true,headlight=bike.headlight==true,
        rpm=engine and Bike.rpmForSpeed(bike,speed) or 0,
        grade=(visual and visual.grade or bike.grade or 0)*100,
        throttle=visual and visual.throttle or bike.throttle or 0,
        boost=visual and visual.boost or bike.boosting or false,
        shifting=(visual and visual.shiftTime or bike.shiftTime or 0)>0}
end
function HUD:drawInstruments(t,engine,bike,visual,firstPerson,registration)
    local g=love.graphics
    registration=registration or outsideInstruments
    Gauge.draw(t,registration,self.fonts[10])
    local function label(text,x,y,w,size)
        g.setFont(self.fonts[size]);g.printf(text,x,y,w,'center')
    end
    local cx,cy,r=registration.cx,registration.cy,registration.r
    g.setColor(.85,.85,.69);g.setLineWidth(1)
    for value=0,HUD.MAX_MPH,4 do
        local angle=math.rad(135+value*270/HUD.MAX_MPH)
        local major=value%20==0;local inner=r-(major and 7 or 3)
        g.line(cx+math.cos(angle)*inner,cy+math.sin(angle)*inner,cx+math.cos(angle)*r,cy+math.sin(angle)*r)
        if major then label(tostring(value),cx+math.cos(angle)*29-10,cy+math.sin(angle)*29-5,20,10) end
    end
    local angle=math.rad(135+math.min(HUD.MAX_MPH,t.mph)*270/HUD.MAX_MPH)
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
        self:prewarmFirstPerson():draw(camera,width,height,function(registration)
            self:drawInstruments(t,engine,bike,visual,true,registration)
        end,bike.paintId)
    end
    g.push('all');g.translate(ox,oy);g.scale(scale)
    if not firstPerson then
        g.setColor(1,1,1);g.draw(self.image,0,0,0,720/self.image:getWidth())
        self:drawInstruments(t,engine,bike,visual,false)
    end
    g.pop()
end
function HUD:release()
    if self.firstPersonBike then self.firstPersonBike:release() end
    self.image:release()
    -- Cached typography is shared with menus and survives this riding view.
    self.fonts={}
end
return HUD
