-- Real-world-informed costing rules for 10x15 Original Heidelberg platen work.
-- Supplier prices are snapshots, while labor, overhead, coverage and production
-- speed are explicit shop assumptions that can be tuned without changing jobs.
local PressEconomics = {}

PressEconomics.MODEL = "Original Heidelberg 10x15 platen"
PressEconomics.PRICE_DATE = "2026-08-24"
PressEconomics.RATED_IMPRESSIONS_PER_HOUR = 5500
PressEconomics.QUOTING_IMPRESSIONS_PER_HOUR = 3000
PressEconomics.MAX_SHEET = { width = 10.25, height = 15 }
PressEconomics.MAX_FORM = { width = 10.25, height = 13.375 }

PressEconomics.prices = {
    plateMinimum = 38.50,
    platePerSquareInch = 0.77,
    plateDimensionAllowance = 0.25,
    blackInkCan = 46.00,
    blackInkPounds = 2.2,
    tympanTenPack = 9.99,
}

PressEconomics.assumptions = {
    laborPerHour = 35,
    machineOverheadPerHour = 12,
    makereadyHoursPerColor = 0.75,
    washupHoursPerColor = 0.25,
    chemistryAllowancePerColor = 2,
    minimumInkAllowancePerColor = 3,
    inkSetupPoundsPerColor = 0.03,
    inkPoundsPerThousandAtFortyPercent = 0.05,
    spoilageRate = 0.03,
    minimumSpoilageSheets = 50,
    targetGrossMargin = 0.35,
    priceRounding = 5,
}

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function round(value, places)
    local scale = 10 ^ (places or 0)
    return math.floor(value * scale + 0.5) / scale
end

local function roundUp(value, increment)
    return math.ceil(value / increment) * increment
end

local function dimensionsFit(size, limit)
    return size.width <= limit.width and size.height <= limit.height
        or size.height <= limit.width and size.width <= limit.height
end

function PressEconomics.validate(spec)
    if type(spec) ~= "table" then return false, { "press must be a table" } end
    local errors = {}
    local colors = spec.colors or 1
    if not finite(colors) or colors ~= math.floor(colors) or colors < 1 or colors > 4 then
        errors[#errors + 1] = "press colors must be a whole number from 1 to 4"
    end
    local coverage = spec.coverage == nil and 0.4 or spec.coverage
    if not finite(coverage) or coverage < 0 or coverage > 1 then
        errors[#errors + 1] = "press coverage must be between 0 and 1"
    end
    if spec.artworkSize ~= nil then
        if type(spec.artworkSize) ~= "table" or not finite(spec.artworkSize.width)
            or not finite(spec.artworkSize.height) or spec.artworkSize.width <= 0
            or spec.artworkSize.height <= 0
        then
            errors[#errors + 1] = "press artworkSize must include positive width and height"
        elseif not dimensionsFit(spec.artworkSize, PressEconomics.MAX_FORM) then
            errors[#errors + 1] = "press artwork must fit the 10.25 x 13.375 inch chase"
        end
    end
    if spec.stockCostPerSheet ~= nil
        and (not finite(spec.stockCostPerSheet) or spec.stockCostPerSheet < 0)
    then
        errors[#errors + 1] = "press stockCostPerSheet cannot be negative"
    end
    return #errors == 0, errors
end

local function plateRate(area)
    if area <= 200 then return 0.77 end
    if area <= 600 then return 0.75 end
    if area <= 1000 then return 0.73 end
    if area <= 2000 then return 0.71 end
    return 0.69
end

function PressEconomics.calculate(spec)
    local valid, errors = PressEconomics.validate(spec)
    if not valid then return nil, errors end

    local impressions = math.max(1, math.floor(tonumber(spec.impressions) or 1))
    local colors = spec.colors or 1
    local coverage = spec.coverage == nil and 0.4 or spec.coverage
    local artwork = spec.artworkSize or { width = 5, height = 7 }
    local price, assumptions = PressEconomics.prices, PressEconomics.assumptions
    local billedWidth = artwork.width + price.plateDimensionAllowance
    local billedHeight = artwork.height + price.plateDimensionAllowance
    local plateArea = billedWidth * billedHeight * colors
    local plateCost = math.max(price.plateMinimum, plateArea * plateRate(plateArea))

    local inkPounds = assumptions.inkSetupPoundsPerColor * colors
        + impressions / 1000 * colors * assumptions.inkPoundsPerThousandAtFortyPercent
            * (coverage / 0.4)
    local inkUnitCost = price.blackInkCan / price.blackInkPounds
    local inkCost = math.max(assumptions.minimumInkAllowancePerColor * colors,
        inkPounds * inkUnitCost)
    local chemistryCost = assumptions.chemistryAllowancePerColor * colors
    local tympanCost = price.tympanTenPack / 10
    local spoilageSheets = math.max(assumptions.minimumSpoilageSheets,
        math.ceil(impressions * assumptions.spoilageRate))
    local stockCost = (impressions + spoilageSheets) * (spec.stockCostPerSheet or 0)

    local runHours = impressions * colors / PressEconomics.QUOTING_IMPRESSIONS_PER_HOUR
    local makereadyHours = assumptions.makereadyHoursPerColor * colors
    local washupHours = assumptions.washupHoursPerColor * colors
    local productionHours = runHours + makereadyHours + washupHours
    local laborCost = productionHours * assumptions.laborPerHour
    local machineCost = productionHours * assumptions.machineOverheadPerHour
    local suppliesCost = plateCost + inkCost + chemistryCost + tympanCost + stockCost
    local productionCost = suppliesCost + laborCost + machineCost
    local recommendedCharge = roundUp(
        productionCost / (1 - assumptions.targetGrossMargin), assumptions.priceRounding)

    return {
        model = PressEconomics.MODEL,
        impressions = impressions,
        colors = colors,
        totalPasses = impressions * colors,
        ratedImpressionsPerHour = PressEconomics.RATED_IMPRESSIONS_PER_HOUR,
        quotingImpressionsPerHour = PressEconomics.QUOTING_IMPRESSIONS_PER_HOUR,
        plateBilledSize = { width = round(billedWidth, 3), height = round(billedHeight, 3) },
        plateSquareInches = round(plateArea, 3),
        plateCost = round(plateCost, 2),
        inkPounds = round(inkPounds, 3),
        inkCost = round(inkCost, 2),
        chemistryCost = round(chemistryCost, 2),
        tympanCost = round(tympanCost, 2),
        spoilageSheets = spoilageSheets,
        stockCost = round(stockCost, 2),
        runHours = round(runHours, 3),
        makereadyHours = round(makereadyHours, 3),
        washupHours = round(washupHours, 3),
        productionHours = round(productionHours, 3),
        suppliesCost = round(suppliesCost, 2),
        laborCost = round(laborCost, 2),
        machineCost = round(machineCost, 2),
        productionCost = round(productionCost, 2),
        recommendedCharge = recommendedCharge,
        priceDate = PressEconomics.PRICE_DATE,
    }
end

return PressEconomics
