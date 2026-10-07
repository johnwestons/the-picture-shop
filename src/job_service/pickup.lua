-- Job completion, pickup scheduling, loading, and payment.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.activeJob(state, jobId)
        Runtime.prepareCollections(state)
        for index, job in ipairs(state.jobs.active) do
            if job.id == jobId then return job, index end
        end
    end

    function Runtime.JobService.completionReady(job)
        if type(job) ~= "table" or job.status ~= "in_production"
            or type(job.pallets) ~= "table" or #job.pallets == 0
        then
            return false
        end
        for _, pallet in ipairs(job.pallets) do
            if pallet.status ~= "spoiled_discarded"
                and ((pallet.remainingSheets or 0) > 0
                    or pallet.status ~= "wrapped" or not pallet.wrapped)
            then
                return false
            end
            if pallet.status ~= "spoiled_discarded" and job.press
                and (type(pallet.press) ~= "table" or pallet.press.status ~= "complete")
            then
                return false
            end
        end
        return true
    end

    function Runtime.JobService.requestPickup(state, job, timestamp)
        if type(state) ~= "table" or type(job) ~= "table" then return false, "state and job are required" end
        local active = Runtime.activeJob(state, job.id)
        if active ~= job then return false, "job is not active" end
        if not Runtime.JobService.completionReady(job) then
            return false, "every pallet must be finished and wrapped before pickup"
        end
        job.status = "ready_for_pickup"
        job.pickup = {
            status = "awaiting_schedule",
            requestedAt = timestamp,
        }
        job.pickupRequestedAtHours = Runtime.BusinessCalendar.absoluteHours(state)
        return true, job
    end

    function Runtime.JobService.nextPickup(state)
        Runtime.prepareCollections(state)
        for _, job in ipairs(state.jobs.active) do
            local pickupStatus = job.pickup and job.pickup.status
            if job.status == "ready_for_pickup"
                or (job.status == "pickup_in_progress" and pickupStatus ~= "completed")
            then
                return job
            end
        end
    end

    function Runtime.JobService.schedulePickup(job, timestamp)
        if type(job) ~= "table" or (job.status ~= "ready_for_pickup" and job.status ~= "pickup_in_progress") then
            return false, "job is not awaiting pickup"
        end
        job.pickup = type(job.pickup) == "table" and job.pickup or {}
        job.status = "pickup_in_progress"
        job.pickup.status = "scheduled"
        job.pickup.scheduledAt = timestamp
        return true, job
    end

    function Runtime.JobService.setPickupStatus(job, status, timestampField, timestamp)
        if type(job) ~= "table" or job.status ~= "pickup_in_progress" then return false end
        job.pickup = type(job.pickup) == "table" and job.pickup or {}
        job.pickup.status = status
        if timestampField then job.pickup[timestampField] = timestamp end
        return true
    end

    function Runtime.JobService.pickupInventory(state, jobId)
        local job = Runtime.activeJob(state, jobId)
        local inventory = {}
        for _, pallet in ipairs(job and job.pallets or {}) do
            if pallet.status ~= "spoiled_discarded" then inventory[#inventory + 1] = {
                id = pallet.id,
                number = pallet.number,
                sheets = pallet.finishedSheets,
                location = pallet.location,
                status = pallet.status,
                paper = pallet.paper,
                pallet = pallet,
            } end
        end
        return job, inventory
    end

    function Runtime.JobService.remainingPickup(state, jobId)
        local _, inventory = Runtime.JobService.pickupInventory(state, jobId)
        local remaining = 0
        for _, item in ipairs(inventory) do
            if item.location ~= "outbound_truck" and item.location ~= "none" then remaining = remaining + 1 end
        end
        return remaining
    end

    function Runtime.JobService.loadForPickup(state, jobId, palletId, timestamp)
        local job = Runtime.activeJob(state, jobId)
        if not job or job.status ~= "pickup_in_progress" then return false, "pickup is not in progress" end
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.id == palletId then
                if pallet.location == "outbound_truck" then return false, "that pallet is already on the truck" end
                if pallet.status ~= "wrapped" or not pallet.wrapped then return false, "that pallet is not wrapped" end
                if pallet.location ~= "warehouse" and pallet.location ~= "cutter_output"
                    and pallet.location ~= "press_output" then
                    return false, "lower the wrapped pallet onto the warehouse floor before loading"
                end
                local transitioned, transitionError = Runtime.PalletState.transition(
                    state, pallet, "outbound_truck", { status = "loaded_for_pickup" })
                if not transitioned then return false, transitionError end
                state.inventory.finishedPallets = math.max(0, (state.inventory.finishedPallets or 0) - 1)
                local remaining = Runtime.JobService.remainingPickup(state, jobId)
                Runtime.JobService.setPickupStatus(job, remaining == 0 and "loaded" or "loading",
                    remaining == 0 and "loadedAt" or nil, timestamp)
                return true, pallet, remaining
            end
        end
        return false, "the pickup pallet was not found"
    end

    function Runtime.JobService.completePickup(state, jobId, timestamp)
        local job, activeIndex = Runtime.activeJob(state, jobId)
        if not job or job.status ~= "pickup_in_progress" then return false, "pickup is not in progress" end
        if Runtime.JobService.remainingPickup(state, jobId) ~= 0 then return false, "pickup pallets remain on the floor" end
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.status ~= "spoiled_discarded" and pallet.location ~= "outbound_truck" then
                return false, "pickup manifest is incomplete"
            end
        end
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.status ~= "spoiled_discarded" then
                local transitioned, transitionError = Runtime.PalletState.transition(
                    state, pallet, "none", { status = "picked_up" })
                if not transitioned then return false, transitionError end
                pallet.pickedUpAt = timestamp
            end
        end
        local payment = job.quote.totalPrice
        job.status = "completed"
        job.employeeSkillAwards = nil
        job.completedAt = timestamp
        job.completedAtHours = Runtime.BusinessCalendar.absoluteHours(state)
        job.paidAt = timestamp
        job.paymentAmount = payment
        job.pickup.status = "completed"
        job.pickup.completedAt = timestamp
        table.remove(state.jobs.active, activeIndex)
        state.jobs.completed[#state.jobs.completed + 1] = job
        state.accountsReceivable = math.max(0, (state.accountsReceivable or 0) - payment)
        state.money = math.max(0, state.money or 0) + payment
        local reputationGain, reputationScore = Runtime.Reputation.completeJob(state, job)
        job.reputationGain = reputationGain
        job.reputationAfter = reputationScore
        Runtime.JobService.scheduleRepeatEmail(state, job)
        return true, job, payment
    end

    function Runtime.JobService.templates()
        return Runtime.copy(Runtime.templates)
    end

    function Runtime.JobService.printTemplates()
        return Runtime.copy(Runtime.pressTemplates)
    end
end

return Component
