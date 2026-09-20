-- Host-only, atomic transfers of existing job/procurement pallets. The rack
-- registry contains no inventory: each pallet remains its sole durable owner.
local Storage = { ROWS = 2, COLUMNS = 5, MAX_RECEIPTS = 128 }
local BAYS = { front_left = true, front_right = true }
local VEHICLES = { pallet_jack = "palletJack", forklift = "forklift" }
local LOCATIONS = { pallet_jack = "on_pallet_jack", forklift = "on_forklift" }
local ACTIONS = { store = true, retrieve = true, stack = true, unstack = true }
local FLOOR = { warehouse = true, cutter_output = true, press_output = true }

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function integer(value, low, high)
    return finite(value) and value == math.floor(value) and value >= (low or 0) and value <= (high or 2147483647)
end
local function token(value)
    return type(value) == "string" and #value > 0 and #value <= 128
        and value:match("^[%w_.%-]+$") ~= nil
end
local function exact(value, fields)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do if not fields[key] then return false end end
    return true
end
local function sequential(value, maximum)
    if type(value) ~= "table" or #value > maximum then return false end
    local count = 0
    for key in pairs(value) do
        if not integer(key, 1, #value) then return false end
        count = count + 1
    end
    return count == #value
end
local function items(state)
    -- Lazy resolution permits PalletState to call this module's validation.
    return require("src.pallet_state").items(state)
end
local function position(world)
    return type(world) == "table" and finite(world.x) and finite(world.y)
end
local function slotKey(rackId, row, column)
    return rackId .. ":" .. row .. ":" .. column
end
local function completedRack(state, rack)
    local bay = state.warehouse and state.warehouse.bays and state.warehouse.bays[rack.bayId]
    return type(bay) == "table" and bay.status == "complete" and bay.optionId == "storage"
end

function Storage.defaultState()
    return { revision = 0, racks = {}, appliedRequests = {} }
end

function Storage.rackDefinition(bayId)
    if not BAYS[bayId] then return nil end
    return { id = bayId .. "-rack", bayId = bayId, revision = 0 }
end

local REQUEST_FIELDS = { requestId=true, action=true, vehicle=true, palletId=true,
    expectedRevision=true, rackId=true, row=true, column=true, supportPalletId=true }
local function validRequest(request)
    if not exact(request, REQUEST_FIELDS) or not token(request.requestId)
        or not ACTIONS[request.action] or not VEHICLES[request.vehicle]
        or not token(request.palletId) or not integer(request.expectedRevision) then return false end
    if request.action == "store" or request.action == "retrieve" then
        return token(request.rackId) and integer(request.row, 1, Storage.ROWS)
            and integer(request.column, 1, Storage.COLUMNS) and request.supportPalletId == nil
    end
    return token(request.supportPalletId) and request.rackId == nil
        and request.row == nil and request.column == nil and request.vehicle == "forklift"
end

local function validRegistry(value)
    if not exact(value, { revision=true, racks=true, appliedRequests=true })
        or not integer(value.revision) or type(value.racks) ~= "table"
        or not sequential(value.appliedRequests, Storage.MAX_RECEIPTS) then
        return false, "Invalid storage registry."
    end
    local bays, count = {}, 0
    for key, rack in pairs(value.racks) do
        if not exact(rack, { id=true, bayId=true, revision=true })
            or not BAYS[rack.bayId] or rack.id ~= rack.bayId .. "-rack" or key ~= rack.id
            or not integer(rack.revision) or rack.revision > value.revision or bays[rack.bayId] then
            return false, "Invalid rack definition."
        end
        count, bays[rack.bayId] = count + 1, true
    end
    if count > 2 then return false, "Too many warehouse racks." end
    local requests, lastRevision = {}, 0
    for _, receipt in ipairs(value.appliedRequests) do
        if not exact(receipt, { playerId=true, request=true, revision=true, code=true })
            or not integer(receipt.playerId, 1, 4) or not validRequest(receipt.request)
            or not integer(receipt.revision, 1) or receipt.revision > value.revision
            or receipt.revision <= lastRevision or receipt.code ~= receipt.request.action
            or receipt.request.expectedRevision ~= receipt.revision - 1 then
            return false, "Invalid storage transfer receipt."
        end
        local key = tostring(receipt.playerId) .. ":" .. receipt.request.requestId
        if requests[key] then return false, "Duplicate storage transfer receipt." end
        requests[key], lastRevision = true, receipt.revision
    end
    return true
end

-- Schema normalization copies valid state, but never repairs malformed paid
-- inventory by silently deleting or teleporting pallets.
function Storage.normalize(value)
    if value == nil then return Storage.defaultState() end
    local valid, reason = validRegistry(value)
    if not valid then return nil, reason end
    return copy(value)
end

function Storage.normalizePlacement(pallet)
    if type(pallet) ~= "table" then return nil, "Invalid pallet." end
    local value = pallet.storage
    if pallet.location == "rack" then
        if not exact(value, { rackId=true, row=true, column=true }) or not token(value.rackId)
            or not integer(value.row, 1, 2) or not integer(value.column, 1, 5) then
            return nil, "Invalid rack placement."
        end
    elseif pallet.location == "stacked" then
        if not exact(value, { supportPalletId=true, level=true })
            or not token(value.supportPalletId) or value.level ~= 2 or value.supportPalletId == pallet.id then
            return nil, "Invalid two-high stack placement."
        end
    elseif value ~= nil then return nil, "Non-stored pallet has storage metadata."
    else return nil end
    return copy(value)
end

function Storage.find(state, palletId)
    for _, item in ipairs(items(state)) do if item.pallet.id == palletId then return item end end
end

function Storage.isSupporting(state, palletId)
    for _, item in ipairs(items(state)) do
        local pallet = item.pallet
        if pallet.location == "stacked" and type(pallet.storage) == "table"
            and pallet.storage.supportPalletId == palletId then return true, pallet.id end
    end
    return false
end

function Storage.slots(state, rackId)
    local result = { {}, {} }
    for _, item in ipairs(items(state)) do
        local pallet, placement = item.pallet, item.pallet.storage
        if pallet.location == "rack" and type(placement) == "table" and placement.rackId == rackId
            and integer(placement.row, 1, 2) and integer(placement.column, 1, 5) then
            result[placement.row][placement.column] = pallet.id
        end
    end
    return result
end

function Storage.validate(state)
    if type(state) ~= "table" then return false, { "A shop state is required." } end
    for _, field in pairs(VEHICLES) do
        if state[field] ~= nil and type(state[field]) ~= "table" then
            return false, { "Invalid vehicle record: " .. field }
        end
    end
    local jack, forklift = state.palletJack, state.forklift
    if jack and forklift and jack.operating and forklift.operating
        and jack.operatorPlayerId ~= nil and jack.operatorPlayerId == forklift.operatorPlayerId then
        return false, { "One worker cannot operate both vehicles." }
    end
    local registry = state.storage or Storage.defaultState()
    local good, reason = validRegistry(registry)
    if not good then return false, { reason } end
    local errors, ids, occupied, supported = {}, {}, {}, {}
    local vehicles = { on_pallet_jack = {}, on_forklift = {} }
    for _, item in ipairs(items(state)) do
        local pallet = item.pallet
        if type(pallet) ~= "table" then return false, { "Invalid pallet record." } end
        if not token(pallet.id) then errors[#errors + 1] = "Pallet has no stable ID."
        elseif ids[pallet.id] then errors[#errors + 1] = "Duplicate pallet ID: " .. pallet.id
        else ids[pallet.id] = pallet end
        local placement, errorMessage = Storage.normalizePlacement(pallet)
        if errorMessage then errors[#errors + 1] = tostring(pallet.id) .. ": " .. errorMessage end
        if placement and pallet.location == "rack" then
            local rack = registry.racks[placement.rackId]
            if not rack or not completedRack(state, rack) then
                errors[#errors + 1] = tostring(pallet.id) .. " references an unavailable rack."
            end
            local key = slotKey(placement.rackId, placement.row, placement.column)
            if occupied[key] then errors[#errors + 1] = "Multiple pallets occupy " .. key end
            occupied[key] = pallet.id
        elseif placement and pallet.location == "stacked" then
            if supported[placement.supportPalletId] then
                errors[#errors + 1] = "Multiple pallets rest on " .. placement.supportPalletId
            end
            supported[placement.supportPalletId] = pallet.id
        end
        if vehicles[pallet.location] then
            vehicles[pallet.location][#vehicles[pallet.location] + 1] = pallet.id
            if not position(pallet.world) then errors[#errors + 1] = tostring(pallet.id) .. " has no vehicle position." end
        end
    end
    for supportId, topId in pairs(supported) do
        local support, top = ids[supportId], ids[topId]
        if not support or not FLOOR[support.location] or not position(support.world) or supported[topId] then
            errors[#errors + 1] = "Stack has a missing/non-floor/cyclic/three-high support: " .. supportId
        elseif not top or not position(top.world) or top.world.x ~= support.world.x or top.world.y ~= support.world.y then
            errors[#errors + 1] = "Stack upper pallet has drifted from its support: " .. tostring(topId)
        end
    end
    for kind, field in pairs(VEHICLES) do
        local vehicle, loads = state[field] or {}, vehicles[LOCATIONS[kind]]
        if #loads > 1 then errors[#errors + 1] = "Multiple pallets claimed by " .. kind end
        if vehicle.carriedPalletId ~= nil then
            local pallet = ids[vehicle.carriedPalletId]
            if not pallet or pallet.location ~= LOCATIONS[kind] or #loads ~= 1 or loads[1] ~= pallet.id then
                errors[#errors + 1] = "Vehicle/pallet ownership mismatch: " .. kind
            end
        elseif #loads > 0 then errors[#errors + 1] = "Pallet has no matching vehicle owner: " .. kind end
    end
    return #errors == 0, errors
end

local function sameRequest(left, right)
    for key in pairs(REQUEST_FIELDS) do if left[key] ~= right[key] then return false end end
    return true
end

local function vehicleFor(state, request, context)
    local vehicle = state[VEHICLES[request.vehicle]]
    if type(vehicle) ~= "table" or not vehicle.operating or vehicle.operatorPlayerId ~= context.playerId then
        return nil, "not_operator"
    end
    if vehicle.moving or not finite(vehicle.x) or not finite(vehicle.y) then return nil, "vehicle_not_stationary" end
    local other = state[request.vehicle == "forklift" and "palletJack" or "forklift"]
    if other and other.operating and other.operatorPlayerId == context.playerId then return nil, "two_vehicles" end
    if request.vehicle == "forklift" then
        if not (state.warehouse and state.warehouse.forkliftOwned == true) or vehicle.owned ~= true then
            return nil, "forklift_not_owned"
        end
        if vehicle.lifting == true then return nil, "lift_in_progress" end
        local required = (request.row == 2 or request.action == "stack" or request.action == "unstack") and 1 or 0
        if not finite(vehicle.forkHeight) or math.abs(vehicle.forkHeight - required) > 0.001
            or (vehicle.targetForkHeight ~= nil and (not finite(vehicle.targetForkHeight)
                or math.abs(vehicle.targetForkHeight - vehicle.forkHeight) > 0.001)) then
            return nil, "wrong_fork_height"
        end
    elseif request.row == 2 then return nil, "forklift_required" end
    return vehicle
end

local function cargoWorld(vehicle)
    return { x=vehicle.x, y=vehicle.y, fromX=vehicle.x, fromY=vehicle.y,
        direction=vehicle.direction or "northwest", spawnProgress=1 }
end

-- The caller derives near/aligned/clear and stacking policy from the current
-- authoritative world. Do not deserialize context from a player's request.
function Storage.apply(state, request, context)
    if type(state) ~= "table" or not validRequest(request)
        or type(context) ~= "table" or not integer(context.playerId, 1, 4) then return false, "invalid_request" end
    local registry = state.storage or Storage.defaultState()
    local registryValid = validRegistry(registry)
    if not registryValid then return false, "invalid_state" end
    for _, receipt in ipairs(registry.appliedRequests) do
        if receipt.playerId == context.playerId and receipt.request.requestId == request.requestId then
            if not sameRequest(receipt.request, request) then return false, "request_conflict" end
            return true, "replayed", copy(receipt)
        end
    end
    if request.expectedRevision ~= registry.revision then return false, "stale_revision" end
    -- Never commit a transfer that would create a registry rejected by saves.
    -- Exact old receipts above remain replayable even after the counter is full.
    if registry.revision >= 2147483647 then return false, "revision_exhausted" end
    local valid = Storage.validate(state)
    if not valid then return false, "invalid_state" end
    if context.near ~= true then return false, "out_of_range" end
    if context.aligned ~= true then return false, "not_aligned" end
    if context.clear ~= true then return false, "blocked" end
    local vehicle, vehicleError = vehicleFor(state, request, context)
    if not vehicle then return false, vehicleError end
    local item = Storage.find(state, request.palletId)
    if not item then return false, "missing_pallet" end
    local pallet, rack, support = item.pallet
    if Storage.isSupporting(state, pallet.id) then return false, "supporting_pallet" end
    local storing = request.action == "store" or request.action == "stack"
    if storing then
        if vehicle.carriedPalletId ~= pallet.id or pallet.location ~= LOCATIONS[request.vehicle] then
            return false, "not_vehicle_cargo"
        end
    elseif vehicle.carriedPalletId ~= nil then return false, "vehicle_loaded" end
    if request.action == "store" or request.action == "retrieve" then
        rack = registry.racks[request.rackId]
        if not rack or not completedRack(state, rack) then return false, "rack_unavailable" end
        local occupant = Storage.slots(state, request.rackId)[request.row][request.column]
        if request.action == "store" and occupant ~= nil then return false, "slot_occupied" end
        if request.action == "retrieve" and (occupant ~= pallet.id or pallet.location ~= "rack") then
            return false, "wrong_slot"
        end
    else
        local supportItem = Storage.find(state, request.supportPalletId)
        support = supportItem and supportItem.pallet
        if not support or support == pallet or not FLOOR[support.location] or not position(support.world) then
            return false, "invalid_support"
        end
        if request.action == "stack" then
            if Storage.isSupporting(state, support.id) then return false, "support_occupied" end
            if context.stackable ~= true then return false, "not_stackable" end
            if context.compatible ~= true then return false, "incompatible_footprint" end
        elseif pallet.location ~= "stacked" or not pallet.storage
            or pallet.storage.supportPalletId ~= support.id or pallet.storage.level ~= 2 then
            return false, "wrong_stack"
        end
    end
    -- All fallible checks occur above. Only ownership/placement fields change;
    -- paper, wraps, print/drying data, quantities and object identity survive.
    if request.action == "store" then
        pallet.location = "rack"
        pallet.storage = { rackId=request.rackId, row=request.row, column=request.column }
        pallet.world, vehicle.carriedPalletId = nil, nil
    elseif request.action == "stack" then
        pallet.location = "stacked"
        pallet.storage = { supportPalletId=support.id, level=2 }
        pallet.world, vehicle.carriedPalletId = copy(support.world), nil
    else
        pallet.location, pallet.storage = LOCATIONS[request.vehicle], nil
        pallet.world, vehicle.carriedPalletId = cargoWorld(vehicle), pallet.id
    end
    vehicle.candidatePalletId = nil
    state.storage = registry
    registry.revision = registry.revision + 1
    if rack then rack.revision = rack.revision + 1 end
    local receipt = { playerId=context.playerId, request=copy(request), revision=registry.revision, code=request.action }
    registry.appliedRequests[#registry.appliedRequests + 1] = receipt
    if #registry.appliedRequests > Storage.MAX_RECEIPTS then table.remove(registry.appliedRequests, 1) end
    return true, request.action, copy(receipt)
end

for action in pairs(ACTIONS) do
    local operation = action
    Storage[operation] = function(state, request, context)
        if type(request) ~= "table" or (request.action ~= nil and request.action ~= operation) then
            return false, "invalid_request"
        end
        local intent = copy(request)
        intent.action = operation
        return Storage.apply(state, intent, context)
    end
end

return Storage
