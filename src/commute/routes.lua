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
return Routes
