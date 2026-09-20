-- Host/local orchestration only: durable phone notices + explicit physical
-- worker gates. This module never spawns/teleports an actor or invents dialogue.
local Calendar = require("src.business_calendar")
local Upgrades = require("src.warehouse_upgrades")
local Phone = require("src.work_phone")

local Service = { RING_HOURS = 1 }
local observations = setmetatable({}, { __mode = "k" })
local CALLBACKS = { workerStarted=true, workerArrived=true, workerExited=true, workerBlocked=true }
local BAY_NAMES = { front_left="front-left bay", front_right="front-right bay" }
local function finiteHours(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end
local function matches(call, project)
    return type(call) == "table" and call.kind == "construction_notice"
        and call.projectId == project.id and call.bayId == project.bayId and call.optionId == project.optionId
end
local function findNotice(phone, project)
    if matches(phone.incoming, project) then return phone.incoming end
    for _, call in ipairs(phone.history) do if matches(call, project) then return call end end
end
local function noticeSpec(project)
    local option = Upgrades.catalog(project.optionId)
    return { kind="construction_notice", projectId=project.id, bayId=project.bayId, optionId=project.optionId,
        caller="Warehouse construction", role="CONSTRUCTION SERVICE", subject="UPGRADE APPOINTMENT",
        message=string.format("%s: %s in the %s. Builder arrival through the front entrance is scheduled in %d game hours. Four construction stages take one game day each. Keep the marked approach clear.",
            project.id, option.name, BAY_NAMES[project.bayId], Upgrades.ARRIVAL_LEAD_HOURS) }
end

-- Callbacks receive (state, detachedProject, nowHours). Started must idempotently
-- ensure/confirm a physical visit by project ID; Arrived/Exited confirm actual
-- positions, never merely elapsed time. A callback may return (ready, changed)
-- if it also changed its own authoritative visitor state. Missing callbacks
-- are false gates. Runtime dispatch must be saved by the integrating caller.
function Service.update(state, nowHours, callbacks)
    callbacks = callbacks or {}
    if type(callbacks) ~= "table" then return false, "Construction callbacks must be a table." end
    for key, callback in pairs(callbacks) do
        if not CALLBACKS[key] or type(callback) ~= "function" then return false, "Invalid construction worker callback." end
    end
    local warehouse, errorMessage = Upgrades.ensure(state)
    if not warehouse then return false, errorMessage end
    local now = nowHours == nil and Calendar.absoluteHours(state) or nowHours
    if not finiteHours(now) then return false, "Invalid construction time." end
    local changed, events = false, {}
    local function append(kind, project, detail)
        events[#events + 1] = { kind=kind, projectId=project and project.id,
            bayId=project and project.bayId, optionId=project and project.optionId, message=detail }
    end
    local function advance(at, gates)
        local updated, emitted = Upgrades.update(state, at, gates)
        if type(emitted) ~= "table" then return false, emitted end
        changed = changed or updated
        for _, item in ipairs(emitted) do events[#events + 1] = item end
        return true
    end
    local function worker(name, project)
        if not callbacks[name] then return false end
        local okay, ready, runtimeChanged = pcall(callbacks[name], state, Upgrades.activeProject(state), now)
        if not okay then append("worker_callback_failed", project, name .. ": " .. tostring(ready)); return false end
        if runtimeChanged == true then
            changed = true
            append("worker_runtime_changed", project, name)
        end
        return ready == true
    end

    local project = Upgrades.activeProject(state)
    if not project then
        local okay, reason = advance(now)
        if not okay then return false, reason end
        project = Upgrades.activeProject(state)
    end
    local phone = Phone.ensure(state)
    local ringing = phone.incoming
    if ringing and ringing.kind == "construction_notice" and not ringing.answered
        and finiteHours(ringing.receivedAtHours) and now >= ringing.receivedAtHours + Service.RING_HOURS then
        local missed = Phone.missConstructionNotice(state, ringing.id, now)
        if missed then changed = true; append("notice_missed", {id=ringing.projectId,bayId=ringing.bayId,optionId=ringing.optionId}) end
    end
    if not project then observations[state] = nil; return changed, events end

    if project.phase == "awaiting_notice" then
        local notice = findNotice(phone, project)
        if not notice and not phone.incoming then
            local queued, result = Phone.queueCall(state, noticeSpec(project), now)
            if queued then
                notice, changed = result, true
                append("notice_queued", project)
            end
        end
        if notice and finiteHours(notice.receivedAtHours) and notice.receivedAtHours <= now then
            local deliveredAt = math.max(project.purchasedAtHours, notice.receivedAtHours)
            local okay, reason = advance(deliveredAt,
                {noticeDeliveredProjectId=project.id,noticeCallId=notice.id})
            if not okay then return changed, reason end
            project = Upgrades.activeProject(state)
        end
    end
    if project.phase == "awaiting_arrival" and now >= project.arrivalDueAtHours then
        if worker("workerStarted", project) and worker("workerArrived", project)
            and not worker("workerBlocked", project) then
            local okay, reason = advance(now, {workerArrivedProjectId=project.id})
            if not okay then return changed, reason end
            observations[state] = {warehouse=warehouse,projectId=project.id,confirmedAtHours=now}
            project = Upgrades.activeProject(state)
        end
    elseif project.phase == "building" then
        local present = worker("workerStarted", project) and worker("workerArrived", project)
        local blocked = not present or worker("workerBlocked", project)
        if blocked then
            if not project.pausedAtHours then
                -- Never catch up phantom work when the runtime is absent.
                -- After reload, conservatively stop at this stage's start;
                -- during a live visit retain work up to the last real check.
                local last = observations[state]
                local confirmed = last and last.warehouse == warehouse and last.projectId == project.id and last.confirmedAtHours
                    or project.stageStartedAtHours
                local pauseAt = math.max(project.stageStartedAtHours,
                    math.min(now, confirmed, project.stageDueAtHours - 0.000001))
                local okay, reason = advance(pauseAt, {blockedProjectId=project.id})
                if not okay then return changed, reason end
                project = Upgrades.activeProject(state)
            end
        else
            local gates = project.pausedAtHours and {unblockedProjectId=project.id} or nil
            local okay, reason = advance(now, gates)
            if not okay then return changed, reason end
            observations[state] = {warehouse=warehouse,projectId=project.id,confirmedAtHours=now}
            project = Upgrades.activeProject(state)
        end
    end
    if project.phase == "complete" and worker("workerExited", project) then
        local okay, reason = advance(now, {workerReleasedProjectId=project.id})
        if not okay then return changed, reason end
        observations[state] = nil
    end
    return changed, events
end

return Service
