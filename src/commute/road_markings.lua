-- Static pavement paint, shared by both cameras. Coordinates remain in metres;
-- dirt trails have no traffic paint and junction throats remain clear.
local Paint={}
local white={.89,.87,.73};local yellow={.88,.70,.25}
local function vertex(out,x,z,h,color)
    out[#out+1]={x,z,h,0,1,0,x/4,z/4,x/4,z/4,0,0,
        color[1],color[2],color[3],1,0,0,0,0,0,0,0,0}
end
local function quad(out,a,b,c,d,color)
    for _,p in ipairs({a,b,c,a,c,d})do vertex(out,p[1],p[2],p[3],color)end
end
local function strip(out,s,offset,width,color)
    local a,b=s.a,s.b;local l,r=offset-width/2,offset+width/2
    quad(out,{a.x+a.nx*l,a.z+a.nz*l,a.h+.075},{b.x+b.nx*l,b.z+b.nz*l,b.h+.075},
        {b.x+b.nx*r,b.z+b.nz*r,b.h+.075},{a.x+a.nx*r,a.z+a.nz*r,a.h+.075},color)
end
local function arrow(out,world,x,z,dx,dz,bend)
    local nx,nz=-dz,dx
    local function at(side,forward)
        local px,pz=x+nx*side+dx*forward,z+nz*side+dz*forward
        return {px,pz,world:supportHeight(px,pz)+.085}
    end
    quad(out,at(-.11,-1.4),at(.11,-1.4),at(.11,.6),at(-.11,.6),white)
    if bend then
        quad(out,at(-.11,.38),at(-.11,.60),at(-.95,.60),at(-.95,.38),white)
        for _,p in ipairs({at(-1.4,.49),at(-.83,1.0),at(-.83,-.02)})do vertex(out,p[1],p[2],p[3],white)end
    else
        for _,p in ipairs({at(0,1.45),at(-.55,.45),at(.55,.45)})do vertex(out,p[1],p[2],p[3],white)end
    end
end
function Paint.build(world)
    local out={};local stats={arrows=0,turnArrows=0,stopBars=0,segments=0}
    local roads=world.roads;local modern=world.town and world.town.generatorVersion>=3
    local junctions={};local seen={}
    -- Only shared coordinates create a junction. Decorative paint must not
    -- imply a connection between roads that merely cross at different heights.
    if modern then for _,path in ipairs(roads.paths)do
        if path.role~='trail' then for _,p in ipairs(path.points)do
            local key=('%.3f:%.3f:%.3f'):format(p.x,p.z,p.h)
            local previous=seen[key]
            if previous and previous~=path.id then junctions[key]=p else seen[key]=path.id end
        end end
    end end
    local function throat(x,z)
        for _,p in pairs(junctions)do if (p.x-x)^2+(p.z-z)^2<42 then return true end end
        return false
    end
    local lastArrow={}
    for _,s in ipairs(roads.segments)do
        if s.surface~='dirt' and not s.bridge then
            local x,z=(s.a.x+s.b.x)/2,(s.a.z+s.b.z)/2
            if not throat(x,z)then
                stats.segments=stats.segments+1
                local dash=math.floor(s.distance/4)%2==0
                if modern and s.role~='drive' then
                    strip(out,s,s.width*.5-.22,.09,white);strip(out,s,-s.width*.5+.22,.09,white)
                end
                if s.turnLane and (s.lanes or 2)>=3 then
                    for _,side in ipairs({-1,1})do
                        strip(out,s,side*1.63,.09,yellow)
                        if dash then strip(out,s,side*1.47,.09,yellow)end
                    end
                elseif (s.lanes or (s.width>5.5 and 2 or 1))>=2 and dash then
                    strip(out,s,0,.10,s.oneWay and white or yellow)
                end
                if modern and (s.role=='main' or s.oneWay) and s.distance-(lastArrow[s.id] or -20)>=28
                    and not throat(x+s.dx/s.len*4,z+s.dz/s.len*4)then
                    lastArrow[s.id]=s.distance
                    local dx,dz=s.dx/s.len,s.dz/s.len
                    if s.oneWay then arrow(out,world,x,z,dx,dz);stats.arrows=stats.arrows+1
                    else
                        local offset=s.turnLane and 3.05 or s.width*.25
                        arrow(out,world,x+s.nx*offset,z+s.nz*offset,dx,dz)
                        arrow(out,world,x-s.nx*offset,z-s.nz*offset,-dx,-dz)
                        stats.arrows=stats.arrows+2
                        if s.turnLane then
                            local sign=math.floor(s.distance/28)%2==0 and 1 or -1
                            arrow(out,world,x,z,dx*sign,dz*sign,true);stats.turnArrows=stats.turnArrows+1
                        end
                    end
                end
            end
        end
    end
    local infrastructure=world.infrastructure
    for _,f in ipairs(infrastructure and infrastructure.fixtures or {})do
        if f.kind=='stop' and f.stopX then
            -- The sign faces the approaching driver; their right-hand lane is
            -- to the left of that face normal, across half the road width.
            local nx,nz=f.fz,-f.fx;local b=(f.roadWidth or 6)/2-.2;local a=f.oneWay and -b or .2
            local function at(side,d)
                local x,z=f.stopX+nx*side+f.fx*d,f.stopZ+nz*side+f.fz*d
                return {x,z,world:supportHeight(x,z)+.09}
            end
            quad(out,at(a,-.13),at(b,-.13),at(b,.13),at(a,.13),white)
            stats.stopBars=stats.stopBars+1
        end
    end
    return out,stats
end
return Paint
