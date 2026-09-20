-- Closed wire intent: geometry, custody, money and player identity are always
-- recomputed by the host world, never accepted from a remote menu.
local Intent = {}
local shapes = {
    operate = {}, release = {}, drop = {},
    set_height = { height = true }, pickup = { palletId = true },
    store = { requestId = true, expectedRevision = true, vehicle = true,
        palletId = true, rackId = true, row = true, column = true },
    retrieve = { requestId = true, expectedRevision = true, vehicle = true,
        palletId = true, rackId = true, row = true, column = true },
    stack = { requestId = true, expectedRevision = true, vehicle = true,
        palletId = true, supportPalletId = true },
    unstack = { requestId = true, expectedRevision = true, vehicle = true,
        palletId = true, supportPalletId = true },
}
local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value)
        and value >= low and value <= high
end
local function token(value)
    return type(value) == "string" and #value > 0 and #value <= 64
        and value:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$") ~= nil
end
function Intent.normalize(value)
    if type(value) ~= "table" or not shapes[value.kind] then
        return nil, "Unknown warehouse action."
    end
    local allowed, result = shapes[value.kind], { kind = value.kind }
    for key in pairs(value) do
        if key ~= "kind" and not allowed[key] then
            return nil, "Unexpected warehouse action field: " .. tostring(key)
        end
    end
    for key in pairs(allowed) do
        local item = value[key]
        local valid
        if key == "height" then valid = item == 0 or item == 0.08 or item == 1
        elseif key == "row" then valid = integer(item, 1, 2)
        elseif key == "column" then valid = integer(item, 1, 5)
        elseif key == "expectedRevision" then valid = integer(item, 0, 2147483647)
        elseif key == "vehicle" then valid = item == "forklift" or item == "pallet_jack"
        else valid = token(item) end
        if not valid then return nil, "Invalid warehouse action field: " .. key end
        result[key] = item
    end
    if (result.kind == "stack" or result.kind == "unstack") and
        (result.vehicle ~= "forklift" or result.palletId == result.supportPalletId) then
        return nil, "Floor stacks require a forklift and two different pallets."
    end
    return result
end
return Intent
