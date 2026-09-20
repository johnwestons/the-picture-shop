-- Durable warehouse construction rules. Only the authoritative shop caller
-- invokes mutations; this module performs no I/O, rendering, or phone side effects.
local Calendar = require("src.business_calendar")
local Upgrades = { LAYOUT_VERSION = 2, STAGE_HOURS = 24, ARRIVAL_LEAD_HOURS = 2 }

local BAY_IDS = { "front_left", "front_right" }
local BAYS = { front_left = true, front_right = true }
local CATALOG = {
    floor = { id = "floor", name = "Open warehouse floor", price = 2500 },
    storage = { id = "storage", name = "Pallet shelving", price = 4500,
        rows = 2, columns = 5, capacity = 10, upperRowRequiresForklift = true,
        warning = "10 pallet spaces. Lower 5: pallet jack or forklift. Upper 5: forklift required." },
    breakroom = { id = "breakroom", name = "Employee breakroom", price = 3500 },
    forklift = { id = "forklift", name = "Warehouse forklift", price = 6500 },
}
local STAGES = {
    { number = 1, name = "Foundation", tool = "concrete_float" },
    { number = 2, name = "Framing", tool = "framing_hammer" },
    { number = 3, name = "Assembly", tool = "assembly_drill" },
    { number = 4, name = "Finishing", tool = "finishing_roller" },
}
local PHASES = { queued = true, awaiting_notice = true, awaiting_arrival = true,
    building = true, complete = true }
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function nonnegative(value) return finite(value) and value >= 0 end
local function sameTime(left, right) return finite(left) and finite(right) and math.abs(left - right) < 0.000001 end
local function atLeastTime(left, right) return finite(left) and finite(right) and (left >= right or sameTime(left, right)) end
local function integer(value) return nonnegative(value) and value == math.floor(value) end
local function token(value)
    return type(value) == "string" and #value >= 1 and #value <= 64
        and value:match("^[%w_.%-]+$") ~= nil
end
local function optionalHours(value) return value == nil or nonnegative(value) end
local function exact(value, fields)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do if not fields[key] then return false end end
    return true
end
local function array(value, maximum)
    if type(value) ~= "table" or #value > maximum then return false end
    local count = 0
    for key in pairs(value) do
        if not integer(key) or key < 1 or key > #value then return false end
        count = count + 1
    end
    return count == #value
end
local function findProject(warehouse, id)
    for _, project in ipairs(warehouse.projects) do
        if project.id == id then return project end
    end
end
local function clock(state, supplied)
    if supplied ~= nil then return nonnegative(supplied) and supplied or nil end
    return Calendar.absoluteHours(state)
end

function Upgrades.defaultState()
    return { layoutVersion = Upgrades.LAYOUT_VERSION, nextProjectId = 1,
        bays = { front_left = { status = "locked" }, front_right = { status = "locked" } },
        projects = {}, receipts = {}, forkliftOwned = false }
end

function Upgrades.catalog(optionId)
    if optionId then return copy(CATALOG[optionId]) end
    return { copy(CATALOG.floor), copy(CATALOG.storage), copy(CATALOG.breakroom), copy(CATALOG.forklift) }
end

function Upgrades.stageInfo(stage) return copy(STAGES[stage]) end

function Upgrades.validate(value)
    if not exact(value, { layoutVersion=true, nextProjectId=true, bays=true, projects=true,
        receipts=true, forkliftOwned=true, activeProjectId=true })
        or value.layoutVersion ~= Upgrades.LAYOUT_VERSION
        or not integer(value.nextProjectId) or value.nextProjectId < 1 or value.nextProjectId > 3
        or type(value.forkliftOwned) ~= "boolean"
        or not exact(value.bays, BAYS) or not array(value.projects, 2) or not array(value.receipts, 3)
        or value.nextProjectId ~= #value.projects + 1
        or (value.activeProjectId ~= nil and not token(value.activeProjectId)) then
        return false, "Invalid warehouse state."
    end
    local ids, projectBays, activeCount = {}, {}, 0
    for index, project in ipairs(value.projects) do
        if not exact(project, { id=true, requestId=true, bayId=true, optionId=true, pricePaid=true,
            purchasedAtHours=true, phase=true, stage=true, noticeCallId=true, noticeDeliveredAtHours=true,
            arrivalDueAtHours=true, workerArrivedAtHours=true, stageStartedAtHours=true, stageDueAtHours=true,
            pausedAtHours=true, completedAtHours=true, workerReleasedAtHours=true })
            or project.id ~= string.format("WUP-%04d", index) or not token(project.requestId)
            or not BAYS[project.bayId] or not CATALOG[project.optionId] or project.optionId == "forklift"
            or not integer(project.pricePaid) or not nonnegative(project.purchasedAtHours)
            or not PHASES[project.phase] or not integer(project.stage) or project.stage > 4
            or ids[project.id] or projectBays[project.bayId]
            or (project.noticeCallId ~= nil and not token(project.noticeCallId)) then
            return false, "Invalid construction project."
        end
        for _, field in ipairs({ "noticeDeliveredAtHours", "arrivalDueAtHours", "workerArrivedAtHours",
            "stageStartedAtHours", "stageDueAtHours", "pausedAtHours", "completedAtHours", "workerReleasedAtHours" }) do
            if not optionalHours(project[field]) then return false, "Invalid construction deadline." end
        end
        local announced = project.phase == "awaiting_arrival" or project.phase == "building" or project.phase == "complete"
        local started = project.phase == "building" or project.phase == "complete"
        if announced then
            if not project.noticeCallId or not project.noticeDeliveredAtHours or not project.arrivalDueAtHours
                or project.noticeDeliveredAtHours < project.purchasedAtHours
                or not sameTime(project.arrivalDueAtHours, project.noticeDeliveredAtHours + Upgrades.ARRIVAL_LEAD_HOURS) then
                return false, "Construction requires a delivered arrival notice."
            end
        elseif project.noticeCallId or project.noticeDeliveredAtHours or project.arrivalDueAtHours then
            return false, "Unannounced construction has arrival data."
        end
        if started then
            if project.stage < 1 or not project.workerArrivedAtHours or not project.stageStartedAtHours
                or not project.stageDueAtHours or project.workerArrivedAtHours < project.arrivalDueAtHours
                or not atLeastTime(project.stageStartedAtHours,
                    project.workerArrivedAtHours + (project.stage - 1) * Upgrades.STAGE_HOURS)
                or not sameTime(project.stageDueAtHours, project.stageStartedAtHours + Upgrades.STAGE_HOURS) then
                return false, "Construction requires worker arrival and a full stage deadline."
            end
        elseif project.stage ~= 0 or project.workerArrivedAtHours or project.stageStartedAtHours
            or project.stageDueAtHours or project.pausedAtHours then
            return false, "Unstarted construction has work progress."
        end
        if project.pausedAtHours and (project.phase ~= "building"
            or project.pausedAtHours < project.stageStartedAtHours or project.pausedAtHours >= project.stageDueAtHours) then
            return false, "Invalid construction pause."
        end
        if project.phase == "complete" then
            if project.stage ~= 4 or not sameTime(project.completedAtHours, project.stageDueAtHours)
                or not atLeastTime(project.completedAtHours, project.workerArrivedAtHours + 4 * Upgrades.STAGE_HOURS)
                or (project.workerReleasedAtHours and project.workerReleasedAtHours < project.completedAtHours) then
                return false, "Invalid construction completion."
            end
        elseif project.completedAtHours or project.workerReleasedAtHours then
            return false, "Unfinished construction has completion data."
        end
        if project.phase ~= "queued" and not project.workerReleasedAtHours then
            activeCount = activeCount + 1
            if value.activeProjectId ~= project.id then return false, "Construction worker ownership mismatch." end
        elseif value.activeProjectId == project.id then return false, "Inactive project owns the worker." end
        ids[project.id], projectBays[project.bayId] = project, project
    end
    if activeCount > 1 or (value.activeProjectId and not ids[value.activeProjectId]) then
        return false, "More than one construction worker assignment."
    end
    for _, bayId in ipairs(BAY_IDS) do
        local bay, project = value.bays[bayId], projectBays[bayId]
        if not exact(bay, { status=true, optionId=true, projectId=true }) then return false, "Invalid warehouse bay." end
        if not project then
            if bay.status ~= "locked" or bay.optionId or bay.projectId then return false, "Unpurchased bay must be locked." end
        else
            local status = project.phase == "complete" and "complete" or project.phase == "building" and "building" or "reserved"
            if bay.projectId ~= project.id or bay.optionId ~= project.optionId or bay.status ~= status then
                return false, "Bay and construction project disagree."
            end
        end
    end
    local requests, paidProjects, forkliftReceipt = {}, {}, false
    for _, receipt in ipairs(value.receipts) do
        if not exact(receipt, { requestId=true, kind=true, bayId=true, optionId=true, targetId=true,
            pricePaid=true, purchasedAtHours=true }) or not token(receipt.requestId)
            or requests[receipt.requestId] or not integer(receipt.pricePaid)
            or not nonnegative(receipt.purchasedAtHours) then return false, "Invalid warehouse purchase receipt." end
        requests[receipt.requestId] = true
        if receipt.kind == "upgrade" then
            local project = ids[receipt.targetId]
            if not project or paidProjects[project.id] or receipt.bayId ~= project.bayId
                or receipt.optionId ~= project.optionId or receipt.pricePaid ~= project.pricePaid
                or receipt.purchasedAtHours ~= project.purchasedAtHours or receipt.requestId ~= project.requestId then
                return false, "Construction purchase receipt mismatch."
            end
            paidProjects[project.id] = true
        elseif receipt.kind == "forklift" then
            if forkliftReceipt or receipt.bayId ~= nil or receipt.optionId ~= "forklift" or receipt.targetId ~= "forklift" then
                return false, "Invalid forklift purchase receipt."
            end
            forkliftReceipt = true
        else return false, "Unknown warehouse purchase kind." end
    end
    for id in pairs(ids) do if not paidProjects[id] then return false, "Construction has no purchase receipt." end end
    if value.forkliftOwned ~= forkliftReceipt then return false, "Forklift entitlement and receipt disagree." end
    return true
end

-- Missing legacy state receives locked defaults. Malformed paid state is never
-- silently reset: doing so could lose purchased upgrades or allow a second debit.
function Upgrades.normalize(value)
    if value == nil then return Upgrades.defaultState() end
    local valid, reason = Upgrades.validate(value)
    if not valid then return nil, reason end
    return copy(value)
end

function Upgrades.ensure(state)
    if type(state) ~= "table" then return nil, "A shop state is required." end
    if state.warehouse == nil then state.warehouse = Upgrades.defaultState() end
    local valid, reason = Upgrades.validate(state.warehouse)
    return valid and state.warehouse or nil, reason
end

local function priorPurchase(warehouse, requestId, kind, bayId, optionId)
    for _, receipt in ipairs(warehouse.receipts) do
        if receipt.requestId == requestId then
            if receipt.kind ~= kind or receipt.bayId ~= bayId or receipt.optionId ~= optionId then
                return false, "That purchase request ID was already used for another choice.", "request_conflict"
            end
            return true, copy(kind == "upgrade" and findProject(warehouse, receipt.targetId) or receipt), "replayed"
        end
    end
end

function Upgrades.purchase(state, bayId, optionId, requestId, nowHours)
    if not BAYS[bayId] or not CATALOG[optionId] or optionId == "forklift" or not token(requestId) then
        return false, "Choose a valid bay, upgrade and purchase request ID.", "invalid_purchase"
    end
    local warehouse, reason = Upgrades.ensure(state)
    if not warehouse then return false, reason, "invalid_state" end
    local replay, result, code = priorPurchase(warehouse, requestId, "upgrade", bayId, optionId)
    if replay ~= nil then return replay, result, code end
    local now = clock(state, nowHours)
    if not now then return false, "Invalid purchase time.", "invalid_time" end
    if warehouse.bays[bayId].status ~= "locked" then return false, "That bay already has an upgrade order.", "bay_owned" end
    local price = CATALOG[optionId].price
    if not nonnegative(state.money) or state.money < price then return false, "Not enough money for this upgrade.", "insufficient_funds" end
    local project = { id = string.format("WUP-%04d", warehouse.nextProjectId), requestId = requestId,
        bayId = bayId, optionId = optionId, pricePaid = price, purchasedAtHours = now, phase = "queued", stage = 0 }
    warehouse.nextProjectId = warehouse.nextProjectId + 1
    warehouse.projects[#warehouse.projects + 1] = project
    warehouse.bays[bayId] = { status = "reserved", optionId = optionId, projectId = project.id }
    warehouse.receipts[#warehouse.receipts + 1] = { requestId = requestId, kind = "upgrade", bayId = bayId,
        optionId = optionId, targetId = project.id, pricePaid = price, purchasedAtHours = now }
    state.money = state.money - price
    return true, copy(project), "purchased"
end

function Upgrades.purchaseForklift(state, requestId, nowHours)
    if not token(requestId) then return false, "A valid purchase request ID is required.", "invalid_purchase" end
    local warehouse, reason = Upgrades.ensure(state)
    if not warehouse then return false, reason, "invalid_state" end
    local replay, result, code = priorPurchase(warehouse, requestId, "forklift", nil, "forklift")
    if replay ~= nil then return replay, result, code end
    local now = clock(state, nowHours)
    if not now then return false, "Invalid purchase time.", "invalid_time" end
    if warehouse.forkliftOwned then return false, "The shop already owns a forklift.", "forklift_owned" end
    if not nonnegative(state.money) or state.money < CATALOG.forklift.price then
        return false, "Not enough money for the forklift.", "insufficient_funds"
    end
    local receipt = { requestId = requestId, kind = "forklift", optionId = "forklift", targetId = "forklift",
        pricePaid = CATALOG.forklift.price, purchasedAtHours = now }
    state.money = state.money - receipt.pricePaid
    warehouse.forkliftOwned = true
    warehouse.receipts[#warehouse.receipts + 1] = receipt
    return true, copy(receipt), "purchased"
end

function Upgrades.activeProject(state)
    local warehouse, reason = Upgrades.ensure(state)
    if not warehouse then return nil, reason end
    return copy(findProject(warehouse, warehouse.activeProjectId))
end

function Upgrades.pendingNotice(state)
    local project = Upgrades.activeProject(state)
    if project and project.phase == "awaiting_notice" then
        return { kind = "construction_notice", projectId = project.id, bayId = project.bayId,
            optionId = project.optionId, constructionHours = Upgrades.STAGE_HOURS * 4 }
    end
end

function Upgrades.isBayAccessible(state, bayId)
    local warehouse = Upgrades.ensure(state)
    return warehouse ~= nil and BAYS[bayId] == true and warehouse.bays[bayId].status == "complete"
end

local UPDATE_FIELDS = { noticeDeliveredProjectId=true, noticeCallId=true, workerArrivedProjectId=true,
    workerReleasedProjectId=true, blockedProjectId=true, unblockedProjectId=true }

function Upgrades.update(state, nowHours, options)
    options = options or {}
    if not exact(options, UPDATE_FIELDS) then return false, "Invalid construction update gates." end
    for _, value in pairs(options) do if not token(value) then return false, "Invalid construction gate ID." end end
    if (options.noticeDeliveredProjectId ~= nil) ~= (options.noticeCallId ~= nil)
        or (options.blockedProjectId and options.unblockedProjectId) then
        return false, "Construction update gates disagree."
    end
    local warehouse, reason = Upgrades.ensure(state)
    if not warehouse then return false, reason end
    local now = clock(state, nowHours)
    if not now then return false, "Invalid construction time." end
    local events, changed = {}, false
    local function event(kind, project)
        events[#events + 1] = { kind = kind, projectId = project.id, bayId = project.bayId,
            optionId = project.optionId, stage = project.stage }
        changed = true
    end
    local project = findProject(warehouse, warehouse.activeProjectId)
    if project and project.phase == "complete" and options.workerReleasedProjectId == project.id
        and now >= project.completedAtHours then
        project.workerReleasedAtHours = now
        warehouse.activeProjectId = nil
        event("worker_released", project)
        project = nil
    end
    if not project then
        for _, queued in ipairs(warehouse.projects) do
            if queued.phase == "queued" and now >= queued.purchasedAtHours then
                project = queued
                project.phase, warehouse.activeProjectId = "awaiting_notice", project.id
                event("notice_requested", project)
                break
            end
        end
    end
    if not project then return changed, events end
    if project.phase == "awaiting_notice" and options.noticeDeliveredProjectId == project.id
        and now >= project.purchasedAtHours then
        project.noticeCallId, project.noticeDeliveredAtHours = options.noticeCallId, now
        project.arrivalDueAtHours = now + Upgrades.ARRIVAL_LEAD_HOURS
        project.phase = "awaiting_arrival"
        event("arrival_announced", project)
    end
    if project.phase == "awaiting_arrival" and options.workerArrivedProjectId == project.id
        and now >= project.arrivalDueAtHours then
        project.phase, project.stage, project.workerArrivedAtHours = "building", 1, now
        project.stageStartedAtHours, project.stageDueAtHours = now, now + Upgrades.STAGE_HOURS
        warehouse.bays[project.bayId].status = "building"
        event("work_started", project)
    end
    if project.phase ~= "building" then return changed, events end
    if project.pausedAtHours then
        if options.unblockedProjectId ~= project.id or now < project.pausedAtHours then return changed, events end
        local delay = now - project.pausedAtHours
        project.stageStartedAtHours = project.stageStartedAtHours + delay
        project.stageDueAtHours = project.stageDueAtHours + delay
        project.pausedAtHours = nil
        event("work_resumed", project)
    end
    while project.phase == "building" and now >= project.stageDueAtHours do
        if project.stage == 4 then
            project.phase, project.completedAtHours = "complete", project.stageDueAtHours
            warehouse.bays[project.bayId].status = "complete"
            event("construction_complete", project)
        else
            project.stage, project.stageStartedAtHours = project.stage + 1, project.stageDueAtHours
            project.stageDueAtHours = project.stageStartedAtHours + Upgrades.STAGE_HOURS
            event("stage_changed", project)
        end
    end
    if project.phase == "building" and options.blockedProjectId == project.id
        and now >= project.stageStartedAtHours then
        project.pausedAtHours = now
        event("work_blocked", project)
    end
    return changed, events
end

return Upgrades
