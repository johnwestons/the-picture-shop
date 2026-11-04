-- Plan dry, public shortcuts between actual street junctions. Store the chosen
-- centerlines and clearings in the town so loading never reruns this search.
local M=require('src.commute.vendor.mathx')
local Sites=require('src.commute.sites')
local Terrain=require('src.commute.town_terrain_v2')
local Trails={WIDTH=2.8}
local function q(v)return math.floor(v*1000+.5)/1000 end
local function distance(a,b)return M.length(a[1]-b[1],a[2]-b[2]) end
local function roadDistance(edge,x,z)
    local t=M.clamp(((x-edge.a[1])*edge.dx+(z-edge.a[2])*edge.dz)/edge.length2,0,1)
    return (x-edge.a[1]-edge.dx*t)^2+(z-edge.a[2]-edge.dz*t)^2
end
local function edge(a,b,width)
    local dx,dz=b[1]-a[1],b[2]-a[2]
    return {a=a,b=b,dx=dx,dz=dz,length2=dx*dx+dz*dz,width=width}
end
local function buildNetwork(town)
    local nodes,byKey,edges,anchors={},{},{},{}
    local function node(point)
        local key=table.concat(point,'/')
        if not byKey[key] then
            local n={p=point,index=#nodes+1,neighbors={}}
            nodes[#nodes+1]=n;byKey[key]=n
        end
        return byKey[key]
    end
    local function link(a,b)
        local length=distance(a.p,b.p)
        a.neighbors[b.index]=length;b.neighbors[a.index]=length
    end
    for _,road in ipairs(town.roads) do
        local sinceAnchor=0
        for i=1,#road.points-1 do
            local a,b=road.points[i],road.points[i+1]
            local start,finish=node(a),node(b)
            edges[#edges+1]=edge(a,b,road.width)
            if road.role~='drive' and not road.id:match('%-drive$') and not (road.bridgeEdges and road.bridgeEdges[i]) then
                -- Short control edges describe the curve, not extra trailheads.
                -- Keep enough separated entrances without scoring every pair of
                -- five-metre samples against the entire street graph.
                if i==1 or town.generatorVersion<5 then start.anchor=true end
                sinceAnchor=sinceAnchor+distance(a,b)
                if i==#road.points-1 or sinceAnchor>=23 or town.generatorVersion<5 then
                    finish.anchor=true
                    sinceAnchor=0
                end
                -- A trail may meet a street between its existing intersections.
                if distance(a,b)>30 then
                    local p={q((a[1]+b[1])/2),q((a[2]+b[2])/2),q((a[3]+b[3])/2)}
                    local mid=node(p)
                    mid.anchor=true;mid.insert={road=road,index=i}
                    link(start,mid);link(mid,finish)
                else link(start,finish) end
            else link(start,finish) end
        end
    end
    for _,n in ipairs(nodes) do if n.anchor then anchors[#anchors+1]=n end end
    return nodes,edges,anchors
end
local function pavedDistances(nodes,source)
    -- This graph contains authored junctions, not the dense render samples.
    local queue,dist,queued={source},{[source]=0},{[source]=true}
    local head=1
    while head<=#queue do
        local i=queue[head];head=head+1;queued[i]=nil
        for j,length in pairs(nodes[i].neighbors) do
            local via=dist[i]+length
            if not dist[j] or via<dist[j]-.001 then
                dist[j]=via
                if not queued[j] then queue[#queue+1]=j;queued[j]=true end
            end
        end
    end
    return dist
end
local function clearLot(ctx,x,z,radius)
    local b=ctx.town.bounds
    if x<b.x0+radius or x>b.x1-radius or z<b.z0+radius or z>b.z1-radius then return false end
    for _,s in ipairs(ctx.sites) do
        if x>s.minX-radius and x<s.maxX+radius and z>s.minZ-radius and z<s.maxZ+radius
            and s:distance(x,z,true)<radius then return false end
    end
    for _,p in ipairs(ctx.pads) do if (p.x-x)^2+(p.z-z)^2<(radius+8)^2 then return false end end
    for _,area in ipairs(ctx.town.recreation) do
        if (area.x-x)^2+(area.z-z)^2<(radius+area.radius+1)^2 then return false end
    end
    return true
end
local function clearEdges(ctx,x,z,radius)
    for _,j in ipairs(ctx.junctions) do
        if (x-j.x)^2+(z-j.z)^2<(j.outerRadius+radius)^2 then return false end
    end
    for _,e in ipairs(ctx.edges) do
        if roadDistance(e,x,z)<(radius+e.width*.5)^2 then return false end
    end
    return true
end
local function pairsByUsefulness(ctx,nodes,anchors)
    local pairs={}
    local center=ctx.plan.config.center or ctx.town.size*.5
    for i,a in ipairs(anchors) do
        local detours=pavedDistances(nodes,a.index)
        for j=i+1,#anchors do
            local b=anchors[j]
            local direct=distance(a.p,b.p)
            local detour=detours[b.index]
            local settings=ctx.town.terrain.settings
            local leisure=settings and settings.length==3
            if direct>25 and direct<246 and detour and (leisure or detour>direct*1.25 and detour-direct>10) then
                local x,z=(a.p[1]+b.p[1])*.5,(a.p[2]+b.p[2])*.5
                local canopy=ctx.plan:habitat(x,z)
                local score=math.min(detour/direct,3)*20+canopy*30+direct*.12+ctx.random(0,8)
                if ctx.plan.island then
                    local ar=M.length(a.p[1]-center,a.p[2]-center)
                    local br=M.length(b.p[1]-center,b.p[2]-center)
                    local aa=math.atan2(a.p[2]-center,a.p[1]-center)
                    local ba=math.atan2(b.p[2]-center,b.p[1]-center)
                    local angle=math.abs(aa-ba)%(math.pi*2)
                    angle=math.min(angle,math.pi*2-angle)
                    score=score+math.min(ar,br)*.10+angle*12
                end
                -- Favor longer connections for leisure rides.
                if settings then score=score+(settings.length-2)*direct*2 end
                pairs[#pairs+1]={a=a,b=b,direct=direct,detour=detour,score=score,order=#pairs+1}
            end
        end
    end
    table.sort(pairs,function(a,b)return a.score>b.score or a.score==b.score and a.order<b.order end)
    return pairs
end
local function path(ctx,pair,bend)
    local a,b=pair.a.p,pair.b.p
    local dx,dz=b[1]-a[1],b[2]-a[2]
    local nx,nz=-dz/pair.direct,dx/pair.direct
    local steps=math.ceil(pair.direct/4.2)
    local points={a}
    local length=0
    for i=1,steps do
        local t=i/steps
        local side=bend*math.sin(t*math.pi)+bend*.18*math.sin(t*math.pi*2)
        local x,z=q(a[1]+dx*t+nx*side),q(a[2]+dz*t+nz*side)
        if not clearLot(ctx,x,z,Trails.WIDTH*.5+1.2) then return end
        -- Keep away from other pavement except inside the two trail mouths.
        if t*pair.direct>8 and (1-t)*pair.direct>8 and not clearEdges(ctx,x,z,Trails.WIDTH*.5+.8) then return end
        local h=ctx.plan:height(x,z)
        local half=Trails.WIDTH*.5+1
        if h<.85 or ctx.plan:height(x+nx*half,z+nz*half)<.8
            or ctx.plan:height(x-nx*half,z-nz*half)<.8 then return end
        if t*pair.direct<10 then h=M.lerp(a[3],h,t*pair.direct/10) end
        if (1-t)*pair.direct<10 then h=M.lerp(b[3],h,(1-t)*pair.direct/10) end
        local p=i==steps and b or {x,z,q(h)}
        local previous=points[#points];local d=distance(previous,p)
        if math.abs(previous[3]-p[3])>d*.28 then return end
        points[#points+1]=p;length=length+d
    end
    local settings=ctx.town.terrain.settings
    if length>pair.detour*(settings and settings.length==3 and 1.6 or .88) then return end
    return points
end
local function bendValues(ctx,pair)
    if not ctx.plan.island then return {8,-8,18,-18,0,32,-32} end
    local a,b=pair.a.p,pair.b.p
    local nx,nz=-(b[2]-a[2])/pair.direct,(b[1]-a[1])/pair.direct
    local center=ctx.plan.config.center or ctx.town.size*.5
    local mx,mz=(a[1]+b[1])*.5-center,(a[2]+b[2])*.5-center
    local facing=nx*mx+nz*mz
    local outward=facing<0 and -1 or 1
    if math.abs(facing)<1e-5 then outward=(pair.a.index+pair.b.index)%2==0 and 1 or -1 end
    local values={}
    local settings=ctx.town.terrain.settings
    local bends=settings and settings.length==1 and {8,16,24} or {72,44,20}
    for _,magnitude in ipairs(bends) do
        values[#values+1]=outward*magnitude
        values[#values+1]=-outward*magnitude
    end
    values[#values+1]=0
    return values
end
local kinds={'picnic','camp','park'}
local labels={picnic='Shaded Picnic Grove',camp='Pine Campground',park='Woodland Park'}
local function clearing(ctx,points,index,trailId)
    local radius=4.2
    for i=4,#points-3 do
        local p=points[i];local next=points[i+1]
        local d=distance(p,next)
        local nx,nz=-(next[2]-p[2])/d,(next[1]-p[1])/d
        for _,side in ipairs({1,-1}) do
            local x,z=q(p[1]+nx*side*(radius+2)),q(p[2]+nz*side*(radius+2))
            local h=ctx.plan:height(x,z)
            -- Keep the whole clearing outside the building grading aprons so
            -- its saved flat height does not get pulled toward a nearby pad.
            local safe=h>1 and clearLot(ctx,x,z,radius+2+Sites.GRADE_APRON) and clearEdges(ctx,x,z,radius+3)
            for _,area in ipairs(ctx.town.recreation) do
                if M.length(area.x-x,area.z-z)<25 then safe=false end
            end
            for k=1,8 do
                local angle=math.pi*k/4
                local sample=ctx.plan:height(x+math.cos(angle)*(radius+1.5),z+math.sin(angle)*(radius+1.5))
                if sample<.8 or math.abs(sample-h)>1 then safe=false;break end
            end
            if safe then
                local kind=kinds[(index+ctx.town.seed-1)%#kinds+1]
                return {id=kind..'-'..index,kind=kind,label=labels[kind],trailId=trailId,
                    x=x,z=z,h=q(h),radius=radius,heading=q(math.atan2(-nz*side,-nx*side))}
            end
        end
    end
end
local function commitJunctions(inserts)
    for road,byEdge in pairs(inserts) do
        local points,flags={},{}
        for i,p in ipairs(road.points) do
            points[#points+1]=p
            if i<#road.points then
                local bridge=road.bridgeEdges and road.bridgeEdges[i]==true or false
                flags[#points]=bridge
                if byEdge[i] then points[#points+1]=byEdge[i];flags[#points]=bridge end
            end
        end
        road.points,road.bridgeEdges=points,flags
    end
end
function Trails.generate(town,plan)
    if not plan then
        local model=town.terrain and town.terrain.mode=='island-town-v3'
            and require('src.commute.town_terrain_v3') or Terrain
        plan=model.new(town.terrain,{size=town.size,center=town.size/2,radius=model.ISLAND_RADIUS or 201})
    end
    local ctx={town=town,plan=plan,random=Terrain.random(town.seed,77),pads={},
        sites=Sites.create({placements=town.placements,designs=town.designs}).all}
    for _,site in ipairs(ctx.sites) do ctx.pads[#ctx.pads+1]=town.destinations[site.id] end
    local nodes,edges,anchors=buildNetwork(town);ctx.edges=edges
    ctx.junctions=town.generatorVersion>=5 and require('src.commute.roads').junctionsFor(town.roads) or {}
    town.recreation={}
    local count,inserts,used=0,{},{}
    local settings=town.terrain.settings
    local target=settings and ({0,1,3,7})[settings.trails] or town.seed%2+3
    if target==0 then return 0 end
    for _,pair in ipairs(pairsByUsefulness(ctx,nodes,anchors)) do
        if not used[pair.a] and not used[pair.b] then
            for _,bend in ipairs(bendValues(ctx,pair)) do
                local points=path(ctx,pair,bend)
                if points then
                    local id='woodland-trail-'..(count+1)
                    local area=#town.recreation<3 and clearing(ctx,points,count+1,id)
                    if settings or area or #town.recreation>=2 then
                        for _,n in ipairs({pair.a,pair.b}) do
                            used[n]=true
                            if n.insert then
                                local road=n.insert.road
                                inserts[road]=inserts[road] or {};inserts[road][n.insert.index]=n.p
                            end
                        end
                        town.roads[#town.roads+1]={id=id,role='trail',surface='dirt',width=Trails.WIDTH,
                            lanes=1,oneWay=false,turnLane=false,sidewalks=false,points=points,interpolation='linear'}
                        for i=1,#points-1 do edges[#edges+1]=edge(points[i],points[i+1],Trails.WIDTH) end
                        if area then town.recreation[#town.recreation+1]=area end
                        count=count+1;break
                    end
                end
            end
        end
        if count>=target then break end
    end
    commitJunctions(inserts)
    return count
end
return Trails
