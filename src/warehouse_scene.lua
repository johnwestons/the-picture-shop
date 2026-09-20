-- A top-only, non-destructive registration of the taller warehouse architecture.
-- The live base below its roof silhouette stays byte-for-byte the existing image:
-- dock animation, lounge foregrounds, walk mask and gameplay anchors keep their
-- established registration. The source candidate's different floor/furniture
-- geometry must NOT be stretched over that live floor as a drop-in replacement.
local Config = require("src.config")
local Scene = {}
local mesh

-- Native source x -> established 1536-wide background x. Architectural posts,
-- not actors or equipment, are registered by these vertical strip boundaries.
local STRIPS = {
    { 0, 0 }, { 578, 500 }, { 688, 664 },
    { 822, 766 }, { 1090, 1040 }, { 1672, 1536 },
}
-- Existing top silhouette, measured in the ORIGINAL background's coordinates.
-- The replacement underlaps the roof cap a few pixels; drawing the original
-- last covers the underlap, preventing alpha slivers at fractional zoom.
local ROOF = {
    { 0, 202 }, { 500, 27 }, { 663, 99 }, { 762, 43 },
    { 992, 139 }, { 1040, 104 }, { 1536, 286 },
}
local WIDTH, HEIGHT = 1536, 1024
local SOURCE_WIDTH, SOURCE_HEIGHT = 1672, 941
local TOP_SAMPLE_HEIGHT = 320

function Scene.registration()
    local strips, roof = {}, {}
    for i, point in ipairs(STRIPS) do strips[i] = { sourceX=point[1], legacyX=point[2] } end
    for i, point in ipairs(ROOF) do roof[i] = { x=point[1], y=point[2] } end
    return {
        sourceWidth=SOURCE_WIDTH, sourceHeight=SOURCE_HEIGHT,
        legacyWidth=WIDTH, legacyHeight=HEIGHT, strips=strips, roof=roof,
        topOnly=true, preservesGameplayMask=true,
    }
end

function Scene.worldPoint(legacyX, legacyY)
    return legacyX * Config.baseWidth / WIDTH, legacyY * Config.baseHeight / HEIGHT
end

function Scene.sourcePoint(sourceX, sourceY)
    if type(sourceX)~="number" or type(sourceY)~="number"
        or sourceX<0 or sourceX>SOURCE_WIDTH or sourceY<0 or sourceY>TOP_SAMPLE_HEIGHT then return nil end
    for index=1,#STRIPS-1 do
        local a,b=STRIPS[index],STRIPS[index+1]
        if sourceX<=b[1] then
            local t=(sourceX-a[1])/(b[1]-a[1])
            return Scene.worldPoint(a[2]+(b[2]-a[2])*t,sourceY)
        end
    end
end

function Scene.topContains(x,y)
    if type(x)~="number" or type(y)~="number" or x<0 or x>Config.baseWidth or y<0 then return false end
    local lx,ly=x*WIDTH/Config.baseWidth,y*HEIGHT/Config.baseHeight
    for index=1,#ROOF-1 do
        local a,b=ROOF[index],ROOF[index+1]
        if lx<=b[1] then
            local t=(lx-a[1])/(b[1]-a[1])
            return ly<=a[2]+(b[2]-a[2])*t
        end
    end
    return false
end

local function vertices()
    local result={}
    local function vertex(sourceX,y)
        local x,wy=Scene.sourcePoint(sourceX,y)
        return {x,wy,sourceX/SOURCE_WIDTH,y/SOURCE_HEIGHT,1,1,1,1}
    end
    for index=1,#STRIPS-1 do
        local a,b=STRIPS[index][1],STRIPS[index+1][1]
        local tl,tr,bl,br=vertex(a,0),vertex(b,0),vertex(a,TOP_SAMPLE_HEIGHT),vertex(b,TOP_SAMPLE_HEIGHT)
        for _,point in ipairs({tl,tr,br,tl,br,bl}) do result[#result+1]=point end
    end
    return result
end

function Scene.drawArchitecture(assets)
    if not Config.warehouseScene or not Config.warehouseScene.enabled then return false end
    local image=assets.get("warehouseArchitecture")
    if not image then return false end
    if not mesh then mesh=love.graphics.newMesh(vertices(),"triangles","static") end
    mesh:setTexture(image)
    local outline={0,0,Config.baseWidth,0}
    for index=#ROOF,1,-1 do
        local x,y=Scene.worldPoint(ROOF[index][1],ROOF[index][2])
        outline[#outline+1]=x;outline[#outline+1]=y
    end
    love.graphics.stencil(function() love.graphics.polygon("fill",unpack(outline)) end,"replace",1)
    love.graphics.setStencilTest("greater",0)
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(mesh)
    love.graphics.setStencilTest()
    return true
end

return Scene
