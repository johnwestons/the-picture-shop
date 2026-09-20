local MachineMaintenance = require("src.machine_maintenance")

local WrapperMaintenanceAuthority = {}

local TASK_TARGETS = {
    turntableBearing = 3,
    filmCarriage = 3,
    driveBelt = 1,
    controlBoard = 3,
}

local function exactArguments(arguments, required)
    if type(arguments) ~= "table" then return false end
    local allowed = {}
    for _, name in ipairs(required or {}) do allowed[name] = true end
    for key in pairs(arguments) do
        if type(key) ~= "string" or not allowed[key] then return false end
    end
    for _, name in ipairs(required or {}) do
        if arguments[name] == nil then return false end
    end
    return true
end

local function noArguments(arguments)
    if not exactArguments(arguments, {}) then
        return nil, "invalid_arguments", "That wrapper-service action takes no additional data."
    end
    return {}
end

local function targetArguments(arguments)
    local value = type(arguments) == "table" and arguments.itemIndex
    if not exactArguments(arguments, { "itemIndex" })
        or type(value) ~= "number" or value ~= math.floor(value)
        or value < 1 or value > 3
    then
        return nil, "invalid_target", "Choose the currently marked wrapper-service target."
    end
    return { itemIndex = value }
end

local function clampInteger(value, minimum, maximum)
    value = math.floor(tonumber(value) or minimum)
    return math.max(minimum, math.min(maximum, value))
end

local function serviceView(view, session)
    if not session then return view end
    local task = MachineMaintenance.activeTask(session)
    local taskState = MachineMaintenance.wrapperTaskState(session)
    if not task or not taskState then return view end
    local targetCount = TASK_TARGETS[task.id]
    if not targetCount then return view end

    -- Production candidates and stale runtime selection are irrelevant while
    -- the host-owned service bay has the machine locked out.
    view.step, view.progress = "idle", 0
    view.selectedPalletId, view.palletId = nil, nil
    view.pallets = {}
    view.serviceStep = "task"
    view.serviceTaskId = task.id
    view.serviceTaskIndex = clampInteger(session.activeIndex, 1, #session.tasks)
    view.serviceTaskCount = #session.tasks
    view.servicePhase = clampInteger(taskState.phase, 1, targetCount)
    view.serviceTargetCount = targetCount
    view.serviceAttempts = clampInteger(taskState.attempts, 0, 9999)
    view.serviceMisses = clampInteger(taskState.misses, 0, view.serviceAttempts)
    local completed = math.max(0, session.activeIndex - 1)
    local withinTask = math.max(0, taskState.phase - 1) / targetCount
    view.servicePermille = clampInteger(
        (completed + withinTask) / math.max(1, #session.tasks) * 1000, 0, 999)
    return view
end

function WrapperMaintenanceAuthority.newSession()
    return { maintenance = nil }
end

function WrapperMaintenanceAuthority.create(options)
    options = options or {}
    local state = assert(options.state, "wrapper maintenance authority requires state")
    local baseView = assert(options.baseView,
        "wrapper maintenance authority requires a base view callback")
    local validateAccess = assert(options.validateAccess,
        "wrapper maintenance authority requires an access validator")
    local machineReady = assert(options.machineReady,
        "wrapper maintenance authority requires a machine readiness callback")
    local resetRuntime = type(options.resetRuntime) == "function"
        and options.resetRuntime or function() return true end
    local save = assert(options.save, "wrapper maintenance authority requires a save callback")

    local authority = {}

    function authority.view(session, detailed)
        return serviceView(baseView(detailed ~= false), session and session.maintenance)
    end

    local function perform(lease, player, operation, durable)
        local allowed, code, message = validateAccess(player)
        if not allowed then
            return false, code, message, authority.view(lease and lease.private, true)
        end
        local accepted, resultCode, resultMessage = operation()
        accepted = accepted == true
        if accepted and durable then save() end
        return accepted, resultCode or (accepted and "service_updated" or "service_blocked"),
            tostring(resultMessage or (accepted and "Wrapper service updated."
                or "The wrapper is not ready for that service action.")),
            authority.view(lease and lease.private, true)
    end

    local commands = {}

    commands.begin_service = {
        normalize = noArguments,
        perform = function(lease, player)
            return perform(lease, player, function()
                if lease.private.maintenance then
                    return false, "service_active", "Finish or cancel the active wrapper service first."
                end
                local ready, code, message = machineReady()
                if ready ~= true then return false, code or "machine_busy", message end
                local session, errorMessage = MachineMaintenance.beginWrapperService(state)
                if not session then return false, "service_blocked", errorMessage end
                if resetRuntime() ~= true then
                    return false, "machine_changed", "The wrapper changed before service could begin."
                end
                lease.private.maintenance = session
                return true, "service_started",
                    "Wrapper service opened. Follow the host-ordered component targets."
            end, false)
        end,
    }

    commands.service_target = {
        normalize = targetArguments,
        perform = function(lease, player, arguments)
            return perform(lease, player, function()
                local session = lease.private.maintenance
                local task = session and MachineMaintenance.activeTask(session)
                local taskState = session and MachineMaintenance.wrapperTaskState(session)
                local targetCount = task and TASK_TARGETS[task.id]
                if not session or not task or not taskState or not targetCount then
                    return false, "service_inactive", "Begin wrapper service first."
                end
                if arguments.itemIndex ~= taskState.phase
                    or arguments.itemIndex > targetCount
                then
                    return false, "stale_target",
                        "That marker is no longer active; use the current host-listed target."
                end
                local x, y = MachineMaintenance.wrapperTarget(session, arguments.itemIndex)
                if not x or not y then
                    return false, "target_unavailable", "The current service marker is unavailable."
                end
                local result = MachineMaintenance.wrapperTaskClick(session, x, y)
                if not result.hit then
                    return false, "target_changed", "The service marker changed before the host accepted it."
                end
                if result.finished then
                    local committed, itemOrError = MachineMaintenance.commit(state, session)
                    if not committed then
                        MachineMaintenance.rollbackLastTask(session, result.task.id)
                        session.taskState[result.task.id] = nil
                        return false, "commit_blocked", tostring(itemOrError)
                    end
                    lease.private.maintenance = nil
                    save()
                    return true, "maintenance_completed",
                        string.format("Wrapper service completed at %.1f%% condition.",
                            tonumber(itemOrError.condition) or 0)
                end
                if result.completedTask then
                    local nextTask = MachineMaintenance.activeTask(session)
                    return true, "task_completed", "Component complete. Next: "
                        .. tostring(nextTask and nextTask.componentLabel or "final inspection") .. "."
                end
                return true, "target_completed", "Service target accepted by the host."
            end, false)
        end,
    }

    commands.service_miss = {
        normalize = noArguments,
        perform = function(lease, player)
            return perform(lease, player, function()
                local session = lease.private.maintenance
                if not session then return false, "service_inactive", "Begin wrapper service first." end
                local result = MachineMaintenance.wrapperTaskClick(session, -10000, -10000)
                if result.ignored then
                    return false, "service_inactive", "No wrapper-service target is active."
                end
                return true, "target_missed",
                    "Miss recorded by the host. Re-align with the active service marker."
            end, false)
        end,
    }

    commands.cancel_service = {
        normalize = noArguments,
        perform = function(lease, player)
            return perform(lease, player, function()
                if not lease.private.maintenance then
                    return false, "service_inactive", "No wrapper service is active."
                end
                lease.private.maintenance = nil
                return true, "service_cancelled",
                    "Uncommitted wrapper-service progress was safely discarded."
            end, false)
        end,
    }

    authority.commands = commands

    function authority.withProductionCommands(production)
        local merged = {}
        for action, spec in pairs(production or {}) do
            local productionSpec = spec
            merged[action] = {
                normalize = productionSpec.normalize,
                perform = function(lease, player, arguments, context)
                    if lease.private and lease.private.maintenance then
                        return false, "service_active",
                            "Finish or cancel wrapper maintenance before operating the machine.",
                            authority.view(lease.private, true)
                    end
                    local accepted, code, message = productionSpec.perform(
                        lease, player, arguments, context)
                    return accepted, code, message, authority.view(lease.private, true)
                end,
            }
        end
        for action, spec in pairs(commands) do merged[action] = spec end
        return merged
    end

    return authority
end

WrapperMaintenanceAuthority.TASK_TARGETS = TASK_TARGETS

return WrapperMaintenanceAuthority
