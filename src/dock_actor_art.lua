-- A small, asynchronous sprite cache for the dock window. A cold doorway
-- requests at most one new image per refresh; the global loader stages uploads.
local Loader=require('src.image_loader')
local Box=require('src.commute.truck_turntable_pages')
local Kei=require('src.commute.kei_turntable_pages')
local Art={MAX_BYTES=8*1024*1024,PAGE_SIZE=512};Art.__index=Art
function Art.new()return setmetatable({images={},pending={},quads={},clock=0,bytes=0},Art)end
function Art:beginRefresh()self.requested=false;self.clock=self.clock+1 end
function Art:image(path)
    local entry=self.images[path]
    if entry then entry.used=self.clock;return entry.image end
    if self.requested then return nil end
    self.requested=true;self.pending[path]=true
    local image,reason=Loader.load(path)
    if not image then
        if reason~='pending' then self.pending[path]=nil end
        return nil
    end
    self.pending[path]=nil;image:setFilter('linear','linear')
    local w,h=image:getDimensions()
    -- Keep all sixteen source directions, but retain a small GPU downsample
    -- for this tiny window. The large decoded/uploaded source is transient.
    local g=love.graphics;local reduced=g.newCanvas(Art.PAGE_SIZE,Art.PAGE_SIZE,{dpiscale=1})
    g.push('all');g.origin();g.setScissor();g.setShader();g.setDepthMode();g.setStencilTest()
    g.setCanvas(reduced);g.clear(0,0,0,0);g.setBlendMode('replace');g.setColor(1,1,1,1)
    g.draw(image,0,0,0,Art.PAGE_SIZE/w,Art.PAGE_SIZE/h);g.pop()
    image:release();image=reduced;image:setFilter('linear','linear')
    local bytes=Art.PAGE_SIZE*Art.PAGE_SIZE*4
    while self.bytes+bytes>Art.MAX_BYTES do
        local oldest,key
        for candidate,value in pairs(self.images)do
            if not oldest or value.used<oldest.used then oldest,key=value,candidate end
        end
        if not key then break end
        oldest.image:release();self.bytes=self.bytes-oldest.bytes;self.images[key]=nil
    end
    self.images[path]={image=image,bytes=bytes,used=self.clock};self.bytes=self.bytes+bytes
    return image
end
function Art:vehicle(entry,camera,world)
    local p=entry.actor;local heading=p.heading or 0
    local angle=heading+math.rad(camera.yaw)+math.pi*.5
    local frame,width,height,scale,ax,ay,path
    if entry.truck then
        local kei=p.model=='kei'
        frame=kei and Kei.frame(angle,'isometric') or Box.frame(angle)
        width,height=kei and 314 or 384,kei and 314 or 384
        scale=kei and 384/314*.67 or 1
        ax,ay=width*.5,kei and 314*.823 or 316
        path=('assets/commute/truck/%s/isometric-64-%d.png'):format(
            kei and 'kei-turntables' or 'turntables',math.floor((frame-1)/16)+1)
        frame=(frame-1)%16
    else
        frame=math.floor(angle/(math.pi*2/16)+.5)%16
        width,height,scale,ax,ay=320,320,.46,160,260
        path='assets/commute/bike/'..(entry.bikeOnly and 'parked-16.png' or 'mounted-16.png')
    end
    local image=self:image(path);if not image then return false end
    local key=path..':'..frame;local quad=self.quads[key]
    local cellW,cellH=image:getWidth()/4,image:getHeight()/4
    if not quad then
        quad=love.graphics.newQuad(frame%4*cellW,math.floor(frame/4)*cellH,cellW,cellH,image:getDimensions())
        self.quads[key]=quad
    end
    local x,y=camera:screen(p.x,p.z,p.h or world:supportHeight(p.x,p.z))
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,quad,x,y,0,scale*camera.zoom*width/cellW,scale*camera.zoom*height/cellH,
        ax*cellW/width,ay*cellH/height)
    return true
end
function Art:person(entry,camera,world,assets,clock)
    local Normal=require('src.commute.normal_art')
    local Animation=require('src.character_animation')
    local p=entry.actor;local appearance=Normal.appearance(entry.appearance)
    local character=appearance.character
    if character=='rabbit-worker' and entry.gear and entry.gear.outfit=='geared' then character='suited-rider'end
    local action,mirror,distance=Normal.selection(p,camera)
    if not assets.hasAction(character,action)then action='idle'end
    if assets.resolveAction then action=assets.resolveAction(character,action)end
    local count=assets.getFrameCount(character,action)
    local frame=Animation.frameForPlayerAction(action,math.max(1,count),distance/require('src.commute.rider').FRAME_DISTANCE,
        clock,1,require('src.config').player.idleAnimationRate)
    local image,quad=assets.get(character,action,frame);if not image or not quad then return false end
    local ax,ay=assets.getAnchor(character,action,frame)
    local scale=require('src.commute.rider_scale').sprite(camera.zoom,assets.getNormalization(character,action))
    local x,y=camera:screen(p.x,p.z,p.h or world:supportHeight(p.x,p.z))
    love.graphics.setColor(1,1,1,1)
    if character=='rabbit-worker' then
        require('src.rabbit_colorways').draw(image,quad,x,y,0,scale*mirror,scale,ax,ay,0,0,
            appearance.furColorway,appearance.overallsColorway)
    else love.graphics.draw(image,quad,x,y,0,scale*mirror,scale,ax,ay)end
    return true
end
function Art:pause()
    for path in pairs(self.pending)do Loader.cancel(path)end;self.pending={}
end
function Art:release()
    self:pause()
    for _,entry in pairs(self.images)do entry.image:release()end
    for _,quad in pairs(self.quads)do quad:release()end
    self.images,self.quads,self.bytes={},{},0
end
return Art
