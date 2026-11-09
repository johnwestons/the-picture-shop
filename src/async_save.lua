local Schema=require("src.save_schema")
local Writer={}
Writer.__index=Writer

-- Check whether the live state can be sent through a Channel as-is. Channel
-- serialization detaches its message before push returns, so building a second
-- Lua table tree here would copy every saved field twice on the gameplay thread.
-- Keep schema normalization in the worker; normalize on the main thread only
-- when transient values make the state unsuitable for a channel.
local function channelSafe(value,active)
    local kind=type(value)
    if kind=="boolean" or kind=="number" or kind=="string" then return true end
    if kind~="table" then return false end
    active=active or {}
    if active[value] then return false end
    active[value]=true
    for key,item in pairs(value) do
        local keyType=type(key)
        if keyType~="boolean" and keyType~="number" and keyType~="string" then
            active[value]=nil
            return false
        end
        if not channelSafe(item,active) then
            active[value]=nil
            return false
        end
    end
    active[value]=nil
    return true
end

function Writer.new(store)
    return setmetatable({store=store,waiting={},notices={},threads=setmetatable({}, {__mode="k"})},Writer)
end
function Writer:pending() return self.active~=nil or #self.waiting>0 end
function Writer:start()
    if self.thread then return end
    self.requests,self.results=love.thread.newChannel(),love.thread.newChannel()
    self.thread=love.thread.newThread("src/workers/save.lua")
    self.threads[self.thread]=true
    self.thread:start(self.requests,self.results)
end
function Writer:dispatch()
    if self.active or #self.waiting==0 then return end
    if not self.flushing and self.retryAfter and love.timer.getTime()<self.retryAfter then return end
    local job=table.remove(self.waiting,1)
    local snapshot=channelSafe(job.state) and job.state or nil
    local reason
    if not snapshot then snapshot,reason=Schema.snapshot(job.state) end
    if not snapshot then
        self.retryAfter=love.timer.getTime()+5
        self.notices[#self.notices+1]={directory=job.directory,slot=job.slot,okay=false,reason=reason or "invalid_snapshot"}
        return
    end
    -- Channels copy detached data; workers never read mutable gameplay tables.
    self:start()
    self.active={directory=job.directory,slot=job.slot}
    self.requests:push({kind="save",directory=job.directory,slot=job.slot,state=snapshot,world=job.world})
end
function Writer:queue(slot,state,world)
    if not Schema.validSlot(slot) or type(state)~="table" then return false,"invalid_save_request" end
    local directory=love.filesystem.getSaveDirectory()
    if self.directory~=directory then
        if not love.filesystem.createDirectory("saves") then return false,"save_directory_unavailable" end
        self.directory=directory
    end
    local job={directory=directory,slot=slot,state=state,
        world={x=world and world.x,y=world and world.y,sceneId=world and world.sceneId}}
    for index,old in ipairs(self.waiting) do
        if old.directory==job.directory and old.slot==slot then
            self.waiting[index]=job
            return true
        end
    end
    self.waiting[#self.waiting+1]=job
    self:dispatch()
    return true
end
function Writer:poll()
    if self.results then
        local result=self.results:pop()
        if result then
            self.active=nil
            if not result.okay then
                self.directory=nil;self.retryAfter=love.timer.getTime()+5
            else self.retryAfter=nil end
            self.store.invalidate(result.slot)
            self.notices[#self.notices+1]=result
        end
        local reason=self.thread:getError()
        if reason then
            self.retryAfter=love.timer.getTime()+5
            if self.active then
                self.active.okay,self.active.reason=false,reason
                self.notices[#self.notices+1]=self.active
            end
            self.active,self.thread,self.requests,self.results=nil,nil,nil,nil
        end
    end
    self:dispatch()
    local notices=self.notices;self.notices={}
    return notices
end
function Writer:flush()
    self.flushing=true
    local okay,reason=true,nil
    while self:pending() do
        for _,result in ipairs(self:poll()) do
            if not result.okay then okay,reason=false,result.reason end
        end
        if self.active then love.timer.sleep(.001) end
    end
    for _,result in ipairs(self:poll()) do
        if not result.okay then okay,reason=false,result.reason end
    end
    self.flushing=nil
    return okay,reason
end
function Writer:shutdown()
    local okay,reason=self:flush()
    if self.thread then self.requests:push({kind="stop"});self.thread:wait() end
    self.thread,self.requests,self.results=nil,nil,nil
    return okay,reason
end
return Writer
