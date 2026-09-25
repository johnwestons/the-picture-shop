local PalletState = {}
local Config = require("src.config")
local CutterZones = require("src.cutter_zones")
local PalletStorage = require("src.pallet_storage")
local function ownerId(state, modelId)
    local selected = state._operatingMachineId
        or ((state.screen == "machine" or state.screen == "press") and state.machineId)
    local first
    for _, item in ipairs(state.machines and state.machines.items or {}) do
        if item.modelId == modelId and item.status == "installed" then
            if item.id == selected then return item.id end
            first = first or item.id
        end
    end
    return first
end

local function palletOwner(pallet, location, state)
    local field = location == "at_cutter" and "cutterMachineId" or "pressMachineId"
    local model = location == "at_cutter" and "polar_115" or "heidelberg_10x15"
    if pallet[field] then return pallet[field] end
    for _, item in ipairs(state.machines and state.machines.items or {}) do
        if item.modelId == model and item.status == "installed" then return item.id end
    end
end

local allowedLocations = {
    awaiting_delivery = { warehouse = true, none = true },
    warehouse = { on_pallet_jack = true, on_forklift = true, at_cutter = true, at_press = true, outbound_truck = true, none = true },
    on_pallet_jack = { warehouse = true },
    on_forklift = { warehouse = true },
    -- Rack/stack transfers are atomic multi-owner operations in PalletStorage.
    -- Recognize their canonical locations without offering a bypass here.
    rack = {},
    stacked = {},
    at_cutter = { cutter_output = true, warehouse = true, none = true },
    cutter_output = { on_pallet_jack = true, on_forklift = true, warehouse = true, at_press = true, outbound_truck = true, none = true },
    at_press = { press_output = true, warehouse = true },
    press_output = { on_pallet_jack = true, on_forklift = true, warehouse = true, at_press = true, outbound_truck = true, none = true },
    outbound_truck = { none = true },
    none = {},
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function allPallets(state)
    local result = {}
    for _, job in ipairs(state and state.jobs and state.jobs.active or {}) do
        for _, pallet in ipairs(job.pallets or {}) do
            result[#result + 1] = { job = job, pallet = pallet, vendor = false }
        end
    end
    for _, order in ipairs(state and state.procurement and state.procurement.orders or {}) do
        for _, pallet in ipairs(order.pallets or {}) do
            result[#result + 1] = { job = order, pallet = pallet, vendor = true }
        end
    end
    return result
end

function PalletState.items(state) return allPallets(state) end

local function validWorld(world)
    return type(world) == "table" and type(world.x) == "number" and type(world.y) == "number"
end

function PalletState.find(state, palletId)
    if type(palletId) ~= "string" then return nil end
    for _, item in ipairs(allPallets(state)) do
        if item.pallet.id == palletId then return item end
    end
end

function PalletState.validate(state)
    local errors, ids, atCutter, atPress, onJack = {}, {}, {}, {}, {}
    local jack = state and state.palletJack or {}
    for _, item in ipairs(allPallets(state)) do
        local pallet = item.pallet
        if type(pallet.id) ~= "string" or pallet.id == "" then
            errors[#errors + 1] = "pallet without a stable id"
        elseif ids[pallet.id] then
            errors[#errors + 1] = "duplicate pallet id " .. pallet.id
        else
            ids[pallet.id] = pallet
        end
        if not allowedLocations[pallet.location] then
            errors[#errors + 1] = tostring(pallet.id) .. " has invalid location " .. tostring(pallet.location)
        end
        if pallet.location == "warehouse" or pallet.location == "cutter_output"
            or pallet.location == "on_pallet_jack" or pallet.location == "at_cutter"
            or pallet.location == "at_press" or pallet.location == "press_output"
            or pallet.location == "on_forklift" or pallet.location == "stacked"
        then
            if not validWorld(pallet.world) then
                errors[#errors + 1] = tostring(pallet.id) .. " has no physical floor position"
            end
        end
        if pallet.location == "at_cutter" then
            local owner = palletOwner(pallet, "at_cutter", state) or "missing"
            atCutter[owner] = (atCutter[owner] or 0) + 1
        end
        if pallet.location == "at_press" then
            local owner = palletOwner(pallet, "at_press", state) or "missing"
            atPress[owner] = (atPress[owner] or 0) + 1
        end
        if pallet.location == "on_pallet_jack" then onJack[#onJack + 1] = pallet end
    end
    for _, count in pairs(atCutter) do
        if count > 1 then errors[#errors + 1] = "more than one pallet is owned by the cutter" end
    end
    for _, count in pairs(atPress) do
        if count > 1 then errors[#errors + 1] = "more than one pallet is owned by the Windmill" end
    end
    if #onJack > 1 then errors[#errors + 1] = "more than one pallet is owned by the pallet jack" end
    if jack.carriedPalletId then
        local carried = ids[jack.carriedPalletId]
        if not carried then
            errors[#errors + 1] = "pallet jack references missing pallet " .. tostring(jack.carriedPalletId)
        elseif carried.location ~= "on_pallet_jack" then
            errors[#errors + 1] = tostring(carried.id) .. " is claimed by the jack but located at " .. tostring(carried.location)
        end
    elseif #onJack > 0 then
        errors[#errors + 1] = tostring(onJack[1].id) .. " is on the jack but the jack owns nothing"
    end
    if #onJack == 1 and jack.carriedPalletId ~= onJack[1].id then
        errors[#errors + 1] = tostring(onJack[1].id) .. " does not match the jack ownership id"
    end
    local storedValid, storedErrors = PalletStorage.validate(state)
    if not storedValid then
        for _, reason in ipairs(storedErrors or {}) do errors[#errors + 1] = reason end
    end
    return #errors == 0, errors
end

function PalletState.reconcile(state)
    if type(state) ~= "table" then return false end
    local jackSeat, forkliftSeat = state.palletJack, state.forklift
    if type(jackSeat) == "table" and type(forkliftSeat) == "table"
        and jackSeat.operating == true and forkliftSeat.operating == true
        and jackSeat.operatorPlayerId ~= nil and jackSeat.operatorPlayerId == forkliftSeat.operatorPlayerId then
        return false, { "One worker cannot operate both warehouse vehicles." }
    end
    -- New storage/vehicle ownership is never repaired by changing locations.
    -- In particular a stale jack claim must not steal a rack or forklift load.
    local strictStorage = state.forklift and state.forklift.carriedPalletId ~= nil
    for _, item in ipairs(allPallets(state)) do
        local pallet = item.pallet
        if pallet.location == "rack" or pallet.location == "stacked"
            or pallet.location == "on_forklift" or pallet.storage ~= nil then strictStorage = true end
    end
    if strictStorage then return PalletState.validate(state) end
    state.palletJack = type(state.palletJack) == "table" and state.palletJack or {}
    local jack, atCutter, atPress, onJack = state.palletJack, {}, {}, {}
    for _, item in ipairs(allPallets(state)) do
        local pallet = item.pallet
        if pallet.location == "at_cutter" then atCutter[#atCutter + 1] = pallet end
        if pallet.location == "at_press" then atPress[#atPress + 1] = pallet end
        if pallet.location == "on_pallet_jack" then onJack[#onJack + 1] = pallet end
    end

    local seenCutter, seenPress = {}, {}
    for _, pallet in ipairs(atCutter) do
        local owner = palletOwner(pallet, "at_cutter", state) or "missing"
        if seenCutter[owner] then pallet.location = "warehouse" else seenCutter[owner] = true end
    end
    for _, pallet in ipairs(atPress) do
        local owner = palletOwner(pallet, "at_press", state) or "missing"
        if seenPress[owner] then pallet.location = "warehouse" else seenPress[owner] = true end
    end
    local claimed = PalletState.find(state, jack.carriedPalletId)
    if claimed and claimed.pallet.location == "at_cutter" then
        jack.carriedPalletId = nil
    elseif claimed then
        claimed.pallet.location = "on_pallet_jack"
    elseif jack.carriedPalletId then
        jack.carriedPalletId = nil
    end

    onJack = {}
    for _, item in ipairs(allPallets(state)) do
        if item.pallet.location == "on_pallet_jack" then onJack[#onJack + 1] = item.pallet end
    end
    if not jack.carriedPalletId and onJack[1] then jack.carriedPalletId = onJack[1].id end
    for index = 1, #onJack do
        if onJack[index].id ~= jack.carriedPalletId then onJack[index].location = "warehouse" end
    end
    return PalletState.validate(state)
end

local function nearCutter(state, pallet, radius)
    return CutterZones.inInputZone(state, pallet, Config.cutterPlacement, radius)
end

function PalletState.cutterCandidates(state, radius)
    local owned, staged = {}, {}
    for _, item in ipairs(allPallets(state)) do
        local pallet, paper = item.pallet, item.pallet.paper
        if not item.vendor and paper then
            local candidate = { job = item.job, pallet = pallet, paper = paper }
            if pallet.location == "at_cutter"
                and palletOwner(pallet, "at_cutter", state) == ownerId(state, "polar_115") then
                owned[#owned + 1] = candidate
            elseif paper.status ~= "complete" and pallet.location == "warehouse"
                and nearCutter(state, pallet, radius)
            then
                candidate.inputDistance = CutterZones.inputDistanceSquared(
                    state, pallet, Config.cutterPlacement)
                staged[#staged + 1] = candidate
            end
        end
    end
    table.sort(staged, function(left, right)
        if left.inputDistance == right.inputDistance then return left.pallet.id < right.pallet.id end
        return left.inputDistance < right.inputDistance
    end)
    local result = {}
    for _, candidate in ipairs(owned) do result[#result + 1] = candidate end
    for _, candidate in ipairs(staged) do result[#result + 1] = candidate end
    return result
end

function PalletState.hasUnfinishedCustomerPaper(state)
    for _, item in ipairs(allPallets(state)) do
        if not item.vendor and item.pallet.paper and item.pallet.paper.status ~= "complete"
            and item.pallet.location ~= "awaiting_delivery" and item.pallet.location ~= "none"
        then
            return true
        end
    end
    return false
end

function PalletState.transitionDetached(pallet, target, options)
    options = options or {}
    if type(pallet) ~= "table" then return false, "pallet is required" end
    local source = pallet.location
    if source == "on_forklift" or target == "on_forklift" then
        return false, "forklift transfers require the authoritative shop state"
    end
    if not (allowedLocations[source] and allowedLocations[source][target]) then
        return false, string.format("cannot move pallet from %s to %s", tostring(source), tostring(target))
    end
    pallet.location = target
    if options.status ~= nil then pallet.status = options.status end
    if options.world ~= nil then pallet.world = copy(options.world) end
    if target == "none" and options.keepWorld ~= true then pallet.world = nil end
    return true, pallet
end

function PalletState.transition(state, pallet, target, options)
    options = options or {}
    if type(state) ~= "table" or type(pallet) ~= "table" then return false, "state and pallet are required" end
    local source = pallet.location
    if not (allowedLocations[source] and allowedLocations[source][target]) then
        return false, string.format("cannot move pallet from %s to %s", tostring(source), tostring(target))
    end

    local jack = state.palletJack or {}
    local forklift = state.forklift or {}
    if PalletStorage.isSupporting(state, pallet.id) then
        return false, "remove the upper pallet before moving its support"
    end
    if target == "on_pallet_jack" and jack.carriedPalletId then return false, "pallet jack is already carrying a pallet" end
    if source == "on_pallet_jack" and jack.carriedPalletId ~= pallet.id then
        return false, "pallet jack does not own this pallet"
    end
    if target == "on_forklift" then
        if forklift.owned ~= true or not state.warehouse or state.warehouse.forkliftOwned ~= true then
            return false, "a purchased forklift is required"
        end
        if forklift.carriedPalletId then return false, "forklift is already carrying a pallet" end
    end
    if source == "on_forklift" and forklift.carriedPalletId ~= pallet.id then
        return false, "forklift does not own this pallet"
    end
    if target == "at_cutter" then
        local radius = options.cutterRadius or Config.cutterPlacement.palletInputZoneRadius
        if source ~= "warehouse" or not nearCutter(state, pallet, radius) then
            return false, "stage the pallet on clear floor beside the cutter"
        end
        for _, item in ipairs(allPallets(state)) do
            if item.pallet ~= pallet and item.pallet.location == "at_cutter"
                and palletOwner(item.pallet, "at_cutter", state) == ownerId(state, "polar_115") then
                return false, "the cutter already owns another pallet"
            end
        end
    end
    if target == "at_press" then
        if source ~= "warehouse" and source ~= "cutter_output" and source ~= "press_output" then
            return false, "stage the pallet on the warehouse floor before press loading"
        end
        for _, item in ipairs(allPallets(state)) do
            if item.pallet ~= pallet and item.pallet.location == "at_press"
                and palletOwner(item.pallet, "at_press", state) == ownerId(state, "heidelberg_10x15") then
                return false, "the Windmill already owns another pallet"
            end
        end
    end

    local previous = {
        location = pallet.location,
        status = pallet.status,
        world = copy(pallet.world),
        cutterMachineId = pallet.cutterMachineId,
        pressMachineId = pallet.pressMachineId,
        carriedPalletId = jack.carriedPalletId,
        forkliftCarriedPalletId = forklift.carriedPalletId,
    }
    pallet.location = target
    if target == "at_cutter" then pallet.cutterMachineId = ownerId(state, "polar_115") end
    if target == "at_press" then pallet.pressMachineId = ownerId(state, "heidelberg_10x15") end
    if options.status ~= nil then pallet.status = options.status end
    if options.world ~= nil then pallet.world = copy(options.world) end
    if target == "on_pallet_jack" then jack.carriedPalletId = pallet.id end
    if source == "on_pallet_jack" then jack.carriedPalletId = nil end
    if target == "on_forklift" then forklift.carriedPalletId = pallet.id end
    if source == "on_forklift" then forklift.carriedPalletId = nil end
    if target == "outbound_truck" then pallet.world = nil end
    if target == "none" and options.keepWorld ~= true then pallet.world = nil end

    local valid, errors = PalletState.validate(state)
    if not valid then
        pallet.location, pallet.status, pallet.world = previous.location, previous.status, previous.world
        pallet.cutterMachineId, pallet.pressMachineId = previous.cutterMachineId, previous.pressMachineId
        jack.carriedPalletId = previous.carriedPalletId
        forklift.carriedPalletId = previous.forkliftCarriedPalletId
        return false, table.concat(errors, "; ")
    end
    return true, pallet
end

return PalletState
