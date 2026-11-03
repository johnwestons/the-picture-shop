-- Pure CPU preparation for continuously resident town terrain. GPU ownership stays
-- with the caller; completed tiles can be uploaded and their Lua arrays discarded.
local Surface=require('src.commute.vendor.terrain')
local Mesh={};Mesh.__index=Mesh
function Mesh.new(world,options)
    options=options or {}
    local spacing=options.spacing or 1;local tileSize=options.tileSize or 24
    assert(spacing>0 and spacing*2%1==0,'Terrain spacing must be a positive half metre multiple')
    assert(tileSize>0 and tileSize/spacing%1==0,'Terrain tile size must align to spacing')
    local self=setmetatable({world=world,spacing=spacing,tileSize=tileSize,tiles={},completed=0,
        sampleCount=0,heightSamples=0,cacheHits=0,vertexCount=0,indexCount=0,lastBuildMs=0,
        exactMaterials=options.exactMaterials==true,surface=options.surface or Surface.surface,indexCache={}},Mesh)
    for x0=0,world.size-spacing/100,tileSize do
        for z0=0,world.size-spacing/100,tileSize do
            local x1,z1=math.min(world.size,x0+tileSize),math.min(world.size,z0+tileSize)
            self.tiles[#self.tiles+1]={key=x0..':'..z0,x0=x0,z0=z0,x1=x1,z1=z1,
                centerX=(x0+x1)*.5,centerZ=(z0+z1)*.5,nx=math.ceil((x1-x0)/spacing),nz=math.ceil((z1-z0)/spacing)}
        end
    end
    self.total=#self.tiles;self.ready=self.total==0
    return self
end
local function height(self,job,x,z)
    -- Both geometry and material offsets lie on a tenth-metre grid. Integer keys
    -- share exact samples without introducing interpolated gameplay heights.
    local qx,qz=math.floor(x*10+.5),math.floor(z*10+.5)
    local row=job.heights[qx]
    if not row then row={};job.heights[qx]=row end
    local h=row[qz]
    if h==nil then h=self.world:height(x,z);row[qz]=h;self.heightSamples=self.heightSamples+1
    else self.cacheHits=self.cacheHits+1 end
    return h
end
-- Lower only the displayed soil under every nearby road surface. At junctions
-- the nearest road can be higher than an overlapping lane, so use all segments
-- in the existing spatial bin. The guard covers the diagonal of one grid cell.
-- Physics continues to query the unmodified authoritative world.
function Mesh.visualHeight(world,x,z,h,spacing)
    local roads=world.roads
    if not roads then return h end
    local guard=(spacing or 1)*math.sqrt(2)
    if roads.bins then
        local binSize=roads.binSize or 16
        local segments=roads.bins[math.floor(x/binSize)..':'..math.floor(z/binSize)] or {}
        for _,segment in ipairs(segments)do
            local u=math.max(0,math.min(1,((x-segment.a.x)*segment.dx+(z-segment.a.z)*segment.dz)/segment.length2))
            local dx,dz=x-segment.a.x-segment.dx*u,z-segment.a.z-segment.dz*u
            local reach=segment.width*.5+guard
            if dx*dx+dz*dz<=reach*reach then
                h=math.min(h,segment.a.h+(segment.b.h-segment.a.h)*u-.08)
            end
        end
    else
        local distance,segment,support=roads:sample(x,z)
        if segment and distance<=segment.width*.5+guard then h=math.min(h,support-.08)end
    end
    return h
end
function Mesh:buildRow()
    if self.ready then return end
    local job=self.job
    if not job then job={tile=self.tiles[self.completed+1],row=0,vertices={},heights={}};self.job=job end
    local tile=job.tile
    -- A caller may retry a failed GPU upload without regenerating or duplicating rows.
    if job.row>tile.nx then return true end
    local x=math.min(tile.x1,tile.x0+job.row*self.spacing)
    for iz=0,tile.nz do
        local z=math.min(tile.z1,tile.z0+iz*self.spacing)
        local h=height(self,job,x,z)
        local nx=height(self,job,x-.5,z)-height(self,job,x+.5,z)
        local nz=height(self,job,x,z-.5)-height(self,job,x,z+.5)
        local slope=math.sqrt(nx*nx+nz*nz)
        if self.exactMaterials then
            local hx=height(self,job,x+.3,z)-height(self,job,x-.3,z)
            local hz=height(self,job,x,z+.3)-height(self,job,x,z-.3)
            slope=math.sqrt(hx*hx+hz*hz)/.6
        end
        local r,g,b,_,gw,dw,lw,coverage,gv,sv,lv=self.surface(self.world,x,z,{height=h,slope=slope})
        h=Mesh.visualHeight(self.world,x,z,h,self.spacing)
        local len=math.sqrt(nx*nx+nz*nz+1)
        local u,v=(x-tile.x0)/4,(z-tile.z0)/4
        job.vertices[#job.vertices+1]={x,z,math.max(0,h),nx/len,1/len,nz/len,u,v,u,v,
            (tile.x0/4)%2,(tile.z0/4)%2,r,g,b,1,gw,dw,lw,coverage,gv,sv,lv,-h}
        self.sampleCount=self.sampleCount+1
    end
    job.row=job.row+1
    return job.row>tile.nx
end
function Mesh:finishTile(onTile)
    local job=self.job;local tile=job and job.tile
    assert(tile and job.row>tile.nx,'Terrain tile is not complete')
    local key=tile.nx..':'..tile.nz;local indices=self.indexCache[key]
    if not indices then
        indices={};local stride=tile.nz+1
        for ix=0,tile.nx-1 do for iz=0,tile.nz-1 do
            local a=ix*stride+iz+1;local b=a+stride;local c=a+1;local d=b+1
            for _,index in ipairs({a,b,c,d,c,b})do indices[#indices+1]=index end
        end end
        self.indexCache[key]=indices
    end
    tile.height=self.world.supportHeight and self.world:supportHeight(tile.centerX,tile.centerZ)
        or height(self,job,tile.centerX,tile.centerZ)
    tile.vertexCount,tile.indexCount=#job.vertices,#indices
    if onTile then onTile(tile,job.vertices,indices)
    else tile.vertices,tile.indices=job.vertices,indices end
    tile.ready=true;self.vertexCount=self.vertexCount+tile.vertexCount;self.indexCount=self.indexCount+#indices
    self.completed=self.completed+1;self.job=nil;self.ready=self.completed==self.total
    return tile
end
function Mesh:step(budgetSeconds,onTile,clock)
    clock=clock or os.clock
    local started=clock();local deadline=started+math.max(0,budgetSeconds or .004)
    local finished=0
    while not self.ready and clock()<deadline do
        if self:buildRow()then self:finishTile(onTile);finished=finished+1 end
    end
    self.lastBuildMs=(clock()-started)*1000
    return self.ready,finished
end
return Mesh
