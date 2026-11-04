-- Billboard renderer for the warehouse box truck's 64-view movement set.
local Art={FRAME=320,COLUMNS=8,ROWS=8,FRAME_COUNT=64,ANCHOR_X=160,ANCHOR_Y=286,SCALE=.58,
    PATH='assets/commute/truck/moving-64.png'}
Art.__index=Art

function Art.frame(camera,heading)
    local relative
    if camera.firstPerson then relative=heading-(camera.viewHeading or 0)-math.pi*.5
    else relative=heading+math.rad(camera.yaw or 0) end
    local step=math.pi*2/Art.FRAME_COUNT
    return math.floor((relative+math.pi*.5)/step+.5)%Art.FRAME_COUNT+1
end

function Art.new()
    assert(love.filesystem.getInfo(Art.PATH,'file'),'Missing delivery truck turntable: '..Art.PATH)
    local image=love.graphics.newImage(Art.PATH)
    assert(image:getWidth()==2560 and image:getHeight()==2560,'Invalid delivery truck turntable: '..Art.PATH)
    image:setFilter('linear','linear')
    local quads={}
    for i=0,63 do quads[i+1]=love.graphics.newQuad(i%8*320,math.floor(i/8)*320,320,320,2560,2560) end
    return setmetatable({image=image,quads=quads},Art)
end

function Art:draw(actor,camera,world)
    local h=actor.h or world:supportHeight(actor.x,actor.z)
    local x,y=camera:screen(actor.x,actor.z,h)
    local frame=Art.frame(camera,actor.heading or 0)
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(self.image,self.quads[frame],x,y,0,Art.SCALE*camera.zoom,Art.SCALE*camera.zoom,
        Art.ANCHOR_X,Art.ANCHOR_Y)
end

function Art:release()
    self.image:release()
    for _,quad in ipairs(self.quads) do quad:release() end
end

return Art
