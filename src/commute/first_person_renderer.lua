-- Perspective terrain plus depth-tested scenery billboards. All geometry is
-- derived from the same roads and support heights used by motorcycle physics.
local FP=require('src.commute.first_person_camera')
local M=require('src.commute.vendor.mathx')
local Bridge=require('src.commute.bridge_art')
local Sites=require('src.commute.sites')
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
extern float spriteDepth;
extern float spriteFog;
#ifdef VERTEX
vec4 position(mat4 transform_projection,vec4 vertex_position) {
    vec4 clip=transform_projection*vertex_position;
    clip.z=spriteDepth*clip.w;
    return clip;
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 pixel) {
    vec4 surface=Texel(tex,uv)*color;
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
    local self=setmetatable({meshes={},canvas=g.newCanvas(1280,880),
        shader=g.newShader(love.filesystem.read('src/commute/perspective.glsl')..'\n'..meshShader),
        spriteShader=g.newShader(spriteShader)},View)
    self.canvas:setFilter('linear','linear')
    local function mesh(vertices,image,color)
        if #vertices==0 then return end
        local m=g.newMesh(format,vertices,'triangles','static')
        if image then m:setTexture(image) end
        self.meshes[#self.meshes+1]={mesh=m,color=color or {1,1,1}}
    end
    local deck,marks,sides,caps,ends={},{},{},{},{}
    for _,s in ipairs(renderer.world.roads.segments) do
        local a,b,w=s.a,s.b,s.width*.5
        if s.bridge then
            local u0,u1=s.distance/3.2,(s.distance+s.len)/3.2
            quad(deck,point(a,a.nx*w,a.nz*w,.045,u0,0),point(b,b.nx*w,b.nz*w,.045,u1,0),
                point(b,-b.nx*w,-b.nz*w,.045,u1,s.width/3.2),point(a,-a.nx*w,-a.nz*w,.045,u0,s.width/3.2))
        end
        if s.width>5.5 and math.floor(s.distance/4)%2==0 then
            quad(marks,point(a,a.nx*.055,a.nz*.055,.065,0,0),point(b,b.nx*.055,b.nz*.055,.065,1,0),
                point(b,-b.nx*.055,-b.nz*.055,.065,1,1),point(a,-a.nx*.055,-a.nz*.055,.065,0,1))
        end
    end
    local above=Bridge.PROFILE_METERS*Bridge.DECK_LINE_FROM_TOP
    local below=above-Bridge.PROFILE_METERS
    for _,p in ipairs(renderer.bridgeArt.sides) do
        quad(sides,point(p.a,0,0,above,0,0),point(p.a,0,0,below,0,1),
            point(p.b,0,0,below,1,1),point(p.b,0,0,above,1,0))
    end
    for _,p in ipairs(renderer.bridgeArt.caps) do
        local inner=-p.side*Bridge.CAP_WIDTH_METERS*(1-Bridge.CAP_OUTER_FRACTION)
        local outer=p.side*Bridge.CAP_WIDTH_METERS*Bridge.CAP_OUTER_FRACTION
        local a,b=p.a,p.b
        local u0,u1=p.distance/3.2,(p.distance+p.len)/3.2
        quad(caps,point(a,p.nx*inner,p.nz*inner,above+.02,u0,0),point(b,p.nx*inner,p.nz*inner,above+.02,u1,0),
            point(b,p.nx*outer,p.nz*outer,above+.02,u1,1),point(a,p.nx*outer,p.nz*outer,above+.02,u0,1))
        -- The inner parapet face is a real plane, so passing it never flips
        -- an isometric screen-space quad through the camera.
        quad(sides,point(a,p.nx*inner,p.nz*inner,above,0,0),point(a,p.nx*inner,p.nz*inner,below,0,1),
            point(b,p.nx*inner,p.nz*inner,below,1,1),point(b,p.nx*inner,p.nz*inner,above,1,0))
    end
    for _,p in ipairs(renderer.bridgeArt.endPosts) do
        local w=p.width*.5
        for _,edge in ipairs({{-w,-w,w,-w},{w,-w,w,w},{w,w,-w,w},{-w,w,-w,-w}}) do
            quad(ends,point(p,edge[1],edge[2],p.height,0,0),point(p,edge[1],edge[2],0,0,1),
                point(p,edge[3],edge[4],0,1,1),point(p,edge[3],edge[4],p.height,1,0))
        end
    end
    mesh(deck,renderer.bridgeArt.asphaltImage)
    mesh(marks,nil,{.78,.72,.44})
    mesh(sides,renderer.bridgeArt.sideImage)
    mesh(caps,renderer.bridgeArt.capImage)
    mesh(ends,renderer.bridgeArt.endBlockImage)
    return self
end
function View:billboard(camera,x,z,h,radius,draw)
    local sx,sy,depth=camera:screen(x,z,h)
    local distance=M.length(x-camera.centerX,z-camera.centerZ)
    if depth<FP.NEAR or depth>FP.FAR or distance>=radius then return end
    local scale=camera.focal/depth/48
    if sx < -640*scale or sx > 1280+640*scale then return end
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
    for y=0,420,14 do
        local t=y/440
        g.setColor(M.lerp(.28,.57,t),M.lerp(.49,.68,t),M.lerp(.65,.70,t))
        g.rectangle('fill',0,y,1280,14)
    end
    g.setDepthMode('lequal',true);g.setMeshCullMode('none');g.setColor(1,1,1)
    local groundShader=renderer:shader(camera)
    groundShader:send('rideHeadlight',actor.headlight==true)
    groundShader:send('rideForward',{math.cos(actor.heading),math.sin(actor.heading)})
    g.setShader(groundShader)
    for _,chunk in ipairs(renderer.visible or {}) do
        if FP.inView(camera,chunk.cx*6+3,chunk.cz*6+3,12) then g.draw(chunk.mesh) end
    end
    for _,mesh in ipairs(renderer.roadMeshes) do g.draw(mesh) end
    FP.send(camera,self.shader);self.shader:send('sceneryRadius',renderer.effectiveRadius)
    self.shader:send('rideHeadlight',actor.headlight==true)
    self.shader:send('rideForward',{math.cos(actor.heading),math.sin(actor.heading)})
    g.setShader(self.shader)
    for _,entry in ipairs(self.meshes) do g.setColor(entry.color);g.draw(entry.mesh) end
    for _,p in ipairs(renderer.visibleProps or {}) do
        self:billboard(camera,p.x,p.z,p.h,renderer.effectiveRadius,function(scale)
            g.setColor(.91,.94,.87)
            renderer.plantSprites:drawPlant(p,renderer.calendar,renderer.clock,0,0,p.scale*scale,renderer.plantMotion:sway(p))
        end)
    end
    local site=Sites.warehouse
    local art=renderer.warehouseArt
    local registration=require('src.commute.warehouse_art').view(camera)
    local anchor=registration.door and site.threshold or site
    self:billboard(camera,anchor.x,anchor.z,site.h,renderer.effectiveRadius,function(scale)
        g.setColor(1,1,1)
        g.draw(art.image,art.quads[registration.index],0,0,0,art.SCALE*scale,art.SCALE*scale,registration.x,registration.y)
    end)
    -- The local rider and their motorcycle are omitted; other riders remain
    -- visible and depth-tested against the road, hills, and vegetation.
    for _,entry in ipairs(actors or {}) do
        local p=entry.actor
        if p~=actor then
            self:billboard(camera,p.x,p.z,p.h or renderer.world:supportHeight(p.x,p.z),renderer.effectiveRadius,function(scale)
                local proxy={zoom=scale,screen=function()return 0,0 end,
                    headingDirection=function(_,heading)return camera:headingDirection(heading) end}
                if entry.gear then
                    require('src.commute.presentation').foot(0,0,scale*.7,entry.gear,p.distance,p.speed,entry.presentation)
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
