-- A town is immutable playthrough data. Generation happens only in setup;
-- world construction reads the saved terrain, roads and local-design placements.
local Sites=require('src.commute.sites')
local Default=require('src.commute.town_layout')
local M=require('src.commute.vendor.mathx')
local Options=require('src.commute.island_options')
local Town={VERSION=1,GENERATOR_VERSION=9,MIN_SEED=1,MAX_SEED=2147483646}
local islandBounds={x0=6,z0=6,x1=506,z1=506}
-- Generated labels are part of the saved seed fingerprint. Current signage
-- is applied to the runtime destinations without mutating a town or preset.
local names={warehouse='The Picture Shop',['brick-walkup']='Brick walk-up',garden='Garden apartment',
    courtyard='Courtyard apartments',corner='Corner apartment',mechanic='WrenchWorks Garage',
    ['gas-station']='Gas Station',grocery='Town Grocery',['post-office']='Post Office',police='Police Station',
    ['fire-station']='Fire Station',diner='Town Diner',['coffee-shop']='Coffee Shop',
    ['general-store']='General Store'}
local function plain(value)
    local active,count={},0
    local function visit(v,depth)
        count=count+1;if count>30000 or depth>14 then return false end
        if type(v)=='number' then return M.finite(v) end
        if type(v)=='string' then return #v<=160 end
        if type(v)=='boolean' or v==nil then return true end
        if type(v)~='table' or active[v] then return false end
        active[v]=true
        for k,item in pairs(v) do
            if type(k)~='string' and type(k)~='number' or not visit(k,depth+1) or not visit(item,depth+1) then return false end
        end
        active[v]=nil;return true
    end
    return visit(value,0)
end
local function copyUnchecked(v)
    if type(v)~='table' then return v end
    local out={};for k,item in pairs(v) do out[k]=copyUnchecked(item) end;return out
end
local function copy(v)
    assert(plain(v),'Town data must be bounded finite plain data')
    return copyUnchecked(v)
end
Town.copy=copy
local function integer(v,lo,hi)return M.finite(v) and v%1==0 and v>=lo and v<=hi end
local function point(p,lo,hi)
    return type(p)=='table' and M.finite(p.x) and M.finite(p.z) and M.finite(p.h)
        and p.x>=lo and p.x<=hi and p.z>=lo and p.z<=hi and p.h>=-2 and p.h<=84
end
local function withinBounds(x,z,h,bounds)
    return M.finite(x) and M.finite(z) and M.finite(h)
        and x>=bounds.x0 and x<=bounds.x1 and z>=bounds.z0 and z<=bounds.z1 and h>=-2 and h<=84
end
local function array(t,maximum)
    if type(t)~='table' or #t>maximum then return false end
    local count=0;for k in pairs(t) do if not integer(k,1,#t) then return false end;count=count+1 end
    return count==#t
end
function Town.valid(t)
    if not plain(t) or type(t)~='table' or t.version~=1
        or not integer(t.generatorVersion,0,Town.GENERATOR_VERSION) then return false end
    if t.generatorVersion>=6 and (type(t.terrain)~='table' or not Options.valid(t.terrain.settings)) then return false end
    local expectedBounds=t.generatorVersion>=4 and islandBounds or Default.bounds
    local function townPoint(p,lo,hi)
        if t.generatorVersion>=4 then
            return type(p)=='table' and withinBounds(p.x,p.z,p.h,expectedBounds)
        end
        return point(p,lo,hi)
    end
    local validTerrain=t.generatorVersion>=4 and require('src.commute.town_terrain_v3').valid(t.terrain)
        or t.generatorVersion>=2 and t.generatorVersion<4 and require('src.commute.town_terrain_v2').valid(t.terrain)
        or t.generatorVersion<2 and type(t.terrain)=='table' and t.terrain.mode=='inland-town-v1'
    if not integer(t.seed,1,Town.MAX_SEED) or t.size~=512
        or type(t.id)~='string' or #t.id>80 or not t.id:match('^[%w%-]+$')
        or type(t.bounds)~='table' or t.bounds.x0~=expectedBounds.x0 or t.bounds.z0~=expectedBounds.z0
        or t.bounds.x1~=expectedBounds.x1 or t.bounds.z1~=expectedBounds.z1
        or not validTerrain or t.terrain.seed~=t.seed or t.terrain.size~=t.size
        or not array(t.roads,96) or #t.roads<1 or not array(t.placements,64)
        or #t.placements<5 or type(t.destinations)~='table' or type(t.designs)~='table' then return false end
    local designCount=0
    for id,d in pairs(t.designs) do
        designCount=designCount+1
        if designCount>32 or type(id)~='string' or #id>48 or not id:match('^[%w%-]+$')
            or not Sites.validDesign(d) then return false end
    end
    if t.terrain.heights~=nil then
        if not array(t.terrain.heights,4225) or #t.terrain.heights~=4225 then return false end
        for _,h in ipairs(t.terrain.heights) do if not M.finite(h) or h< -2 or h>84 then return false end end
    elseif t.generatorVersion~=0 then return false end
    local ids={}
    for _,p in ipairs(t.placements) do
        if type(p)~='table' or type(p.id)~='string' or #p.id>48 or not p.id:match('^[%w%-]+$')
            or ids[p.id] or not t.designs[p.design] or not point(p.origin,40,472)
            or not M.finite(p.yaw or 0) or math.abs(p.yaw or 0)>math.pi*2 then return false end
        if p.size then
            if type(p.size)~='table' then return false end
            for _,key in ipairs({'width','depth','height'}) do
                if not M.finite(p.size[key]) or p.size[key]<2 or p.size[key]>48 then return false end
            end
        end
        ids[p.id]=true
    end
    local required={'warehouse','brick-walkup','garden','courtyard','corner'}
    if t.generatorVersion>0 then
        for _,id in ipairs({'mechanic','grocery','post-office','police','fire-station','diner','coffee-shop','general-store',
            'residential-1','residential-2','residential-3'}) do required[#required+1]=id end
    end
    for _,id in ipairs(required) do
        if not ids[id] or not townPoint(t.destinations[id],56,458) then return false end
    end
    local destinations=0
    for id,p in pairs(t.destinations) do
        destinations=destinations+1
        if destinations>64 or not ids[id] or not townPoint(p,56,458)
            or type(p.label)~='string' or #p.label>80 then return false end
    end
    local roadIds={}
    for _,r in ipairs(t.roads) do
        local maxRoadPoints=t.generatorVersion>=7 and type(r)=='table' and r.role=='trail' and 128 or 64
        if type(r)~='table' or type(r.id)~='string' or #r.id>64 or roadIds[r.id]
            or (r.interpolation~=nil and r.interpolation~='linear')
            or not M.finite(r.width) or r.width<2 or r.width>12
            or not array(r.points,maxRoadPoints) or #r.points<2 then return false end
        roadIds[r.id]=r
        if t.generatorVersion>=3 then
            local role=r.role
            if (role~='local' and role~='main' and role~='drive' and role~='trail')
                or r.surface~=(role=='trail' and 'dirt' or 'paved') or not integer(r.lanes,1,3)
                or type(r.oneWay)~='boolean' or type(r.turnLane)~='boolean' or type(r.sidewalks)~='boolean'
                or r.oneWay and (role~='local' or r.lanes~=1)
                or r.turnLane and (role~='main' or r.lanes~=3) then return false end
        end
        for _,p in ipairs(r.points) do
            if type(p)~='table' or not M.finite(p[1]) or not M.finite(p[2]) or not M.finite(p[3])
                or p[3]<.3 or p[3]>84
                or t.generatorVersion>=4 and not withinBounds(p[1],p[2],p[3],expectedBounds)
                or t.generatorVersion<4 and (p[1]<56 or p[1]>458 or p[2]<56 or p[2]>458) then return false end
        end
        if r.bridgeEdges then
            if type(r.bridgeEdges)~='table' then return false end
            for k,v in pairs(r.bridgeEdges) do
                if not integer(k,1,#r.points-1) or type(v)~='boolean' then return false end
            end
        end
    end
    if t.generatorVersion>=9 then
        local exit=t.mainlandExit
        local road=type(exit)=='table' and roadIds[exit.roadId]
        local last=road and road.points[#road.points]
        local coordsFinite=type(exit)=='table' and M.finite(exit.x) and M.finite(exit.z) and M.finite(exit.h)
        local atBoundary=coordsFinite and
            (math.abs(exit.x-expectedBounds.x0)<.01 or math.abs(exit.x-expectedBounds.x1)<.01
                or math.abs(exit.z-expectedBounds.z0)<.01 or math.abs(exit.z-expectedBounds.z1)<.01)
        if type(exit)~='table' or exit.city~='Millhaven' or not atBoundary
            or not road or road.role~='main' or road.surface~='paved'
            or not coordsFinite
            or not M.finite(exit.heading) or math.abs(exit.heading)>math.pi*2
            or not last or math.abs(last[1]-exit.x)>.01 or math.abs(last[2]-exit.z)>.01
                or math.abs(last[3]-exit.h)>.01 then return false end
    end
    if t.generatorVersion>=3 then
        local main=type(t.topology)=='table' and t.topology.mainStreet
        if type(main)~='table' or (main.pattern~='strip' and main.pattern~='crossroads')
            or not M.finite(main.x) or not M.finite(main.z)
            or main.x<expectedBounds.x0 or main.x>expectedBounds.x1
            or main.z<expectedBounds.z0 or main.z>expectedBounds.z1
            or not array(main.roadIds,12) or #main.roadIds<2 then return false end
        local listed={}
        for _,id in ipairs(main.roadIds) do
            if listed[id] or not roadIds[id] or roadIds[id].role~='main' then return false end
            listed[id]=true
        end
        for _,p in ipairs(t.placements) do
            local frontage=roadIds[p.frontageRoadId]
            local residential=p.design=='residential' or p.id=='garden' or p.id=='corner'
                or p.id=='brick-walkup' or p.id=='courtyard'
            local district=p.id=='warehouse' and 'industrial' or residential and 'residential' or 'center'
            local country=t.terrain.settings and t.terrain.settings.roads==1
            if p.district~=district or not frontage or frontage.role~=((country or district=='center') and 'main' or 'local') then return false end
        end
        -- Safe recreation clearings are optional when a valid layout has no
        -- terrain corridor that can hold them.
        if not array(t.recreation,12) then return false end
        local seen={}
        for _,site in ipairs(t.recreation) do
            if type(site)~='table' or type(site.id)~='string' or #site.id>48 or seen[site.id]
                or (site.kind~='park' and site.kind~='picnic' and site.kind~='camp')
                or not townPoint(site,56,458) or not M.finite(site.radius) or site.radius<=0 or site.radius>32
                or not M.finite(site.heading) or type(site.label)~='string' or #site.label>80
                or not roadIds[site.trailId] or roadIds[site.trailId].role~='trail' then return false end
            seen[site.id]=true
        end
    end
    return true
end
function Town.fingerprint(t)
    assert(plain(t),'Invalid town fingerprint data')
    local hash=17
    local function add(s)for i=1,#s do hash=(hash*131+s:byte(i))%2147483647 end end
    local function visit(v,root)
        if type(v)=='table' then
            local keys={};for k in pairs(v) do if not (root and k=='id') then keys[#keys+1]=k end end
            table.sort(keys,function(a,b)return tostring(a)<tostring(b) end)
            for _,k in ipairs(keys) do add(tostring(k));visit(v[k]) end
        elseif type(v)=='number' then add(v==0 and '0' or ('%.12g'):format(v)) else add(tostring(v)) end
    end
    visit(t,true);return tostring(math.floor(hash))
end
function Town.legacy()
    return {version=1,generatorVersion=0,id='original-valley-v3',seed=4261,size=512,
        bounds=copy(Default.bounds),terrain={mode='inland-town-v1',seed=4261,size=512},
        roads=copy(Default.roads),destinations=copy(Default.destinations),placements=copy(Sites.defaultPlacements),designs=copy(Sites.designs)}
end
-- Add a roadside station to pre-station towns on a runtime copy. Keep the
-- saved fingerprint and every existing address intact.
local function stationLayout(t,world)
    if t.destinations['gas-station'] then return t end
    local frontage=require('src.commute.town_generator_v2').frontage
    local placed=Sites.create({placements=t.placements,designs=t.designs}).all
    local pads={}
    for _,site in ipairs(placed) do pads[#pads+1]=site.parking end
    for index,road in ipairs(t.roads) do
        if road.role~='drive' and road.role~='trail' and road.id~='east-bank' then
            for edge=1,#road.points-1 do
                local a,b=road.points[edge],road.points[edge+1]
                local length=M.length(b[1]-a[1],b[2]-a[2])
                if length>12 and not (road.bridgeEdges and road.bridgeEdges[edge]) then
                    for _,fraction in ipairs({.5,.25,.75}) do
                        local anchor=frontage.mix(a,b,fraction)
                        for _,side in ipairs({1,-1}) do
                            local nx,nz=(a[2]-b[2])/length*side,(b[1]-a[1])/length*side
                            local pad={x=anchor[1]+nx*12,z=anchor[2]+nz*12,h=anchor[3]}
                            local lot=frontage.placement('gas-station','gas-station',pad,nx,nz,1)
                            local site=Sites.create({placements={lot}}).all[1]
                            if frontage.clear(site,pad,placed,pads,t.roads,world.plan,anchor) then
                                local out=copy(t)
                                out.designs[lot.id]=copy(Sites.designs[lot.id])
                                out.placements[#out.placements+1]=lot
                                out.destinations[lot.id]={x=pad.x,z=pad.z,h=pad.h,label='Gas Station'}
                                local r=out.roads[index]
                                table.insert(r.points,edge+1,anchor)
                                if r.bridgeEdges then
                                    for i=#r.points-1,edge+1,-1 do r.bridgeEdges[i]=r.bridgeEdges[i-1] end
                                    r.bridgeEdges[edge]=false
                                end
                                out.roads[#out.roads+1]={id='station-drive',role='drive',lanes=1,surface='paved',
                                    width=3.5,interpolation='linear',points={anchor,{pad.x,pad.z,pad.h}}}
                                return out
                            end
                        end
                    end
                end
            end
        end
    end
    return t
end
function Town.world(t)
    t=t or Town.legacy();assert(Town.valid(t),'Invalid saved town definition')
    local world=require('src.commute.terrain').new(t.terrain)
    t=stationLayout(t,world)
    local runtimeTown=t
    local sites=Sites.create({placements=runtimeTown.placements,designs=runtimeTown.designs})
    if not runtimeTown.mainlandExit then
        runtimeTown=copy(runtimeTown)
        local planner=require('src.commute.town_generator_v3')
        local exit,reason=planner.attachMainlandExit(runtimeTown,world.plan,sites)
        assert(exit,reason)
    end
    local destinations=copy(runtimeTown.destinations)
    if destinations.mechanic then destinations.mechanic.label=Sites.MECHANIC_NAME end
    if runtimeTown.mainlandExit then
        local exit=runtimeTown.mainlandExit
        destinations.mainland_exit={x=exit.x,z=exit.z,h=exit.h,label=exit.city..' Gate'}
    end
    local roadVersion=require('src.commute.roads').VERSION
    local roads=require('src.commute.roads').new({definitions=runtimeTown.roads,destinations=destinations,
        bounds=runtimeTown.bounds,sites=sites,layoutId=runtimeTown.id,version=roadVersion,recreation=runtimeTown.recreation})
    roads:attach(world);world.townId=runtimeTown.id;world.town=runtimeTown
    world.mainlandExit=runtimeTown.mainlandExit;world.neighboringCity='Millhaven'
    if runtimeTown.generatorVersion>=3 then require('src.commute.infrastructure').ensure(world) end
    return world
end
local function random(seed)
    local state=seed
    return function(lo,hi)
        state=state*16807%2147483647
        local lower,upper=lo or 0,hi or 1
        return lower+(upper-lower)*(state-1)/2147483646
    end
end
local function q(n)return math.floor(n*1000+.5)/1000 end
local function shuffle(items,rng)
    for i=#items,2,-1 do local j=math.floor(rng(0,1)*i)+1;items[i],items[j]=items[j],items[i] end
end
local function lot(id,designId,pad,dx,dz,rng)
    local design=assert(Sites.designs[designId],'Missing town building design '..designId)
    local yaw=math.atan2(dx,-dz)
    local scale=rng and rng(.94,1.08) or 1
    local size={width=design.width*scale,depth=design.depth*scale,height=design.height}
    local c,s=math.cos(yaw),math.sin(yaw)
    local px,pz=design.parking.x*scale,design.parking.z*scale
    return {id=id,design=designId,yaw=yaw,size=size,
        origin={x=pad.x-px*c+pz*s,z=pad.z-px*s-pz*c,h=pad.h}}
end
local function overlap(a,b,margin)
    return a.minX-margin<b.maxX and a.maxX+margin>b.minX and a.minZ-margin<b.maxZ and a.maxZ+margin>b.minZ
end
local function clearLot(site,placed,roads,terrain)
    if site.minX<60 or site.maxX>454 or site.minZ<60 or site.maxZ>454 then return false end
    for _,other in ipairs(placed) do if overlap(site,other,5) then return false end end
    for _,r in ipairs(roads) do for i=1,#r.points-1 do
        local a,b=r.points[i],r.points[i+1]
        local count=math.max(1,math.ceil(M.length(b[1]-a[1],b[2]-a[2])/2))
        for j=0,count do
            local x,z=M.lerp(a[1],b[1],j/count),M.lerp(a[2],b[2],j/count)
            if site:distance(x,z)<r.width*.5+2 then return false end
        end
    end end
    for _,p in ipairs(site.foundation.corners) do
        if terrain:height(p.x,p.z)<.5 then return false end
    end
    return true
end
local function generate(seed)
    local rng=random(seed)
    local terrain=require('src.commute.terrain').new({seed=seed,size=512})
    local result={version=1,generatorVersion=1,seed=seed,size=512,bounds=copy(Default.bounds),
        terrain={mode='inland-town-v1',seed=seed,size=512,heights={}},roads={},destinations={},placements={},designs=copy(Sites.designs)}
    for x=0,64 do for z=0,64 do result.terrain.heights[#result.terrain.heights+1]=terrain.plan.grid[x][z] end end
    local nodes={}
    local function node(id,x,z,h,jitter)
        jitter=jitter or 0
        local p={q(x+rng(-jitter,jitter)),q(z+rng(-jitter,jitter)),h};nodes[id]=p;return p
    end
    node('shop',100,389,4.5,7);node('south',137,358,5,7);node('valley',175,322,5,8)
    node('center',245,292,4.4,7);node('northeast',250,231,6,8)
    node('north',215,181,8,8);node('ridge',143,158,10,8)
    node('west',110,225,11,7);node('southwest',110,290,8,5)
    node('bridgewest',285,270,3.6);node('bridgeentry',302,270,3.6)
    node('bridgeexit',360,270,3.6);node('bridgeeast',385,270,3.6)
    local function road(id,ids,width,bridgeEdges)
        local p={};for _,name in ipairs(ids) do p[#p+1]=nodes[name] end
        local r={id=id,width=width or 5,points=p,bridgeEdges=bridgeEdges or {}}
        result.roads[#result.roads+1]=r;return r
    end
    road('shop-lane',{'shop','south'},5)
    road('main-street',{'south','valley','center'},6.4)
    road('neighborhood-loop',{'center','northeast','north','ridge','west','southwest','south'},5.6)
    road('river-road',{'center','bridgewest','bridgeentry','bridgeexit','bridgeeast'},5,{[3]=true})
    local placed={}
    local function accept(p,pad)
        local site=Sites.create({placements={p}}).all[1]
        result.placements[#result.placements+1]=p;placed[#placed+1]=site
        result.destinations[p.id]={x=pad.x,z=pad.z,h=pad.h,label=names[p.id] or 'Town residences'}
    end
    local function padNode(id,design,nodeId,previous)
        local p,prev=nodes[nodeId],nodes[previous]
        local dx,dz=p[1]-prev[1],p[2]-prev[2];local length=M.length(dx,dz);dx,dz=dx/length,dz/length
        local pad={x=p[1],z=p[2],h=p[3]}
        accept(lot(id,design,pad,dx,dz,rng),pad)
    end
    padNode('warehouse','warehouse','shop','south')
    local homes={'brick-walkup','garden','courtyard','corner'};shuffle(homes,rng)
    local locations={{'east-home',425,205,6,'bridgeeast'},{'south-home',222,348,5,'valley'},
        {'west-home',181,227,9,'west'},{'north-home',111,120,12,'ridge'}}
    for i,where in ipairs(locations) do
        node(where[1],where[2],where[3],where[4],5)
        road(homes[i]..'-lane',{where[5],where[1]},4.2)
        padNode(homes[i],homes[i],where[1],where[5])
    end
    local candidates={}
    for _,r in ipairs(result.roads) do for i=1,#r.points-1 do
        local a,b=r.points[i],r.points[i+1];local length=M.length(b[1]-a[1],b[2]-a[2])
        if length>32 and not r.bridgeEdges[i] and r.id~='river-road' then
            for _,t in ipairs({.28,.52,.76}) do for _,side in ipairs({-1,1}) do
                candidates[#candidates+1]={road=r,edge=i,t=t,side=side,a=a,b=b}
            end end
        end
    end end
    shuffle(candidates,rng)
    local services={'mechanic','grocery','post-office','police','fire-station','diner','coffee-shop','general-store',
        'residential-1','residential-2','residential-3'}
    local spurs={}
    for _,id in ipairs(services) do
        local design=id:match('^residential') and 'residential' or id
        local found=false
        for _,c in ipairs(candidates) do if not c.used then
            local a,b=c.a,c.b;local length=M.length(b[1]-a[1],b[2]-a[2])
            local nx,nz=-(b[2]-a[2])/length*c.side,(b[1]-a[1])/length*c.side
            local anchor={q(M.lerp(a[1],b[1],c.t)),q(M.lerp(a[2],b[2],c.t)),q(M.lerp(a[3],b[3],c.t))}
            local pad={x=q(anchor[1]+nx*16),z=q(anchor[2]+nz*16),h=anchor[3]}
            local p=lot(id,design,pad,nx,nz,rng);local site=Sites.create({placements={p}}).all[1]
            if clearLot(site,placed,result.roads,terrain) then
                accept(p,pad);c.used=true;found=true
                c.road.inserts=c.road.inserts or {};c.road.inserts[c.edge]=c.road.inserts[c.edge] or {}
                table.insert(c.road.inserts[c.edge],{t=c.t,point=anchor})
                spurs[#spurs+1]={id=id..'-drive',width=3.5,points={anchor,{pad.x,pad.z,pad.h}},bridgeEdges={}}
                break
            end
        end end
        assert(found,'Could not fit '..id..' safely into this town')
    end
    for _,r in ipairs(result.roads) do if r.inserts then
        local expanded={}
        for i,p in ipairs(r.points) do
            expanded[#expanded+1]=p
            local inserts=r.inserts[i] or {};table.sort(inserts,function(a,b)return a.t<b.t end)
            for _,v in ipairs(inserts) do
                local last=expanded[#expanded]
                if last[1]~=v.point[1] or last[2]~=v.point[2] then expanded[#expanded+1]=v.point end
            end
        end
        r.points=expanded;r.inserts=nil
    end end
    for _,r in ipairs(spurs) do result.roads[#result.roads+1]=r end
    -- The reliable network/preset codec permits dense arrays, not sparse maps.
    for _,r in ipairs(result.roads) do
        local flags={};for i=1,#r.points-1 do flags[i]=r.bridgeEdges[i]==true end
        r.bridgeEdges=flags
    end
    result.id='town-v1-'..seed..'-'..Town.fingerprint(result)
    assert(Town.valid(result),'Generated town failed its data contract')
    return result
end
function Town.generate(seed,options)
    seed=tonumber(seed)
    if not integer(seed,1,Town.MAX_SEED) then return nil,'Enter a whole-number seed from 1 to 2147483646.' end
    local okay,result=pcall(function()
        local version=options and options.generatorVersion or Town.GENERATOR_VERSION
        if version==0 then return Town.legacy() end
        if version==1 then return generate(seed) end
        assert(version>=2 and version<=Town.GENERATOR_VERSION,'Unknown town generator version')
        local bounds=version>=4 and islandBounds or Default.bounds
        -- V4 and V5 share the island terrain. Only V5 surveys curved streets.
        local settings=version>=6 and Options.copy(options and options.island) or nil
        local plannerVersion=version>=4 and 4 or version
        local result=require('src.commute.town_generator_v'..plannerVersion).generate(seed,
            {bounds=bounds,names=names,generatorVersion=version,settings=settings})
        result.id='town-v'..version..'-'..seed..'-'..Town.fingerprint(result)
        assert(Town.valid(result),'Generated town failed its data contract')
        return result
    end)
    if not okay then return nil,'This seed could not form a safe town: '..tostring(result) end
    return result
end
return Town
