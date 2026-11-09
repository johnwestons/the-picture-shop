-- Four pages per view/livery keep a 64-angle truck within mobile texture limits.
local Pages={FRAME_COUNT=64,VIEWS_PER_PAGE=16,MAX_CACHED_PAGES=3}
Pages.__index=Pages

local formats={
    chase={width=640,height=384,anchorX=320,anchorY=352,scale=.42},
    isometric={width=384,height=384,anchorX=192,anchorY=316,scale=1},
}

local function path(kind,page)
    return ('assets/commute/truck/turntables/%s-64-%d.png'):format(kind,page)
end

function Pages.frame(angle)
    return math.floor(angle/(math.pi*2/Pages.FRAME_COUNT)+.5)%Pages.FRAME_COUNT+1
end

function Pages.new()
    return setmetatable({cache={},clock=0,quads={}},Pages)
end

function Pages:get(kind,frame)
    local format=assert(formats[kind],'Invalid truck view')
    assert(frame>=1 and frame<=Pages.FRAME_COUNT and frame%1==0,'Invalid truck frame')
    local page=math.floor((frame-1)/Pages.VIEWS_PER_PAGE)+1
    local key=kind..':'..page
    local entry=self.cache[key]
    if not entry then
        local filename=path(kind,page)
        assert(love.filesystem.getInfo(filename,'file'),'Missing 64-angle truck page: '..filename)
        local image=love.graphics.newImage(filename)
        assert(image:getWidth()==format.width*4 and image:getHeight()==format.height*4,
            'Invalid 64-angle truck page: '..filename)
        image:setFilter('linear','linear')
        entry={image=image}
        self.cache[key]=entry
    end
    self.clock=self.clock+1
    entry.used=self.clock
    local count=0
    for _ in pairs(self.cache) do count=count+1 end
    if count>Pages.MAX_CACHED_PAGES then
        local oldestKey,oldest
        for k,v in pairs(self.cache) do
            if k~=key and (not oldest or v.used<oldest.used) then oldestKey,oldest=k,v end
        end
        oldest.image:release()
        self.cache[oldestKey]=nil
    end
    local localFrame=(frame-1)%Pages.VIEWS_PER_PAGE
    local quadKey=kind..':'..localFrame
    local quad=self.quads[quadKey]
    if not quad then
        quad=love.graphics.newQuad(localFrame%4*format.width,
            math.floor(localFrame/4)*format.height,format.width,format.height,
            format.width*4,format.height*4)
        self.quads[quadKey]=quad
    end
    return entry.image,quad,format
end

function Pages:release()
    for _,entry in pairs(self.cache) do entry.image:release() end
    for _,quad in pairs(self.quads) do quad:release() end
    self.cache={};self.quads={}
end

return Pages
