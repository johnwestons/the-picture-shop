-- Cached setup-map topography sampled from the exact frozen playthrough world.
local Town=require('src.commute.town')
local Preview={RESOLUTION=128}
function Preview.sample(town,resolution)
    resolution=resolution or Preview.RESOLUTION
    local world=Town.world(town);local heights={};local high=0
    for z=0,resolution-1 do
        for x=0,resolution-1 do
            local h=world:height((x+.5)*town.size/resolution,(z+.5)*town.size/resolution)
            heights[z*resolution+x+1]=h;high=math.max(high,h)
        end
    end
    return {resolution=resolution,size=town.size,heights=heights,high=high,bounds=town.bounds}
end
function Preview.color(samples,x,z)
    local n=samples.resolution;local cell=samples.size/n
    local function height(px,pz)
        return samples.heights[math.max(0,math.min(n-1,pz))*n+math.max(0,math.min(n-1,px))+1]
    end
    local h=height(x,z);local r,g,b
    if h<=0 then r,g,b=.12,.32,.42
    else
        local t=math.min(1,h/math.max(1,samples.high))
        r,g,b=.22+t*.38,.40+t*.16,.28+t*.12
        if h<1 then r,g,b=.38,.46,.34 end
        local dx,dz=(height(x+1,z)-height(x-1,z))/(cell*2),(height(x,z+1)-height(x,z-1))/(cell*2)
        local light=.74+.26*(1-dx*.55-dz*.45)/math.sqrt(1+dx*dx+dz*dz)
        if math.floor(h/2)~=math.floor(height(x+1,z)/2)
            or math.floor(h/2)~=math.floor(height(x,z+1)/2) then light=light*.84 end
        r,g,b=r*light,g*light,b*light
    end
    local px,pz=(x+.5)*cell,(z+.5)*cell;local bounds=samples.bounds
    if px<bounds.x0 or px>bounds.x1 or pz<bounds.z0 or pz>bounds.z1 then r,g,b=r*.48,g*.48,b*.48 end
    return r,g,b,1
end
function Preview.image(samples)
    local n=samples.resolution;local data=love.image.newImageData(n,n)
    data:mapPixel(function(x,z)return Preview.color(samples,x,z) end)
    local image=love.graphics.newImage(data);data:release();image:setFilter('linear','linear')
    return image
end
return Preview
