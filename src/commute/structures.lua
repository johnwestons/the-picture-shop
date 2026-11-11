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
local function townSignTexture(label)
    local g=love.graphics
    local canvas=g.newCanvas(512,144,{dpiscale=1});canvas:setFilter('linear','linear')
    g.push('all');g.origin();g.setCanvas(canvas);g.clear(.09,.16,.13,1)
    g.setColor(.08,.13,.11,1);g.rectangle('fill',0,0,512,144)
    g.setColor(.77,.65,.39,1);g.setLineWidth(5);g.rectangle('line',8,8,496,128,8,8)
    local heading,name=(label or 'WELCOME TO\nTOWN'):match('^([^\n]*)\n?(.*)$')
    heading=heading or 'WELCOME TO';name=name or 'TOWN'
    local headingFont=g.newFont(25)
    local size=36
    local nameFont=g.newFont(size)
    while nameFont:getWidth(name:upper())>456 and size>20 do
        nameFont:release();size=size-2;nameFont=g.newFont(size)
    end
    g.setFont(headingFont);g.setColor(.91,.85,.68,1);g.printf(heading:upper(),24,22,464,'center')
    g.setFont(nameFont);g.setColor(.99,.96,.86,1);g.printf(name:upper(),24,64,464,'center')
    g.pop();headingFont:release();nameFont:release()
    return canvas
end
local function townSignMesh(f)
    local m=Geometry.new()
    local function point(x,height,front)
        return {f.x+f.fz*x+f.fx*front,f.z-f.fx*x+f.fz*front,f.h+height}
    end
    Geometry.quad(m,point(-1.92,1.68,.14),point(1.92,1.68,.14),
        point(1.92,2.62,.14),point(-1.92,2.62,.14),{1,1,1,1},{f.fx,0,f.fz})
    return m
end
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
    self:setLighting(require('src.commute.day_night').sample(world.calendar or
        {month=6,day=1,elapsed=600,secondsPerDay=1200}))
    local function add(p)
        p.radius=p.radius or radius(p.bounds,p.x,p.z)
        if p.kind=='building' then
            -- Retain coarse upward faces only, not a site-sized rectangle that
            -- would turn courtyards and gardens into solid building shadows.
            p.shadowFaces={}
            for i=1,#p.vertices,3 do
                local a,b,c=p.vertices[i],p.vertices[i+1],p.vertices[i+2]
                local area=math.abs((b[1]-a[1])*(c[2]-a[2])-(b[2]-a[2])*(c[1]-a[1]))*.5
                if a[5]>.2 and math.max(a[3],b[3],c[3])>p.bounds.minH+.8 and area>4 then
                    p.shadowFaces[#p.shadowFaces+1]={{a[1],a[2],a[3]},{b[1],b[2],b[3]},{c[1],c[2],c[3]}}
                    if #p.shadowFaces>=32 then break end
                end
            end
        end
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
    self.townSigns={}
    for _,fixture in ipairs(infrastructure.fixtures or {}) do
        if fixture.kind=='townSign' and fixture.signText then
            local model=townSignMesh(fixture)
            local mesh=g.newMesh(Structures.FORMAT,model.vertices,'triangles','static')
            local image=townSignTexture(fixture.signText)
            mesh:setTexture(image)
            self.townSigns[#self.townSigns+1]={mesh=mesh,image=image,x=fixture.x,z=fixture.z,h=fixture.h}
        end
    end
    -- Structure crops use the fixed commute viewport's pixel coordinates.
    self.canvas=g.newCanvas(1280,880,{dpiscale=1});self.canvas:setFilter('linear','linear')
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
    local light=require('src.commute.day_night').sample(self.world.calendar)
    self.shader:send('fogColor',camera.firstPerson and light.horizon or light.sky)
    self.shader:send('structureRadius',range)
    self.shader:send('groundDepthSpan',math.max(1,(self.world.size or 512)*100+(self.world.maxHeight or 84)*100))
    Headlight.send(self.shader,camera,actor or {})
end
function Structures:resizeViewport(width,height)
    width,height=math.max(1,math.floor(width+.5)),math.max(1,math.floor(height+.5))
    if width==self.viewportWidth and height==self.viewportHeight then return false end
    self.canvas:release();self.crop:release()
    self.viewportWidth,self.viewportHeight=width,height
    self.canvas=love.graphics.newCanvas(width,height,{dpiscale=1});self.canvas:setFilter('linear','linear')
    self.crop=love.graphics.newQuad(0,0,1,1,width,height)
    return true
end
function Structures:setLighting(light)
    self.shader:send('sunDirection',light.sunDirection)
    self.shader:send('sunColor',light.sunColor)
    self.shader:send('sunlight',light.sunlight)
    self.shader:send('ambientLight',light.ambient)
    self.shader:send('fogColor',light.sky)
end
function Structures:drawOutsideDepth(camera,actor,range)
    local g=love.graphics;local visible=self:visible(camera,range,'base')
    if #visible>0 then
        self:send(camera,range,actor)
        self.shader:send('useStructureTexture',false)
        g.setDepthMode('lequal',true);g.setMeshCullMode('none');g.setColor(1,1,1)
        g.setShader(self.shader)
        for _,piece in ipairs(visible) do g.draw(piece.mesh) end
    end
    self:drawTownSigns(camera,actor,range)
    g.setShader()
    return #visible
end
function Structures:drawTownSigns(camera,actor,range)
    if not self.townSigns or #self.townSigns==0 then return 0 end
    local visible={}
    for _,sign in ipairs(self.townSigns) do
        local dx,dz=sign.x-camera.centerX,sign.z-camera.centerZ
        if dx*dx+dz*dz<(range+5)^2
            and (not camera.firstPerson or FP.inView(camera,sign.x,sign.z,5)) then visible[#visible+1]=sign end
    end
    if #visible==0 then return 0 end
    local g=love.graphics
    self:send(camera,range,actor);self.shader:send('useStructureTexture',true)
    g.setDepthMode('lequal',true);g.setMeshCullMode('none');g.setColor(1,1,1,1);g.setShader(self.shader)
    for _,sign in ipairs(visible) do g.draw(sign.mesh) end
    self.shader:send('useStructureTexture',false)
    return #visible
end
function Structures:drawOutsidePropsDepth(camera,actor,range)
    local g=love.graphics;local visible=self:visible(camera,range,'props')
    if #visible==0 then return 0 end
    self:send(camera,range,actor);self.shader:send('useStructureTexture',false)
    g.setBlendMode('alpha');g.setDepthMode('lequal',true);g.setMeshCullMode('none')
    g.setShader(self.shader)
    for _,piece in ipairs(visible) do
        g.setColor(1,1,1,1);g.draw(piece.mesh)
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
    local g=love.graphics
    g.push('all');g.origin();g.setCanvas({self.canvas,depth=true})
    g.setScissor(x,y,w,h);g.clear(0,0,0,0,0,1)
    g.setBlendMode('alpha');g.setDepthMode('lequal',true);g.setMeshCullMode('none')
    g.setColor(1,1,1);self:send(camera,range,actor);g.setShader(self.shader);g.draw(p.mesh)
    g.pop()
    -- Only the projected rectangle is cleared and copied. A bridge with many
    -- wall bays therefore does not clear the full viewport once per bay.
    self.crop:setViewport(x,y,w,h,self.viewportWidth,self.viewportHeight)
    g.push('all');g.setShader();g.setColor(1,1,1,1)
    g.setBlendMode('alpha','premultiplied');g.draw(self.canvas,self.crop,x,y);g.pop()
end
function Structures:drawFirstPerson(camera,actor,range)
    local g=love.graphics;self:send(camera,range,actor)
    self.shader:send('useStructureTexture',false)
    g.setShader(self.shader);g.setColor(1,1,1)
    for _,p in ipairs(self:visible(camera,range)) do g.draw(p.mesh) end
    self:drawTownSigns(camera,actor,range)
    g.setShader()
end
function Structures:release()
    for _,p in ipairs(self.pieces) do p.mesh:release() end
    for _,sign in ipairs(self.townSigns or {}) do sign.mesh:release();sign.image:release() end
    self.shader:release();self.canvas:release();self.crop:release()
end
return Structures
