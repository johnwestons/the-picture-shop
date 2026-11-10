-- Measurements/navigation use the same sampled centerlines as physical roads.
-- Only authored shared coordinates form junctions; crossing lines do not create
-- accidental links (important if a future bridge crosses another road).
local Routes={};Routes.__index=Routes
local function key(p) return ('%.4f:%.4f:%.4f'):format(p.x,p.z,p.h) end
function Routes.new(roads,options)
    options=options or {}
    local self=setmetatable({nodes={},destinations={},destinationPoints={},roads=roads,precomputedRoutes={},
        includeTruckOnly=options.includeTruckOnly==true,pavedOnly=options.pavedOnly==true,
        savedRoutesOnly=options.savedRoutesOnly==true},Routes)
    local function node(p)
        local id=key(p)
        if not self.nodes[id] then self.nodes[id]={x=p.x,z=p.z,h=p.h,edges={}} end
        return id,self.nodes[id]
    end
    if not self.savedRoutesOnly then
        for _,s in ipairs(roads.segments) do
            if (options.includeTruckOnly or not s.truckOnly)
                and (not options.pavedOnly or s.surface~='dirt') then
                local a,an=node(s.a);local b,bn=node(s.b)
                an.edges[#an.edges+1]={to=b,length=s.len,bridge=s.bridge}
                if not s.oneWay then bn.edges[#bn.edges+1]={to=a,length=s.len,bridge=s.bridge} end
            end
        end
        for id,p in pairs(roads.destinations) do
            local k=key(p);assert(self.nodes[k],'Unconnected destination: '..id)
            self.destinations[id]=k
            self.destinationPoints[id]={x=p.x,z=p.z,h=p.h}
        end
        for id,p in pairs(options.destinations or {}) do
            local k=key(p);assert(self.nodes[k],'Unconnected extra destination: '..id)
            self.destinations[id]=k
            self.destinationPoints[id]={x=p.x,z=p.z,h=p.h}
        end
    end
    local drivingMap=roads.drivingMap
    if drivingMap and drivingMap.version==2 then
        self.drivingMap=drivingMap
        for _,route in ipairs(drivingMap.routes or {}) do
            local from,to=drivingMap.destinations[route.from],drivingMap.destinations[route.to]
            if from and to then
                self.precomputedRoutes[from..'\0'..to]={route=route,reversed=false}
                if route.bidirectional then
                    self.precomputedRoutes[to..'\0'..from]={route=route,reversed=true}
                end
            end
        end
    end
    return self
end
function Routes:find(from,to)
    local saved=type(from)=='string' and type(to)=='string'
        and self.precomputedRoutes[from..'\0'..to] or nil
    if saved then
        local record,reversed=saved.route,saved.reversed
        local points={}
        for index=1,#record.points do
            local routeIndex=reversed and (#record.points-index+1) or index
            local nodeId=record.points[routeIndex]
            local sourceIndex=(nodeId-1)*3+1
            local x,z,h=self.drivingMap.points[sourceIndex],self.drivingMap.points[sourceIndex+1],
                self.drivingMap.points[sourceIndex+2]
            if not h then return nil,'Invalid saved driving map' end
            points[index]={x=x,z=z,h=h}
        end
        for turnIndex=1,#record.turns,2 do
            local at,speed=record.turns[turnIndex],record.turns[turnIndex+1]
            if reversed then at=#points+1-at end
            local point=points[at]
            if point then point.speedLimit=speed end
        end
        for index=2,#points-1 do
            local before,at,after=points[index-1],points[index],points[index+1]
            local incoming=math.atan2(at.z-before.z,at.x-before.x)
            local outgoing=math.atan2(after.z-at.z,after.x-at.x)
            at.turnAngle=math.atan2(math.sin(outgoing-incoming),math.cos(outgoing-incoming))
        end
        return {from=from,to=to,length=record.length,points=points,crossesBridge=record.bridge}
    end
    if self.savedRoutesOnly then return nil,'No saved route' end
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
    for id,point in pairs(self.destinationPoints) do
        local px,pz=point.x or point[1],point.z or point[2]
        if px and pz and (px-x)^2+(pz-z)^2<=.03^2 then
            local saved=self:find(id,to)
            if saved then saved.from='current-position';return saved end
        end
    end
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
        if (self.includeTruckOnly or not segment.truckOnly)
            and (not self.pavedOnly or segment.surface~='dirt') then
            local a,b=segment.a,segment.b
            local dx,dz=b.x-a.x,b.z-a.z
            local length2=dx*dx+dz*dz
            local t=length2>1e-8 and math.max(0,math.min(1,((x-a.x)*dx+(z-a.z)*dz)/length2)) or 0
            local px,pz=a.x+dx*t,a.z+dz*t
            local off=math.sqrt((x-px)^2+(z-pz)^2)
            projections[#projections+1]={segment=segment,t=t,x=px,z=pz,off=off}
            bestDistance=math.min(bestDistance,off)
        end
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
    local joinDistance=start and math.sqrt((x-start.x)^2+(z-start.z)^2) or 0
    return {from='current-position',to=to,length=distance[finish],points=points,crossesBridge=bridge,
        joinDistance=joinDistance}
end
return Routes
