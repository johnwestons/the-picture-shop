local Input = {}
local mobileMovementProvider = nil

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
                if math.abs(axisX) < 0.20 then axisX = 0 end
                if math.abs(axisY) < 0.20 then axisY = 0 end
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
    else
        state.message = "Back on the warehouse floor."
    end
    state.screen = "world"
    context.saveCurrent()
    return true
end

function Input.keypressed(key, context)
    local state = context.state
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
        if key == "m" and ((selected and selected.kind == "cutter")
            or (context.world.cutterNearby and context.world.cutterNearby(state)))
        then
            if context.world.beginCutterMove(state) then context.saveCurrent() end
            return
        end
        if key == "m" and ((selected and selected.kind == "skidWrapper") or context.world.wrapperNearby(state)) then
            if context.world.beginWrapperMove(state) then context.saveCurrent() end
            return
        end
        if key == "m" and ((selected and selected.kind == "windmill")
            or (context.world.windmillNearby and context.world.windmillNearby(state)))
        then
            if context.world.beginWindmillMove(state) then context.saveCurrent() end
            return
        end
        if key == "q" and ((state.cutter and state.cutter.moving)
            or (selected and selected.kind == "cutter"))
        then
            if context.world.rotateCutter(state) then context.saveCurrent() end
            return
        end
        if key == "q" and ((state.wrapper and state.wrapper.moving)
            or (selected and selected.kind == "skidWrapper"))
        then
            if context.world.rotateWrapper(state) then context.saveCurrent() end
            return
        end
        if key == "q" and ((state.windmill and state.windmill.moving)
            or (selected and selected.kind == "windmill"))
        then
            if context.world.rotateWindmill(state) then context.saveCurrent() end
            return
        end
        if key == "f" then
            if context.world.parkPalletJack(state) then context.saveCurrent() end
            return
        end
        if key ~= "e" then return end
        if state.cutter and state.cutter.moving then
            if context.world.placeCutter(state, context.assets) then context.saveCurrent() end
        elseif state.wrapper and state.wrapper.moving then
            if context.world.placeWrapper(state, context.assets) then context.saveCurrent() end
        elseif state.windmill and state.windmill.moving then
            if context.world.placeWindmill(state, context.assets) then context.saveCurrent() end
        elseif selected and selected.kind == "customer" then
            local offer, errors = context.jobService.createNextOffer(state, os.time())
            if not offer then
                state.message = "Could not prepare the job: " .. table.concat(errors or {}, "; ")
            elseif context.world.beginCustomerReview() then
                state.currentOffer = offer
                if context.jobOfferScreen.enter then context.jobOfferScreen.enter(offer) end
                state.screen = "job_offer"
                state.message = "Review the paperwork and choose Accept or Decline."
            end
        elseif selected and selected.kind == "computer" then
            context.computerScreen.enter(state)
            state.screen = "computer"
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
            context.machine.reset(state)
            context.machineScreen.enter()
            state.machineType = "cutter"
            state.screen = "machine"
        elseif selected and selected.kind == "skidWrapper" then
            context.wrapper.reset(state)
            context.machineScreen.enter()
            state.machineType = "skid_wrapper"
            state.screen = "machine"
        elseif selected and selected.kind == "windmill" then
            context.windmill.ensure(state)
            context.pressScreen.enter(state)
            state.screen = "press"
        elseif selected and selected.kind == "palletJack" then
            if context.world.handlePalletJack(state, context.assets) then context.saveCurrent() end
        end
    elseif state.screen == "machine" then
        if state.machineType == "skid_wrapper" and key == "m" then
            if context.world.beginWrapperMove(state) then
                state.screen = "world"
                context.saveCurrent()
            end
            return true
        end
        if state.machineType == "skid_wrapper" and context.wrapper.keypressed(key, state) then return end
        if context.machineScreen.keypressed(state, key) then return end
        if context.machine.keypressed(key, state) then context.machineScreen.syncGauge() end
    elseif state.screen == "computer" then
        return context.computerScreen.keypressed(state, key)
    elseif state.screen == "job_offer" then
        return context.jobOfferScreen.keypressed(key)
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
        if context.world.selectPlacement(state, context.assets, worldX, worldY) then
            return true
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
        end
        return result
    end
    if state.screen == "press" then
        local result = context.pressScreen.mousepressed(state, x, y, button)
        if type(result) == "table" and result.action == "exit" then return Input.closeScreen(context) end
        if result then context.saveCurrent() end
        return result
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
            or result.action == "promotion_sent"
            or result.action == "service_notice_dismissed"
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
    if state.screen ~= "job_offer" or button ~= 1 then return false end
    local action = context.jobOfferScreen.hitTest(x, y)
    if action ~= "quote_input" and context.jobOfferScreen.blurQuote then
        context.jobOfferScreen.blurQuote()
    end
    if not action then return false end

    if action == "back" then
        return Input.closeScreen(context)
    end
    if action == "quote_input" then
        context.jobOfferScreen.focusQuote()
        return true
    end

    local job = state.currentOffer
    if not job then
        state.message = "The customer paperwork is missing."
        return false
    end

    local timestamp = os.time()
    local succeeded, errorMessage
    local quoteResult
    if action == "accept" then
        succeeded, quoteResult = context.jobService.submitQuote(
            state, job, context.jobOfferScreen.quoteAmount(), timestamp)
        errorMessage = quoteResult
    else
        succeeded, errorMessage = context.jobService.declineOffer(state, job, timestamp)
    end
    if not succeeded then
        state.message = "Could not " .. action .. " the job: " .. tostring(errorMessage)
        return false
    end

    local accepted = action == "accept" and quoteResult.accepted
    context.world.resolveCustomer(accepted and "accepted" or "declined", state)
    state.currentOffer = nil
    state.screen = "world"
    if action == "accept" then
        state.message = quoteResult.accepted
            and string.format("%s accepted your $%d quote. %s.", job.company, quoteResult.amount,
                context.jobService.deliverySummary(job, state))
            or string.format("%s declined your $%d quote. The customer is leaving.",
                job.company, quoteResult.amount)
    else
        state.message = string.format("Declined %s. The customer is leaving.", job.id)
    end
    context.saveCurrent()
    return true
end

function Input.wheelmoved(x, y, context)
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
