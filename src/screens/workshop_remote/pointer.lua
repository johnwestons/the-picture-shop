-- Remote console pointer action dispatch.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Screen.mousepressed(state, x, y, button, sendCommand)
        if Runtime.Screen.hostLayout and Runtime.Screen.resourceId=="truck" then
            if button~=1 then return false end
            local action,args=Runtime.TruckScreen.remoteIntent(Runtime.Screen.view,x,y)
            if action=="close" then return Runtime.Screen.canClose() and {action="close"} or true end
            return action and Runtime.request(sendCommand,action,args) or false
        end
        if Runtime.Screen.sharedPress then
            Runtime.Screen.sendCommand=sendCommand
            local result=Runtime.Screen.sharedPress.mousepressed(state,x,y,button)
            if type(result)=="table" and result.action=="exit" then return Runtime.Screen.canClose() and {action="close"} or true end
            return result
        end
        if Runtime.Screen.hostLayout and Runtime.Screen.resourceId=="vendor" then
            if button~=1 then return false end
            local projected=Runtime.Projection.copy(state); projected.vendorCategory=Runtime.Screen.view.categoryIndex
            local action,args=Runtime.VendorScreen.remoteIntent(projected,x,y)
            if action=="close" then return Runtime.Screen.canClose() and {action="close"} or true end
            return action and Runtime.request(sendCommand,action,args) or false
        elseif Runtime.Screen.hostLayout and Runtime.Screen.resourceId=="reception_customer" then
            if button~=1 then return false end
            local action=Runtime.JobOfferScreen.hitTest(x,y)
            if action=="back" then return Runtime.Screen.canClose() and {action="close"} or true end
            return action=="accept" and Runtime.request(sendCommand,"request_details",{}) or false
        end
        if Runtime.Screen.sharedMachine then
            Runtime.Screen.sendCommand=sendCommand
            local result=Runtime.Screen.sharedMachine.mousepressed(state,x,y,button)
            if not Runtime.Screen.waiting and not Runtime.Screen.safetyWaiting and Runtime.Screen.sharedMachine.feedback then Runtime.Screen.status=Runtime.Screen.sharedMachine.feedback end
            if type(result)=="table" and result.action=="exit" then return Runtime.Screen.canClose() and {action="close"} or true end
            return result
        end
        if Runtime.Screen.sharedComputer then
            if Runtime.Screen.waiting then return true end
            Runtime.Screen.sendCommand, Runtime.Screen.guiState = sendCommand, Runtime.Projection.copy(state)
            local oldMessage=Runtime.Screen.guiState.message
            local result = Runtime.Screen.sharedComputer.mousepressed(Runtime.Screen.guiState, x, y, button)
            if not Runtime.Screen.waiting and Runtime.Screen.guiState.message~=oldMessage then Runtime.Screen.status=Runtime.Screen.guiState.message end
            if result and result.action == "close" then return Runtime.Screen.canClose() and { action = "close" } or true end
            if result and result.action == "pickup_ready" then return Runtime.request(sendCommand, "request_pickup", { jobId = result.job.id }) end
            return result
        end
        if Runtime.Screen.resourceId == "work_phone" then
            if button ~= 1 then return false end
            local action, args = Runtime.WorkPhoneScreen.remoteIntent(state, x, y)
            if action == "close" then return Runtime.Screen.canClose() and { action = "close" } or true end
            return action and Runtime.request(sendCommand, action, args) or false
        end
        if button ~= 1 or not Runtime.Screen:isOpen() then return false end
        if Runtime.contains(Runtime.BACK, x, y) then
            if Runtime.Screen.canClose() then return { action = "close" } end
            if Runtime.Screen.resourceId == "windmill" and Runtime.Screen.view
                and Runtime.Screen.view.status == "production"
            then
                Runtime.Screen.status = "Stop the production run before closing the remote Windmill console."
            end
            return true
        end
        if Runtime.Screen.resourceId == "reception_customer" then
            Runtime.Screen.quoteFocused = false
            if Runtime.contains(Runtime.CONFIRM, x, y) then
                Runtime.request(sendCommand, "request_details", {})
                return true
            end
        elseif Runtime.Screen.resourceId == "office_computer" then
            local jobs = Runtime.activeJobs(state)
            for index, job in ipairs(jobs) do
                if Runtime.contains(Runtime.rowRect(index), x, y) then
                    Runtime.Screen.selectedJobId = job.id
                    Runtime.Screen.status = Runtime.JobService.completionReady(job)
                        and "Ready to request customer pickup."
                        or "This job is visible, but every pallet must be finished and wrapped first."
                    return true
                end
            end
            if Runtime.contains(Runtime.CONFIRM, x, y) and Runtime.Screen.selectedJobId then
                return Runtime.request(sendCommand, "request_pickup", { jobId = Runtime.Screen.selectedJobId })
            end
        elseif Runtime.Screen.resourceId == "vendor" then
            for index, item in ipairs(Runtime.vendorRows()) do
                if Runtime.contains(Runtime.vendorBuyRect(index), x, y) then
                    local affordable = item.available == true
                        and (tonumber(Runtime.Screen.view and Runtime.Screen.view.cash) or 0)
                            >= (tonumber(item.price) or math.huge)
                    if not affordable then
                        Runtime.Screen.status = item.available ~= true
                            and tostring(item.detail or "That item is unavailable.")
                            or "The host shop does not have enough cash for that purchase."
                        return true
                    end
                    local action = Runtime.Screen.view.kind == "machines"
                        and "purchase_machine" or "purchase_stock"
                    return Runtime.request(sendCommand, action, { itemIndex = item.itemIndex })
                end
            end
            if Runtime.contains(Runtime.CONFIRM, x, y) then
                return Runtime.request(sendCommand, "dismiss", {})
            end
        elseif Runtime.Screen.resourceId == "truck" then
            local view = Runtime.Screen.view or {}
            for index, item in ipairs(view.items or {}) do
                if Runtime.contains(Runtime.vendorBuyRect(index), x, y) then
                    if item.available ~= true then
                        Runtime.Screen.status = "That manifest row was already handled."
                        return true
                    end
                    return Runtime.request(sendCommand, "move_item", { itemIndex = item.itemIndex })
                end
            end
            if Runtime.contains(Runtime.TRUCK_PREVIOUS, x, y) then
                if (tonumber(view.page) or 1) > 1 then
                    return Runtime.request(sendCommand, "page_previous", {})
                end
                return true
            elseif Runtime.contains(Runtime.TRUCK_NEXT, x, y) then
                if (tonumber(view.page) or 1) < (tonumber(view.pageCount) or 1) then
                    return Runtime.request(sendCommand, "page_next", {})
                end
                return true
            elseif Runtime.contains(Runtime.CONFIRM, x, y) then
                if view.canClose ~= true then
                    Runtime.Screen.status = "Finish every available manifest row before releasing the truck."
                    return true
                end
                return Runtime.request(sendCommand, "close_truck", {})
            end
        elseif Runtime.Screen.resourceId == "skid_wrapper" then
            local view = Runtime.Screen.view or {}
            local serviceActive = tostring(view.serviceStep or "idle") ~= "idle"
            if Runtime.contains(Runtime.WRAPPER_TABS.production, x, y) then
                if not serviceActive then Runtime.Screen.wrapperTab = "production" end
                return true
            elseif Runtime.contains(Runtime.WRAPPER_TABS.service, x, y) then
                Runtime.Screen.wrapperTab = "service"
                return true
            end
            if Runtime.Screen.wrapperTab == "service" then
                if serviceActive then
                    if Runtime.contains(Runtime.WRAPPER_SERVICE_CANCEL, x, y) then
                        return not Runtime.Screen.waiting
                            and Runtime.request(sendCommand, "cancel_service", {}) or true
                    end
                    local target = Runtime.wrapperServiceTarget(view)
                    if target and Runtime.contains(target, x, y) then
                        return not Runtime.Screen.waiting and Runtime.request(sendCommand, "service_target",
                            { itemIndex = tonumber(view.servicePhase) }) or true
                    elseif Runtime.contains(Runtime.WRAPPER_SERVICE_WORK, x, y) then
                        return not Runtime.Screen.waiting and Runtime.request(sendCommand, "service_miss", {}) or true
                    end
                elseif Runtime.contains(Runtime.WRAPPER_SERVICE_BEGIN, x, y) then
                    if not Runtime.wrapperServiceBeginEnabled(state) then
                        Runtime.Screen.status = #Runtime.wrapperRows(state) > 0
                            and "Move every eligible pallet away from the turntable first."
                            or "The host requires an idle wrapper and one maintenance kit."
                        return true
                    end
                    return Runtime.request(sendCommand, "begin_service", {})
                end
                return true
            end
            local rows = Runtime.wrapperRows(state)
            for index, item in ipairs(rows) do
                if Runtime.contains(Runtime.wrapperRowRect(index), x, y) then
                    Runtime.Screen.selectedPalletId = item.palletId
                    return Runtime.request(sendCommand, "select_pallet", { palletId = item.palletId })
                end
            end
            if Runtime.contains(Runtime.CONFIRM, x, y) then
                local selected = Runtime.selectedWrapperPallet(rows)
                if not Runtime.Screen.wrapperStartEnabled(state) then
                    if Runtime.Screen.waiting or Runtime.Wrapper.step == "wrapping" then return true end
                    Runtime.Screen.status = #rows == 0
                        and "Park a finished, unwrapped pallet beside the skid wrapper first."
                        or "Select a nearby finished pallet first."
                    return true
                end
                return Runtime.request(sendCommand, "start_cycle", { palletId = selected.palletId })
            end
        elseif Runtime.Screen.resourceId == "windmill" then
            return Runtime.windmillMousepressed(state, x, y, sendCommand)
        elseif Runtime.Screen.resourceId == "cutter" then
            local view = Runtime.Screen.view or {}
            local serviceStep = tostring(view.serviceStep or "idle")
            if Runtime.Screen.cutterTab == "service" then
                if Runtime.contains(Runtime.CUTTER_SERVICE_NAV, x, y) then
                    if serviceStep ~= "idle" then
                        return Runtime.cutterServiceButtonEnabled("cancel_service", state)
                            and Runtime.request(sendCommand, "cancel_service", {}) or true
                    end
                    Runtime.Screen.cutterTab = "production"
                    return true
                elseif serviceStep == "idle" then
                    if Runtime.contains(Runtime.CUTTER_SERVICE_CONTROLS.lubrication, x, y) then
                        return Runtime.cutterServiceButtonEnabled("begin_lubrication", state)
                            and Runtime.request(sendCommand, "begin_lubrication", {}) or true
                    elseif Runtime.contains(Runtime.CUTTER_SERVICE_CONTROLS.blade, x, y) then
                        return Runtime.cutterServiceButtonEnabled("begin_blade", state)
                            and Runtime.request(sendCommand, "begin_blade", {}) or true
                    elseif Runtime.contains(Runtime.CUTTER_SERVICE_CONTROLS.technician, x, y) then
                        return Runtime.cutterServiceButtonEnabled("book_blade_technician", state)
                            and Runtime.request(sendCommand, "book_blade_technician", {}) or true
                    elseif Runtime.contains(Runtime.CUTTER_SERVICE_CONTROLS.weekly, x, y) then
                        return Runtime.cutterServiceButtonEnabled("set_weekly_technician", state)
                            and Runtime.request(sendCommand, "set_weekly_technician",
                                { enabled = Runtime.cutterMaintenanceStatus(state).weeklyTechnician ~= true }) or true
                    end
                elseif serviceStep == "lockout_disconnect" or serviceStep == "lockout_key"
                    or serviceStep == "lockout_tag" or serviceStep == "prep_cartridge"
                    or serviceStep == "prep_prime"
                then
                    if Runtime.contains(Runtime.CUTTER_SERVICE_CONTROLS.advance, x, y) then
                        return Runtime.cutterServiceButtonEnabled("service_advance", state)
                            and Runtime.request(sendCommand, "service_advance", {}) or true
                    end
                elseif serviceStep == "lubricate" then
                    for index = 1, #Runtime.CUTTER_SERVICE_VIEWS do
                        if Runtime.contains(Runtime.cutterServiceViewRect(index), x, y) then
                            if index == 5 and view.centralInstalled ~= true then return true end
                            return Runtime.cutterServiceButtonEnabled("service_view", state)
                                and Runtime.request(sendCommand, "service_view", { itemIndex = index }) or true
                        end
                    end
                    for index = 1, #Runtime.CUTTER_SERVICE_TOOLS do
                        if Runtime.contains(Runtime.cutterServiceToolRect(index), x, y) then
                            return Runtime.cutterServiceButtonEnabled("service_tool", state)
                                and Runtime.request(sendCommand, "service_tool", { itemIndex = index }) or true
                        end
                    end
                    for index, item in ipairs(view.serviceItems or {}) do
                        if Runtime.contains(Runtime.cutterServiceItemRect(index), x, y) then
                            return Runtime.cutterServiceButtonEnabled("service_point", state)
                                and Runtime.request(sendCommand, "service_point",
                                    { itemIndex = item.itemIndex }) or true
                        end
                    end
                    if Runtime.contains(Runtime.CUTTER_SERVICE_CONTROLS.pump, x, y) then
                        return Runtime.cutterServiceButtonEnabled("service_pump", state)
                            and Runtime.request(sendCommand, "service_pump", {}) or true
                    elseif Runtime.contains(Runtime.CUTTER_SERVICE_CONTROLS.gear, x, y) then
                        return Runtime.cutterServiceButtonEnabled("service_gear", state)
                            and Runtime.request(sendCommand, "service_gear", {}) or true
                    elseif Runtime.contains(Runtime.CUTTER_SERVICE_CONTROLS.finish, x, y) then
                        return Runtime.cutterServiceButtonEnabled("finish_lubrication", state)
                            and Runtime.request(sendCommand, "finish_lubrication", {}) or true
                    end
                elseif serviceStep == "blade_bolts" then
                    local nextBolt = (tonumber(view.bladeBoltsDone) or 0) + 1
                    for index = 1, 4 do
                        if Runtime.contains(Runtime.cutterBladeBoltRect(index), x, y) then
                            return index == nextBolt
                                and Runtime.cutterServiceButtonEnabled("remove_blade_bolt", state)
                                and Runtime.request(sendCommand, "remove_blade_bolt", { itemIndex = index }) or true
                        end
                    end
                elseif serviceStep == "blade_lift"
                    and Runtime.contains(Runtime.CUTTER_SERVICE_CONTROLS.bladeAction, x, y)
                then
                    return Runtime.cutterServiceButtonEnabled("lift_blade", state)
                        and Runtime.request(sendCommand, "lift_blade", {}) or true
                elseif serviceStep == "blade_sleeve"
                    and Runtime.contains(Runtime.CUTTER_SERVICE_CONTROLS.bladeAction, x, y)
                then
                    return Runtime.cutterServiceButtonEnabled("sleeve_blade", state)
                        and Runtime.request(sendCommand, "sleeve_blade", {}) or true
                end
                if serviceStep ~= "idle" and Runtime.contains(Runtime.CUTTER_SERVICE_CONTROLS.cancel, x, y) then
                    return Runtime.cutterServiceButtonEnabled("cancel_service", state)
                        and Runtime.request(sendCommand, "cancel_service", {}) or true
                end
                return true
            end
            if view.loaded ~= true and Runtime.contains(Runtime.CUTTER_SERVICE_NAV, x, y) then
                if view.loaded == true or view.step ~= "idle" then
                    Runtime.Screen.status = "Unload the cutter and return it to idle before maintenance."
                    return true
                end
                Runtime.Screen.cutterTab = "service"
                Runtime.Screen.gaugeFocused = false
                return true
            end
            if view.loaded ~= true then
                for index, candidate in ipairs(Runtime.cutterCandidates()) do
                    if Runtime.contains(Runtime.cutterCandidateRect(index), x, y) then
                        Runtime.Screen.gaugeFocused = false
                        if Runtime.cutterButtonEnabled("load_pallet") then
                            return Runtime.request(sendCommand, "load_pallet", { palletId = candidate.palletId })
                        end
                        return true
                    end
                end
                if Runtime.contains(Runtime.CUTTER_UNLOADED_CONTROLS.load_stock, x, y) then
                    Runtime.Screen.gaugeFocused = false
                    if not Runtime.cutterButtonEnabled("load_stock") then return true end
                    if (tonumber(view.genericSheets) or 0) <= 0 then
                        Runtime.Screen.status = "No generic production stock is available on the host device."
                        return true
                    end
                    return Runtime.request(sendCommand, "load_stock", {})
                end
                if Runtime.contains(Runtime.CUTTER_UNLOADED_CONTROLS.set_barrier, x, y) then
                    return Runtime.cutterButtonEnabled("set_barrier")
                        and Runtime.request(sendCommand, "set_barrier", { barrierClear = view.barrierClear ~= true }) or true
                elseif Runtime.contains(Runtime.CUTTER_UNLOADED_CONTROLS.reset_safety, x, y) then
                    return Runtime.cutterButtonEnabled("reset_safety")
                        and Runtime.request(sendCommand, "reset_safety", {}) or true
                elseif Runtime.contains(Runtime.CUTTER_UNLOADED_CONTROLS.run_next_lift, x, y) then
                    return Runtime.cutterButtonEnabled("run_next_lift")
                        and Runtime.request(sendCommand, "run_next_lift", {}) or true
                elseif Runtime.contains(Runtime.CUTTER_UNLOADED_CONTROLS.emergency_stop, x, y) then
                    return Runtime.cutterButtonEnabled("emergency_stop")
                        and Runtime.request(sendCommand, "emergency_stop", {}) or true
                end
                return false
            end
            if Runtime.contains(Runtime.CUTTER_GAUGE_INPUT, x, y) then
                Runtime.Screen.gaugeFocused, Runtime.Screen.gaugeReplaceOnType = true, true
                return true
            end
            Runtime.Screen.gaugeFocused = false
            for index, rect in ipairs(Runtime.CUTTER_PROGRAMS) do
                if Runtime.contains(rect, x, y) then
                    if Runtime.cutterButtonEnabled("select_program") then
                        return Runtime.request(sendCommand, "select_program", { programIndex = index })
                    end
                    return true
                end
            end
            if Runtime.contains(Runtime.CUTTER_CONTROLS.gauge_set, x, y) then
                return Runtime.cutterButtonEnabled("gauge_set") and Runtime.commitCutterGauge(sendCommand) or true
            elseif Runtime.contains(Runtime.CUTTER_CONTROLS.auto_gauge, x, y) then
                return Runtime.cutterButtonEnabled("auto_gauge") and Runtime.request(sendCommand, "auto_gauge", {}) or true
            elseif Runtime.contains(Runtime.CUTTER_CONTROLS.save_gauge, x, y) then
                return Runtime.cutterButtonEnabled("save_gauge") and Runtime.request(sendCommand, "save_gauge", {}) or true
            elseif Runtime.contains(Runtime.CUTTER_CONTROLS.recall_gauge, x, y) then
                return Runtime.cutterButtonEnabled("recall_gauge") and Runtime.request(sendCommand, "recall_gauge", {}) or true
            elseif Runtime.contains(Runtime.CUTTER_CONTROLS.rotate_paper, x, y) then
                return Runtime.cutterButtonEnabled("rotate_paper") and Runtime.request(sendCommand, "rotate_paper", {}) or true
            elseif Runtime.contains(Runtime.CUTTER_CONTROLS.position_paper, x, y) then
                return Runtime.cutterButtonEnabled("position_paper") and Runtime.request(sendCommand, "position_paper", {}) or true
            elseif Runtime.contains(Runtime.CUTTER_CONTROLS.set_clamp, x, y) then
                return Runtime.cutterButtonEnabled("set_clamp")
                    and Runtime.request(sendCommand, "set_clamp", { clamp = view.clamp ~= true }) or true
            elseif Runtime.contains(Runtime.CUTTER_CONTROLS.set_barrier, x, y) then
                return Runtime.cutterButtonEnabled("set_barrier")
                    and Runtime.request(sendCommand, "set_barrier", { barrierClear = view.barrierClear ~= true }) or true
            elseif Runtime.contains(Runtime.CUTTER_CONTROLS.reset_safety, x, y) then
                return Runtime.cutterButtonEnabled("reset_safety") and Runtime.request(sendCommand, "reset_safety", {}) or true
            elseif Runtime.contains(Runtime.CUTTER_CONTROLS.emergency_stop, x, y) then
                return Runtime.cutterButtonEnabled("emergency_stop") and Runtime.request(sendCommand, "emergency_stop", {}) or true
            elseif Runtime.contains(Runtime.CUTTER_CONTROLS.return_to_pallet, x, y) then
                return Runtime.cutterButtonEnabled("return_to_pallet")
                    and Runtime.request(sendCommand, "return_to_pallet", {}) or true
            elseif Runtime.contains(Runtime.CUTTER_CONTROLS.run_next_lift, x, y) then
                return Runtime.cutterButtonEnabled("run_next_lift")
                    and Runtime.request(sendCommand, "run_next_lift", {}) or true
            elseif Runtime.contains(Runtime.CUTTER_CONTROLS.cut_left, x, y) then
                return Runtime.handleCutterCut(sendCommand)
            elseif Runtime.contains(Runtime.CUTTER_CONTROLS.cut_right, x, y) then
                return Runtime.handleCutterCut(sendCommand)
            end
        end
        return false
    end
end

return Component
