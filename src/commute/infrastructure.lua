-- Derive street furniture from the frozen road network. Distances are metres.
-- The same geometry records feed the renderer and spatially indexed collisions.
local M = require('src.commute.vendor.mathx')
local Infrastructure = {}
Infrastructure.__index = Infrastructure
local CELL = 12
local function key(x,z) return math.floor(x/CELL)..':'..math.floor(z/CELL) end
local function nodeKey(x,z) return math.floor(x*100+.5)..':'..math.floor(z*100+.5) end
local function closest(x,z,ax,az,bx,bz)
    local dx,dz=bx-ax,bz-az
    local u=M.clamp(((x-ax)*dx+(z-az)*dz)/math.max(1e-16,dx*dx+dz*dz),0,1)
    local ox,oz=x-ax-u*dx,z-az-u*dz
    return ox*ox+oz*oz,ox,oz,u
end
local function addCollider(plan,kind,ax,az,bx,bz,ha,hb,radius,height)
    local shape={kind=kind,ax=ax,az=az,bx=bx,bz=bz,ha=ha,hb=hb,radius=radius,height=height,id=#plan.solids+1}
    plan.solids[#plan.solids+1]=shape
    for ix=math.floor((math.min(ax,bx)-radius)/CELL),math.floor((math.max(ax,bx)+radius)/CELL) do
        for iz=math.floor((math.min(az,bz)-radius)/CELL),math.floor((math.max(az,bz)+radius)/CELL) do
            local k=ix..':'..iz
            local bin=plan.bins[k] or {}
            bin[#bin+1]=shape
            plan.bins[k]=bin
        end
    end
end
function Infrastructure:blocked(x,z)
    local bin=self.bins[key(x,z)]
    if bin then for _,s in ipairs(bin) do
        if closest(x,z,s.ax,s.az,s.bx,s.bz)<=s.radius^2 then return true end
    end end
    return false
end
function Infrastructure:occupied(x,z,margin)
    margin=margin or 0
    for ix=math.floor((x-margin)/CELL),math.floor((x+margin)/CELL) do
        for iz=math.floor((z-margin)/CELL),math.floor((z+margin)/CELL) do
            local bin=self.bins[ix..':'..iz]
            if bin then for _,s in ipairs(bin) do
                if closest(x,z,s.ax,s.az,s.bx,s.bz)<=(s.radius+margin)^2 then return true end
            end end
        end
    end
    return false
end

local function triangleHeight(x,z,a,b,c)
    local bx,bz=b[1]-a[1],b[2]-a[2]
    local cx,cz=c[1]-a[1],c[2]-a[2]
    local det=bx*cz-bz*cx
    if math.abs(det)<1e-10 then return nil end
    local u=((x-a[1])*cz-(z-a[2])*cx)/det
    local v=(bx*(z-a[2])-bz*(x-a[1]))/det
    if u>=-1e-8 and v>=-1e-8 and u+v<=1.00000001 then
        return a[3]+u*(b[3]-a[3])+v*(c[3]-a[3])
    end
end
function Infrastructure:sidewalkHeight(x,z)
    local bin=self.walkBins[key(x,z)]
    if bin then for _,walk in ipairs(bin) do
        local p=walk.corners
        local h=triangleHeight(x,z,p[1],p[2],p[3]) or triangleHeight(x,z,p[1],p[3],p[4])
        if h then return h end
    end end
end
function Infrastructure:sidewalkDistance(x,z,reach)
    if self:sidewalkHeight(x,z) then return 0 end
    reach=reach or 3
    local best,seen=math.huge,{}
    for ix=math.floor((x-reach)/CELL),math.floor((x+reach)/CELL) do
        for iz=math.floor((z-reach)/CELL),math.floor((z+reach)/CELL) do
            for _,walk in ipairs(self.walkBins[ix..':'..iz] or {}) do
                if not seen[walk] then
                    seen[walk]=true;local p=walk.corners
                    for i=1,4 do
                        local a,b=p[i],p[i%4+1]
                        local distance2=closest(x,z,a[1],a[2],b[1],b[2])
                        best=math.min(best,distance2)
                    end
                end
            end
        end
    end
    return math.sqrt(best)
end
-- Most slabs need only their two end cross-sections. Resolve a local rise
-- between them before indexing, so the walk and its support follow the ground.
local function refineWalks(plan)
    local refined={}
    local function middle(a,b)
        local x,z=(a[1]+b[1])*.5,(a[2]+b[2])*.5
        local ground=plan.world:height(x,z)
        return {x,z,ground+.105,ground}
    end
    local function add(w,p,depth)
        local left,right=middle(p[1],p[2]),middle(p[4],p[3])
        local x,z=(left[1]+right[1])*.5,(left[2]+right[2])*.5
        local top=math.max(left[3],right[3],plan.world:height(x,z)+.105)
        if depth<3 and top>(p[1][3]+p[2][3])*.5+.018 then
            left[3],right[3]=top,top
            add(w,{p[1],left,right,p[4]},depth+1)
            -- Each slab owns its corners because the gap ramps are applied later.
            add(w,{{unpack(left)},p[2],p[3],{unpack(right)}},depth+1)
        else
            refined[#refined+1]={kind=w.kind,roadId=w.roadId,side=w.side,corners=p,x=x,z=z}
        end
    end
    for _,w in ipairs(plan.walks) do
        local p=w.corners
        for _,pair in ipairs({{1,4},{2,3}}) do
            local a,b=p[pair[1]],p[pair[2]]
            local top=math.max(a[3],b[3],plan.world:height((a[1]+b[1])*.5,(a[2]+b[2])*.5)+.105)
            a[3],b[3]=top,top
        end
        add(w,p,0)
    end
    plan.walks=refined
end
local function joins(a,b)
    if not a or not b or a.roadId~=b.roadId or a.side~=b.side then return false end
    local left,right=a.corners[2],b.corners[1]
    return math.abs(left[1]-right[1])+math.abs(left[2]-right[2])<.0001
end
local function indexWalks(plan)
    for i,walk in ipairs(plan.walks) do
        local p=walk.corners
        local prev,nextWalk=plan.walks[i-1],plan.walks[i+1]
        -- Taper each discontinuous run down to a driveway or intersection.
        if not joins(prev,walk) then
            p[1][3]=p[1][3]-.08;p[4][3]=p[4][3]-.08
        end
        if not joins(walk,nextWalk) then
            p[2][3]=p[2][3]-.08;p[3][3]=p[3][3]-.08
        end
        local x0,z0,x1,z1=p[1][1],p[1][2],p[1][1],p[1][2]
        for _,v in ipairs(p) do
            x0,z0,x1,z1=math.min(x0,v[1]),math.min(z0,v[2]),math.max(x1,v[1]),math.max(z1,v[2])
        end
        for ix=math.floor(x0/CELL),math.floor(x1/CELL) do for iz=math.floor(z0/CELL),math.floor(z1/CELL) do
            local k=ix..':'..iz;local bin=plan.walkBins[k] or {}
            bin[#bin+1]=walk;plan.walkBins[k]=bin
        end end
    end
end

-- Swept disc against a finite capsule (round rail ends and cylindrical posts).
local function contact(s,x,z,vx,vz,r,bottom,top)
    local distance,ox,oz,u=closest(x,z,s.ax,s.az,s.bx,s.bz)
    local total=r+s.radius
    local function at(t,nx,nz,fraction)
        local h=s.ha+(s.hb-s.ha)*fraction
        if bottom and bottom>=h+s.height or top and top<=h then return nil end
        local length=M.length(nx,nz)
        if length<1e-8 then return t,1,0 end
        return t,nx/length,nz/length
    end
    local speed2=vx*vx+vz*vz
    if distance<=total^2+1e-10 then
        if speed2>1e-16 and vx*ox+vz*oz>=-1e-12 then return nil end
        return at(0,ox,oz,u)
    end
    if speed2<1e-16 then return nil end
    local dx,dz=s.bx-s.ax,s.bz-s.az
    local length=M.length(dx,dz)
    local best,hx,hz
    local function consider(t,nx,nz,fraction)
        if t and t>=0 and t<=1 and (not best or t<best) then
            local hit,normalX,normalZ=at(t,nx,nz,fraction)
            if hit then best,hx,hz=hit,normalX,normalZ end
        end
    end
    if length>.00001 then
        local tx,tz=dx/length,dz/length
        local nx,nz=-tz,tx
        local normalSpeed=vx*nx+vz*nz
        local offset=(x-s.ax)*nx+(z-s.az)*nz
        if math.abs(normalSpeed)>1e-10 then
            local side=normalSpeed<0 and 1 or -1
            local t=(total*side-offset)/normalSpeed
            local along=(x+vx*t-s.ax)*tx+(z+vz*t-s.az)*tz
            if along>=0 and along<=length then consider(t,side*nx,side*nz,along/length) end
        end
    end
    local function cap(cx,cz,fraction)
        local px,pz=x-cx,z-cz
        local dot=px*vx+pz*vz
        local discriminant=dot*dot-speed2*(px*px+pz*pz-total*total)
        if dot<0 and discriminant>=0 then
            local t=(-dot-math.sqrt(discriminant))/speed2
            consider(t,px+t*vx,pz+t*vz,fraction)
        end
    end
    cap(s.ax,s.az,0)
    if length>.00001 then cap(s.bx,s.bz,1) end
    return best,hx,hz
end
function Infrastructure:sweep(x,z,nx,nz,radius,bottom,top)
    local best,hx,hz,kind,id
    for ix=math.floor((math.min(x,nx)-radius)/CELL),math.floor((math.max(x,nx)+radius)/CELL) do
        for iz=math.floor((math.min(z,nz)-radius)/CELL),math.floor((math.max(z,nz)+radius)/CELL) do
            local bin=self.bins[ix..':'..iz]
            if bin then for _,s in ipairs(bin) do
                local t,a,b=contact(s,x,z,nx-x,nz-z,radius,bottom,top)
                if t and (not best or t<best-1e-10 or math.abs(t-best)<1e-10 and s.id<id) then
                    best,hx,hz,kind,id=t,a,b,s.kind,s.id
                end
            end end
        end
    end
    return best,hx,hz,kind,id
end

-- Saved path definitions have junction nodes but no dense renderer tessellation.
local function measure(road)
    local path={id=road.id,role=road.role,width=road.width,sidewalks=road.sidewalks,oneWay=road.oneWay,
        edges={},length=0}
    for i=1,#road.points-1 do
        local a,b=road.points[i],road.points[i+1]
        local dx,dz=b[1]-a[1],b[2]-a[2]
        local length=M.length(dx,dz)
        if length>.001 then
            path.edges[#path.edges+1]={x=a[1],z=a[2],dx=dx/length,dz=dz/length,length=length,start=path.length,
                bridge=road.bridgeEdges and road.bridgeEdges[i]}
            path.length=path.length+length
        end
    end
    return path
end
local function along(path,d)
    d=M.clamp(d,0,path.length)
    for i,edge in ipairs(path.edges) do
        if d<=edge.start+edge.length+.00001 or i==#path.edges then
            return edge.x+edge.dx*(d-edge.start),edge.z+edge.dz*(d-edge.start),edge
        end
    end
end
local function available(world,path,x,z,margin)
    local bounds=world.roads.bounds
    if x<=bounds.x0+margin or x>=bounds.x1-margin or z<=bounds.z0+margin or z>=bounds.z1-margin then return false end
    local bin=world.roads.bins[math.floor(x/16)..':'..math.floor(z/16)] or {}
    for _,seg in ipairs(bin) do
        if seg.id~=path.id and closest(x,z,seg.a.x,seg.a.z,seg.b.x,seg.b.z)<(seg.width*.5+margin)^2 then return false end
    end
    for _,s in ipairs(world.sites.all) do
        if s:distance(x,z)<margin+.3 then return false end
        if (x-s.parking.x)^2+(z-s.parking.z)^2<(6+margin)^2 then return false end
    end
    return world:height(x,z)>.35
end
local dimensions={lamp={.14,3.6},mailbox={.22,1.2},stop={.08,2.6},curve={.08,2.6},
    table={.85,.8},bench={.55,.88},fireRing={.72,.28},tent={1.05,1.48},trailSign={.16,1.65}}
local function fixture(plan,kind,x,z,fx,fz,roadId)
    local size=dimensions[kind]
    if plan:occupied(x,z,size[1]+.6) then return end
    local h=plan:sidewalkHeight(x,z) or plan.world:height(x,z)
    if h<=.35 then return end
    local f={kind=kind,x=x,z=z,h=h,fx=fx,fz=fz,roadId=roadId}
    plan.fixtures[#plan.fixtures+1]=f
    plan.counts[kind]=(plan.counts[kind] or 0)+1
    addCollider(plan,kind,x,z,x,z,h,h,size[1],size[2])
    return f
end
local function offset(path,d,side,lateral)
    local x,z,e=along(path,d)
    return x-e.dz*side*lateral,z+e.dx*side*lateral,e
end
local function walksAndRails(plan,path)
    local world=plan.world
    local width=path.role=='main' and 1.8 or 1.35
    local curb=path.width*.5+.15
    local count=math.max(1,math.ceil(path.length/3))
    for _,side in ipairs({1,-1}) do
        for i=1,count do
            local start,finish=(i-1)*path.length/count,i*path.length/count
            local mid=(start+finish)*.5
            local cx,cz,edge=offset(path,mid,side,curb+width*.5)
            local px,pz,first=offset(path,start,side,curb+width*.5)
            local qx,qz,last=offset(path,finish,side,curb+width*.5)
            if not edge.bridge and not first.bridge and not last.bridge
                and available(world,path,px,pz,width*.5+.3) and available(world,path,qx,qz,width*.5+.3)
                and available(world,path,cx,cz,width*.5+.3) then
                if path.sidewalks then
                    local corners={}
                    for _,point in ipairs({{start,curb},{finish,curb},{finish,curb+width},{start,curb+width}}) do
                        local x,z=offset(path,point[1],side,point[2])
                        local ground=world:height(x,z)
                        corners[#corners+1]={x,z,ground+.105,ground}
                    end
                    -- Bench the walk across its width even where the far edge
                    -- of the road shoulder falls away. Its exposed side is solid.
                    corners[1][3]=math.max(corners[1][3],corners[4][3]);corners[4][3]=corners[1][3]
                    corners[2][3]=math.max(corners[2][3],corners[3][3]);corners[3][3]=corners[2][3]
                    plan.walks[#plan.walks+1]={kind='sidewalk',roadId=path.id,corners=corners,side=side}
                end
                local railOffset=curb+(path.sidewalks and width+.35 or .65)
                local rx,rz=offset(path,mid,side,railOffset)
                local outerX,outerZ=offset(path,mid,side,railOffset+7)
                local h=world:height(rx,rz)
                local drop=h-world:height(outerX,outerZ)
                local ax,az=offset(path,start,side,railOffset)
                local bx,bz=offset(path,finish,side,railOffset)
                if drop>1.55 and h>.45 and available(world,path,ax,az,.45)
                    and available(world,path,bx,bz,.45) and available(world,path,rx,rz,.45) then
                    local ha,hb=world:height(ax,az),world:height(bx,bz)
                    local rail={kind='guardrail',roadId=path.id,x=rx,z=rz,ax=ax,az=az,bx=bx,bz=bz,ha=ha,hb=hb,drop=drop}
                    plan.rails[#plan.rails+1]=rail
                    addCollider(plan,'guardrail',ax,az,bx,bz,ha,hb,.16,.85)
                end
            end
        end
    end
end
local function addLamps(plan,path,seed)
    if not path.sidewalks then return end
    local spacing=path.role=='main' and 19 or 42
    for _,side in ipairs({1,-1}) do
        local start=7+(seed+#path.id*5+(side==1 and 11 or 0))%math.floor(spacing*.55)
        for d=start,path.length-5,spacing do
            local x,z,e=offset(path,d,side,path.width*.5+1.4)
            if not e.bridge and available(plan.world,path,x,z,.7) then
                fixture(plan,'lamp',x,z,e.dz*side,-e.dx*side,path.id)
            end
        end
    end
end
local function mailboxes(plan,paths,town)
    for _,p in ipairs(town.placements or {}) do
        local frontage=paths[p.frontageRoadId]
        local drive=paths[p.id..'-drive']
        if frontage and drive and p.district=='residential' then
            local anchorX,anchorZ=along(drive,0)
            local nearest,best=0,math.huge
            for _,e in ipairs(frontage.edges) do
                local dist,_,_,u=closest(anchorX,anchorZ,e.x,e.z,e.x+e.dx*e.length,e.z+e.dz*e.length)
                if dist<best then best,nearest=dist,e.start+u*e.length end
            end
            local _,_,edge=along(frontage,nearest)
            local side=(p.origin.x-anchorX)*(-edge.dz)+(p.origin.z-anchorZ)*edge.dx>=0 and 1 or -1
            for _,shift in ipairs({3.2,-3.2,4.5,-4.5,6,-6}) do
                local x,z,e=offset(frontage,nearest+shift,side,frontage.width*.5+1.25)
                if available(plan.world,frontage,x,z,.5) and fixture(plan,'mailbox',x,z,e.dz*side,-e.dx*side,frontage.id) then break end
            end
        end
    end
end
local function approachSign(plan,path,atStart,kind,turn)
    local direction=atStart and -1 or 1
    if path.oneWay and atStart then return end
    for _,setback in ipairs(kind=='stop' and {7,9,11,13} or {15,18,20}) do
        if setback>path.length*.45 then break end
        local d=atStart and setback or path.length-setback
        local px,pz,e=along(path,d)
        local dx,dz=e.dx*direction,e.dz*direction
        local x,z=px-dz*(path.width*.5+1.3),pz+dx*(path.width*.5+1.3)
        if not e.bridge and available(plan.world,path,x,z,.65) then
            local sign=fixture(plan,kind,x,z,-dx,-dz,path.id)
            if sign then
                sign.turn=turn or 1
                sign.roadWidth=path.width
                sign.oneWay=path.oneWay==true
                sign.stopX,sign.stopZ=px,pz
                return sign
            end
        end
    end
end
local function signs(plan,junctions)
    for _,node in ipairs(junctions) do
        local branches=node.branches
        local mainCount=0
        for _,b in ipairs(branches) do if b.path.role=='main' then mainCount=mainCount+1 end end
        if #branches>=3 then
            for _,b in ipairs(branches) do
                if mainCount==0 or mainCount>=3 or b.path.role~='main' then
                    approachSign(plan,b.path,b.atStart,'stop')
                end
            end
        elseif #branches==2 then
            local a,b=branches[1],branches[2]
            local dot=a.dx*b.dx+a.dz*b.dz
            if dot>-.90 and dot<.7 then
                local turn=a.dz*b.dx-a.dx*b.dz
                approachSign(plan,a.path,a.atStart,'curve',turn)
                approachSign(plan,b.path,b.atStart,'curve',-turn)
            end
        end
    end
end
local function recreation(plan,town)
    for _,area in ipairs(town.recreation or {}) do
        local fx,fz=math.cos(area.heading or 0),math.sin(area.heading or 0)
        local function place(kind,side,forward)
            local x=area.x+fz*side+fx*forward
            local z=area.z-fx*side+fz*forward
            if (side^2+forward^2)^.5+dimensions[kind][1]>area.radius then return end
            if plan.world.roads:padAt(x,z) or plan.world.sites:blocked(x,z) then return end
            local d,s=plan.world.roads:nearest(x,z)
            if s and d<s.width*.5+dimensions[kind][1]+.2 then return end
            fixture(plan,kind,x,z,fx,fz,area.trailId)
        end
        if area.kind=='camp' then place('tent',1.7,.8);place('fireRing',-1.7,-1);place('bench',-.8,2.4)
        elseif area.kind=='picnic' then place('table',0,0);place('bench',1,2.8)
        else place('bench',-1.8,0);place('table',1.7,1) end
        place('trailSign',0,-area.radius+.85)
    end
end
function Infrastructure.new(world,options)
    local plan=setmetatable({world=world,fixtures={},walks={},rails={},solids={},bins={},walkBins={},counts={}},Infrastructure)
    local town=world.town
    if not town or (town.generatorVersion or 0)<3 and not (options and options.enabled) then return plan end
    local lookup,streets,junctions,byNode={},{},{},{}
    for _,road in ipairs(town.roads) do
        local path=measure(road)
        lookup[path.id]=path
        if #path.edges>0 and (path.role=='main' or path.role=='local') then
            streets[#streets+1]=path
            for _,start in ipairs({true,false}) do
                local x,z,e=along(path,start and 0 or path.length)
                local k=nodeKey(x,z)
                local node=byNode[k]
                if not node then node={branches={}};byNode[k]=node;junctions[#junctions+1]=node end
                local dir=start and 1 or -1
                node.branches[#node.branches+1]={path=path,atStart=start,dx=e.dx*dir,dz=e.dz*dir}
            end
        end
    end
    for _,path in ipairs(streets) do walksAndRails(plan,path) end
    refineWalks(plan)
    indexWalks(plan)
    signs(plan,junctions)
    mailboxes(plan,lookup,town)
    for _,path in ipairs(streets) do addLamps(plan,path,town.seed) end
    recreation(plan,town)
    plan.counts.sidewalk=#plan.walks
    plan.counts.guardrail=#plan.rails
    return plan
end
function Infrastructure.ensure(world)
    if not world.town or (world.town.generatorVersion or 0)<3 then return Infrastructure.new(world) end
    if not world.infrastructure then
        world.infrastructure=Infrastructure.new(world)
        world.roads.infrastructure=world.infrastructure
    end
    return world.infrastructure
end
return Infrastructure
