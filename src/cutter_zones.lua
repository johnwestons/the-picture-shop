local CutterZones = {}

local palletFrames = {
    northwest = 1, north = 1,
    northeast = 2, east = 2,
    southeast = 4, south = 4,
    southwest = 3, west = 3,
}

local signs = {
    northwest = { x = 1, y = 1 },
    north = { x = 0, y = 1 },
    northeast = { x = -1, y = 1 },
    east = { x = -1, y = 0 },
    southeast = { x = -1, y = -1 },
    south = { x = 0, y = -1 },
    southwest = { x = 1, y = -1 },
    west = { x = 1, y = 0 },
}

local directionOrder = {
    northwest = { "northwest", "north", "west", "northeast", "southwest", "east", "south", "southeast" },
    north = { "north", "northeast", "northwest", "east", "west", "southeast", "southwest", "south" },
    northeast = { "northeast", "east", "north", "southeast", "northwest", "south", "west", "southwest" },
    east = { "east", "southeast", "northeast", "south", "north", "southwest", "northwest", "west" },
    southeast = { "southeast", "south", "east", "southwest", "northeast", "west", "north", "northwest" },
    south = { "south", "southwest", "southeast", "west", "east", "northwest", "northeast", "north" },
    southwest = { "southwest", "west", "south", "northwest", "southeast", "north", "east", "northeast" },
    west = { "west", "northwest", "southwest", "north", "south", "northeast", "southeast", "east" },
}

local function cutter(state, config)
    local value = state and state.cutter or {}
    local selected = state and (state._operatingMachineId
        or (state.screen == "machine" and state.machineId))
    if selected then
        for _, item in ipairs(state.machines and state.machines.items or {}) do
            if item.id == selected and item.modelId == "polar_115" and item.world then
                value = item.world
                break
            end
        end
    end
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
    local seen = {}
    local function add(x, y)
        local key = string.format("%.3f,%.3f", x, y)
        if seen[key] then return end
        seen[key] = true
        result[#result + 1] = {
            x = x,
            y = y,
            direction = machine.direction,
            rotation = palletFrames[machine.direction],
        }
    end
    for _, direction in ipairs(directionOrder[machine.direction]) do
        local sign = signs[direction]
        if sign.x == 0 then
            add(machine.x, machine.y + sign.y * offsets[1].x)
            add(machine.x - offsets[1].y, machine.y + sign.y * offsets[1].x)
            add(machine.x + offsets[1].y, machine.y + sign.y * offsets[1].x)
            add(machine.x, machine.y + sign.y * offsets[4].x)
        elseif sign.y == 0 then
            add(machine.x + sign.x * offsets[1].x, machine.y)
            add(machine.x + sign.x * offsets[1].x, machine.y - offsets[1].y)
            add(machine.x + sign.x * offsets[1].x, machine.y + offsets[1].y)
            add(machine.x + sign.x * offsets[4].x, machine.y)
        else
            for _, offset in ipairs(offsets) do
                add(machine.x + sign.x * offset.x, machine.y + sign.y * offset.y)
            end
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
