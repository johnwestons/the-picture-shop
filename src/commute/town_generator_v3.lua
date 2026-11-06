-- Reserve the town center first. Its connected street frontage is the address
-- for every public service. Neighborhood streets fill out the remaining graph.
local M = require('src.commute.vendor.mathx')
local Sites = require('src.commute.sites')
local Terrain = require('src.commute.town_terrain_v2')
local IslandTerrain = require('src.commute.town_terrain_v3')
local Frontage = require('src.commute.town_generator_v2').frontage
local Alignment = require('src.commute.street_alignment')
local Planner = {VERSION=3}

local MAINLAND_CITY='Millhaven'

local function connectorEndpoint(result,desiredAngle,plan,sites)
    local centerX,centerZ=256,256
    local dx,dz=math.cos(desiredAngle),math.sin(desiredAngle)
    local bounds=result.bounds
    local candidates,fallback,seen={},{},{}
    for _,road in ipairs(result.roads or {}) do
        if road.role=='main' or road.role==nil then
            for _,p in ipairs({road.points[1],road.points[#road.points]}) do
                local key=('%0.3f:%0.3f:%0.3f'):format(p[1],p[2],p[3])
                if not seen[key] then
                    seen[key]=true
                    local vx,vz=p[1]-centerX,p[2]-centerZ
                    local radius=math.sqrt(vx*vx+vz*vz)
                    local core=result.topology and result.topology.mainStreet
                    local atCore=core and math.abs(p[1]-core.x)<.01 and math.abs(p[2]-core.z)<.01
                    -- The mainland link belongs on the outer road network;
                    -- attaching it to the core junction adds a third arm to
                    -- the town center and sends through-traffic past every
                    -- service frontage.
                    if radius>80 and not atCore then
                        local ux,uz=vx/radius,vz/radius
                        local score=(ux*dx+uz*dz)*2+radius/1000
                        local blocked=false
                        if sites and sites.all then
                            local length=math.sqrt((bounds.x1-bounds.x0)^2+(bounds.z1-bounds.z0)^2)
                            local tx,tz=ux,uz
                            local edge=math.huge
                            if tx>1e-6 then edge=math.min(edge,(bounds.x1-p[1])/tx)
                            elseif tx< -1e-6 then edge=math.min(edge,(bounds.x0-p[1])/tx) end
                            if tz>1e-6 then edge=math.min(edge,(bounds.z1-p[2])/tz)
                            elseif tz< -1e-6 then edge=math.min(edge,(bounds.z0-p[2])/tz) end
                            edge=math.min(edge,length)
                            for distance=0,edge,8 do
                                local x,z=p[1]+tx*distance,p[2]+tz*distance
                                for _,site in ipairs(sites.all) do
                                    if site:distance(x,z)<5.5 then blocked=true;break end
                                end
                                if blocked then break end
                            end
                        end
                        local candidate={point=p,score=score,ux=ux,uz=uz}
                        fallback[#fallback+1]=candidate
                        if not blocked then candidates[#candidates+1]=candidate end
                    end
                end
            end
        end
    end
    table.sort(candidates,function(a,b)return a.score>b.score end)
    table.sort(fallback,function(a,b)return a.score>b.score end)
    local selected=candidates[1] or fallback[1]
    if not selected then return nil end
    local p=selected.point
    local distance=math.huge
    if selected.ux>1e-6 then distance=math.min(distance,(bounds.x1-p[1])/selected.ux)
    elseif selected.ux< -1e-6 then distance=math.min(distance,(bounds.x0-p[1])/selected.ux) end
    if selected.uz>1e-6 then distance=math.min(distance,(bounds.z1-p[2])/selected.uz)
    elseif selected.uz< -1e-6 then distance=math.min(distance,(bounds.z0-p[2])/selected.uz) end
    if not (distance>1 and distance<math.huge) then return nil end
    local x,z=p[1]+selected.ux*distance,p[2]+selected.uz*distance
    return {start=p,x=x,z=z,dx=selected.ux,dz=selected.uz,distance=distance}
end

-- A gate terminates on the playable boundary. Vehicles use it as a virtual
-- portal; the player remains blocked by Roads:blocked at the same boundary.
function Planner.attachMainlandExit(result,plan,sites)
    if result.mainlandExit then return result.mainlandExit end
    local rng=Terrain.random(result.seed,97)
    local desiredAngle=rng(0,math.pi*2)
    local endpoint=connectorEndpoint(result,desiredAngle,plan,sites)
    if not endpoint then return nil,'No safe mainland road connector could be placed.' end
    local points,wet={},{}
    local steps=math.max(2,math.ceil(endpoint.distance/8))
    local deck=1.35
    for i=0,steps do
        local t=i/steps
        local x=endpoint.start[1]+endpoint.dx*endpoint.distance*t
        local z=endpoint.start[2]+endpoint.dz*endpoint.distance*t
        local ground=plan and plan.height and plan:height(x,z) or endpoint.start[3]
        local h=ground>.9 and plan and plan.landHeight and plan:landHeight(x,z) or deck
        if i==0 then
            -- Keep the connector's junction identical to the authored road
            -- endpoint in x, z and elevation so the route graph joins exactly.
            points[#points+1]={endpoint.start[1],endpoint.start[2],endpoint.start[3]}
        else
            points[#points+1]={Frontage.round(x),Frontage.round(z),Frontage.round(math.max(.35,h))}
        end
        wet[i+1]=ground<=.9
    end
    -- The island surface can fall sharply near the shoreline. Blend the
    -- connector into a safe road profile instead of reproducing that terrain
    -- cliff in the driving lane. A small embankment is preferable to a short,
    -- unexpectedly steep grade.
    local maxRoadGrade=.055
    for i=2,#points do
        local previous,current=points[i-1],points[i]
        local length=M.length(current[1]-previous[1],current[2]-previous[2])
        local maxRise=length*maxRoadGrade
        current[3]=Frontage.round(M.clamp(current[3],previous[3]-maxRise,previous[3]+maxRise))
    end
    local bridgeEdges={}
    for i=1,#points-1 do bridgeEdges[i]=wet[i] or wet[i+1] end
    local roadId='mainland-connector'
    local road={id=roadId,width=7.6,role='main',surface='paved',lanes=2,
        oneWay=false,turnLane=false,sidewalks=false,interpolation='linear',
        points=points,bridgeEdges=bridgeEdges}
    result.roads[#result.roads+1]=road
    local gate={city=MAINLAND_CITY,roadId=roadId,x=points[#points][1],z=points[#points][2],
        h=points[#points][3],heading=math.atan2(endpoint.dz,endpoint.dx)}
    result.mainlandExit=gate
    if result.topology then result.topology.mainlandExit={roadId=roadId,city=MAINLAND_CITY} end
    return gate
end

local services = {'fire-station', 'grocery', 'police', 'mechanic', 'general-store', 'post-office', 'diner', 'coffee-shop', 'gas-station'}
local sideStreetLots = {'courtyard', 'garden', 'brick-walkup', 'corner', 'warehouse', 'residential-1', 'residential-2', 'residential-3'}
local function gridIndex(row, column) return (row-1)*4+column end

local function createNodes(rng, frame, plan, generatorVersion, settings, countryBypass)
    local nodes = {}
    local roads=settings and settings.roads or 2
    if generatorVersion>=8 and roads==1 then
        -- Survey the coast in ten directions instead of fitting a rectangular
        -- road to it. Each direction may reach a different inland setback.
        local start=rng(0,math.pi*2)
        for i=1,10 do
            local angle=start+(i-1)*math.pi/5+rng(-.12,.12)
            local dx,dz=math.cos(angle),math.sin(angle)
            local reach=155
            for radius=160,215,5 do
                if plan:shoreDistance(256+dx*radius,256+dz*radius)>44 then reach=radius else break end
            end
            local radius=reach-rng(0,38)
            local x,z=256+dx*radius,256+dz*radius
            assert(plan:height(x,z)>.9,'Country road junction touches a waterway')
            nodes[i]={Frontage.round(x),Frontage.round(z),Frontage.round(plan:landHeight(x,z))}
        end
        -- Short inward roads use the middle of the island as well as its rim.
        local first=math.floor(rng(2,5))
        local second=math.floor(rng(7,10))
        local branchCount=countryBypass and 2 or math.floor(rng(1,3))
        local branches={first}
        if branchCount==2 then branches[2]=second end
        for i=1,branchCount do
            local index=branches[i]
            local outer=nodes[index]
            local radius=rng(.43,.59)
            local x,z=256+(outer[1]-256)*radius,256+(outer[2]-256)*radius
            assert(plan:height(x,z)>.9,'Country road branch touches a waterway')
            nodes[#nodes+1]={Frontage.round(x),Frontage.round(z),Frontage.round(plan:landHeight(x,z))}
        end
        return nodes,branches
    end
    local sx,sz,stagger
    if generatorVersion>=7 then
        local low,high=98,108
        if roads==1 then low,high=108,118 elseif roads==3 then low,high=91,101 end
        if generatorVersion>=8 then
            low,high=110,126
            if roads==3 then low,high=101,116 end
        end
        sx,sz,stagger=rng(low,high),rng(low,high),rng(-10,10)
    else
        sx,sz,stagger=rng(81,93),rng(81,93),rng(-8,8)
    end
    local shearX,shearZ,foldX,foldZ=0,0,0,0
    if generatorVersion>=8 then
        shearX,shearZ=rng(-19,19),rng(-19,19)
        foldX,foldZ=rng(-27,27),rng(-27,27)
    end
    for row=1,4 do for column=1,4 do
        local u = (column-2.5)*sx + (row%2)*stagger + rng(-6,6)
            +(row-2.5)*shearX+math.sin((row-1)*math.pi/3)*foldX
        local v = (row-2.5)*sz + rng(-6,6)
            +(column-2.5)*shearZ+math.sin((column-1)*math.pi/3)*foldZ
        local x, z = frame.x+u*frame.c-v*frame.s, frame.z+u*frame.s+v*frame.c
        if generatorVersion>=7 and plan.island and plan.shoreDistance then
            -- Spread the outer streets across more of the island while keeping
            -- every junction safely inland, even along a narrow shore segment.
            local attempts=0
            while plan:shoreDistance(x,z)<26 and attempts<32 do
                x=M.lerp(x,frame.x,.08);z=M.lerp(z,frame.z,.08);attempts=attempts+1
            end
        end
        assert(plan:height(x,z)>.9,'Street junction touches a waterway')
        nodes[#nodes+1] = {Frontage.round(x), Frontage.round(z), Frontage.round(plan:landHeight(x,z))}
    end end
    return nodes
end

local function graph(rng, pattern, density, generatorVersion, branches, countryBypass)
    if density==1 then
        if generatorVersion>=8 then
            local edges={}
            local gap=countryBypass and math.floor(rng(2,10)) or 0
            for i=1,10 do
                if i~=gap then edges[#edges+1]={a=i,b=i%10+1,main=true} end
            end
            for i,index in ipairs(branches) do edges[#edges+1]={a=index,b=10+i,main=true} end
            if countryBypass then edges[#edges+1]={a=11,b=12,main=true} end
            return edges,1,1
        end
        local order=generatorVersion>=7
            and {1,2,3,4,8,12,16,15,14,13,9,5}
            or {1,2,3,4,8,7,6,5,9,10,11,12}
        local edges={}
        for i=2,#order do edges[#edges+1]={a=order[i-1],b=order[i],main=true} end
        if generatorVersion>=7 then edges[#edges+1]={a=order[#order],b=order[1],main=true} end
        return edges,generatorVersion>=7 and 4 or 7,generatorVersion>=7 and 1 or 0
    end
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
    local loops = math.min(#redundant,density==3 and 10 or math.floor(rng(1,8)))
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

local function planStreets(result, rng, nodes, plan, pattern, yaw, branches, countryBypass)
    local settings=result.terrain.settings
    local edges, hub, loops = graph(rng,pattern,settings and settings.roads,result.generatorVersion,branches,countryBypass)
    local scenic=result.generatorVersion>=5
    local curveRandom=Terrain.random(result.seed,91)
    if scenic then Alignment.prepare(nodes,edges,plan,hub) end
    local main = {pattern=pattern,roadIds={},x=nodes[hub][1],z=nodes[hub][2]}
    local bridges=0
    for index,e in ipairs(edges) do
        local points,flags
        if scenic then points,flags=Alignment.street(e,nodes,plan,curveRandom)
        else points,flags=Frontage.splitWater(nodes[e.a],nodes[e.b],plan) end
        for i,flag in ipairs(flags) do if flag and not flags[i-1] then bridges=bridges+1 end end
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
    if scenic then assert(Alignment.connectedOnlyAtNodes(result.roads),'Street curves cross outside a junction') end
    result.topology={nodes=#nodes,edges=#edges,cycles=loops,bridges=bridges,
        orientation=Frontage.round(yaw),mainStreet=main}
end

local function frontageCandidates(roads,rng,scenic,rural)
    local candidates={main={},localStreet={}}
    for _,road in ipairs(roads) do
        local group = road.role=='main' and candidates.main or candidates.localStreet
        local chain={0}
        for i=1,#road.points-1 do
            local a,b=road.points[i],road.points[i+1]
            chain[i+1]=chain[i]+M.length(b[1]-a[1],b[2]-a[2])
        end
        local dryStart,dryEnd=0,0
        for edge=1,#road.points-1 do
            local a,b=road.points[edge],road.points[edge+1]
            local length=M.length(b[1]-a[1],b[2]-a[2])
            if road.bridgeEdges[edge] then
                dryStart=chain[edge+1]
            else
                if edge>=dryEnd then
                    dryEnd=edge
                    while dryEnd<#road.points and not road.bridgeEdges[dryEnd] do dryEnd=dryEnd+1 end
                end
                for _,t in ipairs(rural and {.28,.5,.72} or scenic and {.5} or {.18,.30,.42,.54,.66,.78,.88}) do
                    local station=chain[edge]+t*length
                    local clearance=scenic and math.min(station-dryStart,chain[dryEnd]-station) or math.min(t,1-t)*length
                    if clearance>12 then
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
                local side=id=='warehouse' or design=='residential' or id=='courtyard' or id=='garden' or id=='brick-walkup' or id=='corner'
                lot.district=id=='warehouse' and 'industrial' or side and 'residential' or 'center'
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
    local yaw=(options.generatorVersion or 3)>=8 and rng(0,math.pi*2)
        or math.floor(rng(0,4))*math.pi/2+rng(-.12,.12)
    local frame={x=rng(250,262),z=rng(250,262),c=math.cos(yaw),s=math.sin(yaw)}
    local terrainModel=(options.generatorVersion or 3)>=4 and IslandTerrain or Terrain
    local terrain=terrainModel.generate(seed,frame,options.shoreline,options.settings,options.generatorVersion)
    local plan=terrainModel.new(terrain,{size=512,center=256,radius=terrainModel.ISLAND_RADIUS or 201})
    local result={version=1,generatorVersion=options.generatorVersion or 3,seed=seed,size=512,bounds=Frontage.copy(options.bounds),
        terrain=terrain,roads={},placements={},destinations={},designs=Frontage.copy(Sites.designs)}
    local countryBypass=result.generatorVersion>=8 and options.settings and options.settings.roads==1
        and Terrain.random(seed,70)()<.5
    local nodes,branches=createNodes(rng,frame,plan,result.generatorVersion,options.settings,countryBypass)
    planStreets(result,rng,nodes,plan,pattern,yaw,branches,countryBypass)
    if result.generatorVersion>=9 then
        local exit,reason=Planner.attachMainlandExit(result,plan)
        assert(exit,reason)
    end
    local candidates=frontageCandidates(result.roads,rng,result.generatorVersion>=5,
        result.generatorVersion>=8 and options.settings and options.settings.roads==1)
    if options.settings and options.settings.roads==1 then candidates.localStreet=candidates.main end
    local placed,pads={},{}
    for _,id in ipairs(services) do placeLot(result,id,candidates.main,rng,plan,placed,pads,options.names) end
    for _,id in ipairs(sideStreetLots) do placeLot(result,id,candidates.localStreet,rng,plan,placed,pads,options.names) end
    Frontage.finishDriveways(result.roads)
    -- Trails and recreation are optional town dressing. Keep every route that
    -- passes the safety checks, but don't reject an otherwise valid town when
    -- this terrain and street layout cannot fit two safe shortcuts.
    require('src.commute.town_trails').generate(result,plan)
    return result
end

function Planner.generate(seed,options)
    local pattern=Terrain.random(seed,71)()<.5 and 'strip' or 'crossroads'
    if options.settings and options.settings.roads==1 then pattern='strip' end
    local reason
    for attemptIndex=0,23 do
        local ok,result=pcall(attempt,seed,options,attemptIndex,pattern)
        if ok then return result end
        reason=result
    end
    error('Town planning exhausted safe street layouts: '..tostring(reason))
end

Planner.MAINLAND_CITY=MAINLAND_CITY
return Planner
