-- Pallet-jack controls and workshop commands.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.palletJackCommandFor(action, selected)
        local jack = Runtime.PalletJack.ensure(Runtime.state, Runtime.Config.palletJack)
        if action == "park" then return "park_jack", {} end
        if action == "rotate_machine" then return "rotate_machine", {} end
        if action == "place_machine" then
            local placementCell = Runtime.World.networkPlacementCellId(Runtime.state, Runtime.Assets)
            if not placementCell then
                return nil, nil, "Choose a green placement cell before setting the machine down."
            end
            return "place_machine", { placementCell = placementCell }
        end
        if action == "move_machine" then
            local machineIndex = selected and ({
                cutter = 1,
                skidWrapper = 2,
                windmill = 3,
            })[selected.kind]
            if not machineIndex then return nil, nil, "Move beside the machine you want to relocate." end
            return "move_machine", { machineIndex = machineIndex }
        end
        if action == "lift" then
            local selectedPallet = selected and selected.target
                and selected.target.item and selected.target.item.pallet
            local palletId = selectedPallet and selectedPallet.id
            if type(palletId) ~= "string" or palletId == "" then
                return nil, nil, "Tap a valid skid to lift it."
            end
            if jack.carriedPalletId then
                return nil, nil, "Lower the skid already on the forks before lifting another one."
            end
            return "lift_pallet", { palletId = palletId }
        end
        if jack.carriedPalletId then
            local placementCell = Runtime.World.networkPlacementCellId(Runtime.state,Runtime.Assets)
            if not placementCell then return nil,nil,"Choose a green space before lowering the pallet." end
            return "lower_pallet", { palletId = jack.carriedPalletId,placementCell=placementCell }
        end
        local candidateId = jack.candidatePalletId
            or Runtime.World.networkPalletJackSnapshot(Runtime.state).candidatePalletId
        if candidateId then return "lift_pallet", { palletId = candidateId } end
        return "park_jack", {}
    end

    function Runtime.handlePalletJackControl(action, selected)
        if Runtime.machineRelocationActive() then
            local targetsPalletJack = action == "park" or action == "use"
                or action == "lift"
            if targetsPalletJack and action ~= "place_machine" then
                Runtime.state.message = "Place the moving machine before using or parking the pallet jack."
                return true
            end
        end
        if Runtime.multiplayer:isClient() then
            local info = Runtime.multiplayer:workshopInfo()
            if not info or info.resourceId ~= "pallet_jack" then
                if action == "park" then
                    Runtime.state.message = Runtime.state.palletJack and Runtime.state.palletJack.operating
                        and "Another worker is operating the pallet jack."
                        or "Acquire the pallet jack before parking it."
                    return true
                end
                return false
            end
            local command, arguments, commandError = Runtime.palletJackCommandFor(action, selected)
            if not command then Runtime.state.message = commandError; return true end
            local requested, errorMessage = Runtime.multiplayer:requestWorkshopCommand(
                command, arguments)
            Runtime.state.message = requested
                and (command == "lift_pallet" and "Waiting for the host to verify that exact pallet..."
                    or command == "lower_pallet" and "Waiting for the host to verify the drop space..."
                    or command == "move_machine" and "Waiting for the host to attach that machine..."
                    or command == "rotate_machine" and "Waiting for the host to rotate the machine..."
                    or command == "place_machine" and "Waiting for the host to verify that floor cell..."
                    or "Waiting for the host to park the pallet jack...")
                or tostring(errorMessage or "The pallet-jack request could not be sent.")
            return true
        end
        if not Runtime.multiplayer:isHost() then return false end
        if Runtime.localWorkshopLease and Runtime.localWorkshopLease.resourceId == "pallet_jack" then
            local command, arguments, commandError = Runtime.palletJackCommandFor(action, selected)
            if not command then Runtime.state.message = commandError; return true end
            local accepted, message = Runtime.commandLocalWorkshop(command, arguments)
            Runtime.state.message = tostring(message or (accepted
                and "Pallet-jack action completed." or "Pallet-jack action was rejected."))
            if accepted and command == "park_jack" then Runtime.releaseLocalWorkshop("closed") end
            return true
        end
        local jack = Runtime.PalletJack.ensure(Runtime.state, Runtime.Config.palletJack)
        if action == "park" and jack.operating and jack.operatorPlayerId ~= 1 then
            Runtime.state.message = "Another worker is operating the pallet jack."
            return true
        end
        return false
    end
end

return Component
