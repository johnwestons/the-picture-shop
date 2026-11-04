-- Full-resolution 64-view poses, paged so phones do not upload every atlas.
-- A page contains sixteen unchanged 320px cells. Logical direction stays 1..64.
local Pages={FRAME=320,PAGE_SIZE=1280,VIEWS=64,VIEWS_PER_PAGE=16,MAX_CACHED_PAGES=12}
Pages.__index=Pages
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
    local self=setmetatable({cache={},imageInfo={},quads={},clock=0,count=0,peakCount=0},Pages)
    for i=0,15 do self.quads[i+1]=love.graphics.newQuad(i%4*320,math.floor(i/4)*320,320,320,1280,1280) end
    return self
end
function Pages:get(state,frame)
    assert(known[state] and frame%1==0 and frame>=1 and frame<=64,'Invalid motorcycle action view')
    local page=math.floor((frame-1)/16)+1;local key=state..':'..page
    self.clock=self.clock+1
    local entry=self.cache[key]
    if not entry then
        if self.count>=Pages.MAX_CACHED_PAGES then
            local oldestKey,oldest
            for candidate,value in pairs(self.cache) do
                if not oldest or value.used<oldest.used then oldestKey,oldest=candidate,value end
            end
            self.imageInfo[oldest.image]=nil;oldest.image:release();self.cache[oldestKey]=nil
            self.count=self.count-1
        end
        local path=Pages.path(state,page);local image=love.graphics.newImage(path)
        assert(image:getWidth()==1280 and image:getHeight()==1280,'Invalid motorcycle action page: '..path)
        image:setFilter('linear','linear')
        entry={image=image,used=self.clock,state=state,page=page};self.cache[key]=entry
        self.imageInfo[image]=entry;self.count=self.count+1;self.peakCount=math.max(self.peakCount,self.count)
    end
    entry.used=self.clock
    return entry.image,self.quads[(frame-1)%16+1],page
end
function Pages:prepare(action,frame)
    if not known[action] then return end
    action=action:gsub('Mid$','')
    self:get(action..'Mid',frame);self:get(action,frame)
end
function Pages:describe(image,quad)
    local entry=self.imageInfo[image];if not entry then return nil end
    local x,y=quad:getViewport()
    return {state=entry.state,frame=(entry.page-1)*16+y/320*4+x/320+1,page=entry.page}
end
function Pages:release()
    for _,entry in pairs(self.cache) do entry.image:release() end
    for _,quad in ipairs(self.quads) do quad:release() end
    self.cache={};self.imageInfo={};self.quads={};self.count=0
end
return Pages
