-- Registered bitmap keycaps. The atlas supplies every rim, face and pressed
-- state; only the legends are live so they remain readable at mobile scales.
local Art = {}
local Fonts = require('src.screens.title_fonts')
local BladeProfiles = require('src.machine.cutter.blade_profiles')
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

function Art.bladeSharpness(item)
    local cutter = item and item.maintenance and item.maintenance.cutter
    if not cutter or cutter.bladeRemoved then return nil end
    return item.variables and item.variables.bladeSharpness
end

function Art.bladeWarning(sharpness, x, y, scale)
    if sharpness == nil or sharpness > BladeProfiles.DULL_THRESHOLD then return end
    local g = love.graphics
    g.push('all')
    g.translate(x, y)
    g.scale(scale)
    g.setColor(.35, .055, .07, 1)
    g.rectangle('fill', 0, 0, 24, 19, 3)
    g.setColor(1, .29, .25, 1)
    g.polygon('fill', 3, 5, 21, 5, 21, 9, 4, 15)
    g.setColor(.35, .055, .07, 1)
    for _, boltX in ipairs({7, 12, 17}) do g.circle('fill', boltX, 7, 1, 8) end
    g.pop()
end

-- Coordinates are in the operator-console sprite's 768 x 512 space.
function Art.machineReadout(machine, unit, sharpness)
    local g = love.graphics
    local paper = machine.paper
    local number = machine.programIndex or 1
    local cut = paper and paper.cuts and paper.cuts[number]
    if machine.step == 'idle' or machine.step == 'finished' then cut = nil end
    unit = unit or 'in'
    local factor = unit == 'mm' and 25.4 or 1
    local modeColor = machine.autoMode and {.43, 1, .74, 1} or {.65, .84, 1, 1}
    g.setColor(.025, .11, .20, 1)
    g.rectangle('fill', 277, 32, 152, 79, 2)
    g.setColor(.10, .22, .34, 1)
    g.rectangle('fill', 278, 33, 150, 23, 2)
    Art.label(cut and string.format('CUT %d/%d', number, #paper.cuts) or 'CUT --',
        284, 37, 68, 13, 'program')
    Art.label(machine.autoMode and 'AUTO' or 'MANUAL', 351, 37, 55, 13, 'program', modeColor)
    Art.bladeWarning(sharpness, 407, 37, .75)
    Art.label('TARGET', 284, 62, 55, 12, 'program', {.65, .84, 1, 1})
    Art.label(cut and string.format('%.2f %s', cut.gauge * factor, unit) or '--',
        339, 61, 84, 14, 'program', nil, 'right')
    Art.label('GAUGE', 284, 85, 55, 12, 'program', {.65, .84, 1, 1})
    Art.label(string.format('%.2f %s', (machine.gauge or 0) * factor, unit),
        339, 83, 84, 14, 'program', {.83, 1, .88, 1}, 'right')
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
