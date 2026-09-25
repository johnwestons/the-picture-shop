-- Real-world-informed costing rules for 10x15 Original Heidelberg platen work.
-- Supplier prices are snapshots, while labor, overhead, coverage and production
-- speed are explicit shop assumptions that can be tuned without changing jobs.
local PressEconomics = {}

PressEconomics.MODEL = "Original Heidelberg 10x15 platen"
PressEconomics.PRICE_DATE = "2026-09-25"
PressEconomics.RATED_IMPRESSIONS_PER_HOUR = 5500
PressEconomics.QUOTING_IMPRESSIONS_PER_HOUR = 3000
PressEconomics.MAX_SHEET = { width = 10.25, height = 15 }
PressEconomics.MAX_FORM = { width = 10.25, height = 13.375 }

PressEconomics.prices = {
    plateMinimum = 12.50,
    platePerSquareInch = 0.55,
    plateDimensionAllowance = 0.25,
    blackInkCan = 46.00,
    blackInkPounds = 2.2,
    tympanTenPack = 10.77,
}

PressEconomics.assumptions = {
    laborPerHour = 22.77,
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

local function validDimensions(size)
    return type(size) == "table" and finite(size.width) and finite(size.height)
        and size.width > 0 and size.height > 0
end

local function nonBlank(value)
    return type(value) == "string" and not value:match("^%s*$")
end

local function validateColorSequence(sequence, colors, errors)
    if sequence == nil then return end
    if type(sequence) ~= "table" then
        errors[#errors + 1] = "press colorSequence must be a sequential list"
        return
    end
    local count, highest = 0, 0
    for key in pairs(sequence) do
        if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
            errors[#errors + 1] = "press colorSequence must be a sequential list"
            return
        end
        count, highest = count + 1, math.max(highest, key)
    end
    if count ~= highest or count ~= colors then
        errors[#errors + 1] = "press colorSequence must contain exactly one named ink per color"
        return
    end
    for index = 1, colors do
        if not nonBlank(sequence[index]) then
            errors[#errors + 1] = string.format("press color %d must have a name", index)
        end
    end
end

function PressEconomics.validate(spec)
    if type(spec) ~= "table" then return false, { "press must be a table" } end
    local errors = {}
    local colors = spec.colors or 1
    if not finite(colors) or colors ~= math.floor(colors) or colors < 1 or colors > 4 then
        errors[#errors + 1] = "press colors must be a whole number from 1 to 4"
    end
    validateColorSequence(spec.colorSequence,
        finite(colors) and colors == math.floor(colors) and colors >= 1 and colors <= 4 and colors or 1,
        errors)
    local coverage = spec.coverage == nil and 0.4 or spec.coverage
    if not finite(coverage) or coverage < 0 or coverage > 1 then
        errors[#errors + 1] = "press coverage must be between 0 and 1"
    end
    local finished = spec.finishedSize
    if finished ~= nil and not validDimensions(finished) then
        errors[#errors + 1] = "press finishedSize must include positive width and height"
    end
    local sheet = spec.sheetSize or finished
    if sheet ~= nil then
        if not validDimensions(sheet) then
            errors[#errors + 1] = "press sheetSize must include positive width and height"
        elseif not dimensionsFit(sheet, PressEconomics.MAX_SHEET) then
            errors[#errors + 1] = "press finished sheet must fit the 10.25 x 15 inch feed limit"
        end
    end
    if spec.artworkSize ~= nil then
        if not validDimensions(spec.artworkSize) then
            errors[#errors + 1] = "press artworkSize must include positive width and height"
        elseif not dimensionsFit(spec.artworkSize, PressEconomics.MAX_FORM) then
            errors[#errors + 1] = "press artwork must fit the 10.25 x 13.375 inch chase"
        elseif validDimensions(finished) and not dimensionsFit(spec.artworkSize, finished) then
            errors[#errors + 1] = "press artwork must fit within the finished piece"
        end
    end
    if spec.impressions ~= nil
        and (not finite(spec.impressions) or spec.impressions ~= math.floor(spec.impressions)
            or spec.impressions < 1)
    then
        errors[#errors + 1] = "press impressions must be a positive whole number"
    end
    if spec.suppliedSheets ~= nil
        and (not finite(spec.suppliedSheets) or spec.suppliedSheets ~= math.floor(spec.suppliedSheets)
            or spec.suppliedSheets < 1)
    then
        errors[#errors + 1] = "press suppliedSheets must be a positive whole number"
    elseif finite(spec.suppliedSheets) and finite(spec.impressions)
        and spec.suppliedSheets < spec.impressions
    then
        errors[#errors + 1] = "press suppliedSheets cannot be fewer than requested impressions"
    end
    if spec.stockCostPerSheet ~= nil
        and (not finite(spec.stockCostPerSheet) or spec.stockCostPerSheet < 0)
    then
        errors[#errors + 1] = "press stockCostPerSheet cannot be negative"
    end
    return #errors == 0, errors
end

local function plateRate(area)
    return PressEconomics.prices.platePerSquareInch
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
    local suppliedSheets = math.floor(tonumber(spec.suppliedSheets) or (impressions + spoilageSheets))
    local spoilageAllowance = math.max(0, suppliedSheets - impressions)
    local stockCost = suppliedSheets * (spec.stockCostPerSheet or 0)

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
        orderedCopies = impressions,
        suppliedSheets = suppliedSheets,
        spoilageAllowance = spoilageAllowance,
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
