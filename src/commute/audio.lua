-- Presentation-only motorcycle mixer. No saved state or network commands.
local Audio={};Audio.__index=Audio
local root='assets/audio/commute/'
local bands={1400,3000,5000,7500}
local loops={'engine-1400','engine-3000','engine-5000','engine-7500','wind','tires','intake','brake','nature'}
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
function Audio.partBike(part)
    local bike,visual=part.rider.bike,part.presentation
    if not visual then return bike end
    local model=require('src.commute.motorcycle')
    local speed=part.rider.gear.mounted and (visual.speed or 0) or 0
    local gear=bike.gear or 1
    return {speed=speed,gear=gear,rpm=bike.reverse and model.IDLE_RPM+speed*500 or clamp(model.REDLINE*speed/model.GEARS[gear].speed,model.IDLE_RPM,model.REDLINE),
        throttle=visual.throttle,shiftTime=visual.shiftTime,impactPulse=visual.impactPulse,impactStrength=visual.impactStrength}
end
function Audio.new()
    return setmetatable({sources={},errors={},master=1,sfx=.85,ambient=.42,
        muted=false,paused=false,loaded=false,rpm=1400,speed=0,load=0,fade=0,
        engine=false,impact=0,cooldown=0},Audio)
end
function Audio:loadSources()
    if self.loaded then return end;self.loaded=true
    if not love or not love.audio then return end
    local function load(name,loop)
        local path=name=='nature' and root..'forest-ambience.mp3' or root..name..'.wav'
        local ok,source=pcall(love.audio.newSource,path,name=='nature' and 'stream' or 'static')
        if ok then source:setLooping(loop);source:setVolume(0);self.sources[name]=source
        else self.errors[#self.errors+1]=path..': '..tostring(source);print('[COMMUTE AUDIO] '..self.errors[#self.errors]) end
    end
    for _,name in ipairs(loops) do load(name,true) end
    for _,name in ipairs({'ignition','shutdown','shift','impact'}) do load(name,false) end
end
function Audio:setLevels(master,sfx,ambient)
    self.master=clamp(master or self.master,0,1);self.sfx=clamp(sfx or self.sfx,0,1)
    self.ambient=clamp(ambient or self.ambient,0,1)
    if self.master==0 then for _,s in pairs(self.sources) do s:setVolume(0) end end
end
function Audio:setMuted(muted)
    self.muted=muted==true
    if self.muted then for _,s in pairs(self.sources) do s:stop() end end
end
function Audio:setPaused(paused)
    self.paused=paused==true
    if self.paused then for _,s in pairs(self.sources) do s:stop() end end
end
function Audio:cue(name,volume)
    local s=self.sources[name]
    if not s or self.muted or self.paused then return end
    s:stop();s:setVolume(self.master*self.sfx*volume);s:play()
end
function Audio:loop(name,volume,pitch,ambient)
    local s=self.sources[name];if not s then return end
    volume=volume*self.master*(ambient and self.ambient or self.sfx)
    s:setVolume(volume);s:setPitch(clamp(pitch or 1,.4,2.5))
    if volume>.0001 then if not s:isPlaying() then s:play() end
    elseif s:isPlaying() then s:pause() end
end
function Audio:update(dt,bike,engine,options)
    options=options or {};self:loadSources()
    dt=clamp(dt or 0,0,.1)
    if self.paused then return end
    bike=bike or {};engine=engine==true
    self.cooldown=math.max(0,self.cooldown-dt)
    if engine~=self.engine then self:cue(engine and 'ignition' or 'shutdown',.40) end
    if engine and self.engine and self.gear and self.gear~=bike.gear then self:cue('shift',.22) end
    local impact=bike.impactPulse or 0
    if impact>self.impact+.08 and self.cooldown==0 then
        self:cue('impact',.25+.2*(bike.impactStrength or 0));self.cooldown=.5
    end
    self.engine,self.gear,self.impact=engine,bike.gear,impact
    if self.muted then return end
    local blend=1-math.exp(-dt*12)
    self.rpm=self.rpm+(clamp(bike.rpm or 1400,1400,8000)-self.rpm)*blend
    self.speed=self.speed+(math.abs(bike.speed or 0)-self.speed)*blend
    self.load=self.load+((bike.throttle or 0)-self.load)*blend
    self.fade=self.fade+((engine and 1 or 0)-self.fade)*(1-math.exp(-dt*5))
    local speed=clamp(self.speed/14.4,0,1)
    local gearDip=(bike.shiftTime or 0)>0 and .60 or 1
    for i,base in ipairs(bands) do
        local weight
        if self.rpm<=base then weight=i==1 and 1 or clamp((self.rpm-bands[i-1])/(base-bands[i-1]),0,1)
        else weight=i==#bands and 1 or clamp((bands[i+1]-self.rpm)/(bands[i+1]-base),0,1) end
        self:loop('engine-'..base,math.sqrt(weight)*self.fade*(.28+.26*self.load)*gearDip,self.rpm/base)
    end
    self:loop('intake',self.fade*self.load*.12*(.4+speed),.85+self.rpm/12000)
    self:loop('wind',speed^1.7*.27, .8+speed*.35,true)
    self:loop('tires',speed*.14, .65+speed*.65)
    local brake=options.brake or bike.brake or 0
    self:loop('brake',clamp(brake,0,1)*speed*.12, .85+speed*.25)
    self:loop('nature',(.22-.13*speed)*(options.outdoors==false and 0 or 1),1,true)
end
function Audio:release()
    for _,s in pairs(self.sources) do s:stop();s:release() end
    self.sources={};self.loaded=false;self.engine=false;self.gear=nil
end
return Audio
