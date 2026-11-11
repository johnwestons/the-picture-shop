-- One bounded proxy mesh per group; stencil unions the light's shadows.
local Shapes=require('src.shadow_shapes')
local Flora=require('src.commute.flora')
local Shadows={RANGE=36,MAX_STATIC=72,MAX_VERTICES=9000,BUILD_SECONDS=.00065}
Shadows.__index=Shadows
local format={{'VertexPosition','float',2},{'WorldHeight','float',1}}
function Shadows.new()
    local shader=love.graphics.newShader(love.filesystem.read('src/commute/perspective.glsl')..'\n'..love.filesystem.read('src/commute/shadows.glsl'))
    return setmetatable({shader=shader,static={},dynamic={},built=-100,stats={}},Shadows)
end
local function upload(group,vertices)
    group.count=#vertices
    if #vertices==0 then return end
    if not group.mesh then group.mesh=love.graphics.newMesh(format,Shadows.MAX_VERTICES,'triangles','dynamic')end
    group.mesh:setVertices(vertices);group.mesh:setDrawRange(1,#vertices)
end
local function polygon(vertices,points,world,base,budgeted)
    if #points<6 then return end
    local ok,triangles=pcall(love.math.triangulate,points);if not ok then return end
    -- Subdivide large faces so they conform to the ground instead of floating.
    local function triangle(ax,az,bx,bz,cx,cz,level)
        if budgeted then coroutine.yield()end
        if #vertices+3>Shadows.MAX_VERTICES then return end
        local longest=math.max((ax-bx)^2+(az-bz)^2,(ax-cx)^2+(az-cz)^2,(bx-cx)^2+(bz-cz)^2)
        if longest>25 and level<3 then
            local abx,abz,bcx,bcz,cax,caz=(ax+bx)/2,(az+bz)/2,(bx+cx)/2,(bz+cz)/2,(cx+ax)/2,(cz+az)/2
            triangle(ax,az,abx,abz,cax,caz,level+1);triangle(abx,abz,bx,bz,bcx,bcz,level+1)
            triangle(cax,caz,bcx,bcz,cx,cz,level+1);triangle(abx,abz,bcx,bcz,cax,caz,level+1);return
        end
        local ah,ak=world:supportHeight(ax,az);local bh,bk=world:supportHeight(bx,bz);local ch,ck=world:supportHeight(cx,cz)
        -- Don't bridge discontinuities, climb onto elevated decks, or paint water.
        if math.min(ah,bh,ch)<(world.waterLevel or -math.huge)+.01
            or ak=='water' or bk=='water' or ck=='water' or math.max(ah,bh,ch)-math.min(ah,bh,ch)>2
            or math.max(ah,bh,ch)>base+2 then return end
        vertices[#vertices+1]={ax,az,ah+.025};vertices[#vertices+1]={bx,bz,bh+.025};vertices[#vertices+1]={cx,cz,ch+.025}
    end
    for _,t in ipairs(triangles)do triangle(t[1],t[2],t[3],t[4],t[5],t[6],0)end
end
function Shadows:draw(renderer,camera,actors,light)
    local video=require('src.video_settings')
    local settings=video.current
    if self.disabled or not settings.dynamicShadows then self.worker=nil;return end
    local policy=settings.shadowDistance..':'..tostring(settings.vegetationShadows)
    if policy~=self.policy then
        self.policy=policy;self.worker=nil;self.sun=nil;self.static.count=0
    end
    if light.sunDirection[2]<=.015 then
        self.worker=nil;self.sun=nil;self.static.count=0;return
    end
    local world=renderer.world;local range=math.min(video.shadowRadius(),renderer.mobile and 28 or Shadows.RANGE)
    local now=renderer.clock or 0
    local direction=light.sunDirection
    local dirty=not self.sun or math.abs(direction[1]-self.sun[1])+math.abs(direction[2]-self.sun[2])+math.abs(direction[3]-self.sun[3])>.015
        or math.abs(camera.centerX-(self.cx or 0))+math.abs(camera.centerZ-(self.cz or 0))>4
        or now-self.built>2
    if not self.worker and dirty then
        local cx,cz=camera.centerX,camera.centerZ
        local props=renderer.visibleProps or {}
        self.worker=coroutine.create(function()
        local vertices={};local count=0
        local function near(x,z)return (x-cx)^2+(z-cz)^2<(range+18)^2 end
        for _,p in ipairs(renderer.structures.buildings or {})do
            if near(p.x,p.z) and count<Shadows.MAX_STATIC then
                local b=p.bounds
                for _,face in ipairs(p.shadowFaces or {})do
                    local points={}
                    for _,v in ipairs(face)do
                        local dx,dz=Shapes.sun(light.sunDirection,v[3]-b.minH,18)
                        points[#points+1]={v[1],v[2]};points[#points+1]={v[1]+dx,v[2]+dz}
                    end
                    polygon(vertices,Shapes.hull(points),world,b.minH,true)
                end
                count=count+1
            end
        end
        for _,p in ipairs(props)do
            if settings.vegetationShadows and Flora.canopy[p.kind] and near(p.x,p.z) and count<Shadows.MAX_STATIC and #vertices<Shadows.MAX_VERTICES-300 then
                local height=math.max(1,p.scale*248/22);local dx,dz=Shapes.sun(light.sunDirection,height,14)
                polygon(vertices,Shapes.silhouette(p.kind=='pine' and Shapes.pine or Shapes.tree,p.x,p.z,height*.65,dx,dz),world,p.h,true);count=count+1
            end
        end
        upload(self.static,vertices);self.built=renderer.clock or now;self.sun={direction[1],direction[2],direction[3]};self.cx,self.cz=cx,cz;self.stats.staticCasters=count
        end)
    end
    if self.worker then
        local deadline=love.timer.getTime()+(renderer.mobile and .0004 or Shadows.BUILD_SECONDS)
        repeat
            local okay,reason=coroutine.resume(self.worker);assert(okay,reason)
            if coroutine.status(self.worker)=='dead' then self.worker=nil;break end
        until love.timer.getTime()>=deadline
    end
    local vertices={}
    for i,entry in ipairs(actors or {})do if i<=32 then
        local p=entry.actor
        if p and p.x and p.z and (entry.localPlayer or (p.x-camera.centerX)^2+(p.z-camera.centerZ)^2<(range+7)^2) then
            local onFoot=entry.onFoot or entry.characterId or (entry.gear and not entry.gear.mounted and not entry.bikeOnly)
            local base=world:supportHeight(p.x,p.z);local height=entry.truck and 2.7 or onFoot and 1.7 or 1.4
            local dx,dz=Shapes.sun(light.sunDirection,height,7);local shape
            if entry.truck then
                local dims=require('src.commute.truck_footprint').dimensions(p)
                shape=Shapes.box(p.x,p.z,dims.halfLength,dims.halfWidth,dx,dz,p.heading)
            elseif onFoot then shape=Shapes.silhouette(Shapes.person,p.x,p.z,.8,dx,dz)
            else shape=Shapes.box(p.x,p.z,1,.27,dx,dz,p.heading)end
            polygon(vertices,shape,world,base)
        end
    end end
    upload(self.dynamic,vertices);self.stats.vertices=(self.static.count or 0)+#vertices
    local g=love.graphics;g.push('all');g.setShader(self.shader);camera:send(self.shader)
    self.shader:send('groundDepthSpan',renderer:depthSpan());g.setDepthMode('lequal',false);g.setMeshCullMode('none');g.setColor(1,1,1)
    g.stencil(function()for _,group in ipairs({self.static,self.dynamic})do if group.mesh and group.count>0 then g.draw(group.mesh)end end end,'replace',1,false)
    g.setStencilTest('equal',1);g.setShader();g.setDepthMode('always',false)
    g.setColor(.035,.045,.065,.22*math.min(1,light.sunDirection[2]/.15)*(light.daylight or 1))
    g.rectangle('fill',0,0,renderer.viewportWidth or 1280,renderer.viewportHeight or 880);g.pop()
end
function Shadows:release()
    self.worker=nil
    for _,group in ipairs({self.static,self.dynamic})do if group.mesh then group.mesh:release()end end;self.shader:release()
end
return Shadows
