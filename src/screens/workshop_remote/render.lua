-- Remote console render dispatch and helper controls.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Screen.draw(state, pointerX, pointerY, assets)
        if Runtime.Screen.hostLayout and Runtime.Screen.resourceId=="truck" then
            Runtime.TruckScreen.draw(Runtime.Projection.copy(state),nil,assets,pointerX,pointerY,Runtime.Screen.view)
            love.graphics.setColor(0.8,0.9,0.9); love.graphics.printf(Runtime.Screen.status,82,526,790,"center")
            return
        end
        if Runtime.Screen.sharedPress then
            Runtime.Screen.sharedPress.draw(state,assets,pointerX,pointerY,Runtime.Screen.status)
            return
        end
        if Runtime.Screen.hostLayout and Runtime.Screen.resourceId=="vendor" then
            local projected=Runtime.Projection.copy(state); projected.vendorCategory=Runtime.Screen.view.categoryIndex
            projected.money=Runtime.Screen.view.cash or projected.money
            Runtime.VendorScreen.draw(projected,assets,pointerX,pointerY)
            love.graphics.setColor(0.8,0.9,0.9); love.graphics.printf(Runtime.Screen.status,82,590,790,"center")
            return
        elseif Runtime.Screen.hostLayout and Runtime.Screen.resourceId=="reception_customer" then
            local projected=Runtime.Projection.copy(state)
            if not projected.currentOffer then
                projected.currentOffer=Runtime.JobOfferScreen.fromNetwork(Runtime.Screen.view)
            end
            Runtime.JobOfferScreen.draw(projected,pointerX,pointerY,assets)
            return
        end
        if Runtime.Screen.sharedMachine then
            Runtime.Screen.sharedMachine.draw(state,assets,pointerX,pointerY,Runtime.Screen.status)
            return
        end
        if Runtime.Screen.sharedComputer then
            Runtime.Screen.guiState = Runtime.Projection.copy(state)
            Runtime.Screen.guiState.message = Runtime.Screen.status
            Runtime.Screen.sharedComputer.draw(Runtime.Screen.guiState, pointerX, pointerY, assets)
            return
        end
        if Runtime.Screen.resourceId == "work_phone" then
            Runtime.WorkPhoneScreen.draw(Runtime.Projection.copy(state), pointerX, pointerY, assets, Runtime.Screen.waiting)
            love.graphics.setColor(0.8, 0.9, 0.9)
            love.graphics.printf(Runtime.Screen.status, 68, 612, 812, "center")
            return
        end
        local titles = {
            reception_customer = { "REMOTE RECEPTION", "Review the job now; estimate it later from the office computer" },
            vendor = { "REMOTE SUPPLIER", "The host verifies cash, catalog availability, and each purchase" },
            truck = { "REMOTE TRUCK MANIFEST", "The host verifies every cargo move and owns the saved result" },
            office_computer = { "REMOTE OFFICE COMPUTER", "Shared shop records are live; transactions run on the host device" },
            skid_wrapper = { "REMOTE SKID WRAPPER", "The host device owns the machine cycle and saved pallet state" },
            cutter = { "REMOTE POLAR CUTTER", "The host device owns the blade cycle and saved paper state" },
            windmill = { "REMOTE HEIDELBERG WINDMILL", "The host device owns press safety, production, and saved paper state" },
        }
        local copy = titles[Runtime.Screen.resourceId] or { "REMOTE WORKSHOP", "Host-authoritative console" }
        Runtime.header(copy[1], copy[2], pointerX, pointerY, assets)
        if Runtime.Screen.resourceId == "reception_customer" then Runtime.drawCustomer(pointerX, pointerY)
        elseif Runtime.Screen.resourceId == "vendor" then Runtime.drawVendor(pointerX, pointerY)
        elseif Runtime.Screen.resourceId == "truck" then Runtime.drawTruck(pointerX, pointerY)
        elseif Runtime.Screen.resourceId == "office_computer" then Runtime.drawComputer(state, pointerX, pointerY)
        elseif Runtime.Screen.resourceId == "skid_wrapper" then Runtime.drawWrapper(state, pointerX, pointerY)
        elseif Runtime.Screen.resourceId == "cutter" then Runtime.drawCutter(state, pointerX, pointerY, assets)
        elseif Runtime.Screen.resourceId == "windmill" then Runtime.drawWindmill(state, pointerX, pointerY) end
        love.graphics.setColor(0.18, 0.21, 0.22)
        love.graphics.printf(Runtime.Screen.status, Runtime.PANEL.x + 24, Runtime.PANEL.y + Runtime.PANEL.height - 30,
            Runtime.PANEL.width - 48, "center")
    end

    function Runtime.Screen.backCenter() return Runtime.BACK.x + Runtime.BACK.width / 2, Runtime.BACK.y + Runtime.BACK.height / 2 end
    function Runtime.Screen.confirmCenter() return Runtime.CONFIRM.x + Runtime.CONFIRM.width / 2, Runtime.CONFIRM.y + Runtime.CONFIRM.height / 2 end
    function Runtime.Screen.quoteInputCenter()
        return Runtime.QUOTE_INPUT.x + Runtime.QUOTE_INPUT.width / 2, Runtime.QUOTE_INPUT.y + Runtime.QUOTE_INPUT.height / 2
    end
    function Runtime.Screen.rowCenter(index)
        local rect = Runtime.Screen.resourceId == "skid_wrapper"
            and Runtime.wrapperRowRect(index) or Runtime.rowRect(index)
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end


    function Runtime.Screen.wrapperTabCenter(tab)
        local rect = Runtime.WRAPPER_TABS[tab]
        if not rect then return nil end
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.Screen.wrapperServiceCenter(action)
        local rect
        if action == "begin_service" then
            rect = Runtime.WRAPPER_SERVICE_BEGIN
        elseif action == "cancel_service" then
            rect = Runtime.WRAPPER_SERVICE_CANCEL
        elseif action == "service_target" then
            rect = Runtime.wrapperServiceTarget(Runtime.Screen.view or {})
        elseif action == "service_miss" then
            rect = { x = Runtime.WRAPPER_SERVICE_WORK.x + 8, y = Runtime.WRAPPER_SERVICE_WORK.y + 8,
                width = 2, height = 2 }
        end
        if not rect then return nil end
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.Screen.update(dt)
        if Runtime.Screen.sharedPress then Runtime.Screen.sharedPress.screen.update(dt); return true end
        if Runtime.Screen.sharedMachine then Runtime.Screen.sharedMachine.screen.update(dt) end
        if Runtime.Screen.resourceId == "cutter" then
            Runtime.Screen.cutterPresentation:update(dt)
            return true
        end
        if Runtime.Screen.resourceId ~= "skid_wrapper" then return false end
        Runtime.Screen.wrapperClock = (Runtime.Screen.wrapperClock + math.max(0, tonumber(dt) or 0)) % 10000
        return true
    end

    function Runtime.Screen.requiredAssetPack()
        return ({ cutter = "cutter", skid_wrapper = "wrapper", windmill = "press" })[Runtime.Screen.resourceId]
    end

    function Runtime.Screen.wheelmoved(state, x, y)
        if Runtime.Screen.sharedComputer then return Runtime.Screen.sharedComputer.wheelmoved(Runtime.Projection.copy(state), x, y) end
        return false
    end

    function Runtime.Screen.vendorBuyCenter(index)
        local rect = Runtime.vendorBuyRect(index)
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.Screen.vendorDismissCenter()
        return Runtime.CONFIRM.x + Runtime.CONFIRM.width / 2, Runtime.CONFIRM.y + Runtime.CONFIRM.height / 2
    end

    function Runtime.Screen.truckMoveCenter(index)
        local rect = Runtime.vendorBuyRect(index)
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.Screen.truckPageCenter(direction)
        local rect = direction == "previous" and Runtime.TRUCK_PREVIOUS or Runtime.TRUCK_NEXT
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.Screen.truckCloseCenter()
        return Runtime.CONFIRM.x + Runtime.CONFIRM.width / 2, Runtime.CONFIRM.y + Runtime.CONFIRM.height / 2
    end

    function Runtime.Screen.cutterButtonCenter(action, value)
        local rect
        if action == "select_program" then
            rect = Runtime.CUTTER_PROGRAMS[tonumber(value) or 1]
        elseif action == "load_pallet" then
            rect = Runtime.cutterCandidateRect(tonumber(value) or 1)
        elseif action == "set_gauge" or action == "gauge_set" then
            rect = Runtime.CUTTER_CONTROLS.gauge_set
        elseif (Runtime.Screen.view and Runtime.Screen.view.loaded) ~= true and Runtime.CUTTER_UNLOADED_CONTROLS[action] then
            rect = Runtime.CUTTER_UNLOADED_CONTROLS[action]
        else
            rect = Runtime.CUTTER_CONTROLS[action]
        end
        if not rect then return nil end
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.Screen.windmillButtonCenter(action, value)
        local rect
        if action == "load_pallet" then
            local index = tonumber(value)
            if not index and value ~= nil then
                for candidateIndex, candidate in ipairs(Runtime.windmillCandidates()) do
                    if candidate.palletId == value then index = candidateIndex; break end
                end
            end
            rect = Runtime.windmillCandidateRect(index or 1)
        elseif action == "start_run" or action == "stop_run" or action == "run" then
            rect = Runtime.WINDMILL_RUN_CONTROLS.run
        elseif action == "begin_setup" then
            local index = tonumber(value)
            if not index and value ~= nil then
                for taskIndex, task in ipairs(Runtime.WINDMILL_SETUP_TASKS) do
                    if task == value then index = taskIndex; break end
                end
            end
            rect = Runtime.windmillSetupTaskRect(index or 1)
        elseif action == "setup_action" then
            local task = Runtime.Screen.view and Runtime.Screen.view.setupTask
            if not task then return nil end
            local controls = Runtime.PressSetupGames.controls(task)
            local index = tonumber(value)
            if not index and value ~= nil then
                for controlIndex, control in ipairs(controls) do
                    if control[1] == value then index = controlIndex; break end
                end
            end
            if #controls > 0 then rect = Runtime.windmillSetupControlRect(task, index or 1) end
        elseif action == "cancel_setup" then
            rect = Runtime.WINDMILL_SETUP_CANCEL
        elseif action == "select_job" or action == "select_plate_job" then
            rect = Runtime.windmillPlateJobRect(tonumber(value) or 1)
        elseif action == "select_plate" then
            rect = Runtime.windmillPlateRect(tonumber(value) or 1)
        else
            rect = Runtime.WINDMILL_RUN_CONTROLS[action]
                or Runtime.WINDMILL_PLATE_CONTROLS[action]
                or Runtime.WINDMILL_SERVICE_CONTROLS[action]
        end
        if not rect then return nil end
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.Screen.windmillTabCenter(tab)
        local rect = Runtime.WINDMILL_TABS[tab]
        if not rect then return nil end
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.Screen.buttonCenter(action, value)
        if Runtime.Screen.resourceId == "windmill" then
            return Runtime.Screen.windmillButtonCenter(action, value)
        end
        return Runtime.Screen.cutterButtonCenter(action, value)
    end

    function Runtime.Screen.cutterGaugeInputCenter()
        return Runtime.CUTTER_GAUGE_INPUT.x + Runtime.CUTTER_GAUGE_INPUT.width / 2,
            Runtime.CUTTER_GAUGE_INPUT.y + Runtime.CUTTER_GAUGE_INPUT.height / 2
    end

    function Runtime.Screen.cutterCandidateCenter(index)
        local rect = Runtime.cutterCandidateRect(index)
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.Screen.cutterServiceCenter(action, value)
        local rect
        if action == "tab" or action == "production" then
            rect = Runtime.CUTTER_SERVICE_NAV
        elseif action == "begin_lubrication" then
            rect = Runtime.CUTTER_SERVICE_CONTROLS.lubrication
        elseif action == "begin_blade" then
            rect = Runtime.CUTTER_SERVICE_CONTROLS.blade
        elseif action == "book_blade_technician" then
            rect = Runtime.CUTTER_SERVICE_CONTROLS.technician
        elseif action == "set_weekly_technician" then
            rect = Runtime.CUTTER_SERVICE_CONTROLS.weekly
        elseif action == "service_advance" then
            rect = Runtime.CUTTER_SERVICE_CONTROLS.advance
        elseif action == "service_view" then
            rect = Runtime.cutterServiceViewRect(tonumber(value) or 1)
        elseif action == "service_tool" then
            rect = Runtime.cutterServiceToolRect(tonumber(value) or 1)
        elseif action == "service_point" then
            rect = Runtime.cutterServiceItemRect(tonumber(value) or 1)
        elseif action == "service_pump" then
            rect = Runtime.CUTTER_SERVICE_CONTROLS.pump
        elseif action == "service_gear" then
            rect = Runtime.CUTTER_SERVICE_CONTROLS.gear
        elseif action == "finish_lubrication" then
            rect = Runtime.CUTTER_SERVICE_CONTROLS.finish
        elseif action == "cancel_service" then
            rect = Runtime.CUTTER_SERVICE_CONTROLS.cancel
        elseif action == "remove_blade_bolt" then
            rect = Runtime.cutterBladeBoltRect(tonumber(value) or 1)
        elseif action == "lift_blade" or action == "sleeve_blade" then
            rect = Runtime.CUTTER_SERVICE_CONTROLS.bladeAction
        end
        if not rect then return nil end
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end
end

return Component
