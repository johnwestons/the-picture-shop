-- Promotion terms and client follow-up offers.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.JobService.promotionTerms(state, customMessage)
        local messageLength = #tostring(customMessage or ""):sub(1, 240)
        local reputation = Runtime.Reputation.ensure(state)
        local chance = 0.10 + messageLength / 240 * 0.65 + reputation.score / 100 * 0.15
        return {
            messageLength = messageLength,
            responseChance = math.max(0.10, math.min(0.90, chance)),
        }
    end

    function Runtime.promotionRoll(sourceJob, promoNumber, customMessage)
        local hash = promoNumber * 7919 + #customMessage * 104729
        local source = tostring(sourceJob and sourceJob.id or "PROMO") .. customMessage
        for index = 1, #source do hash = (hash * 33 + string.byte(source, index)) % 2147483647 end
        return (hash % 10000) / 10000
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
        customMessage = tostring(customMessage or ""):sub(1, 240)
        local offer = Runtime.repeatOffer(state, sourceJob, emailNumber)
        if not offer then return false, "could not prepare the promotional follow-up" end
        local standardPrice = offer.quote.totalPrice
        offer.quote.standardPrice = standardPrice
        offer.quote.totalPrice = math.max(1, math.floor(standardPrice * 0.90 + 0.5))
        offer.quote.recommendedPrice = offer.quote.totalPrice
        if offer.quote.servicePrice then offer.quote.servicePrice=math.max(1,math.floor(offer.quote.servicePrice*.90+.5)) end
        offer.promotionDiscount = 0.10
        emails.nextPromotionId = promoNumber + 1
        emails.nextEmailId = emailNumber + 1
        local promoId = string.format("PROMO-%04d", promoNumber)
        local terms = Runtime.JobService.promotionTerms(state, customMessage)
        local roll = Runtime.promotionRoll(sourceJob, promoNumber, customMessage)
        local outcome = roll <= terms.responseChance and "new_job"
            or roll <= math.min(1, terms.responseChance + 0.18) and "thank_you" or "no_response"
        local promotion = {
            id = promoId, recipient = sourceJob.company, discountPercent = 10,
            customMessage = customMessage, sentAtHours = Runtime.BusinessCalendar.absoluteHours(state),
            responseOutcome = outcome, sourceJobId = sourceJob.id,
            messageLength = terms.messageLength, responseChance = terms.responseChance,
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
                    "Thank you for the 10%% offer. Please estimate this new %s job. The coupon and discounted total are shown below.",
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
        end
        return true, promotion
    end
end

return Component
