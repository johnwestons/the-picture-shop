-- A complete authored sprite draped along the bike. The small height profile
-- keeps instruments facing the rider while the frame, saddle and rack extend
-- underneath and behind the eye. GPU clipping handles looking past the bars.
local FP=require('src.commute.first_person_camera')
local PaintArt=require('src.commute.bike_paint_art')
local Body={};Body.__index=Body
Body.PATH='assets/commute/cockpit/first-person-bike-fuel-v2.png'
Body.WIDTH,Body.HEIGHT=1024,1536
Body.INSTRUMENTS={cx=511,cy=235,r=48,gearX=584,gearY=216,gearW=72,gearScale=.7,
    fuelX=410,fuelY=228,fuelR=24}
-- Sprite row, distance ahead of the rider, height above the road.
local profile={{350,.9725,1.16},{440,.88,1.04},{760,.15,.65},{850,0,.82},
    {970,-.20,.82},{1190,-.57,.74},{1380,-.83,.40},{1536,-1.04,.25}}
local shader=[[
#ifdef VERTEX
vec4 position(mat4 transform_projection,vec4 vertex_position) {
    return riderProjection(transform_projection,vertex_position.xyz);
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color,Image tex,vec2 uv,vec2 pixel) {
    vec4 surface=bikePaintSurface(Texel(tex,uv),uv)*color;
    if(surface.a<.02) discard;
    return surface;
}
#endif
]]
local function barPoint(x,y)
    return 1.13-y*.00045,1.58-y*.0012,(x/Body.WIDTH-.5)*1.15
end
function Body.point(x,y)
    if y<=350 then return barPoint(x,y) end
    local a,b=profile[1],profile[2]
    for i=2,#profile do
        a,b=profile[i-1],profile[i]
        if y<=b[1] then break end
    end
    local t=(y-a[1])/(b[1]-a[1])
    return a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t,(x/Body.WIDTH-.5)*1.15
end
function Body.projectControls(camera,width,height,specs)
    local view=Body.camera(camera)
    local scaleX,scaleY=width/1280,height/880
    local radiusScale=math.min(scaleX,scaleY)
    local ox,oy=(width-1280*scaleX)*.5,(height-880*scaleY)*.5
    local result={}
    for _,spec in ipairs(specs) do
        local forward,elevation,right=Body.point(spec.firstPersonX,spec.firstPersonY)
        local x,y,depth=FP.screen(view,forward,right,elevation)
        if depth>=FP.NEAR then
            local edgeForward,edgeElevation,edgeRight=Body.point(spec.firstPersonX+16,spec.firstPersonY)
            local edgeX,edgeY=FP.screen(view,edgeForward,edgeRight,edgeElevation)
            local radius=math.sqrt((edgeX-x)^2+(edgeY-y)^2)*radiusScale*.62
            local sx,sy=ox+x*scaleX,oy+y*scaleY
            if sx>=-40 and sy>=-40 and sx<=width+40 and sy<=height+40 then
                result[#result+1]={action=spec.action,x=sx,y=sy,visualRadius=math.max(5,radius)}
            end
        end
    end
    return result
end
local function wheelPoint(x,y)
    return 1.5-y*.0016,.40+y/165*.30,(x/Body.WIDTH-.5)*1.15
end
function Body.new()
    local g=love.graphics
    -- These canvases store art in authored pixel coordinates; don't inherit
    -- Android's physical display DPI scale.
    local self=setmetatable({image=g.newImage(Body.PATH),
        texture=g.newCanvas(Body.WIDTH,Body.HEIGHT,{dpiscale=1}),
        canvas=g.newCanvas(1280,880,{dpiscale=1}),
        shader=g.newShader(love.filesystem.read('src/commute/perspective.glsl')..PaintArt.source()..shader)},Body)
    self.image:setFilter('linear','linear');self.texture:setFilter('linear','linear');self.canvas:setFilter('linear','linear')
    local vertices,overlays={},{}
    local function vertex(x,y,point)
        local forward,height,right=point(x,y)
        return {forward,height,right,x/Body.WIDTH,y/Body.HEIGHT}
    end
    local function patch(target,x0,y0,x1,y1,point)
        local a,b,c,d=vertex(x0,y0,point),vertex(x1,y0,point),vertex(x1,y1,point),vertex(x0,y1,point)
        for _,v in ipairs({a,b,c,a,c,d}) do target[#target+1]=v end
    end
    -- The narrow front wheel belongs below the steering head. The mirrors
    -- and instruments share one plane, so looking down cannot fold them.
    patch(vertices,420,0,605,165,wheelPoint)
    patch(vertices,0,0,420,165,barPoint)
    patch(vertices,605,0,Body.WIDTH,165,barPoint)
    patch(vertices,0,165,Body.WIDTH,350,barPoint)
    for i=2,#profile do
        local y0,y1=profile[i-1][1],profile[i][1]
        patch(vertices,0,y0,Body.WIDTH,y1,Body.point)
    end
    local format={{'VertexPosition','float',3},{'VertexTexCoord','float',2}}
    self.mesh=g.newMesh(format,vertices,'triangles','static');self.mesh:setTexture(self.image)
    patch(overlays,350,130,710,350,barPoint)
    patch(overlays,210,195,380,320,barPoint)
    patch(overlays,645,195,820,320,barPoint)
    self.instruments=g.newMesh(format,overlays,'triangles','static');self.instruments:setTexture(self.texture)
    return self
end
function Body.camera(camera)
    -- The body mesh lives in chassis coordinates. Transform the actual eye
    -- and gaze into that frame once, so the bars stay attached during a jump.
    local pitch=camera.bikePitch or 0
    local heading,look,roll=FP.tiltView(camera.viewHeading-camera.bikeHeading,
        camera.viewPitch or FP.NEUTRAL_PITCH+(camera.headPitch or 0),camera.roll or 0,-pitch)
    local eyeForward=camera.eyeForward or 0
    local eyeUp=camera.eyeHeight and camera.eyeHeight-(camera.focusHeight or 0) or FP.EYE_HEIGHT
    local c,s=math.cos(pitch),math.sin(pitch)
    return {centerX=c*eyeForward+s*eyeUp,centerZ=0,eyeHeight=c*eyeUp-s*eyeForward,focal=camera.focal,
        viewHeading=heading,viewPitch=look,roll=roll+(camera.barSteer or 0)*.055}
end
function Body:draw(camera,width,height,instruments,paintId)
    local g=love.graphics
    g.push('all');g.origin();g.setScissor();g.setShader();g.setColor(1,1,1)
    g.setDepthMode('always',false);g.setBlendMode('alpha')
    g.setCanvas(self.texture);g.clear(0,0,0,0)
    instruments(Body.INSTRUMENTS)
    g.setCanvas({self.canvas,depth=true});g.clear(0,0,0,0,0,1)
    g.setColor(1,1,1);g.setBlendMode('alpha');g.setDepthMode('lequal',true);g.setMeshCullMode('none')
    FP.send(Body.camera(camera),self.shader)
    PaintArt.configure(self.shader,paintId,self.image,nil,1,'parked','firstPerson')
    g.setShader(self.shader);g.draw(self.mesh)
    self.shader:send('bikePaintEnabled',false)
    g.setBlendMode('alpha','premultiplied');g.setDepthMode('always',false);g.draw(self.instruments)
    g.pop()
    g.push('all');g.setShader();g.setColor(1,1,1);g.setBlendMode('alpha','premultiplied')
    local scaleX,scaleY=width/1280,height/880
    g.draw(self.canvas,(width-1280*scaleX)*.5,(height-880*scaleY)*.5,0,scaleX,scaleY)
    g.pop()
end
function Body:release()
    self.image:release();self.texture:release();self.canvas:release();self.shader:release();self.mesh:release();self.instruments:release()
end
return Body
