-- The kei truck's source pages are raw 4x4 contact sheets. Keep their
-- original dimensions and derive each cell boundary so odd-sized pages do
-- not crop the final row or column.
local Pages={FRAME_COUNT=64,VIEWS_PER_PAGE=16,MAX_CACHED_PAGES=3}
Pages.__index=Pages

function Pages.frame(angle)
    return math.floor(angle/(math.pi*2/Pages.FRAME_COUNT)+.5)%Pages.FRAME_COUNT+1
end

function Pages.new()
    return setmetatable({cache={},clock=0,quads={}},Pages)
end

function Pages:get(kind,frame)
    assert(kind=='chase' or kind=='isometric','Invalid kei truck view')
    assert(frame>=1 and frame<=Pages.FRAME_COUNT and frame%1==0,'Invalid kei truck frame')
    local page=math.floor((frame-1)/Pages.VIEWS_PER_PAGE)+1
    local key=kind..':'..page
    local entry=self.cache[key]
    if not entry then
        local filename=('assets/commute/truck/kei-turntables/%s-64-%d.png'):format(kind,page)
        assert(love.filesystem.getInfo(filename,'file'),'Missing kei truck page: '..filename)
        local image=love.graphics.newImage(filename)
        image:setFilter('linear','linear')
        entry={image=image,width=image:getWidth(),height=image:getHeight()}
        self.cache[key]=entry
    end
    self.clock=self.clock+1;entry.used=self.clock
    local count=0
    for _ in pairs(self.cache) do count=count+1 end
    if count>Pages.MAX_CACHED_PAGES then
        local oldestKey,oldest
        for candidate,value in pairs(self.cache) do
            if candidate~=key and (not oldest or value.used<oldest.used) then oldestKey,oldest=candidate,value end
        end
        oldest.image:release();self.cache[oldestKey]=nil
    end
    local localFrame=(frame-1)%Pages.VIEWS_PER_PAGE
    local col,row=localFrame%4,math.floor(localFrame/4)
    local x,y=math.floor(col*entry.width/4),math.floor(row*entry.height/4)
    local right,bottom=math.floor((col+1)*entry.width/4),math.floor((row+1)*entry.height/4)
    local cellWidth,cellHeight=right-x,bottom-y
    local quadKey=key..':'..localFrame
    local quad=self.quads[quadKey]
    if not quad then
        quad=love.graphics.newQuad(x,y,cellWidth,cellHeight,entry.width,entry.height)
        self.quads[quadKey]=quad
    end
    local scale=kind=='chase' and .42*640/cellWidth or 384/cellWidth
    local format={width=cellWidth,height=cellHeight,anchorX=cellWidth*.5,
        anchorY=kind=='chase' and cellHeight*.917 or cellHeight*.823,scale=scale}
    return entry.image,quad,format
end

function Pages:release()
    for _,entry in pairs(self.cache) do entry.image:release() end
    for _,quad in pairs(self.quads) do quad:release() end
    self.cache={};self.quads={}
end

return Pages
