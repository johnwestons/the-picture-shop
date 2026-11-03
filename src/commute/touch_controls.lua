local B=require('src.commute.bindings')
local Icons=require('src.commute.ui_icons')
local Touch={};Touch.__index=Touch
local DEADZONE=.16
local RESPONSE_POWER=1.65
local DEFAULT_TOUCH={accelerate='touch1',brake='touch2',boost='touch3',interact='touch4'}

local function clamp(value,lo,hi) return math.max(lo,math.min(hi,value)) end
local function shape(x,y)
    local length=math.sqrt(x*x+y*y)
    if length<=DEADZONE then return 0,0 end
    local magnitude=math.min(1,(length-DEADZONE)/(1-DEADZONE))^RESPONSE_POWER
    return x/length*magnitude,y/length*magnitude
end
local function touchPoint(p,id,width,height)
    local token=p.touch and p.touch[id]
    if not token or token=='' then token=DEFAULT_TOUCH[id] end
    local point=token and p.layout[token]
    if not point and DEFAULT_TOUCH[id] then point=p.layout[DEFAULT_TOUCH[id]] end
    if not point then return width*.90,height*.70 end
    return point.x*width,point.y*height
end
local function addButton(buttons,id,label,icon,x,y,radius,active,enabled)
    buttons[#buttons+1]={action=id,label=label,icon=icon,x=x,y=y,radius=radius,
        hitRadius=radius*1.32,active=active==true,enabled=enabled~=false}
end

function Touch.new()
    return setmetatable({contacts={},held={},x=0,y=0,cameraX=0,cameraY=0,visible=false},Touch)
end
function Touch:cancel()
    self.contacts={};self.held={};self.x=0;self.y=0;self.cameraX=0;self.cameraY=0
end

-- These same hit targets are drawn for mouse and touch, so the visible labels
-- always correspond to the controls that actually receive input.
function Touch.actionButtons(width,height,p,context,options)
    context=context or {};options=options or {}
    local mobile=options.mobile==true
    local minDim=math.min(width,height)
    local mainRadius=mobile and clamp(minDim*.052,23,40) or clamp(minDim*.042,20,32)
    local actionRadius=mobile and clamp(minDim*.045,20,34) or clamp(minDim*.036,18,29)
    local cameraRadius=mobile and clamp(minDim*.040,19,30) or clamp(minDim*.034,17,26)
    local utilityRadius=mobile and clamp(minDim*.038,18,27) or clamp(minDim*.031,17,24)
    local buttons={}
    local mounted=context.mounted~=false

    if mounted then
        local x,y=touchPoint(p,'accelerate',width,height)
        addButton(buttons,'accelerate','GO','throttle',x,y,mainRadius,false,true)
        x,y=touchPoint(p,'brake',width,height)
        addButton(buttons,'brake','BRAKE','brake',x,y,mainRadius,false,true)
        x,y=touchPoint(p,'boost',width,height)
        addButton(buttons,'boost','BOOST','boost',x,y,actionRadius,false,true)
        x,y=touchPoint(p,'interact',width,height)
        addButton(buttons,'interact',context.arrived and 'FINISH' or 'GET OFF','dismount',
            x,y,actionRadius,false,not context.gearTransition)
    else
        local x,y=touchPoint(p,'interact',width,height)
        addButton(buttons,'interact',context.arrived and 'FINISH' or 'USE','dismount',
            x,y,actionRadius,false,not context.gearTransition)
    end

    local cameraY=math.max(58+32+cameraRadius+8,height*.23)
    local cameraX=width-cameraRadius*1.55
    addButton(buttons,'followCamera',context.outsideMode=='follow' and 'FIXED' or 'FOLLOW',
        'follow',cameraX,cameraY,cameraRadius,context.outsideMode=='follow',true)
    addButton(buttons,'recenter','CENTER','center',cameraX,cameraY+cameraRadius*2.8,
        cameraRadius,false,true)
    addButton(buttons,'rescue','RESCUE','center',cameraX,cameraY+cameraRadius*5.6,
        cameraRadius,false,not context.gearTransition and not context.pedCrash and not context.arrived)

    local utilities={}
    if mounted then
        utilities={
            {'ignition',context.engine and 'STOP' or 'START','ignition',context.engine},
            {'headlight','LIGHTS','headlight',context.headlight},
            {'transmission',context.transmission=='manual' and 'MANUAL' or 'AUTO',
                'transmission',context.transmission=='manual'},
            {'reverse',context.reverse and 'FWD' or 'REV','reverse',context.reverse},
        }
        if context.transmission=='manual' then
            utilities[#utilities+1]={'shiftDown','DOWN','shift',false}
            utilities[#utilities+1]={'shiftUp','UP','shift',false}
        end
    elseif not context.arrived then
        local label=context.gearTransition and 'WAIT' or context.gearOutfit=='geared' and 'REMOVE' or 'GEAR'
        utilities={{'gear',label,'helmet',context.gearOutfit=='geared',not context.gearTransition}}
    end
    if #utilities>0 then
        local rowScale=math.min(1.25,width*.64/720,height*.32/230)
        local cockpitTop=height-230*rowScale
        local y=math.max(minDim*.50,cockpitTop-utilityRadius-12)
        local spacing=math.max(utilityRadius*2+7,math.min(width*.08,72))
        local left=(width-(#utilities-1)*spacing)*.5
        for i,item in ipairs(utilities) do
            addButton(buttons,item[1],item[2],item[3],left+(i-1)*spacing,y,utilityRadius,
                item[4],item[5])
        end
    end
    return buttons
end

function Touch.actionAt(x,y,width,height,p,context,options)
    local buttons=Touch.actionButtons(width,height,p,context,options)
    for i=#buttons,1,-1 do
        local button=buttons[i];local dx,dy=x-button.x,y-button.y
        if dx*dx+dy*dy<=button.hitRadius*button.hitRadius then return button end
    end
end

function Touch:move(id,x,y,width,height,p)
    local c=self.contacts[id];if not c then return false end
    if c.stick then
        local point=p.layout.stick;local radius=math.min(width,height)*.09
        local dx,dy=(x-point.x*width)/radius,(y-point.y*height)/radius
        self.x,self.y=shape(dx,dy)
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
    local point=p.layout.stick
    local dx,dy=x-point.x*width,y-point.y*height
    local hitRadius=radius*2.2
    if dx*dx+dy*dy<=hitRadius*hitRadius then
        for _,contact in pairs(self.contacts) do if contact.stick then return true end end
        self.contacts[id]={stick=true};return self:move(id,x,y,width,height,p)
    end
    return false
end

function Touch:release(id)
    local c=self.contacts[id];if not c then return false end
    self.contacts[id]=nil
    if c.stick then self.x,self.y=0,0 end
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

function Touch:draw(width,height,p,context,options)
    context=context or {};options=options or {}
    local mobile=options.mobile==true
    local showStick=mobile or self.visible or p.showTouch
    local showActions=options.showActions~=false or self.visible or p.showTouch
    if not showStick and not showActions then return end
    local g=love.graphics;g.push('all')
    local minDim=math.min(width,height);local radius=minDim*.045
    if showStick then
        local stick=p.layout.stick;local cx,cy=stick.x*width,stick.y*height
        g.setColor(.025,.055,.045,.84);g.circle('fill',cx,cy,radius*2)
        g.setColor(.72,.81,.61,.94);g.setLineWidth(2);g.circle('line',cx,cy,radius*2)
        g.setColor(.72,.84,.53,.98);g.circle('fill',cx+self.x*radius*1.5,cy+self.y*radius*1.5,radius*.52)
        Icons.draw('steer',cx,cy-radius*1.20,radius*.68)
        g.setColor(.92,.95,.84,.98);g.setFont(fontFor(self,math.max(10,radius*.42)))
        g.printf('STEER',cx-radius,cy+radius*2.15,radius*2,'center')
    end
    if showActions then
        for _,button in ipairs(Touch.actionButtons(width,height,p,context,options)) do
            local cx,cy,r=button.x,button.y,button.radius
            local active=button.active or self.held[button.action]
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
    g.pop()
end

return Touch
