-- Source art remains in assets/source. Runtime pages are normalized 4x4
-- atlases with fixed cell dimensions, so every directional crop uses the same
-- grid and pivot.
local Pages={FRAME_COUNT=64,VIEWS_PER_PAGE=16,MAX_CACHED_PAGES=3}
Pages.__index=Pages
-- The runtime atlases are regenerated from the preserved source contact sheets
-- by tools/commute_lab/normalize_kei_turntables.mjs. Every page now has exact
-- 4x4 cells; all headings share the same visible roof-to-tire height and ground
-- baseline. Uniform resampling preserves each drawing's proportions.
local CELL={
    isometric={width=314,height=314,scale=384/314,anchorY=314*.823},
    chase={width=405,height=243,scale=.42*640/405,anchorY=243*.917},
}

-- The source sheets repeat cardinal views near the end of each page; they
-- are not uniform 5.625-degree turntables like the box truck. These visually
-- calibrated headings skip those repeats. Keep the two elevations separate.
-- Degrees run clockwise from the rear, through the right-facing profile.
local headings={
    isometric={
        {0,1},{10,2},{20,3},{30,4},{40,5},{50,6},{60,7},{70,8},{78,9},{84,11},{90,14},
        {105,18},{115,19},{125,20},{135,21},{145,22},{153,23},{160,24},{167,25},{173,26},{178,27},{180,33},
        {190,34},{200,35},{210,36},{220,37},{230,38},{240,39},{250,40},{260,41},{270,43},
        {285,50},{295,51},{305,52},{315,53},{325,54},{334,55},{342,56},{350,57},{357,58},
    },
    chase={
        {0,1},{10,2},{20,3},{30,4},{40,5},{50,6},{60,7},{70,8},{80,10},{90,15},
        {105,18},{115,19},{125,20},{135,21},{145,22},{155,23},{165,24},{175,25},{178,31},{180,33},
        {190,34},{200,35},{210,36},{220,37},{230,38},{240,39},{250,40},{260,41},{270,43},
        {285,50},{295,51},{305,52},{315,53},{323,54},{331,55},{339,56},{347,57},{353,58},{358,59},
    },
}
function Pages.frame(angle,kind)
    local degrees=math.deg(angle)%360
    local closest,distance=1,math.huge
    for _,view in ipairs(assert(headings[kind or 'isometric'],'Invalid kei truck view')) do
        local delta=math.abs((degrees-view[1]+180)%360-180)
        if delta<distance-1e-7 then closest,distance=view[2],delta end
    end
    return closest
end

function Pages.new()
    return setmetatable({cache={},clock=0,quads={}},Pages)
end

function Pages:get(kind,frame)
    assert(kind=='chase' or kind=='isometric','Invalid kei truck view')
    assert(frame>=1 and frame<=Pages.FRAME_COUNT and frame%1==0,'Invalid kei truck frame')
    local format=CELL[kind]
    local page=math.floor((frame-1)/Pages.VIEWS_PER_PAGE)+1
    local key=kind..':'..page
    local entry=self.cache[key]
    if not entry then
        local filename=('assets/commute/truck/kei-turntables/%s-64-%d.png'):format(kind,page)
        assert(love.filesystem.getInfo(filename,'file'),'Missing kei truck page: '..filename)
        local image=love.graphics.newImage(filename)
        assert(image:getWidth()==format.width*4 and image:getHeight()==format.height*4,
            'Invalid normalized kei truck page: '..filename)
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
    local quadKey=key..':'..localFrame
    local quad=self.quads[quadKey]
    if not quad then
        quad=love.graphics.newQuad(localFrame%4*format.width,
            math.floor(localFrame/4)*format.height,format.width,format.height,
            entry.width,entry.height)
        self.quads[quadKey]=quad
    end
    return entry.image,quad,{width=format.width,height=format.height,
        anchorX=format.width*.5,anchorY=format.anchorY,scale=format.scale}
end

function Pages:release()
    for _,entry in pairs(self.cache) do entry.image:release() end
    for _,quad in pairs(self.quads) do quad:release() end
    self.cache={};self.quads={}
end

return Pages
