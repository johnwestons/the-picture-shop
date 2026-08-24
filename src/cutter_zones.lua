local CutterZones = {}

local directionFrames = { northwest = 1, northeast = 2, southwest = 3, southeast = 4 }

local signs = {
    northwest = { x = 1, y = 1 },
    northeast = { x = -1, y = 1 },
    southwest = { x = 1, y = -1 },
    southeast = { x = -1, y = -1 },
}

local directionOrder = {
    northwest = { "northwest", "northeast", "southwest", "southeast" },
    northeast = { "northeast", "northwest", "southeast", "southwest" },
    southwest = { "southwest", "southeast", "northwest", "northeast" },
    southeast = { "southeast", "southwest", "northeast", "northwest" },
}

local function cutter(state, config)
    local value = state and state.cutter or {}
    return {
        x = type(value.x) == "number" and value.x or config.spawnX,
        y = type(value.y) == "number" and value.y or config.spawnY,
        direction = signs[value.direction] and value.direction or config.defaultDirection or "northwest",
    }
end

function CutterZones.inputAnchor(state, config)
    local machine = cutter(state, config)
    local sign = signs[machine.direction]
    return machine.x + sign.x * (config.palletInputOffsetX or 78),
        machine.y + sign.y * (config.palletInputOffsetY or 38)
end

function CutterZones.inputDistanceSquared(state, pallet, config)
    local world = pallet and pallet.world
    if type(world) ~= "table" or type(world.x) ~= "number" or type(world.y) ~= "number" then
        return math.huge
    end
    local anchorX, anchorY = CutterZones.inputAnchor(state, config)
    local dx, dy = world.x - anchorX, world.y - anchorY
    return dx * dx + dy * dy
end

function CutterZones.inInputZone(state, pallet, config, radius)
    radius = math.max(1, tonumber(radius) or config.palletInputZoneRadius or 62)
    return CutterZones.inputDistanceSquared(state, pallet, config) <= radius * radius
end

function CutterZones.outputCandidates(state, config)
    local machine = cutter(state, config)
    local result = {}
    local offsets = {
        { x = config.palletOutputOffsetX or 96, y = config.palletOutputOffsetY or 72 },
        { x = config.palletOutputSecondX or 164, y = config.palletOutputOffsetY or 72 },
        { x = config.palletOutputOffsetX or 96, y = config.palletOutputSecondY or 124 },
        { x = config.palletOutputSecondX or 164, y = config.palletOutputSecondY or 124 },
    }
    for _, direction in ipairs(directionOrder[machine.direction]) do
        local sign = signs[direction]
        for _, offset in ipairs(offsets) do
            result[#result + 1] = {
                x = machine.x + sign.x * offset.x,
                y = machine.y + sign.y * offset.y,
                direction = machine.direction,
                rotation = directionFrames[machine.direction],
            }
        end
    end
    return result
end

function CutterZones.findOutput(state, config, isClear)
    for _, candidate in ipairs(CutterZones.outputCandidates(state, config)) do
        if isClear(candidate.x, candidate.y) then return candidate end
    end
    return nil, "No clear cutter output zone is available. Move pallets or equipment away from the cutter."
end

return CutterZones
