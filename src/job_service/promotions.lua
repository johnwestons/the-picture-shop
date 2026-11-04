-- Promotion terms and client follow-up offers.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}
local CustomerDemand = require("src.customer_demand")

local function discountOffer(offer)
    if type(offer)~="table" or type(offer.quote)~="table" or offer.promotionDiscount then return nil end
    local quote=offer.quote
    local standardPrice=math.max(1,math.floor(tonumber(quote.totalPrice) or 1))
    local discountedTotal=math.max(1,math.floor(standardPrice*.90+.5))
    quote.totalPrice=discountedTotal
    quote.recommendedPrice=discountedTotal
    if quote.servicePrice then quote.servicePrice=math.max(1,math.floor(quote.servicePrice*.90+.5)) end
    offer.promotionDiscount=.10
    return {
        standardPrice=standardPrice,
        discountAmount=standardPrice-discountedTotal,
        discountedTotal=discountedTotal,
    }
end

function Component.install(Runtime)
    function Runtime.JobService.promotionTerms(state, customMessage)
        local messageLength = #tostring(customMessage or "")
        local month = state and state.calendar and state.calendar.month or 1
        local season = CustomerDemand.seasonForMonth(month)
        -- A quiet season still gives a returning client a reason to reply.
        -- Seasonal demand changes whether that reply contains a new order.
        local chance = math.max(0.28, math.min(0.76,
            0.28 + (season.demand - 0.72) / (1.30 - 0.72) * 0.48))
        return {
            messageLength = messageLength,
            responseChance = chance,
            seasonName = season.name,
            seasonDemand = season.demand,
        }
    end

    function Runtime.promotionRoll(sourceJob, promoNumber)
        local hash = promoNumber * 7919 + 104729
        local source = tostring(sourceJob and sourceJob.id or "PROMO")
        for index = 1, #source do hash = (hash * 33 + string.byte(source, index)) % 2147483647 end
        return (hash % 10000) / 10000
    end

    function Runtime.applyAvailablePromotionCoupon(state, offer, email)
        if type(offer)~="table" or offer.promotionDiscount then return nil end
        local emails=Runtime.ensureEmails(state)
        local promotion
        for _,sent in ipairs(emails.sentPromotions) do
            if sent.recipient==offer.company and sent.responseOutcome=="thank_you"
                and sent.couponUsedAtHours==nil then
                promotion=sent
                break
            end
        end
        if not promotion then return nil end
        local prices=discountOffer(offer)
        if not prices then return nil end
        promotion.couponUsedAtHours=Runtime.BusinessCalendar.absoluteHours(state)
        if email then
            email.promotionId=promotion.id
            email.standardPrice=prices.standardPrice
            email.discountAmount=prices.discountAmount
            email.discountedTotal=prices.discountedTotal
            email.body=tostring(email.body or "")
                .." Your 10% returning-client coupon has been applied to this order."
        end
        return promotion,prices
    end

    function Runtime.applyCouponToNextPendingOrder(state, company)
        local emails=Runtime.ensureEmails(state)
        local candidate
        for _,collection in ipairs({emails.pending,emails.inbox}) do
            for _,email in ipairs(collection) do
                local offer=email.job
                if email.sender==company and type(offer)=="table"
                    and offer.status=="offered" and not offer.promotionDiscount
                    and (not candidate or (tonumber(email.readyAtHours) or 0)
                        < (tonumber(candidate.readyAtHours) or 0)) then
                    candidate=email
                end
            end
        end
        if candidate then
            return Runtime.applyAvailablePromotionCoupon(state,candidate.job,candidate)
        end
        return nil
    end

    function Runtime.JobService.sendPromotion(state, sourceJob, customMessage)
        if type(sourceJob) ~= "table" or sourceJob.status ~= "completed" then
            return false, "choose a completed client job first"
        end
        local emails = Runtime.ensureEmails(state)
        if sourceJob.promotionSent then
            return false, "the 10% offer was already sent for this completed job"
        end
        for _, sent in ipairs(emails.sentPromotions) do
            if sent.sourceJobId == sourceJob.id then
                sourceJob.promotionSent = true
                return false, "the 10% offer was already sent for this completed job"
            end
        end
        local promoNumber, emailNumber = emails.nextPromotionId, emails.nextEmailId
        customMessage = tostring(customMessage or "")
        local offer = Runtime.repeatOffer(state, sourceJob, emailNumber)
        if not offer then return false, "could not prepare the promotional follow-up" end
        local prices=discountOffer(offer)
        local standardPrice=prices.standardPrice
        emails.nextPromotionId = promoNumber + 1
        emails.nextEmailId = emailNumber + 1
        local promoId = string.format("PROMO-%04d", promoNumber)
        local terms = Runtime.JobService.promotionTerms(state, customMessage)
        local roll = Runtime.promotionRoll(sourceJob, promoNumber)
        local outcome = roll < terms.responseChance and "new_job" or "thank_you"
        local promotion = {
            id = promoId, recipient = sourceJob.company, discountPercent = 10,
            customMessage = customMessage, sentAtHours = Runtime.BusinessCalendar.absoluteHours(state),
            responseOutcome = outcome, sourceJobId = sourceJob.id,
            messageLength = terms.messageLength, seasonName = terms.seasonName,
        }
        emails.sentPromotions[#emails.sentPromotions + 1] = promotion
        sourceJob.promotionSent = true
        if outcome == "new_job" then
            local discountAmount = standardPrice - offer.quote.totalPrice
            emails.pending[#emails.pending + 1] = {
                id = string.format("EMAIL-%04d", emailNumber),
                sender = sourceJob.company,
                subject = "Reply to your 10% returning-client offer",
                body = string.format(
                    "Thanks for the 10%% offer. Please quote another %s job. The discounted total is below.",
                    sourceJob.press and "cut-and-print" or "paper-cutting"),
                sourceJobId = sourceJob.id,
                promotionId = promoId,
                readyAtHours = Runtime.BusinessCalendar.absoluteHours(state) + 12,
                standardPrice = standardPrice,
                discountAmount = discountAmount,
                discountedTotal = offer.quote.totalPrice,
                job = offer,
            }
        elseif outcome == "thank_you" then
            Runtime.Inbox.addNotice(state, {
                id = string.format("EMAIL-%04d", emailNumber),
                sender = sourceJob.company,
                subject = "Thank you for the 10% offer",
                body = "Thanks for the 10% coupon. We do not have a new job right now, but we will use it on our next order.",
                noticeKind = "client_thanks",
                sourceJobId = sourceJob.id,
            }, 12)
            Runtime.applyCouponToNextPendingOrder(state,sourceJob.company)
        end
        return true, promotion
    end
end

return Component
