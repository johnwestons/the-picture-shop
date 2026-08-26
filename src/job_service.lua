-- Connects pure job-domain rules to the game's saved shop state.
local Jobs = require("src.jobs")
local PalletState = require("src.pallet_state")
local Config = require("src.config")
local BusinessCalendar = require("src.business_calendar")
local MachineFleet = require("src.machine_fleet")

local JobService = {}

local DELIVERY_SERVICES = {
    express = { id = "express", label = "EXPRESS / URGENT", description = "Arrives within hours" },
    quick = { id = "quick", label = "QUICK", description = "Arrives the next day" },
    standard = { id = "standard", label = "STANDARD", description = "Arrives in 2-3 days" },
}

local templates = {
    {
        difficulty = "easy",
        company = "Blue Ridge Packaging",
        sourceSize = { width = 25, height = 19 },
        finishedSize = { width = 12.5, height = 9.5 },
        sheetCounts = { 1000, 750 },
        packaging = "boxed",
        details = {
            stockDescription = "80 lb customer-supplied cover stock",
            dueDate = "Standard 5-business-day turnaround",
            grainDirection = "Grain long; keep orientation consistent",
            notes = "Keep the two pallets separated and retain all customer skid labels.",
        },
    },
    {
        difficulty = "medium",
        company = "Northstar Bindery",
        sourceSize = { width = 23, height = 17.5 },
        finishedSize = { width = 11.5, height = 8.75 },
        sheetCounts = { 1500 },
        packaging = "flat",
        details = {
            stockDescription = "100 lb gloss text",
            dueDate = "Standard 5-business-day turnaround",
            grainDirection = "Grain long",
            notes = "Protect the gloss surface and wrap the finished skid before pickup.",
        },
    },
    {
        difficulty = "hard",
        company = "Keystone Paper Supply",
        sourceSize = { width = 25, height = 25 },
        finishedSize = { width = 20, height = 12.5 },
        sheetCounts = { 3000, 3000, 2000 },
        packaging = "flat",
        details = {
            stockDescription = "Uncoated offset sheets",
            dueDate = "Standard 7-business-day turnaround",
            grainDirection = "Grain short",
            notes = "Count and label every finished pallet separately.",
        },
    },
}

local pressTemplates = {
    {
        difficulty = "easy",
        company = "Foundry Coffee Roasters",
        sourceSize = { width = 10, height = 15 },
        finishedSize = { width = 5, height = 7 },
        sheetCounts = { 1050 },
        packaging = "flat",
        artworkKey = "ad-garlic-bread",
        artwork = { key = "ad-garlic-bread", displayName = "Foundry Coffee Table Card",
            fileName = "foundry-coffee-table-card.png", suppliedBy = "client", orientation = "portrait" },
        stockSpec = { suppliedBy = "client", grade = "cover", weight = 80, finish = "uncoated",
            color = "natural white", grain = "long", description = "80 lb uncoated cover" },
        press = { colors = 1, coverage = 0.32, artworkSize = { width = 4.25, height = 6.25 },
            colorSequence = { "Black" }, requestedCopies = { 1000 } },
        details = { stockDescription = "80 lb uncoated cover", dueDate = "Five business days",
            grainDirection = "Grain long", notes = "Client supplied final artwork and 50 extra sheets for setup and spoilage." },
    },
    {
        difficulty = "hard",
        company = "Lantern House Events",
        sourceSize = { width = 10, height = 15 },
        finishedSize = { width = 7, height = 10 },
        sheetCounts = { 1575 },
        packaging = "boxed",
        artworkKey = "ad-fashion-tailored",
        artwork = { key = "ad-fashion-tailored", displayName = "Lantern House Gala Invitation",
            fileName = "lantern-house-gala-invitation.png", suppliedBy = "client", orientation = "portrait" },
        stockSpec = { suppliedBy = "client", grade = "cover", weight = 100, finish = "gloss",
            color = "bright white", grain = "long", description = "100 lb gloss cover" },
        press = { colors = 2, coverage = 0.48, artworkSize = { width = 6.25, height = 9 },
            colorSequence = { "Warm Red", "Black" }, requestedCopies = { 1500 } },
        details = { stockDescription = "100 lb gloss cover", dueDate = "Seven business days",
            grainDirection = "Grain long", notes = "Client supplied final gala artwork and 75 extra sheets; hold tight register." },
    },
    {
        difficulty = "medium",
        company = "Maple Street Books",
        sourceSize = { width = 10, height = 15 },
        finishedSize = { width = 6, height = 9 },
        sheetCounts = { 2100 },
        packaging = "flat",
        artworkKey = "ad-photos",
        artwork = { key = "ad-photos", displayName = "Maple Street Reading Series Poster",
            fileName = "maple-street-reading-series.png", suppliedBy = "client", orientation = "portrait" },
        stockSpec = { suppliedBy = "client", grade = "cover", weight = 90, finish = "uncoated",
            color = "cream", grain = "long", description = "90 lb cream uncoated cover" },
        press = { colors = 2, coverage = 0.42, artworkSize = { width = 5.4, height = 8.25 },
            colorSequence = { "Forest Green", "Black" }, requestedCopies = { 2000 } },
        details = { stockDescription = "90 lb cream uncoated cover", dueDate = "Six business days",
            grainDirection = "Grain long", notes = "Client supplied poster art and 100 extra sheets for proofing and spoilage." },
    },
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function artworkName(key)
    local value = tostring(key or "artwork"):gsub("[-_]", " ")
    return (value:gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
end

local function artworkRecord(key, artworkSize)
    return {
        key = key,
        displayName = artworkName(key),
        fileName = key .. ".png",
        suppliedBy = "client",
        orientation = artworkSize and artworkSize.width > artworkSize.height and "landscape" or "portrait",
    }
end

local function nextSequence(state)
    local sequence = type(state.nextJobId) == "number" and math.floor(state.nextJobId) or 1
    return math.max(1, sequence)
end

-- Keep the choice stable for a given job number so it survives save/load,
-- while still distributing the full artwork library unpredictably.
local function artworkSeed(state)
    state.jobs = type(state.jobs) == "table" and state.jobs or {}
    if type(state.jobs.artworkSeed) ~= "number" then
        local timerPart = love and love.timer and math.floor(love.timer.getTime() * 100000) or 0
        state.jobs.artworkSeed = (os.time() * 1009 + timerPart) % 2147483647
    end
    return state.jobs.artworkSeed
end

local function artworkForSequence(state, sequence)
    local artwork = Config.artworkOrder or {}
    if #artwork == 0 then return "flower" end
    local hash = (sequence * 1103515245 + artworkSeed(state) * 1664525 + 12345) % 2147483648
    return artwork[(hash % #artwork) + 1]
end

local function stableDeliveryHash(job, sequence)
    if type(sequence) == "number" then return math.max(1, math.floor(sequence)) end
    local hash = 0
    for index = 1, #(job and job.id or "job") do
        hash = (hash * 31 + string.byte(job.id, index)) % 2147483647
    end
    return hash
end

local function deliveryService(job, sequence)
    local hash = stableDeliveryHash(job, sequence)
    local order = { "express", "quick", "standard" }
    local id = order[(hash - 1) % #order + 1]
    local service = copy(DELIVERY_SERVICES[id])
    if id == "express" then
        service.delayHours = 2 + (hash * 3) % 5 -- deterministic 2-6 hour window
    elseif id == "quick" then
        service.delayHours = 24
    else
        service.delayHours = (2 + hash % 2) * 24
    end
    return service
end

function JobService.deliveryServiceFor(job, sequence)
    return deliveryService(job, sequence)
end

local function ensureEmails(state)
    state.clientEmails = type(state.clientEmails) == "table" and state.clientEmails or {}
    local emails = state.clientEmails
    emails.nextEmailId = math.max(1, math.floor(tonumber(emails.nextEmailId) or 1))
    emails.pending = type(emails.pending) == "table" and emails.pending or {}
    emails.inbox = type(emails.inbox) == "table" and emails.inbox or {}
    emails.archive = type(emails.archive) == "table" and emails.archive or {}
    emails.sentPromotions = type(emails.sentPromotions) == "table" and emails.sentPromotions or {}
    emails.nextPromotionId = math.max(1, math.floor(tonumber(emails.nextPromotionId) or 1))
    return emails
end

local function repeatArtwork(state, sequence)
    local artwork = Config.artworkOrder or {}
    if #artwork == 0 then return "flower" end
    local hash = (artworkSeed(state) + sequence * 2654435761) % 2147483647
    return artwork[hash % #artwork + 1]
end

local function repeatOffer(state, completedJob, emailNumber)
    local palletCount = 1 + emailNumber % 3
    local sheetCounts, requestedCopies = {}, {}
    for index = 1, palletCount do sheetCounts[index] = 500 * (1 + (emailNumber + index) % 6) end
    for index, suppliedSheets in ipairs(sheetCounts) do
        local allowance = completedJob.press and math.max(50, math.ceil(suppliedSheets * 0.03)) or 0
        requestedCopies[index] = suppliedSheets - allowance
    end
    local source = copy(completedJob.sourceSize)
    local finished = copy(completedJob.finishedSize)
    if emailNumber % 2 == 0 and source.width ~= source.height then
        source.width, source.height = source.height, source.width
        finished.width, finished.height = finished.height, finished.width
    end
    local artworkKey = repeatArtwork(state, emailNumber)
    local artworkSize = completedJob.press and copy(completedJob.press.artworkSize) or copy(finished)
    local stockSpec = copy(completedJob.stockSpec)
    local spec = {
        id = string.format("EMAIL-JOB-%04d", emailNumber),
        company = completedJob.company,
        sourceSize = source,
        finishedSize = finished,
        sheetCounts = sheetCounts,
        packaging = emailNumber % 2 == 0 and "boxed" or "flat",
        difficulty = ({ "easy", "medium", "hard" })[(emailNumber - 1) % 3 + 1],
        artworkKey = artworkKey,
        artwork = artworkRecord(artworkKey, artworkSize),
        stockSpec = stockSpec,
        requestChannel = "email",
        deliveryService = deliveryService(completedJob, emailNumber),
        details = {
            stockDescription = stockSpec and stockSpec.description or "Repeat-client supplied stock",
            dueDate = emailNumber % 3 == 0 and "Priority repeat order" or "Standard repeat-order turnaround",
            grainDirection = "Follow the new pallet labels",
            notes = "Returning customer. Treat this as a new order and keep it separate from prior work.",
        },
    }
    if completedJob.press then
        spec.press = copy(completedJob.press)
        spec.press.plates, spec.press.actual = nil, nil
        spec.press.orderedQuantity, spec.press.suppliedSheets, spec.press.spoilageAllowance = nil, nil, nil
        spec.press.artworkSize = artworkSize
        spec.press.requestedCopies = requestedCopies
    end
    return Jobs.createOffer(spec)
end

function JobService.scheduleRepeatEmail(state, completedJob)
    if type(completedJob) ~= "table" or completedJob.status ~= "completed" then return false end
    local emails = ensureEmails(state)
    local number = emails.nextEmailId
    local offer = repeatOffer(state, completedJob, number)
    if not offer then return false end
    local followupHours = (1 + number % 3) * 24
    emails.nextEmailId = number + 1
    emails.pending[#emails.pending + 1] = {
        id = string.format("EMAIL-%04d", number),
        sender = completedJob.company,
        subject = completedJob.press and "Request for another print job" or "Request for another cutting job",
        body = completedJob.press
            and "We were happy with the last order and would like a quote for another cut-and-print job."
            or "We were happy with the last order and would like a quote for another paper-cutting job.",
        sourceJobId = completedJob.id,
        readyAtHours = BusinessCalendar.absoluteHours(state) + followupHours,
        job = offer,
    }
    return true
end

function JobService.updateClientEmails(state)
    local emails = ensureEmails(state)
    local now = BusinessCalendar.absoluteHours(state)
    local delivered = false
    for index = #emails.pending, 1, -1 do
        if now + 0.000001 >= emails.pending[index].readyAtHours then
            local email = table.remove(emails.pending, index)
            email.receivedAtHours = now
            emails.inbox[#emails.inbox + 1] = email
            delivered = true
        end
    end
    if delivered then state.message = "A returning client sent a new job request. Check Email on the office computer." end
    return delivered
end

function JobService.emailInbox(state)
    local result = {}
    for _, notice in ipairs(MachineFleet.serviceInbox(state)) do result[#result + 1] = notice end
    for _, email in ipairs(ensureEmails(state).inbox) do result[#result + 1] = email end
    return result
end

local function emailById(state, emailId)
    for index, email in ipairs(ensureEmails(state).inbox) do
        if email.id == emailId then return email, index end
    end
end

function JobService.respondToEmail(state, emailId, response, timestamp)
    local email, index = emailById(state, emailId)
    if not email then return false, "email request was not found" end
    local succeeded, result
    if response == "accepted" then
        succeeded, result = JobService.acceptOffer(state, email.job, timestamp)
    elseif response == "declined" then
        succeeded, result = JobService.declineOffer(state, email.job, timestamp)
    else
        return false, "email response must be accepted or declined"
    end
    if not succeeded then return false, result end
    table.remove(state.clientEmails.inbox, index)
    state.clientEmails.archive[#state.clientEmails.archive + 1] = {
        id = email.id, sender = email.sender, subject = email.subject,
        jobId = email.job.id, response = response,
        respondedAtHours = BusinessCalendar.absoluteHours(state),
    }
    return true, email.job
end

local function completedRelationship(state, company)
    local count = 0
    for _, job in ipairs((state.jobs and state.jobs.completed) or {}) do
        if job.company == company then count = count + 1 end
    end
    return count
end

local function quoteRoll(job, amount, relationship)
    local hash = math.floor(amount * 100 + relationship * 7919)
    for index = 1, #(job.id or "JOB") do
        hash = (hash * 33 + string.byte(job.id, index)) % 2147483647
    end
    return (hash % 10000) / 10000
end

function JobService.quoteTerms(state, job, amount)
    if type(job) ~= "table" or type(job.quote) ~= "table" then return nil end
    local base = math.max(1, math.floor(tonumber(job.quote.recommendedPrice)
        or tonumber(job.quote.totalPrice) or 1))
    amount = math.max(1, math.floor(tonumber(amount) or base))
    local serviceId = job.deliveryService and job.deliveryService.id or "standard"
    local urgency = serviceId == "express" and 1.40 or serviceId == "quick" and 1.25 or 1.15
    local relationship = completedRelationship(state, job.company)
    local ceiling = base * (urgency + math.min(0.15, relationship * 0.03))
    local chance
    if amount <= base then
        chance = 1
    elseif amount >= ceiling then
        chance = 0.05
    else
        local progress = (amount - base) / math.max(1, ceiling - base)
        chance = 0.88 - progress * 0.73
    end
    return {
        amount = amount,
        recommendedPrice = base,
        maximumPrice = math.floor(ceiling + 0.5),
        acceptanceChance = math.max(0.05, math.min(1, chance)),
        urgency = serviceId,
        relationshipJobs = relationship,
    }
end

function JobService.submitQuote(state, job, amount, timestamp)
    local terms = JobService.quoteTerms(state, job, amount)
    if not terms then return false, "quote paperwork is missing" end
    local accepted = quoteRoll(job, terms.amount, terms.relationshipJobs) <= terms.acceptanceChance
    job.quote.recommendedPrice = terms.recommendedPrice
    job.quote.playerPrice = terms.amount
    job.quote.totalPrice = terms.amount
    job.quoteProposal = {
        amount = terms.amount,
        recommendedPrice = terms.recommendedPrice,
        acceptanceChance = terms.acceptanceChance,
        maximumPrice = terms.maximumPrice,
        relationshipJobs = terms.relationshipJobs,
        accepted = accepted,
    }
    local succeeded, result
    if accepted then succeeded, result = JobService.acceptOffer(state, job, timestamp)
    else succeeded, result = JobService.declineOffer(state, job, timestamp) end
    if not succeeded then return false, result end
    return true, {
        accepted = accepted,
        job = job,
        amount = terms.amount,
        acceptanceChance = terms.acceptanceChance,
        recommendedPrice = terms.recommendedPrice,
    }
end

function JobService.submitEmailQuote(state, emailId, amount, timestamp)
    local email, index = emailById(state, emailId)
    if not email then return false, "email request was not found" end
    local succeeded, result = JobService.submitQuote(state, email.job, amount, timestamp)
    if not succeeded then return false, result end
    table.remove(state.clientEmails.inbox, index)
    state.clientEmails.archive[#state.clientEmails.archive + 1] = {
        id = email.id, sender = email.sender, subject = email.subject,
        jobId = email.job.id,
        response = result.accepted and "quote_accepted" or "quote_rejected",
        quotedPrice = result.amount,
        acceptanceChance = result.acceptanceChance,
        respondedAtHours = BusinessCalendar.absoluteHours(state),
    }
    return true, result
end

function JobService.sendPromotion(state, sourceJob, customMessage)
    if type(sourceJob) ~= "table" or sourceJob.status ~= "completed" then
        return false, "choose a completed client job first"
    end
    local emails = ensureEmails(state)
    local promoNumber, emailNumber = emails.nextPromotionId, emails.nextEmailId
    customMessage = tostring(customMessage or ""):sub(1, 240)
    local offer = repeatOffer(state, sourceJob, emailNumber)
    if not offer then return false, "could not prepare the promotional follow-up" end
    local standardPrice = offer.quote.totalPrice
    offer.quote.standardPrice = standardPrice
    offer.quote.totalPrice = math.max(1, math.floor(standardPrice * 0.90 + 0.5))
    offer.quote.recommendedPrice = offer.quote.totalPrice
    offer.promotionDiscount = 0.10
    emails.nextPromotionId = promoNumber + 1
    emails.nextEmailId = emailNumber + 1
    local promoId = string.format("PROMO-%04d", promoNumber)
    emails.sentPromotions[#emails.sentPromotions + 1] = {
        id = promoId, recipient = sourceJob.company, discountPercent = 10,
        customMessage = customMessage, sentAtHours = BusinessCalendar.absoluteHours(state),
    }
    emails.pending[#emails.pending + 1] = {
        id = string.format("EMAIL-%04d", emailNumber),
        sender = sourceJob.company,
        subject = "Reply to your 10% returning-client offer",
        body = sourceJob.press
            and "Thank you for the 10% offer. Please quote this new cut-and-print job using our attached artwork and specified stock."
            or "Thank you for the 10% offer. Please quote this new paper-cutting job for us.",
        sourceJobId = sourceJob.id,
        promotionId = promoId,
        readyAtHours = BusinessCalendar.absoluteHours(state) + 12,
        job = offer,
    }
    return true, emails.sentPromotions[#emails.sentPromotions]
end

local function offerHistory(state)
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

function JobService.createNextOffer(state, timestamp)
    if type(state) ~= "table" then return nil, { "shop state is required" } end
    local sequence = nextSequence(state)
    local pressInstalled = MachineFleet.isInstalled(state, "heidelberg_10x15")
    local anyPrint, receptionPrintCount, latestReceptionJob = offerHistory(state)
    local pressEnabled = pressInstalled and (not anyPrint
        or (latestReceptionJob and latestReceptionJob.press == nil))
    local template
    if pressEnabled then
        template = copy(pressTemplates[receptionPrintCount % #pressTemplates + 1])
    else
        template = copy(templates[(sequence - 1) % #templates + 1])
    end
    template.id = Jobs.formatId(sequence)
    template.sequence = sequence
    template.createdAt = timestamp
    if pressEnabled then
        template.artworkKey = template.artwork.key
    else
        template.artworkKey = artworkForSequence(state, sequence)
    end
    template.deliveryService = deliveryService(template, sequence)
    return Jobs.createOffer(template)
end

local function prepareCollections(state)
    state.jobs = type(state.jobs) == "table" and state.jobs or {}
    state.jobs.active = type(state.jobs.active) == "table" and state.jobs.active or {}
    state.jobs.completed = type(state.jobs.completed) == "table" and state.jobs.completed or {}
    state.jobs.declined = type(state.jobs.declined) == "table" and state.jobs.declined or {}
end

function JobService.acceptOffer(state, job, timestamp)
    if type(state) ~= "table" or type(job) ~= "table" then return false, "state and job are required" end
    local accepted, errorMessage = Jobs.accept(job, timestamp)
    if not accepted then return false, errorMessage end
    job.deliveryService = job.deliveryService or deliveryService(job, job.sequence)
    local acceptedGameHours = BusinessCalendar.absoluteHours(state)
    job.delivery = {
        status = "pending_arrival",
        service = copy(job.deliveryService),
        acceptedGameHours = acceptedGameHours,
        readyAtHours = acceptedGameHours + job.deliveryService.delayHours,
    }
    prepareCollections(state)
    state.jobs.active[#state.jobs.active + 1] = job
    state.accountsReceivable = math.max(0, state.accountsReceivable or 0) + job.quote.totalPrice
    if job.requestChannel ~= "email" then state.nextJobId = nextSequence(state) + 1 end
    return true, job
end

function JobService.deliveryReady(state, job)
    if type(job) ~= "table" or type(job.delivery) ~= "table" then return true end
    if type(job.delivery.readyAtHours) ~= "number" then return true end
    return BusinessCalendar.absoluteHours(state) + 0.000001 >= job.delivery.readyAtHours
end

function JobService.deliverySummary(job, state)
    local service = job and (job.deliveryService or (job.delivery and job.delivery.service))
    if not service then return "Delivery timing not assigned" end
    if state and job.delivery and not JobService.deliveryReady(state, job) then
        local remaining = math.max(0, job.delivery.readyAtHours - BusinessCalendar.absoluteHours(state))
        if remaining < 24 then
            return string.format("%s — about %d hour%s", service.label,
                math.max(1, math.ceil(remaining)), remaining > 1 and "s" or "")
        end
        return string.format("%s — about %d day%s", service.label,
            math.ceil(remaining / 24), remaining > 24 and "s" or "")
    end
    return service.label .. " — " .. service.description
end

function JobService.declineOffer(state, job, timestamp)
    if type(state) ~= "table" or type(job) ~= "table" then return false, "state and job are required" end
    local declined, errorMessage = Jobs.decline(job, timestamp)
    if not declined then return false, errorMessage end
    prepareCollections(state)
    state.jobs.declined[#state.jobs.declined + 1] = job
    if job.requestChannel ~= "email" then state.nextJobId = nextSequence(state) + 1 end
    return true, job
end

local function activeJob(state, jobId)
    prepareCollections(state)
    for index, job in ipairs(state.jobs.active) do
        if job.id == jobId then return job, index end
    end
end

function JobService.completionReady(job)
    if type(job) ~= "table" or job.status ~= "in_production"
        or type(job.pallets) ~= "table" or #job.pallets == 0
    then
        return false
    end
    for _, pallet in ipairs(job.pallets) do
        if (pallet.remainingSheets or 0) > 0 or pallet.status ~= "wrapped" or not pallet.wrapped then
            return false
        end
        if job.press and (type(pallet.press) ~= "table" or pallet.press.status ~= "complete") then
            return false
        end
    end
    return true
end

function JobService.requestPickup(state, job, timestamp)
    if type(state) ~= "table" or type(job) ~= "table" then return false, "state and job are required" end
    local active = activeJob(state, job.id)
    if active ~= job then return false, "job is not active" end
    if not JobService.completionReady(job) then
        return false, "every pallet must be finished and wrapped before pickup"
    end
    job.status = "ready_for_pickup"
    job.pickup = {
        status = "awaiting_schedule",
        requestedAt = timestamp,
    }
    job.pickupRequestedAtHours = BusinessCalendar.absoluteHours(state)
    return true, job
end

function JobService.nextPickup(state)
    prepareCollections(state)
    for _, job in ipairs(state.jobs.active) do
        local pickupStatus = job.pickup and job.pickup.status
        if job.status == "ready_for_pickup"
            or (job.status == "pickup_in_progress" and pickupStatus ~= "completed")
        then
            return job
        end
    end
end

function JobService.schedulePickup(job, timestamp)
    if type(job) ~= "table" or (job.status ~= "ready_for_pickup" and job.status ~= "pickup_in_progress") then
        return false, "job is not awaiting pickup"
    end
    job.pickup = type(job.pickup) == "table" and job.pickup or {}
    job.status = "pickup_in_progress"
    job.pickup.status = "scheduled"
    job.pickup.scheduledAt = timestamp
    return true, job
end

function JobService.setPickupStatus(job, status, timestampField, timestamp)
    if type(job) ~= "table" or job.status ~= "pickup_in_progress" then return false end
    job.pickup = type(job.pickup) == "table" and job.pickup or {}
    job.pickup.status = status
    if timestampField then job.pickup[timestampField] = timestamp end
    return true
end

function JobService.pickupInventory(state, jobId)
    local job = activeJob(state, jobId)
    local inventory = {}
    for _, pallet in ipairs(job and job.pallets or {}) do
        inventory[#inventory + 1] = {
            id = pallet.id,
            number = pallet.number,
            sheets = pallet.finishedSheets,
            location = pallet.location,
            status = pallet.status,
            paper = pallet.paper,
            pallet = pallet,
        }
    end
    return job, inventory
end

function JobService.remainingPickup(state, jobId)
    local _, inventory = JobService.pickupInventory(state, jobId)
    local remaining = 0
    for _, item in ipairs(inventory) do
        if item.location ~= "outbound_truck" and item.location ~= "none" then remaining = remaining + 1 end
    end
    return remaining
end

function JobService.loadForPickup(state, jobId, palletId, timestamp)
    local job = activeJob(state, jobId)
    if not job or job.status ~= "pickup_in_progress" then return false, "pickup is not in progress" end
    for _, pallet in ipairs(job.pallets or {}) do
        if pallet.id == palletId then
            if pallet.location == "outbound_truck" then return false, "that pallet is already on the truck" end
            if pallet.status ~= "wrapped" or not pallet.wrapped then return false, "that pallet is not wrapped" end
            if pallet.location ~= "warehouse" and pallet.location ~= "cutter_output"
                and pallet.location ~= "press_output" then
                return false, "lower the wrapped pallet onto the warehouse floor before loading"
            end
            local transitioned, transitionError = PalletState.transition(
                state, pallet, "outbound_truck", { status = "loaded_for_pickup" })
            if not transitioned then return false, transitionError end
            state.inventory.finishedPallets = math.max(0, (state.inventory.finishedPallets or 0) - 1)
            local remaining = JobService.remainingPickup(state, jobId)
            JobService.setPickupStatus(job, remaining == 0 and "loaded" or "loading",
                remaining == 0 and "loadedAt" or nil, timestamp)
            return true, pallet, remaining
        end
    end
    return false, "the pickup pallet was not found"
end

function JobService.completePickup(state, jobId, timestamp)
    local job, activeIndex = activeJob(state, jobId)
    if not job or job.status ~= "pickup_in_progress" then return false, "pickup is not in progress" end
    if JobService.remainingPickup(state, jobId) ~= 0 then return false, "pickup pallets remain on the floor" end
    for _, pallet in ipairs(job.pallets or {}) do
        if pallet.location ~= "outbound_truck" then return false, "pickup manifest is incomplete" end
    end
    for _, pallet in ipairs(job.pallets or {}) do
        local transitioned, transitionError = PalletState.transition(
            state, pallet, "none", { status = "picked_up" })
        if not transitioned then return false, transitionError end
        pallet.pickedUpAt = timestamp
    end
    local payment = job.quote.totalPrice
    job.status = "completed"
    job.completedAt = timestamp
    job.completedAtHours = BusinessCalendar.absoluteHours(state)
    job.paidAt = timestamp
    job.paymentAmount = payment
    job.pickup.status = "completed"
    job.pickup.completedAt = timestamp
    table.remove(state.jobs.active, activeIndex)
    state.jobs.completed[#state.jobs.completed + 1] = job
    state.accountsReceivable = math.max(0, (state.accountsReceivable or 0) - payment)
    state.money = math.max(0, state.money or 0) + payment
    JobService.scheduleRepeatEmail(state, job)
    return true, job, payment
end

function JobService.templates()
    return copy(templates)
end

function JobService.printTemplates()
    return copy(pressTemplates)
end

return JobService
