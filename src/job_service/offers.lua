-- Reception offers, acceptance, decline, and delivery readiness.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    local function receptionPrintCount(state)
        local count, seen = 0, {}
        for _, collectionName in ipairs({ "active", "completed", "declined" }) do
            for _, job in ipairs((state.jobs and state.jobs[collectionName]) or {}) do
                local key = type(job) == "table" and (job.id or job) or nil
                if type(job) == "table" and job.press and job.requestChannel ~= "email"
                    and key and not seen[key] then
                    count = count + 1
                    seen[key] = true
                end
            end
        end
        local current = state.currentOffer
        local currentKey = type(current) == "table" and (current.id or current) or nil
        if type(current) == "table" and current.press and current.requestChannel ~= "email"
            and currentKey and not seen[currentKey] then
            count = count + 1
        end
        return count
    end

    local function installedCount(state, modelId)
        return #Runtime.MachineFleet.installedUnits(state, modelId)
    end

    -- The job stream follows the shop's machine mix: cutters create cut-only
    -- opportunities, presses add print work, and print work still requires a
    -- cutter. A repeating weighted sequence makes the split predictable.
    local function isPrintOpportunity(sequence, cutterCount, pressCount)
        if cutterCount < 1 or pressCount < 1 then return false end
        local cycleLength = cutterCount + pressCount
        local position = (sequence - 1) % cycleLength
        return position < pressCount
    end

    local function scaleTemplateVolume(template, machineCount)
        local counts = template.sheetCounts or {}
        local copies = template.press and template.press.requestedCopies or counts
        local multiplier = math.max(1, math.floor(tonumber(machineCount) or 1))
        local maximum = Runtime.Jobs.MAX_PALLETS
        if multiplier <= 1 or #counts == 0 or #counts >= maximum then return end

        local expandedCounts, expandedCopies = {}, {}
        for _ = 1, multiplier do
            for index, sheets in ipairs(counts) do
                if #expandedCounts >= maximum then break end
                expandedCounts[#expandedCounts + 1] = sheets
                expandedCopies[#expandedCopies + 1] = copies[index] or sheets
            end
            if #expandedCounts >= maximum then break end
        end
        template.sheetCounts = expandedCounts
        if template.press then template.press.requestedCopies = expandedCopies end
    end

    function Runtime.JobService.createNextOffer(state, timestamp)
        if type(state) ~= "table" then return nil, { "shop state is required" } end
        local sequence = Runtime.nextSequence(state)
        local cutterCount = installedCount(state, "polar_115")
        local pressCount = installedCount(state, "heidelberg_10x15")
        if cutterCount == 0 then
            return nil, { "Install a cutter before accepting production jobs." }
        end
        local pressJob = isPrintOpportunity(sequence, cutterCount, pressCount)
        local printCount = receptionPrintCount(state)
        local reputation = Runtime.Reputation.ensure(state)
        local _, tier = Runtime.Reputation.tier(reputation)
        local template
        if pressJob then
            local pressIndex
            if tier <= 1 then pressIndex = 1
            elseif tier == 2 then pressIndex = printCount % 2 == 0 and 1 or 3
            else
                local order = { 1, 3, 2 }
                pressIndex = order[printCount % #order + 1]
            end
            template = Runtime.copy(Runtime.pressTemplates[pressIndex])
            scaleTemplateVolume(template, pressCount)
        elseif tier <= 0 then
            template = Runtime.copy(Runtime.starterTemplate)
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
        if not pressJob then scaleTemplateVolume(template, cutterCount) end
        if not pressJob and sequence > 5 then
            local companies = Runtime.additionalCuttingCompanies
            template.company = companies[(sequence - 6) % #companies + 1]
        end
        template.id = Runtime.Jobs.formatId(sequence)
        template.sequence = sequence
        template.createdAt = timestamp
        if pressJob then
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
