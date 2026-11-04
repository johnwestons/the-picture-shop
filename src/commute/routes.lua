-- Measurements/navigation use the same sampled centerlines as physical roads.
-- Only authored shared coordinates form junctions; crossing lines do not create
-- accidental links (important if a future bridge crosses another road).
local Routes={};Routes.__index=Routes
local function key(p) return ('%.4f:%.4f:%.4f'):format(p.x,p.z,p.h) end
function Routes.new(roads)
    local self=setmetatable({nodes={},destinations={},roads=roads},Routes)
    local function node(p)
        local id=key(p)
        if not self.nodes[id] then self.nodes[id]={x=p.x,z=p.z,h=p.h,edges={}} end
        return id,self.nodes[id]
    end
    for _,s in ipairs(roads.segments) do
        local a,an=node(s.a);local b,bn=node(s.b)
        an.edges[#an.edges+1]={to=b,length=s.len,bridge=s.bridge}
        if not s.oneWay then bn.edges[#bn.edges+1]={to=a,length=s.len,bridge=s.bridge} end
    end
    for id,p in pairs(roads.destinations) do
        local k=key(p);assert(self.nodes[k],'Unconnected destination: '..id)
        self.destinations[id]=k
    end
    return self
end
function Routes:find(from,to)
    local start,finish=self.destinations[from],self.destinations[to]
    if not start or not finish then return nil,'Unknown address' end
    -- Positive lengths, sparse fixed graph; queue relaxation also permits the
    -- scenic loop to improve a route found first through the valley.
    local distance,previous,queued={[start]=0},{},{[start]=true}
    local queue,head={start},1
    while head<=#queue do
        local id=queue[head];head=head+1;queued[id]=nil
        for _,edge in ipairs(self.nodes[id].edges) do
            local value=distance[id]+edge.length
            if not distance[edge.to] or value<distance[edge.to]-1e-8 then
                distance[edge.to]=value;previous[edge.to]={from=id,bridge=edge.bridge}
                if not queued[edge.to] then queued[edge.to]=true;queue[#queue+1]=edge.to end
            end
        end
    end
    if not distance[finish] then return nil,'No road connection' end
    local reversed,bridge={},false;local id=finish
    while id do
        reversed[#reversed+1]=self.nodes[id]
        local edge=previous[id];bridge=bridge or edge and edge.bridge or false
        id=edge and edge.from
    end
    local points={}
    for i=#reversed,1,-1 do
        local p=reversed[i];points[#points+1]={x=p.x,z=p.z,h=p.h}
    end
    return {from=from,to=to,length=distance[finish],points=points,crossesBridge=bridge}
end
-- Route from a live world position by joining the nearest traversable road
-- segment, then following the same directed road graph used by address routes.
function Routes:findFromPoint(x,z,to)
    local finish=self.destinations[to]
    if not finish or type(x)~='number' or type(z)~='number' then return nil,'Unknown address' end
    local distance,previous,queued,starts={},{},{},{}
    local function seed(id,value,projection,endpoint)
        if not distance[id] or value<distance[id] then
            distance[id]=value
            starts[id]={x=projection.x,z=projection.z,endpoint=endpoint}
            queued[id]=true
        end
    end
    local projections,bestDistance={},math.huge
    for _,segment in ipairs(self.roads.segments) do
        local a,b=segment.a,segment.b
        local dx,dz=b.x-a.x,b.z-a.z
        local length2=dx*dx+dz*dz
        local t=length2>1e-8 and math.max(0,math.min(1,((x-a.x)*dx+(z-a.z)*dz)/length2)) or 0
        local px,pz=a.x+dx*t,a.z+dz*t
        local off=math.sqrt((x-px)^2+(z-pz)^2)
        projections[#projections+1]={segment=segment,t=t,x=px,z=pz,off=off}
        bestDistance=math.min(bestDistance,off)
    end
    for _,projection in ipairs(projections) do
        if projection.off<=bestDistance+.75 then
            local segment,t=projection.segment,projection.t
            local aid,bid=key(segment.a),key(segment.b)
            if not segment.oneWay then seed(aid,projection.off+t*segment.len,{x=projection.x,z=projection.z},segment.a) end
            seed(bid,projection.off+(1-t)*segment.len,{x=projection.x,z=projection.z},segment.b)
        end
    end
    if not next(distance) then return nil,'No road connection' end
    local queue={};for id in pairs(distance) do queue[#queue+1]=id end
    table.sort(queue);for _,id in ipairs(queue) do queued[id]=true end
    local head=1
    while head<=#queue do
        local id=queue[head];head=head+1;queued[id]=nil
        for _,edge in ipairs(self.nodes[id].edges) do
            local value=distance[id]+edge.length
            if not distance[edge.to] or value<distance[edge.to]-1e-8 then
                distance[edge.to]=value;previous[edge.to]={from=id,bridge=edge.bridge};starts[edge.to]=starts[id]
                if not queued[edge.to] then queued[edge.to]=true;queue[#queue+1]=edge.to end
            end
        end
    end
    if not distance[finish] then return nil,'No road connection' end
    local reversed,bridge={},false;local id=finish
    while id do
        reversed[#reversed+1]=self.nodes[id]
        local edge=previous[id];bridge=bridge or edge and edge.bridge or false
        id=edge and edge.from
    end
    local points={{x=x,z=z}}
    local start=starts[finish]
    if start then
        local p=start.endpoint
        if (points[#points].x-start.x)^2+(points[#points].z-start.z)^2>1e-6 then
            points[#points+1]={x=start.x,z=start.z}
        end
        if (points[#points].x-p.x)^2+(points[#points].z-p.z)^2>1e-6 then
            points[#points+1]={x=p.x,z=p.z,h=p.h}
        end
    end
    for i=#reversed,1,-1 do
        local p=reversed[i]
        if (points[#points].x-p.x)^2+(points[#points].z-p.z)^2>1e-6 then
            points[#points+1]={x=p.x,z=p.z,h=p.h}
        end
    end
    return {from='current-position',to=to,length=distance[finish],points=points,crossesBridge=bridge}
end
return Routes
