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
        and budget.plateCost == 38.50 and budget.inkCost >= 3
        and budget.chemistryCost == 2 and budget.tympanCost == 1)

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
end

return Test
