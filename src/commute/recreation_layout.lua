-- Local metres: side is across the clearing, forward points to its trail entrance.
-- Saved small clearings keep their original layout. New clearings reserve enough
-- space for these facilities before roads, trees and buildings are committed.
local Layout={RADIUS=24}
function Layout.expanded(area)return (area.radius or 0)>=16 end
function Layout.point(area,side,forward)
    local c,s=math.cos(area.heading or 0),math.sin(area.heading or 0)
    return area.x+s*side+c*forward,area.z-c*side+s*forward
end
function Layout.plan(area)
    local result={fixtures={},paths={},patches={}}
    local spacing=area.radius/16
    local entrance=(area.radius+2)/spacing
    local function put(kind,x,z,angle)
        result.fixtures[#result.fixtures+1]={kind=kind,side=x,forward=z,angle=math.rad(angle or 0)}
    end
    local function path(width,points)
        result.paths[#result.paths+1]={width=width,points=points}
    end
    local function patch(kind,x,z,w,d)
        result.patches[#result.patches+1]={kind=kind,side=x,forward=z,width=w,depth=d}
    end
    -- Leave the entrance and every path wide enough to walk or ride through.
    put('parkSign',-2.1,13)
    if area.kind=='camp' then
        path(1.7,{{0,entrance},{0,3},{0,-2},{-3,-5},{-3,-10}})
        path(1.5,{{0,3},{-8,3},{-8,-3.2}})
        path(1.5,{{0,3},{8,3},{8,-3.2}})
        path(1.5,{{0,9},{-6,9}})
        path(1.5,{{0,9},{7,9}})
        for _,side in ipairs({-1,1}) do
            put('tent',side*8,-6)
            put('fireRing',side*5,-3)
            put('logSeat',side*10.5,-3,side*90)
            put('table',side*11,-7)
            patch('campsite',side*8,-5,7,8)
        end
        put('tent',0,-11)
        put('fireRing',0,-7)
        put('logSeat',3,-7,90)
        put('table',3,-11)
        patch('campsite',0,-10,8,7)
        put('rangerHut',-6,6.5)
        put('outhouse',7,6.5)
    else
        -- A loop links the picnic lawn, performance space and pond overlook.
        path(1.7,{{0,entrance},{0,3},{0,-.4},{-3,-.4},{-9,0},{-10,-4},{-9,-11.4},
            {-1,-11.4},{4,-10},{10,-9},{11,-3},{9,1.7},{3,1.7},{0,3}})
        path(1.5,{{-9,0},{-9,5},{-3,5},{0,3}})
        put('pond',6,-5)
        put('bench',6,.1,180)
        put('bench',1,-4,-90)
        put('stage',-5.5,-8)
        for _,z in ipairs({-4,-1.7}) do
            put('logSeat',-7,z,180);put('logSeat',-3.6,z,180)
        end
        for _,x in ipairs({-7,-3.5}) do
            for _,z in ipairs({2.2,7.5}) do put('table',x,z) end
        end
        patch('gathering',-5.5,5,8,9)
        -- Three compact bays reached by the existing public woodland track.
        patch('parking',6,9,8,5)
        path(3.2,{{0,entrance},{6,13},{6,10.5}})
    end
    for _,f in ipairs(result.fixtures) do f.side,f.forward=f.side*spacing,f.forward*spacing end
    for _,p in ipairs(result.patches) do
        p.side,p.forward=p.side*spacing,p.forward*spacing
        if p.kind~='parking' then p.width,p.depth=p.width*spacing,p.depth*spacing end
    end
    for _,p in ipairs(result.paths) do
        for _,point in ipairs(p.points) do point[1],point[2]=point[1]*spacing,point[2]*spacing end
    end
    return result
end
-- Round the authored corners, then resample for terrain-following path ribbons.
-- Adjacent quads share their edges, so bends cannot leave triangular cracks.
function Layout.pathPoints(path)
    local points=path.points;local curved={points[1]}
    for i=2,#points-1 do
        local a,b,c=points[i-1],points[i],points[i+1]
        local ax,az=a[1]-b[1],a[2]-b[2];local bx,bz=c[1]-b[1],c[2]-b[2]
        local la,lb=math.sqrt(ax*ax+az*az),math.sqrt(bx*bx+bz*bz)
        local r=math.min(2.8,la*.3,lb*.3)
        local start={b[1]+ax/la*r,b[2]+az/la*r}
        local finish={b[1]+bx/lb*r,b[2]+bz/lb*r}
        curved[#curved+1]=start
        for step=1,8 do
            local t=step/8;local s=1-t
            curved[#curved+1]={s*s*start[1]+2*s*t*b[1]+t*t*finish[1],
                s*s*start[2]+2*s*t*b[2]+t*t*finish[2]}
        end
    end
    curved[#curved+1]=points[#points]
    local dense={curved[1]}
    for i=1,#curved-1 do
        local a,b=curved[i],curved[i+1];local dx,dz=b[1]-a[1],b[2]-a[2]
        local length=math.sqrt(dx*dx+dz*dz)
        if length>.0001 then
            local steps=math.ceil(length/.75)
            for step=1,steps do dense[#dense+1]={a[1]+dx*step/steps,a[2]+dz*step/steps} end
        end
    end
    return dense
end
-- Solid footprints follow the model rather than using a wide circular blocker
-- that would close the narrow gaps between seats and footpaths.
local footprints={stage={5.2,3,.6},logSeat={2.4,.48,.5},rangerHut={3.6,2.8,3.3},
    outhouse={1.8,1.8,2.7},table={2.1,1.75,.8},bench={1.8,.55,.88},tent={2.14,2.65,1.48},
    fireRing={1.4,1.4,.28},parkSign={.16,.16,2.05}}
function Layout.install(plan,area,addCollider)
    local layout=Layout.plan(area)
    plan.recreationSurfaces=plan.recreationSurfaces or {}
    plan.recreationGroundBins=plan.recreationGroundBins or {}
    for _,spec in ipairs(layout.fixtures) do
        local x,z=Layout.point(area,spec.side,spec.forward)
        local angle=(area.heading or 0)+spec.angle
        local f={kind=spec.kind,x=x,z=z,h=area.h,fx=math.cos(angle),fz=math.sin(angle),
            roadId=area.trailId,areaId=area.id,label=area.kind=='camp' and 'CAMP' or 'PARK'}
        plan.fixtures[#plan.fixtures+1]=f
        plan.counts[f.kind]=(plan.counts[f.kind] or 0)+1
        local function capsule(a,b,forward,radius,height)
            addCollider(plan,f.kind,x+f.fz*a+f.fx*forward,z-f.fx*a+f.fz*forward,
                x+f.fz*b+f.fx*forward,z-f.fx*b+f.fz*forward,area.h,area.h,radius,height,area.trailId)
        end
        if f.kind=='pond' then capsule(-1.1,1.1,0,2.6,.4)
        else
            local size=footprints[f.kind]
            local radius=math.min(.22,size[1]/2,size[2]/2)
            local rows=math.max(1,math.ceil((size[2]-radius*2)/radius)+1)
            for row=1,rows do
                local forward=rows==1 and 0 or -size[2]/2+radius+(row-1)*(size[2]-radius*2)/(rows-1)
                capsule(-size[1]/2+radius,size[1]/2-radius,forward,radius,size[3])
            end
        end
    end
    local function surface(kind,points,color)
        local corners={}
        for _,p in ipairs(points) do
            local x,z=Layout.point(area,p[1],p[2])
            corners[#corners+1]={x,z,plan.world:height(x,z)+(kind=='path' and .065 or .035)}
        end
        plan.recreationSurfaces[#plan.recreationSurfaces+1]={kind=kind,areaId=area.id,
            x=corners[1][1],z=corners[1][2],corners=corners,color=color}
        if kind~='marking' then
            local bounds={x0=math.huge,z0=math.huge,x1=-math.huge,z1=-math.huge,h=math.huge}
            for _,v in ipairs(corners) do
                bounds.x0,bounds.z0=math.min(bounds.x0,v[1]),math.min(bounds.z0,v[2])
                bounds.x1,bounds.z1=math.max(bounds.x1,v[1]),math.max(bounds.z1,v[2])
                bounds.h=math.min(bounds.h,v[3]-.08)
            end
            -- Cover the diagonal of a 1.5 m mobile terrain cell as well as
            -- the visible ribbon. This only affects displayed soil, not physics.
            for ix=math.floor((bounds.x0-2.2)/16),math.floor((bounds.x1+2.2)/16) do
                for iz=math.floor((bounds.z0-2.2)/16),math.floor((bounds.z1+2.2)/16) do
                    local key=ix..':'..iz;local bin=plan.recreationGroundBins[key] or {}
                    bin[#bin+1]=bounds;plan.recreationGroundBins[key]=bin
                end
            end
        end
    end
    for _,p in ipairs(layout.patches) do
        local x,z,w,d=p.side,p.forward,p.width/2,p.depth/2
        local color=p.kind=='parking' and {.35,.35,.30} or {.48,.42,.29}
        surface(p.kind,{{x-w+.7,z-d},{x+w-.7,z-d},{x+w,z-d+.7},{x+w,z+d-.7},
            {x+w-.7,z+d},{x-w+.7,z+d},{x-w,z+d-.7},{x-w,z-d+.7}},color)
        if p.kind=='parking' then
            for i=0,3 do
                local side=x-3.6+i*2.4
                surface('marking',{{side-.045,z-1.9},{side+.045,z-1.9},
                    {side+.045,z+1.8},{side-.045,z+1.8}},{.82,.79,.63})
                -- Separate the painted lines from the lot in the depth buffer.
                for _,v in ipairs(plan.recreationSurfaces[#plan.recreationSurfaces].corners) do v[3]=v[3]+.01 end
            end
        end
    end
    for _,p in ipairs(layout.paths) do
        local points=Layout.pathPoints(p);local sides={}
        for i,point in ipairs(points) do
            local a,b=points[math.max(1,i-1)],points[math.min(#points,i+1)]
            local dx,dz=b[1]-a[1],b[2]-a[2];local length=math.sqrt(dx*dx+dz*dz)
            local nx,nz=-dz/length*p.width/2,dx/length*p.width/2
            sides[i]={{point[1]+nx,point[2]+nz},{point[1]-nx,point[2]-nz}}
        end
        for i=1,#sides-1 do
            local a,b=sides[i],sides[i+1]
            surface('path',{a[1],b[1],b[2],a[2]},{.64,.55,.37})
        end
    end
end
return Layout
