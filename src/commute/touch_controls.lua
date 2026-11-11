local B=require('src.commute.bindings')
local Icons=require('src.commute.ui_icons')
local Cockpit=require('src.commute.cockpit')
local TruckCockpit=require('src.commute.truck_cockpit')
local Beacon=require('src.interaction_beacon')
local Touch={};Touch.__index=Touch
local DEADZONE=.16
local RESPONSE_POWER=1.65
local DEFAULT_TOUCH={accelerate='touch1',brake='touch2',boost='touch3',interact='touch4',worldAction='touch6'}

local function clamp(value,lo,hi) return math.max(lo,math.min(hi,value)) end
local function horizontalExtent(width,bounds)
    if bounds and bounds.left and bounds.right then
        return bounds.left,bounds.right,bounds.right-bounds.left
    end
    return 0,width,width
end
local function horizontalPoint(point,width,bounds)
    local left,_,span=horizontalExtent(width,bounds)
    return left+point.x*span
end
local function shape(x,y,deadzone,power,sensitivity)
    local length=math.sqrt(x*x+y*y)
    if length<=deadzone then return 0,0 end
    sensitivity=clamp(tonumber(sensitivity) or 100,50,150)
    power=power*(2-sensitivity/100)
    local magnitude=math.min(1,(length-deadzone)/(1-deadzone))^power
    return x/length*magnitude,y/length*magnitude
end
local function touchPoint(p,id,width,height,left,right,bounds)
    local token=p.touch and p.touch[id]
    if not token or token=='' then token=DEFAULT_TOUCH[id] end
    local point=token and p.layout[token]
    if not point and DEFAULT_TOUCH[id] then point=p.layout[DEFAULT_TOUCH[id]] end
    if not point then return horizontalPoint({x=.90},width,bounds),height*.70 end
    local x=horizontalPoint(point,width,bounds)
    if left and math.abs(point.x-B.TOUCH_LEFT)<1e-7 then x=left
    elseif right and math.abs(point.x-B.TOUCH_RIGHT)<1e-7 then x=right end
    return x,point.y*height
end
local function addButton(buttons,id,label,icon,x,y,radius,active,enabled,hitRadius)
    buttons[#buttons+1]={action=id,label=label,icon=icon,x=x,y=y,radius=radius,
        hitRadius=hitRadius or radius*1.32,active=active==true,enabled=enabled~=false}
end

local function stickPoint(p)
    return p and p.layout and p.layout.stick or {x=.10,y=.80}
end

local function driveUtilityFits(buttons,x,y,r,gx,gy,scale)
    local dx=math.max(0,math.abs(x-gx)-48*scale)
    local dy=math.max(0,math.abs(y-gy)-23*scale)
    if dx*dx+dy*dy<r*r then return false end
    for _,other in ipairs(buttons) do
        if not other.physical and (x-other.x)^2+(y-other.y)^2<(r+other.hitRadius)^2 then return false end
    end
    return true
end

local function addGearButtons(buttons,items,width,height,radius,left,right,screenLeft,screenRight)
    local manual=#items>2
    if manual then radius=clamp(math.min(width,height)*.028,13,22) end
    local hit=radius*1.32
    local spacing=hit*2+4
    local bottom=manual and height-hit-4 or height*.90
    local gx,gy,scale=Cockpit.throttleGrip(width,height)
    for i,item in ipairs(items) do
        local column=(i-1)%2
        local y=bottom-(manual and i<=2 and spacing or 0)
        local x=column==0 and left or right
        -- Honor a player's remapped controls if they already occupy this row.
        if not driveUtilityFits(buttons,x,y,hit,gx,gy,scale) then
            local found=false
            for row=0,2 do
                local candidateY=y-row*spacing
                for _,candidateX in ipairs({right,left,screenLeft+(screenRight-screenLeft)*.77,
                    screenLeft+(screenRight-screenLeft)*.67}) do
                    if driveUtilityFits(buttons,candidateX,candidateY,hit,gx,gy,scale) then
                        x,y,found=candidateX,candidateY,true;break
                    end
                end
                if found then break end
            end
        end
        addButton(buttons,item[1],item[2],item[3],x,y,radius,item[4],item[5])
    end
end

function Touch.new()
    return setmetatable({contacts={},held={},x=0,y=0,horizontalX=0,cameraX=0,cameraY=0,visible=false},Touch)
end
function Touch:cancel()
    self.contacts={};self.held={};self.x=0;self.y=0;self.horizontalX=0;self.cameraX=0;self.cameraY=0
    self.aimX,self.aimY=0,0
    self.gripId,self.gripGas=nil,0
end

-- These same hit targets are drawn for mouse and touch, so the visible labels
-- always correspond to the controls that actually receive input.
function Touch.actionButtons(width,height,p,context,options)
    context=context or {};options=options or {}
    local mobile=options.mobile==true
    local bounds=mobile and options.bounds or nil
    local screenLeft,screenRight,screenWidth=horizontalExtent(width,bounds)
    local mounted=context.mounted~=false
    local rideLayout=mounted or mobile
    local minDim=math.min(width,height)
    local mainRadius=rideLayout and clamp(minDim*.052,23,40) or clamp(minDim*.042,20,32)
    local actionRadius=rideLayout and clamp(minDim*.045,20,34) or clamp(minDim*.036,18,29)
    local cameraRadius=rideLayout and clamp(minDim*.040,19,30) or clamp(minDim*.034,17,26)
    local utilityRadius=rideLayout and clamp(minDim*.038,18,27) or clamp(minDim*.031,17,24)
    local gasRadius=clamp(minDim*.066,30,51)
    local pad=clamp(minDim*.0065,3,6)
    local left,right
    if mounted then
        -- Fit both round targets inside the screen and leave a gutter between
        -- GO and GET OFF even on narrow phones.
        right=math.min(screenLeft+screenWidth*B.TOUCH_RIGHT,screenRight-mainRadius-pad-3)
        left=math.min(screenLeft+screenWidth*B.TOUCH_LEFT,right-gasRadius-actionRadius-2*pad-4)
    end
    local buttons={}

    if mounted then
        local x,y=touchPoint(p,'accelerate',width,height,left,right,bounds)
        local margin=gasRadius+pad+1
        x,y=clamp(x,screenLeft+margin,screenRight-margin),clamp(y,margin,height-margin)
        addButton(buttons,'accelerate','GO','throttle',x,y,gasRadius,false,true,gasRadius+pad)
        x,y=touchPoint(p,'brake',width,height,left,right,bounds)
        addButton(buttons,'brake','BRAKE','brake',x,y,mainRadius,false,true,mainRadius+pad)
        x,y=touchPoint(p,'interact',width,height,left,right,bounds)
        addButton(buttons,'interact',context.vehicle=='truck' and 'EXIT' or 'GET OFF','dismount',
            x,y,actionRadius,false,not context.gearTransition,actionRadius+pad)
        if context.worldActionLabel then
            x,y=touchPoint(p,'worldAction',width,height,nil,nil,bounds)
            addButton(buttons,'worldAction',context.worldActionLabel,'more',x,y,actionRadius,false,
                not context.gearTransition and not context.pedCrash)
        end
        if context.vehicle~='truck' then
            x,y=touchPoint(p,'boost',width,height,left,right,bounds)
            local hit=actionRadius+pad
            local gas=buttons[1]
            local gap=gas.hitRadius+hit+pad
            if (x-gas.x)^2+(y-gas.y)^2<gap^2 then
                local gx,gy,scale=Cockpit.throttleGrip(width,height)
                local best=math.huge
                local bx,by=x,y
                for _,offset in ipairs({{0,-1},{-1,0},{0,1},{1,0},{-1,-1},{-1,1},{1,-1},{1,1}}) do
                    local px,py=gas.x+offset[1]*gap,gas.y+offset[2]*gap
                    local distance=(px-x)^2+(py-y)^2
                    if distance<best and px>=screenLeft+hit and px<=screenRight-hit and py>=hit and py<=height-hit
                        and driveUtilityFits(buttons,px,py,hit,gx,gy,scale) then
                        bx,by,best=px,py,distance
                    end
                end
                x,y=bx,by
            end
            addButton(buttons,'boost','BOOST','boost',x,y,actionRadius,false,true,hit)
        end
        local states={
            horn={label='HORN',icon='horn',active=context.horn==true},
            beam={label=context.headlightHighBeam and 'HI' or 'LO',icon='headlight',active=context.headlightHighBeam==true},
            ignition={label=context.engine and 'RUN' or 'OFF',icon='ignition',active=context.engine==true},
            headlight={label=context.headlight and 'ON' or 'OFF',icon='headlight',active=context.headlight==true},
        }
        if context.vehicle=='truck' then
            for _,control in ipairs(TruckCockpit.controls(width,height,options.camera,context)) do
                buttons[#buttons+1]={action=control.action,label=control.label,icon=control.icon,
                    x=control.x,y=control.y,radius=control.visualRadius,hitRadius=control.hitRadius,
                    active=control.active,enabled=not context.gearTransition,physical=true}
            end
        else
            for _,control in ipairs(Cockpit.handlebarControls(width,height,options.camera)) do
                local state=states[control.action]
                buttons[#buttons+1]={action=control.action,label=state.label,icon=state.icon,
                    x=control.x,y=control.y,radius=control.visualRadius,hitRadius=mobile and 25 or 15,
                    active=state.active,enabled=not context.gearTransition,physical=true}
            end
        end
    else
        local x,y=touchPoint(p,'interact',width,height,nil,nil,bounds)
        local vehicleActionAvailable=context.nearBike or context.nearTruck
        local worldActionAvailable=context.worldActionLabel~=nil
        if vehicleActionAvailable then
            addButton(buttons,'interact',context.vehicleActionLabel or 'GET ON','dismount',
                x,y,actionRadius,false,not context.gearTransition and not context.pedCrash)
        end
        if worldActionAvailable then
            x,y=touchPoint(p,'worldAction',width,height,nil,nil,bounds)
            addButton(buttons,'worldAction',context.worldActionLabel,'more',x,y,actionRadius,false,
                not context.gearTransition and not context.pedCrash)
        end
        if mobile and not context.arrived then
            x,y=touchPoint(p,'boost',width,height,nil,nil,bounds)
            addButton(buttons,'boost','SPRINT','boost',x,y,actionRadius,false,
                not context.gearTransition and not context.pedCrash)
        end
    end

    -- Keep these clear of the top-right menus, minimap and throttle controls.
    local cameraY=(context.controlsTop or (mobile and 208 or 246))+cameraRadius
    local cameraX=(context.controlsTop and (context.cardX or Cockpit.CARD_X) or screenLeft+16)+cameraRadius
    if not context.cameraMenu then
        addButton(buttons,'followCamera',context.outsideMode=='follow' and 'FIXED' or 'FOLLOW',
            'follow',cameraX,cameraY,cameraRadius,context.outsideMode=='follow',true)
        addButton(buttons,'recenter','CENTER','center',cameraX+cameraRadius*2.8,cameraY,
            cameraRadius,false,true)
        cameraX=cameraX+cameraRadius*5.6
    end
    addButton(buttons,'rescue','RESCUE','center',cameraX,cameraY,
        cameraRadius,false,not context.gearTransition and not context.pedCrash and not context.arrived)
    if mobile and mounted and context.vehicle and not context.arrived then
        local stick=p.layout.stick or {x=.10,y=.80}
        local toggleX=clamp(horizontalPoint(stick,width,bounds),screenLeft+cameraRadius+pad,
            screenRight-cameraRadius-pad)
        local toggleY=clamp((cameraY+stick.y*height)*.5,cameraRadius+pad,height-cameraRadius-pad)
        addButton(buttons,'steeringMode',context.steeringHorizontal and 'HORIZ' or 'RADIAL',
            'steer',toggleX,toggleY,cameraRadius,context.steeringHorizontal==true,
            not context.gearTransition,cameraRadius+pad)
    end

    local utilities={}
    if mounted and context.vehicle~='truck' then
        utilities={
            {'transmission',context.transmission=='manual' and 'MANUAL' or 'AUTO',
                'transmission',context.transmission=='manual'},
            {'reverse',context.reverse and 'FWD' or 'REV','reverse',context.reverse},
        }
        if context.transmission=='manual' then
            utilities[#utilities+1]={'shiftDown','DOWN','shift',false}
            utilities[#utilities+1]={'shiftUp','UP','shift',false}
        end
    elseif not mounted and not context.arrived and context.gearNearBike then
        local label=context.gearTransition and 'WAIT' or context.gearOutfit=='geared' and 'REMOVE' or 'GEAR'
        utilities={{'gear',label,'helmet',context.gearOutfit=='geared',not context.gearTransition}}
    end
    if mounted and #utilities>0 then
        addGearButtons(buttons,utilities,width,height,utilityRadius,left,right,screenLeft,screenRight)
    elseif #utilities>0 then
        local rowScale=math.min(1.25,width*.64/720,height*.32/230)
        local cockpitTop=height-230*rowScale
        local y=math.max(minDim*.50,cockpitTop-utilityRadius-12)
        if bounds then y=math.min(y,height*.54) end
        local spacing=math.max(utilityRadius*2+7,math.min(width*.08,72))
        local left=bounds and screenRight-utilityRadius-24-(#utilities-1)*spacing
            or (width-(#utilities-1)*spacing)*.5
        for i,item in ipairs(utilities) do
            addButton(buttons,item[1],item[2],item[3],left+(i-1)*spacing,y,utilityRadius,
                item[4],item[5])
        end
    end
    if options.hiddenHud then
        local filtered={}
        for _,button in ipairs(buttons) do
            if button.action~='view' and button.action~='followCamera' and button.action~='recenter' then
                filtered[#filtered+1]=button
            end
        end
        return filtered
    end
    return buttons
end

function Touch.actionAt(x,y,width,height,p,context,options)
    local buttons=Touch.actionButtons(width,height,p,context,options)
    local nearestPhysical,nearestDistance
    for i=#buttons,1,-1 do
        local button=buttons[i];local dx,dy=x-button.x,y-button.y
        local distance=dx*dx+dy*dy
        if distance<=button.hitRadius*button.hitRadius then
            if button.physical then
                if not nearestDistance or distance<nearestDistance then nearestPhysical,nearestDistance=button,distance end
            else return button end
        end
    end
    return nearestPhysical
end

function Touch:move(id,x,y,width,height,p,sensitivity,bounds)
    local c=self.contacts[id];if not c then return false end
    if c.stick then
        local point=stickPoint(p);local radius=math.min(width,height)*.09
        local dx,dy=(x-horizontalPoint(point,width,bounds))/radius,(y-point.y*height)/radius
        self.x,self.y=shape(dx,dy,DEADZONE,RESPONSE_POWER,sensitivity)
        -- Horizontal vehicle mode ignores vertical thumb drift when steering.
        self.horizontalX=select(1,shape(dx,0,DEADZONE,RESPONSE_POWER,sensitivity))
        self.aimX,self.aimY=shape(dx,dy,.10,1)
    elseif c.grip then
        self.gripGas=clamp((y-c.startY-3*c.scale)/(48*c.scale),0,1)
    end
    return true
end

function Touch:press(id,x,y,width,height,p,perform,context,options)
    self.visible=true
    context=context or {};options=options or {mobile=true}
    local button=Touch.actionAt(x,y,width,height,p,context,options)
    if button then
        self.contacts[id]={action=button.action}
        if button.enabled then
            local spec=B.byId[button.action]
            if spec and spec.held then self.held[button.action]=true
            else perform(button.action) end
        end
        return true
    end
    local radius=math.min(width,height)*.045
    local point=stickPoint(p)
    local dx,dy=x-horizontalPoint(point,width,options.bounds),y-point.y*height
    local hitRadius=radius*2.2
    if dx*dx+dy*dy<=hitRadius*hitRadius then
        for _,contact in pairs(self.contacts) do if contact.stick then return true end end
        self.contacts[id]={stick=true};return self:move(id,x,y,width,height,p,
            options.stickSensitivity,options.bounds)
    end
    if context.mounted and not context.gearTransition and options.allowGrip~=false
        and options.mobile and options.camera and (not options.hiddenHud or options.camera.firstPerson) then
        local gx,gy,scale=Cockpit.throttleGrip(width,height,options.camera)
        if gx and math.abs(x-gx)<=48*scale and math.abs(y-gy)<=23*scale then
            if self.gripId then return true end
            self.contacts[id]={grip=true,startY=y,scale=scale}
            self.gripId,self.gripGas=id,0
            return true
        end
    end
    return false
end

function Touch:release(id)
    local c=self.contacts[id];if not c then return false end
    self.contacts[id]=nil
    if c.stick then self.x,self.y,self.horizontalX,self.aimX,self.aimY=0,0,0,0,0 end
    if c.grip then self.gripId,self.gripGas=nil,0 end
    if c.action then
        self.held[c.action]=nil
        for _,other in pairs(self.contacts) do if other.action==c.action then self.held[c.action]=true end end
    end
    return true
end

local function fontFor(self,size)
    self.fonts=self.fonts or {}
    size=math.max(8,math.floor(size+.5))
    if not self.fonts[size] then
        self.fonts[size]=love.graphics.newFont(size)
        self.fonts[size]:setFilter('linear','linear')
    end
    return self.fonts[size]
end

-- Every visible pixel in the 960 registered mounted views is within 94
-- world-render pixels of the wheel anchor at zoom 1, including rotation.
function Touch:drawAim(camera,bike,truck)
    local x,y=self.aimX or 0,self.aimY or 0
    local length=math.sqrt(x*x+y*y)
    if length==0 then return end
    x,y=x/length,y/length
    local cx,cy,scale
    if camera.shoulderView then
        local eye=camera.shoulderView
        if not eye.riderSpriteScale then return end
        -- Keep the diamond clear of the actual registered sprite as it banks.
        cx,cy,scale=eye.riderSpriteX,eye.riderSpriteY,eye.riderSpriteScale
    else
        cx,cy=camera:screen(bike.x,bike.z,bike.h);scale=camera.zoom
    end
    local reach=(truck and 150 or 96)*scale+26
    if truck then cy=cy-65*scale end
    Beacon.drawDirectionGem(cx+x*reach,cy+y*reach,math.atan2(y,x))
end

function Touch:draw(width,height,p,context,options)
    context=context or {};options=options or {}
    local mobile=options.mobile==true
    local showStick=mobile or self.visible or p.showTouch
    local showActions=options.showActions~=false or self.visible or p.showTouch
    if not showStick and not showActions then return end
    local g=love.graphics;g.push('all')
    local minDim=math.min(width,height);local radius=minDim*.045
    if showStick then
        local stick=p.layout.stick;local cx,cy=horizontalPoint(stick,width,options.bounds),stick.y*height
        local horizontal=options.horizontalSteering==true and context.mounted
        local aim=not horizontal and context.mounted and B.freeCameraTouch(mobile,options.camera)
        local knobX,knobY=self.x,self.y
        if aim then knobX,knobY=self.aimX or 0,self.aimY or 0 end
        if horizontal then knobX,knobY=self.horizontalX or self.x,0 end
        g.setColor(.025,.055,.045,.84);g.circle('fill',cx,cy,radius*2)
        g.setColor(.72,.81,.61,.94);g.setLineWidth(2);g.circle('line',cx,cy,radius*2)
        if horizontal then
            g.setColor(.72,.81,.61,.72);g.setLineWidth(2)
            g.line(cx-radius*1.35,cy,cx+radius*1.35,cy)
            g.circle('fill',cx-radius*1.35,cy,2.5);g.circle('fill',cx+radius*1.35,cy,2.5)
        end
        g.setColor(.72,.84,.53,.98);g.circle('fill',cx+knobX*radius*1.5,cy+knobY*radius*1.5,radius*.52)
        Icons.draw('steer',cx,cy-radius*1.20,radius*.68)
        g.setColor(.92,.95,.84,.98);g.setFont(fontFor(self,math.max(10,radius*.42)))
        local stickLabel=horizontal and (context.vehicle=='truck' and 'STEER' or 'LEAN') or 'STEER'
        g.printf(stickLabel,cx-radius*2,cy+radius*2.15,radius*4,'center')
        local gx,gy,scale
        if mobile and context.mounted and options.camera then gx,gy,scale=Cockpit.throttleGrip(width,height,options.camera) end
        if gx then
            g.setColor(.92,.89,.75,.82)
            local label=self.gripId and ('GAS %d%%'):format(math.floor(self.gripGas*100+.5)) or 'PULL FOR GAS'
            g.printf(label,gx-55*scale,gy+24*scale,110*scale,'center')
        end
    end
    if showActions then
        for _,button in ipairs(Touch.actionButtons(width,height,p,context,options)) do
            local cx,cy,r=button.x,button.y,button.radius
            local active=button.active or self.held[button.action]
            if button.physical then
                if button.action=='horn' then
                    local cap=math.max(3,r*.46);local cyPressed=cy+(active and r*.10 or 0)
                    g.setColor(.02,.025,.02,.56);g.circle('fill',cx,cyPressed+cap*.15,cap*1.13)
                    g.setColor(active and .98 or .68,active and .45 or .20,active and .10 or .09,.88)
                    g.circle('fill',cx,cyPressed,cap)
                    g.setColor(1,.80,.48,active and .92 or .53);g.setLineWidth(math.max(.7,r*.08))
                    g.circle('line',cx,cyPressed,cap*.87)
                elseif button.action=='signalLeft' or button.action=='signalRight' then
                    local cap=math.max(5,r*.62)
                    g.setColor(.02,.025,.02,.58);g.circle('fill',cx,cy+cap*.15,cap*1.12)
                    g.setColor(active and 1 or .40,active and .68 or .43,active and .18 or .22,.96)
                    g.circle('fill',cx,cy,cap)
                    g.setColor(1,.88,.61,active and .98 or .62);g.setLineWidth(math.max(1,r*.10))
                    g.circle('line',cx,cy,cap*.87)
                    local direction=button.action=='signalLeft' and -1 or 1
                    g.polygon('fill',cx+direction*cap*.28,cy-cap*.43,
                        cx-direction*cap*.40,cy,cx+direction*cap*.28,cy+cap*.43)
                    g.setColor(.10,.12,.09,active and 1 or .82)
                    g.line(cx-direction*cap*.30,cy,cx+direction*cap*.36,cy)
                elseif button.action:sub(1,5)=='radio' then
                    local cap=math.max(5,r*.62)
                    g.setColor(.02,.025,.02,.58);g.circle('fill',cx,cy+cap*.15,cap*1.12)
                    g.setColor(active and .18 or .08,active and .72 or .39,active and .47 or .31,.96)
                    g.circle('fill',cx,cy,cap)
                    g.setColor(1,.88,.61,active and .98 or .70);g.setLineWidth(math.max(1,r*.10))
                    g.circle('line',cx,cy,cap*.87)
                    local glyph=button.action=='radioPrevious' and '<<'
                        or button.action=='radioNext' and '>>'
                        or button.action=='radioMute' and 'M' or active and '||' or '>'
                    g.setColor(1,.91,.72,1);g.setFont(fontFor(self,clamp(r*.62,7,10)))
                    g.printf(glyph,cx-cap,cy-cap*.50,cap*2,'center')
                else
                    local width=math.max(4,r*.66);local height=math.max(6,r*1.22)
                    local travel=button.action=='beam' and (active and -.17 or .17)
                        or (active and .17 or -.17)
                    local knobY=cy+height*travel+(active and r*.06 or 0)
                    local knobColor=button.action=='ignition' and (active and {.35,.79,.40} or {.48,.19,.13})
                        or button.action=='headlight' and (active and {.96,.82,.42} or {.30,.34,.29})
                        or (active and {.98,.79,.30} or {.50,.59,.45})
                    g.setColor(.025,.03,.025,.58);g.rectangle('fill',cx-width*.42,knobY-height*.34+1,width*.84,height*.68,math.max(1,r*.12))
                    g.setColor(knobColor[1],knobColor[2],knobColor[3],.88)
                    g.rectangle('fill',cx-width*.34,knobY-height*.34,width*.68,height*.68,math.max(1,r*.10))
                    g.setColor(1,.88,.59,active and .9 or .48)
                    g.rectangle('line',cx-width*.30,knobY-height*.29,width*.60,height*.58,math.max(1,r*.09))
                end
            else
                if not button.enabled then g.setColor(.055,.075,.068,.72)
                else g.setColor(active and .15 or .035,active and .20 or .075,active and .13 or .06,.94) end
                g.circle('fill',cx,cy,r)
                if not button.enabled then g.setColor(.43,.49,.44,.64)
                elseif active then g.setColor(.96,.79,.42,1)
                else g.setColor(.74,.84,.64,.96) end
                g.setLineWidth(active and 2.4 or 1.6);g.circle('line',cx,cy,r)
                local iconSize=r*(r>30 and .88 or .78)
                local iconY=cy-r*.20
                if button.enabled then Icons.draw(button.icon,cx,iconY,iconSize)
                else Icons.draw(button.icon,cx,iconY,iconSize,{.55,.61,.54,.72}) end
                g.setColor(button.enabled and .96 or .61,button.enabled and .96 or .66,
                    button.enabled and .87 or .60,button.enabled and 1 or .82)
                g.setFont(fontFor(self,clamp(r*.31,8,12)))
                g.printf(button.label,cx-r*1.15,cy+r*.25,r*2.3,'center')
            end
        end
    end
    g.pop()
end

return Touch
