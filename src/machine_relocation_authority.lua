local MachineRelocationAuthority = {}

local function exactArguments(arguments, required)
    if type(arguments) ~= "table" then return false end
    local allowed = {}
    for _, field in ipairs(required or {}) do allowed[field] = true end
    for field in pairs(arguments) do
        if type(field) ~= "string" or not allowed[field] then return false end
    end
    for _, field in ipairs(required or {}) do
        if arguments[field] == nil then return false end
    end
    return true
end

local function machineMoving(state)
    return state.cutter and state.cutter.moving
        or state.wrapper and state.wrapper.moving
        or state.windmill and state.windmill.moving
end

function MachineRelocationAuthority.resource(options)
    options = options or {}
    local state = assert(options.state, "machine relocation authority requires state")
    local assets = assert(options.assets, "machine relocation authority requires assets")
    local world = assert(options.world, "machine relocation authority requires world")
    local palletJack = assert(options.palletJack,
        "machine relocation authority requires palletJack")
    local config = assert(options.config, "machine relocation authority requires config")
    local save = options.save or function() end
    local controlOccupied = options.controlOccupied or function() return false end
    local function validateAccess(player)
        return world.validateNetworkWorkshopAccess(player, state, "pallet_jack")
    end

    return {
        canAcquire = function(player)
            local allowed, code, message = validateAccess(player)
            if not allowed then return false, code, message end
            if machineMoving(state) then
                return false, "machine_moving",
                    "Finish locking the moving machine onto the floor first."
            end
            return true
        end,
        onAcquire = function(_, player)
            local accepted, code, message = world.operateNetworkPalletJack(player, state)
            return accepted, code, message, accepted and {} or nil
        end,
        onRelease = function(lease, player)
            world.recoverNetworkMachineMove(state, assets, player)
            palletJack.forceRelease(state, config.palletJack,
                lease and lease.ownerPlayerId or nil)
            save()
            return true, "released", state.palletJack.carriedPalletId
                and "Loaded pallet jack parked safely."
                or "Pallet jack parked."
        end,
        commands = {
            lift_pallet = {
                normalize = function(arguments)
                    local palletId = type(arguments) == "table" and arguments.palletId
                    if not exactArguments(arguments, { "palletId" })
                        or type(palletId) ~= "string" or #palletId < 1 or #palletId > 64
                        or not palletId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                    then
                        return nil, "invalid_pallet", "Choose a valid nearby pallet."
                    end
                    return { palletId = palletId }
                end,
                perform = function(_, player, arguments)
                    local allowed, accessCode, accessMessage = validateAccess(player)
                    if not allowed then return false, accessCode, accessMessage end
                    if machineMoving(state) then
                        return false, "equipment_moving",
                            "Place the moving machine before lifting a pallet."
                    end
                    local accepted, code, message = world.liftNetworkPallet(
                        player, state, arguments.palletId)
                    if accepted then save() end
                    return accepted, code, message
                end,
            },
            lower_pallet = {
                normalize = function(arguments)
                    local palletId = type(arguments) == "table" and arguments.palletId
                    if not exactArguments(arguments, { "palletId" })
                        or type(palletId) ~= "string" or #palletId < 1 or #palletId > 64
                        or not palletId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                    then
                        return nil, "invalid_pallet",
                            "Choose the pallet currently on the forks."
                    end
                    return { palletId = palletId }
                end,
                perform = function(_, player, arguments)
                    local allowed, accessCode, accessMessage = validateAccess(player)
                    if not allowed then return false, accessCode, accessMessage end
                    if machineMoving(state) then
                        return false, "equipment_moving",
                            "Place the moving machine before lowering a pallet."
                    end
                    local accepted, code, message = world.lowerNetworkPallet(
                        player, state, assets, arguments.palletId)
                    if accepted then save() end
                    return accepted, code, message
                end,
            },
            park_jack = {
                normalize = function(arguments)
                    if not exactArguments(arguments, {}) then
                        return nil, "invalid_arguments", "Parking takes no additional data."
                    end
                    return {}
                end,
                perform = function(_, player)
                    local allowed, accessCode, accessMessage = validateAccess(player)
                    if not allowed then return false, accessCode, accessMessage end
                    if machineMoving(state) then
                        return false, "equipment_moving",
                            "Place the moving machine before parking the jack."
                    end
                    local accepted, code, message = world.releaseNetworkPalletJack(
                        player, state, false)
                    if accepted then save() end
                    return accepted, code, message
                end,
            },
            move_machine = {
                normalize = function(arguments)
                    local machineIndex = type(arguments) == "table"
                        and arguments.machineIndex
                    if not exactArguments(arguments, { "machineIndex" })
                        or type(machineIndex) ~= "number" or machineIndex % 1 ~= 0
                        or machineIndex < 1 or machineIndex > 3
                    then
                        return nil, "invalid_machine", "Choose a valid nearby machine."
                    end
                    return { machineIndex = machineIndex }
                end,
                perform = function(_, player, arguments)
                    local allowed, accessCode, accessMessage = validateAccess(player)
                    if not allowed then return false, accessCode, accessMessage end
                    local accepted, code, message = world.beginNetworkMachineMove(
                        player, state, arguments.machineIndex,
                        controlOccupied(arguments.machineIndex))
                    if accepted then save() end
                    return accepted, code, message
                end,
            },
            rotate_machine = {
                normalize = function(arguments)
                    if not exactArguments(arguments, {}) then
                        return nil, "invalid_arguments", "Rotation takes no additional data."
                    end
                    return {}
                end,
                perform = function(_, player)
                    local allowed, accessCode, accessMessage = validateAccess(player)
                    if not allowed then return false, accessCode, accessMessage end
                    local accepted, code, message = world.rotateNetworkMachine(player, state)
                    if accepted then save() end
                    return accepted, code, message
                end,
            },
            place_machine = {
                normalize = function(arguments)
                    local cell = type(arguments) == "table" and arguments.placementCell
                    local column, row
                    if type(cell) == "string" then
                        column, row = cell:match("^c(%d+)r(%d+)$")
                    end
                    column, row = tonumber(column), tonumber(row)
                    if not exactArguments(arguments, { "placementCell" })
                        or not column or not row or column > 64 or row > 64
                    then
                        return nil, "invalid_cell",
                            "Choose a valid highlighted placement cell."
                    end
                    return { placementCell = cell }
                end,
                perform = function(_, player, arguments)
                    local allowed, accessCode, accessMessage = validateAccess(player)
                    if not allowed then return false, accessCode, accessMessage end
                    local accepted, code, message = world.placeNetworkMachine(
                        player, state, assets, arguments.placementCell)
                    if accepted then save() end
                    return accepted, code, message
                end,
            },
        },
    }
end

return MachineRelocationAuthority
