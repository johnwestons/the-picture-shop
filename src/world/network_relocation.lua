-- Network machine relocation and recovery.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.cutterHasPaper(state)
        for _, job in ipairs(state and state.jobs and state.jobs.active or {}) do
            for _, pallet in ipairs(job.pallets or {}) do
                if pallet.location == "at_cutter" then return true end
            end
        end
        return false
    end

    Runtime.NETWORK_MACHINE_KINDS = {
        [1] = { kind = "cutter", modelId = "polar_115", placement = Runtime.CutterPlacement,
            config = Runtime.Config.cutterPlacement, label = "cutter", parkedOffset = 42 },
        [2] = { kind = "wrapper", modelId = "skid_wrapper", placement = Runtime.WrapperPlacement,
            config = Runtime.Config.wrapperPlacement, label = "skid wrapper", parkedOffset = 46 },
        [3] = { kind = "windmill", modelId = "heidelberg_10x15", placement = Runtime.WindmillPlacement,
            config = Runtime.Config.windmillPlacement, label = "Windmill", parkedOffset = 52 },
    }

    function Runtime.activeNetworkMachine(state)
        local kind = Runtime.activeMachineKind(state)
        if not kind then return nil end
        for index, record in pairs(Runtime.NETWORK_MACHINE_KINDS) do
            if record.kind == kind then return record, index end
        end
    end

    function Runtime.networkJackOwner(player, state)
        local playerId = Runtime.validNetworkPlayerId(player)
        local jack = type(state) == "table" and Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        if not playerId or not jack then
            return nil, nil, "invalid_player", "The host could not identify that worker."
        end
        if not jack.operating or jack.operatorPlayerId ~= playerId then
            return nil, nil, "not_owner", "Acquire the pallet jack before relocating a machine."
        end
        if jack.carriedPalletId then
            return nil, nil, "jack_loaded", "Lower the carried pallet before relocating a machine."
        end
        return playerId, jack
    end

    function Runtime.World.beginNetworkMachineMove(player, state, machineIndex, controlOccupied)
        local playerId, jack, code, message = Runtime.networkJackOwner(player, state)
        if not playerId then return false, code, message end
        if Runtime.palletJackHasAttachedMachine(state) then
            return false, "machine_moving", "Place the moving machine before relocating another one."
        end
        local record = Runtime.NETWORK_MACHINE_KINDS[tonumber(machineIndex)]
        if not record or not Runtime.MachineFleet.isInstalled(state, record.modelId) then
            return false, "machine_unavailable", "That machine is not installed in this shop."
        end
        for _,unit in ipairs(Runtime.MachineFleet.installedUnits(state,record.modelId)) do
            if Runtime.Employees.reservation(state,unit.id) then
                return false,"employee_reserved","Pause the employee's assignment before relocating this machine."
            end
        end
        if controlOccupied then
            return false, "console_busy", "Close the active " .. record.label .. " console first."
        end
        if record.kind == "cutter" then
            if Runtime.Machine.hasActiveBatch() or Runtime.cutterHasPaper(state) then
                return false, "machine_busy", "Unload the cutter and finish its active batch first."
            end
        elseif record.kind == "wrapper" then
            if not Runtime.Wrapper.canRelocate(state) then
                return false, "machine_busy", tostring(state.message)
            end
        else
            local process = Runtime.Windmill.ensure(state)
            if process.status ~= "idle" or process.palletId then
                return false, "machine_busy", "Unload the Windmill and return it to idle first."
            end
        end
        local item = record.placement.ensure(state, record.config)
        if (jack.x - item.x) ^ 2 + (jack.y - item.y) ^ 2
            > record.config.interactionRadius ^ 2
        then
            return false, "out_of_range",
                "Drive the empty pallet jack beside the " .. record.label .. " first."
        end
        if not record.placement.beginMove(state, record.config) then
            return false, "machine_changed", "That machine could not be lifted safely."
        end
        Runtime.World.placementSelection = nil
        item.inMotion = false
        Runtime.PalletJack.followPlacement(state, item, 0, Runtime.Config.palletJack)
        player.x, player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        state.message = record.label .. " is on the pallet jack. Move, choose a green grid space, then place it."
        return true, "machine_attached", state.message, Runtime.World.networkPalletJackSnapshot(state)
    end

    function Runtime.World.rotateNetworkMachine(player, state)
        local playerId, jack, code, message = Runtime.networkJackOwner(player, state)
        if not playerId then return false, code, message end
        local record = Runtime.activeNetworkMachine(state)
        if not record then return false, "no_machine", "No machine is attached to this pallet jack." end
        local rotated, direction = record.placement.rotate(state, record.config)
        if not rotated then return false, "rotation_blocked", "The machine could not be rotated." end
        local item = record.placement.ensure(state, record.config)
        item.inMotion = false
        Runtime.PalletJack.followPlacement(state, item, 0, Runtime.Config.palletJack)
        player.x, player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        state.message = record.label .. " rotated " .. tostring(direction) .. "."
        return true, "machine_rotated", state.message, Runtime.World.networkPalletJackSnapshot(state)
    end

    function Runtime.World.networkPlacementCellId(state, assets)
        local snapshot = Runtime.World.placementGridSnapshot(state, assets)
        local selected = snapshot and snapshot.selected
        if not snapshot or not selected or selected.kind ~= snapshot.kind then return nil end
        return Runtime.PlacementGrid.cellId(selected.x,selected.y,snapshot.config)
    end

    function Runtime.finishNetworkMachinePlacement(player, state, record, x, y)
        local item = record.placement.ensure(state, record.config)
        item.x, item.y = x, y
        if not record.placement.place(state, record.config) then return false end
        Runtime.World.placementSelection = nil
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        Runtime.PalletJack.stop(state, Runtime.Config.palletJack)
        jack.x, jack.y, jack.direction = item.x, item.y + record.parkedOffset, item.direction
        if player then player.x, player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack) end
        state.message = record.label .. " locked into its new floor position."
        return true
    end

    function Runtime.World.placeNetworkMachine(player, state, assets, placementCell)
        local playerId, _, code, message = Runtime.networkJackOwner(player, state)
        if not playerId then return false, code, message end
        local record = Runtime.activeNetworkMachine(state)
        if not record then return false, "no_machine", "No machine is attached to this pallet jack." end
        local x,y = Runtime.PlacementGrid.decode(placementCell,Runtime.Config.placementGrid)
        if not x then
            return false, "invalid_cell", "Choose a valid highlighted placement cell."
        end
        local grid = Runtime.World.placementGridSnapshot(state, assets)
        local valid = false
        for _, cell in ipairs(grid and grid.cells or {}) do
            if cell.x == x and cell.y == y and cell.valid then valid = true; break end
        end
        if not valid or not Runtime.isMachinePlacementClear(state, assets, record.kind, x, y) then
            return false, "placement_blocked", "That placement cell is blocked; choose a green space."
        end
        if not Runtime.finishNetworkMachinePlacement(player, state, record, x, y) then
            return false, "machine_changed", "The machine changed before it could be placed."
        end
        return true, "machine_placed", state.message, Runtime.World.networkPalletJackSnapshot(state)
    end

    function Runtime.World.recoverNetworkMachineMove(state, assets, player)
        local record = Runtime.activeNetworkMachine(state)
        if not record then return false end
        local item = record.placement.ensure(state, record.config)
        local origin = item._relocationOrigin
        Runtime.World.placementSelection = nil
        local grid = Runtime.World.placementGridSnapshot(state, assets)
        local target = grid and grid.selected
        local x, y = target and target.x, target and target.y
        if not x or not y or not Runtime.isMachinePlacementClear(state, assets, record.kind, x, y) then
            x, y = origin and origin.x or item.x, origin and origin.y or item.y
        end
        local recovered = Runtime.finishNetworkMachinePlacement(player, state, record, x, y)
        if recovered then state.message = "Disconnected relocation recovered and the machine was locked safely." end
        return recovered
    end
end

return Component
