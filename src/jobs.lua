-- Pure job-domain rules for print-shop work orders.
-- This module has no dependency on the game state or rendering code.  Callers
-- own the returned records and may serialize them as part of a save file.
local Jobs = {}
local PaperWork = require("src.paper_work")

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
    return #errors == 0, errors, { source = source, finished = finished, counts = counts }
end

function Jobs.calculateQuote(sheetCounts)
    local valid, errors = validateSheetCounts(sheetCounts)
    if not valid then return nil, errors end
    local pallets = {}
    local totalLifts, totalSheets = 0, 0
    for index, sheets in ipairs(sheetCounts) do
        local lifts = math.ceil(sheets / Jobs.LIFT_CAPACITY)
        local price = lifts * Jobs.PRICE_PER_LIFT
        totalLifts, totalSheets = totalLifts + lifts, totalSheets + sheets
        pallets[index] = {
            number = index,
            sheetCount = sheets,
            requiredLifts = lifts,
            price = price,
        }
    end
    return {
        palletCount = #pallets,
        totalSheets = totalSheets,
        totalLifts = totalLifts,
        totalPrice = totalLifts * Jobs.PRICE_PER_LIFT,
        pallets = pallets
    }
end


function Jobs.quote(spec)
    local valid, errors, normalized = Jobs.validateSpec(spec)
    if not valid then return nil, errors end
    return Jobs.calculateQuote(normalized.counts)
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
        details = copy(spec.details or {}),
        difficulty = spec.difficulty or (spec.details and spec.details.difficulty) or "easy",
        packaging = spec.packaging == "boxed" and "boxed" or "flat",
        status = "offered",
        createdAt = spec.createdAt,
        quote = quoted,
        pallets = {}
    }
    for index, quotedPallet in ipairs(quoted.pallets) do
        job.pallets[index] = {
            id = string.format("%s-P%02d", job.id, index),
            number = index,
            initialSheets = quotedPallet.sheetCount,
            remainingSheets = quotedPallet.sheetCount,
            finishedSheets = 0,
            damagedSheets = 0,
            requiredLifts = quotedPallet.requiredLifts,
            completedLifts = 0,
            status = "raw",
            location = "awaiting_delivery",
            packaging = spec.packaging == "boxed" and "boxed" or "flat",
            wrapped = false,
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
            pallet.status = "cancelled"
            pallet.location = "none"
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
