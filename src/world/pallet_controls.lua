-- Local and network pallet-jack ownership and actions.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.validNetworkPlayerId(player)
        local id = type(player) == "table" and tonumber(player.id) or nil
        return id and id == math.floor(id) and id >= 1 and id <= 4 and id or nil
    end

    function Runtime.palletJackHasAttachedMachine(state)
        return type(state) == "table" and ((state.cutter and state.cutter.moving)
            or (state.wrapper and state.wrapper.moving)
            or (state.windmill and state.windmill.moving))
    end

    function Runtime.World.operateNetworkPalletJack(player, state)
        local playerId = Runtime.validNetworkPlayerId(player)
        if not playerId or type(state) ~= "table" then
            return false, "invalid_player", "The host could not identify that worker."
        end
        local mounted, mountCode = Runtime.PalletJack.mount(state, Runtime.Config.palletJack, playerId)
        if not mounted then
            return false, mountCode, mountCode == "busy"
                and "Another worker is operating the pallet jack."
                or "The pallet jack could not be mounted safely."
        end
        local operatorX, operatorY = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        player.x, player.y = operatorX, operatorY
        if playerId == 1 then Runtime.World.player.x, Runtime.World.player.y = operatorX, operatorY end
        state.message = "Operating pallet jack. Click/tap a highlighted skid or press L to lift it. L lowers; F parks."
        return true, mountCode, state.message, Runtime.World.networkPalletJackSnapshot(state)
    end

    function Runtime.World.releaseNetworkPalletJack(player, state, force)
        local playerId = Runtime.validNetworkPlayerId(player)
        if not playerId or type(state) ~= "table" then
            return false, "invalid_player", "The host could not identify that worker."
        end
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        if jack.operatorPlayerId ~= playerId then
            return false, "not_owner", "Another worker owns the pallet jack."
        end
        if not force and Runtime.palletJackHasAttachedMachine(state) then
            return false, "equipment_moving",
                "Place the moving machine before parking the pallet jack."
        end
        local released, releaseCode
        if force then
            released, releaseCode = Runtime.PalletJack.forceRelease(
                state, Runtime.Config.palletJack, playerId)
        else
            released = Runtime.PalletJack.park(state, Runtime.Config.palletJack)
            releaseCode = released and "parked" or "loaded"
        end
        if not released then
            local message = releaseCode == "loaded"
                and "Lower the carried pallet before parking the jack."
                or "The pallet jack could not be released safely."
            state.message = message
            return false, releaseCode, message
        end
        state.message = releaseCode == "parked_loaded"
            and "The disconnected worker's loaded pallet jack was parked safely."
            or "Pallet jack parked."
        return true, releaseCode, state.message, Runtime.World.networkPalletJackSnapshot(state)
    end

    function Runtime.World.liftNetworkPallet(player, state, palletId)
        local playerId = Runtime.validNetworkPlayerId(player)
        if not playerId or not Runtime.PalletJack.isOperator(state, Runtime.Config.palletJack, playerId) then
            return false, "not_owner", "Acquire the pallet jack before lifting a pallet."
        end
        if Runtime.palletJackHasAttachedMachine(state) then
            return false, "equipment_moving",
                "Place the moving machine before lifting a pallet."
        end
        local lifted, liftCode, pallet = Runtime.PalletJack.lift(
            state, Runtime.Config.palletJack, palletId)
        if not lifted then
            local messages = {
                missing = "That pallet no longer exists.",
                unavailable = "That pallet is no longer staged on movable floor space.",
                out_of_range = "Drive the forks closer to that exact pallet.",
                already_loaded = "The pallet jack is already carrying a pallet.",
                invalid_pallet = "Choose a valid pallet.",
                employee_reserved = "Pause the employee's assignment before lifting this pallet.",
                supporting_pallet = "Use the forklift to remove the upper pallet first.",
            }
            state.message = messages[liftCode] or tostring(liftCode)
            return false, liftCode, state.message
        end
        local operatorX, operatorY = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        player.x, player.y = operatorX, operatorY
        state.message = "Lifted " .. pallet.id .. ". Drive it into position, then lower it."
        return true, liftCode, state.message, pallet
    end

    function Runtime.World.lowerNetworkPallet(player, state, assets, palletId, placementCell)
        local playerId = Runtime.validNetworkPlayerId(player)
        if not playerId or not Runtime.PalletJack.isOperator(state, Runtime.Config.palletJack, playerId) then
            return false, "not_owner", "Acquire the pallet jack before lowering a pallet."
        end
        if Runtime.palletJackHasAttachedMachine(state) then
            return false, "equipment_moving",
                "Place the moving machine before lowering a pallet."
        end
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        if jack.carriedPalletId ~= palletId then
            return false, "wrong_pallet", "The pallet on the forks changed; try again."
        end
        local dropX, dropY = Runtime.PalletJack.dropPosition(state, Runtime.Config.palletJack)
        if placementCell ~= nil then
            dropX,dropY = Runtime.PlacementGrid.decode(placementCell,Runtime.Config.placementGrid)
            if not dropX then return false,"invalid_cell","Choose a valid highlighted drop cell." end
            local grid = Runtime.World.placementGridSnapshot(state,assets)
            local cell = Runtime.PlacementGrid.find(grid and grid.cells,dropX,dropY)
            if not cell or not cell.valid then
                return false,"placement_blocked","That drop cell is blocked or out of reach."
            end
        else
            dropX, dropY = Runtime.PlacementGrid.snap(dropX, dropY, Runtime.Config.placementGrid)
        end
        local lowered, lowerCode, pallet = Runtime.PalletJack.lower(
            state, Runtime.Config.palletJack, function(x, y)
                return Runtime.World.isPalletPlacementClear(
                    state, assets or Runtime.World._assets, x, y, palletId)
            end, dropX, dropY, palletId)
        if not lowered then
            state.message = lowerCode == "blocked"
                and "There is not enough clear floor space to lower this pallet."
                or (lowerCode == "missing" and "The carried pallet could not be found."
                    or "The pallet could not be lowered safely.")
            return false, lowerCode, state.message
        end
        state.message = "Lowered " .. pallet.id .. " at its host-validated warehouse position."
        return true, lowerCode, state.message, pallet
    end

    function Runtime.World.handlePalletJack(state, assets, palletId)
        local localPlayerId = tonumber(Runtime.World.player.id) or 1
        local currentJack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        if Runtime.palletJackHasAttachedMachine(state) then
            state.message = "Place the moving machine before using the pallet jack."
            return false
        end
        if currentJack.operating and currentJack.operatorPlayerId ~= localPlayerId then
            state.message = "Another worker is operating the pallet jack."
            return false
        end
        local succeeded, action, pallet
        if palletId ~= nil then
            if not Runtime.PalletJack.isOperator(state, Runtime.Config.palletJack, localPlayerId) then
                state.message = "Operate the pallet jack before tapping a skid."
                return false
            end
            succeeded, action, pallet = Runtime.PalletJack.lift(
                state, Runtime.Config.palletJack, palletId)
        else
            local grid = Runtime.World.placementGridSnapshot(state, assets)
            if currentJack.carriedPalletId and (not grid or not grid.selected) then
                state.message = "Choose a clear green space before lowering this pallet."
                return false
            end
            local selected = grid and grid.selected
            local placementX = selected and selected.kind == "pallet" and selected.x or nil
            local placementY = selected and selected.kind == "pallet" and selected.y or nil
            succeeded, action, pallet = Runtime.PalletJack.use(state, Runtime.Config.palletJack, function(x, y)
                return Runtime.World.isPalletPlacementClear(state, assets, x, y)
            end, placementX, placementY, localPlayerId)
        end
        if not succeeded then
            if state then
                local messages = {
                    blocked = "There is not enough clear floor space to lower this pallet.",
                    missing = "That skid no longer exists.",
                    unavailable = "That skid is not staged where the pallet jack can lift it.",
                    out_of_range = "Push the pallet jack closer to that skid, then tap it again.",
                    already_loaded = "Lower the skid already on the forks before lifting another one.",
                    invalid_pallet = "Tap a valid skid to lift it.",
                    employee_reserved = "Pause the employee's assignment before lifting this pallet.",
                    supporting_pallet = "Use the forklift to remove the upper pallet first.",
                }
                state.message = messages[action] or "The carried pallet could not be found."
            end
            return false
        end
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        if action == "mounted" then
            Runtime.World.player.x, Runtime.World.player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
            state.message = "Operating pallet jack. Click/tap a highlighted skid or press L to lift it. L lowers; F parks."
        elseif action == "lifted" then
            Runtime.World.placementSelection = nil
            state.message = "Lifted " .. pallet.id .. ". Drive it, choose a green grid space, then press L."
        elseif action == "lowered" then
            Runtime.World.placementSelection = nil
            state.message = "Lowered " .. pallet.id .. " at its new warehouse position."
        else
            state.message = "Pallet jack parked."
        end
        return true, action, pallet
    end

    function Runtime.World.parkPalletJack(state)
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        if Runtime.palletJackHasAttachedMachine(state) then
            if state then state.message = "Place the moving machine before parking the pallet jack." end
            return false
        end
        local localPlayerId = tonumber(Runtime.World.player.id) or 1
        if jack.operating and jack.operatorPlayerId ~= localPlayerId then
            if state then state.message = "Another worker is operating the pallet jack." end
            return false
        end
        if not Runtime.PalletJack.park(state, Runtime.Config.palletJack) then
            if state then state.message = "Lower the carried pallet before parking the jack." end
            return false
        end
        if state then state.message = "Pallet jack parked." end
        return true
    end
end

return Component
