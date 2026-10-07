-- Authoritative Windmill command handlers.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.createWindmillCommands()
        local commands = {
            load_pallet = {
                normalize = Runtime.windmillTokenArguments("palletId", "invalid_pallet",
                    "Choose a valid nearby print pallet."),
                perform = function(lease, player, arguments)
                    return Runtime.performWindmillAction(player, lease,
                        function() return Runtime.Windmill.load(Runtime.state, arguments.palletId) end, true)
                end,
            },
            toggle_motor = Runtime.windmillSimpleCommand(function(targetState)
                return Runtime.Windmill.control(targetState, "motor")
            end),
            toggle_feeder = Runtime.windmillSimpleCommand(function(targetState)
                return Runtime.Windmill.control(targetState, "feeder")
            end),
            toggle_impression = Runtime.windmillSimpleCommand(function(targetState)
                return Runtime.Windmill.control(targetState, "impression")
            end),
            speed_up = Runtime.windmillSimpleCommand(function(targetState)
                return Runtime.Windmill.control(targetState, "speed_up")
            end),
            speed_down = Runtime.windmillSimpleCommand(function(targetState)
                return Runtime.Windmill.control(targetState, "speed_down")
            end),
            emergency_stop = Runtime.windmillSimpleCommand(function(targetState)
                return Runtime.Windmill.control(targetState, "emergency")
            end, nil, true),
            reset_safety = Runtime.windmillSimpleCommand(function(targetState)
                return Runtime.Windmill.control(targetState, "reset")
            end),
            take_proof = Runtime.windmillSimpleCommand(Runtime.Windmill.takeProof),
            verify_artwork = Runtime.windmillSimpleCommand(Runtime.Windmill.verifyArtwork),
            approve_proof = Runtime.windmillSimpleCommand(Runtime.Windmill.approveProof),
            start_run = Runtime.windmillSimpleCommand(Runtime.Windmill.startProduction),
            stop_run = Runtime.windmillSimpleCommand(Runtime.Windmill.stopProduction),
            clean_unload = Runtime.windmillSimpleCommand(Runtime.Windmill.cleanAndUnload),
            order_plate = {
                normalize = Runtime.windmillTokenArguments("plateId", "invalid_plate",
                    "Choose a valid press plate."),
                perform = function(lease, player, arguments)
                    return Runtime.performWindmillAction(player, lease, function()
                        local job, plate, colorIndex = Runtime.findPlateById(arguments.plateId)
                        if not job or not plate then return false, "That press plate no longer exists." end
                        local accepted, result = Runtime.PlateService.order(Runtime.state, job, colorIndex)
                        if not accepted then return false, result end
                        Runtime.Windmill.bumpNetworkRevision()
                        return true, "Plate ordered from the trade platemaker."
                    end, true)
                end,
            },
            begin_plate = {
                normalize = Runtime.windmillTokenArguments("plateId", "invalid_plate",
                    "Choose a valid press plate."),
                perform = function(lease, player, arguments)
                    return Runtime.performWindmillAction(player, lease, function()
                        local job, plate, colorIndex = Runtime.findPlateById(arguments.plateId)
                        if not job or not plate then return false, "That press plate no longer exists." end
                        local accepted, result = Runtime.PlateService.beginInHouse(Runtime.state, job, colorIndex)
                        if not accepted then return false, result end
                        Runtime.Windmill.bumpNetworkRevision()
                        return true, "In-house platemaking started."
                    end, true)
                end,
            },
            process_plate = {
                normalize = Runtime.windmillTokenArguments("plateId", "invalid_plate",
                    "Choose a valid press plate."),
                perform = function(lease, player, arguments)
                    return Runtime.performWindmillAction(player, lease, function()
                        local _, plate = Runtime.findPlateById(arguments.plateId)
                        if not plate then return false, "That press plate no longer exists." end
                        local action = Runtime.PlateService.actionFor(plate)
                        if not action then return false, "That plate is already complete." end
                        local marker = Runtime.windmillPlateMarkerPermille()
                        local accuracy = math.max(0, math.min(1,
                            1 - math.abs(marker - 670) / 330))
                        local accepted, result = Runtime.PlateService.process(plate, action, accuracy)
                        if not accepted then return false, result end
                        Runtime.Windmill.bumpNetworkRevision()
                        return true, string.format("%s step completed at %d%% accuracy.",
                            action:gsub("^%l", string.upper), math.floor(accuracy * 100 + 0.5))
                    end, true)
                end,
            },
        }

        local setupTasks = {}
        for _, task in ipairs(Runtime.Windmill.setupTasks()) do setupTasks[task] = true end
        commands.begin_setup = {
            normalize = function(arguments)
                local task = type(arguments) == "table" and arguments.setupTask
                if not Runtime.exactArguments(arguments, { "setupTask" }) or not setupTasks[task] then
                    return nil, "invalid_setup", "Choose one of the six Windmill setup checks."
                end
                return { setupTask = task }
            end,
            perform = function(lease, player, arguments)
                return Runtime.performWindmillAction(player, lease, function()
                    local process, job = Runtime.Windmill.current(Runtime.state)
                    if not process.palletId or not job then
                        return false, "Load a print-ready pallet before setup."
                    end
                    local session = lease.private
                    if session.setupGame then return false, "Finish or cancel the open setup check first." end
                    session.setupTask = arguments.setupTask
                    session.setupGame = Runtime.PressSetupGames.new(arguments.setupTask, job)
                    Runtime.Windmill.bumpNetworkRevision()
                    return true, arguments.setupTask:upper() .. " setup check opened."
                end, false)
            end,
        }

        local setupActions = {}
        for _, task in ipairs(Runtime.Windmill.setupTasks()) do
            for _, control in ipairs(Runtime.PressSetupGames.controls(task)) do
                setupActions[control[1]] = true
            end
        end
        commands.setup_action = {
            normalize = function(arguments)
                local action = type(arguments) == "table" and arguments.setupAction
                if not Runtime.exactArguments(arguments, { "setupAction" }) or not setupActions[action] then
                    return nil, "invalid_setup_action", "Choose a valid setup control."
                end
                return { setupAction = action }
            end,
            perform = function(lease, player, arguments)
                return Runtime.performWindmillAction(player, lease, function()
                    local session = lease.private
                    local game, task = session.setupGame, session.setupTask
                    if not game or not task then return false, "Open a setup check first." end
                    local valid = false
                    for _, control in ipairs(Runtime.PressSetupGames.controls(task)) do
                        if control[1] == arguments.setupAction then valid = true; break end
                    end
                    if not valid then return false, "That control does not belong to this setup check." end
                    local complete, score = Runtime.PressSetupGames.apply(game, arguments.setupAction)
                    if complete then
                        local accepted, result = Runtime.Windmill.completeSetup(Runtime.state, task, score)
                        session.setupGame, session.setupTask = nil, nil
                        if not accepted then return false, result end
                        Runtime.saveCurrent()
                        return true, task:upper() .. " setup check completed."
                    end
                    Runtime.Windmill.bumpNetworkRevision()
                    return true, Runtime.PressSetupGames.summary(game)
                end, false)
            end,
        }
        commands.cancel_setup = {
            normalize = Runtime.windmillNoArguments,
            perform = function(lease, player)
                return Runtime.performWindmillAction(player, lease, function()
                    local session = lease.private
                    if not session or not session.setupGame then
                        return false, "No setup check is open."
                    end
                    session.setupGame, session.setupTask = nil, nil
                    Runtime.Windmill.bumpNetworkRevision()
                    return true, "Setup check cancelled."
                end, false)
            end,
        }

        commands.begin_service = {
            normalize = Runtime.windmillNoArguments,
            perform = function(lease, player)
                return Runtime.performWindmillAction(player, lease, function()
                    local process = Runtime.Windmill.ensure(Runtime.state)
                    if process.status ~= "idle" or process.palletId then
                        return false, "Unload the Windmill and return it to idle before service."
                    end
                    if lease.private.maintenance then return false, "Windmill service is already open." end
                    local item = Runtime.MachineFleet.installed(Runtime.state, "heidelberg_10x15")
                    if not item then return false, "No Heidelberg Windmill is installed." end
                    local maintenance, errorMessage = Runtime.MachineMaintenance.begin(Runtime.state, item.id)
                    if not maintenance then return false, errorMessage end
                    Runtime.Windmill.releaseOperator(Runtime.state)
                    lease.private.setupGame, lease.private.setupTask = nil, nil
                    lease.private.maintenance, lease.private.lockoutStep = maintenance, 1
                    Runtime.Windmill.bumpNetworkRevision()
                    return true, "Windmill service opened. Begin the lockout sequence."
                end, true)
            end,
        }
        commands.service_lockout = {
            normalize = Runtime.windmillNoArguments,
            perform = function(lease, player)
                return Runtime.performWindmillAction(player, lease, function()
                    local session = lease.private
                    if not session.maintenance then return false, "Begin Windmill service first." end
                    local step = math.max(1, math.floor(tonumber(session.lockoutStep) or 1))
                    if step > 3 then return false, "The service lockout is already complete." end
                    local labels = { "Disconnect opened.", "Lockout key secured.", "Service tag attached." }
                    session.lockoutStep = step + 1
                    Runtime.Windmill.bumpNetworkRevision()
                    return true, labels[step]
                end, false, true)
            end,
        }
        commands.service_task = {
            normalize = Runtime.windmillNoArguments,
            perform = function(lease, player)
                return Runtime.performWindmillAction(player, lease, function()
                    local session, maintenance = lease.private, lease.private.maintenance
                    if not maintenance then return false, "Begin Windmill service first." end
                    if (session.lockoutStep or 1) <= 3 then
                        return false, "Complete disconnect, key, and tag lockout first."
                    end
                    local task = Runtime.MachineMaintenance.activeTask(maintenance)
                    if not task then return false, "No maintenance task is ready." end
                    if not Runtime.MachineMaintenance.submitTask(maintenance, task.id, 0.92) then
                        return false, "That maintenance task could not be completed."
                    end
                    if maintenance.finished then
                        local accepted, result = Runtime.MachineMaintenance.commit(Runtime.state, maintenance)
                        if not accepted then
                            Runtime.MachineMaintenance.rollbackLastTask(maintenance, task.id)
                            return false, result
                        end
                        session.maintenance, session.lockoutStep = nil, nil
                        Runtime.Windmill.bumpNetworkRevision()
                        Runtime.saveCurrent()
                        return true, "Windmill maintenance completed and returned to service."
                    end
                    Runtime.Windmill.bumpNetworkRevision()
                    return true, tostring(task.label or task.id) .. " completed."
                end, false, true)
            end,
        }
        commands.book_technician = Runtime.windmillSimpleCommand(function(targetState)
            local accepted, result = Runtime.MachineMaintenance.requestWindmillTechnician(targetState)
            if accepted then Runtime.Windmill.bumpNetworkRevision() end
            return accepted, accepted and "Windmill field technician booked for the next business day." or result
        end)
        return commands
    end
end

return Component
