-- World loading, deliveries, and authoritative simulation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.World.load(position)
        local character = position and position.character or Runtime.Config.player.character
        local playerId = position and tonumber(position.id) or nil
        Runtime.World.player.id = playerId and playerId >= 1 and playerId <= 4
            and playerId == math.floor(playerId) and playerId or nil
        Runtime.World.player.character = Runtime.Config.characters[character] and character or Runtime.Config.player.character
        Runtime.PlayerController.reset(Runtime.World.player, position, Runtime.Config.player)
        Runtime.World.player.resting=false
        Runtime.World.player.sceneId=position and position.sceneId or "warehouse"
        Runtime.World.bayDoor:reset()
        Runtime.World.truck:reset()
        Runtime.World.customer:reset(true)
        Runtime.World.vendor:reset(true)
        Runtime.World.selectedInteraction = nil
        Runtime.World.placementSelection = nil
    end

    function Runtime.activeJobById(state, jobId)
        if not state or not state.jobs or type(state.jobs.active) ~= "table" then return nil end
        for _, job in ipairs(state.jobs.active) do
            if job.id == jobId then return job end
        end
        return nil
    end

    function Runtime.scheduleTruck(state)
        if not state or Runtime.World.truck.state ~= "absent" then return false end
        local pickup = Runtime.JobService.nextPickup(state)
        if pickup and Runtime.World.truck:schedule(pickup.id, "pickup") then
            Runtime.JobService.schedulePickup(pickup, os.time())
            state.message = "Customer pickup scheduled for " .. pickup.id .. "."
            return true
        end
        local machineOrder = Runtime.MachineFleet.nextInbound(state)
        if machineOrder then
            if Runtime.World.truck:schedule(machineOrder.id, "machine_delivery") then
                machineOrder.delivery.status = "scheduled"
                machineOrder.delivery.scheduledAt = os.time()
                state.message = "Machine flatbed delivery scheduled for " .. machineOrder.id .. "."
                return true
            end
            return false
        end
        local purchase = Runtime.Procurement.nextInbound(state)
        if purchase then
            if Runtime.World.truck:schedule(purchase.id, "vendor_delivery") then
                purchase.delivery.status = "scheduled"
                state.message = "Vendor delivery scheduled for " .. purchase.id .. "."
                return true
            end
            return false
        end
        local activeJobs = state.jobs and state.jobs.active or {}
        for _, job in ipairs(activeJobs) do
            local deliveryStatus = job.delivery and job.delivery.status
            local hasInboundPallets = Runtime.PalletLogistics.remainingOnTruck(state, job.id) > 0
            if (job.status == "awaiting_delivery" or job.status == "in_production")
                and hasInboundPallets and deliveryStatus ~= "received"
                and Runtime.JobService.deliveryReady(state, job)
            then
                if Runtime.World.truck:schedule(job.id, "delivery") then
                    job.delivery = job.delivery or {}
                    job.delivery.status = "scheduled"
                    state.message = job.delivery.kind == "replacement"
                        and "The customer's replacement skid is scheduled for delivery."
                        or "Inbound truck scheduled for " .. job.id .. "."
                    return true
                end
                return false
            end
        end
        return false
    end

    function Runtime.updateTruck(dt, motionDt, state)
        local saveNeeded = Runtime.scheduleTruck(state)
        local truckJobId, truckMode = Runtime.World.truck.jobId, Runtime.World.truck.mode
        local event = Runtime.World.truck:update(dt, Runtime.World.bayDoor.state, motionDt)
        if not event then return saveNeeded end
        local job = Runtime.activeJobById(state, truckJobId)
        local purchase = Runtime.Procurement.orderById(state, truckJobId)
        local machineOrder = truckMode == "machine_delivery" and Runtime.MachineFleet.orderById(state, truckJobId) or nil
        local pickup = truckMode == "pickup" and job or nil
        local replacementDelivery = job and job.delivery
            and job.delivery.kind == "replacement" and not pickup
        if event == "request_bay_open" then
            if Runtime.World.bayDoor.state == "closed" then Runtime.World.bayDoor:open() end
            if state then
                state.message = pickup and "Pickup truck arrived. Opening the loading bay..."
                    or (machineOrder and "Machine flatbed arrived. Opening the loading bay..."
                        or (replacementDelivery
                            and "The customer's replacement-stock truck arrived. Opening the loading bay..."
                            or "Delivery truck arrived. Opening the loading bay..."))
            end
        elseif event == "backing_started" then
            if pickup then
                Runtime.JobService.setPickupStatus(pickup, "backing")
            elseif job and job.delivery then job.delivery.status = "backing" end
            if purchase and purchase.delivery then purchase.delivery.status = "backing" end
            if machineOrder then machineOrder.delivery.status = "backing" end
            if state then
                state.message = pickup and "The customer pickup truck is backing into the loading bay."
                    or (machineOrder and "The machine flatbed is backing into the loading bay."
                        or "The delivery truck is backing into the loading bay.")
            end
            saveNeeded = true
        elseif event == "parked" then
            if pickup then
                Runtime.JobService.setPickupStatus(pickup, "at_bay", "arrivedAt", os.time())
            elseif job and job.delivery then job.delivery.status = "at_bay" end
            if purchase and purchase.delivery then purchase.delivery.status = "at_bay" end
            if machineOrder then
                machineOrder.delivery.status = "at_bay"
                machineOrder.delivery.arrivedAt = os.time()
            end
            if state then
                state.message = pickup
                    and "Pickup truck parked. Open its rear cargo door and load the wrapped pallets."
                    or (machineOrder
                        and "Machine flatbed parked. Open its manifest and unload the machine."
                        or (replacementDelivery
                            and "Replacement skid parked at the bay. Open the truck and unload it."
                            or "Truck parked. Open its rear cargo door to unload."))
            end
            saveNeeded = true
        elseif event == "cargo_opened" then
            if pickup then Runtime.JobService.setPickupStatus(pickup, "cargo_open") end
            if state then state.message = pickup
                and "Pickup truck cargo door open. Load every wrapped pallet on the manifest."
                or "Truck cargo door open. Review the manifest and unload each pallet." end
            saveNeeded = pickup ~= nil or saveNeeded
        elseif event == "cargo_closed" then
            local received = (job and job.delivery and job.delivery.status == "received")
                or (purchase and purchase.delivery and purchase.delivery.status == "received")
            local pickupLoaded = pickup and Runtime.JobService.remainingPickup(state, pickup.id) == 0
            if (received or pickupLoaded) and Runtime.World.truck:depart() then
                if pickup then Runtime.JobService.setPickupStatus(pickup, "departing") end
                if state then state.message = pickup
                    and "Pickup cargo secured. The customer truck is departing."
                    or "Cargo secured. The empty truck is departing." end
                saveNeeded = pickup ~= nil or saveNeeded
            elseif state then
                state.message = "Truck cargo door closed."
            end
        elseif event == "departed" then
            if Runtime.World.bayDoor.state == "open" then Runtime.World.bayDoor:close() end
            if pickup then
                local completed, completedJob, payment = Runtime.JobService.completePickup(state, pickup.id, os.time())
                if completed then
                    state.message = string.format("%s picked up and paid $%d. Closing the loading bay door...",
                        completedJob.id, payment)
                    saveNeeded = true
                else
                    state.message = "Pickup truck left, but the job could not be archived."
                end
            elseif state then
                state.message = "The truck left. Closing the loading bay door..."
            end
        end
        return saveNeeded
    end

    function Runtime.World.customerArrivalMessage(state)
        return state and state.currentOffer and state.currentOffer.press
            and "A customer is waiting at reception with a print job."
            or "A customer is waiting at reception with a client job."
    end

    -- Host-owned events have their own clock so an open menu never freezes the
    -- loading bay, visitors, pallet unloading, or technician work for guests.
    function Runtime.World.updateSimulation(dt, assets, state, motionDt)
        motionDt = math.max(0, tonumber(motionDt) or dt)
        assets = Runtime.WarehouseGameplay.assets(assets, state)
        Runtime.World._assets, Runtime.World._state = assets, state
        local player = Runtime.World.player
        local doorEvent = Runtime.World.bayDoor:update(motionDt)
        if doorEvent == "opened" and state then
            state.message = "Loading bay door open. The parking lot is visible."
        elseif doorEvent == "closed" and state then
            state.message = "Loading bay door closed."
        end
        local saveNeeded = Runtime.updateTruck(dt, motionDt, state)
        Runtime.PalletLogistics.update(state, dt, Runtime.Config.palletLogistics.unloadDuration)
        -- Only one reception visitor advances at a time. The other visitor keeps
        -- their full cooldown while the entrance, lounge, or desk is occupied.
        local receptionClosed = Runtime.BusinessCalendar.isWeekend(state) or Runtime.EmployeeAI.receptionOccupied(state)
        local employeeContext = Runtime.World.employeeContext(state,assets)
        local customerEvent = Runtime.World.customer:update(dt, player,
            receptionClosed or Runtime.World.vendor:isPresent(), motionDt, employeeContext)
        if customerEvent == "arrived" and state then
            state.message = Runtime.World.customerArrivalMessage(state)
        elseif customerEvent == "timed_out" and state then
            state.message = "The client waited five minutes without being seen and is leaving."
        elseif customerEvent == "route_blocked" and state then
            state.message = "The client cannot reach the lounge and is heading back to the entrance. Clear the aisle."
        elseif customerEvent == "exited" and state then
            state.message = Runtime.World.customer.routeBlocked
                and "The client left because the lounge was inaccessible."
                or Runtime.World.customer.decision == "timed_out"
                and "The client left after waiting five minutes."
                or (Runtime.World.customer.decision == "accepted"
                    and "The customer left and will email the written job details."
                    or "The customer left after you declined the job.")
            -- Bring the next business client into the arrival queue after this
            -- visit so the configured roster is experienced during one session.
            Runtime.World.customer:reset(false)
        end
        local category = Runtime.Procurement.category(state and state.vendorCategory)
        Runtime.World.vendor.character = category.character
        local vendorEvent = Runtime.World.vendor:update(dt, player,
            receptionClosed or Runtime.World.customer:isPresent(), motionDt, employeeContext)
        if vendorEvent == "arrived" and state then
            state.message = category.salesman .. " is waiting at reception with the " .. category.name:lower() .. " catalog."
        elseif vendorEvent == "route_blocked" and state then
            state.message = "The supplier cannot reach reception and is heading back to the entrance. Clear the aisle."
        elseif vendorEvent == "exited" and state then
            state.vendorCategory = state.vendorCategory % #Runtime.Procurement.categories + 1
            Runtime.World.vendor:reset(false)
            state.message = "The salesman left. Another supplier representative will visit later."
        end
        if Runtime.Technician.update(dt, state,
            Runtime.World.customer:isPresent() or Runtime.World.vendor:isPresent(), motionDt, employeeContext) then
            saveNeeded = true
        end
        employeeContext.motionScale = dt > 0 and motionDt / dt or 1
        local employeeChanged=Runtime.EmployeeAI.update(state,dt,employeeContext)
        return saveNeeded or employeeChanged
    end
end

return Component
