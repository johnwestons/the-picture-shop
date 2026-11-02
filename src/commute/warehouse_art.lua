-- Eight independently authored sprite views. No procedural building body.
local Sites=require('src.commute.sites')
local Registration=require('src.commute.warehouse_registration')
local Art={SCALE=1.48};Art.__index=Art
function Art.view(camera) return Registration[camera:headingDirection(math.pi/2)] end
function Art.new()
    local self=setmetatable({image=love.graphics.newImage('assets/commute/buildings/warehouse.png'),quads={}},Art)
    assert(self.image:getWidth()==2048 and self.image:getHeight()==1024,'Invalid warehouse atlas')
    self.image:setFilter('linear','linear')
    for i=1,8 do self.quads[i]=love.graphics.newQuad((i-1)%4*512,math.floor((i-1)/4)*512,512,512,2048,1024) end
    return self
end
function Art.alpha(camera,actor,world)
    local site=Sites.warehouse
    if not actor or camera:depth(actor.x,actor.z,actor.h or world:supportHeight(actor.x,actor.z))
        >=camera:depth(site.x,site.z,site.h) then return 1 end
    local view=Art.view(camera);local anchor=view.door and site.threshold or site
    local x,y=camera:screen(anchor.x,anchor.z,site.h)
    local ax,ay=camera:screen(actor.x,actor.z,actor.h or world:supportHeight(actor.x,actor.z))
    local scale=Art.SCALE*camera.zoom;local b=view.bounds
    local u,v=(ax-x)/scale+view.x,(ay-y-20*camera.zoom)/scale+view.y
    return u>b[1] and u<b[3] and v>b[2] and v<b[4] and .32 or 1
end
function Art:draw(camera,actor,world)
    local view=Art.view(camera);local site=Sites.warehouse
    local anchor=view.door and site.threshold or site
    local x,y=camera:screen(anchor.x,anchor.z,site.h)
    love.graphics.setColor(1,1,1,Art.alpha(camera,actor,world))
    love.graphics.draw(self.image,self.quads[view.index],x,y,0,Art.SCALE*camera.zoom,Art.SCALE*camera.zoom,view.x,view.y)
    love.graphics.setColor(1,1,1)
end
function Art:release()
    self.image:release();for _,quad in ipairs(self.quads) do quad:release() end
end
return Art
