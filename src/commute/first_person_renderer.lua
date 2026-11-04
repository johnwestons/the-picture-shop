-- Perspective terrain, solid structures and depth-tested scenery billboards.
-- Geometry uses the road network and support heights from motorcycle physics.
local FP=require('src.commute.first_person_camera')
local M=require('src.commute.vendor.mathx')
local PaintArt=require('src.commute.bike_paint_art')
local Camera=require('src.commute.camera')
local View={};View.__index=View
local format={{'VertexPosition','float',2},{'WorldHeight','float',1},{'VertexTexCoord','float',2}}
local meshShader=[[
varying float distanceFromEye;
varying vec2 fromCameraCenter;
varying float surfaceHeight;
#ifdef VERTEX
attribute float WorldHeight;
extern vec2 cameraCenter;
vec4 position(mat4 transform_projection,vec4 vertex_position) {
    vec3 world=vec3(vertex_position.x,WorldHeight,vertex_position.y);
    distanceFromEye=length(world.xz-eyePosition.xz);
    fromCameraCenter=world.xz-cameraCenter;
    surfaceHeight=WorldHeight;
    return riderProjection(transform_projection,world);
}
#endif
#ifdef PIXEL
extern float sceneryRadius;
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 pixel) {
    vec4 surface=Texel(tex,uv)*color;
    if(surface.a<.08) discard;
    if(rideHeadlight) surface.rgb=riderLight(surface.rgb,fromCameraCenter,surfaceHeight);
    surface.rgb=mix(surface.rgb,vec3(.57,.68,.70),smoothstep(sceneryRadius*.74,sceneryRadius,distanceFromEye));
    return surface;
}
#endif
]]
local spriteShader=[[
#ifdef VERTEX
extern float spriteDepth;
vec4 position(mat4 transform_projection,vec4 vertex_position) {
    vec4 clip=transform_projection*vertex_position;
    clip.z=spriteDepth*clip.w;
    return clip;
}
#endif
#ifdef PIXEL
extern float spriteFog;
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 pixel) {
    vec4 surface=bikePaintSurface(Texel(tex,uv),uv)*color;
    if(surface.a<.08) discard;
    surface.rgb=mix(surface.rgb,vec3(.57,.68,.70),spriteFog);
    return surface;
}
#endif
]]
local function quad(vertices,a,b,c,d)
    for _,p in ipairs({a,b,c,a,c,d}) do vertices[#vertices+1]=p end
end
local function point(p,offsetX,offsetZ,height,u,v)
    return {p.x+offsetX,p.z+offsetZ,p.h+height,u,v}
end
function View.shouldDrawActor(entry,localActor)
    return entry.localPlayer~=true and entry.actor~=localActor
end
function View.actorCamera(camera,actor,scale)
    -- Perspective rays are not parallel: two riders with the same heading
    -- can expose different sides when they occupy different parts of the view.
    local dx,dz=actor.x-camera.centerX,actor.z-camera.centerZ
    local bearing=dx*dx+dz*dz>1e-10 and math.atan2(dz,dx) or camera.viewHeading
    return {zoom=scale,firstPerson=true,viewHeading=bearing,projectionCamera=camera,
        screen=function()return 0,0 end,
        headingDirection=Camera.headingDirection,headingDirection16=Camera.headingDirection16}
end
function View.new(renderer)
    local g=love.graphics
    local width,height=renderer.viewportWidth or 1280,renderer.viewportHeight or 880
    local self=setmetatable({meshes={},viewportWidth=width,viewportHeight=height,canvas=g.newCanvas(width,height),
        shader=g.newShader(love.filesystem.read('src/commute/perspective.glsl')..'\n'..meshShader),
        spriteShader=g.newShader(PaintArt.source()..spriteShader)},View)
    self.canvas:setFilter('linear','linear')
    -- Road paint is part of renderer.roadMeshes, so both camera modes use the
    -- same static lane markings, arrows and stop bars.
    return self
end
function View:resizeViewport(width,height)
    width,height=math.max(1,math.floor(width+.5)),math.max(1,math.floor(height+.5))
    if width==self.viewportWidth and height==self.viewportHeight then return false end
    self.canvas:release();self.canvas=love.graphics.newCanvas(width,height)
    self.canvas:setFilter('linear','linear')
    self.viewportWidth,self.viewportHeight=width,height
    return true
end
function View:billboard(camera,x,z,h,radius,draw,surfaceTop)
    local sx,sy,depth=camera:screen(x,z,h)
    local distance=M.length(x-camera.centerX,z-camera.centerZ)
    if depth<FP.NEAR or depth>FP.FAR or distance>=radius then return end
    local scale=camera.focal/depth/48
    local width=camera.viewportWidth or 1280
    if sx < -width*.5*scale or sx > width+width*.5*scale then return end
    local g=love.graphics
    local testDepth=depth
    if surfaceTop and h<surfaceTop and camera.eyeHeight>surfaceTop then
        -- Paint is layered slightly above the support surface. Test at the
        -- paint plane along the same eye ray without lifting the tire onscreen.
        testDepth=depth*(camera.eyeHeight-surfaceTop)/(camera.eyeHeight-h)
    end
    self.spriteShader:send('spriteDepth',FP.depthValue(math.max(FP.NEAR,testDepth)))
    self.spriteShader:send('spriteFog',M.smooth((distance-radius*.74)/(radius*.26)))
    g.setShader(self.spriteShader)
    g.push();g.translate(sx,sy);g.rotate(camera.roll)
    draw(scale)
    g.pop()
end
function View:draw(renderer,camera,actor,actors)
    local g=love.graphics
    -- Restore the caller's canvas, transform and depth state even when the
    -- commute is drawn inside the main game's scaled UI canvas.
    g.push('all');g.origin();g.setScissor();g.setShader();g.setBlendMode('alpha')
    g.setCanvas({self.canvas,depth=true});g.setDepthMode('always',false)
    g.clear(.57,.68,.70,1,0,1)
    for y=0,math.min(self.viewportHeight,420),14 do
        local t=y/440
        g.setColor(M.lerp(.28,.57,t),M.lerp(.49,.68,t),M.lerp(.65,.70,t))
        g.rectangle('fill',0,y,self.viewportWidth,14)
    end
    g.setDepthMode('lequal',true);g.setMeshCullMode('none');g.setColor(1,1,1)
    local groundShader=renderer:shader(camera)
    local Headlight=require('src.commute.headlight')
    Headlight.send(groundShader,camera,actor)
    g.setShader(groundShader)
    for _,chunk in ipairs(renderer.visible or {}) do
        g.draw(chunk.mesh) -- Complete resident ground; GPU clipping handles every camera pitch.
    end
    for _,mesh in ipairs(renderer.roadMeshes) do g.draw(mesh) end
    if renderer.grassFields then renderer:drawGrass(camera,actor) end
    if renderer.tireTracks then renderer.tireTracks:draw(camera) end
    FP.send(camera,self.shader);self.shader:send('sceneryRadius',renderer.effectiveRadius)
    self.shader:send('cameraCenter',{camera.centerX,camera.centerZ})
    Headlight.send(self.shader,camera,actor)
    g.setShader(self.shader)
    for _,entry in ipairs(self.meshes) do g.setColor(entry.color);g.draw(entry.mesh) end
    renderer.structures:drawFirstPerson(camera,actor,renderer.effectiveRadius)
    for _,p in ipairs(renderer.visibleProps or {}) do
        self:billboard(camera,p.x,p.z,p.h,renderer.effectiveRadius,function(scale)
            g.setColor(.91,.94,.87)
            renderer.plantSprites:drawPlant(p,renderer.calendar,renderer.clock,0,0,p.scale*scale,renderer.plantMotion:sway(p))
        end)
    end
    -- Rider-eye omits the local bike; shoulder view includes it in the same
    -- depth-tested actor pass as the other riders.
    camera.riderSpriteScale=nil
    for _,entry in ipairs(actors or {}) do
        local p=entry.actor
        if camera.includeLocalRider or View.shouldDrawActor(entry,actor) then
            local height=not entry.gear and entry.presentation and entry.presentation.h
                or p.h or renderer.world:supportHeight(p.x,p.z)
            local surfaceTop
            if camera.includeLocalRider and not entry.gear and not entry.bikeOnly then
                -- Suspension can place the chassis below the collision
                -- surface. Register the art to the drawn road or terrain.
                local support,kind=renderer.world:supportHeight(p.x,p.z)
                local paved=kind=='road' or kind=='trail'
                height=math.max(height,support+(paved and .04 or 0))
                surfaceTop=support+.09 -- top of the road and parking paint
            end
            self:billboard(camera,p.x,p.z,height,renderer.effectiveRadius,function(scale)
                local proxy=View.actorCamera(camera,p,scale)
                if entry.gear then
                    local presentation=require('src.commute.presentation')
                    local falling=presentation.beginFallPose(p,entry.presentation,proxy,0,0)
                    presentation.foot(0,0,scale,entry.gear,p.distance,p.speed,entry.presentation,entry.appearance)
                    if falling then g.pop() end
                elseif entry.truck then
                    renderer.truckArt:draw(p,proxy,renderer.world)
                else
                    local y=renderer.bikeArt:draw(p,proxy,renderer.world,entry.bikeOnly,entry.presentation)
                    if y and camera.includeLocalRider and entry.localPlayer and not entry.bikeOnly then
                        camera.riderSpriteX,camera.riderSpriteY=g.transformPoint(0,y)
                        camera.riderSpriteScale=scale
                    end
                end
            end,surfaceTop)
        end
    end
    if renderer.bikeParticles then renderer.bikeParticles:draw(camera,renderer.effectiveRadius,renderer:depthSpan()) end
    g.pop()
    g.push('all');g.setShader();g.setColor(1,1,1);g.setBlendMode('alpha','premultiplied')
    g.draw(self.canvas,0,0);g.pop()
end
function View:release()
    for _,entry in ipairs(self.meshes) do entry.mesh:release() end
    self.canvas:release();self.shader:release();self.spriteShader:release()
end
return View
