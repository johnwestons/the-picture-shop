-- Design the island streets before placing addresses. The resulting polylines
-- are frozen in the town and are shared by navigation, rendering and physics.
local M=require('src.commute.vendor.mathx')
local Alignment={}
local PLATFORM=13 -- level ground through the widest intersection and its shoulder
local EASE=9      -- distance over which the road enters its climbing grade
local function round(v) return math.floor(v*1000+.5)/1000 end

-- Find a common set of junction elevations. Upper and lower grade envelopes
-- share the cuts and fills between neighbours instead of moving one road end.
local function gradeNodes(nodes,edges)
    local low,high={},{}
    for i,p in ipairs(nodes) do low[i],high[i]=p[3],p[3] end
    for pass=1,#nodes do
        local changed=false
        for _,e in ipairs(edges) do
            local a,b=e.a,e.b
            local allowance=(e.length-2*PLATFORM-EASE)*(e.main and .045 or .06)
            local al,bl=math.min(low[a],low[b]+allowance),math.min(low[b],low[a]+allowance)
            local ah,bh=math.max(high[a],high[b]-allowance),math.max(high[b],high[a]-allowance)
            if al~=low[a] or bl~=low[b] or ah~=high[a] or bh~=high[b] then changed=true end
            low[a],low[b],high[a],high[b]=al,bl,ah,bh
        end
        if not changed then break end
    end
    for i,p in ipairs(nodes) do p[3]=round((low[i]+high[i])*.5) end
end

local function rise(distance,length)
    local usable=length-2*PLATFORM
    local x=M.clamp(distance-PLATFORM,0,usable)
    if x<EASE then return x*x/(2*EASE*(usable-EASE)) end
    if x>usable-EASE then return 1-(usable-x)^2/(2*EASE*(usable-EASE)) end
    return (x-EASE*.5)/(usable-EASE)
end

local function wet(plan,x,z,nx,nz,half)
    return plan:height(x,z)<.8 or plan:height(x+half*nx,z+half*nz)<.8
        or plan:height(x-half*nx,z-half*nz)<.8
end

-- Choose a through movement at each intersection. Nearby opposite arms
-- share a tangent there. Side streets still approach the junction separately.
local function aim(arms)
    local paired={}
    while true do
        local best,first,second=-math.huge
        for i,a in ipairs(arms) do for j=i+1,#arms do
            local b=arms[j]
            local dot=a.x*b.x+a.z*b.z
            if not paired[i] and not paired[j] and dot<(#arms==2 and .05 or -.60) then
                local score=-dot+(a.edge.main and b.edge.main and 2 or 0)
                if score>best then best,first,second=score,i,j end
            end
        end end
        if not first then break end
        local a,b=arms[first],arms[second]
        local tx,tz=a.x-b.x,a.z-b.z
        if a.edge.crossing then tx,tz=a.x,a.z
        elseif b.edge.crossing then tx,tz=-b.x,-b.z end
        for _,arm in ipairs({a,b}) do
            local sign=arm==a and 1 or -1
            local forward=(tx*arm.x+tz*arm.z)*sign
            if not arm.edge.crossing and forward>.01 then
                local lateral=(tx*arm.edge.nx+tz*arm.edge.nz)*sign
                arm.edge[arm.endpoint]=M.clamp(lateral/forward,-1,1)
            end
        end
        paired[first],paired[second]=true,true
    end
end

function Alignment.prepare(nodes,edges,plan,hub)
    local branches={}
    for i=1,#nodes do branches[i]={} end
    for _,e in ipairs(edges) do
        local a,b=nodes[e.a],nodes[e.b]
        local dx,dz=b[1]-a[1],b[2]-a[2]
        e.length=M.length(dx,dz)
        e.nx,e.nz=-dz/e.length,dx/e.length
        e.startSlope,e.endSlope=0,0
        e.half=e.main and ((e.a==hub or e.b==hub) and 4.9 or 3.8) or e.oneWay and 2.1 or 2.9
        local steps=math.ceil(e.length/1.5)
        for i=0,steps do
            if wet(plan,a[1]+dx*i/steps,a[2]+dz*i/steps,e.nx,e.nz,e.half) then e.crossing=true;break end
        end
        table.insert(branches[e.a],{edge=e,endpoint='startSlope',x=dx/e.length,z=dz/e.length})
        table.insert(branches[e.b],{edge=e,endpoint='endSlope',x=-dx/e.length,z=-dz/e.length})
    end
    for _,arms in ipairs(branches) do aim(arms) end
    gradeNodes(nodes,edges)
end

local function alignment(e,a,b,bow,reverse)
    local points={a}
    local steps=math.ceil(e.length/5)
    for i=1,steps-1 do
        local t=i/steps
        local tangent=e.length*t*(1-t)*(e.startSlope*(1-t)+e.endSlope*t)
        local sweep=bow*math.sin(math.pi*t)^2*(reverse and math.cos(math.pi*t) or 1)
        local offset=tangent+sweep
        points[#points+1]={round(M.lerp(a[1],b[1],t)+e.nx*offset),
            round(M.lerp(a[2],b[2],t)+e.nz*offset),round(M.lerp(a[3],b[3],rise(t*e.length,e.length)))}
    end
    points[#points+1]=b
    return points
end

-- Inspect the width of the final alignment, including the inside of each
-- chord. Keep bridge decks straight and extend them onto dry banks.
local function survey(points,e,plan)
    local flags,cost={},0
    local wetEdges={}
    for i=1,#points-1 do
        local a,b=points[i],points[i+1]
        local dx,dz=b[1]-a[1],b[2]-a[2]
        local len=M.length(dx,dz)
        local samples=math.ceil(len/1.5)
        for j=0,samples do
            local x,z=a[1]+dx*j/samples,a[2]+dz*j/samples
            if wet(plan,x,z,-dz/len,dx/len,e.half) then wetEdges[i]=true;break end
        end
        cost=cost+math.abs(plan:landHeight(a[1],a[2])-a[3])
    end
    for i=1,#points-1 do
        flags[i]=(wetEdges[i-1] or wetEdges[i] or wetEdges[i+1])==true
    end
    return flags,cost,next(wetEdges)~=nil
end

function Alignment.street(e,nodes,plan,random)
    local a,b=nodes[e.a],nodes[e.b]
    local reverse=not e.main and random()<.45
    local magnitude=e.length*(e.main and random(.026,.044) or random(.060,.086))
    local best,bestFlags,bestCost
    if not e.crossing then
        for _,sign in ipairs({1,-1}) do
            local points=alignment(e,a,b,magnitude*sign,reverse)
            local flags,cost,water=survey(points,e,plan)
            if not water and (not bestCost or cost<bestCost) then best,bestFlags,bestCost=points,flags,cost end
        end
    end
    if best then return best,bestFlags end
    -- Water can rule out either curved corridor. Use a surveyed straight
    -- crossing and the same eased vertical profile on its approaches.
    e.startSlope,e.endSlope=0,0
    local points=alignment(e,a,b,0,false)
    local flags=survey(points,e,plan)
    return points,flags
end

local function crosses(a,b,c,d)
    if a==c or a==d or b==c or b==d then return false end
    if math.max(a[1],b[1])<math.min(c[1],d[1]) or math.min(a[1],b[1])>math.max(c[1],d[1])
        or math.max(a[2],b[2])<math.min(c[2],d[2]) or math.min(a[2],b[2])>math.max(c[2],d[2]) then return false end
    local dx,dz=b[1]-a[1],b[2]-a[2]
    local sx,sz=d[1]-c[1],d[2]-c[2]
    local det=dx*sz-dz*sx
    local x,z=c[1]-a[1],c[2]-a[2]
    if math.abs(det)<1e-9 then return math.abs(x*dz-z*dx)<1e-9 end
    local u,v=(x*sz-z*sx)/det,(x*dz-z*dx)/det
    return u>=0 and u<=1 and v>=0 and v<=1
end

-- A bend must not create a second, unregistered crossing. Both the routing
-- graph and the signs attach to explicit junctions. Retry the layout if two
-- streets cross elsewhere, even when one chord ends exactly on the other.
function Alignment.connectedOnlyAtNodes(roads)
    for i,first in ipairs(roads) do
        for j=i+1,#roads do
            local second=roads[j]
            for p=2,#first.points do
                local a,b=first.points[p-1],first.points[p]
                for q=2,#second.points do
                    if crosses(a,b,second.points[q-1],second.points[q]) then return false end
                end
            end
        end
    end
    return true
end
return Alignment
