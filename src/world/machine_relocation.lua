-- Local cutter, wrapper, and Windmill relocation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.World.beginCutterMove(state, cutterControlOccupied)
        if Runtime.World.employeeCutterReserved(state) then
            state.message="Pause the employee's cutter assignment before relocating it."
            return false
        end
        if cutterControlOccupied then
            state.message = "Close the active cutter console before relocating the machine."
            return false
        end
        if Runtime.Machine.hasActiveBatch() then
            state.message = "Finish or safely unload the cutter batch before relocating the machine."
            return false
        end
        if Runtime.palletJackHasAttachedMachine(state) then
            state.message = "Lock the moving machine onto the floor before relocating another one."
            return false
        end
        if not Runtime.MachineFleet.isInstalled(state, "polar_115") then return false end
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        if jack.operating and jack.operatorPlayerId ~= 1 then
            state.message = "Another worker is operating the pallet jack."
            return false
        end
        if not jack.operating or jack.carriedPalletId then
            state.message = "Operate an empty pallet jack before relocating the cutter."
            return false
        end
        local cutter = Runtime.CutterPlacement.ensure(state, Runtime.Config.cutterPlacement)
        if (jack.x - cutter.x) ^ 2 + (jack.y - cutter.y) ^ 2
            > Runtime.Config.cutterPlacement.interactionRadius ^ 2
        then
            state.message = "Drive the empty pallet jack beside the cutter before relocating it."
            return false
        end
        if Runtime.cutterHasPaper(state) then
            state.message = "Unload the paper and clear the cutting bed before relocating the cutter."
            return false
        end
        if not Runtime.CutterPlacement.beginMove(state, Runtime.Config.cutterPlacement) then return false end
        Runtime.World.placementSelection = nil
        cutter.inMotion = false
        Runtime.PalletJack.followPlacement(state, cutter, 0, Runtime.Config.palletJack)
        Runtime.World.player.x, Runtime.World.player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        state.message = "Cutter is on the pallet jack. Move, choose a green grid space, then press E. Q rotates."
        return true
    end

    function Runtime.World.rotateCutter(state, cutterControlOccupied)
        if state.cutter and state.cutter.moving
            and not Runtime.PalletJack.isOperator(state, Runtime.Config.palletJack, 1) then return false end
        if cutterControlOccupied then
            state.message = "Close the active cutter console before rotating the machine."
            return false
        end
        if Runtime.Machine.hasActiveBatch() then
            state.message = "Finish or safely unload the cutter batch before rotating the machine."
            return false
        end
        if Runtime.cutterHasPaper(state) then
            state.message = "Unload the paper and clear the cutting bed before rotating the cutter."
            return false
        end
        local succeeded, direction = Runtime.CutterPlacement.rotate(state, Runtime.Config.cutterPlacement)
        if not succeeded then return false end
        if state.cutter.moving then
            state.cutter.inMotion = false
            Runtime.PalletJack.followPlacement(state, state.cutter, 0, Runtime.Config.palletJack)
            Runtime.World.player.x, Runtime.World.player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        end
        state.message = "Cutter rotated " .. direction .. "."
        return true
    end

    function Runtime.World.placeCutter(state, assets)
        if not Runtime.PalletJack.isOperator(state, Runtime.Config.palletJack, 1) then return false end
        local grid = Runtime.World.placementGridSnapshot(state, assets)
        local target = grid and grid.selected
        if not target or target.kind ~= "cutter"
            or not Runtime.isMachinePlacementClear(state,assets,"cutter",target.x,target.y) then
            state.message = "The cutter cannot be placed there. Choose a green grid space."
            return false
        end
        state.cutter.x, state.cutter.y = target.x, target.y
        if not Runtime.CutterPlacement.place(state, Runtime.Config.cutterPlacement) then return false end
        Runtime.World.placementSelection = nil
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        Runtime.PalletJack.stop(state, Runtime.Config.palletJack)
        jack.x, jack.y = state.cutter.x, state.cutter.y + 42
        Runtime.World.player.x, Runtime.World.player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        state.message = "Cutter locked in its new floor position."
        return true
    end

    function Runtime.World.cutterSnapshot(state)
        return Runtime.CutterPlacement.snapshot(state, Runtime.Config.cutterPlacement)
    end

    function Runtime.World.beginWrapperMove(state, wrapperControlOccupied)
        if wrapperControlOccupied then
            state.message = "Close the active skid-wrapper console before relocating the machine."
            return false
        end
        if Runtime.palletJackHasAttachedMachine(state) then
            state.message = "Lock the moving machine onto the floor before relocating another one."
            return false
        end
        if not Runtime.MachineFleet.isInstalled(state, "skid_wrapper") then return false end
        local installed=Runtime.MachineFleet.installedUnits(state,"skid_wrapper")
        if installed[1] and Runtime.Employees.reservation(state,installed[1].id) then
            state.message="Pause the employee's assignment before relocating the skid wrapper."
            return false
        end
        if not Runtime.Wrapper.canRelocate(state) then return false end
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        if jack.operating and jack.operatorPlayerId ~= 1 then
            state.message = "Another worker is operating the pallet jack."
            return false
        end
        if not jack.operating or jack.carriedPalletId then
            state.message = "Operate an empty pallet jack before relocating the skid wrapper."
            return false
        end
        local wrapper = Runtime.WrapperPlacement.ensure(state, Runtime.Config.wrapperPlacement)
        if (jack.x - wrapper.x) ^ 2 + (jack.y - wrapper.y) ^ 2
            > Runtime.Config.wrapperPlacement.interactionRadius ^ 2
        then
            state.message = "Drive the empty pallet jack beside the skid wrapper before relocating it."
            return false
        end
        if not Runtime.WrapperPlacement.beginMove(state, Runtime.Config.wrapperPlacement) then return false end
        Runtime.World.placementSelection = nil
        wrapper.inMotion = false
        Runtime.PalletJack.followPlacement(state, wrapper, 0, Runtime.Config.palletJack)
        Runtime.World.player.x, Runtime.World.player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        state.message = "Skid wrapper is on the pallet jack. Move, choose a green grid space, then press E. Q rotates."
        return true
    end

    function Runtime.World.wrapperNearby(state)
        if not Runtime.MachineFleet.isInstalled(state, "skid_wrapper") then return false end
        local wrapper = Runtime.WrapperPlacement.ensure(state, Runtime.Config.wrapperPlacement)
        local dx, dy = Runtime.World.player.x - wrapper.x, Runtime.World.player.y - wrapper.y
        return dx * dx + dy * dy <= Runtime.Config.wrapperPlacement.interactionRadius ^ 2
    end

    function Runtime.World.cutterNearby(state)
        if not Runtime.MachineFleet.isInstalled(state, "polar_115") then return false end
        local cutter = Runtime.CutterPlacement.ensure(state, Runtime.Config.cutterPlacement)
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        return (jack.x - cutter.x) ^ 2 + (jack.y - cutter.y) ^ 2
            <= Runtime.Config.cutterPlacement.interactionRadius ^ 2
    end

    function Runtime.World.rotateWrapper(state, wrapperControlOccupied)
        if state.wrapper and state.wrapper.moving
            and not Runtime.PalletJack.isOperator(state, Runtime.Config.palletJack, 1) then return false end
        if wrapperControlOccupied then
            state.message = "Close the active skid-wrapper console before rotating the machine."
            return false
        end
        local succeeded, direction = Runtime.WrapperPlacement.rotate(state, Runtime.Config.wrapperPlacement)
        if not succeeded then return false end
        if state.wrapper.moving then
            state.wrapper.inMotion = false
            Runtime.PalletJack.followPlacement(state, state.wrapper, 0, Runtime.Config.palletJack)
            Runtime.World.player.x, Runtime.World.player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        end
        state.message = "Skid wrapper rotated " .. direction .. "."
        return true
    end

    function Runtime.World.placeWrapper(state, assets)
        if not Runtime.PalletJack.isOperator(state, Runtime.Config.palletJack, 1) then return false end
        local grid = Runtime.World.placementGridSnapshot(state, assets)
        local target = grid and grid.selected
        if not target or target.kind ~= "wrapper"
            or not Runtime.isMachinePlacementClear(state,assets,"wrapper",target.x,target.y) then
            state.message = "The skid wrapper cannot be placed there. Choose a green grid space."
            return false
        end
        state.wrapper.x, state.wrapper.y = target.x, target.y
        if not Runtime.WrapperPlacement.place(state, Runtime.Config.wrapperPlacement) then return false end
        Runtime.World.placementSelection = nil
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        Runtime.PalletJack.stop(state, Runtime.Config.palletJack)
        jack.x, jack.y = state.wrapper.x, state.wrapper.y + 46
        Runtime.World.player.x, Runtime.World.player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        state.message = "Skid wrapper locked in its new floor position."
        return true
    end

    function Runtime.World.wrapperSnapshot(state)
        return Runtime.WrapperPlacement.snapshot(state, Runtime.Config.wrapperPlacement)
    end

    function Runtime.World.beginWindmillMove(state, windmillControlOccupied)
        if windmillControlOccupied then
            state.message = "Close the active Windmill console before relocating the press."
            return false
        end
        if Runtime.palletJackHasAttachedMachine(state) then
            state.message = "Lock the moving machine onto the floor before relocating another one."
            return false
        end
        if not Runtime.MachineFleet.isInstalled(state, "heidelberg_10x15") then return false end
        local installed=Runtime.MachineFleet.installedUnits(state,"heidelberg_10x15")
        if installed[1] and Runtime.Employees.reservation(state,installed[1].id) then
            state.message="Pause the employee's assignment before relocating the Windmill."
            return false
        end
        local process = Runtime.Windmill.ensure(state)
        if process.status ~= "idle" or process.palletId then
            state.message = "Unload the press and return the Windmill to idle before relocating it."
            return false
        end
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        if jack.operating and jack.operatorPlayerId ~= 1 then
            state.message = "Another worker is operating the pallet jack."
            return false
        end
        if not jack.operating or jack.carriedPalletId then
            state.message = "Operate an empty pallet jack before relocating the Windmill."
            return false
        end
        local item = Runtime.WindmillPlacement.ensure(state, Runtime.Config.windmillPlacement)
        if (jack.x - item.x) ^ 2 + (jack.y - item.y) ^ 2
            > Runtime.Config.windmillPlacement.interactionRadius ^ 2
        then
            state.message = "Drive the empty pallet jack beside the Windmill before relocating it."
            return false
        end
        if not Runtime.WindmillPlacement.beginMove(state, Runtime.Config.windmillPlacement) then return false end
        Runtime.World.placementSelection = nil
        item.inMotion = false
        Runtime.PalletJack.followPlacement(state, item, 0, Runtime.Config.palletJack)
        Runtime.World.player.x, Runtime.World.player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        state.message = "Windmill is on the pallet jack. Move, choose a green grid space, then press E. Q rotates."
        return true
    end

    function Runtime.World.windmillNearby(state)
        if not Runtime.MachineFleet.isInstalled(state, "heidelberg_10x15") then return false end
        local item = Runtime.WindmillPlacement.ensure(state, Runtime.Config.windmillPlacement)
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        return (jack.x - item.x) ^ 2 + (jack.y - item.y) ^ 2
            <= Runtime.Config.windmillPlacement.interactionRadius ^ 2
    end

    function Runtime.World.rotateWindmill(state, windmillControlOccupied)
        if state.windmill and state.windmill.moving
            and not Runtime.PalletJack.isOperator(state, Runtime.Config.palletJack, 1) then return false end
        if windmillControlOccupied then
            state.message = "Close the active Windmill console before rotating the press."
            return false
        end
        local process = Runtime.Windmill.ensure(state)
        if process.status ~= "idle" or process.palletId then
            state.message = "Unload the press and return the Windmill to idle before rotating it."
            return false
        end
        local succeeded, direction = Runtime.WindmillPlacement.rotate(state, Runtime.Config.windmillPlacement)
        if not succeeded then return false end
        if state.windmill.moving then
            state.windmill.inMotion = false
            Runtime.PalletJack.followPlacement(state, state.windmill, 0, Runtime.Config.palletJack)
            Runtime.World.player.x, Runtime.World.player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        end
        state.message = "Windmill rotated " .. direction .. "."
        return true
    end

    function Runtime.World.placeWindmill(state, assets)
        if not Runtime.PalletJack.isOperator(state, Runtime.Config.palletJack, 1) then return false end
        local grid = Runtime.World.placementGridSnapshot(state, assets)
        local target = grid and grid.selected
        if not target or target.kind ~= "windmill"
            or not Runtime.isMachinePlacementClear(state,assets,"windmill",target.x,target.y) then
            state.message = "The Windmill cannot be placed there. Choose a green grid space."
            return false
        end
        state.windmill.x, state.windmill.y = target.x, target.y
        if not Runtime.WindmillPlacement.place(state, Runtime.Config.windmillPlacement) then return false end
        Runtime.World.placementSelection = nil
        local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
        Runtime.PalletJack.stop(state, Runtime.Config.palletJack)
        jack.x, jack.y = state.windmill.x, state.windmill.y + 52
        Runtime.World.player.x, Runtime.World.player.y = Runtime.PalletJack.operatorPosition(state, Runtime.Config.palletJack)
        state.message = "Windmill locked in its new floor position."
        return true
    end

    function Runtime.World.windmillSnapshot(state)
        return Runtime.WindmillPlacement.snapshot(state, Runtime.Config.windmillPlacement)
    end
end

return Component
