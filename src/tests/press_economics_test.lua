local Test = {}

function Test.run(context, check)
    local economics = require("src.press_economics")
    local budget = economics.calculate({
        impressions = 1000,
        colors = 1,
        coverage = 0.4,
        artworkSize = { width = 5, height = 7 },
    })
    check("windmill_budget_separates_rated_from_quoting_throughput", budget
        and budget.ratedImpressionsPerHour == 5500
        and budget.quotingImpressionsPerHour == 3000
        and budget.runHours == 0.333)
    check("windmill_budget_uses_current_plate_minimum_and_supply_allowances", budget
        and budget.plateCost == 20.93 and budget.inkCost >= 3
        and budget.chemistryCost == 2 and budget.tympanCost == 1.08)
    check("windmill_budget_exposes_net_order_and_gross_stock", budget
        and budget.orderedCopies == 1000 and budget.suppliedSheets == 1050
        and budget.spoilageAllowance == 50)

    local cuttingOnly = context.jobs.calculateQuote({ 1000 })
    local combined = context.jobs.quote({
        company = "Windmill Quote Test",
        sourceSize = { width = 10, height = 15 },
        finishedSize = { width = 5, height = 7 },
        sheetCounts = { 1000 },
        press = { colors = 1, coverage = 0.4 },
    })
    check("press_budget_adds_to_cutting_quote_without_changing_cutting_only_jobs", cuttingOnly
        and cuttingOnly.totalPrice == 300 and cuttingOnly.pressBudget == nil
        and combined and combined.cuttingPrice == 300
        and combined.totalPrice == 300 + combined.pressBudget.recommendedCharge)

    local tooLarge = economics.calculate({
        impressions = 1000, colors = 1, artworkSize = { width = 12, height = 14 },
    })
    check("windmill_quote_rejects_artwork_larger_than_chase", tooLarge == nil)

    local structured = context.jobs.createOffer({
        id = "PRINT-DOMAIN-001",
        company = "Structured Print Client",
        sourceSize = { width = 10, height = 15 },
        finishedSize = { width = 5, height = 7 },
        sheetCounts = { 1050 },
        artworkKey = "ad-photos",
        artwork = { key = "ad-photos", displayName = "Client Photo Card",
            fileName = "client-photo-card.png", suppliedBy = "client", orientation = "portrait" },
        stockSpec = { suppliedBy = "client", grade = "cover", weight = 80,
            finish = "uncoated", color = "white", grain = "long",
            description = "80 lb white uncoated cover" },
        press = { colors = 1, coverage = 0.35, artworkSize = { width = 4.25, height = 6.25 },
            colorSequence = { "Black" }, requestedCopies = { 1000 } },
    })
    local structuredPallet = structured and structured.pallets[1]
    check("print_offer_keeps_client_artwork_and_structured_stock", structured
        and structured.artworkKey == "ad-photos" and structured.artwork.key == structured.artworkKey
        and structured.artwork.fileName == "client-photo-card.png"
        and structured.artwork.suppliedBy == "client" and structured.stockSpec.weight == 80
        and structured.stockSpec.finish == "uncoated")
    check("print_quote_separates_ordered_copies_from_supplied_sheets", structured
        and structured.quote.orderedCopies == 1000 and structured.quote.suppliedSheets == 1050
        and structured.quote.spoilageAllowance == 50
        and structured.press.orderedQuantity == 1000 and structured.press.suppliedSheets == 1050
        and structured.press.spoilageAllowance == 50
        and structured.quote.pressBudget.impressions == 1000
        and structured.quote.pressBudget.suppliedSheets == 1050)
    check("print_pallet_tracks_required_good_copies_and_available_stock", structuredPallet
        and structuredPallet.requestedCopies == 1000 and structuredPallet.spoilageAllowance == 50
        and structuredPallet.press.requiredGoodSheets == 1000
        and structuredPallet.press.availableSheets == 1050
        and type(structuredPallet.press.passHistory) == "table"
        and #structuredPallet.press.passHistory == 0)

    local legacy = context.jobs.createOffer({
        id = "PRINT-LEGACY-001", company = "Legacy Print Client",
        sourceSize = { width = 10, height = 15 }, finishedSize = { width = 5, height = 7 },
        sheetCounts = { 500 }, press = { colors = 1, coverage = 0.3 },
    })
    check("legacy_print_specs_default_requested_copies_and_metadata", legacy
        and legacy.press.requestedCopies[1] == 500 and legacy.pallets[1].requestedCopies == 500
        and legacy.artworkKey == "flower" and legacy.artwork.key == "flower"
        and legacy.stockSpec.suppliedBy == "client")

    local tooManyCopies = context.jobs.createOffer({
        company = "Invalid Copies", sourceSize = { width = 10, height = 15 },
        finishedSize = { width = 5, height = 7 }, sheetCounts = { 1000 },
        press = { colors = 1, requestedCopies = { 1001 } },
    })
    local mismatchedColors = context.jobs.createOffer({
        company = "Invalid Colors", sourceSize = { width = 10, height = 15 },
        finishedSize = { width = 5, height = 7 }, sheetCounts = { 1000 },
        press = { colors = 2, colorSequence = { "Black" }, requestedCopies = { 950 } },
    })
    local oversizedSheet = context.jobs.createOffer({
        company = "Invalid Press Sheet", sourceSize = { width = 14, height = 11 },
        finishedSize = { width = 14, height = 11 }, sheetCounts = { 1000 },
        press = { colors = 1, artworkSize = { width = 5, height = 7 }, requestedCopies = { 950 } },
    })
    local artworkOutsidePiece = context.jobs.createOffer({
        company = "Invalid Art Fit", sourceSize = { width = 10, height = 15 },
        finishedSize = { width = 5, height = 7 }, sheetCounts = { 1000 },
        press = { colors = 1, artworkSize = { width = 6, height = 8 }, requestedCopies = { 950 } },
    })
    check("print_contract_rejects_quantity_color_sheet_and_artwork_mismatches",
        tooManyCopies == nil and mismatchedColors == nil and oversizedSheet == nil
        and artworkOutsidePiece == nil)

    local cadenceState = context.State.new()
    cadenceState.reputation.score = 20
    cadenceState.money = 20000
    local pressBought = context.machineFleet.buy(cadenceState, "dealer", 3)
    local cadence, companies = {}, {}
    for index = 1, 5 do
        local offer = context.jobService.createNextOffer(cadenceState, 1000 + index)
        cadence[index], companies[index] = offer and offer.press ~= nil, offer and offer.company
        if offer then context.jobService.declineOffer(cadenceState, offer, 2000 + index) end
    end
    check("installed_press_guarantees_first_print_then_alternates_job_families", pressBought
        and cadence[1] and not cadence[2] and cadence[3] and not cadence[4] and cadence[5])
    check("print_offer_rotation_reaches_every_structured_template",
        companies[1] == "Foundry Coffee Roasters"
        and companies[3] == "Lantern House Events"
        and companies[5] == "Maple Street Books")

    structured.status = "completed"
    local repeatState = context.State.new()
    local repeatScheduled = context.jobService.scheduleRepeatEmail(repeatState, structured)
    local repeatJob = repeatState.clientEmails.pending[1]
        and repeatState.clientEmails.pending[1].job
    check("repeat_print_request_preserves_structured_stock_artwork_and_net_quantity", repeatScheduled
        and repeatJob and repeatJob.press and repeatJob.artwork.suppliedBy == "client"
        and repeatJob.stockSpec.description == structured.stockSpec.description
        and repeatJob.press.requestedCopies[1] == repeatJob.pallets[1].requestedCopies
        and repeatJob.quote.orderedCopies < repeatJob.quote.suppliedSheets
        and repeatState.clientEmails.pending[1].subject == "Request for another print job")
    local promoted = context.jobService.sendPromotion(repeatState, structured, string.rep("x", 240))
    local promotionReply = repeatState.clientEmails.pending[#repeatState.clientEmails.pending]
    check("print_promotion_reply_describes_cut_and_print_work", promoted and promotionReply
        and promotionReply.body:find("cut%-and%-print") ~= nil and promotionReply.job.press ~= nil
        and promotionReply.standardPrice > promotionReply.discountedTotal
        and promotionReply.discountAmount == promotionReply.standardPrice - promotionReply.discountedTotal
        and promotionReply.job.quote.totalPrice == promotionReply.discountedTotal)
    local duplicatePromotion = context.jobService.sendPromotion(repeatState, structured, "Duplicate.")
    check("promotion_cannot_be_sent_twice_for_one_completed_job",
        not duplicatePromotion and structured.promotionSent
        and #repeatState.clientEmails.sentPromotions == 1)
    legacy.status = "completed"
    local thanked, thankPromotion = context.jobService.sendPromotion(repeatState, legacy, string.rep("a", 41))
    local thankReply = repeatState.clientEmails.pending[#repeatState.clientEmails.pending]
    local pendingBeforeSilence = #repeatState.clientEmails.pending
    local silentSource = context.jobs.createOffer({
        id = "PROMO-SILENT-001", company = "Silent Coupon Client",
        sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 }, packaging = "flat",
    })
    silentSource.status = "completed"
    local silent, silentPromotion = context.jobService.sendPromotion(
        repeatState, silentSource, "Whenever you are ready.")
    check("promotions_allow_thank_you_only_and_no_response_outcomes",
        thanked and thankPromotion.responseOutcome == "thank_you"
        and thankReply.noticeKind == "client_thanks" and thankReply.job == nil
        and silent and silentPromotion.responseOutcome == "no_response"
        and #repeatState.clientEmails.pending == pendingBeforeSilence)
end

return Test
