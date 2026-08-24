local PalletState = require("src.pallet_state")

local Receiving = {}
local physicalLocations = { warehouse = true, cutter_output = true, on_pallet_jack = true, at_cutter = true }

local function occupant(state, lane, radius, excludedId)
    for _, item in ipairs(PalletState.items(state)) do
        local pallet, world = item.pallet, item.pallet.world
        if pallet.id ~= excludedId and physicalLocations[pallet.location]
            and type(world) == "table" and type(world.x) == "number" and type(world.y) == "number"
        then
            local dx, dy = world.x - lane.x, world.y - lane.y
            if dx * dx + dy * dy <= radius * radius then return item end
        end
    end
end

function Receiving.claim(state, lanes, radius, excludedId)
    if type(lanes) ~= "table" or #lanes == 0 then return nil, "No receiving lanes are configured." end
    radius = math.max(1, tonumber(radius) or 34)
    for index, lane in ipairs(lanes) do
        if not occupant(state, lane, radius, excludedId) then
            return { x = lane.x, y = lane.y, direction = lane.direction or "northwest", lane = index }
        end
    end
    return nil, "Receiving lanes are full. Move a staged pallet away from the marked dock lanes before unloading."
end

function Receiving.snapshot(state, lanes, radius)
    local result = { total = #(lanes or {}), open = 0, lanes = {} }
    radius = math.max(1, tonumber(radius) or 34)
    for index, lane in ipairs(lanes or {}) do
        local item = occupant(state, lane, radius)
        result.lanes[index] = {
            x = lane.x,
            y = lane.y,
            occupied = item ~= nil,
            palletId = item and item.pallet.id or nil,
        }
        if not item then result.open = result.open + 1 end
    end
    return result
end

return Receiving
