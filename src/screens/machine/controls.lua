-- Keyboard, gauge input, and console control positions.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Screen.keypressed(state, key)
        if Runtime.Screen.helpOpen then
            if key == "escape" then Runtime.Screen.helpOpen = false
            elseif key == "left" then Runtime.Screen.helpStep = math.max(1, Runtime.Screen.helpStep - 1)
            elseif key == "right" then Runtime.Screen.helpStep = math.min(#Runtime.cutterHelp, Runtime.Screen.helpStep + 1) end
            return true
        end
        if Runtime.Screen.maintenanceView then
            if key == "escape" then
                if Runtime.dependencies.remoteCommand and (Runtime.Screen.maintenanceView=="wrapper_task"
                    or Runtime.Screen.maintenanceView=="oil" or Runtime.Screen.maintenanceView=="blade") then
                    return Runtime.dependencies.remoteCommand("cancel_service",{})
                end
                if Runtime.Screen.maintenanceView == "wrapper_hub" then
                    Runtime.Screen.maintenanceView = nil
                elseif Runtime.Screen.maintenanceView == "wrapper_task" then
                    Runtime.Screen.maintenanceView, Runtime.Screen.wrapperSession = "wrapper_hub", nil
                elseif Runtime.Screen.maintenanceView == "hub" then Runtime.Screen.maintenanceView = nil
                else Runtime.Screen.maintenanceView, Runtime.Screen.oilSession, Runtime.Screen.bladeStage = "hub", nil, nil end
                return true
            end
            return true
        end
        if Runtime.Screen.loadMenu then
            if key == "escape" then Runtime.Screen.loadMenu = nil; return true end
            if key == "up" then
                Runtime.Screen.loadMenu.selected = math.max(1, Runtime.Screen.loadMenu.selected - 1); return true
            elseif key == "down" then
                Runtime.Screen.loadMenu.selected = math.min(#Runtime.Screen.loadMenu.options, Runtime.Screen.loadMenu.selected + 1); return true
            elseif key == "return" or key == "kpenter" then
                return Runtime.loadSelected(state)
            end
            local number = tonumber(key)
            if number and number >= 1 and number <= Runtime.loadMenuPageSize then
                local pageStart = math.floor((Runtime.Screen.loadMenu.selected - 1) / Runtime.loadMenuPageSize)
                    * Runtime.loadMenuPageSize + 1
                local optionIndex = pageStart + number - 1
                if optionIndex <= #Runtime.Screen.loadMenu.options then return Runtime.loadSelected(state, optionIndex) end
            end
            return true
        end
        if key == "l" then return Runtime.openLoadMenu(state) end
        if not Runtime.Screen.gaugeFocused then return false end
        if key == "backspace" then
            if Runtime.Screen.gaugeReplaceOnType then
                Runtime.Screen.gaugeText = ""
                Runtime.Screen.gaugeReplaceOnType = false
                return true
            end
            local byteOffset = Runtime.utf8.offset(Runtime.Screen.gaugeText, -1)
            if byteOffset then Runtime.Screen.gaugeText = string.sub(Runtime.Screen.gaugeText, 1, byteOffset - 1) end
            return true
        elseif key == "return" or key == "kpenter" then
            return Runtime.commitGauge(state)
        end
        return false
    end

    function Runtime.Screen.update(dt)
        if Runtime.dependencies.remoteCommand then
            for _, session in ipairs({ Runtime.Screen.oilSession or false, Runtime.Screen.wrapperSession or false }) do
                if session then session.animationClock = (session.animationClock or 0) + dt end
            end
            return false
        end
        if Runtime.Screen.maintenanceView == "wrapper_task" and Runtime.Screen.wrapperSession then
            return Runtime.MachineMaintenance.update(Runtime.Screen.wrapperSession, dt)
        elseif Runtime.Screen.maintenanceView == "oil" and Runtime.Screen.oilSession then
            return Runtime.MachineMaintenance.update(Runtime.Screen.oilSession, dt)
        end
        return false
    end

    function Runtime.Screen.textinput(state, text)
        if Runtime.Screen.loadMenu then return false end
        if not Runtime.Screen.gaugeFocused then return false end
        local changed = false
        for character in text:gmatch(".") do
            if character:match("%d") and #Runtime.Screen.gaugeText < 7 then
                if Runtime.Screen.gaugeReplaceOnType then
                    Runtime.Screen.gaugeText = ""
                    Runtime.Screen.gaugeReplaceOnType = false
                end
                Runtime.Screen.gaugeText = Runtime.Screen.gaugeText .. character
                changed = true
            elseif character == "." and not Runtime.Screen.gaugeText:find(".", 1, true) then
                if Runtime.Screen.gaugeReplaceOnType then
                    Runtime.Screen.gaugeText = "0"
                    Runtime.Screen.gaugeReplaceOnType = false
                end
                Runtime.Screen.gaugeText = Runtime.Screen.gaugeText .. character
                changed = true
            end
        end
        return changed
    end

    function Runtime.Screen.wantsTextInput()
        return Runtime.Screen.gaugeFocused and not Runtime.Screen.loadMenu
    end

    function Runtime.Screen.gaugeInputCenter()
        return Runtime.gaugeInput.x + Runtime.gaugeInput.width / 2, Runtime.gaugeInput.y + Runtime.gaugeInput.height / 2
    end

    function Runtime.Screen.mousereleased(state, x, y, button)
        if button ~= 1 then return false end
        local action = Runtime.Screen.pressedAction
        Runtime.Screen.pressedAction = nil
        -- Offline mouse cut controls stay latched for the same 0.30-second
        -- simultaneity window used by the physical keys. Multiplayer input starts
        -- the cut during mousepressed, so release only clears the visual action.
        if action == "cut_left" or action == "cut_right" then return true end
        return action ~= nil
    end

    function Runtime.Screen.buttonCenter(action, value)
        Runtime.layout()
        for _, button in ipairs(Runtime.buttons) do
            if button.action == action and (value == nil or button.value == value) then
                return button.x + button.width / 2, button.y + button.height / 2
            end
        end
    end

    function Runtime.Screen.exitCenter()
        return Runtime.exitButton.x + Runtime.exitButton.width / 2, Runtime.exitButton.y + Runtime.exitButton.height / 2
    end

    function Runtime.Screen.maintenanceCenter()
        return Runtime.maintenanceButton.x + Runtime.maintenanceButton.width / 2,
            Runtime.maintenanceButton.y + Runtime.maintenanceButton.height / 2
    end

    function Runtime.Screen.wrapperMaintenanceCenter()
        return Runtime.wrapperMaintenanceButton.x + Runtime.wrapperMaintenanceButton.width / 2,
            Runtime.wrapperMaintenanceButton.y + Runtime.wrapperMaintenanceButton.height / 2
    end

    function Runtime.Screen.wrapperServiceCenter()
        return Runtime.wrapperServiceButton.x + Runtime.wrapperServiceButton.width / 2,
            Runtime.wrapperServiceButton.y + Runtime.wrapperServiceButton.height / 2
    end

    function Runtime.Screen.wrapperPalletCenter(index)
        index = math.max(1, math.min(Runtime.wrapperPalletList.maxRows, index or 1))
        return Runtime.wrapperPalletList.x + Runtime.wrapperPalletList.width / 2,
            Runtime.wrapperPalletList.y + (index - 0.5) * Runtime.wrapperPalletList.rowHeight - 3
    end

    function Runtime.Screen.wrapperTaskTargetCenter()
        return Runtime.MachineMaintenance.wrapperTarget(Runtime.Screen.wrapperSession)
    end

    function Runtime.Screen.maintenanceTaskCenter(task)
        local rect = task == "oil" and Runtime.oilServiceButton
            or task == "blade" and Runtime.bladeServiceButton
            or task == "technician" and Runtime.technicianButton
            or task == "weekly" and Runtime.weeklyButton
            or Runtime.maintenanceBack
        return rect.x + rect.width / 2, rect.y + rect.height / 2
    end

    function Runtime.Screen.oilingTargetCenter(index)
        local point = Runtime.Screen.oilSession and Runtime.Screen.oilSession.points[index]
        return point and point.x, point and point.y
    end

    function Runtime.Screen.lubricationLockoutCenter(action)
        local rect = Runtime.lockoutButtons[action]; return rect.x + rect.width / 2, rect.y + rect.height / 2
    end
    function Runtime.Screen.lubricationPrepCenter(action)
        local rect = Runtime.prepButtons[action]; return rect.x + rect.width / 2, rect.y + rect.height / 2
    end
    function Runtime.Screen.lubricationViewCenter(view)
        for index, name in ipairs(Runtime.lubricationViews) do if name == view then return 94.5 + (index - 1) * 113, 129 end end
    end
    function Runtime.Screen.lubricationToolCenter(tool)
        for index, name in ipairs(Runtime.lubricationTools) do if name == tool then return 767, 195.5 + (index - 1) * 48 end end
    end
    function Runtime.Screen.lubricationPointCenter(pointId)
        local point = Runtime.MachineMaintenance.lubricationPoint(Runtime.Screen.oilSession, pointId)
        return point and point.x, point and point.y
    end
    function Runtime.Screen.lubricationPumpCenter() return Runtime.pumpButton.x + Runtime.pumpButton.width / 2, Runtime.pumpButton.y + Runtime.pumpButton.height / 2 end
    function Runtime.Screen.lubricationFinishCenter() return Runtime.finishLubricationButton.x + Runtime.finishLubricationButton.width / 2,
        Runtime.finishLubricationButton.y + Runtime.finishLubricationButton.height / 2 end
    function Runtime.Screen.lubricationGearSightCenter() return 490, 340 end

    function Runtime.Screen.bladeBoltCenter(index)
        local position = Runtime.bladeBoltPositions()[index]
        return position[1], position[2]
    end

    function Runtime.Screen.bladeCenter() return 480, 311 end
    function Runtime.Screen.bladeSleeveCenter() return 480, 475 end

    function Runtime.Screen.hasModal() return Runtime.Screen.loadMenu ~= nil or Runtime.Screen.maintenanceView ~= nil or Runtime.Screen.helpOpen end

    function Runtime.Screen.loadMenuOptions()
        return Runtime.Screen.loadMenu and Runtime.Screen.loadMenu.options or {}
    end

    function Runtime.Screen.loadMenuRowCenter(index)
        local displayIndex = ((index or 1) - 1) % Runtime.loadMenuPageSize + 1
        return Runtime.loadMenuRect.x + Runtime.loadMenuRect.width / 2,
            Runtime.loadMenuRect.y + 68 + (displayIndex - 0.5) * Runtime.loadMenuRect.rowHeight
    end

    function Runtime.Screen.artworkRotation(paper)
        return math.rad(((paper and paper.orientation) or 0) % 360)
    end

    -- The same service hit targets feed bounded intent on guests. No local service
    -- task, bolt, kit or condition is advanced before the host confirms it.
end

return Component
