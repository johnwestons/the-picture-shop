-- Authored building footprints. Sprite scenery and physical foundations share
-- this data; apartment exterior artwork can join this catalog later.
local M=require('src.commute.vendor.mathx')
local Sites={}
Sites.warehouse={id='warehouse',x=96.4,z=373.4,h=4.5,minX=90.4,maxX=102.4,minZ=370.8,maxZ=376,
    door={x=100,z=377,h=4.5},threshold={x=100,z=376,h=4.5}}
Sites.all={Sites.warehouse}
function Sites.distance(site,x,z)
    return M.length(math.max(site.minX-x,0,x-site.maxX),math.max(site.minZ-z,0,z-site.maxZ))
end
function Sites.blocked(x,z)
    for _,site in ipairs(Sites.all) do
        if x>=site.minX and x<=site.maxX and z>=site.minZ and z<=site.maxZ then return true end
    end
    return false
end
function Sites.grade(height,x,z)
    for _,site in ipairs(Sites.all) do
        local distance=Sites.distance(site,x,z)
        if distance<2 then height=M.lerp(site.h,height,M.smooth(distance/2)) end
    end
    return height
end
function Sites.vegetationAllowed(x,z)
    for _,site in ipairs(Sites.all) do if Sites.distance(site,x,z)<3 then return false end end
    return true
end
return Sites
