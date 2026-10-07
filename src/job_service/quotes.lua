-- Quote terms, reputation effects, and email estimates.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.completedRelationship(state, company)
        local count = 0
        for _, job in ipairs((state.jobs and state.jobs.completed) or {}) do
            if job.company == company then count = count + 1 end
        end
        return count
    end

    function Runtime.quoteRoll(job, amount, relationship)
        local hash = math.floor(amount * 100 + relationship * 7919)
        for index = 1, #(job.id or "JOB") do
            hash = (hash * 33 + string.byte(job.id, index)) % 2147483647
        end
        return (hash % 10000) / 10000
    end

    function Runtime.decorateOfferForReputation(state, offer, sequence)
        if not offer then return offer end
        local reputation = Runtime.Reputation.ensure(state)
        local tierName, tier = Runtime.Reputation.tier(reputation)
        local demanding = tier >= 3 and sequence % 3 == 0
        local difficultyMultiplier = offer.difficulty == "hard" and 1.60
            or offer.difficulty == "medium" and 1.35 or 1
        local multiplier = Runtime.Reputation.priceMultiplier(state) * difficultyMultiplier
            * (demanding and 1.10 or 1)
        offer.reputationTier = tierName
        offer.clientTemperament = demanding and "demanding" or (tier <= 0 and "cautious" or "standard")
        offer.clientTemperamentNote = demanding
            and "Higher budget, exacting standards, and a larger reputation penalty for spoiled stock."
            or tier == 0 and "A small trial order because the shop has no track record yet."
            or tier < 0 and "A small recovery order because prior spoilage damaged the shop's reputation."
            or "Normal commercial client expectations."
        offer.quote.totalPrice = math.max(1, math.floor(offer.quote.totalPrice * multiplier + 0.5))
        offer.quote.servicePrice = offer.quote.totalPrice
        offer.quote.totalPrice,offer.quote.employeeBudget=Runtime.Labor.price(state,offer,offer.quote.servicePrice)
        offer.quote.recommendedPrice = offer.quote.totalPrice
        return offer
    end

    function Runtime.JobService.quoteTerms(state, job, amount)
        if type(job) ~= "table" or type(job.quote) ~= "table" then return nil end
        local base = math.max(1, math.floor(tonumber(job.quote.recommendedPrice)
            or tonumber(job.quote.totalPrice) or 1))
        local servicePrice=job.quote.servicePrice or base
        local budget=job.quote.employeeBudget
        if job.status=="offered" and not job.quote.playerPrice and not job.promotionDiscount
            and not (job.estimate and job.estimate.stage=="awaiting_reply") then
            base,budget=Runtime.Labor.price(state,job,servicePrice)
            if budget then
                -- Keep an employee quote above the shop's modeled direct cost per
                -- lift, including the negotiated payroll and machine allowance.
                -- This keeps small jobs from underpricing the staffed workflow.
                local finances=require("src.staff_finances").summary(state)
                local lifts=math.max(1,math.floor(tonumber(job.quote.totalLifts) or 1))
                base=math.max(base,math.ceil(finances.pricePerLift*lifts*100-1e-7)/100)
            end
        end
        amount = math.max(1, math.floor(tonumber(amount) or base))
        local serviceId = job.deliveryService and job.deliveryService.id or "standard"
        local urgency = serviceId == "express" and 1.40 or serviceId == "quick" and 1.25 or 1.15
        local relationship = Runtime.completedRelationship(state, job.company)
        local reputation = Runtime.Reputation.ensure(state)
        local reputationRoom = math.max(0, reputation.score) * 0.0025
        local temperamentRoom = job.clientTemperament == "demanding" and 0.10 or 0
        local ceiling = base * (urgency + math.min(0.15, relationship * 0.03)
            + reputationRoom + temperamentRoom)
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
            servicePrice = servicePrice,
            employeeBudget = budget,
            maximumPrice = math.floor(ceiling + 0.5),
            acceptanceChance = math.max(0.05, math.min(1, chance)),
            urgency = serviceId,
            relationshipJobs = relationship,
            reputationScore = reputation.score,
            clientTemperament = job.clientTemperament or "standard",
        }
    end

    function Runtime.JobService.submitQuote(state, job, amount, timestamp)
        if not job or job.status~="offered" then return false,"This customer's agreed price is already fixed." end
        local terms = Runtime.JobService.quoteTerms(state, job, amount)
        if not terms then return false, "quote paperwork is missing" end
        local accepted = Runtime.quoteRoll(job, terms.amount, terms.relationshipJobs) <= terms.acceptanceChance
        job.quote.recommendedPrice = terms.recommendedPrice
        job.quote.servicePrice=terms.servicePrice;job.quote.employeeBudget=terms.employeeBudget
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
        if accepted then succeeded, result = Runtime.JobService.acceptOffer(state, job, timestamp)
        else succeeded, result = Runtime.JobService.declineOffer(state, job, timestamp) end
        if not succeeded then return false, result end
        return true, {
            accepted = accepted,
            job = job,
            amount = terms.amount,
            acceptanceChance = terms.acceptanceChance,
            recommendedPrice = terms.recommendedPrice,
        }
    end

    function Runtime.JobService.submitEmailQuote(state, emailId, amount, timestamp)
        local email, index = Runtime.emailById(state, emailId)
        if not email then return false, "email request was not found" end
        if not email.job then return false, "email does not contain an estimate request" end
        local terms = Runtime.JobService.quoteTerms(state, email.job, amount)
        if not terms then return false, "estimate paperwork is missing" end
        local job = email.job
        local now = Runtime.BusinessCalendar.absoluteHours(state)
        local accepted = Runtime.quoteRoll(job, terms.amount, terms.relationshipJobs) <= terms.acceptanceChance
        job.quote.recommendedPrice = terms.recommendedPrice
        job.quote.servicePrice=terms.servicePrice;job.quote.employeeBudget=terms.employeeBudget
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
        job.estimate = job.estimate or {}
        job.estimate.stage = "awaiting_reply"
        job.estimate.sentAtHours = now
        job.estimate.expiresAtHours = now + 72
        job.estimate.amount = terms.amount
        table.remove(state.clientEmails.inbox, index)
        state.clientEmails.archive[#state.clientEmails.archive + 1] = {
            id = email.id, sender = email.sender, subject = email.subject,
            body = string.format("A $%d estimate was sent for %s. The client reply is pending.",
                terms.amount, job.id),
            jobId = job.id,
            response = "estimate_sent",
            quotedPrice = terms.amount,
            acceptanceChance = terms.acceptanceChance,
            respondedAtHours = now,
            expiresAtHours = job.estimate.expiresAtHours,
        }
        local replyNumber = Runtime.nextEmailNumber(state.clientEmails)
        state.clientEmails.pending[#state.clientEmails.pending + 1] = {
            id = string.format("EMAIL-%04d", replyNumber),
            sender = job.company,
            subject = "Reply to estimate for " .. job.id,
            body = "The client is reviewing your estimate.",
            sourceJobId = job.id,
            readyAtHours = now + Runtime.emailDelay(job, 1, 3),
            expiresAtHours = job.estimate.expiresAtHours,
            quotedPrice = terms.amount,
            accepted = accepted,
            estimateReply = true,
            job = job,
        }
        return true, {
            accepted = nil,
            job = job,
            amount = terms.amount,
            acceptanceChance = terms.acceptanceChance,
            recommendedPrice = terms.recommendedPrice,
            expiresAtHours = job.estimate.expiresAtHours,
        }
    end
end

return Component
