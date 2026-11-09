-- One material shader shared with depth/fog billboards and cockpit meshes.
local Paint=require('src.commute.bike_paint')
local Regions=require('src.commute.bike_paint_regions')
local Tire=require('src.commute.bike_tire_motion')
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
function Art.configure(target,paintId,image,quad,frame,pose,mode,actor,visual)
    local finish=Paint.get(paintId) or Paint.get()
    local enabled=finish.id~=Paint.DEFAULT
    target:send('bikePaintEnabled',enabled)
    local tire
    if mode~='firstPerson' then tire=Tire.sample(actor,visual,pose,frame) end
    target:send('bikeTireEnabled',tire~=nil)
    if tire then
        target:send('bikeTireWheel1',tire.wheel1);target:send('bikeTireWheel2',tire.wheel2)
        target:send('bikeTireMotion',tire.motion)
    end
    if not enabled and not tire then return end
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
function Art.draw(image,quad,paintId,x,y,rotation,sx,sy,ax,ay,frame,pose,actor,visual)
    local g=love.graphics
    local previous=g.getShader()
    local finish=Paint.get(paintId)
    if (not finish or finish.id==Paint.DEFAULT) and not Tire.sample(actor,visual,pose,frame) then
        if previous and previous:hasUniform('bikePaintEnabled') then previous:send('bikePaintEnabled',false) end
        if previous and previous:hasUniform('bikeTireEnabled') then previous:send('bikeTireEnabled',false) end
        g.draw(image,quad,x,y,rotation,sx,sy,ax,ay)
        return
    end
    -- First-person billboard shaders retain their depth and fog uniforms.
    local target=previous and previous:hasUniform('bikePaintEnabled') and previous or Art.prewarm()
    Art.configure(target,paintId,image,quad,frame,pose,nil,actor,visual)
    g.setShader(target);g.draw(image,quad,x,y,rotation,sx,sy,ax,ay)
    target:send('bikePaintEnabled',false)
    target:send('bikeTireEnabled',false)
    g.setShader(previous)
end
return Art
