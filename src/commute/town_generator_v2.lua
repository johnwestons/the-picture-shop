-- Bounded deterministic street topology and frontage planner. No renderer work.
local M=require('src.commute.vendor.mathx')
local Sites=require('src.commute.sites')
local Terrain=require('src.commute.town_terrain_v2')
local G={VERSION=2}
local function q(n)return math.floor(n*1000+.5)/1000 end
local function copy(v)if type(v)~='table'then return v end;local r={};for k,x in pairs(v)do r[k]=copy(x)end;return r end
local function shuffle(a,rng)for i=#a,2,-1 do local j=math.floor(rng(0,i))+1;a[i],a[j]=a[j],a[i]end end
local function mix(a,b,t)return {q(M.lerp(a[1],b[1],t)),q(M.lerp(a[2],b[2],t)),q(M.lerp(a[3],b[3],t))}end
local function overlap(a,b,gap)
    return a.minX-gap<b.maxX and a.maxX+gap>b.minX and a.minZ-gap<b.maxZ and a.maxZ+gap>b.minZ
end
local function placement(id,design,pad,nx,nz,scale)
    local d=Sites.designs[design];local yaw=math.atan2(nx,-nz);local c,s=math.cos(yaw),math.sin(yaw)
    local px,pz=d.parking.x*scale,d.parking.z*scale
    return {id=id,design=design,yaw=yaw,size={width=d.width*scale,depth=d.depth*scale,height=d.height},
        origin={x=pad.x-px*c+pz*s,z=pad.z-px*s-pz*c,h=pad.h}}
end
local function dry(plan,x,z,h)
    local height=plan:height(x,z)
    return height>.7 and math.abs(plan:landHeight(x,z)-h)<4.5
end
local function clear(site,pad,placed,pads,roads,plan,anchor)
    if site.minX<63 or site.maxX>451 or site.minZ<63 or site.maxZ>451 then return false end
    for _,other in ipairs(placed)do if overlap(site,other,5)then return false end end
    for _,other in ipairs(pads)do if M.length(other.x-pad.x,other.z-pad.z)<19 then return false end end
    for _,p in ipairs(site.foundation.corners)do if not dry(plan,p.x,p.z,pad.h)then return false end end
    for i=0,7 do local angle=i*math.pi/4;if not dry(plan,pad.x+math.cos(angle)*5,pad.z+math.sin(angle)*5,pad.h)then return false end end
    for _,r in ipairs(roads)do for edge=1,#r.points-1 do
        local a,b=r.points[edge],r.points[edge+1];local n=math.max(1,math.ceil(M.length(b[1]-a[1],b[2]-a[2])/2))
        for i=0,n do if site:distance(M.lerp(a[1],b[1],i/n),M.lerp(a[2],b[2],i/n))<r.width*.5+2.5 then return false end end
    end end
    for i=0,10 do
        local x,z=M.lerp(anchor[1],pad.x,i/10),M.lerp(anchor[2],pad.z,i/10)
        if not dry(plan,x,z,pad.h)then return false end
        for _,other in ipairs(placed)do if other:distance(x,z)<3.2 then return false end end
    end
    return true
end
local function splitWater(a,b,plan)
    local length=M.length(b[1]-a[1],b[2]-a[2]);local samples=math.ceil(length/2)
    local spans,start={},nil
    for i=0,samples do
        local t=i/samples;local wet=plan:height(M.lerp(a[1],b[1],t),M.lerp(a[2],b[2],t))<.8
        if wet and not start then start=t end
        if start and (not wet or i==samples)then
            spans[#spans+1]={math.max(10/length,start-8/length),math.min(1-10/length,t+8/length)};start=nil
        end
    end
    local merged={}
    for _,span in ipairs(spans)do
        local last=merged[#merged]
        if last and span[1]<=last[2]+.03 then last[2]=span[2]else merged[#merged+1]=span end
    end
    local points,bridges={a},{}
    for _,span in ipairs(merged)do
        points[#points+1]=mix(a,b,span[1]);bridges[#points-1]=false
        points[#points+1]=mix(a,b,span[2]);bridges[#points-1]=true
    end
    points[#points+1]=b;bridges[#points-1]=false
    return points,bridges
end
local function finishDriveways(roads)
    for _,r in ipairs(roads)do if r.inserts then
        local points,flags={},{}
        for i,p in ipairs(r.points)do
            points[#points+1]=p
            local inserts=r.inserts[i]or {};table.sort(inserts,function(a,b)return a.t<b.t end)
            for _,v in ipairs(inserts)do
                local last=points[#points]
                if last[1]~=v.point[1]or last[2]~=v.point[2]then
                    flags[#points]=r.bridgeEdges[i]==true;points[#points+1]=v.point
                end
            end
            if i<#r.points then flags[#points]=r.bridgeEdges[i]==true end
        end
        r.points,r.bridgeEdges,r.inserts=points,flags,nil
    end end
end

-- The next planner reuses the same registration, water crossings and lot
-- clearance rules while making different choices about street topology.
G.frontage={round=q,copy=copy,shuffle=shuffle,mix=mix,placement=placement,
    clear=clear,splitWater=splitWater,finishDriveways=finishDriveways}

local function attempt(seed,options,attemptIndex)
    local rng=Terrain.random(seed,21+attemptIndex)
    local yaw=math.floor(rng(0,4))*math.pi/2+rng(-.12,.12)
    local frame={x=rng(250,262),z=rng(250,262),c=math.cos(yaw),s=math.sin(yaw)}
    local terrain=Terrain.generate(seed,frame)
    local plan=Terrain.new(terrain,{size=512,center=256,radius=201})
    local result={version=1,generatorVersion=2,seed=seed,size=512,bounds=copy(options.bounds),
        terrain=terrain,roads={},placements={},destinations={},designs=copy(Sites.designs)}
    -- This generator predates the roadside station. Runtime placement adds
    -- that design on a copy so original V2 seed fingerprints stay stable.
    result.designs['gas-station']=nil
    local sx,sz=rng(81,93),rng(81,93);local stagger=rng(-8,8)
    local nodes={}
    for row=1,4 do for column=1,4 do
        local x,z=(column-2.5)*sx+(row%2)*stagger+rng(-6,6),(row-2.5)*sz+rng(-6,6)
        x,z=frame.x+x*frame.c-z*frame.s,frame.z+x*frame.s+z*frame.c
        assert(plan:height(x,z)>.9,'Street junction touches a waterway')
        nodes[#nodes+1]={q(x),q(z),q(plan:landHeight(x,z))}
    end end
    local edges={}
    local function edge(a,b)edges[#edges+1]={a=a,b=b,weight=rng(0,1)}end
    for row=1,4 do for col=1,4 do
        local index=(row-1)*4+col
        if col<4 then edge(index,index+1)end
        if row<4 then edge(index,index+4)end
        if row<4 and col<4 then
            if rng()<.5 then edge(index,index+5)else edge(index+1,index+4)end
        end
    end end
    -- Randomized Kruskal yields branching neighborhoods; independently selected
    -- extra edges make different loop counts and diagonals, not one jittered map.
    table.sort(edges,function(a,b)return a.weight<b.weight end)
    local parents={};for i=1,16 do parents[i]=i end
    local function root(i)while parents[i]~=i do i=parents[i]end;return i end
    local selected,unused={},{}
    for _,e in ipairs(edges)do
        local a,b=root(e.a),root(e.b)
        if a~=b then parents[a]=b;selected[#selected+1]=e else unused[#unused+1]=e end
    end
    local extra=math.floor(rng(0,8));shuffle(unused,rng)
    for i=1,extra do selected[#selected+1]=unused[i]end
    local bridges=0
    for i,e in ipairs(selected)do
        local points,flags=splitWater(nodes[e.a],nodes[e.b],plan)
        for _,flag in ipairs(flags)do if flag then bridges=bridges+1 end end
        result.roads[#result.roads+1]={id='street-'..i,width=6,interpolation='linear',points=points,bridgeEdges=flags}
    end
    result.topology={nodes=16,edges=#selected,cycles=extra,bridges=bridges,orientation=q(yaw),
        pattern=extra<2 and 'branching' or extra<5 and 'mixed-neighborhoods' or 'connected-loops'}
    local candidates={}
    for _,r in ipairs(result.roads)do for i=1,#r.points-1 do
        local a,b=r.points[i],r.points[i+1];local length=M.length(b[1]-a[1],b[2]-a[2])
        if not r.bridgeEdges[i] and length>24 then
            for _,t in ipairs({.22,.42,.62,.82})do for _,side in ipairs({-1,1})do
                if t*length>12 and (1-t)*length>12 then candidates[#candidates+1]={road=r,edge=i,t=t,side=side,a=a,b=b}end
            end end
        end
    end end
    shuffle(candidates,rng)
    local ids={'courtyard','fire-station','garden','grocery','police','corner','mechanic','brick-walkup',
        'residential-1','residential-2','residential-3','general-store','diner','post-office','warehouse','coffee-shop'}
    local placed,pads,spurs={},{},{}
    for _,id in ipairs(ids)do
        local design=id:match('^residential') and 'residential' or id;local found=false
        for _,c in ipairs(candidates)do if not c.used then
            local a,b=c.a,c.b;local length=M.length(b[1]-a[1],b[2]-a[2])
            local nx,nz=-(b[2]-a[2])/length*c.side,(b[1]-a[1])/length*c.side
            local anchor=mix(a,b,c.t);local offset=15
            local pad={x=q(anchor[1]+nx*offset),z=q(anchor[2]+nz*offset),h=anchor[3]}
            local p=placement(id,design,pad,nx,nz,rng(.94,1.08));local site=Sites.create({placements={p}}).all[1]
            if clear(site,pad,placed,pads,result.roads,plan,anchor)then
                found=true;c.used=true;placed[#placed+1]=site;pads[#pads+1]=pad;result.placements[#result.placements+1]=p
                result.destinations[id]={x=pad.x,z=pad.z,h=pad.h,label=options.names[id] or 'Town residences'}
                c.road.inserts=c.road.inserts or {};c.road.inserts[c.edge]=c.road.inserts[c.edge] or {}
                table.insert(c.road.inserts[c.edge],{t=c.t,point=anchor})
                local spur={id=id..'-drive',width=3.5,interpolation='linear',points={anchor,{pad.x,pad.z,pad.h}},bridgeEdges={false}}
                spurs[#spurs+1]=spur;result.roads[#result.roads+1]=spur
                break
            end
        end end
        assert(found,'No safe frontage for '..id)
    end
    finishDriveways(result.roads)
    return result
end
function G.generate(seed,options)
    local failures={}
    for index=0,7 do
        local okay,result=pcall(attempt,seed,options,index)
        if okay then return result end
        failures[#failures+1]=tostring(result)
    end
    error('Town planning exhausted its bounded safe attempts: '..table.concat(failures,'; '))
end
return G
