-- Draw nearby road/footprint cells while a bounded static canvas builds, then
-- reuse that canvas as the mini map moves and rotates.
local Detail={};Detail.__index=Detail
local CELL=128
local CACHE_MAX_SIDE=1536
local CACHE_ITEMS_PER_FRAME=48
function Detail.new(world)
    local self=setmetatable({cells={},roadHalfWidth=0,roads={},buildings={},
        minX=math.huge,minZ=math.huge,maxX=-math.huge,maxZ=-math.huge},Detail)
    local function insert(item,points)
        local x0,z0,x1,z1=math.huge,math.huge,-math.huge,-math.huge
        for _,p in ipairs(points) do
            x0,z0=math.min(x0,p.x),math.min(z0,p.z);x1,z1=math.max(x1,p.x),math.max(z1,p.z)
        end
        item.x0,item.z0,item.x1,item.z1=x0,z0,x1,z1
        self.minX,self.minZ=math.min(self.minX,x0),math.min(self.minZ,z0)
        self.maxX,self.maxZ=math.max(self.maxX,x1),math.max(self.maxZ,z1)
        if item.road then self.roadHalfWidth=math.max(self.roadHalfWidth,item.width/2) end
        local items=item.road and self.roads or self.buildings
        items[#items+1]=item
        for x=math.floor(x0/CELL),math.floor(x1/CELL) do
            for z=math.floor(z0/CELL),math.floor(z1/CELL) do
                local key=x..':'..z;local cell=self.cells[key] or {};self.cells[key]=cell
                cell[#cell+1]=item
            end
        end
    end
    for _,path in ipairs(world.roads and world.roads.paths or {}) do
        for i=2,#path.points do
            local a,b=path.points[i-1],path.points[i]
            insert({road=true,points={a.x,a.z,b.x,b.z},width=path.width or 4,dirt=path.surface=='dirt'}, {a,b})
        end
    end
    for _,site in ipairs(world.sites and world.sites.all or {}) do
        for _,footprint in ipairs(site.footprints or {}) do
            local points={}
            for _,p in ipairs(footprint.corners) do points[#points+1]=p.x;points[#points+1]=p.z end
            if #points>=6 then insert({points=points},footprint.corners) end
        end
    end
    return self
end
function Detail:visible(transform,area)
    -- Invert the clipped, rotated viewport. The follow marker sits below its
    -- center, so include both sides and the thick road outline at the edge.
    local c,s=math.abs(math.cos(transform.rotation)),math.abs(math.sin(transform.rotation))
    local dx=math.max(math.abs(area.x-transform.x),math.abs(area.x+area.width-transform.x))
    local dy=math.max(math.abs(area.y-transform.y),math.abs(area.y+area.height-transform.y))
    local pad=self.roadHalfWidth+3/transform.scale
    local rx,rz=(c*dx+s*dy)/transform.scale+pad,(s*dx+c*dy)/transform.scale+pad
    local x0,x1=transform.centerX-rx,transform.centerX+rx
    local z0,z1=transform.centerZ-rz,transform.centerZ+rz
    local seen,roads,buildings={},{},{}
    for x=math.floor(x0/CELL),math.floor(x1/CELL) do
        for z=math.floor(z0/CELL),math.floor(z1/CELL) do
            for _,item in ipairs(self.cells[x..':'..z] or {}) do
                if not seen[item] then
                    seen[item]=true
                    if item.x1>=x0 and item.x0<=x1 and item.z1>=z0 and item.z0<=z1 then
                        local list=item.road and roads or buildings;list[#list+1]=item
                    end
                end
            end
        end
    end
    return roads,buildings
end
local function stroke(g,item,width)
    g.setLineWidth(width);g.line(item.points)
    -- Round the ends of sampled segments so curves and junctions join.
    g.circle('fill',item.points[1],item.points[2],width/2)
    g.circle('fill',item.points[3],item.points[4],width/2)
end
local function drawItem(g,item,pass,scale)
    if pass==1 then
        g.setColor(.37,.47,.49,1);g.polygon('fill',item.points)
        g.setColor(.65,.75,.76,1);g.setLineWidth(1/scale);g.polygon('line',item.points)
    elseif pass==2 then
        g.setColor(.055,.09,.12,1);stroke(g,item,math.max(item.width*scale+3,5)/scale)
    else
        g.setColor(item.dirt and {.65,.51,.31,1} or {.91,.94,.93,1})
        stroke(g,item,math.max(item.width*scale,2)/scale)
    end
end
function Detail:_prepareCache()
    if self.cache or self.cacheUnavailable or self.minX==math.huge then return end
    local g=love.graphics
    if not g.newCanvas then self.cacheUnavailable=true;return end
    local padding=self.roadHalfWidth+4
    local x0,z0=self.minX-padding,self.minZ-padding
    local width,height=self.maxX-self.minX+padding*2,self.maxZ-self.minZ+padding*2
    local scale=math.min(3,CACHE_MAX_SIDE/width,CACHE_MAX_SIDE/height)
    if scale<.5 then self.cacheUnavailable=true;return end
    local okay,canvas=pcall(g.newCanvas,math.ceil(width*scale),math.ceil(height*scale))
    if not okay or not canvas then self.cacheUnavailable=true;return end
    self.cache,self.cacheX,self.cacheZ,self.cacheScale=canvas,x0,z0,scale
    self.cachePass,self.cacheIndex=1,1
    g.push('all');g.origin();g.setScissor();g.setCanvas(canvas);g.clear(0,0,0,0);g.pop()
end
function Detail:_advanceCache()
    if not self.cache or self.cacheReady then return end
    local g=love.graphics
    g.push('all');g.origin();g.setScissor();g.setCanvas(self.cache);g.setBlendMode('alpha')
    g.scale(self.cacheScale);g.translate(-self.cacheX,-self.cacheZ)
    local remaining=CACHE_ITEMS_PER_FRAME
    while remaining>0 and self.cachePass<=3 do
        local list=self.cachePass==1 and self.buildings or self.roads
        local item=list[self.cacheIndex]
        if item then
            drawItem(g,item,self.cachePass,math.min(self.cacheScale,1.2))
            self.cacheIndex=self.cacheIndex+1;remaining=remaining-1
        else self.cachePass=self.cachePass+1;self.cacheIndex=1 end
    end
    g.pop()
    if self.cachePass>3 then self.cacheReady=true end
end
function Detail:draw(transform,area)
    local g=love.graphics
    self:_prepareCache()
    if self.cacheReady then
        g.push('all');g.setBlendMode('alpha','premultiplied')
        g.setColor(1,1,1,1)
        g.draw(self.cache,self.cacheX,self.cacheZ,0,1/self.cacheScale,1/self.cacheScale)
        g.pop()
        return
    end
    local roads,buildings=self:visible(transform,area)
    local scale=transform.scale
    for _,item in ipairs(buildings) do
        drawItem(g,item,1,scale)
    end
    for _,item in ipairs(roads) do
        drawItem(g,item,2,scale)
    end
    for _,item in ipairs(roads) do
        drawItem(g,item,3,scale)
    end
    self:_advanceCache()
end
function Detail:release()
    if self.cache then self.cache:release();self.cache=nil end
end
return Detail
