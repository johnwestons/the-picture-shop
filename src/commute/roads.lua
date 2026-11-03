-- Fixed town geography. All coordinates and elevations are metres.
-- Curve samples drive rendering, grading, collision and route measurements.
local M=require('src.commute.vendor.mathx')
local Sites=require('src.commute.sites')
local Roads={VERSION=3};Roads.__index=Roads
local DefaultLayout=require("src.commute.town_layout")
Roads.destinations=DefaultLayout.destinations
local function cat(a,b,c,d,t)
    return .5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
end
function Roads.new(options)
    options=options or {}
    local self=setmetatable({segments={},paths={},bins={},binSize=16,
        destinations=options.destinations or DefaultLayout.destinations,recreation=options.recreation or {},
        sites=options.sites or Sites.create(),bounds=options.bounds or DefaultLayout.bounds,
        layoutId=options.layoutId or DefaultLayout.id,version=options.version or Roads.VERSION},Roads)
    for _,def in ipairs(options.definitions or DefaultLayout.roads) do
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
    return self
end
function Roads:nearest(x,z,pavedOnly)
    local list=self.bins[math.floor(x/16)..':'..math.floor(z/16)] or {}
    local best,segment,u=math.huge,nil,0
    for _,s in ipairs(list) do
        if not pavedOnly or s.surface~='dirt' then
        local t=M.clamp(((x-s.a.x)*s.dx+(z-s.a.z)*s.dz)/s.length2,0,1)
        local d=M.length(x-s.a.x-t*s.dx,z-s.a.z-t*s.dz)
        if d<best then best,segment,u=d,s,t end
        end
    end
    return best,segment,u
end
function Roads:sample(x,z)
    local d,s,u=self:nearest(x,z)
    if s then return d,s,M.lerp(s.a.h,s.b.h,u) end
    return d,nil,nil
end
function Roads:padAt(x,z)
    for id,p in pairs(self.destinations) do
        local d=M.length(x-p.x,z-p.z)
        if d<9 then return p,d,id end
    end
end
function Roads:grade(base,x,z)
    local distance,s,h=self:sample(x,z)
    local graded=self.sites:grade(base,x,z)
    if s and not s.bridge then
        local blend=1-M.smooth((distance-s.width*.5)/5)
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
    local pad,d=self:padAt(x,z)
    if pad then graded=M.lerp(pad.h,graded,M.smooth((d-5)/4)) end
    -- Roads and parking pads retain their authored elevations across the
    -- broader landscaping apron; building interiors remain perfectly level.
    return self.sites:foundationHeight(x,z) or graded
end
function Roads:supportHeight(world,x,z)
    local d,s,h=self:sample(x,z)
    if s and s.bridge and d<=s.width*.5 then return h,'bridge' end
    if world.infrastructure and world.infrastructure.sidewalkHeight then
        local sidewalk=world.infrastructure:sidewalkHeight(x,z)
        if sidewalk then return sidewalk,'sidewalk' end
    end
    return world:height(x,z),s and d<=s.width*.5 and (s.surface=='dirt' and 'trail' or 'road') or 'terrain'
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
    if h<.25 then return true,'travelLimit' end
    return false
end
function Roads:vegetationAllowed(x,z)
    if not self.sites:vegetationAllowed(x,z) then return false end
    if self:padAt(x,z) then return false end
    for _,area in ipairs(self.recreation) do
        if (x-area.x)^2+(z-area.z)^2<(area.radius+1)^2 then return false end
    end
    if self.infrastructure and self.infrastructure:occupied(x,z,1) then return false end
    local d,s=self:nearest(x,z)
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
