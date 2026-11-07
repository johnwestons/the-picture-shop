-- Full-resolution 64-view poses, paged so phones do not upload every atlas.
-- A page contains sixteen unchanged 320px cells. Logical direction stays 1..64.
local Pages={FRAME=320,PAGE_SIZE=1280,VIEWS=64,VIEWS_PER_PAGE=16,MAX_CACHED_PAGES=12}
Pages.__index=Pages
local ImageLoader=require('src.image_loader')
Pages.states={'aeroMid','aero','boostMid','boost','brakeMid','brake','shiftMid','shift',
    'impactMid','impact','turnLeftMid','turnLeft','turnRightMid','turnRight'}
local known={};for _,state in ipairs(Pages.states) do known[state]=true end
function Pages.path(state,page)
    assert(known[state] and page%1==0 and page>=1 and page<=4,'Unknown motorcycle action page')
    return ('assets/commute/bike/actions-64/%s-%d.png'):format(state,page)
end
function Pages.new()
    -- Validate the complete package before displaying any action. A missing
    -- direction must fail explicitly instead of falling back to old art.
    for _,state in ipairs(Pages.states) do for page=1,4 do
        local path=Pages.path(state,page)
        assert(love.filesystem.getInfo(path,'file'),'Missing 64-view motorcycle action page: '..path)
    end end
    local self=setmetatable({cache={},imageInfo={},quads={},pending={},pendingCount=0,
        failed={},clock=0,count=0,peakCount=0},Pages)
    for i=0,15 do self.quads[i+1]=love.graphics.newQuad(i%4*320,math.floor(i/4)*320,320,320,1280,1280) end
    return self
end
local function clearPending(self,key)
    if self.pending[key] then
        self.pending[key]=nil
        self.pendingCount=math.max(0,self.pendingCount-1)
    end
end
function Pages:get(state,frame)
    assert(known[state] and frame%1==0 and frame>=1 and frame<=64,'Invalid motorcycle action view')
    local page=math.floor((frame-1)/16)+1;local key=state..':'..page
    self.clock=self.clock+1
    local entry=self.cache[key]
    local quad=self.quads[(frame-1)%16+1]
    if not entry then
        if self.failed[key] then return nil,quad,page,self.failed[key] end
        local path=Pages.path(state,page)
        local image,reason
        if ImageLoader.enabled then
            image,reason=ImageLoader.load(path)
            if not image then
                if reason=='pending' then
                    if not self.pending[key] then
                        self.pending[key]=path
                        self.pendingCount=self.pendingCount+1
                    end
                else
                    clearPending(self,key)
                    self.failed[key]=tostring(reason or 'Motorcycle action page failed to load')
                    ImageLoader.cancel(path)
                    print(('Motorcycle action page unavailable (%s): %s'):format(path,self.failed[key]))
                end
                return nil,quad,page,reason
            end
        else
            image=love.graphics.newImage(path)
        end
        clearPending(self,key)
        if image:getWidth()~=1280 or image:getHeight()~=1280 then
            image:release()
            error('Invalid motorcycle action page: '..path,2)
        end
        if self.count>=Pages.MAX_CACHED_PAGES then
            local oldestKey,oldest
            for candidate,value in pairs(self.cache) do
                if not oldest or value.used<oldest.used then oldestKey,oldest=candidate,value end
            end
            self.imageInfo[oldest.image]=nil;oldest.image:release();self.cache[oldestKey]=nil
            self.count=self.count-1
        end
        image:setFilter('linear','linear')
        entry={image=image,used=self.clock,state=state,page=page};self.cache[key]=entry
        self.imageInfo[image]=entry;self.count=self.count+1;self.peakCount=math.max(self.peakCount,self.count)
    end
    entry.used=self.clock
    return entry.image,quad,page
end
function Pages:prepare(action,frame)
    if not known[action] then return end
    action=action:gsub('Mid$','')
    self:get(action..'Mid',frame);self:get(action,frame)
end
function Pages:isResident(state,frame)
    if not known[state] or frame%1~=0 or frame<1 or frame>64 then return false end
    local page=math.floor((frame-1)/16)+1
    return self.cache[state..':'..page]~=nil
end
function Pages:describe(image,quad)
    local entry=self.imageInfo[image];if not entry then return nil end
    local x,y=quad:getViewport()
    return {state=entry.state,frame=(entry.page-1)*16+y/320*4+x/320+1,page=entry.page}
end
function Pages:release()
    for _,path in pairs(self.pending) do ImageLoader.cancel(path) end
    for _,entry in pairs(self.cache) do entry.image:release() end
    for _,quad in ipairs(self.quads) do quad:release() end
    self.cache={};self.imageInfo={};self.quads={};self.pending={};self.pendingCount=0
    self.failed={};self.count=0
end
return Pages
