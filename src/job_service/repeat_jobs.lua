-- Client email state, repeat offers, and delayed arrivals.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}
local CustomerDemand = require("src.customer_demand")
local Progression = require("src.job_progression")

function Component.install(Runtime)
    function Runtime.ensureEmails(state)
        return Runtime.Inbox.ensure(state)
    end

    function Runtime.nextEmailNumber(emails)
        local number = math.max(1, math.floor(tonumber(emails.nextEmailId) or 1))
        emails.nextEmailId = number + 1
        return number
    end

    function Runtime.emailDelay(job, minimum, span)
        local hash = Runtime.stableDeliveryHash(job, job and job.sequence)
        return minimum + (hash * 7) % math.max(1, span)
    end

    function Runtime.JobService.expectedStockArrivalText(state, job)
        local service = job and Runtime.deliveryService(job, job.sequence)
        if not service then return "Not assigned" end
        local now = Runtime.BusinessCalendar.absoluteHours(state)
        local clientReplyHours = Runtime.emailDelay(job, 1, 3)
        local settings = Runtime.App and Runtime.App.settings
        local hours=require('src.business_hours')
        return Runtime.BusinessCalendar.dateTimeTextAtHours(hours.nextService(hours.nextService(now + clientReplyHours)
            + (tonumber(service.delayHours) or 0)),
            not (settings and settings.twelveHourTime==false))
    end

    function Runtime.estimateRequestEmail(state, job)
        local emails = Runtime.ensureEmails(state)
        local number = Runtime.nextEmailNumber(emails)
        local now = Runtime.BusinessCalendar.absoluteHours(state)
        local followupLimit = 1 + Runtime.stableDeliveryHash(job, job.sequence) % 2
        job.requestChannel = "email"
        job.estimate = {
            stage = "awaiting_details",
            requestedAtHours = now,
            followupCount = 0,
            followupLimit = followupLimit,
        }
        return {
            id = string.format("EMAIL-%04d", number),
            sender = job.company,
            subject = "Job details for " .. job.id,
            body = job.outboundDelivery and job.outboundDelivery.requested
                and "Please review the job details and send a production estimate. Include shop delivery as a separate option; we may arrange our own transportation if the fee does not work for us."
                or "Please review the job details and send a production estimate. We will arrange our own transportation for the shipment.",
            sourceJobId = job.id,
            readyAtHours = require('src.business_hours').nextService(now + Runtime.emailDelay(job, 2, 5)),
            estimateRequest = true,
            followupCount = 0,
            followupLimit = followupLimit,
            followupIntervalHours = 24,
            job = job,
        }
    end

    function Runtime.JobService.requestEstimateDetails(state, job, timestamp)
        if type(state) ~= "table" or type(job) ~= "table" then
            return false, "state and job are required"
        end
        if job.status ~= "offered" then return false, "job is no longer available for estimating" end
        local email = Runtime.estimateRequestEmail(state, job)
        job.detailsRequestedAt = timestamp
        Runtime.ensureEmails(state).pending[#Runtime.ensureEmails(state).pending + 1] = email
        -- The walk-in has consumed this reception number even though no job has
        -- been awarded yet. Email-originated repeat jobs already own independent IDs.
        if tostring(job.id or ""):match("^JOB%-%d+$") then
            state.nextJobId = Runtime.nextSequence(state) + 1
        end
        return true, email
    end

    function Runtime.repeatArtwork(state, sequence)
        local artwork = Runtime.Config.artworkOrder or {}
        if #artwork == 0 then return "flower" end
        local hash = (Runtime.artworkSeed(state) + sequence * 2654435761) % 2147483647
        return artwork[hash % #artwork + 1]
    end

    function Runtime.repeatOffer(state, completedJob, emailNumber)
        local _, tier = Runtime.Reputation.tier(Runtime.Reputation.ensure(state))
        local maximumPallets = tier <= 1 and 1 or tier == 2 and 2 or 3
        local maximumLiftGroups = tier <= 1 and 2 or tier == 2 and 4 or 6
        local palletCount = 1 + (emailNumber - 1) % maximumPallets
        local sheetCounts, requestedCopies = {}, {}
        for index = 1, palletCount do
            sheetCounts[index] = 500 * (1 + (emailNumber + index - 2) % maximumLiftGroups)
        end
        for index, suppliedSheets in ipairs(sheetCounts) do
            local allowance = completedJob.press and math.max(50, math.ceil(suppliedSheets * 0.03)) or 0
            requestedCopies[index] = suppliedSheets - allowance
        end
        sheetCounts, requestedCopies = Progression.scaleSheetCounts(sheetCounts, requestedCopies,
            1, Progression.liftBudget(state), Runtime.Jobs.MAX_PALLETS,
            Progression.hasProductionTeam(state))
        local source = Runtime.copy(completedJob.sourceSize)
        local finished = Runtime.copy(completedJob.finishedSize)
        if emailNumber % 2 == 0 and source.width ~= source.height then
            source.width, source.height = source.height, source.width
            finished.width, finished.height = finished.height, finished.width
        end
        -- Older completed tickets may have had flush or barely visible edges.
        -- The new shipment needs trim room, while its finished order stays exact.
        source.width = math.max(source.width, finished.width + Runtime.Jobs.MIN_STOCK_EXCESS)
        source.height = math.max(source.height, finished.height + Runtime.Jobs.MIN_STOCK_EXCESS)
        local artworkKey = Runtime.repeatArtwork(state, emailNumber)
        local artworkSize = completedJob.press and Runtime.copy(completedJob.press.artworkSize) or Runtime.copy(finished)
        local stockSpec = Runtime.copy(completedJob.stockSpec)
        local spec = {
            id = string.format("EMAIL-JOB-%04d", emailNumber),
            company = completedJob.company,
            customerDestination = completedJob.customerDestination,
            sourceSize = source,
            finishedSize = finished,
            sheetCounts = sheetCounts,
            packaging = emailNumber % 2 == 0 and "boxed" or "flat",
            difficulty = Progression.capDifficulty(state, tier <= 1 and "easy"
                or tier == 2 and (emailNumber % 3 == 0 and "medium" or "easy")
                or tier == 3 and ({ "easy", "medium", "hard" })[(emailNumber - 1) % 3 + 1]
                or ({ "medium", "hard", "hard" })[(emailNumber - 1) % 3 + 1],
                completedJob.press and "press" or "cutter"),
            artworkKey = artworkKey,
            artwork = Runtime.artworkRecord(artworkKey, artworkSize),
            stockSpec = stockSpec,
            requestChannel = "email",
            deliveryService = Runtime.deliveryService(completedJob, emailNumber),
            outboundDelivery = Runtime.outboundDeliveryRequest(completedJob, emailNumber),
            details = {
                stockDescription = stockSpec and stockSpec.description or "Repeat-client supplied stock",
                dueDate = emailNumber % 3 == 0 and "Priority repeat order" or "Standard repeat-order turnaround",
                grainDirection = "Follow the new pallet labels",
                notes = "Returning customer. Treat this as a new order and keep it separate from prior work.",
            },
        }
        if completedJob.press then
            spec.press = Runtime.copy(completedJob.press)
            spec.press.plates, spec.press.actual = nil, nil
            spec.press.orderedQuantity, spec.press.suppliedSheets, spec.press.spoilageAllowance = nil, nil, nil
            spec.press.artworkSize = artworkSize
            spec.press.requestedCopies = requestedCopies
        end
        local offer, errors = Runtime.Jobs.createOffer(spec)
        if not offer then return nil, errors end
        return Runtime.decorateOfferForReputation(state, offer, emailNumber)
    end

    function Runtime.JobService.scheduleRepeatEmail(state, completedJob)
        if type(completedJob) ~= "table" or completedJob.status ~= "completed" then return false end
        local emails = Runtime.ensureEmails(state)
        local number = emails.nextEmailId
        local offer = Runtime.repeatOffer(state, completedJob, number)
        if not offer then return false end
        local appliedCoupon,couponPrices=Runtime.applyAvailablePromotionCoupon(state,offer)
        local followupHours = math.floor((1 + number % 3) * 24
            * CustomerDemand.delayMultiplier(state) + 0.5)
        emails.nextEmailId = number + 1
        local email={
            id = string.format("EMAIL-%04d", number),
            sender = completedJob.company,
            subject = completedJob.press and "Request for another print job" or "Request for another cutting job",
            body = completedJob.press
                and "Please quote another cut-and-print job for us."
                or "Please quote another paper-cutting job for us.",
            sourceJobId = completedJob.id,
            readyAtHours = require('src.business_hours').nextService(Runtime.BusinessCalendar.absoluteHours(state) + followupHours),
            job = offer,
        }
        if couponPrices then
            email.promotionId=appliedCoupon.id
            email.standardPrice=couponPrices.standardPrice
            email.discountAmount=couponPrices.discountAmount
            email.discountedTotal=couponPrices.discountedTotal
            email.body=email.body.." Your 10% coupon is applied."
        end
        emails.pending[#emails.pending + 1] = email
        return true
    end

    function Runtime.JobService.updateClientEmails(state)
        local emails = Runtime.ensureEmails(state)
        -- Leave client replies and estimate decisions queued overnight/weekends.
        if not Runtime.BusinessCalendar.isBusinessOpen(state) then return false end
        local now = Runtime.BusinessCalendar.absoluteHours(state)
        local delivered = false

        -- Promotions sent by older saves could be marked silent forever. Give
        -- each of those clients one durable reply under the current email flow.
        for _,promotion in ipairs(emails.sentPromotions) do
            if promotion.responseOutcome=="no_response" then
                promotion.responseOutcome="thank_you"
                local number=Runtime.nextEmailNumber(emails)
                Runtime.Inbox.addNotice(state,{
                    id=string.format("EMAIL-%04d",number),
                    sender=promotion.recipient,
                    subject="Thank you for the 10% offer",
                    body="Thanks for the coupon. We do not have a new job right now, but we will use it on our next order.",
                    noticeKind="client_thanks",
                    sourceJobId=promotion.sourceJobId,
                },0)
                Runtime.applyCouponToNextPendingOrder(state,promotion.recipient)
                delivered=true
            end
        end

        -- A client follows up once or twice if their written request is sitting
        -- unanswered. The reminders stop after that limit; the request remains
        -- available for an estimate or an explicit decline.
        for _, email in ipairs(emails.inbox) do
            if email.estimateRequest and email.job and email.nextFollowupAtHours
                and now + 0.000001 >= email.nextFollowupAtHours
            then
                email.followupCount = math.floor(tonumber(email.followupCount) or 0) + 1
                local limit = math.max(1, math.floor(tonumber(email.followupLimit) or 1))
                email.subject = string.format("Follow-up %d: estimate for %s",
                    email.followupCount, email.job.id)
                email.body = "Just following up on the job specifications we emailed. Please send an estimate or let us know if you are declining the work."
                email.receivedAtHours = now
                email.unread = true
                email.job.estimate = email.job.estimate or {}
                email.job.estimate.followupCount = email.followupCount
                email.nextFollowupAtHours = email.followupCount < limit
                    and require('src.business_hours').nextService(now + math.max(1, tonumber(email.followupIntervalHours) or 24)) or nil
                delivered = true
            end
        end
        for index = #emails.pending, 1, -1 do
            local pending = emails.pending[index]
            if pending.estimateReply and pending.job then
                local sentAtHours = tonumber(pending.job.estimate and pending.job.estimate.sentAtHours)
                if sentAtHours then
                    pending.readyAtHours = require('src.business_hours').nextService(math.min(tonumber(pending.readyAtHours) or sentAtHours,
                        sentAtHours + Runtime.emailDelay(pending.job, 1, 3)))
                end
            end
            if now + 0.000001 >= emails.pending[index].readyAtHours then
                local email = table.remove(emails.pending, index)
                email.receivedAtHours = now
                email.unread = true
                email.awaitingReply = nil
                if email.estimateReply and email.job then
                    local job = email.job
                    local succeeded
                    if email.accepted then
                        local outbound = job.outboundDelivery
                        if type(outbound) == "table" then
                            local productionPrice = math.floor(tonumber(job.quote and job.quote.playerPrice)
                                or tonumber(email.quotedPrice) or 0)
                            local deliveryPrice = math.floor(tonumber(email.quotedDeliveryPrice) or 0)
                            local acceptedDelivery = email.offeredDelivery == true
                                and email.deliveryAccepted == true
                                and outbound.requested == true
                            outbound.offered = email.offeredDelivery == true
                            outbound.quotedPrice = email.offeredDelivery and deliveryPrice or nil
                            outbound.transport = acceptedDelivery and "shop" or "customer"
                            job.quote.totalPrice = productionPrice + (acceptedDelivery and deliveryPrice or 0)
                        end
                        succeeded = Runtime.JobService.acceptOffer(state, job, os.time())
                    else
                        if type(email.job.outboundDelivery) == "table" then
                            email.job.outboundDelivery.transport = "customer"
                        end
                        succeeded = Runtime.JobService.declineOffer(state, job, os.time())
                    end
                    if succeeded then
                        job.estimate = job.estimate or {}
                        job.estimate.stage = email.accepted and "accepted" or "declined"
                        job.estimate.respondedAtHours = now
                        email.noticeKind = email.accepted
                            and "client_estimate_accepted" or "client_estimate_declined"
                        email.subject = email.accepted
                            and ("Estimate accepted: " .. job.id)
                            or ("Estimate declined: " .. job.id)
                        local productionPrice = math.floor(tonumber(email.quotedPrice) or 0)
                        local deliveryPrice = math.floor(tonumber(email.quotedDeliveryPrice) or 0)
                        if not email.accepted then
                            email.body = string.format("Thank you for the $%d production estimate. We have decided not to proceed.",
                                productionPrice)
                        elseif email.offeredDelivery and email.deliveryAccepted then
                            email.body = string.format("We accept your $%d production estimate and $%d delivery quote ($%d total). Please proceed with the job and shop delivery.",
                                productionPrice, deliveryPrice, productionPrice + deliveryPrice)
                        elseif email.offeredDelivery then
                            email.body = string.format("We accept your $%d production estimate, but will arrange our own transportation rather than the $%d shop delivery. Please proceed with the job.",
                                productionPrice, deliveryPrice)
                        else
                            email.body = string.format("We accept your $%d production estimate. We will arrange our own transportation for the shipment.",
                                productionPrice)
                        end
                        email.responseOutcome = email.accepted and "accepted" or "declined"
                        for _, archived in ipairs(emails.archive) do
                            if archived.jobId == job.id and archived.response == "estimate_sent" then
                                archived.response = email.accepted and "accepted" or "declined"
                                archived.subject = email.subject
                                archived.body = email.body
                                archived.respondedAtHours = now
                                break
                            end
                        end
                        email.job = nil
                    end
                elseif email.job then
                    email.estimateRequest = true
                    email.followupCount = math.max(0, math.floor(tonumber(email.followupCount) or 0))
                    email.followupLimit = math.max(1, math.floor(tonumber(email.followupLimit)
                        or (1 + Runtime.stableDeliveryHash(email.job, email.job.sequence) % 2)))
                    email.followupIntervalHours = math.max(1,
                        tonumber(email.followupIntervalHours) or 24)
                    email.job.estimate = email.job.estimate or {}
                    email.job.estimate.stage = "ready_to_quote"
                    email.nextFollowupAtHours = now
                        + email.followupIntervalHours
                end
                emails.inbox[#emails.inbox + 1] = email
                delivered = true
            end
        end
        if delivered then state.message = "New email received. Check the office computer." end
        return delivered
    end
end

return Component
