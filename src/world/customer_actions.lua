-- Customer, vendor, breakroom, and bay-door actions.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.World.faceInteraction()
        local target = Runtime.World.selectedInteraction and Runtime.World.selectedInteraction.target
        if not target then return false end
        local dx, dy = target.x - Runtime.World.player.x, target.y - Runtime.World.player.y
        if math.abs(dx) > 0.01 then Runtime.World.player.facing = dx < 0 and -1 or 1 end
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 0.01 then
            Runtime.World.player.intentX, Runtime.World.player.intentY = dx / length, dy / length
        end
        return true
    end

    -- Breakroom use is a local, transient sit action. It deliberately does not
    -- alter employee needs, money, work speed or saved shop state.
    function Runtime.World.beginBreakroomRest(state)
        local selected=Runtime.World.selectedInteraction
        if not selected or selected.kind~="breakroom" or not selected.target then
            if state then state.message="Move beside a completed employee breakroom first." end
            return false
        end
        local player=Runtime.World.player
        local room=Runtime.WarehouseLayout.bayState(Runtime.World._state,selected.target.bayId)
        if not room or room.status~="complete" or room.optionId~="breakroom" then
            if state then state.message="That breakroom is not available yet." end
            return false
        end
        if Runtime.Forklift.isOperator(Runtime.World._state,Runtime.Config.forklift,player.id)
            or Runtime.PalletJack.isOperator(Runtime.World._state,Runtime.Config.palletJack,player.id) then
            if state then state.message="Step off the equipment before taking a break." end
            return false
        end
        if player.resting then
            player.resting=false
            if state then state.message="Back to work." end
            return true
        end
        for _,w in ipairs(Runtime.Employees.ensure(state).staff) do
            if w.visible and w.seatBay==selected.target.bayId then
                state.message="An employee is using that breakroom seat."
                return false
            end
        end
        player.x,player.y=selected.target.x,selected.target.y
        Runtime.PlayerController.stop(player)
        player.moving=false
        player.resting=true
        player.facing=-1
        player.intentX,player.intentY=-1,0
        if state then state.message="Taking a break. Move or press E to get up." end
        return true
    end

    function Runtime.World.setPlayerCharacter(character)
        if not Runtime.Config.characters[character] then return false end
        Runtime.World.player.character = character
        return true
    end

    function Runtime.World.beginCustomerReview()
        return Runtime.World.selectedInteraction
            and Runtime.World.selectedInteraction.kind == "customer"
            and Runtime.World.customer:beginReview()
            or false
    end

    function Runtime.World.cancelCustomerReview(state)
        if not Runtime.World.customer:cancelReview() then return false end
        if state then state.message = "The customer is still waiting whenever you are ready to review the job." end
        return true
    end

    function Runtime.World.beginVendorReview()
        return Runtime.World.selectedInteraction and Runtime.World.selectedInteraction.kind == "vendor" and Runtime.World.vendor:beginReview() or false
    end

    function Runtime.World.cancelVendorReview(state)
        if not Runtime.World.vendor:cancelReview() then return false end
        if state then state.message = "The salesperson is still waiting if you want to reopen the catalog." end
        return true
    end

    function Runtime.World.resolveVendor(state, decision)
        decision = decision == "declined" and "declined" or "accepted"
        if not Runtime.World.vendor:resolve(decision) then return false end
        if state then
            state.message = decision == "declined"
                and "You said no thanks. The supplier representative is heading out."
                or "The supplier representative is heading out."
        end
        return true
    end

    function Runtime.World.resolveCustomer(decision, state)
        if not Runtime.World.customer:resolve(decision) then return false end
        if state then
            state.message = decision == "accepted"
                and "The customer will email the written job details."
                or "Job declined. The customer is heading out."
        end
        return true
    end

    function Runtime.World.toggleBayDoor(state)
        if Runtime.World.bayDoor.state == "open" and Runtime.World.truck:blocksBayClosure() then
            if state then state.message = "The truck is occupying the bay. Keep the loading door open." end
            return false
        end
        if not Runtime.World.bayDoor:toggle() then
            if state then state.message = "Wait for the loading bay door to finish moving." end
            return false
        end
        if state then
            state.message = Runtime.World.bayDoor.state == "opening"
                and "Opening the loading bay door..."
                or "Closing the loading bay door..."
        end
        return true
    end

    -- Network workers may request only explicitly allowlisted, non-modal actions.
    -- The host resolves the target again from its authoritative worker position;
    -- client coordinates and target state are never accepted as authority.
end

return Component
