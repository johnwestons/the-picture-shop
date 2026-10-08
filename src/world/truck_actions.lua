-- Network doors and truck loading and unloading.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.World.performNetworkInteraction(player, state, requestedKind, desiredState)
        if requestedKind=="shopRoom" or requestedKind=="roomStock" or requestedKind=="roomRest" then
            local okay,code,message=require("src.shop_rooms").perform(player,state,requestedKind,desiredState,
                {obstacles=Runtime.movementObstacles,players=function()
                    local result={Runtime.World.player}
                    local options=Runtime.World._employeeOptions or {}
                    for _,p in ipairs(options.players and options.players() or {}) do result[#result+1]=p end
                    return result
                end})
            return okay,code,message,requestedKind
        end
        if require("src.shop_rooms").scene(player)~="warehouse" then
            return false,"wrong_scene","This control is in the warehouse.",requestedKind
        end
        if type(player) ~= "table"
            or (requestedKind ~= "loadingBayDoor" and requestedKind ~= "truckCargoDoor")
            or (desiredState ~= "open" and desiredState ~= "closed")
        then
            return false, "not_allowed", "That shop control is still host-only.", requestedKind
        end
        Runtime.World._state = state or Runtime.World._state
        local target = requestedKind == "loadingBayDoor"
            and Runtime.World.bayDoor:getInteraction() or Runtime.World.truck:getInteraction()
        if not target then
            return false, "unavailable", "That shop control is no longer available.", requestedKind
        end
        local dx, dy = (tonumber(player.x) or 0) - target.x,
            (tonumber(player.y) or 0) - target.y
        -- One 20 Hz movement sample is roughly eight pixels at normal walking
        -- speed. A small host-side grace avoids boundary flicker without trusting
        -- any coordinate supplied by the client.
        local radius = math.max(0, tonumber(target.radius) or 0) + 10
        if dx * dx + dy * dy > radius * radius then
            return false, "out_of_range", requestedKind == "truckCargoDoor"
                and "Move closer to the truck cargo controls."
                or "Move closer to the loading-bay wall switch.", requestedKind
        end
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 0.01 then
            player.intentX, player.intentY = -dx / length, -dy / length
            if math.abs(dx) > 0.01 then player.facing = dx > 0 and -1 or 1 end
        end
        if requestedKind == "truckCargoDoor" then
            if desiredState ~= "open" then
                return false, "manifest_required",
                    "Review and finish the host-owned manifest before closing this truck.", requestedKind
            end
            if Runtime.World.truck.mode == "machine_delivery" then
                return false, "flatbed_manifest",
                    "This flatbed opens through its host-owned manifest.", requestedKind
            end
            if Runtime.World.truck.state == "cargo_open" then
                return true, "already_applied", "The truck cargo door is already open.", requestedKind
            elseif Runtime.World.truck.state == "cargo_opening" then
                return true, "in_progress", "The truck cargo door is already opening.", requestedKind
            elseif Runtime.World.truck.state ~= "parked_closed" then
                return false, "state_changed",
                    "Wait for the truck to park before opening its cargo door.", requestedKind
            end
            if Runtime.World.toggleTruckCargoDoor(state) then
                return true, "accepted",
                    "Truck cargo door activated. Door movement is synced from the host device.",
                    requestedKind
            end
            return false, "blocked",
                state and state.message or "The truck cargo door cannot open right now.", requestedKind
        end
        if Runtime.World.bayDoor.state == desiredState then
            return true, "already_applied",
                "The loading-bay door is already " .. desiredState .. ".", requestedKind
        end
        local movingTowardDesired = (Runtime.World.bayDoor.state == "opening" and desiredState == "open")
            or (Runtime.World.bayDoor.state == "closing" and desiredState == "closed")
        if movingTowardDesired then
            return true, "in_progress",
                "The loading-bay door is already moving " .. desiredState .. ".", requestedKind
        elseif Runtime.World.bayDoor.state == "opening" or Runtime.World.bayDoor.state == "closing" then
            return false, "state_changed",
                "The loading-bay door changed state. Wait for it to finish and try again.", requestedKind
        end
        local accepted = Runtime.World.toggleBayDoor(state)
        if accepted then
            return true, "accepted",
                "Loading-bay switch activated. Door movement is synced from the host device.",
                requestedKind
        end
        local code = Runtime.World.bayDoor.state == "opening" or Runtime.World.bayDoor.state == "closing"
            and "busy" or "blocked"
        return false, code, state and state.message or "The loading-bay door cannot move right now.", requestedKind
    end

    function Runtime.World.toggleTruckCargoDoor(state)
        if Runtime.World.truck.mode == "machine_delivery" then
            if state then state.message = "This flatbed has no cargo door. Open its delivery manifest instead." end
            return false
        end
        if not Runtime.World.truck:toggleCargoDoor() then
            if state then state.message = "Wait for the truck cargo door to finish moving." end
            return false
        end
        if state then
            state.message = Runtime.World.truck.state == "cargo_opening"
                and "Opening the truck cargo door..."
                or "Closing the truck cargo door..."
        end
        return true
    end

    function Runtime.World.openTruckInventory(state)
        if Runtime.World.truck.mode == "machine_delivery" then
            return Runtime.World.truck.state == "parked_closed"
                and Runtime.MachineFleet.orderById(state, Runtime.World.truck.jobId) ~= nil
        end
        if Runtime.World.truck.state ~= "cargo_open" then return false end
        local job = Runtime.activeJobById(state, Runtime.World.truck.jobId)
        return job ~= nil or Runtime.Procurement.orderById(state, Runtime.World.truck.jobId) ~= nil
    end

    function Runtime.World.unloadTruckMachine(state, machineId)
        if Runtime.World.truck.mode ~= "machine_delivery" or Runtime.World.truck.state ~= "parked_closed" then
            if state then state.message = "Wait for the machine flatbed to park before unloading." end
            return false
        end
        local succeeded, machine, remaining = Runtime.MachineFleet.unloadDelivery(
            state, Runtime.World.truck.jobId, machineId, os.time())
        if state then
            state.message = succeeded
                and string.format("Unloaded %s. Unit %s is now %s.", machine.name, machine.id, machine.status)
                or tostring(machine)
        end
        return succeeded, machine, remaining
    end

    function Runtime.World.unloadTruckPallet(state, palletId)
        if Runtime.World.truck.mode == "pickup" then return false, "Use the outbound loading manifest for this truck." end
        if Runtime.World.truck.state ~= "cargo_open" then
            if state then state.message = "Open the truck cargo door before unloading." end
            return false
        end
        local succeeded, pallet, remaining = Runtime.PalletLogistics.unload(
            state,
            Runtime.World.truck.jobId,
            palletId,
            Runtime.Config.palletLogistics.spawnPoints,
            Runtime.Config.palletLogistics.unloadOrigin
        )
        if state then
            state.message = succeeded
                and string.format("Unloaded %s. %d pallet(s) remain in the truck.", pallet.id, remaining)
                or tostring(pallet)
        end
        return succeeded, pallet, remaining
    end

    function Runtime.World.loadPickupPallet(state, palletId)
        if Runtime.World.truck.state ~= "cargo_open" or Runtime.World.truck.mode ~= "pickup" then
            if state then state.message = "Open the scheduled pickup truck before loading pallets." end
            return false
        end
        local succeeded, pallet, remaining = Runtime.JobService.loadForPickup(
            state, Runtime.World.truck.jobId, palletId, os.time())
        if state then
            state.message = succeeded
                and string.format("Loaded %s. %d pallet(s) remain on the floor.", pallet.id, remaining)
                or tostring(pallet)
        end
        return succeeded, pallet, remaining
    end

    function Runtime.World.closeTruckAfterUnload(state)
        if Runtime.World.truck.mode == "machine_delivery" then
            if Runtime.World.truck.state ~= "parked_closed" then return false end
            if Runtime.MachineFleet.remainingOnTruck(state, Runtime.World.truck.jobId) > 0 then
                if state then state.message = "Unload the machine before releasing the flatbed truck." end
                return false
            end
            local departing = Runtime.World.truck:depart()
            if departing and state then state.message = "The empty machine flatbed is departing." end
            return departing
        end
        if Runtime.World.truck.state ~= "cargo_open" then return false end
        if Runtime.World.truck.mode == "pickup" then
            if Runtime.JobService.remainingPickup(state, Runtime.World.truck.jobId) > 0 then
                if state then state.message = "Load every pickup pallet before closing the cargo door." end
                return false
            end
            return Runtime.World.toggleTruckCargoDoor(state)
        end
        if Runtime.PalletLogistics.remainingOnTruck(state, Runtime.World.truck.jobId) > 0 then
            if state then state.message = "Unload every pallet before closing the cargo door." end
            return false
        end
        return Runtime.World.toggleTruckCargoDoor(state)
    end
end

return Component
