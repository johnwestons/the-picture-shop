-- Registered bitmap keycaps. The atlas supplies every rim, face and pressed
-- state; only the legends are live so they remain readable at mobile scales.
local Art = {}
local Fonts = require('src.screens.title_fonts')
local atlas, quads
local courier = {}
local regions = {
    number = {{24,114,400,324},{24,474,400,324}},
    functionKey = {{450,114,482,324},{450,474,482,324}},
    enter = {{958,114,842,324},{958,474,842,324}},
}

function Art.font(kind, size)
    if kind ~= 'program' then return Fonts.get(kind, size) end
    if not courier[size] then
        courier[size] = love.graphics.newFont('assets/fonts/CourierPrime-Bold.ttf', size)
    end
    return courier[size]
end

function Art.label(value,x,y,width,size,kind,color,align)
    local g=love.graphics
    g.setFont(Art.font(kind,size));g.setColor(color or {.83,.94,1,1})
    g.printf(tostring(value),x,y,width,align or 'left')
end

function Art.key(rect,label,pressed,hover)
    local g=love.graphics
    if not atlas then
        atlas=g.newImage('assets/generated/cutter-computer-v1/keys.png')
        atlas:setFilter('linear','linear')
        quads={}
        for kind,states in pairs(regions) do
            quads[kind]={}
            for i,r in ipairs(states) do
                quads[kind][i]=g.newQuad(r[1],r[2],r[3],r[4],atlas:getDimensions())
            end
        end
    end
    local kind=rect.width/rect.height>2.4 and 'enter'
        or #label>3 and 'functionKey' or 'number'
    local frame=pressed and 2 or 1
    local source=regions[kind][frame]
    g.setColor(hover and 1 or .92,hover and 1 or .95,1,1)
    g.draw(atlas,quads[kind][frame],rect.x,rect.y,0,rect.width/source[3],rect.height/source[4])
    local size=#label==1 and 26 or #label>3 and 14 or 18
    local font=Art.font('metal',size)
    local y=rect.y+(rect.height-font:getHeight())/2+(pressed and 2 or -1)
    -- Painted/engraved legends follow the face into its recessed state.
    Art.label(label,rect.x+4,y+1,rect.width-8,size,'metal',{.02,.03,.04,.9},'center')
    Art.label(label,rect.x+4,y,rect.width-8,size,'metal',{.94,.96,.90,1},'center')
end
return Art
