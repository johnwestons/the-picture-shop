-- Shared 960x678 options panel for the game and the isolated ride preview.
local B=require('src.commute.bindings')
local Screen={};Screen.__index=Screen
local function inside(x,y,rx,ry,w,h) return x>=rx and y>=ry and x<=rx+w and y<=ry+h end
function Screen.new(settings,save,close)
    settings.motorcycleControls=B.normalize(settings.motorcycleControls)
    return setmetatable({settings=settings,save=save,close=close,device='keyboard',page=1,selected=1,
        message='Select a binding to change it. Conflicts swap assignments.'},Screen)
end
function Screen:profile() return self.settings.motorcycleControls end
function Screen:rows()
    local rows={}
    if self.device=='mouse' then for _,id in ipairs({'orbit','pan','zoomIn','zoomOut'}) do rows[#rows+1]=B.byId[id] end end
    for _,a in ipairs(B.actions) do
        if (not a.modifier or self.device=='keyboard') and (not a.mouseOnly or self.device=='mouse')
            and not (self.device=='mouse' and (a.mouseOnly or a.id=='zoomIn' or a.id=='zoomOut')) then rows[#rows+1]=a end
    end
    return rows
end
function Screen:persist(message)
    self.message=self.save() and (message or 'Controls saved.') or 'Active this session, but could not save controls.'
end
function Screen:bind(token)
    local okay,message=B.assign(self:profile(),self.device,self.capture,token)
    if okay then self.capture=nil;self:persist(message) else self.message=message end
    return true
end
function Screen:keypressed(key)
    if self.capture then
        if key=='escape' or key=='f10' then self.capture=nil;self.message='Binding cancelled.'
        elseif key=='delete' then self:bind('')
        elseif self.device=='keyboard' then self:bind(key) end
        return true
    end
    if key=='escape' or key=='f10' then self.close();return true end
    if key=='tab' then
        local i=1;for n,d in ipairs(B.devices) do if d==self.device then i=n end end
        self.device=B.devices[i%4+1];self.page=1;self.selected=1;self.layout=false
    elseif key=='left' or key=='pageup' then self.page=math.max(1,self.page-1);self.selected=1
    elseif key=='right' or key=='pagedown' then self.page=math.min(math.ceil(#self:rows()/9),self.page+1);self.selected=1
    elseif key=='up' then self.selected=math.max(1,self.selected-1)
    elseif key=='down' then self.selected=math.min(9,#self:rows()-(self.page-1)*9,self.selected+1)
    elseif key=='return' or key=='space' then
        local a=self:rows()[(self.page-1)*9+self.selected];if a then self.capture=a.id end
    end
    return true
end
function Screen:gamepadpressed(_,button)
    if self.capture and button=='start' then self.capture=nil;self.message='Binding cancelled.';return true end
    if self.capture and self.device=='controller' then return self:bind(button) end
    if self.capture then if button=='start' then self.capture=nil end;return true end
    local key=({a='return',b='escape',start='escape',dpup='up',dpdown='down',dpleft='left',dpright='right',rightshoulder='tab'})[button]
    if key then return self:keypressed(key) end;return true
end
function Screen:gamepadaxis(_,axis,value)
    if self.capture and self.device=='controller' and math.abs(value)>.65 then return self:bind('axis:'..axis..(value<0 and '-' or '+')) end
    return true
end
function Screen:wheelmoved(_,y)
    if self.capture and self.device=='mouse' and y~=0 then return self:bind(y>0 and 'wheelup' or 'wheeldown') end
    return true
end
function Screen:mousepressed(x,y,button)
    if self.capture then
        if self.device=='mouse' and button~=1 then return self:bind('mouse'..button) end
        if button==1 and inside(x,y,720,598,140,36) then self.capture=nil;return true end
        if button==1 and inside(x,y,540,598,160,36) then return self:bind('') end
        if self.device=='touch' and button==1 then
            for i=1,6 do if inside(x,y,125+(i-1)*120,540,110,42) then return self:bind('touch'..i) end end
        end
        return true
    end
    if button~=1 then return true end
    if inside(x,y,790,24,120,38) then self.close();return true end
    for i,d in ipairs(B.devices) do if inside(x,y,70+(i-1)*210,82,200,42) then
        self.device=d;self.page=1;self.selected=1;self.layout=false;return true end end
    if inside(x,y,70,590,160,40) then
        self.settings.motorcycleControls=B.defaults();self:persist('All motorcycle controls restored to defaults.');return true
    end
    if self.device=='touch' and inside(x,y,250,590,180,40) then self.layout=not self.layout;return true end
    if self.device=='touch' and inside(x,y,450,590,200,40) then
        self:profile().showTouch=not self:profile().showTouch;self:persist();return true
    end
    if self.layout then
        for id,p in pairs(self:profile().layout) do
            if (x-(100+p.x*760))^2+(y-(165+p.y*380))^2<28^2 then self.drag=id;return true end
        end
    else
        for i=1,9 do if inside(x,y,70,154+(i-1)*43,820,39) then
            local a=self:rows()[(self.page-1)*9+i]
            if a then self.selected=i;self.capture=a.id end;return true
        end end
        if inside(x,y,710,548,70,30) then self:keypressed('left')
        elseif inside(x,y,810,548,80,30) then self:keypressed('right') end
    end
    return true
end
function Screen:mousemoved(x,y)
    if self.drag then
        local margin=self.drag=='stick' and .10 or .06
        self:profile().layout[self.drag]={x=math.max(margin,math.min(1-margin,(x-100)/760)),y=math.max(margin,math.min(1-margin,(y-165)/380))}
    end
    return true
end
function Screen:mousereleased()
    if self.drag then self.drag=nil;self:persist('Touch layout saved.') end
    return true
end
function Screen:draw()
    local g=love.graphics;g.push('all');g.clear(.045,.055,.058)
    local function box(x,y,w,h,text,active)
        g.setColor(active and .26 or .12,.20,.17);g.rectangle('fill',x,y,w,h,5)
        g.setColor(.92,.94,.80);g.printf(text,x+5,y+11,w-10,'center')
    end
    g.setColor(1,.85,.4);g.print('MOTORCYCLE CONTROLS',70,30)
    box(790,24,120,38,'BACK')
    for i,d in ipairs(B.devices) do box(70+(i-1)*210,82,200,42,d:upper(),d==self.device) end
    if self.layout then
        g.setColor(.09,.13,.12);g.rectangle('fill',100,165,760,380)
        for id,p in pairs(self:profile().layout) do
            g.setColor(.75,.85,.60);g.circle('line',100+p.x*760,165+p.y*380,24)
            g.printf(id=='stick' and 'STEER' or id:sub(-1),70+p.x*760,158+p.y*380,60,'center')
        end
        g.setColor(.9,.92,.85);g.print('Drag the steering pad and six buttons to reposition them.',100,140)
    else
        for i=1,9 do local a=self:rows()[(self.page-1)*9+i]
            if a then
                local y=154+(i-1)*43;box(70,y,820,39,'',i==self.selected)
                g.setColor(.92,.94,.80);g.print(a.label,88,y+11)
                g.printf(B.label(self:profile()[self.device][a.id]),490,y+11,380,'center')
            end
        end
        g.setColor(.8,.85,.78);g.print(('Page %d / %d'):format(self.page,math.ceil(#self:rows()/9)),580,558)
        box(710,548,70,30,'<');box(810,548,80,30,'>')
    end
    box(70,590,160,40,'RESET ALL')
    if self.device=='touch' then box(250,590,180,40,self.layout and 'ASSIGN BUTTONS' or 'EDIT LAYOUT');box(450,590,200,40,self:profile().showTouch and 'HIDE TOUCH OVERLAY' or 'SHOW TOUCH OVERLAY') end
    g.setColor(.85,.90,.80);g.printf(self.message,70,642,820,'center')
    if self.capture then
        g.setColor(.025,.04,.035,.97);g.rectangle('fill',65,430,830,205,7)
        g.setColor(1,.85,.4);g.printf('Assign '..B.byId[self.capture].label,85,449,790,'center')
        g.setColor(.9,.95,.85)
        local prompt=({keyboard='Press a key.',mouse='Press a mouse button (except left-click) or scroll the wheel.',controller='Press a controller button or move an axis past halfway.',touch='Choose an on-screen button below.'})[self.device]
        g.printf(prompt..'  Esc cancels; Delete clears.',85,478,790,'center')
        g.printf(self.message,85,507,790,'center')
        if self.device=='touch' then for i=1,6 do box(125+(i-1)*120,540,110,42,'BUTTON '..i) end end
        box(540,598,160,36,'CLEAR');box(720,598,140,36,'CANCEL')
    end
    g.pop()
end
return Screen
