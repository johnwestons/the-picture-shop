local Geometry=require('src.commute.bridge_geometry')
local BridgeArt=require('src.commute.bridge_art')
local Test={}
local function near(a,b,e)return math.abs(a-b)<(e or 1e-6) end
local function finite(v)return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function fixture(angle,scale,ox,oz,elevation)
    angle,scale,ox,oz,elevation=angle or 0,scale or 1,ox or 0,oz or 0,elevation or 0
    local tx,tz=math.cos(angle),math.sin(angle);local nx,nz=-tz,tx
    local function p(distance)return {x=ox+tx*distance*scale,z=oz+tz*distance*scale,h=3.6+elevation} end
    local segments={}
    for i=0,7 do
        local a,b=p(i*5),p((i+1)*5)
        segments[#segments+1]={id='fixture',bridge=true,a=a,b=b,len=5*scale,
            width=5*scale,nx=nx,nz=nz,distance=i*5*scale}
    end
    local world={roads={segments=segments},terrainSamples={}}
    function world:height(x,z)
        self.terrainSamples[#self.terrainSamples+1]={x=x,z=z}
        return 1+elevation+((x-ox)*tx+(z-oz)*tz)*.004+((x-ox)*nx+(z-oz)*nz)*.013
    end
    world.ungradedHeight=world.height
    return world,tx,tz
end
local function area(a,b,c)
    local ux,uy,uz=b[1]-a[1],b[3]-a[3],b[2]-a[2]
    local vx,vy,vz=c[1]-a[1],c[3]-a[3],c[2]-a[2]
    local nx,ny,nz=uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx
    return math.sqrt(nx*nx+ny*ny+nz*nz)*.5
end
local function volume(entry)
    local sum=0
    for i=1,#entry.vertices,3 do
        local a,b,c=entry.vertices[i],entry.vertices[i+1],entry.vertices[i+2]
        local ax,ay,az=a[1]-entry.x,a[3]-entry.h,a[2]-entry.z
        local bx,by,bz=b[1]-entry.x,b[3]-entry.h,b[2]-entry.z
        local cx,cy,cz=c[1]-entry.x,c[3]-entry.h,c[2]-entry.z
        sum=sum+(ax*(by*cz-bz*cy)+ay*(bz*cx-bx*cz)+az*(bx*cy-by*cx))/6
    end
    return sum
end
local function key(v)return ('%.6f,%.6f,%.6f'):format(v[1],v[2],v[3]):gsub('%-0%.000000','0.000000') end
local function closed(entry)
    local edges={}
    for i=1,#entry.vertices,3 do
        for edge=0,2 do
            local a=key(entry.vertices[i+edge]);local b=key(entry.vertices[i+(edge+1)%3])
            if a>b then a,b=b,a end
            local id=a..'/'..b;edges[id]=(edges[id] or 0)+1
        end
    end
    for _,count in pairs(edges) do if count%2~=0 then return false end end
    return true
end
local function counts(pieces)
    local result={vertices=0,bridgeDeck=0,bridgeWall=0,bridgePier=0}
    for _,p in ipairs(pieces) do result[p.kind]=result[p.kind]+1;result.vertices=result.vertices+#p.vertices end
    return result
end
function Test.run(check)
    local world,tx,tz=fixture();local pieces=Geometry.build(world);local count=counts(pieces)
    check('solid bridge keeps one deck group, registered wall bays and two actual piers',
        count.bridgeDeck==1 and count.bridgeWall==#BridgeArt.layout(world.roads)
        and count.bridgePier==#BridgeArt.PIER_FRACTIONS and #pieces<30)
    local valid,topology,solid,bounded=true,true,true,true
    for _,p in ipairs(pieces) do
        valid=valid and #p.vertices>0 and #p.vertices%3==0 and p.center and p.radius>0
        topology=topology and closed(p)
        solid=solid and volume(p)>1e-5
        local b=p.bounds
        bounded=bounded and b.maxX>b.minX and b.maxZ>b.minZ and b.maxH>b.minH
        for i,v in ipairs(p.vertices) do
            valid=valid and #v==12 and near(v[4]^2+v[5]^2+v[6]^2,1,1e-5)
            for _,n in ipairs(v) do valid=valid and finite(n) end
            bounded=bounded and v[1]>=b.minX and v[1]<=b.maxX and v[2]>=b.minZ and v[2]<=b.maxZ
                and v[3]>=b.minH and v[3]<=b.maxH
                and (v[1]-p.x)^2+(v[2]-p.z)^2<=(p.radius+1e-6)^2
            if i%3==1 then valid=valid and area(v,p.vertices[i+1],p.vertices[i+2])>1e-10 end
        end
    end
    check('bridge vertices use finite positions, normalized normals and nondegenerate triangles',valid)
    check('bridge solids close all triangle edges including segment ends',topology)
    check('deck, walls and piers each enclose positive solid volume',solid)
    check('piece bounds enclose complete thickness and all vertices',bounded)
    local deck=pieces[1];local registered=true
    for _,s in ipairs(world.roads.segments) do
        for _,endpoint in ipairs({s.a,s.b}) do for _,side in ipairs({-1,1}) do
            local x,z=endpoint.x+s.nx*side*s.width*.5,endpoint.z+s.nz*side*s.width*.5
            local found=false
            for _,v in ipairs(deck.vertices) do
                if near(v[1],x) and near(v[2],z) and near(v[3],endpoint.h+.045) then found=true;break end
            end
            registered=registered and found
        end end
    end
    check('solid slab retains every original road edge and the 0.045m deck clearance',registered)
    local endOn=true
    for _,p in ipairs(pieces) do
        local facing=0
        for i=1,#p.vertices,3 do
            local v=p.vertices[i];facing=facing+area(v,p.vertices[i+1],p.vertices[i+2])*math.abs(v[4]*tx+v[6]*tz)
        end
        endOn=endOn and facing>.015
    end
    check('every structural piece has visible end-on faces instead of a flat side plane',endOn)
    local piers=BridgeArt.pierLayout(world);local pierIndex=0;local rooted=true
    for _,p in ipairs(pieces) do if p.kind=='bridgePier' then
        pierIndex=pierIndex+1;local expected=piers[pierIndex]
        rooted=rooted and near(p.x,expected.x) and near(p.z,expected.z)
            and near(p.baseHeight,expected.baseHeight) and near(p.topHeight,expected.topHeight)
            and p.bounds.minH<expected.baseHeight and p.bounds.maxH>=expected.topHeight
    end end
    check('pier columns and footings sample terrain and meet the registered girder underside',
        rooted and #world.terrainSamples>=18)
    check('untextured bridge stays within a linear mesh budget',
        count.vertices<=Geometry.MAX_VERTICES_PER_SEGMENT*#world.roads.segments
            +Geometry.MAX_VERTICES_PER_BAY*(count.bridgeWall/2)+2800)
    local placement=true
    for _,setting in ipairs({{math.pi*.5,1,210,-70,9},{math.pi*.37,1.7,-84,160,4}}) do
        local changed=fixture(unpack(setting));local shifted=Geometry.build(changed)
        local before=changed.roads.segments[1].a
        for _,p in ipairs(shifted) do
            placement=placement and p.bounds.minH>setting[5]-.5 and p.bounds.maxH<setting[5]+6
                and volume(p)>0 and closed(p)
        end
        placement=placement and near(shifted[1].x,setting[3]+math.cos(setting[1])*20*setting[2])
            and near(shifted[1].z,setting[4]+math.sin(setting[1])*20*setting[2])
            and before==changed.roads.segments[1].a and near(before.x,setting[3]) and near(before.z,setting[4])
    end
    check('rotated, translated and resized road layouts generate correctly oriented solid bridges',placement)
    local separate=fixture();local gap={id='ordinary-road',bridge=false,a={x=40,z=0,h=3.6},
        b={x=50,z=0,h=3.6},len=10,width=5,nx=0,nz=1}
    separate.roads.segments[#separate.roads.segments+1]=gap
    local another=fixture(0,1,50,0,0)
    for _,s in ipairs(another.roads.segments) do separate.roads.segments[#separate.roads.segments+1]=s end
    local separatePieces=Geometry.build(separate);local separateCounts=counts(separatePieces);local unique={};local uniqueOkay=true
    for _,p in ipairs(separatePieces) do uniqueOkay=uniqueOkay and not unique[p.id];unique[p.id]=true end
    check('disconnected spans with the same road id remain separate and uniquely identified',
        separateCounts.bridgeDeck==2 and separateCounts.bridgePier==4 and uniqueOkay)
    local sampled=fixture();sampled.roads.segments={}
    for i=0,99 do
        sampled.roads.segments[#sampled.roads.segments+1]={id='equal-spaced',bridge=true,
            a={x=32.7+i*1.4,z=-22,h=3.6},b={x=32.7+(i+1)*1.4,z=-22,h=3.6},
            len=1.4,width=5,nx=0,nz=1,distance=i*1.4}
    end
    local regular=Geometry.build(sampled);local nondegenerate=true
    for _,p in ipairs(regular) do for i=1,#p.vertices,3 do
        nondegenerate=nondegenerate and area(p.vertices[i],p.vertices[i+1],p.vertices[i+2])>1e-10
    end end
    check('equally spaced collinear road samples skip floating-point empty bay overlaps',nondegenerate)
    local empty={roads={segments={gap}},height=function()return 0 end}
    check('road networks with no bridge generate no structural geometry',#Geometry.build(empty)==0)
end
return Test
