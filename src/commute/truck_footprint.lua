-- Metres from the truck sprite's road anchor to its bumpers, sides and roof.
local F={halfLength=2.74,halfWidth=1.08,height=2.89}
local dimensionsByModel={box={halfLength=2.74,halfWidth=1.08,height=2.89},
    kei={halfLength=1.76,halfWidth=.76,height=2.30}}

function F.dimensions(model)
    if type(model)=='table' then model=model.model end
    local source=dimensionsByModel[model or 'box'] or dimensionsByModel.box
    return {halfLength=source.halfLength,halfWidth=source.halfWidth,height=source.height,
        radius=math.sqrt(source.halfLength^2+source.halfWidth^2)}
end

-- Separating axes of the oriented truck rectangle and a roadside segment.
-- A zero-length segment tests a trunk, rock or post with the supplied radius.
function F.overlaps(x,z,c,s,ax,az,bx,bz,radius,dims)
    dims=dims or dimensionsByModel.box
    local dx,dz=(bx-ax)*.5,(bz-az)*.5
    local mx,mz=ax+dx-x,az+dz-z
    local along,side=mx*c+mz*s,-mx*s+mz*c
    local du,dv=dx*c+dz*s,-dx*s+dz*c
    if du==0 and dv==0 then
        local u=math.max(0,math.abs(along)-dims.halfLength)
        local v=math.max(0,math.abs(side)-dims.halfWidth)
        if u*u+v*v>radius*radius then return false end
        local nx,nz
        if u*u+v*v>1e-16 then
            local length=math.sqrt(u*u+v*v)
            nx=-(along<0 and -u or u)/length
            nz=-(side<0 and -v or v)/length
        elseif dims.halfLength-math.abs(along)<dims.halfWidth-math.abs(side) then
            nx,nz=along<0 and 1 or -1,0
        else nx,nz=0,side<0 and 1 or -1 end
        return true,nx*c-nz*s,nx*s+nz*c
    end
    local length=math.sqrt(du*du+dv*dv)
    local cross=along*dv-side*du
    local alongDepth=dims.halfLength+math.abs(du)+radius-math.abs(along)
    local sideDepth=dims.halfWidth+math.abs(dv)+radius-math.abs(side)
    local edgeDepth=(dims.halfLength*math.abs(dv)+dims.halfWidth*math.abs(du)
        +radius*length-math.abs(cross))/length
    if alongDepth<0 or sideDepth<0 or edgeDepth<0 then return false end
    -- The same separating axes that establish overlap also give the least
    -- translation out of it. Keep the Boolean footprint unchanged and return
    -- an optional normal pointing away from the obstacle for truck physics.
    local nx,nz=along<0 and 1 or -1,0
    local depth=alongDepth
    if sideDepth<depth then nx,nz=0,side<0 and 1 or -1;depth=sideDepth end
    if edgeDepth<depth then
        local sign=cross<0 and 1 or -1
        nx,nz=sign*dv/length,-sign*du/length
    end
    return true,nx*c-nz*s,nx*s+nz*c
end
F.radius=math.sqrt(F.halfLength^2+F.halfWidth^2)
function F.overlapsTruck(x,z,heading,otherX,otherZ,otherHeading,model,otherModel)
    local aDims,bDims=F.dimensions(model),F.dimensions(otherModel)
    local ac,as=math.cos(heading),math.sin(heading)
    local bc,bs=math.cos(otherHeading),math.sin(otherHeading)
    local dx,dz=otherX-x,otherZ-z
    local bestDepth,bestX,bestZ
    local function separated(ax,az)
        local projected=dx*ax+dz*az
        local separation=math.abs(projected)
        local aRadius=aDims.halfLength*math.abs(ac*ax+as*az)+aDims.halfWidth*math.abs(-as*ax+ac*az)
        local bRadius=bDims.halfLength*math.abs(bc*ax+bs*az)+bDims.halfWidth*math.abs(-bs*ax+bc*az)
        local depth=aRadius+bRadius-separation
        if depth<0 then return true end
        if not bestDepth or depth<bestDepth then
            local sign=projected<0 and 1 or -1
            bestDepth,bestX,bestZ=depth,ax*sign,az*sign
        end
        return false
    end
    if separated(ac,as) or separated(-as,ac) or separated(bc,bs) or separated(-bs,bc) then return false end
    return true,bestX,bestZ
end

-- Sweep a circular actor against the truck's oriented footprint. The bike
-- controller already subdivides travel into short steps; binary search the
-- first overlap in each step to return a stable contact point and normal.
function F.sweepCircle(x,z,nx,nz,radius,truckX,truckZ,heading,model)
    local dims=F.dimensions(model)
    local c,s=math.cos(heading),math.sin(heading)
    local dx,dz=nx-x,nz-z
    local function pointAt(t)
        local px,pz=x+dx*t,z+dz*t
        local ox,oz=px-truckX,pz-truckZ
        local along,side=ox*c+oz*s,-ox*s+oz*c
        local nearAlong=math.max(-dims.halfLength,math.min(dims.halfLength,along))
        local nearSide=math.max(-dims.halfWidth,math.min(dims.halfWidth,side))
        local ex,ez=along-nearAlong,side-nearSide
        return ex*ex+ez*ez<=radius*radius,along,side,nearAlong,nearSide,ex,ez
    end
    local function escapeScore(t)
        local _,along,side,_,_,ex,ez=pointAt(t)
        if math.abs(along)<=dims.halfLength and math.abs(side)<=dims.halfWidth then
            return -math.min(dims.halfLength-math.abs(along),dims.halfWidth-math.abs(side))
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
    elseif dims.halfLength-math.abs(along)<dims.halfWidth-math.abs(side) then
        localX,localZ=along<0 and -1 or 1,0
    else
        localX,localZ=0,side<0 and -1 or 1
    end
    return first,localX*c-localZ*s,localX*s+localZ*c
end

function F.hitsEdges(rects,x,z,c,s,dims)
    dims=dims or dimensionsByModel.box
    local radius=dims.radius or math.sqrt(dims.halfLength^2+dims.halfWidth^2)
    for _,rect in ipairs(rects) do
        if x+radius>=rect.minX and x-radius<=rect.maxX and z+radius>=rect.minZ and z-radius<=rect.maxZ then
            local a=rect.corners[4]
            for _,b in ipairs(rect.corners) do
                local hit,nx,nz=F.overlaps(x,z,c,s,a.x,a.z,b.x,b.z,0,dims)
                if hit then return true,nx,nz end
                a=b
            end
        end
    end
    return false
end
return F
