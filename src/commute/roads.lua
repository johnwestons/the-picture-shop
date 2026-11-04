-- Fixed town geography. All coordinates and elevations are metres.
-- Curve samples drive rendering, grading, collision and route measurements.
local M=require('src.commute.vendor.mathx')
local Sites=require('src.commute.sites')
local Roads={VERSION=5};Roads.__index=Roads
local DefaultLayout=require("src.commute.town_layout")
Roads.destinations=DefaultLayout.destinations
local function cat(a,b,c,d,t)
    return .5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
end
local function junctionCandidates(definitions)
    local groups,ordered={},{}
    -- Match the routing graph's position and elevation key. Iterate in saved
    -- road order so overlapping junctions resolve identically on each client.
    local function key(p)return ('%.4f:%.4f:%.4f'):format(p[1],p[2],p[3]) end
    for _,def in ipairs(definitions) do
        for i=1,#def.points-1 do
            local a,b=def.points[i],def.points[i+1]
            local bridge=def.bridgeEdges and def.bridgeEdges[i]==true
            if not def.bridgeEdges and def.id=='east-bank' and (a[1]+b[1])*.5>=302 and (a[1]+b[1])*.5<=360 then bridge=true end
            for _,endpoint in ipairs({{p=a,other=b},{p=b,other=a}}) do
                local k=key(endpoint.p);local group=groups[k]
                if not group then
                    group={x=endpoint.p[1],z=endpoint.p[2],h=endpoint.p[3],first=def.id,arms={},bridge=false}
                    groups[k]=group
                    ordered[#ordered+1]=group
                end
                if group.first~=def.id then group.shared=true end
                group.arms[#group.arms+1]={dx=endpoint.other[1]-endpoint.p[1],dz=endpoint.other[2]-endpoint.p[2],
                    dh=endpoint.other[3]-endpoint.p[3],role=def.role,width=def.width,surface=def.surface or 'paved',id=def.id,bridge=bridge}
                group.bridge=group.bridge or bridge
            end
        end
    end
    local candidates={}
    for _,group in ipairs(ordered) do
        if group.shared and not group.bridge then candidates[#candidates+1]=group end
    end
    local result={}
    for _,candidate in ipairs(candidates) do
        local maxWidth,minAngle,armCount=0,math.pi,0
        local arms={}
        for _,arm in ipairs(candidate.arms) do
            local length=M.length(arm.dx,arm.dz)
            if length>1e-4 and arm.surface~='dirt' and not arm.bridge then
                arms[#arms+1]={dx=arm.dx/length,dz=arm.dz/length,id=arm.id}
                maxWidth=math.max(maxWidth,arm.width);armCount=armCount+1
            end
        end
        for i=1,#arms-1 do for j=i+1,#arms do
            if arms[i].id~=arms[j].id then
                local dot=M.clamp(arms[i].dx*arms[j].dx+arms[i].dz*arms[j].dz,-1,1)
                local angle=math.acos(dot)
                if angle<math.rad(155) then minAngle=math.min(minAngle,angle) end
            end
        end end
        if armCount>=2 and minAngle<math.pi then
            local half=maxWidth*.5
            local radius=M.clamp(half/math.sin(math.max(minAngle,math.rad(24))*.5),half*1.45,half*2.2)
            local gx,gz,count=0,0,0
            local driveway=false
            for _,arm in ipairs(candidate.arms) do
                if arm.role=='drive' then driveway=true
                elseif arm.role=='local' or arm.role=='main' then
                    local length2=arm.dx^2+arm.dz^2
                    if length2>0 then
                        gx,gz=gx+arm.dx*arm.dh/length2,gz+arm.dz*arm.dh/length2
                        count=count+1
                    end
                end
            end
            if not driveway or count==0 then gx,gz=0,0 else gx,gz=gx/count,gz/count end
            result[#result+1]={x=candidate.x,z=candidate.z,h=candidate.h,radius=radius,outerRadius=radius+.85,
                gx=gx,gz=gz,width=0,surface='paved',bridge=false,junction=true}
        end
    end
    return result
end
Roads.junctionsFor=junctionCandidates
local empty={}
local function cells(x0,z0,x1,z1,size,visit)
    for bx=math.floor(x0/size),math.floor(x1/size) do
        for bz=math.floor(z0/size),math.floor(z1/size) do visit(bx..':'..bz) end
    end
end

-- A town is immutable. Mark the cells whose ground can be modified once,
-- instead of searching every address at every height and normal sample.
local function indexGround(roads)
    local size=roads.binSize
    local marked={}
    local function mark(k) marked[k]=true end
    for k in pairs(roads.bins) do mark(k) end
    for k in pairs(roads.junctionBins) do mark(k) end
    for _,area in ipairs(roads.recreation) do
        local r=area.radius+2
        cells(area.x-r,area.z-r,area.x+r,area.z+r,size,mark)
    end
    if roads.sites.bins then
        local siteSize=roads.sites.binSize
        for k in pairs(roads.sites.bins) do
            local x,z=k:match('^(%-?%d+):(%-?%d+)$')
            x,z=tonumber(x)*siteSize,tonumber(z)*siteSize
            cells(x,z,x+siteSize-.001,z+siteSize-.001,size,mark)
        end
        roads.gradedCells=marked
    end
    roads.padBins={}
    for id,p in pairs(roads.destinations) do
        local site=roads.sites.byId and roads.sites.byId[id]
        local anchor=site and site.parking or p
        local reach=9
        if site then
            for _,rect in ipairs({site.localParking,site.localTruckParkingArea,site.localTruckApproach}) do
                if rect then
                    local parking=site.design.parking
                    local dx=math.max(math.abs(rect.minX-parking.x),math.abs(rect.maxX-parking.x))*site.scale.x
                    local dz=math.max(math.abs(rect.minZ-parking.z),math.abs(rect.maxZ-parking.z))*site.scale.z
                    reach=math.max(reach,M.length(dx,dz)+9)
                end
            end
        end
        local pad={site=site,anchor=anchor,id=id}
        cells(anchor.x-reach,anchor.z-reach,anchor.x+reach,anchor.z+reach,size,function(k)
            mark(k)
            local bin=roads.padBins[k] or {}
            roads.padBins[k]=bin
            bin[#bin+1]=pad
        end)
    end
end
function Roads.new(options)
    options=options or {}
    local definitions=options.definitions or DefaultLayout.roads
    local self=setmetatable({segments={},paths={},bins={},junctions={},junctionBins={},binSize=16,
        destinations=options.destinations or DefaultLayout.destinations,recreation=options.recreation or {},
        sites=options.sites or Sites.create(),bounds=options.bounds or DefaultLayout.bounds,
        layoutId=options.layoutId or DefaultLayout.id,version=options.version or Roads.VERSION},Roads)
    for _,def in ipairs(definitions) do
        local path={id=def.id,width=def.width,points={},length=0,role=def.role,
            surface=def.surface or 'paved',lanes=def.lanes,oneWay=def.oneWay,
            turnLane=def.turnLane,sidewalks=def.sidewalks}
        self.paths[#self.paths+1]=path
        for i=1,#def.points-1 do
            local a,b,c,d=def.points[math.max(1,i-1)],def.points[i],def.points[i+1],def.points[math.min(#def.points,i+2)]
            local steps=math.max(1,math.ceil(M.length(c[1]-b[1],c[2]-b[2])/1.5))
            for j=0,steps-1 do
                local t=j/steps
                path.points[#path.points+1]={x=def.interpolation=='linear' and M.lerp(b[1],c[1],t) or cat(a[1],b[1],c[1],d[1],t),
                    z=def.interpolation=='linear' and M.lerp(b[2],c[2],t) or cat(a[2],b[2],c[2],d[2],t),
                    h=M.lerp(b[3],c[3],def.interpolation=='linear' and t or M.smooth(t)),
                    bridge=def.bridgeEdges and def.bridgeEdges[i]==true}
            end
        end
        local p=def.points[#def.points];path.points[#path.points+1]={x=p[1],z=p[2],h=p[3]}
        for i,v in ipairs(path.points) do
            local a,b=path.points[math.max(1,i-1)],path.points[math.min(#path.points,i+1)]
            local dx,dz=b.x-a.x,b.z-a.z;local length=M.length(dx,dz)
            v.nx,v.nz=-dz/length,dx/length
        end
        for i=1,#path.points-1 do
            local a,b=path.points[i],path.points[i+1];local dx,dz=b.x-a.x,b.z-a.z;local len=M.length(dx,dz)
            local s={a=a,b=b,dx=dx,dz=dz,len=len,length2=len*len,width=def.width,id=def.id,distance=path.length}
            s.path=path;s.role,s.surface,s.lanes=path.role,path.surface,path.lanes
            s.priority=path.surface=='dirt' and 1 or path.role=='drive' and 2 or 3
            s.oneWay,s.turnLane,s.sidewalks=path.oneWay,path.turnLane,path.sidewalks
            s.bridge=def.bridgeEdges and a.bridge==true
                or not def.bridgeEdges and def.id=='east-bank' and (a.x+b.x)*.5>=302 and (a.x+b.x)*.5<=360
            s.nx,s.nz=-dz/len,dx/len;path.length=path.length+len
            self.segments[#self.segments+1]=s
            local reach=def.width*.5+7
            for bx=math.floor((math.min(a.x,b.x)-reach)/16),math.floor((math.max(a.x,b.x)+reach)/16) do
                for bz=math.floor((math.min(a.z,b.z)-reach)/16),math.floor((math.max(a.z,b.z)+reach)/16) do
                    local key=bx..':'..bz;self.bins[key]=self.bins[key] or {};table.insert(self.bins[key],s)
                end
            end
        end
    end
    self.junctions=junctionCandidates(definitions)
    for _,junction in ipairs(self.junctions) do
        local reach=junction.outerRadius+6
        for bx=math.floor((junction.x-reach)/self.binSize),math.floor((junction.x+reach)/self.binSize) do
            for bz=math.floor((junction.z-reach)/self.binSize),math.floor((junction.z+reach)/self.binSize) do
                local key=bx..':'..bz;self.junctionBins[key]=self.junctionBins[key] or {}
                self.junctionBins[key][#self.junctionBins[key]+1]=junction
            end
        end
    end
    indexGround(self)
    return self
end
function Roads:nearest(x,z,pavedOnly)
    local key=math.floor(x/16)..':'..math.floor(z/16)
    local list=self.bins[key] or empty
    local best,segment,u,priority=math.huge,nil,0,0
    for _,s in ipairs(list) do
        if not pavedOnly or s.surface~='dirt' then
        local t=M.clamp(((x-s.a.x)*s.dx+(z-s.a.z)*s.dz)/s.length2,0,1)
        local d=M.length(x-s.a.x-t*s.dx,z-s.a.z-t*s.dz)
        local rank=d<=s.width*.5 and s.priority or 0
        if rank>priority or rank==priority and d<best then best,segment,u,priority=d,s,t,rank end
        end
    end
    if priority>=2 then return best,segment,u end
    local junctions=self.junctionBins[key] or empty
    for _,junction in ipairs(junctions) do
        if not pavedOnly or junction.surface~='dirt' then
            local d=math.max(0,M.length(x-junction.x,z-junction.z)-junction.outerRadius)
            if (priority==0 or d==0) and d<best then best,segment,u=d,junction,0 end
        end
    end
    return best,segment,u
end
function Roads:sample(x,z)
    local d,s,u=self:nearest(x,z)
    if s and s.junction then return d,s,s.h+(x-s.x)*s.gx+(z-s.z)*s.gz end
    if s then return d,s,M.lerp(s.a.h,s.b.h,u) end
    return d,nil,nil
end
function Roads:padAt(x,z)
    local key=math.floor(x/self.binSize)..':'..math.floor(z/self.binSize)
    for _,pad in ipairs(self.padBins[key] or empty) do
        local d=pad.site and pad.site:parkingDistance(x,z) or M.length(x-pad.anchor.x,z-pad.anchor.z)
        if d<9 then return pad.anchor,d,pad.id end
    end
end
function Roads:grade(base,x,z)
    if self.gradedCells and not self.gradedCells[math.floor(x/self.binSize)..':'..math.floor(z/self.binSize)] then return base end
    local distance,s,h=self:sample(x,z)
    if s and not s.bridge and distance<=s.width*.5 then return self.sites:foundationHeight(x,z) or h end
    local graded=self.sites:grade(base,x,z)
    local pad,d=self:padAt(x,z)
    if pad then graded=M.lerp(pad.h,graded,M.smooth((d-5)/4)) end
    if s and not s.bridge then
        local blend=s.junction and 1-M.smooth(distance/5) or 1-M.smooth((distance-s.width*.5)/5)
        graded=M.lerp(graded,h,blend)
    end
    for _,area in ipairs(self.recreation) do
        local dx,dz=x-area.x,z-area.z;local reach=area.radius+2
        if math.abs(dx)<reach and math.abs(dz)<reach then
            local d=M.length(dx,dz)
            local blend=1-M.smooth((d-area.radius)/2)
            if s then blend=blend*M.smooth((distance-s.width*.5)/1.5) end
            graded=M.lerp(graded,area.h,blend)
        end
    end
    -- Roads and parking pads retain their authored elevations across the
    -- broader landscaping apron; building interiors remain perfectly level.
    return self.sites:foundationHeight(x,z) or graded
end
function Roads:supportHeight(world,x,z)
    local d,s,h=self:sample(x,z)
    if s and s.bridge and d<=s.width*.5 then return h,'bridge' end
    if s and d<=s.width*.5 then
        local foundation=self.sites.foundationHeight and self.sites:foundationHeight(x,z)
        return foundation or h,s.surface=='dirt' and 'trail' or 'road'
    end
    if world.infrastructure and world.infrastructure.sidewalkHeight then
        local sidewalk=world.infrastructure:sidewalkHeight(x,z)
        if sidewalk then return sidewalk,'sidewalk' end
    end
    return world:height(x,z),'terrain'
end
function Roads:blocked(world,x,z,skipFixtureCollision)
    local bounds=self.bounds
    if x<bounds.x0 or z<bounds.z0 or x>bounds.x1 or z>bounds.z1 then return true,'travelLimit' end
    if self.sites:blocked(x,z) then return true end
    if not skipFixtureCollision and world.infrastructure and world.infrastructure:blocked(x,z) then return true end
    local h,kind=self:supportHeight(world,x,z)
    if kind=='bridge' then return false end
    local d,s=self:sample(x,z)
    if s and s.bridge and d<s.width*.5+1.2 then return true end -- bridge rails
    if h<.25 then
        local plan=world.plan
        if plan and plan.settings and plan.settings.river==1 and h>=-.13 and plan:shoreDistance(x,z)>4
            and not plan:lakeAt(x,z) then
            local distance,_,_,segment=plan:riverDistance(x,z)
            if segment and distance<segment.valleyWidth then return false end
        end
        return true,'travelLimit'
    end
    return false
end
function Roads:vegetationAllowed(x,z)
    if not self.sites:vegetationAllowed(x,z) then return false end
    local _,padDistance=self:padAt(x,z)
    if padDistance and padDistance<.8 then return false end
    for _,area in ipairs(self.recreation) do
        if (x-area.x)^2+(z-area.z)^2<(area.radius+1)^2 then return false end
    end
    if self.infrastructure and self.infrastructure:occupied(x,z,1) then return false end
    local d,s=self:nearest(x,z)
    if s and s.junction then return d>1.2 end
    -- Keep even the largest roadside rock outside the narrow trail's usable width.
    return not s or d>s.width*.5+(s.surface=='dirt' and 4.9 or 2.2)
end
function Roads:attach(world)
    local terrainHeight=world.height
    world.ungradedHeight=terrainHeight;world.roads=self;world.sites=self.sites
    world.playableBounds=self.bounds
    function world:height(x,z) return self.roads:grade(terrainHeight(self,x,z),x,z) end
    function world:supportHeight(x,z) return self.roads:supportHeight(self,x,z) end
    return world
end
return Roads
