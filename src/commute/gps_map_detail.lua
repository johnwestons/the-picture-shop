-- Cache road/footprint geometry in world-space cells; draw only the nearby
-- cells at street zoom. Roads retain crisp edges at every scale.
local Detail={};Detail.__index=Detail
local CELL=128
function Detail.new(world)
    local self=setmetatable({cells={},roadHalfWidth=0},Detail)
    local function insert(item,points)
        local x0,z0,x1,z1=math.huge,math.huge,-math.huge,-math.huge
        for _,p in ipairs(points) do
            x0,z0=math.min(x0,p.x),math.min(z0,p.z);x1,z1=math.max(x1,p.x),math.max(z1,p.z)
        end
        item.x0,item.z0,item.x1,item.z1=x0,z0,x1,z1
        if item.road then self.roadHalfWidth=math.max(self.roadHalfWidth,item.width/2) end
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
function Detail:draw(transform,area)
    local g=love.graphics
    local roads,buildings=self:visible(transform,area)
    local scale=transform.scale
    local function stroke(item,width)
        g.setLineWidth(width);g.line(item.points)
        -- Round the ends of sampled segments so curves and road junctions join.
        g.circle('fill',item.points[1],item.points[2],width/2)
        g.circle('fill',item.points[3],item.points[4],width/2)
    end
    for _,item in ipairs(buildings) do
        g.setColor(.37,.47,.49,1);g.polygon('fill',item.points)
        g.setColor(.65,.75,.76,1);g.setLineWidth(1/scale);g.polygon('line',item.points)
    end
    for _,item in ipairs(roads) do
        g.setColor(.055,.09,.12,1);stroke(item,math.max(item.width*scale+3,5)/scale)
    end
    for _,item in ipairs(roads) do
        g.setColor(item.dirt and {.65,.51,.31,1} or {.91,.94,.93,1})
        stroke(item,math.max(item.width*scale,2)/scale)
    end
end
return Detail
