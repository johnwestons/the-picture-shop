-- Pure job-domain rules for print-shop work orders.
-- This module has no dependency on the game state or rendering code.  Callers
-- own the returned records and may serialize them as part of a save file.
local Jobs = {}
local PaperWork = require("src.paper_work")
local PalletState = require("src.pallet_state")
local PressEconomics = require("src.press_economics")
local PlateService = require("src.plate_service")

Jobs.MIN_PALLETS = 1
Jobs.MAX_PALLETS = 5
Jobs.MIN_SHEETS = 500
Jobs.MAX_SHEETS = 3000
Jobs.MAX_SOURCE_WIDTH = 25
Jobs.MAX_SOURCE_HEIGHT = 25
Jobs.LIFT_CAPACITY = 500
Jobs.PRICE_PER_LIFT = 150

local function isInteger(value)
    return type(value) == "number" and value == math.floor(value)
end

local function dimension(value, name)
    if type(value) ~= "table" then
        return nil, name .. " must be a table with width and height"
    end
    local width = value.width or value.w
    local height = value.height or value.h
    if not (type(width) == "number" and type(height) == "number") then
        return nil, name .. " must include numeric width and height"
    end
    if width <= 0 or height <= 0 then
        return nil, name .. " dimensions must be greater than zero"
    end
    return { width = width, height = height }
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function nonBlank(value)
    return type(value) == "string" and not value:match("^%s*$")
end

local function displayNameFor(key)
    local name = tostring(key or "artwork"):gsub("[-_]", " ")
    return (name:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest
    end))
end

local function orientationFor(size)
    return type(size) == "table" and type(size.width) == "number" and type(size.height) == "number"
        and size.width > size.height and "landscape" or "portrait"
end

local function normalizeArtwork(spec, finished)
    local supplied = type(spec.artwork) == "table" and spec.artwork or {}
    local details = type(spec.details) == "table" and spec.details or {}
    local key = nonBlank(supplied.key) and supplied.key
        or (nonBlank(spec.artworkKey) and spec.artworkKey)
        or (nonBlank(details.artworkKey) and details.artworkKey)
        or "flower"
    local size = type(spec.press) == "table" and spec.press.artworkSize or finished
    return {
        key = key,
        displayName = nonBlank(supplied.displayName) and supplied.displayName or displayNameFor(key),
        fileName = nonBlank(supplied.fileName) and supplied.fileName or (key .. ".png"),
        suppliedBy = supplied.suppliedBy or "client",
        orientation = supplied.orientation or orientationFor(size),
    }
end

local function inferredStockValue(description, choices, fallback)
    local lowered = tostring(description or ""):lower()
    for _, choice in ipairs(choices) do
        if lowered:find(choice, 1, true) then return choice end
    end
    return fallback
end

local function normalizeStockSpec(spec)
    local supplied = type(spec.stockSpec) == "table" and spec.stockSpec or {}
    local details = type(spec.details) == "table" and spec.details or {}
    local description = nonBlank(supplied.description) and supplied.description
        or (nonBlank(details.stockDescription) and details.stockDescription)
        or "Customer-supplied paper"
    local weight = supplied.weight
    if weight == nil then weight = tonumber(description:lower():match("([%d%.]+)%s*lb")) or 0 end
    local grain = supplied.grain
    if not nonBlank(grain) then
        grain = inferredStockValue(details.grainDirection, { "long", "short" }, "unspecified")
    end
    return {
        suppliedBy = supplied.suppliedBy or "client",
        grade = nonBlank(supplied.grade) and supplied.grade
            or inferredStockValue(description, { "cover", "text", "offset" }, "unspecified"),
        weight = weight,
        finish = nonBlank(supplied.finish) and supplied.finish
            or inferredStockValue(description, { "gloss", "uncoated", "coated" }, "unspecified"),
        color = nonBlank(supplied.color) and supplied.color or "white",
        grain = grain,
        description = description,
    }
end

local function normalizedSheetCounts(spec)
    if type(spec.sheetCounts) == "table" then return spec.sheetCounts end
    if type(spec.pallets) == "table" then
        local counts = {}
        for index, pallet in ipairs(spec.pallets) do
            counts[index] = type(pallet) == "table" and pallet.sheetCount or pallet
        end
        return counts
    end
    return nil
end

local function validateSheetCounts(counts)
    local errors = {}
    if type(counts) ~= "table" then
        return false, { "sheetCounts must contain 1 to 5 pallet quantities" }
    end

    local entryCount, highestIndex = 0, 0
    for key in pairs(counts) do
        if not isInteger(key) or key < 1 then
            errors[#errors + 1] = "sheetCounts must be a sequential list"
        else
            entryCount = entryCount + 1
            highestIndex = math.max(highestIndex, key)
        end
    end
    if entryCount ~= highestIndex then
        errors[#errors + 1] = "sheetCounts must not contain empty pallet entries"
    end
    if entryCount < Jobs.MIN_PALLETS or entryCount > Jobs.MAX_PALLETS then
        errors[#errors + 1] = "a job must contain between 1 and 5 pallets"
    end
    for index = 1, highestIndex do
        local sheets = counts[index]
        if not isInteger(sheets) then
            errors[#errors + 1] = string.format("pallet %d sheet count must be a whole number", index)
        elseif sheets < Jobs.MIN_SHEETS or sheets > Jobs.MAX_SHEETS then
            errors[#errors + 1] = string.format("pallet %d must contain 500 to 3000 sheets", index)
        end
    end
    return #errors == 0, errors
end

local function normalizedRequestedCopies(press, counts)
    if type(press) == "table" and press.requestedCopies ~= nil then
        return copy(press.requestedCopies)
    end
    return copy(type(counts) == "table" and counts or {})
end

local function validateRequestedCopies(requested, counts)
    local errors = {}
    if type(requested) ~= "table" then
        return false, { "press requestedCopies must be a list aligned with sheetCounts" }
    end
    local requestedCount, highestIndex = 0, 0
    for key in pairs(requested) do
        if not isInteger(key) or key < 1 then
            errors[#errors + 1] = "press requestedCopies must be a sequential list"
        else
            requestedCount = requestedCount + 1
            highestIndex = math.max(highestIndex, key)
        end
    end
    if requestedCount ~= highestIndex then
        errors[#errors + 1] = "press requestedCopies must not contain empty entries"
    end
    local suppliedCount = type(counts) == "table" and #counts or 0
    if requestedCount ~= suppliedCount then
        errors[#errors + 1] = "press requestedCopies must align 1:1 with sheetCounts"
    end
    for index = 1, highestIndex do
        local requestedCopies = requested[index]
        local suppliedSheets = type(counts) == "table" and counts[index] or nil
        if not isInteger(requestedCopies) or requestedCopies < 1 then
            errors[#errors + 1] = string.format("pallet %d requested copies must be a positive whole number", index)
        elseif isInteger(suppliedSheets) and requestedCopies > suppliedSheets then
            errors[#errors + 1] = string.format("pallet %d requested copies cannot exceed supplied sheets", index)
        end
    end
    return #errors == 0, errors
end

local function normalizedPress(press, finished, requestedCopies, suppliedCounts)
    if type(press) ~= "table" then return nil end
    local result = copy(press)
    result.colors = result.colors or 1
    if result.coverage == nil then result.coverage = 0.4 end
    if result.colorSequence == nil then
        result.colorSequence = {}
        local colors = isInteger(result.colors) and math.max(1, result.colors) or 1
        for index = 1, colors do
            result.colorSequence[index] = index == 1 and "Black" or ("Spot " .. index)
        end
    end
    result.artworkSize = result.artworkSize or copy(finished)
    result.requestedCopies = copy(requestedCopies)
    local orderedQuantity, suppliedSheets = 0, 0
    for _, amount in ipairs(type(requestedCopies) == "table" and requestedCopies or {}) do
        if type(amount) == "number" then orderedQuantity = orderedQuantity + amount end
    end
    for _, amount in ipairs(type(suppliedCounts) == "table" and suppliedCounts or {}) do
        if type(amount) == "number" then suppliedSheets = suppliedSheets + amount end
    end
    result.orderedQuantity = orderedQuantity
    result.suppliedSheets = suppliedSheets
    result.spoilageAllowance = math.max(0, suppliedSheets - orderedQuantity)
    return result
end

local function stableId(spec, counts)
    if type(spec.id) == "string" and spec.id ~= "" then return spec.id end
    if isInteger(spec.sequence) and spec.sequence >= 1 then
        return string.format("JOB-%04d", spec.sequence)
    end
    local company = tostring(spec.company or "unknown"):gsub("%W", "-"):lower()
    local source = spec.sourceSize
    local finished = spec.finishedSize
    local sourceW = source and (source.width or source.w) or 0
    local sourceH = source and (source.height or source.h) or 0
    local finishedW = finished and (finished.width or finished.w) or 0
    local finishedH = finished and (finished.height or finished.h) or 0
    return string.format("JOB-%s-%gx%g-%gx%g-%s", company, sourceW, sourceH,
        finishedW, finishedH, table.concat(counts or {}, "-"))
end

function Jobs.formatId(sequence)
    if not isInteger(sequence) or sequence < 1 then
        return nil, "job sequence must be a positive whole number"
    end
    return string.format("JOB-%04d", sequence)
end

function Jobs.validateSpec(spec)
    local errors = {}
    if type(spec) ~= "table" then
        return false, { "job specification must be a table" }
    end
    if type(spec.company) ~= "string" or spec.company:match("^%s*$") then
        errors[#errors + 1] = "company is required"
    end

    local source, sourceError = dimension(spec.sourceSize, "sourceSize")
    if sourceError then errors[#errors + 1] = sourceError end
    if source and (source.width > Jobs.MAX_SOURCE_WIDTH or source.height > Jobs.MAX_SOURCE_HEIGHT) then
        errors[#errors + 1] = "sourceSize cannot exceed 25 x 25 inches"
    end
    local finished, finishedError = dimension(spec.finishedSize, "finishedSize")
    if finishedError then errors[#errors + 1] = finishedError end
    if source and finished and (finished.width > source.width or finished.height > source.height) then
        errors[#errors + 1] = "finishedSize must fit within sourceSize"
    end

    local counts = normalizedSheetCounts(spec)
    local countsValid, countErrors = validateSheetCounts(counts)
    if not countsValid then
        for _, countError in ipairs(countErrors) do errors[#errors + 1] = countError end
    end
    local requestedCopies = normalizedRequestedCopies(spec.press, counts)
    local requestedValid, requestedErrors = validateRequestedCopies(requestedCopies, counts)
    if not requestedValid then
        for _, requestedError in ipairs(requestedErrors) do errors[#errors + 1] = requestedError end
    end

    if spec.artwork ~= nil and type(spec.artwork) ~= "table" then
        errors[#errors + 1] = "artwork must be a table"
    end
    if spec.stockSpec ~= nil and type(spec.stockSpec) ~= "table" then
        errors[#errors + 1] = "stockSpec must be a table"
    end
    local artwork = normalizeArtwork(spec, finished)
    if type(spec.artwork) == "table" and nonBlank(spec.artwork.key) and nonBlank(spec.artworkKey)
        and spec.artwork.key ~= spec.artworkKey
    then
        errors[#errors + 1] = "artwork.key must match artworkKey"
    end
    if not nonBlank(artwork.key) or not nonBlank(artwork.displayName) or not nonBlank(artwork.fileName) then
        errors[#errors + 1] = "artwork requires a key, displayName, and fileName"
    end
    if artwork.suppliedBy ~= "client" then errors[#errors + 1] = "artwork must be supplied by the client" end
    if artwork.orientation ~= "portrait" and artwork.orientation ~= "landscape" then
        errors[#errors + 1] = "artwork orientation must be portrait or landscape"
    end

    local stockSpec = normalizeStockSpec(spec)
    if stockSpec.suppliedBy ~= "client" then errors[#errors + 1] = "stock must be supplied by the client" end
    for _, field in ipairs({ "grade", "finish", "color", "grain", "description" }) do
        if not nonBlank(stockSpec[field]) then errors[#errors + 1] = "stockSpec." .. field .. " is required" end
    end
    if type(stockSpec.weight) ~= "number" or stockSpec.weight ~= stockSpec.weight
        or stockSpec.weight < 0 or stockSpec.weight == math.huge
    then
        errors[#errors + 1] = "stockSpec.weight must be a nonnegative number"
    end

    if spec.press ~= nil and type(spec.press) ~= "table" then
        errors[#errors + 1] = "press must be a table"
    end
    local press = normalizedPress(spec.press, finished, requestedCopies, counts)
    if press then
        local validationPress = copy(press)
        validationPress.sheetSize = copy(finished)
        validationPress.finishedSize = copy(finished)
        local pressValid, pressErrors = PressEconomics.validate(validationPress)
        if not pressValid then
            for _, pressError in ipairs(pressErrors) do errors[#errors + 1] = pressError end
        end
    end
    return #errors == 0, errors, {
        source = source,
        finished = finished,
        counts = counts,
        requestedCopies = requestedCopies,
        artwork = artwork,
        stockSpec = stockSpec,
        press = press,
    }
end

function Jobs.calculateQuote(sheetCounts, requestedCopies)
    local valid, errors = validateSheetCounts(sheetCounts)
    if not valid then return nil, errors end
    requestedCopies = requestedCopies or copy(sheetCounts)
    local requestedValid, requestedErrors = validateRequestedCopies(requestedCopies, sheetCounts)
    if not requestedValid then return nil, requestedErrors end
    local pallets = {}
    local totalLifts, totalSheets, orderedCopies = 0, 0, 0
    for index, sheets in ipairs(sheetCounts) do
        local lifts = math.ceil(sheets / Jobs.LIFT_CAPACITY)
        local price = lifts * Jobs.PRICE_PER_LIFT
        local requested = requestedCopies[index]
        totalLifts, totalSheets = totalLifts + lifts, totalSheets + sheets
        orderedCopies = orderedCopies + requested
        pallets[index] = {
            number = index,
            sheetCount = sheets,
            requestedCopies = requested,
            spoilageAllowance = sheets - requested,
            requiredLifts = lifts,
            price = price,
        }
    end
    local totalPrice = totalLifts * Jobs.PRICE_PER_LIFT
    return {
        palletCount = #pallets,
        totalSheets = totalSheets,
        suppliedSheets = totalSheets,
        orderedCopies = orderedCopies,
        spoilageAllowance = totalSheets - orderedCopies,
        totalLifts = totalLifts,
        totalPrice = totalPrice,
        recommendedPrice = totalPrice,
        pallets = pallets
    }
end


function Jobs.quote(spec)
    local valid, errors, normalized = Jobs.validateSpec(spec)
    if not valid then return nil, errors end
    local quote, quoteErrors = Jobs.calculateQuote(normalized.counts, normalized.requestedCopies)
    if not quote then return nil, quoteErrors end
    if spec.press then
        local pressSpec = copy(normalized.press)
        pressSpec.impressions = quote.orderedCopies
        pressSpec.suppliedSheets = quote.suppliedSheets
        pressSpec.sheetSize = copy(normalized.finished)
        pressSpec.finishedSize = copy(normalized.finished)
        local pressBudget, pressErrors = PressEconomics.calculate(pressSpec)
        if not pressBudget then return nil, pressErrors end
        quote.cuttingPrice = quote.totalPrice
        quote.pressBudget = pressBudget
        quote.totalPrice = quote.cuttingPrice + pressBudget.recommendedCharge
        quote.recommendedPrice = quote.totalPrice
    end
    return quote
end

function Jobs.createOffer(spec)
    local valid, errors, normalized = Jobs.validateSpec(spec)
    if not valid then return nil, errors end
    local quoted, quoteErrors = Jobs.quote(spec)
    if not quoted then return nil, quoteErrors end
    local job = {
        id = stableId(spec, normalized.counts),
        company = spec.company,
        sourceSize = copy(normalized.source),
        finishedSize = copy(normalized.finished),
        artworkKey = normalized.artwork.key,
        artwork = copy(normalized.artwork),
        stockSpec = copy(normalized.stockSpec),
        deliveryService = copy(spec.deliveryService),
        requestChannel = spec.requestChannel == "email" and "email" or "reception",
        details = copy(spec.details or {}),
        difficulty = spec.difficulty or (spec.details and spec.details.difficulty) or "easy",
        packaging = spec.packaging == "boxed" and "boxed" or "flat",
        press = copy(normalized.press),
        status = "offered",
        createdAt = spec.createdAt,
        quote = quoted,
        pallets = {}
    }
    PlateService.ensureJob(job)
    for index, quotedPallet in ipairs(quoted.pallets) do
        job.pallets[index] = {
            id = string.format("%s-P%02d", job.id, index),
            number = index,
            initialSheets = quotedPallet.sheetCount,
            requestedCopies = quotedPallet.requestedCopies,
            spoilageAllowance = quotedPallet.spoilageAllowance,
            remainingSheets = quotedPallet.sheetCount,
            finishedSheets = 0,
            damagedSheets = 0,
            requiredLifts = quotedPallet.requiredLifts,
            completedLifts = 0,
            activeLift = 1,
            lastLiftSheets = 0,
            programVerified = false,
            awaitingPalletReturn = false,
            status = "raw",
            location = "awaiting_delivery",
            packaging = spec.packaging == "boxed" and "boxed" or "flat",
            wrapped = false,
            press = normalized.press and {
                status = "awaiting_cut", completedColors = 0, goodSheets = 0,
                spoilage = 0, dryUntilHours = nil,
                requiredGoodSheets = quotedPallet.requestedCopies,
                availableSheets = quotedPallet.sheetCount,
                passHistory = {},
            } or nil,
        }
        job.pallets[index].paper = PaperWork.create(job, job.pallets[index], job.difficulty, index)
    end
    return job
end

Jobs.validateOffer = Jobs.validateSpec

local function transition(job, nextStatus, expected)
    if type(job) ~= "table" then return false, "job must be a table" end
    if job.status ~= expected then
        return false, string.format("job must be %s (currently %s)", expected, tostring(job.status))
    end
    job.status = nextStatus
    return true, job
end

function Jobs.accept(job, timestamp)
    local succeeded, result = transition(job, "awaiting_delivery", "offered")
    if succeeded then job.acceptedAt = timestamp end
    return succeeded, result
end

function Jobs.decline(job, timestamp)
    local succeeded, result = transition(job, "declined", "offered")
    if succeeded then
        job.declinedAt = timestamp
        for _, pallet in ipairs(job.pallets or {}) do
            PalletState.transitionDetached(pallet, "none", { status = "cancelled" })
        end
    end
    return succeeded, result
end

function Jobs.status(job)
    return type(job) == "table" and job.status or nil
end

function Jobs.isActive(job)
    local status = Jobs.status(job)
    return status ~= nil and status ~= "declined" and status ~= "completed"
end

function Jobs.isComplete(job)
    return Jobs.status(job) == "completed"
end

return Jobs
