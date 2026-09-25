local Input = {}
local mobileMovementProvider = nil

local function radialDeadzone(x, y, deadzone)
    local magnitude = math.sqrt(x * x + y * y)
    if magnitude <= deadzone then return 0, 0 end
    local strength = math.min(1, (magnitude - deadzone) / (1 - deadzone))
    return x / magnitude * strength, y / magnitude * strength
end

function Input.setMobileMovementProvider(provider)
    mobileMovementProvider = provider
end

function Input.movement()
    local x, y = 0, 0
    if love.keyboard.isDown("a", "left") then x = x - 1 end
    if love.keyboard.isDown("d", "right") then x = x + 1 end
    if love.keyboard.isDown("w", "up") then y = y - 1 end
    if love.keyboard.isDown("s", "down") then y = y + 1 end
    if love.joystick and love.joystick.getJoysticks then
        for _, joystick in ipairs(love.joystick.getJoysticks()) do
            if joystick:isGamepad() then
                local axisX = joystick:getGamepadAxis("leftx") or 0
                local axisY = joystick:getGamepadAxis("lefty") or 0
                axisX, axisY = radialDeadzone(axisX, axisY, 0.20)
                if joystick:isGamepadDown("dpleft") then axisX = -1 end
                if joystick:isGamepadDown("dpright") then axisX = 1 end
                if joystick:isGamepadDown("dpup") then axisY = -1 end
                if joystick:isGamepadDown("dpdown") then axisY = 1 end
                if axisX ~= 0 or axisY ~= 0 then x, y = axisX, axisY end
                break
            end
        end
    end
    if mobileMovementProvider then
        local mobileX, mobileY = mobileMovementProvider()
        if mobileX ~= 0 or mobileY ~= 0 then x, y = mobileX, mobileY end
    end
    return x, y
end

function Input.closeScreen(context)
    local state = context.state
    if state.screen == "world" or state.screen == "title" then return false end
    local readOnlyScreen = state.screen == "pallet_work_order"
    if state.screen == "workshop_remote" then
        if context.workshopRemoteScreen and not context.workshopRemoteScreen.canClose() then
            state.message = "Wait for the host device to finish the current workshop action."
            return true
        end
        if context.releaseWorkshopInteraction then context.releaseWorkshopInteraction("closed") end
        if context.workshopRemoteScreen then context.workshopRemoteScreen.clear() end
        state.screen = "world"
        state.message = "Remote workshop console closed."
        return true
    end
    if state.screen == "machine" and state.machineType == "skid_wrapper"
        and not context.wrapper.canExit(state)
    then
        return true
    end
    if state.screen == "press" and context.windmill and not context.windmill.canExit(state) then
        state.message = "Stop Windmill production before leaving the console."
        return true
    end

    if state.screen == "job_offer" then
        context.world.cancelCustomerReview(state)
        state.currentOffer = nil
    elseif state.screen == "vendor" then
        context.world.cancelVendorReview(state)
    elseif state.screen == "truck_inventory" then
        state.message = "Truck inventory closed. The cargo door remains open."
    elseif state.screen == "machine" then
        state.message = "Exited the machine console."
    elseif state.screen == "computer" then
        state.message = "Office computer closed."
    elseif state.screen == "work_phone" then
        state.message = "Wall phone returned to its cradle."
    else
        state.message = "Back on the warehouse floor."
    end
    if context.releaseWorkshopInteraction
        and (state.screen == "job_offer" or state.screen == "computer"
            or state.screen == "work_phone"
            or state.screen == "vendor"
            or state.screen == "truck_inventory"
            or state.screen == "press"
            or (state.screen == "machine"
                and (state.machineType == "skid_wrapper" or state.machineType == "cutter")))
    then
        context.releaseWorkshopInteraction("closed")
    end
    state.screen = "world"
    if state.machineId then
        if context.machine.select then context.machine.select(nil) end
        if context.wrapper.select then context.wrapper.select(nil) end
        state.machineId = nil
    end
    if not readOnlyScreen then context.saveCurrent() end
    return true
end

function Input.keypressed(key, context)
    local state = context.state
    if key=="escape" and state.screen=="workshop_remote" and context.workshopRemoteScreen.hasMachineModal
        and context.workshopRemoteScreen.hasMachineModal() then
        return context.workshopRemoteScreen.keypressed(key,state,context.requestWorkshopCommand)
    end
    if key == "escape" and state.screen == "machine"
        and context.machineScreen.hasModal and context.machineScreen.hasModal()
    then
        return context.machineScreen.keypressed(state, key)
    end
    if key == "escape" and state.screen ~= "world" and state.screen ~= "title" then
        return Input.closeScreen(context)
    end

    if state.screen == "title" then
        return context.title.keypressed(key)
    elseif state.screen == "world" then
        local selected = context.world.getInteraction()
        if (key == "m" or key == "q") and selected and selected.target
            and selected.target.relocatable == false then
            state.message = "This extra machine is fixed at its assigned floor position."
            return true
        end
        local networkClient = context.isNetworkClient and context.isNetworkClient()
        local movingMachine = state.cutter and state.cutter.moving
            or state.wrapper and state.wrapper.moving
            or state.windmill and state.windmill.moving
        local networkPlayerId = context.world and context.world.player
            and tonumber(context.world.player.id)
        local localPlayerId = networkPlayerId or 1
        local ownsPalletJack = state.palletJack and state.palletJack.operating
            and state.palletJack.operatorPlayerId == localPlayerId
        local ownsNetworkRelocation = networkClient and movingMachine
            and networkPlayerId and networkPlayerId >= 2
            and state.palletJack and state.palletJack.operating
            and state.palletJack.operatorPlayerId == networkPlayerId
        local relocationTarget = selected
        if networkClient and key == "m" and not (relocationTarget
            and (relocationTarget.kind == "cutter"
                or relocationTarget.kind == "skidWrapper"
                or relocationTarget.kind == "windmill"))
        then
            if context.world.cutterNearby and context.world.cutterNearby(state) then
                relocationTarget = { kind = "cutter" }
            elseif context.world.wrapperNearby and context.world.wrapperNearby(state) then
                relocationTarget = { kind = "skidWrapper" }
            elseif context.world.windmillNearby and context.world.windmillNearby(state) then
                relocationTarget = { kind = "windmill" }
            end
        end
        if networkClient and key == "m" and relocationTarget
            and (relocationTarget.kind == "cutter"
                or relocationTarget.kind == "skidWrapper"
                or relocationTarget.kind == "windmill")
        then
            return context.palletJackControl
                and context.palletJackControl("move_machine", relocationTarget)
        end
        if networkClient and key == "q" then
            if ownsNetworkRelocation and context.palletJackControl then
                return context.palletJackControl("rotate_machine", selected)
            end
            state.message = movingMachine
                and "Only the worker operating this pallet jack can rotate the machine."
                or "Acquire the pallet jack and attach the machine before rotating it."
            return true
        end
        if not networkClient and key == "q" and movingMachine
            and state.palletJack and state.palletJack.operating
            and state.palletJack.operatorPlayerId ~= 1
        then
            state.message = "Only the worker operating this pallet jack can rotate the machine."
            return true
        end
        if key == "m" and ((selected and selected.kind == "cutter")
            or (context.world.cutterNearby and context.world.cutterNearby(state)))
        then
            local occupied = context.cutterControlOccupied and context.cutterControlOccupied()
            if context.world.beginCutterMove(state, occupied) then context.saveCurrent() end
            return
        end
        if key == "m" and ((selected and selected.kind == "skidWrapper") or context.world.wrapperNearby(state)) then
            local occupied = context.wrapperControlOccupied and context.wrapperControlOccupied()
            if context.world.beginWrapperMove(state, occupied) then context.saveCurrent() end
            return
        end
        if key == "m" and ((selected and selected.kind == "windmill")
            or (context.world.windmillNearby and context.world.windmillNearby(state)))
        then
            local occupied = context.windmillControlOccupied and context.windmillControlOccupied()
            if context.world.beginWindmillMove(state, occupied) then context.saveCurrent() end
            return
        end
        if key == "q" and ((state.cutter and state.cutter.moving)
            or (selected and selected.kind == "cutter"))
        then
            if context.cutterControlOccupied and context.cutterControlOccupied() then
                state.message = "Close the active cutter console before rotating the machine."
                return true
            end
            local occupied = context.cutterControlOccupied and context.cutterControlOccupied()
            if context.world.rotateCutter(state, occupied) then context.saveCurrent() end
            return
        end
        if key == "q" and ((state.wrapper and state.wrapper.moving)
            or (selected and selected.kind == "skidWrapper"))
        then
            local occupied = context.wrapperControlOccupied and context.wrapperControlOccupied()
            if context.world.rotateWrapper(state, occupied) then context.saveCurrent() end
            return
        end
        if key == "q" and ((state.windmill and state.windmill.moving)
            or (selected and selected.kind == "windmill"))
        then
            local occupied = context.windmillControlOccupied and context.windmillControlOccupied()
            if context.world.rotateWindmill(state, occupied) then context.saveCurrent() end
            return
        end
        if key == "f" then
            if context.palletJackControl
                and context.palletJackControl("park", selected)
            then
                return true
            end
            if context.world.parkPalletJack(state) then context.saveCurrent() end
            return
        end
        -- L is the dedicated fork control. Keeping it separate from E lets a
        -- worker use every ordinary shop interaction while pushing the jack.
        if key == "l" and ownsPalletJack then
            if context.palletJackControl
                and context.palletJackControl("use", selected)
            then
                return true
            end
            if context.world.handlePalletJack(state, context.assets) then
                context.saveCurrent()
            end
            return true
        end
        if key ~= "e" then return end
        if context.world.faceInteraction then context.world.faceInteraction() end
        if ownsNetworkRelocation and context.palletJackControl then
            return context.palletJackControl("place_machine", selected)
        end
        -- On the authoritative host, a moving machine owns E until it is
        -- placed. Network observers cannot place that machine, so their E
        -- press must continue to the unrelated interaction they selected.
        -- Host pallet-jack command routing must never park or load the jack
        -- while equipment is still attached to it.
        local observesNetworkRelocation = networkClient
        if not observesNetworkRelocation and movingMachine
            and state.palletJack and state.palletJack.operating
            and state.palletJack.operatorPlayerId ~= 1
        then
            state.message = "Only the worker operating this pallet jack can place the machine."
            return true
        end
        if not observesNetworkRelocation and state.cutter and state.cutter.moving then
            if context.world.placeCutter(state, context.assets) then context.saveCurrent() end
            return true
        elseif not observesNetworkRelocation and state.wrapper and state.wrapper.moving then
            if context.world.placeWrapper(state, context.assets) then context.saveCurrent() end
            return true
        elseif not observesNetworkRelocation and state.windmill and state.windmill.moving then
            if context.world.placeWindmill(state, context.assets) then context.saveCurrent() end
            return true
        end
        if selected and selected.kind == "palletWorkOrder" then
            -- Pallet paperwork is already part of the host-authored shared
            -- shop snapshot. Inspecting it stays a normal USE action even
            -- while the worker is pushing an empty pallet jack.
            context.palletWorkOrderScreen.enter(selected.target and selected.target.item)
            state.screen = "pallet_work_order"
            state.message = "Inspecting the paper work order attached to the pallet."
            return true
        end
        if selected and selected.kind == "palletJack"
            and context.palletJackControl
            and context.palletJackControl("use", selected)
        then
            return true
        end
        if context.networkInteraction and context.networkInteraction(selected) then return true end
        if selected and selected.kind == "customer" then
            local offer, errors = context.jobService.createNextOffer(state, os.time())
            if not offer then
                state.message = "Could not prepare the job: " .. table.concat(errors or {}, "; ")
                if context.releaseWorkshopInteraction then
                    context.releaseWorkshopInteraction("cancelled")
                end
            elseif context.world.beginCustomerReview() then
                state.currentOffer = offer
                if context.jobOfferScreen.enter then context.jobOfferScreen.enter(offer) end
                state.screen = "job_offer"
                state.message = "Review the paperwork and choose Accept or Decline."
            elseif context.releaseWorkshopInteraction then
                context.releaseWorkshopInteraction("cancelled")
            end
        elseif selected and selected.kind == "computer" then
            context.computerScreen.enter(state)
            state.screen = "computer"
        elseif selected and selected.kind == "workPhone" then
            context.workPhoneScreen.enter(state)
            state.screen = "work_phone"
        elseif selected and selected.kind == "vendor" then
            if context.world.beginVendorReview() then
                state.screen = "vendor"
                state.message = "Review the salesperson's pallet-delivery catalog."
            end
        elseif selected and selected.kind == "loadingBayDoor" then
            context.world.toggleBayDoor(state)
        elseif selected and selected.kind == "truckCargoDoor" then
            local truck = context.world.truckSnapshot()
            if truck.mode == "machine_delivery" and context.world.openTruckInventory(state) then
                state.screen = "truck_inventory"
                state.message = "Review the flatbed manifest and unload the machine."
            elseif truck.state == "cargo_open"
                and context.world.openTruckInventory(state)
            then
                state.screen = "truck_inventory"
                state.message = truck.mode == "pickup"
                    and "Review the outbound manifest and load each wrapped pallet."
                    or "Review the inbound manifest and unload each pallet."
            else
                context.world.toggleTruckCargoDoor(state)
            end
        elseif selected and selected.kind == "cutter" then
            state.machineId = selected.target and selected.target.machineId
            state.machineType = "cutter"
            state.screen = "machine"
            if context.machine.select then context.machine.select(state.machineId, state) end
            context.machine.open(state)
            context.machineScreen.enter()
        elseif selected and selected.kind == "skidWrapper" then
            state.machineId = selected.target and selected.target.machineId
            state.machineType = "skid_wrapper"
            state.screen = "machine"
            if context.wrapper.select then context.wrapper.select(state.machineId, state) end
            context.wrapper.reset(state)
            context.machineScreen.enter()
        elseif selected and selected.kind == "windmill" then
            state.machineId = selected.target and selected.target.machineId
            state.screen = "press"
            context.windmill.ensure(state)
            context.pressScreen.enter(state)
        elseif selected and selected.kind == "palletJack" then
            if context.world.handlePalletJack(state, context.assets) then context.saveCurrent() end
        end
    elseif state.screen == "machine" then
        if state.machineType == "skid_wrapper" and key == "m" then
            for _, item in ipairs(state.machines and state.machines.items or {}) do
                if item.id == state.machineId and item.world then
                    state.message = "This extra wrapper is fixed at its assigned floor position."
                    return true
                end
            end
            local occupied = context.wrapperControlOccupied and context.wrapperControlOccupied()
            if context.world.beginWrapperMove(state, occupied) then
                state.screen = "world"
                state.machineId = nil
                if context.wrapper.select then context.wrapper.select(nil) end
                if context.releaseWorkshopInteraction then
                    context.releaseWorkshopInteraction("closed")
                end
                context.saveCurrent()
            end
            return true
        end
        if state.machineType == "skid_wrapper" and context.wrapper.keypressed(key, state) then return end
        if context.machineScreen.keypressed(state, key) then
            if state.machineType == "cutter" then context.saveCurrent() end
            return
        end
        if context.machine.keypressed(key, state) then
            context.machineScreen.syncGauge()
            if state.machineType == "cutter" then context.saveCurrent() end
        end
    elseif state.screen == "computer" then
        return context.computerScreen.keypressed(state, key)
    elseif state.screen == "pallet_work_order" then
        return false
    elseif state.screen == "job_offer" then
        return context.jobOfferScreen.keypressed(key)
    elseif state.screen == "workshop_remote" then
        return context.workshopRemoteScreen.keypressed(
            key, state, context.requestWorkshopCommand)
    elseif state.screen == "press" then
        local result, errorMessage = context.pressScreen.keypressed(state, key)
        if type(result) == "table" and result.action == "exit" then return Input.closeScreen(context) end
        if result == false and type(errorMessage) == "string" then state.message = errorMessage end
        if result then context.saveCurrent() end
        return result, errorMessage
    end
end

function Input.textinput(text, context)
    if context.state.screen == "machine" then
        return context.machineScreen.textinput(context.state, text)
    elseif context.state.screen == "computer" then
        return context.computerScreen.textinput(context.state, text)
    elseif context.state.screen == "job_offer" then
        return context.jobOfferScreen.textinput(text)
    elseif context.state.screen == "workshop_remote" then
        return context.workshopRemoteScreen.textinput(text)
    end
    return false
end

function Input.mousepressed(x, y, button, context)
    local state = context.state
    if state.screen == "title" then
        return context.title.mousepressed(x, y, button)
    end
    if state.screen == "world" and button == 1 and context.hud.hitTest(x, y) == "exit" then
        context.returnToTitle()
        return true
    end
    if state.screen == "world" and button == 1 then
        local worldX, worldY = x, y
        if context.worldPointerCoordinates then
            worldX, worldY = context.worldPointerCoordinates(x, y)
        end
        local networkReadOnly = context.isNetworkClient and context.isNetworkClient()
        if context.world.selectPlacement(
            state, context.assets, worldX, worldY, networkReadOnly)
        then
            return true
        end
        local tappedPallet = context.world.palletAt
            and context.world.palletAt(state, worldX, worldY)
        local localPlayerId = context.world and context.world.player
            and tonumber(context.world.player.id) or 1
        local ownsPalletJack = state.palletJack and state.palletJack.operating
            and state.palletJack.operatorPlayerId == localPlayerId
        if tappedPallet and ownsPalletJack
            and not state.palletJack.carriedPalletId
        then
            local palletSelection = {
                kind = "palletWorkOrder",
                hovered = true,
                target = { item = tappedPallet },
            }
            if context.palletJackControl
                and context.palletJackControl("lift", palletSelection)
            then
                return true
            end
            if context.world.handlePalletJack(
                state, context.assets, tappedPallet.pallet.id)
            then
                context.saveCurrent()
            end
            -- A tap on a skid is an explicit fork request while operating the
            -- jack, even if it is too far away. Consume it so it cannot open
            -- paperwork after displaying the distance error.
            return true
        end
        local selected = context.world.interactionAt
            and context.world.interactionAt(worldX, worldY, networkReadOnly)
            or context.world.getInteraction()
        if selected and selected.hovered then
            return Input.keypressed("e", context)
        end
    end
    if state.screen == "vendor" then
        local result = context.vendorScreen.mousepressed(state, x, y, button)
        if not result then return false end
        if result.action == "close" then
            return Input.closeScreen(context)
        elseif result.action == "no_thanks" then
            if context.world.resolveVendor(state, "declined") then
                state.screen = "world"
                context.saveCurrent()
            end
            if context.releaseWorkshopInteraction then
                context.releaseWorkshopInteraction("closed")
            end
            return true
        end
        if result.action ~= "blocked" then context.saveCurrent() end
        return true
    end
    if state.screen == "truck_inventory" then
        local result = context.truckInventoryScreen.mousepressed(state, context.world, x, y, button)
        if not result then return false end
        if result.action == "close" then
            return Input.closeScreen(context)
        elseif result.action == "door_closing" or result.action == "truck_departing" then
            if context.releaseWorkshopInteraction then
                context.releaseWorkshopInteraction("closed")
            end
            state.screen = "world"
        end
        if result.action ~= "blocked" then context.saveCurrent() end
        return true
    end
    if state.screen == "machine" then
        local result = context.machineScreen.mousepressed(state, x, y, button)
        if type(result) == "table" and result.action == "exit" then
            Input.closeScreen(context)
            return true
        end
        if type(result) == "table" and (result.action == "maintenance_completed"
            or result.action == "blade_sleeved" or result.action == "technician_booked"
            or result.action == "technician_schedule")
        then
            context.saveCurrent()
        elseif result and state.machineType == "cutter" then
            context.saveCurrent()
        end
        return result
    end
    if state.screen == "press" then
        local result = context.pressScreen.mousepressed(state, x, y, button)
        if type(result) == "table" and result.action == "exit" then return Input.closeScreen(context) end
        if result then context.saveCurrent() end
        return result
    end
    if state.screen == "workshop_remote" then
        local result = context.workshopRemoteScreen.mousepressed(state, x, y, button,
            context.requestWorkshopCommand)
        if type(result) == "table" and result.action == "close" then
            return Input.closeScreen(context)
        end
        return result
    end
    if state.screen == "work_phone" then
        local result = context.workPhoneScreen.mousepressed(state, x, y, button)
        if not result then return false end
        if result.action == "close" then return Input.closeScreen(context) end
        if result.action ~= "blocked" then context.saveCurrent() end
        return true
    end
    if state.screen == "computer" then
        local result = context.computerScreen.mousepressed(state, x, y, button)
        if not result then return false end
        if result.action == "close" then
            return Input.closeScreen(context)
        elseif result.action == "supply_order" or result.action == "bill_paid"
            or result.action == "machine_bought" or result.action == "machine_ordered"
            or result.action == "machine_sold"
            or result.action == "email_accepted" or result.action == "email_declined"
            or result.action == "quote_accepted" or result.action == "quote_rejected"
            or result.action == "estimate_sent"
            or result.action == "promotion_sent"
            or result.action == "service_notice_dismissed"
            or result.action == "inbox_notice_dismissed"
            or result.action == "cart_checked_out"
        then
            context.saveCurrent()
        elseif result.action == "completion_blocked" then
            state.message = "Every pallet must be cut, packaged, and stretch-wrapped before completion."
        elseif result.action == "pickup_ready" then
            local scheduled, jobOrError = context.jobService.requestPickup(state, result.job, os.time())
            if scheduled then
                state.message = result.job.id .. " is ready. Customer pickup is awaiting a truck."
                context.saveCurrent()
            else
                state.message = "Could not schedule pickup: " .. tostring(jobOrError)
            end
        end
        return true
    end
    if state.screen == "pallet_work_order" then
        local result = context.palletWorkOrderScreen.mousepressed(x, y, button)
        if result and result.action == "close" then return Input.closeScreen(context) end
        return result or false
    end
    if state.screen ~= "job_offer" or button ~= 1 then return false end
    local action = context.jobOfferScreen.hitTest(x, y)
    if not action then return false end

    if action == "back" then
        return Input.closeScreen(context)
    end
    local job = state.currentOffer
    if not job then
        state.message = "The customer paperwork is missing."
        return false
    end

    local succeeded, emailOrError = context.jobService.requestEstimateDetails(state, job, os.time())
    if not succeeded then
        state.message = "Could not request the written job details: " .. tostring(emailOrError)
        return false
    end

    context.world.resolveCustomer("accepted", state)
    state.currentOffer = nil
    state.screen = "world"
    if context.releaseWorkshopInteraction then context.releaseWorkshopInteraction("closed") end
    state.message = string.format("%s will email the written details for %s. No estimate has been sent yet.",
        job.company, job.id)
    context.saveCurrent()
    return true
end

function Input.wheelmoved(x, y, context)
    if context.state.screen == "workshop_remote" and context.workshopRemoteScreen.wheelmoved then
        return context.workshopRemoteScreen.wheelmoved(context.state, x, y)
    end
    if context.state.screen == "computer" and context.computerScreen.wheelmoved then
        return context.computerScreen.wheelmoved(context.state, x, y)
    end
    return false
end

function Input.mousereleased(x, y, button, context)
    if context.state.screen == "title" then
        context.title.mousereleased(x, y, button)
        return true
    end
    if context.state.screen == "machine" then
        return context.machineScreen.mousereleased(context.state, x, y, button)
    end
    return false
end

function Input.mousemoved(x, y, context)
    if context.state.screen == "title" then
        context.title.setHover(x, y)
        return true
    end
    return false
end

function Input.keyreleased(key, context)
    if context.state.screen == "machine" then
        context.machine.keyreleased(key)
    end
end

return Input
