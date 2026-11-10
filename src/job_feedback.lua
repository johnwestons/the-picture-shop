-- Saved production milestones, quality inspection, rework, and customer follow-up.
local Calendar = require("src.business_calendar")
local PaperWork = require("src.paper_work")
local PalletState = require("src.pallet_state")

local Feedback = {}

local MAX_EVENTS = 32

local function nonnegative(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function measuredGoodSheets(pallet)
    local finished = nonnegative(pallet and pallet.finishedSheets)
    if finished > 0 then return finished end
    if pallet and pallet.press then return nonnegative(pallet.press.goodSheets) end
    if pallet and pallet.status == "wrapped" and pallet.wrapped
        and nonnegative(pallet.remainingSheets) == 0 then
        return math.max(0, nonnegative(pallet.initialSheets) - nonnegative(pallet.damagedSheets))
    end
    return 0
end

function Feedback.ensure(job)
    if type(job) ~= "table" then return nil end
    job.feedback = type(job.feedback) == "table" and job.feedback or {}
    local record = job.feedback
    record.events = type(record.events) == "table" and record.events or {}
    record.caughtDefects = nonnegative(record.caughtDefects)
    record.reworkSheets = nonnegative(record.reworkSheets)
    record.reworkCost = nonnegative(record.reworkCost)
    record.scrapSheets = nonnegative(record.scrapSheets)
    record.deliveredSheets = nonnegative(record.deliveredSheets)
    return record
end

function Feedback.goodQuantity(job)
    local total = 0
    for _, pallet in ipairs(job and job.pallets or {}) do
        if pallet.status ~= "spoiled_discarded" then total = total + measuredGoodSheets(pallet) end
    end
    return total
end

function Feedback.record(job, stage, atHours, detail)
    local record = Feedback.ensure(job)
    if not record or type(stage) ~= "string" then return nil end
    detail = type(detail) == "string" and detail:sub(1, 220) or ""
    local stageDetail = detail ~= "" and detail or nil
    if stage ~= "employee_alert" and record.stage == stage and record.stageDetail == stageDetail then return end
    local previous = record.events[#record.events]
    if stage == "employee_alert" and previous
        and previous.stage == stage and previous.detail == detail then return previous end
    local event = {
        stage = stage,
        atHours = math.max(0, tonumber(atHours) or 0),
        detail = detail,
    }
    record.events[#record.events + 1] = event
    while #record.events > MAX_EVENTS do table.remove(record.events, 1) end
    if stage ~= "employee_alert" then
        record.stage = stage
        record.stageDetail = stageDetail
        record.stageAtHours = event.atHours
    end
    if detail ~= "" then record.lastDetail = detail end
    return event
end

local function employeeAlert(state, job)
    for _, worker in ipairs(state.employment and state.employment.staff or {}) do
        local assignment = worker.assignment
        if assignment and assignment.jobId == job.id then
            local activity = tostring(worker.activity or "")
            local lower = string.lower(activity)
            if lower:find("blocked", 1, true) or lower:find("needs player", 1, true)
                or lower:find("needs owner", 1, true) or lower:find("waiting for", 1, true)
                or lower:find("needs attention", 1, true) or lower:find("not staged", 1, true)
                or lower:find("clear the", 1, true)
            then
                return worker.name .. ": " .. activity
            end
        end
    end
end

function Feedback.progress(state, job)
    if type(job) ~= "table" or type(job.status) ~= "string" then return nil end
    state = type(state) == "table" and state or {}
    local stage, blocker, nextAction
    local inspection = job.inspection or {}
    if job.status == "completed" then
        stage, nextAction = "CLOSED", "Review the completed job record"
    elseif job.status == "pickup_in_progress" then
        stage, nextAction = "SHIPPING", "Load every wrapped pallet on the pickup truck"
    elseif job.status == "ready_for_pickup" then
        stage, nextAction = "READY TO SHIP", "Finish loading the customer pickup"
    elseif inspection.status == "held" then
        stage, nextAction = "QUALITY HOLD", "Send the affected pallet through rework"
    elseif inspection.status == "passed" then
        stage, nextAction = "QUALITY PASSED", "Schedule customer pickup"
    elseif job.status == "awaiting_delivery" or (job.delivery and job.delivery.status ~= "received") then
        stage = "WAITING FOR STOCK"
        blocker = job.delivery and "Customer stock has not arrived yet" or "Waiting for the customer stock"
        nextAction = "Receive and unload every job skid"
    else
        stage = "WRAPPING"
        nextAction = "Stretch-wrap each finished pallet"
        local allPalletsWrapped = #(job.pallets or {}) > 0
        local hasActivePallet = false
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.status ~= "spoiled_discarded" then
                hasActivePallet = true
                if job.press and (type(pallet.press) ~= "table" or pallet.press.status ~= "complete") then
                    allPalletsWrapped = false
                    if pallet.paper and pallet.paper.status ~= "complete" then
                        stage, nextAction = "CUTTING", "Complete the remaining cuts"
                    else
                        stage, nextAction = "PRINTING", "Finish the Windmill press run"
                    end
                    break
                elseif pallet.paper and pallet.paper.status ~= "complete" then
                    allPalletsWrapped = false
                    stage, nextAction = "CUTTING", "Complete the remaining cuts"
                    break
                elseif (pallet.remainingSheets or 0) > 0 or pallet.status ~= "wrapped" or not pallet.wrapped then
                    allPalletsWrapped = false
                    stage, nextAction = "WRAPPING", "Move the finished pallet to the skid wrapper"
                    break
                end
            end
        end
        if hasActivePallet and allPalletsWrapped then
            stage, nextAction = "READY FOR INSPECTION", "Inspect the finished job on the computer"
        end
    end

    local alert = employeeAlert(state, job)
    if alert then blocker = alert end
    local quantityTarget = job.press
        and nonnegative(job.quote and (job.quote.orderedCopies or job.press.orderedQuantity))
        or nonnegative(job.quote and job.quote.totalSheets)
    local goodSheets, scrapSheets = 0, 0
    for _, pallet in ipairs(job.pallets or {}) do
        if pallet.status ~= "spoiled_discarded" then
            goodSheets = goodSheets + measuredGoodSheets(pallet)
        end
        scrapSheets = scrapSheets + nonnegative(pallet.damagedSheets)
    end
    return {
        stage = stage,
        blocker = blocker,
        nextAction = nextAction,
        goodSheets = goodSheets,
        targetSheets = quantityTarget,
        scrapSheets = scrapSheets,
        alert = alert,
    }
end

function Feedback.sync(state)
    local changed = false
    for _, job in ipairs(state.jobs and state.jobs.active or {}) do
        local progress = Feedback.progress(state, job)
        local record = Feedback.ensure(job)
        if progress then
            if Feedback.record(job, progress.stage, Calendar.absoluteHours(state), progress.blocker or "") then
                changed = true
            end
            if progress.alert and record.lastAlert ~= progress.alert then
                record.lastAlert = progress.alert
                if Feedback.record(job, "employee_alert", Calendar.absoluteHours(state), progress.alert) then
                    changed = true
                end
            elseif not progress.alert then
                record.lastAlert = nil
            end
            if record.blocker ~= progress.blocker then record.blocker, changed = progress.blocker, true end
            if record.deliveredSheets ~= progress.goodSheets then record.deliveredSheets, changed = progress.goodSheets, true end
            if record.scrapSheets ~= progress.scrapSheets then record.scrapSheets, changed = progress.scrapSheets, true end
        end
    end
    return changed
end

local function collectFindings(job)
    local findings, affected = {}, {}
    local groups = {}
    for _, pallet in ipairs(job.pallets or {}) do
        if pallet.status ~= "spoiled_discarded" then
            local root = pallet.replacementFor or pallet.id
            local group = groups[root] or { target = 0, good = 0, pallets = {} }
            groups[root] = group
            group.target = group.target + nonnegative(pallet.requestedCopies or pallet.initialSheets)
            group.good = group.good + measuredGoodSheets(pallet)
            group.pallets[#group.pallets + 1] = pallet
            if pallet.paper and pallet.paper.offSpec and measuredGoodSheets(pallet) > 0 then
                findings[#findings + 1] = string.format("Pallet %d has an off-size cut.", pallet.number)
                affected[pallet.id] = true
            elseif pallet.paper and (tonumber(pallet.paper.cutQuality) or 1) < 0.80
                and measuredGoodSheets(pallet) > 0 then
                findings[#findings + 1] = string.format("Pallet %d has weak cut-edge quality.", pallet.number)
                affected[pallet.id] = true
            end
            for _, pass in ipairs(pallet.press and pallet.press.passHistory or {}) do
                local proofQuality = tonumber(pass.proofQuality)
                if (proofQuality and proofQuality < 0.82) or pass.artworkVerified == false then
                    findings[#findings + 1] = string.format("Pallet %d has a low-quality or unverified print pass.",
                        pallet.number)
                    affected[pallet.id] = true
                    break
                end
            end
        end
    end
    for _, group in pairs(groups) do
        if group.good < group.target and #group.pallets > 0 then
            local missing = group.target - group.good
            findings[#findings + 1] = string.format("%s good sheets are missing from the finished quantity.",
                tostring(missing))
            for _, pallet in ipairs(group.pallets) do affected[pallet.id] = true end
        end
    end
    local ids = {}
    for id in pairs(affected) do ids[#ids + 1] = id end
    table.sort(ids)
    table.sort(findings)
    return findings, ids
end

function Feedback.inspect(state, job)
    if type(job) ~= "table" or job.status ~= "in_production" then
        return false, "This job is not ready for final inspection."
    end
    for _, pallet in ipairs(job.pallets or {}) do
        if pallet.status ~= "spoiled_discarded"
            and (not pallet.wrapped or pallet.status ~= "wrapped"
                or (job.press and (not pallet.press or pallet.press.status ~= "complete"))) then
            return false, "Every pallet must be finished and wrapped before inspection."
        end
    end
    local findings, palletIds = collectFindings(job)
    local status = #findings == 0 and "passed" or "held"
    job.inspection = {
        status = status,
        inspectedAtHours = Calendar.absoluteHours(state),
        findings = findings,
        palletIds = palletIds,
        firstPass = (Feedback.ensure(job).reworkSheets or 0) == 0,
    }
    Feedback.ensure(job).caughtDefects = (Feedback.ensure(job).caughtDefects or 0) + #findings
    Feedback.record(job, status == "passed" and "quality_passed" or "quality_hold",
        job.inspection.inspectedAtHours, #findings == 0 and "Sample passed" or table.concat(findings, " "))
    if status == "held" then
        Feedback.ensure(job).blocker = "Quality inspection found a defect; rework the affected pallet before pickup."
        return true, job.inspection
    end
    Feedback.ensure(job).blocker = nil
    return true, job.inspection
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function nextReplacementId(job)
    local index = 1
    local seen = {}
    for _, pallet in ipairs(job.pallets or {}) do seen[pallet.id] = true end
    while seen[string.format("%s-QC%02d", job.id, index)] do index = index + 1 end
    return string.format("%s-QC%02d", job.id, index), index
end

function Feedback.requestRework(state, job)
    if type(job) ~= "table" or job.status ~= "in_production"
        or type(job.inspection) ~= "table" or job.inspection.status ~= "held"
    then return false, "Inspect the completed job and identify affected pallets first." end
    if type(job.inspection.palletIds) ~= "table" or #job.inspection.palletIds == 0 then
        return false, "The inspection did not identify a pallet that can be reworked."
    end
    local originals = {}
    for _, pallet in ipairs(job.pallets or {}) do originals[pallet.id] = pallet end
    local candidates = {}
    for _, palletId in ipairs(job.inspection.palletIds) do
        local source = originals[palletId]
        if source and source.location == "warehouse" and source.status == "wrapped" and source.wrapped then
            candidates[#candidates + 1] = source
        end
    end
    if #candidates == 0 then
        return false, "Move the affected wrapped pallet to clear warehouse floor space before rework."
    end
    local now = Calendar.absoluteHours(state)
    local added, sheets, totalCost = {}, 0, 0
    for _, source in ipairs(candidates) do
        local requested = nonnegative(source.requestedCopies or source.initialSheets)
        if requested > 0 then
            local id, sequence = nextReplacementId(job)
            local stockSheets = nonnegative(source.initialSheets)
            local cost = math.max(100, math.floor(stockSheets * 0.08 * 100 + 0.5))
            totalCost = totalCost + cost
            local replacement = {
                id = id,
                number = #job.pallets + 1,
                replacementFor = source.replacementFor or source.id,
                replacementSequence = sequence,
                initialSheets = stockSheets,
                requestedCopies = requested,
                spoilageAllowance = math.max(0, stockSheets - requested),
                remainingSheets = stockSheets,
                finishedSheets = 0,
                damagedSheets = 0,
                requiredLifts = math.max(1, math.ceil(stockSheets / 500)),
                completedLifts = 0,
                activeLift = 1,
                lastLiftSheets = 0,
                programVerified = false,
                awaitingPalletReturn = false,
                status = "replacement_in_transit",
                location = "awaiting_delivery",
                packaging = source.packaging or job.packaging or "flat",
                wrapped = false,
            }
            if job.press then
                replacement.press = {
                    status = "awaiting_cut",
                    completedColors = 0,
                    goodSheets = 0,
                    spoilage = 0,
                    dryUntilHours = nil,
                    requiredGoodSheets = requested,
                    availableSheets = stockSheets,
                    passHistory = {},
                }
            end
            replacement.paper = PaperWork.create(job, replacement, job.difficulty or "easy", sequence)
            local moved, moveError = PalletState.transition(state, source, "none", { status = "spoiled_discarded" })
            if not moved then return false, moveError end
            if state.inventory then
                state.inventory.finishedPallets = math.max(0, (state.inventory.finishedPallets or 0) - 1)
            end
            source.requestedCopies = nil
            source.spoilageAllowance = 0
            source.remainingSheets = 0
            source.finishedSheets = 0
            source.damagedSheets = source.initialSheets
            source.press = nil
            source.wrapped = false
            source.discardAfterSpoil = nil
            job.pallets[#job.pallets + 1] = replacement
            added[#added + 1] = replacement
            sheets = sheets + stockSheets
        end
    end
    if #added == 0 then return false, "No affected pallet could be reworked." end
    -- Rework is paid by the shop as a small operating cost; replacement stock
    -- and machine time then flow through the normal receiving and production loop.
    local billedCost = math.ceil(totalCost / 100)
    Calendar.addCharge(state, "Shop rework materials for " .. tostring(job.id),
        billedCost, job.id, "shop_rework")
    local record = Feedback.ensure(job)
    record.reworkSheets = record.reworkSheets + sheets
    record.reworkCost = record.reworkCost + totalCost
    record.scrapSheets = record.scrapSheets + sheets
    job.replacementSkids = nonnegative(job.replacementSkids) + #added
    job.replacementSheets = nonnegative(job.replacementSheets) + sheets
    local service = job.deliveryService or (job.delivery and job.delivery.service) or {
        id = "standard", label = "STANDARD", description = "Arrives within a day", delayHours = 24,
    }
    local delay = math.max(1, math.min(8, tonumber(service.delayHours) or 4))
    job.delivery = {
        status = "replacement_pending",
        kind = "replacement",
        service = copy(service),
        acceptedGameHours = now,
        readyAtHours = require('src.business_hours').nextService(now + delay),
        palletIds = {},
    }
    for _, pallet in ipairs(added) do job.delivery.palletIds[#job.delivery.palletIds + 1] = pallet.id end
    job.inspection.status = "rework_in_progress"
    job.inspection.palletIds = {}
    job.inspection.findings = {}
    Feedback.record(job, "rework_started", now,
        string.format("%d replacement sheets; stock and shop time cost $%d", sheets, billedCost))
    return true, { pallets = added, sheets = sheets, cost = billedCost, delayHours = delay }
end

function Feedback.lateByHours(job)
    if type(job)~="table" then return 0 end
    return require("src.business_deadlines").lateByHours(job)
end

return Feedback
