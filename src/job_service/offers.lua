-- Reception offers, acceptance, decline, and delivery readiness.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.offerHistory(state)
        local anyPrint, receptionPrintCount, latestSequence, latestJob = false, 0, 0, nil
        for _, collectionName in ipairs({ "active", "completed", "declined" }) do
            for _, job in ipairs((state.jobs and state.jobs[collectionName]) or {}) do
                if type(job) == "table" and job.press then anyPrint = true end
                if type(job) == "table" and job.requestChannel ~= "email" then
                    local sequence = tonumber(tostring(job.id or ""):match("^JOB%-(%d+)$"))
                    if sequence then
                        if job.press then receptionPrintCount = receptionPrintCount + 1 end
                        if sequence > latestSequence then latestSequence, latestJob = sequence, job end
                    end
                end
            end
        end
        return anyPrint, receptionPrintCount, latestJob
    end

    function Runtime.JobService.createNextOffer(state, timestamp)
        if type(state) ~= "table" then return nil, { "shop state is required" } end
        local sequence = Runtime.nextSequence(state)
        local pressInstalled = Runtime.MachineFleet.isInstalled(state, "heidelberg_10x15")
        local anyPrint, receptionPrintCount, latestReceptionJob = Runtime.offerHistory(state)
        local pressEnabled = pressInstalled and (not anyPrint
            or (latestReceptionJob and latestReceptionJob.press == nil))
        local reputation = Runtime.Reputation.ensure(state)
        local _, tier = Runtime.Reputation.tier(reputation)
        local template
        if tier <= 0 then
            template = Runtime.copy(Runtime.starterTemplate)
            pressEnabled = false
        elseif pressEnabled then
            local pressIndex
            if receptionPrintCount == 0 or tier == 1 then pressIndex = 1
            elseif tier == 2 then pressIndex = receptionPrintCount % 2 == 0 and 1 or 3
            else
                local order = { 1, 3, 2 }
                pressIndex = order[receptionPrintCount % #order + 1]
            end
            template = Runtime.copy(Runtime.pressTemplates[pressIndex])
        elseif tier == 1 then
            template = Runtime.copy(Runtime.templates[1])
        elseif tier == 2 then
            template = Runtime.copy(Runtime.templates[sequence % 3 == 0 and 2 or 1])
        elseif tier == 3 then
            template = Runtime.copy(Runtime.templates[(sequence - 1) % #Runtime.templates + 1])
        else
            local order = { 2, 3, 1, 3 }
            template = Runtime.copy(Runtime.templates[order[(sequence - 1) % #order + 1]])
        end
        template.id = Runtime.Jobs.formatId(sequence)
        template.sequence = sequence
        template.createdAt = timestamp
        if pressEnabled then
            template.artworkKey = template.artwork.key
        else
            template.artworkKey = Runtime.artworkForSequence(state, sequence)
        end
        template.deliveryService = Runtime.deliveryService(template, sequence)
        local offer, errors = Runtime.Jobs.createOffer(template)
        if not offer then return nil, errors end
        return Runtime.decorateOfferForReputation(state, offer, sequence)
    end

    function Runtime.prepareCollections(state)
        state.jobs = type(state.jobs) == "table" and state.jobs or {}
        state.jobs.active = type(state.jobs.active) == "table" and state.jobs.active or {}
        state.jobs.completed = type(state.jobs.completed) == "table" and state.jobs.completed or {}
        state.jobs.declined = type(state.jobs.declined) == "table" and state.jobs.declined or {}
    end

    -- Do not accept an order unless its one initial truck manifest can carry
    -- every quoted original skid for that job.
    local function hasFullInitialShipment(job)
        local quoted=job and job.quote and job.quote.pallets
        if type(quoted)~="table" or #quoted==0 or type(job.pallets)~="table" then return false end
        local originals={}
        for _,pallet in ipairs(job.pallets) do
            if not pallet.replacementFor then
                local number=pallet.number
                if type(number)~="number" or number~=math.floor(number)
                    or number<1 or number>#quoted or originals[number] then return false end
                originals[number]=pallet
            end
        end
        for index,quotedPallet in ipairs(quoted) do
            local pallet=originals[index]
            if type(quotedPallet)~="table" or not pallet or pallet.location~="awaiting_delivery"
                or pallet.initialSheets~=quotedPallet.sheetCount then return false end
        end
        return true
    end

    function Runtime.JobService.acceptOffer(state, job, timestamp)
        if type(state) ~= "table" or type(job) ~= "table" then return false, "state and job are required" end
        if job.status=="offered" and not job.quote.playerPrice then
            local terms=Runtime.JobService.quoteTerms(state,job)
            job.quote.totalPrice=terms.amount;job.quote.recommendedPrice=terms.recommendedPrice
            job.quote.servicePrice=terms.servicePrice;job.quote.employeeBudget=terms.employeeBudget
        end
        if not hasFullInitialShipment(job) then
            return false,"This job cannot be accepted until every quoted skid is included in its first delivery."
        end
        local accepted, errorMessage = Runtime.Jobs.accept(job, timestamp)
        if not accepted then return false, errorMessage end
        job.deliveryService = Runtime.deliveryService(job, job.sequence)
        local acceptedGameHours = Runtime.BusinessCalendar.absoluteHours(state)
        job.delivery = {
            status = "pending_arrival",
            service = Runtime.copy(job.deliveryService),
            acceptedGameHours = acceptedGameHours,
            readyAtHours = acceptedGameHours + job.deliveryService.delayHours,
        }
        Runtime.prepareCollections(state)
        state.jobs.active[#state.jobs.active + 1] = job
        state.accountsReceivable = math.max(0, state.accountsReceivable or 0) + job.quote.totalPrice
        if job.requestChannel ~= "email" then state.nextJobId = Runtime.nextSequence(state) + 1 end
        return true, job
    end

    function Runtime.JobService.deliveryReady(state, job)
        if type(job) ~= "table" or type(job.delivery) ~= "table" then return true end
        if type(job.delivery.readyAtHours) ~= "number" then return true end
        if job.delivery.status == "pending_arrival" and tonumber(job.delivery.acceptedGameHours) then
            local service = Runtime.deliveryService(job, job.sequence)
            job.deliveryService = service
            job.delivery.service = Runtime.copy(service)
            job.delivery.readyAtHours = job.delivery.acceptedGameHours + service.delayHours
        end
        return Runtime.BusinessCalendar.absoluteHours(state) + 0.000001 >= job.delivery.readyAtHours
    end

    function Runtime.JobService.deliverySummary(job, state)
        if job and state and job.delivery and job.delivery.status == "pending_arrival" then
            Runtime.JobService.deliveryReady(state, job)
        end
        local service = job and (job.deliveryService or (job.delivery and job.delivery.service))
        if not service then return "Delivery timing not assigned" end
        if state and job.delivery and not Runtime.JobService.deliveryReady(state, job) then
            local remaining = math.max(0, job.delivery.readyAtHours - Runtime.BusinessCalendar.absoluteHours(state))
            if remaining < 24 then
                return string.format("%s — about %d hour%s", service.label,
                    math.max(1, math.ceil(remaining)), remaining > 1 and "s" or "")
            end
            return string.format("%s — about %d day%s", service.label,
                math.ceil(remaining / 24), remaining > 24 and "s" or "")
        end
        return service.label .. " — " .. service.description
    end

    function Runtime.JobService.declineOffer(state, job, timestamp)
        if type(state) ~= "table" or type(job) ~= "table" then return false, "state and job are required" end
        local declined, errorMessage = Runtime.Jobs.decline(job, timestamp)
        if not declined then return false, errorMessage end
        Runtime.prepareCollections(state)
        state.jobs.declined[#state.jobs.declined + 1] = job
        if job.requestChannel ~= "email" then state.nextJobId = Runtime.nextSequence(state) + 1 end
        return true, job
    end
end

return Component
