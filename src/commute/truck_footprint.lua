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
