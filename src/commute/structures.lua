-- Immutable model meshes shared by outside and first-person rendering.
local Geometry=require('src.commute.structure_geometry')
local BridgeGeometry=require('src.commute.bridge_geometry')
local BridgeArt=require('src.commute.bridge_art')
local Sites=require('src.commute.sites')
local FP=require('src.commute.first_person_camera')
local Headlight=require('src.commute.headlight')
local Structures={FORMAT={{'VertexPosition','float',2},{'WorldHeight','float',1},
    {'StructureNormal','float',3},{'VertexTexCoord','float',2},{'VertexColor','float',4}}}
Structures.__index=Structures
local basePriority={sidewalk=1,bridgePier=2,bridgeDeck=3}
local function radius(bounds,x,z)
    return math.sqrt(math.max(math.abs(bounds.minX-x),math.abs(bounds.maxX-x))^2
        +math.max(math.abs(bounds.minZ-z),math.abs(bounds.maxZ-z))^2)
end
function Structures.new(world)
    local g=love.graphics
    local self=setmetatable({world=world,pieces={},buildings={},piers=BridgeArt.pierLayout(world),
        viewportWidth=1280,viewportHeight=880},Structures)
    self.shader=g.newShader(love.filesystem.read('src/commute/perspective.glsl')..'\n'
        ..love.filesystem.read('src/commute/structure.glsl'))
    local function add(p)
        p.radius=p.radius or radius(p.bounds,p.x,p.z)
        p.mesh=g.newMesh(Structures.FORMAT,p.vertices,'triangles','static')
        p.vertexCount=#p.vertices;p.vertices=nil
        self.pieces[#self.pieces+1]=p
    end
    local registry=world.roads.sites or Sites.default
    for _,site in ipairs(registry.all) do
        local model=Geometry.build(site)
        local p={id='building:'..site.id,kind='building',site=site,x=site.x,z=site.z,h=site.h,
            center={x=site.x,z=site.z,h=site.h},vertices=model.vertices,bounds=model.bounds,
            features=model.features,counts=model.counts}
        add(p);self.buildings[#self.buildings+1]=p
    end
    for _,p in ipairs(BridgeGeometry.build(world)) do add(p) end
    local infrastructure=require('src.commute.infrastructure').ensure(world)
    for _,p in ipairs(require('src.commute.infrastructure_geometry').build(infrastructure)) do add(p) end
    self.canvas=g.newCanvas(1280,880);self.canvas:setFilter('linear','linear')
    self.crop=g.newQuad(0,0,1,1,1280,880)
    return self
end
function Structures:visible(camera,range,pass)
    local visible={}
    for _,p in ipairs(self.pieces) do
        local prepass=basePriority[p.kind]~=nil
        if (pass==nil or (pass=='base')==prepass) then
            local dx,dz=p.x-camera.centerX,p.z-camera.centerZ
            if dx*dx+dz*dz<(range+p.radius)^2
                and (not camera.firstPerson or FP.inView(camera,p.x,p.z,p.radius+4)) then
                p.depth=camera:depth(p.x,p.z,p.h)
                p.structure=true;visible[#visible+1]=p
            end
        end
    end
    -- Keep piers before decks for equal-depth edge cases; the scene depth
    -- buffer handles the normal outside-view ordering.
    if pass=='base' then table.sort(visible,function(a,b)
        if a.kind~=b.kind then
            return basePriority[a.kind]<basePriority[b.kind]
        end
        return a.depth<b.depth
    end) end
    return visible
end
function Structures:send(camera,range,actor)
    camera:send(self.shader)
    self.shader:send('structureRadius',range)
    self.shader:send('groundDepthSpan',math.max(1,(self.world.size or 512)*100+(self.world.maxHeight or 84)*100))
    if actor then Headlight.send(self.shader,camera,actor)
    else
        self.shader:send('rideHeadlight',false)
        self.shader:send('rideForward',{1,0})
        self.shader:send('rideLightOffset',{0,0})
        self.shader:send('rideLightHeight',0)
        self.shader:send('rideBeamRange',11)
        self.shader:send('rideBeamSpread',.16)
        self.shader:send('rideBeamDrop',.075)
    end
end
function Structures:resizeViewport(width,height)
    width,height=math.max(1,math.floor(width+.5)),math.max(1,math.floor(height+.5))
    if width==self.viewportWidth and height==self.viewportHeight then return false end
    self.canvas:release();self.crop:release()
    self.viewportWidth,self.viewportHeight=width,height
    self.canvas=love.graphics.newCanvas(width,height);self.canvas:setFilter('linear','linear')
    self.crop=love.graphics.newQuad(0,0,1,1,width,height)
    return true
end
function Structures:drawOutsideDepth(camera,actor,range)
    local g=love.graphics;local visible=self:visible(camera,range,'base')
    if #visible==0 then return 0 end
    self:send(camera,range,actor)
    g.setDepthMode('lequal',true);g.setMeshCullMode('none');g.setColor(1,1,1)
    g.setShader(self.shader)
    for _,piece in ipairs(visible) do g.draw(piece.mesh) end
    g.setShader()
    return #visible
end
function Structures:drawOutsidePropsDepth(camera,actor,range)
    local g=love.graphics;local visible=self:visible(camera,range,'props')
    if #visible==0 then return 0 end
    self:send(camera,range,actor)
    g.setBlendMode('alpha');g.setDepthMode('lequal',true);g.setMeshCullMode('none')
    g.setShader(self.shader)
    for _,piece in ipairs(visible) do
        local alpha=1
        if piece.kind=='building' and actor then
            local height=actor.h or self.world:supportHeight(actor.x,actor.z)
            if camera:depth(actor.x,actor.z,height)<piece.depth then
                local x,y,w,h=Structures.screenBounds(piece,camera)
                local ax,ay=camera:screen(actor.x,actor.z,height)
                ay=ay-20*camera.zoom
                if ax>x and ax<x+w and ay>y and ay<y+h then alpha=.32 end
            end
        end
        g.setColor(1,1,1,alpha);g.draw(piece.mesh)
    end
    g.setShader();g.setColor(1,1,1)
    return #visible
end
function Structures.screenBounds(p,camera)
    local b=p.bounds;local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
    for _,x in ipairs({b.minX,b.maxX}) do for _,z in ipairs({b.minZ,b.maxZ}) do for _,h in ipairs({b.minH,b.maxH}) do
        local sx,sy=camera:screen(x,z,h)
        x0,y0=math.min(x0,sx),math.min(y0,sy);x1,y1=math.max(x1,sx),math.max(y1,sy)
    end end end
    local left,top=math.max(0,math.floor(x0)-2),math.max(0,math.floor(y0)-2)
    local right,bottom=math.min(camera.viewportWidth or 1280,math.ceil(x1)+2),
        math.min(camera.viewportHeight or 880,math.ceil(y1)+2)
    return left,top,right-left,bottom-top
end
function Structures:drawOutside(p,camera,actor,range)
    local x,y,w,h=Structures.screenBounds(p,camera)
    if w<=0 or h<=0 then return end
    local alpha=1
    if p.kind=='building' and actor then
        local ah=actor.h or self.world:supportHeight(actor.x,actor.z)
        if camera:depth(actor.x,actor.z,ah)<p.depth then
            local ax,ay=camera:screen(actor.x,actor.z,ah)
            ay=ay-20*camera.zoom
            if ax>x and ax<x+w and ay>y and ay<y+h then alpha=.32 end
        end
    end
    local g=love.graphics
    g.push('all');g.origin();g.setCanvas({self.canvas,depth=true})
    g.setScissor(x,y,w,h);g.clear(0,0,0,0,0,1)
    g.setBlendMode('alpha');g.setDepthMode('lequal',true);g.setMeshCullMode('none')
    g.setColor(1,1,1);self:send(camera,range,actor);g.setShader(self.shader);g.draw(p.mesh)
    g.pop()
    -- Only the projected rectangle is cleared and copied. A bridge with many
    -- wall bays therefore does not clear the full viewport once per bay.
    self.crop:setViewport(x,y,w,h,self.viewportWidth,self.viewportHeight)
    g.push('all');g.setShader();g.setColor(alpha,alpha,alpha,alpha)
    g.setBlendMode('alpha','premultiplied');g.draw(self.canvas,self.crop,x,y);g.pop()
end
function Structures:drawFirstPerson(camera,actor,range)
    local g=love.graphics;self:send(camera,range,actor)
    g.setShader(self.shader);g.setColor(1,1,1)
    for _,p in ipairs(self:visible(camera,range)) do g.draw(p.mesh) end
end
function Structures:release()
    for _,p in ipairs(self.pieces) do p.mesh:release() end
    self.shader:release();self.canvas:release();self.crop:release()
end
return Structures
