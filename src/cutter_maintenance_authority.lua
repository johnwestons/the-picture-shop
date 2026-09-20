local MachineMaintenance = require("src.machine_maintenance")

local CutterMaintenanceAuthority = {}

local VIEWS = { "rear", "front", "side", "gear", "central" }
local TOOLS = { "rag", "grease", "inspect", "gear_oil" }

local function exactArguments(arguments, fields)
    if type(arguments) ~= "table" then return false end
    local allowed, count = {}, 0
    for _, field in ipairs(fields) do allowed[field] = true end
    for field in pairs(arguments) do
        if type(field) ~= "string" or not allowed[field] then return false end
        count = count + 1
    end
    return count == #fields
end

local function noArguments(arguments)
    if not exactArguments(arguments, {}) then
        return nil, "invalid_arguments", "That service action takes no additional data."
    end
    return {}
end

local function itemIndexArguments(arguments)
    local index = type(arguments) == "table" and arguments.itemIndex
    if not exactArguments(arguments, { "itemIndex" }) or type(index) ~= "number"
        or index ~= math.floor(index) or index < 1 or index > 7
    then
        return nil, "invalid_item", "Choose a valid host-listed service control."
    end
    return { itemIndex = index }
end

local function enabledArguments(arguments)
    local enabled = type(arguments) == "table" and arguments.enabled
    if not exactArguments(arguments, { "enabled" }) or type(enabled) ~= "boolean" then
        return nil, "invalid_enabled", "The technician schedule must be enabled or disabled."
    end
    return { enabled = enabled }
end

local function clampInteger(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, math.floor(tonumber(value) or minimum)))
end

local function serviceStep(session)
    local lubrication = session and session.lubrication
    if lubrication then
        if lubrication.stage == "lockout" then
            if not lubrication.lockout.disconnect then return "lockout_disconnect" end
            if not lubrication.lockout.key then return "lockout_key" end
            return "lockout_tag"
        elseif lubrication.stage == "prep" then
            return lubrication.prep.cartridge and "prep_prime" or "prep_cartridge"
        end
        return "lubricate"
    end
    if session and session.bladeStage then
        return "blade_" .. session.bladeStage
    end
    return "idle"
end

local function currentItems(lubrication)
    local items = {}
    if lubrication.activeView == "central" and lubrication.centralInstalled then
        local point = lubrication.central
        items[1] = {
            itemIndex = 7,
            label = "Central lubrication fitting",
            cleaned = point.cleaned == true,
            coupled = point.coupled == true,
            strokes = clampInteger(point.strokes, 0, 99),
            complete = point.complete == true,
        }
        return items
    end
    for index, point in ipairs(lubrication.points or {}) do
        if point.view == lubrication.activeView then
            items[#items + 1] = {
                itemIndex = index,
                label = tostring(point.label or point.id),
                cleaned = point.cleaned == true,
                coupled = point.coupled == true,
                strokes = clampInteger(point.strokes, 0, 99),
                complete = point.complete == true,
            }
        end
    end
    return items
end

function CutterMaintenanceAuthority.newSession()
    return {
        lubrication = nil,
        bladeStage = nil,
        bladeBolts = { false, false, false, false },
    }
end

function CutterMaintenanceAuthority.create(options)
    options = options or {}
    local state = assert(options.state, "cutter maintenance authority requires state")
    local baseView = assert(options.baseView,
        "cutter maintenance authority requires a base view callback")
    local validateAccess = assert(options.validateAccess,
        "cutter maintenance authority requires an access validator")
    local save = assert(options.save, "cutter maintenance authority requires a save callback")
    local machineReady = assert(options.machineReady,
        "cutter maintenance authority requires a machine readiness callback")

    local authority = {}

    function authority.view(session, includeCandidates)
        local view = baseView(includeCandidates == true)
        local lubrication = session and session.lubrication
        if lubrication then
            view.candidates, view.genericSheets = nil, nil
            view.serviceStep = serviceStep(session)
            view.servicePermille = clampInteger(
                MachineMaintenance.lubricationProgress(lubrication) * 1000, 0, 1000)
            if lubrication.stage == "service" then
                for index, name in ipairs(VIEWS) do
                    if name == lubrication.activeView then view.serviceView = index; break end
                end
                for index, name in ipairs(TOOLS) do
                    if name == lubrication.activeTool then view.serviceTool = index; break end
                end
                view.serviceItems = currentItems(lubrication)
                view.centralInstalled = lubrication.centralInstalled == true
                view.gearInspected = lubrication.gear.inspected == true
                view.gearLevelPermille = clampInteger(lubrication.gear.level * 1000, 0, 1000)
            end
        elseif session and session.bladeStage then
            view.candidates, view.genericSheets = nil, nil
            view.serviceStep = serviceStep(session)
            local removed, mask = 0, 0
            for index = 1, 4 do
                if session.bladeBolts[index] then removed = removed + 1; mask = mask + 2^(index-1) end
            end
            view.bladeBoltsDone = removed
            view.bladeBoltMask = mask
            view.servicePermille = session.bladeStage == "bolts" and removed * 150
                or session.bladeStage == "lift" and 750 or 900
        end
        return view
    end

    local function perform(lease, player, operation, durable)
        local allowed, code, message = validateAccess(player)
        if not allowed then
            return false, code, message, authority.view(lease and lease.private, true)
        end
        local accepted, resultCode, resultMessage = operation()
        accepted = accepted == true
        if accepted and durable then save() end
        return accepted, resultCode or (accepted and "completed" or "service_blocked"),
            tostring(resultMessage or (accepted and "Cutter service action completed."
                or "The cutter is not ready for that service action.")),
            authority.view(lease and lease.private, true)
    end

    local function requireIdleMachine()
        local ready, message = machineReady()
        if ready ~= true then return false, "machine_busy", message end
        return true
    end

    local commands = {}

    commands.begin_lubrication = {
        normalize = noArguments,
        perform = function(lease, player)
            return perform(lease, player, function()
                if lease.private.lubrication or lease.private.bladeStage then
                    return false, "service_active", "Finish or cancel the active cutter service first."
                end
                local ready, code, message = requireIdleMachine()
                if not ready then return false, code, message end
                local _, cutter = MachineMaintenance.cutterStatus(state)
                if cutter and cutter.bladeRemoved then
                    return false, "blade_removed", "Reinstall the cutter blade before lubricating the machine."
                end
                local session, errorMessage = MachineMaintenance.beginCutterLubrication(state)
                if not session then return false, "service_blocked", errorMessage end
                lease.private.lubrication = session
                return true, "service_started", "Cutter lubrication opened. Begin the lockout sequence."
            end, false)
        end,
    }

    commands.service_advance = {
        normalize = noArguments,
        perform = function(lease, player)
            return perform(lease, player, function()
                local session = lease.private.lubrication
                if not session then return false, "service_inactive", "Begin cutter lubrication first." end
                local step = serviceStep(lease.private)
                local action = ({
                    lockout_disconnect = "disconnect", lockout_key = "key", lockout_tag = "tag",
                })[step]
                local accepted
                if action then
                    accepted = MachineMaintenance.lubricationLockout(session, action)
                elseif step == "prep_cartridge" then
                    accepted = MachineMaintenance.lubricationPrepare(session, "cartridge")
                elseif step == "prep_prime" then
                    accepted = MachineMaintenance.lubricationPrepare(session, "prime")
                else
                    return false, "wrong_step", "The ordered lockout and preparation sequence is complete."
                end
                return accepted, accepted and "service_advanced" or "wrong_step",
                    accepted and "Cutter service advanced to the next host-owned step."
                        or "Complete the service controls in order."
            end, false)
        end,
    }

    commands.service_view = {
        normalize = itemIndexArguments,
        perform = function(lease, player, arguments)
            return perform(lease, player, function()
                local session = lease.private.lubrication
                local view = VIEWS[arguments.itemIndex]
                if not session or not view then return false, "invalid_view", "Choose a valid service view." end
                local accepted = MachineMaintenance.selectLubricationView(session, view)
                return accepted, accepted and "view_selected" or "view_blocked",
                    accepted and ("Service view changed to " .. view .. ".")
                        or "That service view is unavailable."
            end, false)
        end,
    }

    commands.service_tool = {
        normalize = itemIndexArguments,
        perform = function(lease, player, arguments)
            return perform(lease, player, function()
                local session = lease.private.lubrication
                local tool = TOOLS[arguments.itemIndex]
                if not session or not tool then return false, "invalid_tool", "Choose a valid service tool." end
                local accepted = MachineMaintenance.selectLubricationTool(session, tool)
                return accepted, accepted and "tool_selected" or "tool_blocked",
                    accepted and ("Selected " .. tool:gsub("_", " ") .. ".")
                        or "That tool is unavailable right now."
            end, false)
        end,
    }

    commands.service_point = {
        normalize = itemIndexArguments,
        perform = function(lease, player, arguments)
            return perform(lease, player, function()
                local session = lease.private.lubrication
                if not session then return false, "service_inactive", "Begin cutter lubrication first." end
                local pointId = arguments.itemIndex == 7 and "central"
                    or session.points[arguments.itemIndex] and session.points[arguments.itemIndex].id
                if not pointId then return false, "invalid_point", "Choose a host-listed lubrication point." end
                local accepted = MachineMaintenance.serviceLubricationPoint(session, pointId)
                return accepted, accepted and "point_serviced" or "point_blocked",
                    accepted and "The host accepted that lubrication-point action."
                        or "Clean the visible point before coupling the grease gun."
            end, false)
        end,
    }

    commands.service_pump = {
        normalize = noArguments,
        perform = function(lease, player)
            return perform(lease, player, function()
                local session = lease.private.lubrication
                local accepted = session and MachineMaintenance.pumpLubricationGun(session)
                return accepted, accepted and "grease_pumped" or "pump_blocked",
                    accepted and "Grease stroke registered by the host."
                        or "Couple the grease gun to a cleaned point first."
            end, false)
        end,
    }

    commands.service_gear = {
        normalize = noArguments,
        perform = function(lease, player)
            return perform(lease, player, function()
                local session = lease.private.lubrication
                if not session then return false, "service_inactive", "Begin cutter lubrication first." end
                local accepted = session.activeTool == "inspect"
                    and MachineMaintenance.inspectGearOil(session)
                    or session.activeTool == "gear_oil"
                        and MachineMaintenance.topUpGearOil(session) or false
                return accepted, accepted and "gear_serviced" or "gear_blocked",
                    accepted and "Gearbox sight-glass action accepted."
                        or "Select the gearbox view and the correct inspection or oil tool."
            end, false)
        end,
    }

    commands.finish_lubrication = {
        normalize = noArguments,
        perform = function(lease, player)
            return perform(lease, player, function()
                local session = lease.private.lubrication
                if not session then return false, "service_inactive", "Begin cutter lubrication first." end
                local accepted, result = MachineMaintenance.finishCutterLubrication(state, session)
                if not accepted then return false, "service_incomplete", result end
                lease.private.lubrication = nil
                return true, "maintenance_completed", "Cutter lubrication completed and saved by the host."
            end, true)
        end,
    }

    commands.cancel_service = {
        normalize = noArguments,
        perform = function(lease, player)
            return perform(lease, player, function()
                if not lease.private.lubrication and not lease.private.bladeStage then
                    return false, "service_inactive", "No cutter service is active."
                end
                lease.private.lubrication = nil
                lease.private.bladeStage = nil
                lease.private.bladeBolts = { false, false, false, false }
                return true, "service_cancelled", "Uncommitted cutter service progress was safely discarded."
            end, false)
        end,
    }

    commands.begin_blade = {
        normalize = noArguments,
        perform = function(lease, player)
            return perform(lease, player, function()
                if lease.private.lubrication or lease.private.bladeStage then
                    return false, "service_active", "Finish or cancel the active cutter service first."
                end
                local ready, code, message = requireIdleMachine()
                if not ready then return false, code, message end
                local _, cutter = MachineMaintenance.cutterStatus(state)
                if not cutter or cutter.bladeRemoved or cutter.bladeInSleeve then
                    return false, "blade_unavailable", "The cutter blade is already secured for service."
                end
                lease.private.bladeStage = "bolts"
                lease.private.bladeBolts = { false, false, false, false }
                return true, "blade_service_started", "Blade removal opened. Remove all four host-tracked bolts."
            end, false)
        end,
    }

    commands.remove_blade_bolt = {
        normalize = itemIndexArguments,
        perform = function(lease, player, arguments)
            return perform(lease, player, function()
                local index = arguments.itemIndex
                if lease.private.bladeStage ~= "bolts" or index > 4 then
                    return false, "wrong_step", "The blade bolts are not ready for that action."
                end
                if lease.private.bladeBolts[index] then
                    return false, "already_removed", "That blade bolt is already removed."
                end
                lease.private.bladeBolts[index] = true
                local allRemoved = true
                for bolt = 1, 4 do allRemoved = allRemoved and lease.private.bladeBolts[bolt] end
                if allRemoved then lease.private.bladeStage = "lift" end
                return true, "bolt_removed", allRemoved
                    and "All bolts are out. Lift the blade into the handling position."
                    or "Blade bolt removed."
            end, false)
        end,
    }

    commands.lift_blade = {
        normalize = noArguments,
        perform = function(lease, player)
            return perform(lease, player, function()
                if lease.private.bladeStage ~= "lift" then
                    return false, "wrong_step", "Remove all four blade bolts first."
                end
                lease.private.bladeStage = "sleeve"
                return true, "blade_lifted", "Blade lifted safely. Place it in the wooden sleeve."
            end, false)
        end,
    }

    commands.sleeve_blade = {
        normalize = noArguments,
        perform = function(lease, player)
            return perform(lease, player, function()
                if lease.private.bladeStage ~= "sleeve" then
                    return false, "wrong_step", "Lift the released blade before sleeving it."
                end
                local accepted, result = MachineMaintenance.prepareBladeForTechnician(state)
                if not accepted then return false, "blade_blocked", result end
                lease.private.bladeStage = nil
                lease.private.bladeBolts = { false, false, false, false }
                return true, "blade_sleeved", "Cutter blade removed, sleeved, and saved by the host."
            end, true)
        end,
    }

    commands.book_blade_technician = {
        normalize = noArguments,
        perform = function(lease, player)
            return perform(lease, player, function()
                if lease.private.lubrication or lease.private.bladeStage then
                    return false, "service_active", "Finish or cancel the active cutter service first."
                end
                local accepted, result = MachineMaintenance.requestTechnician(state)
                if not accepted then return false, "technician_blocked", result end
                return true, "technician_booked",
                    "Blade technician booked for game day " .. tostring(result) .. "."
            end, true)
        end,
    }

    commands.set_weekly_technician = {
        normalize = enabledArguments,
        perform = function(lease, player, arguments)
            return perform(lease, player, function()
                if lease.private.lubrication or lease.private.bladeStage then
                    return false, "service_active", "Finish or cancel the active cutter service first."
                end
                local _, cutter = MachineMaintenance.cutterStatus(state)
                if cutter and cutter.weeklyTechnician == arguments.enabled then
                    return false, "schedule_unchanged", arguments.enabled
                        and "Weekly blade service is already scheduled."
                        or "Weekly blade service is already disabled."
                end
                local accepted, result = MachineMaintenance.setWeeklyTechnician(state, arguments.enabled)
                if not accepted then return false, "technician_blocked", result end
                return true, "technician_schedule", arguments.enabled
                    and "Weekly blade service scheduled."
                    or "Weekly blade service cancelled."
            end, true)
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
                    if lease.private
                        and (lease.private.lubrication or lease.private.bladeStage)
                    then
                        return false, "service_active",
                            "Finish or cancel cutter maintenance before operating the machine.",
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

return CutterMaintenanceAuthority
