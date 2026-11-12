-- Perspective terrain, solid structures and depth-tested scenery billboards.
-- Geometry uses the road network and support heights from motorcycle physics.
local FP=require('src.commute.first_person_camera')
local M=require('src.commute.vendor.mathx')
local PaintArt=require('src.commute.bike_paint_art')
local Colorways=require('src.rabbit_colorways')
local Camera=require('src.commute.camera')
local SilhouetteStyle=require('src.commute.silhouette_style')
local PlantMotion=require('src.commute.vendor.plant_motion')
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
extern vec3 fogColor;
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 pixel) {
    vec4 surface=Texel(tex,uv)*color;
    if(surface.a<.08) discard;
    surface.rgb=localLighting(surface.rgb,fromCameraCenter,surfaceHeight);
    surface.rgb=riderLight(surface.rgb,fromCameraCenter,surfaceHeight);
    surface.rgb=mix(surface.rgb,fogColor,smoothstep(sceneryRadius*.74,sceneryRadius,distanceFromEye));
    return surface;
}
#endif
]]
local spriteShader=Colorways.blendShaderSource()..[[
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
extern vec3 fogColor;
extern bool silhouetteMode;
extern vec3 silhouetteColor;
]]..SilhouetteStyle.shaderFunctions..[[
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 pixel) {
    vec4 surface=bikePaintSurface(Texel(tex,uv),uv)*color;
    if(surface.a<.08) discard;
    surface=applyRabbitColorways(surface);
    if(silhouetteMode) {
        if(silhouetteOutlineOnly && !silhouetteOutlinePixel(tex,uv)) discard;
        return vec4(silhouetteColor,silhouetteOutputAlpha(surface.a));
    }
    surface.rgb=mix(surface.rgb,fogColor,spriteFog);
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
function View.shouldDrawLocalActor(camera,entry)
    -- Keep the player's motorcycle visible after they park it and drive a
    -- truck. The first-person truck view omits the driven truck itself, while
    -- shoulder view includes it; both should still show the parked bike.
    if camera.localVehicle=='truck' and entry.localPlayer and entry.bikeOnly then return true end
    if camera.localVehicle=='ped' and entry.localPlayer and entry.bikeOnly then return true end
    if camera.includeLocalRider~=true or entry.localPlayer~=true then return false end
    return (entry.truck==true)==(camera.localVehicle=='truck')
end
function View.actorCamera(camera,actor,scale,lockToActorHeading,calibrateShoulder)
    -- Perspective rays are not parallel: two riders with the same heading
    -- can expose different sides when they occupy different parts of the view.
    local dx,dz=actor.x-camera.centerX,actor.z-camera.centerZ
    local bearing=lockToActorHeading and actor.heading or
        dx*dx+dz*dz>1e-10 and math.atan2(dz,dx) or camera.viewHeading
    if calibrateShoulder and camera.shoulderPerspective and camera.shoulderHeadingOffset then
        bearing=bearing-camera.shoulderHeadingOffset
    end
    return {zoom=scale,firstPerson=true,viewHeading=bearing,projectionCamera=camera,
        screen=function()return 0,0 end,
        headingDirection=Camera.headingDirection,headingDirection16=Camera.headingDirection16}
end
function View.new(renderer)
    local g=love.graphics
    local width,height=renderer.viewportWidth or 1280,renderer.viewportHeight or 880
    -- Scene sizes are in logical pixels, including the cab's wider viewport.
    -- Android enables DPI scaling even when the desktop high-DPI flag is false, so
    -- inheriting the window scale here makes the rendered scene occupy only
    -- part of the canvas before it is composited into the game viewport.
    local self=setmetatable({meshes={},viewportWidth=width,viewportHeight=height,
        canvas=g.newCanvas(width,height,{dpiscale=1}),
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
    self.canvas:release();self.canvas=love.graphics.newCanvas(width,height,{dpiscale=1})
    self.canvas:setFilter('linear','linear')
    self.viewportWidth,self.viewportHeight=width,height
    return true
end
function View:billboard(camera,x,z,h,radius,draw,surfaceTop,silhouetteMode,highlightStyle,billboardScale)
    local sx,sy,depth=camera:screen(x,z,h)
    local distance=M.length(x-camera.centerX,z-camera.centerZ)
    if depth<FP.NEAR or depth>FP.FAR or distance>=radius then return end
    local scale=camera.focal/depth/48
    local width=camera.viewportWidth or 1280
    if sx < -width*.5*scale or sx > width+width*.5*scale then return end
    if billboardScale then
        local size=billboardScale*scale
        local halfX=(128+256*PlantMotion.MAX_SWAY)*size
        local halfY=128*size
        local centerY=-120*size
        local cosine,sine=math.cos(camera.roll or 0),math.sin(camera.roll or 0)
        local centerX=-sine*centerY
        centerY=centerY*cosine
        local boundX=math.abs(cosine)*halfX+math.abs(sine)*halfY+2
        local boundY=math.abs(sine)*halfX+math.abs(cosine)*halfY+2
        local height=camera.viewportHeight or 880
        if sx+centerX+boundX<0 or sx+centerX-boundX>width
            or sy+centerY+boundY<0 or sy+centerY-boundY>height then return end
    end
    local g=love.graphics
    local testDepth=depth
    if surfaceTop and h<surfaceTop and camera.eyeHeight>surfaceTop then
        -- Paint is layered slightly above the support surface. Test at the
        -- paint plane along the same eye ray without lifting the tire onscreen.
        testDepth=depth*(camera.eyeHeight-surfaceTop)/(camera.eyeHeight-h)
    end
    self.spriteDepthValue=FP.depthValue(math.max(FP.NEAR,testDepth))
    self.spriteShader:send('spriteDepth',self.spriteDepthValue)
    self.spriteShader:send('spriteFog',M.smooth((distance-radius*.74)/(radius*.26)))
    if silhouetteMode~=nil then SilhouetteStyle.send(self.spriteShader,silhouetteMode,highlightStyle) end
    self.spriteShader:send('furEnabled',0);self.spriteShader:send('overallsEnabled',0)
    g.setShader(self.spriteShader)
    g.push();g.translate(sx,sy);g.rotate(camera.roll)
    draw(scale)
    g.pop()
    if silhouetteMode then SilhouetteStyle.send(self.spriteShader,false,highlightStyle) end
end
function View:draw(renderer,camera,actor,actors,highlightStyle)
    local g=love.graphics
    local light=require('src.commute.day_night').sample(renderer.calendar)
    -- Restore the caller's canvas, transform and depth state even when the
    -- commute is drawn inside the main game's scaled UI canvas.
    g.push('all');g.origin();g.setScissor();g.setShader();g.setBlendMode('alpha')
    g.setCanvas({self.canvas,depth=true,stencil=true});g.setDepthMode('always',false)
    g.clear(light.horizon[1],light.horizon[2],light.horizon[3],1,0,1)
    for y=0,math.min(self.viewportHeight,420),14 do
        local t=y/440
        g.setColor(M.lerp(light.sky[1],light.horizon[1],t),
            M.lerp(light.sky[2],light.horizon[2],t),M.lerp(light.sky[3],light.horizon[3],t))
        g.rectangle('fill',0,y,self.viewportWidth,14)
    end
    g.setDepthMode('lequal',true);g.setMeshCullMode('none');g.setColor(1,1,1)
    local groundShader=renderer:shader(camera)
    local Headlight=require('src.commute.headlight')
    Headlight.send(groundShader,camera,actor)
    g.setShader(groundShader)
    for _,chunk in ipairs(renderer.drawTiles or renderer.visible or {}) do
        g.draw(chunk.mesh) -- Fog-radius tile culling is independent of camera pitch.
    end
    for _,mesh in ipairs(renderer.roadMeshes) do g.draw(mesh) end
    if renderer.shadows then renderer.shadows:draw(renderer,camera,actors,light) end
    if renderer.grassFields then renderer:drawGrass(camera,actor) end
    if renderer.tireTracks then renderer.tireTracks:draw(camera,renderer.tireTrackShader,renderer:depthSpan()) end
    if renderer.footTracks then
        renderer.footTracks:draw(camera,renderer.tireTrackShader,renderer:depthSpan(),renderer.world,renderer.effectiveRadius)
    end
    FP.send(camera,self.shader);self.shader:send('sceneryRadius',renderer.effectiveRadius)
    self.shader:send('fogColor',light.horizon);self.spriteShader:send('fogColor',light.horizon)
    self.shader:send('cameraCenter',{camera.centerX,camera.centerZ})
    Headlight.send(self.shader,camera,actor)
    g.setShader(self.shader)
    for _,entry in ipairs(self.meshes) do g.setColor(entry.color);g.draw(entry.mesh) end
    renderer.structures:drawFirstPerson(camera,actor,renderer.effectiveRadius)
    local foliageRadius=renderer.visiblePropsRadius or renderer.effectiveRadius
    local plantMotion=renderer.plantMotion
    local plantMotionActive=not plantMotion.hasSway or plantMotion:hasSway()
    for _,p in ipairs(renderer.visibleProps or {}) do
        self:billboard(camera,p.x,p.z,p.h,p.foliageRadius or foliageRadius,function(scale)
            g.setColor(.91,.94,.87)
            local sway=plantMotionActive and plantMotion:sway(p) or 0
            renderer.plantSprites:drawPlant(p,renderer.calendar,renderer.clock,0,0,p.scale*scale,sway)
        end,nil,nil,nil,p.scale)
    end
    -- Rider-eye omits the local bike; shoulder view includes it in the same
    -- depth-tested actor pass as the other riders.
    camera.riderSpriteScale=nil
    for _,entry in ipairs(actors or {}) do
        local p=entry.actor
        if View.shouldDrawLocalActor(camera,entry) or View.shouldDrawActor(entry,actor) then
            local height=not entry.gear and entry.presentation and entry.presentation.h
                or p.h or renderer.world:supportHeight(p.x,p.z)
            local surfaceTop
            if entry.truck then
                if p.grounded~=false then
                    local support,kind=renderer.world:supportHeight(p.x,p.z)
                    local paved=kind=='road' or kind=='trail'
                    height=math.max(height,support+(paved and .04 or 0))
                    surfaceTop=renderer.truckArt:firstPersonOcclusionTop(p,camera,height,renderer.world)
                else
                    -- Preserve the physics height in flight; wheel contact
                    -- correction is only for a truck resting on a surface.
                    surfaceTop=nil
                end
            elseif camera.includeLocalRider and not entry.gear and not entry.bikeOnly then
                -- Suspension can place the chassis below the collision
                -- surface. Register the art to the drawn road or terrain.
                local support,kind=renderer.world:supportHeight(p.x,p.z)
                local paved=kind=='road' or kind=='trail'
                height=math.max(height,support+(paved and .04 or 0))
                surfaceTop=support+.11 -- road paint plane plus a small depth precision margin
            end
            local function drawActor(scale,silhouette)
                local lockLocalHeading=camera.includeLocalRider and entry.localPlayer==true
                    and not camera.shoulderPerspective and not entry.truck
                local calibrateShoulder=camera.shoulderPerspective and entry.localPlayer==true
                    and not entry.truck
                local proxy=View.actorCamera(camera,p,scale,lockLocalHeading,calibrateShoulder)
                if entry.npcCharacter then
                    require('src.commute.npc_character_art').draw(renderer.characterAssets,p,
                        entry.characterId,proxy,renderer.world,renderer.clock)
                elseif entry.dismounting then
                    local presentation=require('src.commute.presentation')
                    renderer.bikeArt:draw(p,proxy,renderer.world,true,entry.presentation)
                    presentation.world(renderer.characterAssets,entry.actionActor or p,proxy,renderer.world,
                        entry.gear,entry.appearance,entry.presentation,renderer.clock,self.spriteShader,
                        self.spriteShader,self.spriteDepthValue,silhouette,highlightStyle)
                elseif entry.gear then
                    local presentation=require('src.commute.presentation')
                    g.setShader(self.spriteShader)
                    local authoredCrash=presentation.hasAuthoredCrash(entry.appearance)
                        and (p.crash~=nil or entry.presentation and entry.presentation.pose=='crash')
                    local falling=not authoredCrash and presentation.beginFallPose(p,entry.presentation,proxy,0,0)
                    presentation.world(renderer.characterAssets,p,proxy,renderer.world,
                        entry.gear,entry.appearance,entry.presentation,renderer.clock,self.spriteShader,
                        self.spriteShader,self.spriteDepthValue,silhouette,highlightStyle)
                    if falling then g.pop() end
                elseif entry.truck then
                    renderer.truckArt:draw(p,proxy,renderer.world,silhouette)
                    if not silhouette then renderer.truckArt:drawSignals(p,proxy,renderer.world,renderer.clock) end
                    if camera.includeLocalRider and entry.localPlayer then
                        camera.riderSpriteX,camera.riderSpriteY=g.transformPoint(0,0)
                        camera.riderSpriteScale=scale
                    end
                else
                    local y=renderer.bikeArt:draw(p,proxy,renderer.world,entry.bikeOnly,entry.presentation)
                    if y and camera.includeLocalRider and entry.localPlayer and not entry.bikeOnly then
                        camera.riderSpriteX,camera.riderSpriteY=g.transformPoint(0,y)
                        camera.riderSpriteScale=scale
                    end
                end
            end
            self:billboard(camera,p.x,p.z,height,renderer.effectiveRadius,function(scale)
                drawActor(scale,false)
            end,surfaceTop,false,highlightStyle)
            if entry.localPlayer then
                g.setDepthMode('greater',false)
                self:billboard(camera,p.x,p.z,height,renderer.effectiveRadius,function(scale)
                    drawActor(scale,true)
                end,surfaceTop,true,highlightStyle)
                g.setDepthMode('lequal',true)
            end
        end
    end
    if renderer.bikeParticles then renderer.bikeParticles:draw(camera,renderer.effectiveRadius,renderer:depthSpan()) end
    g.setShader();g.setDepthMode();g.setColor(.045,.075,.15,light.sceneShade)
    g.rectangle('fill',0,0,self.viewportWidth,self.viewportHeight)
    g.pop()
    -- See the isometric renderer: Android's inherited viewport scissor clips
    -- this full-size scene canvas when it is drawn under nested transforms.
    g.push('all');g.setScissor();g.setShader();g.setColor(1,1,1);g.setBlendMode('alpha','premultiplied')
    g.draw(self.canvas,0,0);g.pop()
end
function View:release()
    for _,entry in ipairs(self.meshes) do entry.mesh:release() end
    self.canvas:release();self.shader:release();self.spriteShader:release()
end
return View
