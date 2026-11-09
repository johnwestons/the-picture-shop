-- Solid, untextured bridge structures. Road support/collision stay in roads.lua.
-- Coordinates and layout come entirely from the supplied road network and terrain.
local BridgeArt=require('src.commute.bridge_art')
local Geometry={DECK_CLEARANCE=.045,SLAB_DEPTH=.34,MAX_VERTICES_PER_SEGMENT=400,MAX_VERTICES_PER_BAY=600}
local colors={asphalt={.25,.27,.28,1},concrete={.62,.61,.57,1},coping={.73,.72,.67,1},
    rib={.66,.65,.61,1},girder={.34,.37,.37,1},joint={.13,.15,.15,1},
    footing={.48,.48,.44,1},bearing={.23,.26,.26,1}}
local function finite(n)return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge end
local function point(x,z,h)return {x=x,z=z,h=h} end
local function triangle(piece,a,b,c,color,hint)
    local ux,uy,uz=b.x-a.x,b.h-a.h,b.z-a.z
    local vx,vy,vz=c.x-a.x,c.h-a.h,c.z-a.z
    local nx,ny,nz=uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx
    if hint and nx*hint[1]+ny*hint[2]+nz*hint[3]<0 then
        b,c=c,b;nx,ny,nz=-nx,-ny,-nz
    end
    local length=math.sqrt(nx*nx+ny*ny+nz*nz)
    assert(length>1e-10,'Degenerate bridge triangle')
    nx,ny,nz=nx/length,ny/length,nz/length
    for _,p in ipairs({a,b,c}) do
        piece.vertices[#piece.vertices+1]={p.x,p.z,p.h,nx,ny,nz,0,0,color[1],color[2],color[3],color[4] or 1}
    end
end
local function quad(piece,a,b,c,d,color,hint)
    triangle(piece,a,b,c,color,hint);triangle(piece,a,c,d,color,hint)
end
local function piece(id,kind,center,extra)
    local result={id=id,kind=kind,x=center.x,z=center.z,h=center.h,center=center,vertices={}}
    for key,value in pairs(extra or {}) do result[key]=value end
    return result
end
-- Extrude a convex lateral/height profile along a sampled road segment.
-- Profiles are counterclockwise in lateral/up coordinates. Every extrusion
-- includes its two end faces, so a rail or girder remains solid when seen end-on.
local function extrude(target,a,b,nx,nz,profile,color,shift)
    local dx,dz=b.x-a.x,b.z-a.z;local length=math.sqrt(dx*dx+dz*dz)
    assert(length>1e-7,'Bridge segment must have positive length')
    local front,back={},{};shift=shift or 0
    for i,p in ipairs(profile) do
        local lateral=p[1]+shift
        front[i]=point(a.x+nx*lateral,a.z+nz*lateral,a.h+p[2])
        back[i]=point(b.x+nx*lateral,b.z+nz*lateral,b.h+p[2])
    end
    for i=2,#profile-1 do
        triangle(target,front[1],front[i],front[i+1],color,{-dx/length,0,-dz/length})
        triangle(target,back[1],back[i],back[i+1],color,{dx/length,0,dz/length})
    end
    for i,p in ipairs(profile) do
        local j=i%#profile+1;local q=profile[j]
        local lateral,vertical=q[2]-p[2],p[1]-q[1]
        quad(target,front[i],front[j],back[j],back[i],color,{nx*lateral,vertical,nz*lateral})
    end
end
local function profile(width,bottom,top,chamfer)
    assert(width>0 and top>bottom,'Bridge solids need positive dimensions')
    local w=width*.5;local c=math.min(chamfer or 0,width*.2,(top-bottom)*.2)
    if c<=0 then return {{-w,bottom},{w,bottom},{w,top},{-w,top}} end
    return {{-w,bottom+c},{-w+c,bottom},{w-c,bottom},{w,bottom+c},
        {w,top-c},{w-c,top},{-w+c,top},{-w,top-c}}
end
local function beam(target,a,b,nx,nz,width,bottom,top,color,shift,chamfer)
    extrude(target,a,b,nx,nz,profile(width,bottom,top,chamfer),color,shift)
end
local function box(target,c,tx,tz,length,width,bottom,top,color,chamfer)
    local a=point(c.x-tx*length*.5,c.z-tz*length*.5,c.h)
    local b=point(c.x+tx*length*.5,c.z+tz*length*.5,c.h)
    beam(target,a,b,-tz,tx,width,bottom,top,color,0,chamfer)
end
local function groups(roads)
    local result,current={},nil
    for _,s in ipairs(roads.segments or {}) do
        if s.bridge then
            assert(finite(s.len) and s.len>1e-7 and finite(s.width) and s.width>0,'Invalid bridge segment')
            if not current or current.id~=s.id then
                current={id=s.id,segments={},length=0};result[#result+1]=current
            end
            current.segments[#current.segments+1]=s;current.length=current.length+s.len
        else current=nil end
    end
    return result
end
local function tangentAt(group,distance)
    local traversed=0
    for i,s in ipairs(group.segments) do
        if distance<traversed+s.len-1e-8 or i==#group.segments then
            local dx,dz=s.b.x-s.a.x,s.b.z-s.a.z;local length=math.sqrt(dx*dx+dz*dz)
            return dx/length,dz/length
        end
        traversed=traversed+s.len
    end
end
local function terrain(world,x,z)
    return world.ungradedHeight and world:ungradedHeight(x,z) or world:height(x,z)
end
local function clipRange(origin,delta,minimum,maximum,low,high)
    if math.abs(delta)<1e-9 then
        if origin<minimum or origin>maximum then return nil end
        return low,high
    end
    local a,b=(minimum-origin)/delta,(maximum-origin)/delta
    if a>b then a,b=b,a end
    low,high=math.max(low,a),math.min(high,b)
    if low>high then return nil end
    return low,high
end
local function visibleWallIntervals(a,b,ownId,segments)
    -- At a same-level bridge junction, parapets and girders stop at the other
    -- deck's edge instead of continuing across its driveable surface.
    local dx,dz=b.x-a.x,b.z-a.z
    local blocked={}
    for _,other in ipairs(segments) do
        if other.bridge and other.id~=ownId then
            local tx,tz=other.dx/other.len,other.dz/other.len
            local nx,nz=-tz,tx
            local ox,oz=a.x-other.a.x,a.z-other.a.z
            local along0,alongD=ox*tx+oz*tz,dx*tx+dz*tz
            local side0,sideD=ox*nx+oz*nz,dx*nx+dz*nz
            -- Road segment.a is the segment start, so the along interval is
            -- [0,len]. Centering it on the start clips only half of each
            -- crossing segment and leaves bridge supports inconsistently cut.
            local low,high=clipRange(along0,alongD,-.04,other.len+.04,0,1)
            if low then
                low,high=clipRange(side0,sideD,-other.width*.5-.32,other.width*.5+.32,low,high)
                if low then
                    -- Only remove parapets/girders where the other bridge is
                    -- at the same elevation. A crossing at a different level
                    -- must keep its solid sides and underside.
                    local otherGrade=(other.b.h-other.a.h)/other.len
                    local height0=a.h-other.a.h-otherGrade*along0
                    local heightD=(b.h-a.h)-otherGrade*alongD
                    low,high=clipRange(height0,heightD,-BridgeArt.DECK_LEVEL_TOLERANCE,
                        BridgeArt.DECK_LEVEL_TOLERANCE,low,high)
                    if low then blocked[#blocked+1]={low,high} end
                end
            end
        end
    end
    table.sort(blocked,function(left,right)return left[1]<right[1] end)
    local merged={}
    for _,range in ipairs(blocked) do
        local last=merged[#merged]
        if last and range[1]<=last[2]+1e-5 then last[2]=math.max(last[2],range[2])
        else merged[#merged+1]={range[1],range[2]} end
    end
    local visible={};local cursor=0
    for _,range in ipairs(merged) do
        if range[1]>cursor+1e-4 then visible[#visible+1]={cursor,range[1]} end
        cursor=math.max(cursor,range[2])
    end
    if cursor<1-1e-4 then visible[#visible+1]={cursor,1} end
    return visible
end
local function lerpPoint(a,b,t)
    return point(a.x+(b.x-a.x)*t,a.z+(b.z-a.z)*t,a.h+(b.h-a.h)*t)
end
local function finish(target)
    local bounds={minX=math.huge,minZ=math.huge,minH=math.huge,maxX=-math.huge,maxZ=-math.huge,maxH=-math.huge}
    for _,v in ipairs(target.vertices) do
        for _,n in ipairs(v) do assert(finite(n),'Bridge mesh contains a nonfinite attribute') end
        bounds.minX=math.min(bounds.minX,v[1]);bounds.maxX=math.max(bounds.maxX,v[1])
        bounds.minZ=math.min(bounds.minZ,v[2]);bounds.maxZ=math.max(bounds.maxZ,v[2])
        bounds.minH=math.min(bounds.minH,v[3]);bounds.maxH=math.max(bounds.maxH,v[3])
    end
    bounds.radius=0
    for _,v in ipairs(target.vertices) do
        bounds.radius=math.max(bounds.radius,math.sqrt((v[1]-target.x)^2+(v[2]-target.z)^2))
    end
    target.bounds=bounds;target.radius=bounds.radius
    return target
end
function Geometry.build(world)
    assert(world and world.roads and world.height,'Bridge geometry needs roads and terrain')
    local result={}
    for groupIndex,group in ipairs(groups(world.roads)) do
        local roads={segments=group.segments};local prefix=tostring(group.id)..':'..groupIndex
        local center=BridgeArt.pointAt(group,group.length*.5,0,0)
        local deck=piece(prefix..':deck','bridgeDeck',center,{bridgeId=group.id,span=groupIndex})
        local sides=BridgeArt.layout(roads);local caps=BridgeArt.capLayout(roads)
        local bays=#sides/2;local walls={}
        for _,side in ipairs(sides) do
            local key=side.bay..':'..side.side
            walls[key]=piece(prefix..':wall:'..key,'bridgeWall',side.center,
                {bridgeId=group.id,bay=side.bay,side=side.side})
        end
        local above=BridgeArt.PROFILE_METERS*BridgeArt.DECK_LINE_FROM_TOP
        local girderBottom=-BridgeArt.GIRDER_DEPTH_METERS
        local traversed=0
        for index,s in ipairs(group.segments) do
            local nx,nz=s.nx,s.nz
            -- One deck group contains all samples; no extra draw item per sample.
            beam(deck,s.a,s.b,nx,nz,s.width,Geometry.DECK_CLEARANCE-Geometry.SLAB_DEPTH,
                Geometry.DECK_CLEARANCE,colors.asphalt)
            for _,side in ipairs({-1,1}) do
                local offset=side*s.width*.32
                local a=point(s.a.x+nx*offset,s.a.z+nz*offset,s.a.h)
                local b=point(s.b.x+nx*offset,s.b.z+nz*offset,s.b.h)
                for _,interval in ipairs(visibleWallIntervals(a,b,group.id,world.roads.segments)) do
                    beam(deck,lerpPoint(a,b,interval[1]),lerpPoint(a,b,interval[2]),
                        nx,nz,.42,girderBottom,-.27,colors.girder)
                end
            end
            local spacing=group.length/bays
            local firstBay=math.min(bays,math.floor(traversed/spacing)+1)
            local lastBay=math.min(bays,math.floor((traversed+s.len-1e-8)/spacing)+1)
            for bay=firstBay,lastBay do
                local from=math.max(traversed,(bay-1)*spacing)
                local to=math.min(traversed+s.len,bay*spacing)
                -- Cumulative road samples can land a few ulps below a bay
                -- edge. That empty overlap is not a solid wall segment.
                if to-from>1e-7 then
                local ta,tb=(from-traversed)/s.len,(to-traversed)/s.len
                for sideIndex,side in ipairs({-1,1}) do
                    local cap=caps[(index-1)*2+sideIndex]
                    local function at(t)return point(cap.a.x+(cap.b.x-cap.a.x)*t,
                        cap.a.z+(cap.b.z-cap.a.z)*t,cap.a.h+(cap.b.h-cap.a.h)*t) end
                    local a,b=at(ta),at(tb)
                    local wall=walls[bay..':'..side]
                    local shift=side*BridgeArt.CAP_WIDTH_METERS*(BridgeArt.CAP_OUTER_FRACTION-.5)
                    for _,interval in ipairs(visibleWallIntervals(a,b,group.id,world.roads.segments)) do
                        local clippedA,clippedB=lerpPoint(a,b,interval[1]),lerpPoint(a,b,interval[2])
                        beam(wall,clippedA,clippedB,nx,nz,.34,-.15,above-.14,colors.concrete,shift)
                        beam(wall,clippedA,clippedB,nx,nz,BridgeArt.CAP_WIDTH_METERS,above-.16,above+.02,
                            colors.coping,shift,.035)
                    end
                end
                end
            end
            traversed=traversed+s.len
        end
        -- Bay-end ribs add actual relief beneath the coping; they do not widen
        -- its registered outer/inner limits or alter the driveable support plane.
        for _,side in ipairs(sides) do
            local target=walls[side.bay..':'..side.side]
            local distance=(side.bay-.5)*side.spacing
            local tx,tz=tangentAt(group,distance)
            local shift=side.side*BridgeArt.CAP_WIDTH_METERS*(BridgeArt.CAP_OUTER_FRACTION-.5)
            for _,endPoint in ipairs({side.a,side.b}) do
                if not BridgeArt.onOtherBridgeDeck(endPoint.x,endPoint.z,group.id,world.roads,.32,endPoint.h) then
                    local c=point(endPoint.x-tz*shift,endPoint.z+tx*shift,endPoint.h)
                    box(target,c,tx,tz,.13,.40,.09,above-.16,colors.rib)
                end
            end
        end
        -- Terminal posts belong to their adjacent wall items for painter order.
        for _,post in ipairs(BridgeArt.endPostLayout(roads,world.roads)) do
            local bay=post.endName=='start' and 1 or bays
            local target=walls[bay..':'..post.side]
            local tx,tz=tangentAt(group,post.endName=='start' and 0 or group.length)
            local c=point(post.x,post.z,post.h)
            box(target,c,tx,tz,post.width,post.width,0,.20,colors.concrete,.035)
            box(target,c,tx,tz,post.width-.08,post.width-.08,.16,post.height-.14,colors.concrete,.025)
            box(target,c,tx,tz,post.width,post.width,post.height-.16,post.height+.02,colors.coping,.035)
        end
        -- Thin finite expansion-joint bars at the abutments and pier axes.
        local joints={0,group.length}
        for _,fraction in ipairs(BridgeArt.PIER_FRACTIONS) do joints[#joints+1]=group.length*fraction end
        for _,distance in ipairs(joints) do
            local c=BridgeArt.pointAt(group,distance,0,0);local tx,tz=tangentAt(group,distance)
            if not BridgeArt.onOtherBridgeDeck(c.x,c.z,group.id,world.roads,nil,c.h) then
                box(deck,c,tx,tz,.045,c.width-.72,Geometry.DECK_CLEARANCE+.001,
                    Geometry.DECK_CLEARANCE+.008,colors.joint)
            end
        end
        result[#result+1]=finish(deck)
        for _,side in ipairs(sides) do
            local wall=walls[side.bay..':'..side.side]
            if #wall.vertices>0 then result[#result+1]=finish(wall) end
        end
        local subworld={roads=roads,height=function(_,x,z)return world:height(x,z) end,
            ungradedHeight=function(_,x,z)return terrain(world,x,z) end}
        for _,pier in ipairs(BridgeArt.pierLayout(subworld,nil,world.roads)) do
            local tx,tz=tangentAt(group,group.length*BridgeArt.PIER_FRACTIONS[pier.pier])
            local target=piece(prefix..':pier:'..pier.pier,'bridgePier',point(pier.x,pier.z,pier.baseHeight),
                {bridgeId=group.id,pier=pier.pier,deckHeight=pier.deckHeight,
                    topHeight=pier.topHeight,baseHeight=pier.baseHeight})
            local capBottom=pier.topHeight-.38
            box(target,point(pier.x,pier.z,0),tx,tz,1.12,pier.width,capBottom,pier.topHeight,colors.concrete,.06)
            for _,side in ipairs({-1,1}) do
                local c=point(pier.x-tz*side*pier.width*.28,pier.z+tx*side*pier.width*.28,0)
                local minGround,maxGround=math.huge,-math.huge
                for _,along in ipairs({-.78,.78}) do for _,across in ipairs({-.64,.64}) do
                    local h=terrain(world,c.x+tx*along-tz*across,c.z+tz*along+tx*across)
                    minGround=math.min(minGround,h);maxGround=math.max(maxGround,h)
                end end
                local footingTop=math.min(maxGround+.20,capBottom-.15)
                local footingBottom=math.min(minGround-.18,footingTop-.32)
                box(target,c,tx,tz,1.56,1.28,footingBottom,footingTop,colors.footing,.055)
                box(target,c,tx,tz,.76,.72,footingTop,capBottom+.025,colors.concrete,.045)
                box(target,c,tx,tz,.98,.96,capBottom-.18,capBottom+.04,colors.coping,.035)
                box(target,c,tx,tz,.65,.56,pier.topHeight-.015,pier.topHeight+.055,colors.bearing,.015)
            end
            result[#result+1]=finish(target)
        end
        local vertices=0
        for _,entry in ipairs(result) do if entry.span==groupIndex or entry.id:sub(1,#prefix+1)==prefix..':' then vertices=vertices+#entry.vertices end end
        local budget=Geometry.MAX_VERTICES_PER_SEGMENT*#group.segments+Geometry.MAX_VERTICES_PER_BAY*bays+2800
        assert(vertices<=budget,'Bridge geometry exceeded its linear mesh budget')
    end
    return result
end
return Geometry
