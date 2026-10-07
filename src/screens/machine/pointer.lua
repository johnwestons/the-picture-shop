-- Machine console pointer actions.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Screen.mousepressed(state, x, y, button)
        if Runtime.dependencies.remoteCommand and Runtime.Screen.remoteServiceInput then
            local handled = Runtime.Screen.remoteServiceInput(state, x, y, button)
            if handled ~= nil then return handled end
        end
        if button ~= 1 then return false end
        -- Android text input is opt-in: every non-field tap releases the gauge
        -- before the gauge hit target below can explicitly focus it again.
        Runtime.Screen.gaugeFocused = false
        if Runtime.Screen.helpOpen then
            if Runtime.inside(Runtime.helpBack, x, y) then Runtime.Screen.helpOpen = false; return { action = "help_close" } end
            if Runtime.inside(Runtime.helpPrevious, x, y) then Runtime.Screen.helpStep = math.max(1, Runtime.Screen.helpStep - 1); return true end
            if Runtime.inside(Runtime.helpNext, x, y) then
                if Runtime.Screen.helpStep < #Runtime.cutterHelp then Runtime.Screen.helpStep = Runtime.Screen.helpStep + 1 else Runtime.Screen.helpOpen = false end
                return true
            end
            return true
        end
        if Runtime.Screen.maintenanceView == "wrapper_task" then
            if Runtime.inside(Runtime.maintenanceBack, x, y) then
                Runtime.Screen.maintenanceView, Runtime.Screen.wrapperSession = "wrapper_hub", nil
                return { action = "maintenance_cancel" }
            end
            local result = Runtime.MachineMaintenance.wrapperTaskClick(Runtime.Screen.wrapperSession, x, y)
            if result.hit then
                if result.finished then
                    local completed, itemOrError = Runtime.MachineMaintenance.commit(state, Runtime.Screen.wrapperSession)
                    if completed then
                        Runtime.Screen.wrapperSession, Runtime.Screen.maintenanceView = nil, "wrapper_hub"
                        state.message = string.format("Wrapper service complete. Condition is now %.1f%%.",
                            Runtime.MachineFleet.condition(itemOrError))
                        return { action = "maintenance_completed" }
                    end
                    Runtime.MachineMaintenance.rollbackLastTask(Runtime.Screen.wrapperSession, result.task.id)
                    Runtime.Screen.wrapperSession.taskState[result.task.id] = nil
                    state.message = tostring(itemOrError)
                elseif result.completedTask then
                    local nextTask = Runtime.MachineMaintenance.activeTask(Runtime.Screen.wrapperSession)
                    state.message = "Step complete. Next: " .. (nextTask and nextTask.componentLabel or "final inspection") .. "."
                end
            else
                state.message = "Missed the service point. Re-align and try again."
            end
            return true
        elseif Runtime.Screen.maintenanceView == "wrapper_hub" then
            local item = Runtime.MachineFleet.installed(state, "skid_wrapper")
            local stock = state.inventory and state.inventory.stock or {}
            local safetyReady = not Runtime.Wrapper.isActive() and not Runtime.Wrapper.nearbyPallet(state)
            if Runtime.inside(Runtime.maintenanceBack, x, y) then
                Runtime.Screen.maintenanceView = nil
                return { action = "maintenance_close" }
            elseif Runtime.inside(Runtime.wrapperServiceButton, x, y) and item and safetyReady
                and (stock.maintenance_kit or 0) > 0 then
                local session, errorMessage = Runtime.MachineMaintenance.beginWrapperService(state)
                if not session then state.message = tostring(errorMessage); return true end
                Runtime.Screen.wrapperSession, Runtime.Screen.maintenanceView = session, "wrapper_task"
                state.message = "Begin with the marked " .. session.tasks[1].componentLabel .. " service points."
                return { action = "maintenance_minigame", game = "wrapper_service" }
            end
            return true
        elseif Runtime.Screen.maintenanceView == "oil" then
            if Runtime.inside(Runtime.maintenanceBack, x, y) then
                Runtime.Screen.maintenanceView, Runtime.Screen.oilSession = "hub", nil
                return { action = "maintenance_cancel" }
            end
            local session = Runtime.Screen.oilSession
            if session.stage == "lockout" then
                for action, rect in pairs(Runtime.lockoutButtons) do
                    if Runtime.inside(rect, x, y) then
                        Runtime.MachineMaintenance.lubricationLockout(session, action)
                        return true
                    end
                end
            elseif session.stage == "prep" then
                for action, rect in pairs(Runtime.prepButtons) do
                    if Runtime.inside(rect, x, y) then
                        Runtime.MachineMaintenance.lubricationPrepare(session, action)
                        return true
                    end
                end
            else
                for index, view in ipairs(Runtime.lubricationViews) do
                    local rect = { x = 42 + (index - 1) * 113, y = 112, width = 105, height = 34 }
                    if Runtime.inside(rect, x, y) then
                        Runtime.MachineMaintenance.selectLubricationView(session, view)
                        return true
                    end
                end
                for index, tool in ipairs(Runtime.lubricationTools) do
                    local rect = { x = 650, y = 176 + (index - 1) * 48, width = 234, height = 39 }
                    if Runtime.inside(rect, x, y) then
                        Runtime.MachineMaintenance.selectLubricationTool(session, tool)
                        return true
                    end
                end
                if Runtime.inside(Runtime.pumpButton, x, y) then
                    Runtime.MachineMaintenance.pumpLubricationGun(session)
                    return true
                elseif Runtime.inside(Runtime.finishLubricationButton, x, y) then
                    local completed, result = Runtime.MachineMaintenance.finishCutterLubrication(state, session)
                    if completed then
                        Runtime.Screen.maintenanceView, Runtime.Screen.oilSession = "hub", nil
                        state.message = string.format("Cutter lubrication complete. Quality %.0f%%; condition %.1f%%.",
                            result.maintenance.lastServiceQuality * 100, result.condition)
                        return { action = "maintenance_completed" }
                    end
                    state.message = tostring(result)
                    return true
                elseif session.activeView == "gear" and (x - 490) ^ 2 + (y - 340) ^ 2 <= 55 ^ 2 then
                    if session.activeTool == "inspect" then Runtime.MachineMaintenance.inspectGearOil(session)
                    elseif session.activeTool == "gear_oil" then Runtime.MachineMaintenance.topUpGearOil(session) end
                    return true
                elseif session.activeView == "central" and (x - 370) ^ 2 + (y - 330) ^ 2 <= 45 ^ 2 then
                    Runtime.MachineMaintenance.serviceLubricationPoint(session, "central")
                    return true
                else
                    for _, point in ipairs(session.points) do
                        if point.view == session.activeView
                            and (x - point.x) ^ 2 + (y - point.y) ^ 2 <= 38 ^ 2 then
                            Runtime.MachineMaintenance.serviceLubricationPoint(session, point.id)
                            return true
                        end
                    end
                end
            end
            return true
        elseif Runtime.Screen.maintenanceView == "blade" then
            if Runtime.inside(Runtime.maintenanceBack, x, y) then
                Runtime.Screen.maintenanceView, Runtime.Screen.bladeStage, Runtime.Screen.bladeBolts = "hub", nil, nil
                return { action = "maintenance_cancel" }
            end
            if Runtime.Screen.bladeStage == "bolts" then
                for index, pos in ipairs(Runtime.bladeBoltPositions()) do
                    if not Runtime.Screen.bladeBolts[index] and (x - pos[1]) ^ 2 + (y - pos[2]) ^ 2 <= 24 ^ 2 then
                        Runtime.Screen.bladeBolts[index] = true
                        local allRemoved = true
                        for bolt = 1, 4 do allRemoved = allRemoved and Runtime.Screen.bladeBolts[bolt] end
                        if allRemoved then Runtime.Screen.bladeStage = "blade" end
                        return true
                    end
                end
            elseif Runtime.Screen.bladeStage == "blade" and x >= 304 and x <= 656 and y >= 280 and y <= 342 then
                Runtime.Screen.bladeStage = "sleeve"
                return true
            elseif Runtime.Screen.bladeStage == "sleeve" and x >= 330 and x <= 630 and y >= 445 and y <= 505 then
                local completed, result = Runtime.MachineMaintenance.prepareBladeForTechnician(state)
                if completed then
                    Runtime.Screen.maintenanceView, Runtime.Screen.bladeStage, Runtime.Screen.bladeBolts = "hub", nil, nil
                    state.message = "Cutter blade removed and secured in its wooden sleeve. Book the technician when ready."
                    return { action = "blade_sleeved" }
                end
                state.message = tostring(result)
            end
            return true
        elseif Runtime.Screen.maintenanceView == "hub" then
            local _, cutter = Runtime.MachineMaintenance.cutterStatus(state)
            local stock = state.inventory and state.inventory.stock or {}
            if Runtime.inside(Runtime.maintenanceBack, x, y) then
                Runtime.Screen.maintenanceView = nil
                return { action = "maintenance_close" }
            elseif Runtime.inside(Runtime.oilServiceButton, x, y) and (stock.maintenance_kit or 0) > 0 and not cutter.bladeRemoved then
                local session, errorMessage = Runtime.MachineMaintenance.beginCutterLubrication(state)
                if not session then state.message = tostring(errorMessage); return true end
                Runtime.Screen.oilSession, Runtime.Screen.maintenanceView = session, "oil"
                state.message = "Begin by locking out the cutter's main disconnect."
                return { action = "maintenance_minigame", game = "cutter_lubrication" }
            elseif Runtime.inside(Runtime.bladeServiceButton, x, y) and not cutter.bladeInSleeve then
                Runtime.Screen.maintenanceView, Runtime.Screen.bladeStage = "blade", "bolts"
                Runtime.Screen.bladeBolts = { false, false, false, false }
                return { action = "maintenance_minigame", game = "blade_removal" }
            elseif Runtime.inside(Runtime.technicianButton, x, y) and cutter.bladeInSleeve and not cutter.nextTechnicianDay then
                local booked, day = Runtime.MachineMaintenance.requestTechnician(state)
                if booked then state.message = "Blade technician booked for game day " .. tostring(day) .. "." end
                return { action = "technician_booked" }
            elseif Runtime.inside(Runtime.weeklyButton, x, y) then
                Runtime.MachineMaintenance.setWeeklyTechnician(state, not cutter.weeklyTechnician)
                state.message = cutter.weeklyTechnician and "Weekly blade service scheduled."
                    or "Weekly blade service cancelled."
                return { action = "technician_schedule" }
            end
            return true
        end
        if Runtime.Screen.loadMenu then
            local pageStart = math.floor((Runtime.Screen.loadMenu.selected - 1) / Runtime.loadMenuPageSize)
                * Runtime.loadMenuPageSize + 1
            local pageEnd = math.min(#Runtime.Screen.loadMenu.options, pageStart + Runtime.loadMenuPageSize - 1)
            for index = pageStart, pageEnd do
                local displayIndex = index - pageStart + 1
                local row = {
                    x = Runtime.loadMenuRect.x + 16,
                    y = Runtime.loadMenuRect.y + 68 + (displayIndex - 1) * Runtime.loadMenuRect.rowHeight,
                    width = Runtime.loadMenuRect.width - 32,
                    height = Runtime.loadMenuRect.rowHeight - 6,
                }
                if Runtime.inside(row, x, y) then return Runtime.loadSelected(state, index) end
            end
            return true
        end
        if Runtime.inside(Runtime.exitButton, x, y) then return { action = "exit" } end
        if state.machineType == "skid_wrapper" then
            local nearbyPallets = Runtime.Wrapper.nearbyPallets(state)
            for index = 1, math.min(#nearbyPallets, Runtime.wrapperPalletList.maxRows) do
                local row = { x = Runtime.wrapperPalletList.x,
                    y = Runtime.wrapperPalletList.y + (index - 1) * Runtime.wrapperPalletList.rowHeight,
                    width = Runtime.wrapperPalletList.width, height = Runtime.wrapperPalletList.rowHeight - 6 }
                if Runtime.inside(row, x, y) then
                    return Runtime.Wrapper.selectPallet(state, nearbyPallets[index].pallet.id)
                end
            end
            if Runtime.inside(Runtime.wrapperMaintenanceButton, x, y) then
                if Runtime.Wrapper.isActive() then
                    state.message = "Wait for the wrapping cycle to finish before opening maintenance."
                    return true
                end
                Runtime.Screen.maintenanceView = "wrapper_hub"
                return { action = "maintenance_hub" }
            end
            return Runtime.inside(Runtime.wrapButton, x, y) and Runtime.Wrapper.start(state) or false
        end
        if Runtime.inside(Runtime.helpButton, x, y) then
            Runtime.Screen.helpOpen, Runtime.Screen.helpStep, Runtime.Screen.gaugeFocused = true, 1, false
            return { action = "help_open" }
        end
        if Runtime.inside(Runtime.maintenanceButton, x, y) then
            if Runtime.Machine.loaded or Runtime.Machine.step ~= "idle" then
                state.message = "Unload the cutter and return it to idle before opening maintenance."
                return true
            end
            Runtime.Screen.maintenanceView = "hub"
            Runtime.Screen.gaugeFocused = false
            return { action = "maintenance_hub" }
        end
        Runtime.layout()
        if Runtime.inside(Runtime.gaugeInput, x, y) then
            Runtime.Screen.gaugeFocused = true
            Runtime.Screen.gaugeReplaceOnType = true
            return true
        end
        for _, target in ipairs(Runtime.buttons) do
            if Runtime.inside(target, x, y) then
                Runtime.Screen.pressedAction = target.action
                local succeeded
                if target.action == "program" then succeeded = Runtime.Machine.selectProgram(target.value, state)
                elseif target.action == "set_gauge" then succeeded = Runtime.commitGauge(state)
                elseif target.action == "gauge" then succeeded = Runtime.Machine.adjustGauge(target.value, state)
                elseif target.action == "auto" then succeeded = Runtime.Machine.autoGauge(state)
                elseif target.action == "save" then succeeded = Runtime.Machine.saveGauge(state)
                elseif target.action == "recall" then succeeded = Runtime.Machine.recallGauge(state)
                elseif target.action == "load" then succeeded = Runtime.openLoadMenu(state)
                else succeeded = Runtime.Machine.keypressed(target.key, state) end
                if succeeded and target.action ~= "program" then Runtime.formatGauge() end
                return succeeded
            end
        end
        Runtime.Screen.gaugeFocused = false
        return false
    end
end

return Component
