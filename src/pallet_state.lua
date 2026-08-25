local PalletState = {}
local Config = require("src.config")
local CutterZones = require("src.cutter_zones")

local allowedLocations = {
    awaiting_delivery = { warehouse = true, none = true },
    warehouse = { on_pallet_jack = true, at_cutter = true, at_press = true, outbound_truck = true, none = true },
    on_pallet_jack = { warehouse = true },
    at_cutter = { cutter_output = true, warehouse = true },
    cutter_output = { on_pallet_jack = true, warehouse = true, at_press = true, outbound_truck = true, none = true },
    at_press = { press_output = true, warehouse = true },
    press_output = { on_pallet_jack = true, warehouse = true, at_press = true, outbound_truck = true, none = true },
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
    local errors, ids, atCutter, atPress, onJack = {}, {}, 0, 0, {}
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
        then
            if not validWorld(pallet.world) then
                errors[#errors + 1] = tostring(pallet.id) .. " has no physical floor position"
            end
        end
        if pallet.location == "at_cutter" then atCutter = atCutter + 1 end
        if pallet.location == "at_press" then atPress = atPress + 1 end
        if pallet.location == "on_pallet_jack" then onJack[#onJack + 1] = pallet end
    end
    if atCutter > 1 then errors[#errors + 1] = "more than one pallet is owned by the cutter" end
    if atPress > 1 then errors[#errors + 1] = "more than one pallet is owned by the Windmill" end
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
    return #errors == 0, errors
end

function PalletState.reconcile(state)
    if type(state) ~= "table" then return false end
    state.palletJack = type(state.palletJack) == "table" and state.palletJack or {}
    local jack, atCutter, atPress, onJack = state.palletJack, {}, {}, {}
    for _, item in ipairs(allPallets(state)) do
        local pallet = item.pallet
        if pallet.location == "at_cutter" then atCutter[#atCutter + 1] = pallet end
        if pallet.location == "at_press" then atPress[#atPress + 1] = pallet end
        if pallet.location == "on_pallet_jack" then onJack[#onJack + 1] = pallet end
    end

    for index = 2, #atCutter do atCutter[index].location = "warehouse" end
    for index = 2, #atPress do atPress[index].location = "warehouse" end
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
            if pallet.location == "at_cutter" then
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
    if target == "on_pallet_jack" and jack.carriedPalletId then return false, "pallet jack is already carrying a pallet" end
    if source == "on_pallet_jack" and jack.carriedPalletId ~= pallet.id then
        return false, "pallet jack does not own this pallet"
    end
    if target == "at_cutter" then
        local radius = options.cutterRadius or Config.cutterPlacement.palletInputZoneRadius
        if source ~= "warehouse" or not nearCutter(state, pallet, radius) then
            return false, "stage the pallet on clear floor beside the cutter"
        end
        for _, item in ipairs(allPallets(state)) do
            if item.pallet ~= pallet and item.pallet.location == "at_cutter" then
                return false, "the cutter already owns another pallet"
            end
        end
    end
    if target == "at_press" then
        if source ~= "warehouse" and source ~= "cutter_output" and source ~= "press_output" then
            return false, "stage the pallet on the warehouse floor before press loading"
        end
        for _, item in ipairs(allPallets(state)) do
            if item.pallet ~= pallet and item.pallet.location == "at_press" then
                return false, "the Windmill already owns another pallet"
            end
        end
    end

    local previous = {
        location = pallet.location,
        status = pallet.status,
        world = copy(pallet.world),
        carriedPalletId = jack.carriedPalletId,
    }
    pallet.location = target
    if options.status ~= nil then pallet.status = options.status end
    if options.world ~= nil then pallet.world = copy(options.world) end
    if target == "on_pallet_jack" then jack.carriedPalletId = pallet.id end
    if source == "on_pallet_jack" then jack.carriedPalletId = nil end
    if target == "outbound_truck" then pallet.world = nil end
    if target == "none" and options.keepWorld ~= true then pallet.world = nil end

    local valid, errors = PalletState.validate(state)
    if not valid then
        pallet.location, pallet.status, pallet.world = previous.location, previous.status, previous.world
        jack.carriedPalletId = previous.carriedPalletId
        return false, table.concat(errors, "; ")
    end
    return true, pallet
end

return PalletState
