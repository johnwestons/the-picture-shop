-- Job completion, pickup scheduling, loading, and payment.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}
local Feedback = require("src.job_feedback")

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

    function Runtime.JobService.requestPickup(state, job, timestamp, driverMode)
        if type(state) ~= "table" or type(job) ~= "table" then return false, "state and job are required" end
        local active = Runtime.activeJob(state, job.id)
        if active ~= job then return false, "job is not active" end
        if not Runtime.JobService.completionReady(job) then
            return false, "every pallet must be finished and wrapped before pickup"
        end
        if not job.inspection or job.inspection.status ~= "passed" then
            if job.inspection and job.inspection.status == "held" then
                return false, "quality inspection found a defect; rework the affected pallet before pickup"
            end
            local inspected, result = Feedback.inspect(state, job)
            if not inspected then return false, result end
            if result.status ~= "passed" then
                return false, "quality inspection found a defect; rework the affected pallet before pickup"
            end
        end
        local clientArrangesTransport = job.outboundDelivery
            and job.outboundDelivery.transport == "customer"
        if clientArrangesTransport then
            driverMode = nil
        else
            driverMode = driverMode == "player" and "player" or "employee"
        end
        local dispatchAtHours=Runtime.BusinessCalendar.absoluteHours(state)+(clientArrangesTransport and .5 or .25)
        if clientArrangesTransport then
            for _,other in ipairs(state.jobs.active) do
                local pickup=other.pickup
                if pickup and not pickup.driverMode and pickup.status=='awaiting_schedule' then
                    dispatchAtHours=math.max(dispatchAtHours,(pickup.dispatchAtHours or dispatchAtHours)+.5)
                end
            end
        end
        job.status = "ready_for_pickup"
        dispatchAtHours=require('src.business_hours').nextService(dispatchAtHours)
        job.pickup = {
            status = "awaiting_schedule",
            requestedAt = timestamp,
            driverMode = driverMode,
            -- Give the owner time to change the delivery choice in the active
            -- job ticket before an employee reserves and loads the truck.
            dispatchAtHours = dispatchAtHours,
        }
        job.pickupRequestedAtHours = Runtime.BusinessCalendar.absoluteHours(state)
        Feedback.record(job, "ready_to_ship", job.pickupRequestedAtHours, "Quality inspection passed")
        return true, job
    end

    function Runtime.JobService.setPickupDriverMode(state, jobId, driverMode)
        if driverMode ~= "employee" and driverMode ~= "player" then
            return false, "Choose employee delivery or player delivery."
        end
        local job = Runtime.activeJob(state, jobId)
        if job and job.outboundDelivery and job.outboundDelivery.transport == "customer" then
            return false, "The client is arranging transportation for this shipment."
        end
        if not job or job.status ~= "ready_for_pickup" or type(job.pickup) ~= "table"
            or job.pickup.status ~= "awaiting_schedule" then
            return false, "Delivery choice can only be changed before a driver loads the job."
        end
        job.pickup.driverMode = driverMode
        job.pickup.dispatchAtHours = require('src.business_hours').nextService(Runtime.BusinessCalendar.absoluteHours(state) + .25)
        return true, job
    end

    function Runtime.JobService.inspectJob(state, jobId)
        local job = Runtime.activeJob(state, jobId)
        if not job then return false, "job is not active" end
        if not Runtime.JobService.completionReady(job) then
            return false, "every pallet must be finished and wrapped before inspection"
        end
        return Feedback.inspect(state, job)
    end

    function Runtime.JobService.requestQualityRework(state, jobId)
        local job = Runtime.activeJob(state, jobId)
        if not job then return false, "job is not active" end
        if not Runtime.JobService.completionReady(job) then
            return false, "finish and wrap the job before sending it to quality rework"
        end
        return Feedback.requestRework(state, job)
    end

    function Runtime.JobService.resolveCustomerCase(state, jobId, response)
        local job
        for _, completed in ipairs(state.jobs and state.jobs.completed or {}) do
            if completed.id == jobId then job = completed; break end
        end
        if not job or type(job.customerCase) ~= "table" or job.customerCase.status ~= "open" then
            return false, "There is no open customer case for that job."
        end
        if response ~= "credit" and response ~= "apology" and response ~= "decline" then
            return false, "Choose a credit, apology, or decline response."
        end
        local now = Runtime.BusinessCalendar.absoluteHours(state)
        local resultText
        if response == "credit" then
            local amount = math.max(1, math.floor((tonumber(job.paymentAmount) or job.quote.totalPrice or 0) * 0.10))
            Runtime.BusinessCalendar.addCharge(state,
                "Customer account credit for " .. tostring(job.id), amount, job.id, "customer_refund")
            job.customerCase.creditAmount = amount
            Runtime.Reputation.adjustReview(state, job.id, 1, "The shop issued an account credit and followed up.")
            resultText = string.format("A $%d account credit was issued. The credit is listed with the shop's bills.", amount)
        elseif response == "apology" then
            Runtime.Reputation.adjustReview(state, job.id, 0, "The shop apologized and explained how it will prevent a repeat.")
            resultText = "The shop sent an apology and explained the corrective action."
        else
            Runtime.Reputation.adjustReview(state, job.id, -1, "The shop declined responsibility for the complaint.")
            local reputation = Runtime.Reputation.ensure(state)
            reputation.score = math.max(-100, reputation.score - 2)
            resultText = "The shop declined responsibility. The customer was not satisfied."
        end
        job.customerCase.status = "resolved"
        job.customerCase.resolution = response
        job.customerCase.resolvedAtHours = now
        job.customerCase.responseText = resultText
        Feedback.record(job, "customer_case_resolved", now, response .. ": " .. resultText)
        local emailId = "CASE-" .. tostring(job.id)
        for _, email in ipairs(Runtime.ensureEmails(state).inbox) do
            if email.id == emailId then
                email.noticeKind = "customer_case_resolved"
                email.subject = "Resolved: " .. email.subject
                email.body = resultText
                email.unread = true
            end
        end
        return true, job.customerCase
    end

    function Runtime.JobService.nextPickup(state, canSchedule)
        Runtime.prepareCollections(state)
        for _, job in ipairs(state.jobs.active) do
            local pickupStatus = job.pickup and job.pickup.status
            if job.status == "ready_for_pickup"
                and not (job.pickup and job.pickup.driverMode)
                or (job.status == "pickup_in_progress" and pickupStatus ~= "completed"
                    and pickupStatus ~= "player_delivery"
                    and not (job.pickup and job.pickup.driverMode))
            then
                if not canSchedule or canSchedule(job) then return job end
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

    function Runtime.JobService.pickupItemAvailable(state,item,scene)
        local position=item.pallet and item.pallet.world
        if position and (position.sceneId or 'warehouse')~=(scene or 'warehouse') then return false end
        if item.location=='on_pallet_jack' then
            local jack=state.palletJack
            return jack and jack.carriedPalletId==item.id and jack.operating
                and jack.operatorPlayerId~=nil and jack.operatorEmployeeId==nil or false
        end
        return item.location=='warehouse' or item.location=='cutter_output' or item.location=='press_output'
    end

    function Runtime.JobService.loadForPickup(state, jobId, palletId, timestamp, employeeId)
        local job = Runtime.activeJob(state, jobId)
        if not job or job.status ~= "pickup_in_progress" then return false, "pickup is not in progress" end
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.id == palletId then
                if pallet.location == "outbound_truck" then return false, "that pallet is already on the truck" end
                if pallet.status ~= "wrapped" or not pallet.wrapped then return false, "that pallet is not wrapped" end
                local jack=state.palletJack
                local employeeLoad=employeeId and pallet.location=="on_pallet_jack" and jack
                    and jack.carriedPalletId==palletId and jack.operating and jack.operatorEmployeeId==employeeId
                local playerLoad=not employeeId and pallet.location=="on_pallet_jack" and jack
                    and jack.carriedPalletId==palletId and jack.operating and jack.operatorPlayerId~=nil
                    and jack.operatorEmployeeId==nil
                if not employeeLoad and not playerLoad and pallet.location ~= "warehouse" and pallet.location ~= "cutter_output"
                    and pallet.location ~= "press_output" then
                    return false, "lower the wrapped pallet onto the warehouse floor before loading"
                end
                local transitioned, transitionError = Runtime.PalletState.transition(
                    state, pallet, "outbound_truck", { status = "loaded_for_pickup" })
                if not transitioned then return false, transitionError end
                local feedback = Feedback.ensure(job)
                if not feedback.shippedAtHours then
                    feedback.shippedAtHours = Runtime.BusinessCalendar.absoluteHours(state)
                    Feedback.record(job, "shipped", feedback.shippedAtHours,
                        "First finished pallet loaded onto the customer pickup")
                end
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
        require("src.household_finances").record(state,"revenue",payment*100)
        require('src.receipt_book').job(state,job)
        local reputationGain, reputationScore = Runtime.Reputation.completeJob(state, job)
        local completedHours = Runtime.BusinessCalendar.absoluteHours(state)
        Feedback.record(job, "closed", completedHours, "Customer pickup completed; payment received")
        local review = Runtime.Reputation.recordReview(state, job, completedHours)
        local feedback = Feedback.ensure(job)
        feedback.deliveredSheets = Feedback.goodQuantity(job)
        job.reputationGain = reputationGain
        job.reputationAfter = reputationScore
        local lateHours = Feedback.lateByHours(job)
        if review and lateHours > 0 then
            local latePenalty = lateHours >= 48 and -2 or -1
            review = Runtime.Reputation.adjustReview(state, job.id, latePenalty,
                string.format("Delivered late by about %d hours.", math.ceil(lateHours)))
        end
        if review and (review.rating <= 2 or lateHours > 0) then
            local reason = lateHours > 0 and "late" or "quality"
            job.customerCase = {
                status = "open",
                reason = reason,
                openedAtHours = completedHours,
                lateHours = lateHours,
            }
            local reasons = {}
            if review.rating <= 2 then reasons[#reasons + 1] = "The delivered job received a low quality rating." end
            if lateHours > 0 then
                reasons[#reasons + 1] = string.format("The job arrived about %d hours after its promised turnaround.",
                    math.ceil(lateHours))
            end
            local reasonText = table.concat(reasons, " ")
            Runtime.Inbox.addNotice(state, {
                id = "CASE-" .. tostring(job.id),
                sender = job.company,
                subject = "Follow-up needed for " .. tostring(job.id),
                body = reasonText .. " Choose a 10% account credit, send an apology, or decline responsibility.",
                noticeKind = "customer_case",
                sourceJobId = job.id,
            }, 0)
            if lateHours >= 24 then
                require("src.work_phone").queueCall(state, {
                    kind = "customer_complaint",
                    caller = job.company,
                    role = "CUSTOMER",
                    subject = "LATE JOB COMPLAINT",
                    message = string.format("We are calling about job %s. It arrived late; please review our follow-up email and let us know how you will make this right.", job.id),
                    jobId = job.id,
                }, completedHours)
            end
        end
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
