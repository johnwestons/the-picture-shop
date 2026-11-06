-- Metres from the truck sprite's road anchor to its bumpers, sides and roof.
local F={halfLength=2.74,halfWidth=1.08,height=2.89}

-- Separating axes of the oriented truck rectangle and a roadside segment.
-- A zero-length segment tests a trunk, rock or post with the supplied radius.
function F.overlaps(x,z,c,s,ax,az,bx,bz,radius)
    local dx,dz=(bx-ax)*.5,(bz-az)*.5
    local mx,mz=ax+dx-x,az+dz-z
    local along,side=mx*c+mz*s,-mx*s+mz*c
    local du,dv=dx*c+dz*s,-dx*s+dz*c
    if du==0 and dv==0 then
        local u=math.max(0,math.abs(along)-F.halfLength)
        local v=math.max(0,math.abs(side)-F.halfWidth)
        return u*u+v*v<=radius*radius
    end
    return math.abs(along)<=F.halfLength+math.abs(du)+radius
        and math.abs(side)<=F.halfWidth+math.abs(dv)+radius
        and math.abs(along*dv-side*du)<=F.halfLength*math.abs(dv)+F.halfWidth*math.abs(du)
            +radius*math.sqrt(du*du+dv*dv)
end
F.radius=math.sqrt(F.halfLength^2+F.halfWidth^2)
function F.overlapsTruck(x,z,heading,otherX,otherZ,otherHeading)
    local ac,as=math.cos(heading),math.sin(heading)
    local bc,bs=math.cos(otherHeading),math.sin(otherHeading)
    local dx,dz=otherX-x,otherZ-z
    local function separated(ax,az)
        local separation=math.abs(dx*ax+dz*az)
        local aRadius=F.halfLength*math.abs(ac*ax+as*az)+F.halfWidth*math.abs(-as*ax+ac*az)
        local bRadius=F.halfLength*math.abs(bc*ax+bs*az)+F.halfWidth*math.abs(-bs*ax+bc*az)
        return separation>aRadius+bRadius
    end
    return not separated(ac,as) and not separated(-as,ac)
        and not separated(bc,bs) and not separated(-bs,bc)
end

-- Sweep a circular actor against the truck's oriented footprint. The bike
-- controller already subdivides travel into short steps; binary search the
-- first overlap in each step to return a stable contact point and normal.
function F.sweepCircle(x,z,nx,nz,radius,truckX,truckZ,heading)
    local c,s=math.cos(heading),math.sin(heading)
    local dx,dz=nx-x,nz-z
    local function pointAt(t)
        local px,pz=x+dx*t,z+dz*t
        local ox,oz=px-truckX,pz-truckZ
        local along,side=ox*c+oz*s,-ox*s+oz*c
        local nearAlong=math.max(-F.halfLength,math.min(F.halfLength,along))
        local nearSide=math.max(-F.halfWidth,math.min(F.halfWidth,side))
        local ex,ez=along-nearAlong,side-nearSide
        return ex*ex+ez*ez<=radius*radius,along,side,nearAlong,nearSide,ex,ez
    end
    local function escapeScore(t)
        local _,along,side,_,_,ex,ez=pointAt(t)
        if math.abs(along)<=F.halfLength and math.abs(side)<=F.halfWidth then
            return -math.min(F.halfLength-math.abs(along),F.halfWidth-math.abs(side))
        end
        return math.sqrt(ex*ex+ez*ez)
    end
    local atStart=pointAt(0)
    local atEnd=pointAt(1)
    if not atEnd then return nil end
    local first=0
    if atStart then
        -- Let a bike that began overlapped escape in the direction that
        -- increases clearance; otherwise keep it from driving deeper.
        if escapeScore(1)>escapeScore(0)+1e-6 then return nil end
    else
        local low,high=0,1
        for _=1,12 do
            local middle=(low+high)*.5
            if pointAt(middle) then high=middle else low=middle end
        end
        first=high
    end
    local _,along,side,nearAlong,nearSide,ex,ez=pointAt(first)
    local distance=math.sqrt(ex*ex+ez*ez)
    local localX,localZ
    if distance>1e-7 then
        localX,localZ=ex/distance,ez/distance
    elseif F.halfLength-math.abs(along)<F.halfWidth-math.abs(side) then
        localX,localZ=along<0 and -1 or 1,0
    else
        localX,localZ=0,side<0 and -1 or 1
    end
    return first,localX*c-localZ*s,localX*s+localZ*c
end

function F.hitsEdges(rects,x,z,c,s)
    for _,rect in ipairs(rects) do
        if x+F.radius>=rect.minX and x-F.radius<=rect.maxX and z+F.radius>=rect.minZ and z-F.radius<=rect.maxZ then
            local a=rect.corners[4]
            for _,b in ipairs(rect.corners) do
                if F.overlaps(x,z,c,s,a.x,a.z,b.x,b.z,0) then return true end
                a=b
            end
        end
    end
    return false
end
return F
