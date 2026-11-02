local B=require('src.commute.bindings')
local Touch={};Touch.__index=Touch
function Touch.new() return setmetatable({contacts={},held={},x=0,y=0,visible=false},Touch) end
function Touch:cancel() self.contacts={};self.held={};self.x=0;self.y=0 end
function Touch:move(id,x,y,width,height,p)
    local c=self.contacts[id];if not c then return false end
    if c.stick then
        local point=p.layout.stick;local radius=math.min(width,height)*.09
        local dx,dy=(x-point.x*width)/radius,(y-point.y*height)/radius
        local length=math.sqrt(dx*dx+dy*dy)
        self.x,self.y=dx/math.max(1,length),dy/math.max(1,length)
    end
    return true
end
function Touch:press(id,x,y,width,height,p,perform)
    self.visible=true
    local radius=math.min(width,height)*.045
    for i=1,6 do
        local token='touch'..i;local point=p.layout[token]
        if (x-point.x*width)^2+(y-point.y*height)^2<=radius^2 then
            local action=B.action(p,'touch',token)
            self.contacts[id]={action=action}
            if action then
                if B.byId[action].held then self.held[action]=true else perform(action) end
            end
            return true
        end
    end
    local point=p.layout.stick
    if (x-point.x*width)^2+(y-point.y*height)^2<=(radius*2.2)^2 then
        for _,c in pairs(self.contacts) do if c.stick then return true end end
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
function Touch:draw(width,height,p)
    if not self.visible and not p.showTouch then return end
    local g=love.graphics;g.push('all')
    local radius=math.min(width,height)*.045
    local stick=p.layout.stick
    g.setColor(.08,.12,.10,.65);g.circle('fill',stick.x*width,stick.y*height,radius*2)
    g.setColor(.75,.82,.65,.8);g.circle('line',stick.x*width,stick.y*height,radius*2)
    g.circle('fill',stick.x*width+self.x*radius*1.5,stick.y*height+self.y*radius*1.5,radius*.5)
    for i=1,6 do
        local token='touch'..i;local point=p.layout[token];local id=B.action(p,'touch',token)
        g.setColor(.08,.12,.10,.85);g.circle('fill',point.x*width,point.y*height,radius)
        g.setColor(id and self.held[id] and 1 or .8,.85,.60);g.circle('line',point.x*width,point.y*height,radius)
        local label=id and ({accelerate='GO',brake='BRAKE',boost='BOOST',interact='USE',headlight='LIGHT',view='VIEW'})[id]
            or id and B.byId[id].label or tostring(i)
        g.printf(label,point.x*width-radius,point.y*height-7,radius*2,'center')
    end
    g.pop()
end
return Touch
