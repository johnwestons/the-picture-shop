-- Keyboard routing and mobile actions.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.wantsTextInput()
        if Runtime.state.screen == "options" then
            return Runtime.OptionsScreen.wantsTextInput()
        elseif Runtime.state.screen == "job_offer" and Runtime.JobOfferScreen.wantsTextInput then
            return Runtime.JobOfferScreen.wantsTextInput()
        elseif Runtime.state.screen == "computer" and Runtime.ComputerScreen.wantsTextInput then
            return Runtime.ComputerScreen.wantsTextInput()
        elseif Runtime.state.screen == "machine" and Runtime.MachineScreen.wantsTextInput then
            return Runtime.MachineScreen.wantsTextInput()
        elseif Runtime.state.screen == "lan" then
            return Runtime.LanScreen.wantsTextInput()
        elseif Runtime.state.screen == "direct" then
            return Runtime.DirectScreen.wantsTextInput()
        elseif Runtime.state.screen == "workshop_remote" then
            return Runtime.WorkshopRemoteScreen.wantsTextInput()
        end
        return false
    end

    Runtime.syncMobileKeyboard = function()
        if Runtime.mobileControls and Runtime.mobileControls:isEnabled() and love.keyboard.setTextInput then
            love.keyboard.setTextInput(Runtime.wantsTextInput())
        end
    end

    function Runtime.dispatchKeyPressed(key)
        if Runtime.state.screen == "options" then
            local result = Runtime.OptionsScreen.keypressed(key)
            Runtime.syncMobileKeyboard()
            return result
        elseif (key == "o" and not Runtime.wantsTextInput())
            or (key == "escape" and Runtime.state.screen == "world")
        then
            return Runtime.openOptions()
        elseif Runtime.state.screen == "lan" then
            local result = Runtime.LanScreen.keypressed(key)
            Runtime.syncMobileKeyboard()
            return result
        elseif Runtime.state.screen == "direct" then
            local result = Runtime.DirectScreen.keypressed(key)
            Runtime.syncMobileKeyboard()
            return result
        end
        if Runtime.state.screen == "world"
            and Runtime.MultiplayerHud.keypressed(key, Runtime.multiplayerHudInfo())
        then
            return true
        end
        if Runtime.state.screen == "world" and Runtime.multiplayer:isActive() then
            local consumed, message = Runtime.HighFiveUi.keypressed(key,
                Runtime.multiplayer:highFiveInfo(), Runtime.multiplayer)
            if consumed then
                if message then Runtime.state.message = tostring(message) end
                return true
            end
        end
        if Runtime.warehouseControls:keypressed(key) then return true end
        return Runtime.Input.keypressed(key, Runtime.inputContext)
    end

    function Runtime.primaryMobileAction()
        if Runtime.warehouseControls:ownsLift() then
            return "e",Runtime.state.forklift.carriedPalletId and "DROP" or "PICK UP"
        end
        local movingMachine = Runtime.state.cutter and Runtime.state.cutter.moving
            or Runtime.state.wrapper and Runtime.state.wrapper.moving or Runtime.state.windmill and Runtime.state.windmill.moving
        if movingMachine then
            local localPlayerId = tonumber(Runtime.World.player.id) or 1
            local ownsRelocation = Runtime.state.palletJack and Runtime.state.palletJack.operating
                and Runtime.state.palletJack.operatorPlayerId == localPlayerId
            if ownsRelocation then return "e", "PLACE" end
            return "e", "BUSY"
        end
        local selected = Runtime.World.getInteraction()
        if not selected then return "e", "USE" end
        if Runtime.multiplayer:isClient() and selected.kind ~= "loadingBayDoor"
            and selected.kind ~= "truckCargoDoor"
            and selected.kind ~= "palletWorkOrder"
            and selected.kind ~= "shopClock"
            and selected.kind ~= "jukebox"
            and selected.kind ~= "forklift" and selected.kind ~= "palletRack"
            and selected.kind ~= "breakroom"
            and not Runtime.World.workshopResourceId(selected.kind)
        then
            return "e", "HOST"
        end
        local jackLabel = "DRIVE"
        if Runtime.state.palletJack and Runtime.state.palletJack.operating then
            local localPlayerId = tonumber(Runtime.World.player.id) or 1
            if Runtime.state.palletJack.operatorPlayerId ~= localPlayerId then
                jackLabel = "BUSY"
            else
                local candidateId = Runtime.state.palletJack.candidatePalletId
                    or Runtime.World.networkPalletJackSnapshot(Runtime.state).candidatePalletId
                jackLabel = Runtime.state.palletJack.carriedPalletId and "LOWER"
                    or candidateId and "LIFT" or "PARK"
            end
        end
        local labels = {
            customer = "JOB", computer = "PC", shopClock = "CLOCK", jukebox = "RADIO", vendor = "TALK", loadingBayDoor = "DOOR",
            truckCargoDoor = "TRUCK", cutter = "CUTTER", skidWrapper = "WRAP",
            windmill = "PRESS", palletJack = jackLabel, palletWorkOrder = "VIEW",
            forklift = "DRIVE", palletRack = "SHELVES",
            breakroom = Runtime.World.player.resting and "STAND" or "REST",
        }
        return "e", labels[selected.kind] or "USE"
    end

    function Runtime.extraMobileActions()
        local actions = {}
        if Runtime.multiplayer:isClient() then
            local info = Runtime.multiplayer:workshopInfo()
            if info and info.resourceId == "pallet_jack" then
                local movingMachine = Runtime.state.cutter and Runtime.state.cutter.moving
                    or Runtime.state.wrapper and Runtime.state.wrapper.moving
                    or Runtime.state.windmill and Runtime.state.windmill.moving
                if movingMachine then
                    actions[#actions + 1] = { key = "q", label = "TURN" }
                else
                    local carryingPallet = Runtime.state.palletJack
                        and Runtime.state.palletJack.carriedPalletId ~= nil
                    if carryingPallet then
                        actions[#actions + 1] = { key = "l", label = "LOWER" }
                    else
                        actions[#actions + 1] = { key = "f", label = "PARK" }
                        local selected = Runtime.World.getInteraction()
                        local extraMachine = selected and selected.target
                            and selected.target.relocatable == false
                        local canRelocate = selected and (selected.kind == "cutter"
                            or selected.kind == "skidWrapper" or selected.kind == "windmill")
                            and not extraMachine
                        if not canRelocate and not extraMachine then
                            canRelocate = Runtime.World.cutterNearby and Runtime.World.cutterNearby(Runtime.state)
                                or Runtime.World.wrapperNearby and Runtime.World.wrapperNearby(Runtime.state)
                                or Runtime.World.windmillNearby and Runtime.World.windmillNearby(Runtime.state)
                        end
                        if canRelocate then
                            actions[#actions + 1] = { key = "m", label = "MOVE" }
                        end
                    end
                end
            end
            return actions
        end
        if Runtime.state.cutter and Runtime.state.cutter.moving or Runtime.state.wrapper and Runtime.state.wrapper.moving
            or Runtime.state.windmill and Runtime.state.windmill.moving
        then
            actions[#actions + 1] = { key = "q", label = "TURN" }
            return actions
        end
        if Runtime.state.palletJack and Runtime.state.palletJack.operating
            and Runtime.state.palletJack.operatorPlayerId == 1
        then
            local carryingPallet = Runtime.state.palletJack.carriedPalletId ~= nil
            if carryingPallet then
                actions[#actions + 1] = { key = "l", label = "LOWER" }
            else
                actions[#actions + 1] = { key = "f", label = "PARK" }
                local selected = Runtime.World.getInteraction()
                local extraMachine = selected and selected.target
                    and selected.target.relocatable == false
                local canRelocate = selected and (selected.kind == "cutter"
                    or selected.kind == "skidWrapper" or selected.kind == "windmill")
                    and not extraMachine
                if not canRelocate and not extraMachine then
                    canRelocate = Runtime.World.cutterNearby and Runtime.World.cutterNearby(Runtime.state)
                        or Runtime.World.wrapperNearby and Runtime.World.wrapperNearby(Runtime.state)
                        or Runtime.World.windmillNearby and Runtime.World.windmillNearby(Runtime.state)
                end
                if canRelocate then actions[#actions + 1] = { key = "m", label = "MOVE" } end
            end
        end
        return actions
    end
end

return Component
