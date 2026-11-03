-- Reserve the town center first. Its connected street frontage is the address
-- for every public service. Neighborhood streets fill out the remaining graph.
local M = require('src.commute.vendor.mathx')
local Sites = require('src.commute.sites')
local Terrain = require('src.commute.town_terrain_v2')
local Frontage = require('src.commute.town_generator_v2').frontage
local Planner = {VERSION=3}

local services = {'fire-station', 'grocery', 'police', 'mechanic', 'general-store', 'post-office', 'diner', 'coffee-shop'}
local sideStreetLots = {'courtyard', 'garden', 'brick-walkup', 'corner', 'warehouse', 'residential-1', 'residential-2', 'residential-3'}
local function gridIndex(row, column) return (row-1)*4+column end

local function createNodes(rng, frame, plan)
    local nodes = {}
    local sx, sz, stagger = rng(81,93), rng(81,93), rng(-8,8)
    for row=1,4 do for column=1,4 do
        local u = (column-2.5)*sx + (row%2)*stagger + rng(-6,6)
        local v = (row-2.5)*sz + rng(-6,6)
        local x, z = frame.x+u*frame.c-v*frame.s, frame.z+u*frame.s+v*frame.c
        assert(plan:height(x,z)>.9,'Street junction touches a waterway')
        nodes[#nodes+1] = {Frontage.round(x), Frontage.round(z), Frontage.round(plan:landHeight(x,z))}
    end end
    return nodes
end

local function graph(rng, pattern)
    local row, column = math.floor(rng(2,4)), math.floor(rng(2,4))
    local horizontal = rng()<.5
    local hub = gridIndex(row,column)
    local candidates, parents = {}, {}
    for i=1,16 do parents[i]=i end
    local function edge(a,b,main)
        -- A crossroads has precisely four street approaches at its center.
        if pattern=='crossroads' and not main and (a==hub or b==hub) then return end
        candidates[#candidates+1] = {a=a,b=b,main=main==true,weight=rng()}
    end
    for r=1,4 do for c=1,4 do
        local i=gridIndex(r,c)
        if c<4 then edge(i,i+1,r==row and (horizontal or pattern=='crossroads')) end
        if r<4 then edge(i,i+4,c==column and (not horizontal or pattern=='crossroads')) end
        if c<4 and r<4 then
            if rng()<.5 then edge(i,i+5) else edge(i+1,i+4) end
        end
    end end
    table.sort(candidates,function(a,b)
        if a.main~=b.main then return a.main end
        return a.weight<b.weight
    end)
    local function root(i) while parents[i]~=i do i=parents[i] end return i end
    local selected, redundant = {}, {}
    for _,e in ipairs(candidates) do
        local a,b=root(e.a),root(e.b)
        if a~=b then
            parents[a]=b
            selected[#selected+1]=e
        else
            redundant[#redundant+1]=e
        end
    end
    Frontage.shuffle(redundant,rng)
    local loops = math.min(#redundant,math.floor(rng(1,8)))
    for i=1,loops do
        local e=redundant[i]
        -- Every lot stays reachable in both directions through the two-way
        -- spanning tree. Only redundant neighborhood links can be one-way.
        if i==1 then
            e.oneWay=true
            if rng()<.5 then e.a,e.b=e.b,e.a end
        end
        selected[#selected+1]=e
    end
    return selected,hub,loops
end

local function planStreets(result, rng, nodes, plan, pattern, yaw)
    local edges, hub, loops = graph(rng,pattern)
    local main = {pattern=pattern,roadIds={},x=nodes[hub][1],z=nodes[hub][2]}
    local bridges=0
    for index,e in ipairs(edges) do
        local points,flags=Frontage.splitWater(nodes[e.a],nodes[e.b],plan)
        for _,flag in ipairs(flags) do if flag then bridges=bridges+1 end end
        local turnLane = e.main and (e.a==hub or e.b==hub)
        local lanes = turnLane and 3 or e.oneWay and 1 or 2
        local road = {id=(e.main and 'main-' or 'street-')..index,
            role=e.main and 'main' or 'local',surface='paved',lanes=lanes,
            oneWay=e.oneWay==true,turnLane=turnLane,sidewalks=e.main or not e.oneWay,
            width=e.main and (turnLane and 9.8 or 7.6) or e.oneWay and 4.2 or 5.8,
            interpolation='linear',points=points,bridgeEdges=flags}
        result.roads[#result.roads+1]=road
        if e.main then main.roadIds[#main.roadIds+1]=road.id end
    end
    result.topology={nodes=#nodes,edges=#edges,cycles=loops,bridges=bridges,
        orientation=Frontage.round(yaw),mainStreet=main}
end

local function frontageCandidates(roads,rng)
    local candidates={main={},localStreet={}}
    for _,road in ipairs(roads) do
        local group = road.role=='main' and candidates.main or candidates.localStreet
        for edge=1,#road.points-1 do
            local a,b=road.points[edge],road.points[edge+1]
            local length=M.length(b[1]-a[1],b[2]-a[2])
            if not road.bridgeEdges[edge] then
                for _,t in ipairs({.18,.30,.42,.54,.66,.78,.88}) do
                    if math.min(t,1-t)*length>12 then
                        for _,side in ipairs({-1,1}) do
                            group[#group+1]={road=road,edge=edge,t=t,side=side,a=a,b=b,length=length}
                        end
                    end
                end
            end
        end
    end
    Frontage.shuffle(candidates.main,rng)
    Frontage.shuffle(candidates.localStreet,rng)
    return candidates
end

local function placeLot(result, id, candidates, rng, plan, placed, pads, names)
    local design=id:match('^residential') and 'residential' or id
    local scale=rng(.94,1.08)
    for _,c in ipairs(candidates) do
        if not c.used then
            local nx=-(c.b[2]-c.a[2])/c.length*c.side
            local nz=(c.b[1]-c.a[1])/c.length*c.side
            local anchor=Frontage.mix(c.a,c.b,c.t)
            local pad={x=Frontage.round(anchor[1]+nx*15),z=Frontage.round(anchor[2]+nz*15),h=anchor[3]}
            local lot=Frontage.placement(id,design,pad,nx,nz,scale)
            local site=Sites.create({placements={lot}}).all[1]
            if Frontage.clear(site,pad,placed,pads,result.roads,plan,anchor) then
                lot.frontageRoadId=c.road.id
                lot.district=c.road.role=='main' and 'center' or id=='warehouse' and 'industrial' or 'residential'
                result.placements[#result.placements+1]=lot
                result.destinations[id]={x=pad.x,z=pad.z,h=pad.h,label=names[id] or ('Town residences '..id:match('%d+$'))}
                c.used=true
                placed[#placed+1],pads[#pads+1]=site,pad
                c.road.inserts=c.road.inserts or {}
                c.road.inserts[c.edge]=c.road.inserts[c.edge] or {}
                table.insert(c.road.inserts[c.edge],{t=c.t,point=anchor})
                result.roads[#result.roads+1]={id=id..'-drive',width=3.5,role='drive',surface='paved',lanes=1,
                    oneWay=false,turnLane=false,sidewalks=false,interpolation='linear',
                    points={anchor,{pad.x,pad.z,pad.h}},bridgeEdges={false}}
                return
            end
        end
    end
    error('No safe '..id..' frontage in its district')
end

local function attempt(seed,options,attemptIndex,pattern)
    local rng=Terrain.random(seed,72+attemptIndex)
    local yaw=math.floor(rng(0,4))*math.pi/2+rng(-.12,.12)
    local frame={x=rng(250,262),z=rng(250,262),c=math.cos(yaw),s=math.sin(yaw)}
    local terrain=Terrain.generate(seed,frame)
    local plan=Terrain.new(terrain,{size=512,center=256,radius=201})
    local result={version=1,generatorVersion=3,seed=seed,size=512,bounds=Frontage.copy(options.bounds),
        terrain=terrain,roads={},placements={},destinations={},designs=Frontage.copy(Sites.designs)}
    local nodes=createNodes(rng,frame,plan)
    planStreets(result,rng,nodes,plan,pattern,yaw)
    local candidates=frontageCandidates(result.roads,rng)
    local placed,pads={},{}
    for _,id in ipairs(services) do placeLot(result,id,candidates.main,rng,plan,placed,pads,options.names) end
    for _,id in ipairs(sideStreetLots) do placeLot(result,id,candidates.localStreet,rng,plan,placed,pads,options.names) end
    Frontage.finishDriveways(result.roads)
    assert(require('src.commute.town_trails').generate(result,plan)>=2,'Two safe off-road shortcuts are required')
    return result
end

function Planner.generate(seed,options)
    local pattern=Terrain.random(seed,71)()<.5 and 'strip' or 'crossroads'
    local reason
    for attemptIndex=0,23 do
        local ok,result=pcall(attempt,seed,options,attemptIndex,pattern)
        if ok then return result end
        reason=result
    end
    error('Town planning exhausted safe street layouts: '..tostring(reason))
end
return Planner
