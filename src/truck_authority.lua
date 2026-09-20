local JobService = require("src.job_service")
local MachineFleet = require("src.machine_fleet")
local PalletLogistics = require("src.pallet_logistics")

local TruckAuthority = {}

local PAGE_SIZE = 3

local function exactArguments(arguments, required)
    if type(arguments) ~= "table" then return false end
    local allowed = {}
    for _, name in ipairs(required or {}) do allowed[name] = true end
    for key in pairs(arguments) do
        if type(key) ~= "string" or not allowed[key] then return false end
    end
    for _, name in ipairs(required or {}) do
        if arguments[name] == nil then return false end
    end
    return true
end

local function itemIndex(arguments)
    local value = type(arguments) == "table" and arguments.itemIndex
    if not exactArguments(arguments, { "itemIndex" })
        or type(value) ~= "number" or value ~= math.floor(value)
        or value < 1 or value > PAGE_SIZE
    then
        return nil, "invalid_item", "Choose a valid row from the live truck manifest."
    end
    return { itemIndex = value }
end

local function noArguments(arguments)
    if not exactArguments(arguments, {}) then
        return nil, "invalid_arguments", "That truck action takes no additional data."
    end
    return {}
end

local function manifest(state, world)
    local snapshot = world.truckSnapshot()
    local record, inventory
    if snapshot.mode == "pickup" then
        record, inventory = JobService.pickupInventory(state, snapshot.jobId)
    elseif snapshot.mode == "machine_delivery" then
        record, inventory = MachineFleet.truckInventory(state, snapshot.jobId)
    else
        record, inventory = PalletLogistics.truckInventory(state, snapshot.jobId)
    end
    return snapshot, record, inventory or {}
end

local function available(item, mode)
    if mode == "machine_delivery" then return item ~= nil end
    if mode == "pickup" then
        return item.location == "warehouse" or item.location == "cutter_output"
            or item.location == "press_output"
    end
    return item.location == "awaiting_delivery"
end

local function itemCopy(item, mode, rowIndex)
    local label, detail
    if mode == "machine_delivery" then
        local model = MachineFleet.definition(item.modelId)
        label = string.format("Unit %s · %s", tostring(item.id),
            tostring(model and model.shortName or item.modelId or "Machine"))
        detail = string.format("%s condition · %s", MachineFleet.conditionStatus(item.condition),
            available(item, mode) and "ready to unload" or "received")
    elseif mode == "pickup" then
        label = string.format("Pallet %d · %s", tonumber(item.number) or 0, tostring(item.id))
        detail = string.format("%d finished sheets · %s", tonumber(item.sheets) or 0,
            tostring(item.status or "wrapped"))
    elseif item.vendorProduct then
        label = tostring(item.productName or item.id)
        detail = string.format("%s %s · %s", tostring(item.quantity or 0),
            tostring(item.unit or "units"), tostring(item.status or "awaiting delivery"))
    else
        label = string.format("Pallet %d · %s", tonumber(item.number) or 0, tostring(item.id))
        detail = string.format("%d sheets · %s", tonumber(item.sheets) or 0,
            tostring(item.status or "awaiting delivery"))
    end
    return {
        itemIndex = rowIndex,
        label = label,
        detail = detail,
        available = available(item, mode),
    }
end

local function remaining(state, world, snapshot)
    if snapshot.mode == "pickup" then
        return JobService.remainingPickup(state, snapshot.jobId)
    elseif snapshot.mode == "machine_delivery" then
        return MachineFleet.remainingOnTruck(state, snapshot.jobId)
    end
    return PalletLogistics.remainingOnTruck(state, snapshot.jobId)
end

function TruckAuthority.view(state, world, page)
    local snapshot, record, inventory = manifest(state, world)
    local pageCount = math.max(1, math.ceil(#inventory / PAGE_SIZE))
    page = math.max(1, math.min(pageCount, math.floor(tonumber(page) or 1)))
    local rows = {}
    local first = (page - 1) * PAGE_SIZE + 1
    for absoluteIndex = first, math.min(#inventory, first + PAGE_SIZE - 1) do
        rows[#rows + 1] = itemCopy(inventory[absoluteIndex], snapshot.mode, #rows + 1)
    end
    local cargoRemaining = math.max(0, tonumber(remaining(state, world, snapshot)) or 0)
    return {
        mode = tostring(snapshot.mode),
        state = tostring(snapshot.state),
        manifestId = tostring(snapshot.jobId),
        title = tostring(record and (record.company or record.machineName or record.id)
            or "Truck manifest"),
        page = page,
        pageCount = pageCount,
        remaining = cargoRemaining,
        canClose = cargoRemaining == 0
            and (snapshot.mode == "machine_delivery" and snapshot.state == "parked_closed"
                or snapshot.mode ~= "machine_delivery" and snapshot.state == "cargo_open"),
        items = rows,
    }
end

function TruckAuthority.resource(options)
    assert(type(options) == "table", "truck authority options are required")
    local state = assert(options.state, "truck authority state is required")
    local world = assert(options.world, "truck authority world is required")
    local save = type(options.save) == "function" and options.save or function() end

    local function access(player)
        return world.validateNetworkWorkshopAccess(player, state, "truck")
    end

    local function currentView(lease)
        local view = TruckAuthority.view(state, world, lease.private and lease.private.page)
        if lease.private then lease.private.page = view.page end
        return view
    end

    local function changePage(lease, player, delta)
        local allowed, code, message = access(player)
        if not allowed then return false, code, message, currentView(lease) end
        local before = currentView(lease)
        lease.private.page = math.max(1, math.min(before.pageCount, before.page + delta))
        return true, "page_changed", "Truck manifest page changed.", currentView(lease)
    end

    return {
        canAcquire = function(player)
            return access(player)
        end,
        onAcquire = function(_, player)
            if player.id == 1 then
                return true, "acquired", "Truck manifest reserved for the host player."
            end
            return true, "acquired", "Truck manifest connected.",
                TruckAuthority.view(state, world, 1), { page = 1 }
        end,
        onRelease = function() return true end,
        commands = {
            move_item = {
                normalize = itemIndex,
                perform = function(lease, player, arguments)
                    local allowed, code, message = access(player)
                    if not allowed then return false, code, message, currentView(lease) end
                    local snapshot, _, inventory = manifest(state, world)
                    local absoluteIndex = ((lease.private and lease.private.page or 1) - 1)
                        * PAGE_SIZE + arguments.itemIndex
                    local item = inventory[absoluteIndex]
                    if not item or not available(item, snapshot.mode) then
                        return false, "cargo_changed",
                            "That manifest row is no longer available; review the refreshed manifest.",
                            currentView(lease)
                    end
                    local accepted, result, cargoRemaining
                    if snapshot.mode == "pickup" then
                        accepted, result, cargoRemaining = world.loadPickupPallet(state, item.id)
                    elseif snapshot.mode == "machine_delivery" then
                        accepted, result, cargoRemaining = world.unloadTruckMachine(state, item.id)
                    else
                        accepted, result, cargoRemaining = world.unloadTruckPallet(state, item.id)
                    end
                    if not accepted then
                        return false, "cargo_blocked", tostring(result), currentView(lease)
                    end
                    save()
                    local verb = snapshot.mode == "pickup" and "Loaded" or "Unloaded"
                    return true, snapshot.mode == "pickup" and "pallet_loaded" or "cargo_unloaded",
                        string.format("%s %s. %d manifest item(s) remain.",
                            verb, tostring(item.id), tonumber(cargoRemaining) or 0),
                        currentView(lease)
                end,
            },
            page_next = {
                normalize = noArguments,
                perform = function(lease, player) return changePage(lease, player, 1) end,
            },
            page_previous = {
                normalize = noArguments,
                perform = function(lease, player) return changePage(lease, player, -1) end,
            },
            close_truck = {
                normalize = noArguments,
                perform = function(lease, player)
                    local allowed, code, message = access(player)
                    if not allowed then return false, code, message, currentView(lease) end
                    local view = currentView(lease)
                    if not view.canClose then
                        return false, "cargo_remaining",
                            "Finish every available manifest row before releasing the truck.", view
                    end
                    if not world.closeTruckAfterUnload(state) then
                        return false, "truck_changed",
                            "The truck changed state before it could be released.", currentView(lease)
                    end
                    save()
                    return true, "truck_released",
                        view.mode == "machine_delivery"
                            and "The empty flatbed is departing."
                            or "The cargo door is closing.",
                        currentView(lease)
                end,
            },
        },
    }
end

TruckAuthority.PAGE_SIZE = PAGE_SIZE

return TruckAuthority
