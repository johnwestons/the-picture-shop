local MachineFleet = require("src.machine_fleet")
local BusinessCalendar = require("src.business_calendar")

local Maintenance = {}

local function clamp(value)
    return math.max(0, math.min(1, tonumber(value) or 0))
end

function Maintenance.begin(state, machineId)
    local stock = state and state.inventory and state.inventory.stock or {}
    if (stock.maintenance_kit or 0) < 1 then
        return nil, "A machine maintenance kit is required before beginning service."
    end
    local plan, errorMessage = MachineFleet.maintenancePlan(state, machineId)
    if not plan then return nil, errorMessage end
    return {
        machineId = plan.machineId,
        modelId = plan.modelId,
        tasks = plan.tasks,
        activeIndex = 1,
        scores = {},
        animationClock = 0,
        interactions = 0,
        finished = false,
    }
end

function Maintenance.update(session, dt)
    if type(session) ~= "table" or session.finished then return false end
    session.animationClock = session.animationClock + math.max(0, tonumber(dt) or 0)
    if session.pumpPulse then session.pumpPulse = math.max(0, session.pumpPulse - math.max(0, tonumber(dt) or 0)) end
    return true
end

function Maintenance.activeTask(session)
    return type(session) == "table" and session.tasks[session.activeIndex] or nil
end

function Maintenance.submitTask(session, taskId, score)
    if type(session) ~= "table" or session.finished then return false end
    local task = Maintenance.activeTask(session)
    if not task or task.id ~= taskId then return false end
    session.scores[taskId] = clamp(score)
    session.interactions = session.interactions + 1
    session.activeIndex = session.activeIndex + 1
    session.finished = session.activeIndex > #session.tasks
    return true
end

function Maintenance.rollbackLastTask(session, taskId)
    if type(session) ~= "table" or type(session.tasks) ~= "table"
        or type(session.scores) ~= "table" or session.finished ~= true
        or session.activeIndex ~= #session.tasks + 1
    then
        return false
    end
    local task = session.tasks[#session.tasks]
    if not task or task.id ~= taskId then return false end
    session.activeIndex, session.finished = #session.tasks, false
    session.scores[taskId] = nil
    return true
end

function Maintenance.progress(session)
    if type(session) ~= "table" or #session.tasks == 0 then return 0 end
    local completed = math.min(#session.tasks, session.activeIndex - 1)
    return completed / #session.tasks
end

function Maintenance.commit(state, session)
    if type(session) ~= "table" or not session.finished then
        return false, "Complete every maintenance task before returning the machine to service."
    end
    return MachineFleet.completeMaintenance(state, session.machineId, session.scores)
end

local wrapperTargets = {
    turntableBearing = { { 300, 366 }, { 420, 408 }, { 538, 364 } },
    filmCarriage = { { 404, 214 }, { 404, 304 }, { 404, 390 } },
    controlBoard = { { 470, 224 }, { 520, 310 }, { 556, 396 } },
}

local function wrapperTarget(session, taskId, index)
    local targets = wrapperTargets[taskId]
    if targets then
        local base = targets[index]
        if not base then return nil end
        local clock = session and session.animationClock or 0
        return base[1] + math.sin(clock * 1.4 + index * 1.8) * 10,
            base[2] + math.cos(clock * 1.1 + index * 1.3) * 7
    end
    if taskId == "driveBelt" then
        local clock = session and session.animationClock or 0
        return 420 + math.sin(clock * 1.5) * 120, 390
    end
end

local function prepareWrapperTask(session)
    local task = Maintenance.activeTask(session)
    if not task then return nil end
    session.taskState = session.taskState or {}
    session.taskState[task.id] = { phase = 1, hits = 0, misses = 0, attempts = 0, completed = false }
    return session.taskState[task.id]
end

function Maintenance.beginWrapperService(state)
    local item = MachineFleet.installed(state, "skid_wrapper")
    if not item then return nil, "No skid wrapper is installed." end
    local session, errorMessage = Maintenance.begin(state, item.id)
    if not session then return nil, errorMessage end
    session.kind = "wrapper_service"
    session.taskState = {}
    prepareWrapperTask(session)
    return session
end

function Maintenance.wrapperTarget(session, index)
    local task = Maintenance.activeTask(session)
    if not task then return nil end
    local state = session.taskState and session.taskState[task.id]
    return wrapperTarget(session, task.id, index or (state and state.phase) or 1)
end

function Maintenance.wrapperTaskState(session)
    local task = Maintenance.activeTask(session)
    return task and session.taskState and session.taskState[task.id] or nil
end

local function wrapperTaskScore(taskState)
    return math.max(0.55, math.min(1, 1 - taskState.misses * 0.12
        - math.max(0, taskState.attempts - taskState.hits) * 0.03))
end

function Maintenance.wrapperTaskClick(session, x, y)
    if type(session) ~= "table" or session.kind ~= "wrapper_service" or session.finished then
        return { hit = false, ignored = true }
    end
    local task = Maintenance.activeTask(session)
    local taskState = Maintenance.wrapperTaskState(session)
        or (task and prepareWrapperTask(session))
    if not task or not taskState then return { hit = false, ignored = true } end
    taskState.attempts = taskState.attempts + 1
    local tx, ty = wrapperTarget(session, task.id, taskState.phase)
    local hit = tx and ty and (x - tx) ^ 2 + (y - ty) ^ 2 <= 38 ^ 2
    if not hit then
        taskState.misses = taskState.misses + 1
        return { hit = false, misses = taskState.misses, task = task }
    end
    taskState.hits = taskState.hits + 1
    local targetCount = task.id == "driveBelt" and 1 or 3
    taskState.phase = taskState.phase + 1
    if taskState.phase <= targetCount then
        return { hit = true, hits = taskState.hits, task = task }
    end
    taskState.completed = true
    local score = wrapperTaskScore(taskState)
    Maintenance.submitTask(session, task.id, score)
    if not session.finished then prepareWrapperTask(session) end
    return {
        hit = true, completedTask = true, finished = session.finished,
        score = score, hits = taskState.hits, task = task,
    }
end

function Maintenance.cutterStatus(state)
    local item = MachineFleet.installed(state, "polar_115")
    return item, item and item.maintenance.cutter or nil
end

local lubricationPoints = {
    { id = "backgauge_left", label = "Left backgauge rail", view = "rear", x = 230, y = 335 },
    { id = "backgauge_right", label = "Right backgauge rail", view = "rear", x = 500, y = 335 },
    { id = "knife_guide", label = "Knife guide gib", view = "front", x = 235, y = 310 },
    { id = "clamp_guide", label = "Clamp guide gib", view = "front", x = 500, y = 310 },
    { id = "eccentric", label = "Eccentric bearing", view = "side", x = 280, y = 320 },
    { id = "crank_pin", label = "Crank pin", view = "side", x = 485, y = 350 },
}

function Maintenance.beginCutterLubrication(state)
    local item = MachineFleet.installed(state, "polar_115")
    local stock = state and state.inventory and state.inventory.stock or {}
    if not item then return nil, "No cutter is installed." end
    if (stock.maintenance_kit or 0) < 1 then
        return nil, "A machine maintenance kit is required for lubrication."
    end
    local points = {}
    for _, source in ipairs(lubricationPoints) do
        points[#points + 1] = {
            id = source.id, label = source.label, view = source.view, x = source.x, y = source.y,
            cleaned = false, coupled = false, strokes = 0, complete = false,
        }
    end
    local cutter = item.maintenance.cutter
    return {
        kind = "cutter_lubrication", machineId = item.id, animationClock = 0,
        stage = "lockout", lockout = { disconnect = false, key = false, tag = false },
        prep = { cartridge = false, primed = false }, points = points,
        activeView = "rear", activeTool = "rag", coupledPoint = nil,
        centralInstalled = cutter.centralLubricationInstalled == true,
        central = { cleaned = false, coupled = false, strokes = 0, flashes = 0, complete = false },
        gear = { inspected = false, level = cutter.gearOilLevel or 0.48, topUps = 0 },
        errors = 0, overgrease = 0, finished = false,
    }
end

Maintenance.beginCutterOiling = Maintenance.beginCutterLubrication

function Maintenance.lubricationPoint(session, pointId)
    for _, point in ipairs(session and session.points or {}) do
        if point.id == pointId then return point end
    end
end

function Maintenance.lubricationLockout(session, action)
    if not session or session.stage ~= "lockout" then return false end
    if action == "disconnect" and not session.lockout.disconnect then
        session.lockout.disconnect = true
    elseif action == "key" and session.lockout.disconnect and not session.lockout.key then
        session.lockout.key = true
    elseif action == "tag" and session.lockout.key and not session.lockout.tag then
        session.lockout.tag = true
    else
        session.errors = session.errors + 1
        return false
    end
    if session.lockout.tag then session.stage = "prep" end
    return true
end

function Maintenance.lubricationPrepare(session, action)
    if not session or session.stage ~= "prep" then return false end
    if action == "cartridge" and not session.prep.cartridge then
        session.prep.cartridge = true
    elseif action == "prime" and session.prep.cartridge and not session.prep.primed then
        session.prep.primed = true
    else
        session.errors = session.errors + 1
        return false
    end
    if session.prep.primed then session.stage = "service" end
    return true
end

function Maintenance.selectLubricationView(session, view)
    if not session or session.stage ~= "service" then return false end
    if not ({ rear = true, front = true, side = true, gear = true, central = true })[view] then return false end
    if view == "central" and not session.centralInstalled then return false end
    session.activeView, session.coupledPoint = view, nil
    return true
end

function Maintenance.selectLubricationTool(session, tool)
    if not session or session.stage ~= "service" then return false end
    if not ({ rag = true, grease = true, inspect = true, gear_oil = true })[tool] then return false end
    session.activeTool, session.coupledPoint = tool, nil
    return true
end

function Maintenance.serviceLubricationPoint(session, pointId)
    if not session or session.stage ~= "service" then return false end
    if session.activeView == "central" then
        local point = session.central
        if session.activeTool == "rag" and not point.cleaned then point.cleaned = true; return true end
        if session.activeTool == "grease" and point.cleaned then
            point.coupled, session.coupledPoint = true, "central"
            return true
        end
    end
    local point = Maintenance.lubricationPoint(session, pointId)
    if not point or point.view ~= session.activeView then return false end
    if session.activeTool == "rag" and not point.cleaned then point.cleaned = true; return true end
    if session.activeTool == "grease" and point.cleaned and not point.complete then
        point.coupled, session.coupledPoint = true, point.id
        return true
    end
    session.errors = session.errors + 1
    return false
end

function Maintenance.pumpLubricationGun(session)
    if not session or session.activeTool ~= "grease" or not session.coupledPoint then return false end
    session.pumpPulse = 0.28
    if session.coupledPoint == "central" then
        local point = session.central
        point.strokes = point.strokes + 1
        if point.strokes == 2 or point.strokes == 4 then point.flashes = point.flashes + 1 end
        if point.flashes >= 2 then point.complete = true end
        if point.strokes > 4 then session.overgrease = session.overgrease + 1 end
        return true
    end
    local point = Maintenance.lubricationPoint(session, session.coupledPoint)
    if not point then return false end
    point.strokes = point.strokes + 1
    if point.strokes >= 2 then point.complete = true end
    if point.strokes > 3 then session.overgrease = session.overgrease + 1 end
    return true
end

function Maintenance.inspectGearOil(session)
    if not session or session.stage ~= "service" or session.activeView ~= "gear"
        or session.activeTool ~= "inspect" then return false end
    session.gear.inspected = true
    return true
end

function Maintenance.topUpGearOil(session)
    if not session or not session.gear.inspected or session.activeView ~= "gear"
        or session.activeTool ~= "gear_oil" then return false end
    session.gear.topUps = session.gear.topUps + 1
    session.gear.level = math.min(0.50, session.gear.level + 0.06)
    return true
end

function Maintenance.canFinishCutterLubrication(session)
    if not session or session.stage ~= "service" or not session.gear.inspected
        or session.gear.level < 0.42 or session.gear.level > 0.58 then return false end
    if session.centralInstalled then return session.central.complete end
    for _, point in ipairs(session.points) do if not point.complete then return false end end
    return true
end

function Maintenance.lubricationProgress(session)
    if not session then return 0 end
    if session.stage == "lockout" then
        return ((session.lockout.disconnect and 1 or 0) + (session.lockout.key and 1 or 0)
            + (session.lockout.tag and 1 or 0)) / 12
    elseif session.stage == "prep" then
        return (3 + (session.prep.cartridge and 1 or 0) + (session.prep.primed and 1 or 0)) / 12
    end
    local done, required = 0, session.centralInstalled and 1 or #session.points
    if session.centralInstalled then done = session.central.complete and 1 or 0
    else for _, point in ipairs(session.points) do done = done + (point.complete and 1 or 0) end end
    return math.min(1, (5 + done * 6 / required + (session.gear.inspected and 1 or 0)) / 12)
end

function Maintenance.finishCutterLubrication(state, session)
    if not Maintenance.canFinishCutterLubrication(session) then
        return false, "Complete the lubrication points and inspect the gearbox sight glass first."
    end
    local correct = 0
    if session.centralInstalled then correct = session.central.strokes == 4 and 1 or 0
    else
        for _, point in ipairs(session.points) do
            if point.strokes == 2 or point.strokes == 3 then correct = correct + 1 end
        end
        correct = correct / #session.points
    end
    local score = clamp(0.55 + correct * 0.35 - session.errors * 0.025 - session.overgrease * 0.08)
    session.finished = true
    local completed, result = MachineFleet.completeCutterLubrication(state, session.machineId,
        { score = score, gearOilLevel = session.gear.level })
    if not completed then session.finished = false end
    return completed, result
end

Maintenance.finishCutterOiling = Maintenance.finishCutterLubrication

function Maintenance.prepareBladeForTechnician(state)
    local item, cutter = Maintenance.cutterStatus(state)
    if not item then return false, "No cutter is installed." end
    cutter.bladeRemoved, cutter.bladeInSleeve = true, true
    return true, cutter
end

function Maintenance.requestTechnician(state)
    local item, cutter = Maintenance.cutterStatus(state)
    if not item then return false, "No cutter is installed." end
    if not cutter.bladeInSleeve then return false, "Remove the blade and place it in its wooden sleeve first." end
    if cutter.nextTechnicianDay then return false, "A blade technician is already scheduled." end
    cutter.nextTechnicianDay = state.calendar.totalDays + 1
    cutter.appointmentType = "requested"
    return true, cutter.nextTechnicianDay
end

function Maintenance.setWeeklyTechnician(state, enabled)
    local item, cutter = Maintenance.cutterStatus(state)
    if not item then return false, "No cutter is installed." end
    cutter.weeklyTechnician = enabled == true
    if cutter.weeklyTechnician then
        cutter.nextTechnicianDay = state.calendar.totalDays + 7
        cutter.appointmentType = "weekly"
    elseif cutter.appointmentType == "weekly" then
        cutter.nextTechnicianDay, cutter.appointmentType = nil, nil
    end
    return true, cutter
end

local function technicianOutcome(item, day)
    local sequence = item.maintenance.cutter.technicianSequence + 1
    item.maintenance.cutter.technicianSequence = sequence
    return (day * 37 + sequence * 29 + tonumber(item.id:match("(%d+)$")) * 11) % 100
end

local function updateCutterTechnician(state)
    local item, cutter = Maintenance.cutterStatus(state)
    if not item or not cutter.nextTechnicianDay or state.calendar.totalDays < cutter.nextTechnicianDay then
        return false
    end
    local appointmentDay = cutter.nextTechnicianDay
    local outcome = technicianOutcome(item, appointmentDay)
    if outcome < 15 then
        MachineFleet.addServiceNotice(state, "Technician unable to attend",
            "We cannot make today's cutter-blade appointment. We have moved the visit to next week and apologize for the disruption.")
        cutter.nextTechnicianDay = appointmentDay + 7
        state.message = "The blade technician emailed: this week's visit was cancelled."
    elseif outcome < 35 then
        MachineFleet.addServiceNotice(state, "Blade technician running late",
            "Our technician is running behind and will arrive one business day late for the cutter-blade service.")
        cutter.nextTechnicianDay = appointmentDay + 1
        state.message = "The blade technician emailed that the appointment is running late."
    elseif not cutter.bladeInSleeve then
        MachineFleet.addServiceNotice(state, "Blade was not ready for service",
            "The cutter blade was not removed and secured in its wooden sleeve, so it could not be sharpened during today's visit.")
        cutter.nextTechnicianDay = cutter.weeklyTechnician and appointmentDay + 7 or nil
        cutter.appointmentType = cutter.weeklyTechnician and "weekly" or nil
        state.message = "The technician could not sharpen the cutter blade because it was not sleeved."
    else
        local Technician = require("src.technician")
        if not Technician.schedule(state, "cutter", appointmentDay, cutter.weeklyTechnician) then return false end
        cutter.nextTechnicianDay = nil
        cutter.technicianStatus = "traveling"
    end
    return true
end

function Maintenance.requestWindmillTechnician(state)
    local item = MachineFleet.installed(state, "heidelberg_10x15")
    if not item then return false, "No Heidelberg Windmill is installed." end
    local press = item.maintenance.windmill
    if press.technicianDueDay then return false, "A press technician is already scheduled." end
    if (state.money or 0) < 350 then return false, "The $350 service call is not affordable right now." end
    state.money = state.money - 350
    press.technicianDueDay = state.calendar.totalDays + 1
    press.technicianStatus = "scheduled"
    return true, press.technicianDueDay
end

function Maintenance.updateWindmillTechnician(state)
    local item = MachineFleet.installed(state, "heidelberg_10x15")
    local press = item and item.maintenance.windmill
    if not press or not press.technicianDueDay
        or state.calendar.totalDays < press.technicianDueDay then return false end
    local Technician = require("src.technician")
    if not Technician.schedule(state, "windmill", press.technicianDueDay, false) then return false end
    press.technicianDueDay, press.technicianStatus = nil, "traveling"
    return true
end

function Maintenance.completeTechnicianVisit(state, kind, visit)
    if kind == "windmill" then
        local item = MachineFleet.installed(state, "heidelberg_10x15")
        if not item then return false end
        local press = item.maintenance.windmill
        for _, componentId in ipairs({ "gripperTiming", "driveLubrication", "safetyCircuit", "suctionAir" }) do
            item.variables[componentId] = math.max(item.variables[componentId] or 0, 88)
        end
        press.technicianStatus = "completed"
        press.serviceCount = (press.serviceCount or 0) + 1
        MachineFleet.condition(item)
        MachineFleet.addServiceNotice(state, "Windmill field service complete",
            "The lizard technician checked gripper timing, suction, lubrication, guards, and emergency controls. The press is released for production.",
            "Letterpress Field Service")
        return true
    end
    local item, cutter = Maintenance.cutterStatus(state)
    if not item then return false end
    item.variables.bladeSharpness = 100
    item.condition = MachineFleet.condition(item)
    cutter.bladeRemoved, cutter.bladeInSleeve = false, false
    cutter.technicianStatus = "completed"
    local appointmentDay = visit and visit.appointmentDay or state.calendar.totalDays
    local recurring = visit and visit.recurring or cutter.weeklyTechnician
    cutter.nextTechnicianDay = recurring and appointmentDay + 7 or nil
    cutter.appointmentType = recurring and "weekly" or nil
    MachineFleet.addServiceNotice(state, "Cutter blade sharpened",
        "The mouse technician sharpened, inspected, and reinstalled the sleeved cutter blade. The cutter is ready for production.")
    return true
end

function Maintenance.updateTechnician(state)
    local cutterChanged = updateCutterTechnician(state)
    local pressChanged = Maintenance.updateWindmillTechnician(state)
    return cutterChanged or pressChanged
end

return Maintenance
