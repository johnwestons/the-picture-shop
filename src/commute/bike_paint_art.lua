-- One reusable material shader. Original bronze bypasses recoloring exactly.
local Paint=require('src.commute.bike_paint')
local Regions=require('src.commute.bike_paint_regions')
local Art={}
local source,shader
function Art.source()
    if not source then source=assert(love.filesystem.read('src/commute/bike_paint.glsl')) end
    return source
end
function Art.prewarm()
    if not shader then
        shader=love.graphics.newShader(Art.source()..[[
vec4 effect(vec4 color,Image texture,vec2 uv,vec2 pixel) {
    return bikePaintSurface(Texel(texture,uv),uv)*color;
}
]])
    end
    return shader
end
function Art.configure(target,paintId,image,quad,frame,pose,mode)
    local finish=Paint.get(paintId) or Paint.get()
    local enabled=finish.id~=Paint.DEFAULT
    target:send('bikePaintEnabled',enabled)
    if not enabled then return end
    local width,height=image:getDimensions()
    local x,y,w,h=0,0,width,height
    if quad then x,y,w,h=quad:getViewport() end
    frame=frame or math.floor(y/320)*4+math.floor(x/320)+1
    target:send('bikePaintColor',finish.color)
    target:send('bikePaintTextureSize',{width,height})
    target:send('bikePaintFrame',{x,y,w,h})
    target:send('bikePaintLower',mode=='firstPerson' and 0 or Regions.lower(pose or 'parked',frame))
    target:send('bikePaintMode',mode=='firstPerson' and 1 or 0)
end
function Art.draw(image,quad,paintId,x,y,rotation,sx,sy,ax,ay,frame,pose)
    local g=love.graphics
    local previous=g.getShader()
    local finish=Paint.get(paintId)
    if not finish or finish.id==Paint.DEFAULT then
        if previous and previous:hasUniform('bikePaintEnabled') then previous:send('bikePaintEnabled',false) end
        g.draw(image,quad,x,y,rotation,sx,sy,ax,ay)
        return
    end
    -- First-person billboard shaders retain their depth and fog uniforms.
    local target=previous and previous:hasUniform('bikePaintEnabled') and previous or Art.prewarm()
    Art.configure(target,paintId,image,quad,frame,pose)
    g.setShader(target);g.draw(image,quad,x,y,rotation,sx,sy,ax,ay)
    target:send('bikePaintEnabled',false)
    g.setShader(previous)
end
return Art
