-- Transient external forces only. Calm, untouched plants have exactly zero sway.
-- This clock advances with the simulation, so menus/focus pause all responses.
local M=require('src.commute.vendor.mathx')
local Flora=require('src.commute.vendor.flora')
local Life=require('src.commute.vendor.lifecycle')
local Motion={};Motion.__index=Motion
Motion.MAX_SWAY=.065
local reach=Flora.spriteReach
local flexibility={grass=1.1,strawberry=1,sumac=.7,bramble=.7,oak=.12,pine=.12,
    redbud=.12,blueberry=.7,milkweed=.95,dogwood=.16,persimmon=.12,
    ['chickasaw-plum']=.72,['little-bluestem']=1.08,['blue-phlox']=.9,
    bloodroot=.7,['virginia-bluebells']=.92,['wild-columbine']=.9,
    ['purple-coneflower']=.8,['wild-bergamot']=1.0,['cardinal-flower']=1.08,
    ['new-england-aster']=.9,['common-goldenrod']=.94}
function Motion.new(world,options)
    options=options or {}
    local rng=M.random(world.seed+5813)
    return setmetatable({world=world,time=0,responses={},wind=nil,rng=rng,
        automaticWind=options.automaticWind~=false,nextGust=18+rng()*14},Motion)
end
function Motion:gust(strength,duration,direction)
    if not M.finite(strength) or strength<=0 or strength>1 or not M.finite(duration)
        or duration<=0 or duration>10 or not M.finite(direction or 1) then return false end
    self.wind={start=self.time,duration=duration,strength=strength,direction=(direction or 1)<0 and -1 or 1}
    return true
end
function Motion:update(dt)
    self.time=self.time+dt
    if self.wind and self.time>=self.wind.start+self.wind.duration then self.wind=nil end
    if self.automaticWind and self.time>=self.nextGust then
        self:gust(.35+self.rng()*.4,3+self.rng()*3,self.rng()<.5 and -1 or 1)
        self.nextGust=self.time+self.wind.duration+18+self.rng()*17
    end
    -- Analytic damped spring: a new touch adds force without snapping the pose.
    local damping,frequency=5,14
    local w=math.sqrt(frequency^2-damping^2)
    local fade,c,s=math.exp(-damping*dt),math.cos(w*dt),math.sin(w*dt)
    for id,r in pairs(self.responses) do
        local x,v=r.x,r.v
        r.x=fade*(x*c+(v+damping*x)/w*s)
        r.v=fade*(v*c-(damping*v+frequency^2*x)/w*s)
        if self.time-r.last>1.5 and math.abs(r.x)+math.abs(r.v)<.0001 then self.responses[id]=nil end
    end
end
function Motion:hasSway()
    return self.wind~=nil or next(self.responses)~=nil
end
function Motion:disturb(p,strength,direction)
    if not Flora.types[p.kind] or p.lifePhase~='live' or not Flora.appearance(p,self.world.calendar)
        or not M.finite(strength) or strength<=0 then return false end
    local response=self.responses[p.id]
    if not response then response={x=0,v=0,last=-math.huge};self.responses[p.id]=response end
    if self.time-response.last<.22 then return false end
    response.last=self.time
    local sign=(direction or 1)<0 and -1 or 1
    response.v=M.clamp(response.v+sign*math.min(1,strength)*.65*flexibility[p.kind],-.8,.8)
    return true
end
function Motion:brush(actor,beforeX,beforeZ)
    local dx,dz=actor.x-beforeX,actor.z-beforeZ
    local distance=M.length(dx,dz)
    if distance<1e-5 then return end
    local radius=actor.radius or .25;local padding=radius+1.2
    self.world:eachProp(math.min(beforeX,actor.x)-padding,math.min(beforeZ,actor.z)-padding,
        math.max(beforeX,actor.x)+padding,math.max(beforeZ,actor.z)+padding,function(p)
            if reach[p.kind] then
                local u=M.clamp(((p.x-beforeX)*dx+(p.z-beforeZ)*dz)/distance^2,0,1)
                local x,z=beforeX+dx*u,beforeZ+dz*u
                local contact=radius+reach[p.kind]*p.scale*Life.plantScale(p,self.world.ageDays)
                if (p.x-x)^2+(p.z-z)^2<contact^2 then
                    self:disturb(p,math.min(1,M.length(actor.vx or 0,actor.vz or 0)/2),dx+dz*.45)
                end
            end
        end)
end
function Motion:sway(p)
    if not flexibility[p.kind] or p.lifePhase~='live' then return 0 end
    local response=self.responses[p.id];local sway=response and response.x or 0
    if self.wind then
        local wind=self.wind;local progress=(self.time-wind.start)/wind.duration
        if progress>0 and progress<1 then
            local envelope=math.sin(progress*math.pi)^2
            local phase=(p.x+p.z)*.18
            sway=sway+wind.direction*wind.strength*envelope*(.7+.3*math.sin(progress*math.pi*3+phase))
                *.018*((p.kind=='oak' or p.kind=='pine' or p.kind=='redbud' or p.kind=='dogwood' or p.kind=='persimmon') and .6 or flexibility[p.kind])
        end
    end
    return M.clamp(sway,-Motion.MAX_SWAY,Motion.MAX_SWAY)
end
return Motion
