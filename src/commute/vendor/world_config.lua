-- Area is nominal circular land area, not the square including ocean corners.
local M=require('src.commute.vendor.mathx')
local Config={AREA_KM2=1.5,VERSION=13,HEIGHT_LIMIT=84,PATCH=16,COARSE=8,PROP_CELL=4,
    MAX_PATCHES=96,MAX_HEIGHT_TILES=128,MAX_RENDER_CHUNKS=256,MESH_BYTES=8*1024*1024}
function Config.new(area)
    area=area or Config.AREA_KM2
    assert(M.finite(area) and area>=.02 and area<=4,'Island area must be between .02 and 4 km2')
    local radius=math.sqrt(area*1000000/math.pi)
    -- Area describes the approximate land budget, not a circular boundary.
    -- Ocean padding allows long peninsulas and elongated seeded silhouettes.
    local size=math.ceil((radius*3.80+32)/32)*32
    return {streamed=true,areaKm2=area,radius=radius,size=size,center=size/2}
end
return Config
