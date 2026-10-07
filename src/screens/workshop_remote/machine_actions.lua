-- Cutter and Windmill control availability and actions.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.cutterButtonEnabled = function(action)
        local view = Runtime.Screen.view or {}
        if Runtime.Screen.safetyWaiting then return false end
        if Runtime.Screen.waiting then
            return action == "emergency_stop"
                or (action == "set_barrier" and view.barrierClear == true)
        end
        if tostring(view.serviceStep or "idle") ~= "idle" then return false end
        if action == "emergency_stop" or action == "set_barrier" then return true end
        if action == "reset_safety" then
            return view.emergencyStopped == true or view.step == "blocked" or view.step == "finished"
        elseif action == "return_to_pallet" then
            return view.loaded == true and view.step == "cut_complete"
        elseif action == "run_next_lift" then
            return view.loaded == false and view.step == "repeat_ready"
        elseif action == "set_clamp" then
            return view.loaded == true and (view.step == "positioned" or view.step == "clamped")
        elseif action == "position_paper" then
            return view.loaded == true and view.clamp ~= true and view.step == "loaded"
        elseif action == "rotate_paper" then
            return view.loaded == true and view.clamp ~= true
                and (view.step == "loaded" or view.step == "positioned")
        elseif action == "auto_gauge" or action == "save_gauge" or action == "recall_gauge"
            or action == "gauge_set" or action == "select_program"
        then
            return view.loaded == true and view.clamp ~= true and view.step ~= "cutting"
        elseif action == "cut_left" or action == "cut_right" then
            return Runtime.cutterCutReady()
        elseif action == "load_stock" or action == "load_pallet" then
            return view.loaded ~= true and (view.step == "idle" or view.step == "finished")
        end
        return false
    end

    function Runtime.cutterMaintenanceStatus(state)
        local cutter
        for _, item in ipairs(state and state.machines and state.machines.items or {}) do
            if item.modelId == "polar_115" and item.status == "installed" then
                cutter = item.maintenance and item.maintenance.cutter
                break
            end
        end
        local stock = state and state.inventory and state.inventory.stock or {}
        cutter = cutter or {}
        return {
            maintenanceKits = tonumber(stock.maintenance_kit) or 0,
            bladeRemoved = cutter.bladeRemoved == true,
            bladeInSleeve = cutter.bladeInSleeve == true,
            weeklyTechnician = cutter.weeklyTechnician == true,
            technicianScheduled = cutter.nextTechnicianDay ~= nil,
        }
    end

    function Runtime.cutterServiceButtonEnabled(action, state)
        local view = Runtime.Screen.view or {}
        local status = Runtime.cutterMaintenanceStatus(state)
        if Runtime.Screen.waiting or Runtime.Screen.safetyWaiting then return false end
        local step = tostring(view.serviceStep or "idle")
        if action == "begin_lubrication" then
            return step == "idle" and view.loaded ~= true and view.step == "idle"
                and status.maintenanceKits > 0 and status.bladeRemoved ~= true
        elseif action == "begin_blade" then
            return step == "idle" and view.loaded ~= true and view.step == "idle"
                and status.bladeInSleeve ~= true
        elseif action == "book_blade_technician" then
            return step == "idle" and status.bladeInSleeve == true
                and status.technicianScheduled ~= true
        elseif action == "set_weekly_technician" then
            return step == "idle"
        elseif action == "service_advance" then
            return step == "lockout_disconnect" or step == "lockout_key"
                or step == "lockout_tag" or step == "prep_cartridge" or step == "prep_prime"
        elseif action == "service_view" or action == "service_tool"
            or action == "service_point" or action == "service_pump"
            or action == "service_gear" or action == "finish_lubrication"
        then
            return step == "lubricate"
        elseif action == "remove_blade_bolt" then
            return step == "blade_bolts"
        elseif action == "lift_blade" then
            return step == "blade_lift"
        elseif action == "sleeve_blade" then
            return step == "blade_sleeve"
        elseif action == "cancel_service" then
            return step ~= "idle"
        end
        return false
    end

    Runtime.windmillButtonEnabled = function(action, state)
        local view = Runtime.Screen.view or {}
        if Runtime.Screen.safetyWaiting then return false end
        if Runtime.Screen.waiting then return action == "emergency_stop" end
        local serviceActive = tostring(view.serviceStep or "idle") ~= "idle"
        if serviceActive and action ~= "emergency_stop"
            and action ~= "service_lockout" and action ~= "service_task"
        then
            return false
        end
        if action == "emergency_stop" then return true end
        if action == "reset_safety" then return view.emergency == true end
        if action == "toggle_motor" or action == "speed_up" or action == "speed_down" then
            return view.emergency ~= true
        elseif action == "toggle_feeder" or action == "toggle_impression" then
            return view.emergency ~= true and view.motor == true
        elseif action == "load_pallet" then
            return view.status == "idle"
        elseif action == "take_proof" then
            local needed = math.max(0, (tonumber(view.targetSheets) or 0)
                - (tonumber(view.goodSheets) or 0))
            local proofState = view.status == "setup" or view.status == "proof"
                or view.status == "approved"
            return proofState and view.jobId ~= nil and view.palletId ~= nil
                and Runtime.windmillActivePlateReady(state, view) and Runtime.windmillSetupComplete(view)
                and view.emergency ~= true and view.motor == true and view.feeder == true
                and view.impression == true and (tonumber(view.feedRemaining) or 0) > needed
        elseif action == "verify_artwork" then
            return view.status == "proof" and view.proofPermille ~= nil
        elseif action == "approve_proof" then
            return view.status == "proof" and view.artworkVerified == true
                and (tonumber(view.proofPermille) or 0) >= 820
        elseif action == "start_run" then
            return view.status == "approved" and view.proofApproved == true
                and view.emergency ~= true and view.motor == true and view.feeder == true
                and view.impression == true
        elseif action == "stop_run" then
            return view.status == "production"
        elseif action == "clean_unload" then
            return view.status == "pass_complete"
        elseif action == "begin_setup" then
            return view.palletId ~= nil and view.setupTask == nil
                and view.status ~= "production" and view.status ~= "pass_complete"
        elseif action == "setup_action" or action == "cancel_setup" then
            return view.setupTask ~= nil
        elseif action == "begin_service" then
            local stock = state and state.inventory and state.inventory.stock or {}
            return view.serviceStep == "idle" and view.status == "idle"
                and (tonumber(stock.maintenance_kit) or 0) > 0
        elseif action == "service_lockout" then
            return view.serviceStep == "lockout_disconnect"
                or view.serviceStep == "lockout_key" or view.serviceStep == "lockout_tag"
        elseif action == "service_task" then
            return view.serviceStep == "task"
        elseif action == "book_technician" then
            local scheduled = false
            for _, item in ipairs(state and state.machines and state.machines.items or {}) do
                if item.modelId == "heidelberg_10x15" and item.status == "installed" then
                    local maintenance = item.maintenance and item.maintenance.windmill or {}
                    scheduled = maintenance.technicianDueDay ~= nil
                    break
                end
            end
            return view.serviceStep == "idle" and view.status == "idle" and not scheduled
                and (tonumber(state and state.money) or 0) >= 350
        elseif action == "order_plate" or action == "begin_plate" or action == "process_plate" then
            local plate = Runtime.windmillSelectedPlate(state)
            if not plate then return false end
            if action == "process_plate" then return plate.status == "processing" end
            return plate.status == "unprepared"
        end
        return false
    end

    function Runtime.windmillMousepressed(state, x, y, sendCommand)
        for _, tab in ipairs(Runtime.WINDMILL_TAB_ORDER) do
            if Runtime.contains(Runtime.WINDMILL_TABS[tab], x, y) then
                Runtime.Screen.windmillTab = tab
                Runtime.Screen.status = tab:sub(1, 1):upper() .. tab:sub(2) .. " controls opened."
                return true
            end
        end

        local view = Runtime.Screen.view or {}
        if Runtime.Screen.windmillTab == "run" then
            if view.status == "idle" then
                for index, candidate in ipairs(Runtime.windmillCandidates()) do
                    if Runtime.contains(Runtime.windmillCandidateRect(index), x, y) then
                        return Runtime.windmillButtonEnabled("load_pallet", state)
                            and Runtime.request(sendCommand, "load_pallet", { palletId = candidate.palletId }) or true
                    end
                end
            end
            for action, rect in pairs(Runtime.WINDMILL_RUN_CONTROLS) do
                if Runtime.contains(rect, x, y) then
                    local command = action
                    if action == "run" then
                        command = view.status == "production" and "stop_run" or "start_run"
                    end
                    return Runtime.windmillButtonEnabled(command, state)
                        and Runtime.request(sendCommand, command, {}) or true
                end
            end
        elseif Runtime.Screen.windmillTab == "plates" then
            local selected, plates, _, jobs = Runtime.windmillSelectedPlate(state)
            for index, job in ipairs(jobs) do
                if Runtime.contains(Runtime.windmillPlateJobRect(index), x, y) then
                    Runtime.Screen.windmillJobId, Runtime.Screen.windmillPlateId = job.id, nil
                    Runtime.windmillSelectedPlate(state)
                    Runtime.Screen.status = "Selected plate job " .. tostring(job.id) .. "."
                    return true
                end
            end
            for index, plate in ipairs(plates) do
                if Runtime.contains(Runtime.windmillPlateRect(index), x, y) then
                    Runtime.Screen.windmillPlateId = plate.id
                    Runtime.Screen.status = "Selected " .. tostring(plate.id) .. "."
                    return true
                end
            end
            for action, rect in pairs(Runtime.WINDMILL_PLATE_CONTROLS) do
                if Runtime.contains(rect, x, y) then
                    if not selected or not Runtime.windmillButtonEnabled(action, state) then return true end
                    return Runtime.request(sendCommand, action, { plateId = selected.id })
                end
            end
        elseif Runtime.Screen.windmillTab == "setup" then
            if view.setupTask then
                if Runtime.contains(Runtime.WINDMILL_SETUP_CANCEL, x, y) then
                    return Runtime.windmillButtonEnabled("cancel_setup", state)
                        and Runtime.request(sendCommand, "cancel_setup", {}) or true
                end
                for index, control in ipairs(Runtime.PressSetupGames.controls(view.setupTask)) do
                    if Runtime.contains(Runtime.windmillSetupControlRect(view.setupTask, index), x, y) then
                        return Runtime.windmillButtonEnabled("setup_action", state)
                            and Runtime.request(sendCommand, "setup_action", { setupAction = control[1] }) or true
                    end
                end
            else
                for index, task in ipairs(Runtime.WINDMILL_SETUP_TASKS) do
                    if Runtime.contains(Runtime.windmillSetupTaskRect(index), x, y) then
                        return Runtime.windmillButtonEnabled("begin_setup", state)
                            and Runtime.request(sendCommand, "begin_setup", { setupTask = task }) or true
                    end
                end
            end
        elseif Runtime.Screen.windmillTab == "service" then
            local step = tostring(view.serviceStep or "idle")
            if step == "idle" then
                if Runtime.contains(Runtime.WINDMILL_SERVICE_CONTROLS.begin_service, x, y) then
                    return Runtime.windmillButtonEnabled("begin_service", state)
                        and Runtime.request(sendCommand, "begin_service", {}) or true
                elseif Runtime.contains(Runtime.WINDMILL_SERVICE_CONTROLS.book_technician, x, y) then
                    return Runtime.windmillButtonEnabled("book_technician", state)
                        and Runtime.request(sendCommand, "book_technician", {}) or true
                end
            elseif step == "task" then
                if Runtime.contains(Runtime.WINDMILL_SERVICE_CONTROLS.service_task, x, y) then
                    return Runtime.windmillButtonEnabled("service_task", state)
                        and Runtime.request(sendCommand, "service_task", {}) or true
                end
            elseif Runtime.contains(Runtime.WINDMILL_SERVICE_CONTROLS.service_lockout, x, y) then
                return Runtime.windmillButtonEnabled("service_lockout", state)
                    and Runtime.request(sendCommand, "service_lockout", {}) or true
            end
        end
        return false
    end
end

return Component
