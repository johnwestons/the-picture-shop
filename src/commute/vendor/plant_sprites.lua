-- Atlas pages fit 2048px GPUs, including transparent cell gutters. Long source
-- strips are sliced on the CPU and never uploaded as oversized GPU textures.
local Flora=require('src.commute.vendor.flora')
local PlantVariants=require('src.commute.vendor.plant_variants')
local AtlasLayout=require('src.commute.vendor.plant_atlas_layout')
local ImageLoader=require('src.image_loader')
local Sprites={MOTION_BUDGET=16*1024*1024,MOTION_RECENCY_RESERVE=4*1024*1024,
    MOTION_HARD_LIMIT=32*1024*1024,BASE_PREPARE_BUDGET_MS=4,
    MOTION_PREPARE_BUDGET_MS=4,MOTION_UPLOAD_BYTES=1024*256*4};Sprites.__index=Sprites
Sprites.BASE_MOBILE_BUDGET=20*1024*1024
Sprites.BASE_DESKTOP_BUDGET=32*1024*1024
local staticVariants={rock=11,log=5,twig=2,['leaf-litter']=2,stone=1}
local staticFiles={rock='rock.png',log='log.png',twig='twig.png',
    ['leaf-litter']='leaf-litter.png',stone='stone-clutter.png'}
local landmarkKinds={
    'skiff-intact','skiff-split','skiff-collapsed','fishing-net','crayfish-trap','fishing-pole',
    'cabin-hearth-remains','cabin-partial-ruin','cabin-shell-ruin',
    'camp-fire-ring','camp-collapsed-tent','camp-lean-to',
    'eastern-cottontail-nest','gray-fox-den','long-tailed-weasel-den','red-shouldered-hawk-nest',
    'white-tailed-deer-bed',
}
local function buildItems(hasFile)
    hasFile=hasFile or function() return true end
    local items={}
    for _,kind in ipairs(Flora.order) do
        local profile=Flora.types[kind]
        for i,state in ipairs(Flora.states) do
            items[#items+1]={key=kind..'/'..state,path='assets/commute/plants/'..kind..'.png',sx=(i-1)*256}
        end
        local variant=PlantVariants.forms[kind]
        if variant then
            local path='assets/commute/plants/variants/'..variant.file
            if hasFile(path) then
                for i,state in ipairs(Flora.states) do
                    items[#items+1]={key=kind..'/'..variant.key..'/'..state,path=path,sx=(i-1)*256}
                end
            end
        end
        for _,state in ipairs({'autumn','senescent'}) do
            local path='assets/commute/plants/motion/'..kind..'-'..state..'.png'
            if profile.authoredMotion~=false or hasFile(path) then
                items[#items+1]={key=kind..'/'..state,path=path,sx=0}
            end
        end
        if profile.authoredMotion~=false then
            local path='assets/commute/plants/motion/'..kind..'-wind-idle.png'
            for i=1,2 do
                items[#items+1]={key=kind..'/wind'..i,path=path,sx=(i-1)*256}
            end
        end
    end
    for _,kind in ipairs({'rock','log','twig','leaf-litter','stone'}) do
        items[#items+1]={key=kind,path='assets/commute/scenery/'..staticFiles[kind],sx=0}
        for variant=2,staticVariants[kind] do
            items[#items+1]={key=kind..'-v'..variant,path='assets/commute/scenery/'..kind..'-v'..variant..'.png',sx=0}
        end
    end
    for _,kind in ipairs(landmarkKinds) do
        items[#items+1]={key=kind,path='assets/commute/scenery/environmental/'..kind..'.png',sx=0}
    end
    return items
end
Sprites.buildItems=buildItems
function Sprites.new(options)
    options=options or {}
    local mobile=options.mobile==true or love.system.getOS()=='Android'
    for _,v in ipairs(arg or {}) do if v=='--low-ground-memory' then mobile=true end end
    local self=setmetatable({pages={},pageImages={},pageUsage={},pageBytes={},pageKeys={},
        quads={},bytes=0,motion={},motionBytes=0,clock=0,requests={},wanted={},
        layout=AtlasLayout,baseBudget=mobile and Sprites.BASE_MOBILE_BUDGET or Sprites.BASE_DESKTOP_BUDGET,
        lastPrepareMs=0,lastPrepareBytes=0,lastUploadMs=0,totalUploadedBytes=0,
        maxUploadBytes=0,baseInitialized=true},Sprites)
    self.baseItems=buildItems(function(path) return love.filesystem.getInfo(path)~=nil end)
    for _,item in ipairs(self.baseItems) do
        assert(AtlasLayout.entries[item.key],'Missing generated plant atlas cell: '..item.key)
        local page=AtlasLayout.entries[item.key][1]
        self.pageKeys[page]=self.pageKeys[page] or {}
        self.pageKeys[page][#self.pageKeys[page]+1]=item.key
    end
    self.baseItems=nil
    -- `ready` now means the static layout is initialized. Page images are
    -- loaded on demand by prepare(), never by draw().
    self.ready=true
    return self
end
function Sprites:prepareBase()
    return false
end
function Sprites:hasKey(key)
    if self.layout and self.layout.entries[key] then return true end
    return self.quads[key]~=nil
end
function Sprites:resolveKey(key)
    local cached=self.quads[key]
    local entry=self.layout and self.layout.entries[key]
    if not entry then return cached end
    if self.pageImages and not self.pageImages[entry[1]] then return nil end
    if cached and cached.page==entry[1] then return cached end
    cached={page=entry[1],quad=love.graphics.newQuad(entry[2],entry[3],256,256,AtlasLayout.columns*260,260)}
    self.quads[key]=cached
    return cached
end
function Sprites:resolve(kind,state,variant)
    if Flora.types[kind] then
        local key=variant and kind..'/'..variant..'/'..tostring(state) or kind..'/'..tostring(state)
        return self:resolveKey(key)
    end
    return self:resolveKey(kind)
end
function Sprites:_loadImage(path)
    local image,reason=ImageLoader.load(path)
    if image then return image end
    if reason and reason~='pending' then error(reason,2) end
    return nil
end
function Sprites:_drawResolved(resolved,x,y,scale,sway,tint)
    if not resolved then return false end
    local image=self.pageImages and self.pageImages[resolved.page]
    if not image and self.pages then image=self.pages[resolved.page] end
    if not image then return false end
    if tint then
        local r,g,b,a=love.graphics.getColor()
        love.graphics.setColor(r*tint[1],g*tint[2],b*tint[3],a*(tint[4] or 1))
        love.graphics.draw(image,resolved.quad,x,y,0,scale,scale,128,248,sway or 0,0)
        love.graphics.setColor(r,g,b,a)
    else
        love.graphics.draw(image,resolved.quad,x,y,0,scale,scale,128,248,sway or 0,0)
    end
    return true
end
function Sprites:draw(kind,state,x,y,scale,sway,variant)
    local resolved=self:resolve(kind,state,variant)
    return self:_drawResolved(resolved,x,y,scale,sway)
end
function Sprites:drawLandmark(piece,x,y,scale)
    local resolved=self:resolve(piece.kind)
    if not resolved then return false end
    local image=self.pageImages and self.pageImages[resolved.page]
    if not image and self.pages then image=self.pages[resolved.page] end
    if not image then return false end
    love.graphics.draw(image,resolved.quad,x,y,piece.rotation or 0,scale,scale,128,248)
    return true
end
function Sprites:drawTinted(kind,state,x,y,scale,sway,tint,variant)
    local r,g,b,a=love.graphics.getColor()
    love.graphics.setColor(r*tint[1],g*tint[2],b*tint[3],a*(tint[4] or 1))
    local drawn=self:draw(kind,state,x,y,scale,sway,variant)
    love.graphics.setColor(r,g,b,a)
    return drawn
end
local function lifecycleKey(kind,state,variant)
    return kind..'/'..(variant and variant..'/' or '')..tostring(state)
end
function Sprites:plantKey(p,calendar,time)
    if p.kind=='leaf-litter' then
        local month=calendar and calendar.month or 5
        if month<9 or month>11 then return nil end
    end
    if not Flora.types[p.kind] then
        local count=staticVariants[p.kind]
        if not count then return p.kind end
        local index=(p.id or 0)%count
        if p.kind=='rock' and p.h then
            if p.h>18 then
                local alpine={2,4,5,6,7,8,9,10}
                index=alpine[(p.id or 0)%#alpine+1]
            elseif p.h>2 then
                local upland={2,4,7,8,9,10}
                index=upland[(p.id or 0)%#upland+1]
            elseif p.h<1 then index=(p.id or 0)%2==0 and 1 or 3 end
        end
        return index==0 and p.kind or p.kind..'-v'..(index+1)
    end
    local state,action,frame=Flora.visual(p,calendar,time)
    if not state then return nil end
    local profile=Flora.types[p.kind]
    local variant=p.visualVariant
    if variant and not self:hasKey(lifecycleKey(p.kind,'mature',variant)) then variant=nil end
    if action=='wind-idle' then
        if variant then return lifecycleKey(p.kind,state,variant),action,variant end
        return p.kind..'/wind'..tostring(frame),action,variant
    end
    if action then
        local motionKey=p.kind..'/'..(variant and variant..'/' or '')..action
        local cached=self.motion[motionKey]
        if cached and cached.frames then
            local resolved=cached.frames[frame]
            if resolved then return resolved.key,action,variant end
        elseif cached and cached.image then
            return nil,action,variant
        end
        state=state=='senescent' and 'mature' or state
        return lifecycleKey(p.kind,state,variant),action,variant
    end
    if profile.authoredMotion==false or variant then
        if (state=='autumn' or state=='senescent') and self:hasKey(lifecycleKey(p.kind,state,variant)) then
            return lifecycleKey(p.kind,state,variant)
        elseif state=='autumn' then
            local month=calendar and calendar.month or 5
            state=profile.fruits[month] and 'fruit' or 'mature'
        elseif state=='senescent' then
            state='mature'
        end
    end
    return lifecycleKey(p.kind,state,variant),action,variant
end
function Sprites:_visibleKeys(plants,calendar,time,landmarks,extraProps,requests)
    local keys,seen={},{}
    local function add(key)
        if key and self:hasKey(key) and not seen[key] then
            seen[key]=true;keys[#keys+1]=key
        end
    end
    local function addPlant(p,collectMotion)
        local key,action,variant=self:plantKey(p,calendar,time)
        add(key)
        if requests and collectMotion and Flora.types[p.kind]
            and action and action~='wind-idle' then
            local motionKey=p.kind..'/'..(variant and variant..'/' or '')..action
            if not self.wanted[motionKey] then
                requests[#requests+1]={key=motionKey,kind=p.kind,action=action,variant=variant}
            end
            self.wanted[motionKey]=true
            if self.motion[motionKey] then self.motion[motionKey].used=self.clock end
        end
    end
    -- A starting-home marker identifies where a study begins. Queue its page
    -- before nearby flora so the landmark appears as soon as the field opens.
    for _,piece in ipairs(landmarks or {}) do if piece.home then add(piece.kind) end end
    for _,p in ipairs(plants or {}) do addPlant(p,true) end
    for _,piece in ipairs(landmarks or {}) do if not piece.home then add(piece.kind) end end
    for _,p in ipairs(extraProps or {}) do addPlant(p,false) end
    return keys
end
function Sprites:_pageOrder(keys)
    local ordered,seen={},{}
    if not self.layout then return ordered end
    for _,key in ipairs(keys) do
        local entry=self.layout.entries[key]
        if entry and not seen[entry[1]] then
            seen[entry[1]]=true;ordered[#ordered+1]=entry[1]
        end
    end
    return ordered
end
function Sprites:_protectedPages(order)
    local protected={}
    for _,page in ipairs(order) do protected[page]=true end
    local target=self.baseBudget or Sprites.BASE_DESKTOP_BUDGET
    local pageBytes=(self.layout and self.layout.pageBytes) or AtlasLayout.pageBytes
    local catalogPages=self.layout and #self.layout.pages or 0
    local catalogBytes=catalogPages*pageBytes
    local wantedBytes=#order*pageBytes
    -- The budget is a soft cache target. Every page needed by the current
    -- view stays resident; the finite generated catalog is the hard ceiling.
    local effectiveBudget=math.min(math.max(target,wantedBytes),catalogBytes)
    local maxPages=pageBytes>0 and math.floor(effectiveBudget/pageBytes) or 0
    return protected,maxPages,effectiveBudget,target,catalogBytes,wantedBytes
end
function Sprites:_updateDemand(order,protected,maxPages,effectiveBudget,target,catalogBytes,wantedBytes)
    local missing=0
    for _,page in ipairs(order) do if not self.pageImages or not self.pageImages[page] then missing=missing+1 end end
    self.wantedPageCount=#order
    self.wantedBytes=wantedBytes or (#order*((self.layout and self.layout.pageBytes) or AtlasLayout.pageBytes))
    self.pendingPageCount=missing
    self.pendingBytes=missing*((self.layout and self.layout.pageBytes) or AtlasLayout.pageBytes)
    self.targetBudget=target or self.baseBudget or Sprites.BASE_DESKTOP_BUDGET
    self.effectiveBudget=effectiveBudget or self.targetBudget
    self.catalogBytes=catalogBytes or 0
    self.residencyCapacityPages=maxPages
    self.residencyOverflow=self.wantedBytes>self.catalogBytes
end
function Sprites:readyFor(plants,calendar,time,landmarks,extraProps)
    if not self.ready then return false end
    if not self.layout then return true end
    local order=self:_pageOrder(self:_visibleKeys(plants,calendar,time,landmarks,extraProps))
    local protected,maxPages,effectiveBudget,target,catalogBytes,wantedBytes=self:_protectedPages(order)
    self:_updateDemand(order,protected,maxPages,effectiveBudget,target,catalogBytes,wantedBytes)
    if self.residencyOverflow then return false,'visible atlas demand exceeds the generated catalog' end
    for page in pairs(protected) do if not self.pageImages[page] then return false end end
    return true
end
function Sprites:_removePage(page)
    local image=self.pageImages[page]
    if not image then return end
    image:release();self.pageImages[page]=nil
    local bytes=self.pageBytes[page] or 0
    self.bytes=math.max(0,self.bytes-bytes);self.pageBytes[page]=nil;self.pageUsage[page]=nil
    for index,candidate in ipairs(self.pages) do
        if candidate==image then table.remove(self.pages,index);break end
    end
    for _,key in ipairs(self.pageKeys[page] or {}) do self.quads[key]=nil end
end
function Sprites:_trimToBudget(protected,budget)
    while (self.bytes or 0)>(budget or 0) do
        local oldest,stamp=nil,math.huge
        for resident,last in pairs(self.pageUsage or {}) do
            if not protected[resident] and last<stamp then oldest,stamp=resident,last end
        end
        if not oldest then return false end
        self:_removePage(oldest)
    end
    return true
end
function Sprites:_loadPage(page,protected,budget,uploadBudget)
    if self.pageImages[page] then self.pageUsage[page]=self.clock;return false,0 end
    local path=self.layout.pages[page]
    if not path then return false,0 end
    local started=love.timer.getTime()
    local width,height=AtlasLayout.columns*260,260
    local bytes=width*height*4
    if bytes>self.layout.pageBytes then error('Generated plant page exceeds upload budget') end
    if uploadBudget and not uploadBudget:canUpload() then return false,0 end
    while self.bytes+bytes>(budget or self.effectiveBudget or self.baseBudget) do
        local oldest,stamp=nil,math.huge
        for resident,last in pairs(self.pageUsage) do
            if not protected[resident] and last<stamp then oldest,stamp=resident,last end
        end
        if not oldest then return false,0 end
        self:_removePage(oldest)
    end
    local image=self:_loadImage(path)
    if not image then return false,0 end
    if uploadBudget and not uploadBudget:claim() then image:release();return false,0 end
    image:setFilter('linear','linear')
    local uploadMs=(love.timer.getTime()-started)*1000
    local actualWidth,actualHeight=image:getDimensions()
    bytes=actualWidth*actualHeight*4
    assert(actualWidth==width and actualHeight==height,'Unexpected generated plant page dimensions')
    assert(bytes<=self.layout.pageBytes,'Generated plant page exceeds upload budget')
    self.pageImages[page]=image;self.pageBytes[page]=bytes;self.pageUsage[page]=self.clock
    self.pages[#self.pages+1]=image;self.bytes=self.bytes+bytes
    self.lastPrepareBytes=bytes
    self.lastUploadMs=uploadMs;self.totalUploadedBytes=self.totalUploadedBytes+bytes
    self.maxUploadBytes=math.max(self.maxUploadBytes,bytes)
    self.lastPrepareMs=(love.timer.getTime()-started)*1000
    return true,bytes
end
function Sprites:drawPlant(p,calendar,time,x,y,scale,sway)
    if p.kind=='leaf-litter' then
        local month=calendar and calendar.month or 5
        if month<9 or month>11 then return false end
    end
    if not Flora.types[p.kind] then
        local count=staticVariants[p.kind]
        if count then
            local index=(p.id or 0)%count
            if p.kind=='rock' and p.h then
                if p.h>18 then
                    -- The new large outcrops appear only high on some peaks.
                    -- Their distribution follows deterministic prop IDs.
                    local alpine={2,4,5,6,7,8,9,10}
                    index=alpine[(p.id or 0)%#alpine+1]
                elseif p.h>2 then
                    local upland={2,4,7,8,9,10}
                    index=upland[(p.id or 0)%#upland+1]
                elseif p.h<1 then index=(p.id or 0)%2==0 and 1 or 3 end
            end
            local kind=index==0 and p.kind or p.kind..'-v'..(index+1)
            return self:draw(kind,nil,x,y,scale)
        end
        return self:draw(p.kind,nil,x,y,scale)
    end
    local state,action,frame=Flora.visual(p,calendar,time)
    if not state then return false end
    local profile=Flora.types[p.kind]
    local variant=p.visualVariant
    if variant and not self:hasKey(p.kind..'/'..variant..'/mature') then variant=nil end
    if (profile.authoredMotion==false or variant) and not action then
        if (state=='autumn' or state=='senescent') and self:resolve(p.kind,state,variant) then
            return self:draw(p.kind,state,x,y,scale,sway,variant)
        end
        if state=='autumn' then
            local month=calendar and calendar.month or 5
            local seasonalState=profile.fruits[month] and 'fruit' or 'mature'
            return self:drawTinted(p.kind,seasonalState,x,y,scale,sway,{1,.77,.48,1},variant)
        elseif state=='senescent' then
            return self:drawTinted(p.kind,'mature',x,y,scale,sway,{.74,.69,.55,1},variant)
        end
        return self:draw(p.kind,state,x,y,scale,sway,variant)
    end
    if action=='wind-idle' then
        if variant then return self:draw(p.kind,state,x,y,scale,sway,variant) end
        return self:draw(p.kind,'wind'..frame,x,y,scale)
    end
    if not action then return self:draw(p.kind,state,x,y,scale,sway,variant) end
    local key=p.kind..'/'..(variant and variant..'/' or '')..action;local cached=self.motion[key]
    if not cached then
        -- Drawing always has a ready static pose. Action sequences warm in
        -- prepare(), outside draw submission, at most one new action per frame.
        local fallback=state=='senescent' and 'mature' or state
        return self:draw(p.kind,fallback,x,y,scale,sway,variant)
    end
    cached.used=self.clock
    if cached.frames then
        local resolved=cached.frames[frame]
        local cell=resolved and resolved.key and self:resolveKey(resolved.key) or resolved
        if not cell then
            local fallback=state=='senescent' and 'mature' or state
            return self:draw(p.kind,fallback,x,y,scale,sway,variant)
        end
        return self:_drawResolved(cell,x,y,scale,sway,resolved.tint)
    else
        love.graphics.draw(cached.image,cached.quads[frame],x,y,0,scale,scale,128,248,sway or 0,0)
    end
    return true
end
function Sprites:prepare(plants,calendar,time,landmarks,extraProps,uploadBudget)
    if not self.ready and self.layout then return false end
    self.clock=self.clock+1;self.wanted={};self.lastPrepareMs=0;self.lastPrepareBytes=0;self.lastUploadMs=0
    local started=love.timer.getTime()
    local requests={}
    local keys=self:_visibleKeys(plants,calendar,time,landmarks,extraProps,requests)
    local order=self:_pageOrder(keys)
    local protected,maxPages,effectiveBudget,target,catalogBytes,wantedBytes=self:_protectedPages(order)
    self:_updateDemand(order,protected,maxPages,effectiveBudget,target,catalogBytes,wantedBytes)
    local wantedMotionBytes=0
    for _,request in ipairs(requests) do
        if Flora.types[request.kind].authoredMotion~=false and request.variant==nil then
            wantedMotionBytes=wantedMotionBytes+Sprites.MOTION_UPLOAD_BYTES
        end
    end
    -- Keep a small recency reserve above the currently visible authored set.
    -- A larger visible working set may exceed the soft target, but never the
    -- hard texture-memory ceiling. Virtual motions own no texture bytes.
    self.motionWantedBytes=wantedMotionBytes
    self.motionRetentionBudget=math.min(Sprites.MOTION_HARD_LIMIT,
        math.max(Sprites.MOTION_BUDGET,wantedMotionBytes+Sprites.MOTION_RECENCY_RESERVE))
    self.motionResidencyOverflow=wantedMotionBytes>Sprites.MOTION_HARD_LIMIT
    for page in pairs(protected) do
        if self.pageImages[page] then self.pageUsage[page]=self.clock end
    end
    self:_trimToBudget(protected,effectiveBudget)
    -- One immutable, prebuilt page is the maximum base upload unit per call.
    -- LÖVE's image creation is synchronous and cannot be interrupted mid-upload.
    for _,page in ipairs(order) do
        if not self.pageImages[page] then
            local loaded,bytes=self:_loadPage(page,protected,effectiveBudget,uploadBudget)
            self.lastPrepareBytes=bytes or 0
            self.lastPrepareMs=(love.timer.getTime()-started)*1000
            self:_updateDemand(order,protected,maxPages,effectiveBudget,target,catalogBytes,wantedBytes)
            return loaded,false
        end
    end
    local function currentReady()
        for page in pairs(protected) do if not self.pageImages[page] then return false end end
        for _,request in ipairs(requests) do if not self.motion[request.key] then return false end end
        return true
    end
    for _,request in ipairs(requests) do if not self.motion[request.key] then
        if (love.timer.getTime()-started)*1000>=Sprites.BASE_PREPARE_BUDGET_MS then
            self.lastPrepareMs=(love.timer.getTime()-started)*1000
            return false,currentReady()
        end
        local virtual=Flora.types[request.kind].authoredMotion==false or request.variant~=nil
        local bytesNeeded=virtual and 0 or Sprites.MOTION_UPLOAD_BYTES
        assert(bytesNeeded<=Sprites.MOTION_UPLOAD_BYTES,'Motion upload exceeds its preparation budget')
        if not virtual and uploadBudget and not uploadBudget:canUpload() then
            self.lastPrepareMs=(love.timer.getTime()-started)*1000
            return false,currentReady()
        end
        local victims,planned={},{}
        local projectedBytes=self.motionBytes+bytesNeeded
        while bytesNeeded>0 and projectedBytes>self.motionRetentionBudget do
            local oldest,stamp=nil,math.huge
            for key,entry in pairs(self.motion) do
                if not self.wanted[key] and not planned[key] and entry.used<stamp then
                    oldest,stamp=key,entry.used
                end
            end
            if not oldest then return false,currentReady() end
            planned[oldest]=true;victims[#victims+1]=oldest
            projectedBytes=projectedBytes-self.motion[oldest].bytes
        end
        local key,action=request.key,request.action
        if virtual then
            -- Virtual animation cells remain references into demand-loaded pages.
            local dedicatedSenescent=self:hasKey(lifecycleKey(request.kind,'senescent',request.variant))
            local agingPose=dedicatedSenescent and 'senescent' or 'mature'
            local agingTint={1,.77,.48,1}
            if dedicatedSenescent then agingTint=nil end
            local sequences={
                ['establish-grow']={'seed','sprout','young','mature'},
                ['browse-impact']={'mature','browsed','depleted','depleted'},
                regrow={'depleted','regrowth','browsed','mature'},
                ['senesce-wilt']={{state=agingPose},{state=agingPose,tint=agingTint},
                    {state='dormant'},{state='dormant',tint={.74,.69,.55,1}}},
                ['collapse-decay']={'dead','dead','decay','decay'},
            }
            local frames={}
            for i,value in ipairs(sequences[action] or {}) do
                local stateName=type(value)=='table' and value.state or value
                local frameKey=lifecycleKey(request.kind,stateName,request.variant)
                assert(self:hasKey(frameKey),'Missing lifecycle frame for '..key..'/'..stateName)
                local tint=type(value)=='table' and value.tint or nil
                local resolved=not self.layout and self:resolve(request.kind,stateName,request.variant) or nil
                frames[i]={key=frameKey,page=resolved and resolved.page,quad=resolved and resolved.quad,tint=tint}
            end
            self.motion[key]={frames=frames,bytes=0,used=self.clock,owned=false}
            self.lastPrepareMs=(love.timer.getTime()-started)*1000
            return true,currentReady()
        end
        local image=self:_loadImage('assets/commute/plants/motion/'..request.kind..'-'..action..'.png')
        if not image then
            self.lastPrepareMs=(love.timer.getTime()-started)*1000
            return false,currentReady()
        end
        if uploadBudget and not uploadBudget:claim() then
            image:release()
            self.lastPrepareMs=(love.timer.getTime()-started)*1000
            return false,currentReady()
        end
        -- Claim before releasing anything, so a shared-budget denial can never
        -- evict resident motion without replacing it.
        for _,victim in ipairs(victims) do
            local entry=self.motion[victim]
            if entry.owned~=false then entry.image:release() end
            self.motionBytes=self.motionBytes-entry.bytes;self.motion[victim]=nil
        end
        image:setFilter('linear','linear')
        local uploadMs=(love.timer.getTime()-started)*1000
        local width,height=image:getDimensions()
        assert(width==1024 and height==256,'Unexpected plant motion strip: '..key)
        local cached={image=image,quads={},bytes=width*height*4,used=self.clock,owned=true}
        assert(cached.bytes<=Sprites.MOTION_UPLOAD_BYTES,'Motion texture exceeds upload budget')
        for i=1,4 do cached.quads[i]=love.graphics.newQuad((i-1)*256,0,256,256,width,height) end
        self.motion[key]=cached;self.motionBytes=self.motionBytes+cached.bytes
        self.lastPrepareBytes=cached.bytes
        self.lastUploadMs=uploadMs;self.totalUploadedBytes=self.totalUploadedBytes+cached.bytes
        self.maxUploadBytes=math.max(self.maxUploadBytes,cached.bytes)
        self.lastPrepareMs=(love.timer.getTime()-started)*1000
        return true,currentReady()
    end end
    self.lastPrepareMs=(love.timer.getTime()-started)*1000
    return false,currentReady()
end
function Sprites:release()
    for _,page in ipairs(self.pages) do page:release() end
    for _,entry in pairs(self.motion) do if entry.owned~=false then entry.image:release() end end
    self.pages={};self.pageImages={};self.pageUsage={};self.pageBytes={};self.pageKeys={}
    self.quads={};self.bytes=0;self.baseItems=nil;self.ready=false
    self.motion={};self.motionBytes=0
end
return Sprites
