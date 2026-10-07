-- Only inactive textures enter this cache. Active screen images stay pinned.
local Cache = {}
Cache.__index = Cache
local function release(image)
    if image and image.release then pcall(image.release, image) end
end
function Cache.new(maxBytes, lifetime, clock)
    return setmetatable({entries={},bytes=0,maxBytes=maxBytes,lifetime=lifetime,
        clock=clock or love.timer.getTime,sequence=0},Cache)
end
function Cache:remove(key, keep)
    local entry=self.entries[key]
    if not entry then return nil end
    self.entries[key]=nil;self.bytes=self.bytes-entry.bytes
    if not keep then release(entry.image) end
    return entry.image
end
function Cache:prune()
    local now=self.clock()
    for key,entry in pairs(self.entries) do
        if now-entry.at>=self.lifetime then self:remove(key) end
    end
    while self.bytes>self.maxBytes do
        local oldest,sequence=nil,math.huge
        for key,entry in pairs(self.entries) do
            if entry.sequence<sequence then oldest,sequence=key,entry.sequence end
        end
        if not oldest then break end
        self:remove(oldest)
    end
end
function Cache:put(key,image)
    self:remove(key)
    local width,height=image:getDimensions()
    local bytes=width*height*4
    if bytes>self.maxBytes then release(image);return end
    self.sequence=self.sequence+1
    self.entries[key]={image=image,bytes=bytes,at=self.clock(),sequence=self.sequence}
    self.bytes=self.bytes+bytes;self:prune()
end
function Cache:take(key)
    self:prune()
    return self:remove(key,true)
end
function Cache:clear()
    for key in pairs(self.entries) do self:remove(key) end
end
return Cache
