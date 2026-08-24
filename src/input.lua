local Input = {}

function Input.movement()
    local x, y = 0, 0
    if love.keyboard.isDown("a", "left") then x = x - 1 end
    if love.keyboard.isDown("d", "right") then x = x + 1 end
    if love.keyboard.isDown("w", "up") then y = y - 1 end
    if love.keyboard.isDown("s", "down") then y = y + 1 end
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
        if key == "m" and selected and selected.kind == "cutter" then
            if context.world.beginCutterMove(state) then context.saveCurrent() end
            return
        end
        if key == "m" and ((selected and selected.kind == "skidWrapper") or context.world.wrapperNearby(state)) then
            if context.world.beginWrapperMove(state) then context.saveCurrent() end
            return
        end
        if key == "q" and selected and selected.kind == "cutter" then
            if context.world.rotateCutter(state) then context.saveCurrent() end
            return
        end
        if key == "q" and selected and selected.kind == "skidWrapper" then
            if context.world.rotateWrapper(state) then context.saveCurrent() end
            return
        end
        if key == "f" then
            if context.world.parkPalletJack(state) then context.saveCurrent() end
            return
        end
        if key ~= "e" then return end
        if state.cutter and state.cutter.moving then
            if context.world.placeCutter(state) then context.saveCurrent() end
        elseif state.wrapper and state.wrapper.moving then
            if context.world.placeWrapper(state) then context.saveCurrent() end
        elseif selected and selected.kind == "customer" then
            local offer, errors = context.jobService.createNextOffer(state, os.time())
            if not offer then
                state.message = "Could not prepare the job: " .. table.concat(errors or {}, "; ")
            elseif context.world.beginCustomerReview() then
                state.currentOffer = offer
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
            if context.world.truckSnapshot().state == "cargo_open"
                and context.world.openTruckInventory(state)
            then
                state.screen = "truck_inventory"
                state.message = context.world.truckSnapshot().mode == "pickup"
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
    end
end

function Input.textinput(text, context)
    if context.state.screen == "machine" then
        return context.machineScreen.textinput(context.state, text)
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
    if state.screen == "vendor" then
        local result = context.vendorScreen.mousepressed(state, x, y, button)
        if not result then return false end
        if result.action == "close" then
            return Input.closeScreen(context)
        end
        if result.action ~= "blocked" then context.saveCurrent() end
        return true
    end
    if state.screen == "truck_inventory" then
        local result = context.truckInventoryScreen.mousepressed(state, context.world, x, y, button)
        if not result then return false end
        if result.action == "close" then
            return Input.closeScreen(context)
        elseif result.action == "door_closing" then
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
        return result
    end
    if state.screen == "computer" then
        local result = context.computerScreen.mousepressed(state, x, y, button)
        if not result then return false end
        if result.action == "close" then
            return Input.closeScreen(context)
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
    if not action then return false end

    if action == "back" then
        return Input.closeScreen(context)
    end

    local job = state.currentOffer
    if not job then
        state.message = "The customer paperwork is missing."
        return false
    end

    local timestamp = os.time()
    local succeeded, errorMessage
    if action == "accept" then
        succeeded, errorMessage = context.jobService.acceptOffer(state, job, timestamp)
    else
        succeeded, errorMessage = context.jobService.declineOffer(state, job, timestamp)
    end
    if not succeeded then
        state.message = "Could not " .. action .. " the job: " .. tostring(errorMessage)
        return false
    end

    context.world.resolveCustomer(action == "accept" and "accepted" or "declined", state)
    state.currentOffer = nil
    state.screen = "world"
    state.message = action == "accept"
        and string.format("Accepted %s for $%d. Delivery is awaiting scheduling.", job.id, job.quote.totalPrice)
        or string.format("Declined %s. The customer is leaving.", job.id)
    context.saveCurrent()
    return true
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
