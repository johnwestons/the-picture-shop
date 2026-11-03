-- Perspective terrain, solid structures and depth-tested scenery billboards.
-- Geometry uses the road network and support heights from motorcycle physics.
local FP=require('src.commute.first_person_camera')
local M=require('src.commute.vendor.mathx')
local PaintArt=require('src.commute.bike_paint_art')
local View={};View.__index=View
local format={{'VertexPosition','float',2},{'WorldHeight','float',1},{'VertexTexCoord','float',2}}
local meshShader=[[
varying float distanceFromEye;
varying vec2 fromEye;
#ifdef VERTEX
attribute float WorldHeight;
vec4 position(mat4 transform_projection,vec4 vertex_position) {
    vec3 world=vec3(vertex_position.x,WorldHeight,vertex_position.y);
    distanceFromEye=length(world.xz-eyePosition.xz);
    fromEye=world.xz-eyePosition.xz;
    return riderProjection(transform_projection,world);
}
#endif
#ifdef PIXEL
extern float sceneryRadius;
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 pixel) {
    vec4 surface=Texel(tex,uv)*color;
    if(surface.a<.08) discard;
    if(rideHeadlight) surface.rgb=riderLight(surface.rgb,fromEye);
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
function View:billboard(camera,x,z,h,radius,draw)
    local sx,sy,depth=camera:screen(x,z,h)
    local distance=M.length(x-camera.centerX,z-camera.centerZ)
    if depth<FP.NEAR or depth>FP.FAR or distance>=radius then return end
    local scale=camera.focal/depth/48
    local width=camera.viewportWidth or 1280
    if sx < -width*.5*scale or sx > width+width*.5*scale then return end
    local g=love.graphics
    self.spriteShader:send('spriteDepth',FP.depthValue(depth))
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
    groundShader:send('rideHeadlight',actor.headlight==true)
    groundShader:send('rideForward',{math.cos(actor.heading),math.sin(actor.heading)})
    g.setShader(groundShader)
    for _,chunk in ipairs(renderer.visible or {}) do
        g.draw(chunk.mesh) -- Complete resident ground; GPU clipping handles every camera pitch.
    end
    for _,mesh in ipairs(renderer.roadMeshes) do g.draw(mesh) end
    FP.send(camera,self.shader);self.shader:send('sceneryRadius',renderer.effectiveRadius)
    self.shader:send('rideHeadlight',actor.headlight==true)
    self.shader:send('rideForward',{math.cos(actor.heading),math.sin(actor.heading)})
    g.setShader(self.shader)
    for _,entry in ipairs(self.meshes) do g.setColor(entry.color);g.draw(entry.mesh) end
    renderer.structures:drawFirstPerson(camera,actor,renderer.effectiveRadius)
    for _,p in ipairs(renderer.visibleProps or {}) do
        self:billboard(camera,p.x,p.z,p.h,renderer.effectiveRadius,function(scale)
            g.setColor(.91,.94,.87)
            renderer.plantSprites:drawPlant(p,renderer.calendar,renderer.clock,0,0,p.scale*scale,renderer.plantMotion:sway(p))
        end)
    end
    -- The local rider and their motorcycle are omitted; other riders remain
    -- visible and depth-tested against the road, hills, and vegetation.
    for _,entry in ipairs(actors or {}) do
        local p=entry.actor
        if p~=actor then
            local height=not entry.gear and entry.presentation and entry.presentation.h
                or p.h or renderer.world:supportHeight(p.x,p.z)
            self:billboard(camera,p.x,p.z,height,renderer.effectiveRadius,function(scale)
                local proxy={zoom=scale,firstPerson=true,viewHeading=camera.viewHeading,projectionCamera=camera,screen=function()return 0,0 end,
                    headingDirection=function(_,heading)return camera:headingDirection(heading) end,
                    headingDirection16=function(_,heading)return camera:headingDirection16(heading) end}
                if entry.gear then
                    local presentation=require('src.commute.presentation')
                    local falling=presentation.beginFallPose(p,entry.presentation,proxy,0,0)
                    presentation.foot(0,0,scale,entry.gear,p.distance,p.speed,entry.presentation,entry.appearance)
                    if falling then g.pop() end
                else renderer.bikeArt:draw(p,proxy,renderer.world,entry.bikeOnly,entry.presentation) end
            end)
        end
    end
    g.pop()
    g.push('all');g.setShader();g.setColor(1,1,1);g.setBlendMode('alpha','premultiplied')
    g.draw(self.canvas,0,0);g.pop()
end
function View:release()
    for _,entry in ipairs(self.meshes) do entry.mesh:release() end
    self.canvas:release();self.shader:release();self.spriteShader:release()
end
return View
