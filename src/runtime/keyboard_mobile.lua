-- Keyboard routing and mobile actions.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

local function mobileActionLabel(Runtime, selected)
    if not selected then return "" end
    local kind = selected.kind
    local target = selected.target or {}
    if kind == "applicant" then return target.actionLabel or "TALK" end
    if kind == "workPhone" then
        return target.actionLabel or (Runtime.state.workPhone and Runtime.state.workPhone.incoming
            and "ANSWER" or "PHONE")
    end
    if kind == "loadingBayDoor" then
        if target.doorState == "closed" then return "OPEN" end
        if target.doorState == "open" then return "CLOSE" end
        return "WAIT"
    end
    if kind == "truckCargoDoor" then
        if target.truckState == "parked_closed" then
            return target.truckMode == "machine_delivery" and "MANIFEST" or "OPEN"
        end
        if target.truckState == "cargo_open" then return "INVENTORY" end
        return "WAIT"
    end
    if kind == "customer" then
        return target.customerState == "reviewing" and "REVIEW" or "TALK"
    end
    if kind == "shopEntrance" then
        return require("src.shop_rooms").scene(Runtime.World.player) == "warehouse"
            and "ROOMS" or "EXIT"
    end
    if kind == "roomGame" then return target.ball and "PICK UP" or "PLAY" end
    if kind == "roomRest" or kind == "breakroom" then
        return Runtime.World.player.resting and "STAND" or "REST"
    end
    if kind == "palletJack" then
        local jack = target.jackState
        if not jack or not jack.operating then return "DRIVE" end
        if not target.ownsJack then return "BUSY" end
        if jack.carriedPalletId then return "LOWER" end
        return target.candidatePalletId and "LIFT" or "PARK"
    end
    if kind == "forklift" then
        local lift = Runtime.state.forklift
        local playerId = tonumber(Runtime.World.player.id) or 1
        return lift and lift.operating and lift.operatorPlayerId ~= playerId
            and "BUSY" or "DRIVE"
    end
    local labels = {
        computer = "OPEN", shopClock = "CHECK", vendor = "TALK",
        cutter = "OPERATE", skidWrapper = "WRAP", windmill = "PRINT",
        palletWorkOrder = "READ", palletRack = "STOCK",
        roomStock = "STOCK",
    }
    return target.actionLabel or labels[kind] or ""
end

function Component.install(Runtime)
    local mobileTextInputState

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
        local enabled = Runtime.mobileControls and Runtime.mobileControls:isEnabled()
        if not enabled then
            if mobileTextInputState == true and type(love.keyboard.setTextInput) == "function" then
                love.keyboard.setTextInput(false)
                mobileTextInputState = false
            end
            return
        end
        local wantsTextInput = Runtime.wantsTextInput() == true
        if type(love.keyboard.setTextInput) == "function"
            and mobileTextInputState ~= wantsTextInput
        then
            love.keyboard.setTextInput(wantsTextInput)
            mobileTextInputState = wantsTextInput
        end
    end

    Runtime.invalidateMobileKeyboardState = function()
        mobileTextInputState = nil
    end

    function Runtime.dispatchKeyPressed(key)
        if Runtime.state.screen=="air_hockey" then
            return require("src.screens.air_hockey_screen").keypressed(Runtime,key)
        end
        if Runtime.state.screen=="critter_kombat" then
            return require("src.screens.critter_kombat_screen").keypressed(Runtime,key)
        end
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
        if require("src.shop_room_controls").keypressed(key,Runtime) then return true end
        if Runtime.warehouseControls:keypressed(key) then return true end
        return Runtime.Input.keypressed(key, Runtime.inputContext)
    end

    function Runtime.primaryMobileAction()
        if Runtime.state.screen=="world" and require("src.basketball").heldBy(
            Runtime.state,tonumber(Runtime.World.player.id) or 1) then
            return "space","SHOOT"
        end
        if require("src.shop_rooms").scene(Runtime.World.player)~="warehouse" then
            local selected=Runtime.World.getInteraction()
            return "e",mobileActionLabel(Runtime,selected)
        end
        if Runtime.warehouseControls:ownsLift() then
            return "e",Runtime.state.forklift.carriedPalletId and "DROP" or "PICK UP"
        end
        local movingMachine = Runtime.World.movingMachine(Runtime.state)
        if movingMachine then
            local localPlayerId = tonumber(Runtime.World.player.id) or 1
            local ownsRelocation = Runtime.state.palletJack and Runtime.state.palletJack.operating
                and Runtime.state.palletJack.operatorPlayerId == localPlayerId
            if ownsRelocation then return "e", "PLACE" end
            return "e", "BUSY"
        end
        local pickup = Runtime.World.palletPickupSnapshot(Runtime.state)
        if pickup.selected then return "l", "LIFT" end
        local selected = Runtime.World.getInteraction()
        if not selected then return "e", "" end
        if Runtime.multiplayer:isClient() and selected.kind ~= "loadingBayDoor"
            and selected.kind ~= "truckCargoDoor"
            and selected.kind ~= "palletWorkOrder"
            and selected.kind ~= "shopClock"
            and selected.kind ~= "forklift" and selected.kind ~= "palletRack"
            and selected.kind ~= "breakroom"
            and selected.kind ~= "shopEntrance" and selected.kind ~= "roomStock" and selected.kind ~= "roomRest"
            and selected.kind ~= "roomGame"
            and not Runtime.World.workshopResourceId(selected.kind)
        then
            return "e", "HOST"
        end
        return "e", mobileActionLabel(Runtime,selected)
    end

    function Runtime.extraMobileActions()
        local actions = {}
        if require("src.basketball").heldBy(Runtime.state,tonumber(Runtime.World.player.id) or 1) then
            actions[#actions+1]={key="q",label="DROP"}
        end
        local Rooms = require("src.shop_rooms")
        local sceneId = Rooms.scene(Runtime.World.player)
        if sceneId ~= "warehouse" and not Rooms.machineRoomAllowed(Runtime.state, sceneId) then return actions end
        local selected=Runtime.World.getInteraction()
        if selected and selected.kind=="applicant" and not Runtime.multiplayer:isClient() then
            actions[#actions+1]={key="x",label="DISMISS"}
        end
        if Runtime.multiplayer:isClient() then
            local info = Runtime.multiplayer:workshopInfo()
            if info and info.resourceId == "pallet_jack" then
                local movingMachine = Runtime.World.movingMachine(Runtime.state)
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
                        local canRelocate = selected and (selected.kind == "cutter"
                            or selected.kind == "skidWrapper" or selected.kind == "windmill")
                        canRelocate = canRelocate or Runtime.World.nearbyMachineMove(Runtime.state) ~= nil
                        if canRelocate then
                            actions[#actions + 1] = { key = "m", label = "MOVE" }
                        end
                    end
                end
            end
            return actions
        end
        if Runtime.World.movingMachine(Runtime.state)
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
                local canRelocate = selected and (selected.kind == "cutter"
                    or selected.kind == "skidWrapper" or selected.kind == "windmill")
                canRelocate = canRelocate or Runtime.World.nearbyMachineMove(Runtime.state) ~= nil
                if canRelocate then actions[#actions + 1] = { key = "m", label = "MOVE" } end
            end
        end
        return actions
    end
end

return Component
