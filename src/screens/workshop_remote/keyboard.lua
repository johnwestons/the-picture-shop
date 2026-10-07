-- Remote command requests, keyboard, and text input.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.urgentWorkshopSafety(action, args)
        if action == "emergency_stop" then
            return Runtime.Screen.resourceId == "cutter" or Runtime.Screen.resourceId == "windmill"
        end
        return Runtime.Screen.resourceId == "cutter" and action == "set_barrier"
            and type(args) == "table" and args.barrierClear == false
    end

    Runtime.request = function(sendCommand, action, args)
        args = args or {}
        local urgentSafety = Runtime.urgentWorkshopSafety(action, args)
        if Runtime.Screen.safetyWaiting or (Runtime.Screen.waiting and not urgentSafety) then return false end
        if type(sendCommand) ~= "function" then
            Runtime.Screen.status = "The remote console is not connected to the host command channel."
            return true
        end
        local ok, errorMessage = sendCommand(action, args)
        if ok then
            if urgentSafety then
                Runtime.Screen.safetyWaiting = true
                Runtime.Screen.status = Runtime.Screen.resourceId == "windmill"
                    and "Urgent Windmill safety action sent to the host device..."
                    or "Urgent cutter safety action sent to the host device..."
            else
                Runtime.Screen.waiting = true
                Runtime.Screen.status = "Waiting for the host device to verify that action..."
            end
        else
            Runtime.Screen.status = tostring(errorMessage or "The command could not be sent.")
        end
        return true
    end

    function Runtime.commitCutterGauge(sendCommand)
        local inches = tonumber(Runtime.Screen.gaugeText)
        if not inches or inches < 0 or inches > 25 then
            Runtime.Screen.status = "Enter a backgauge position from 0.00 to 25.00 inches."
            return true
        end
        Runtime.Screen.gaugeText = string.format("%.2f", inches)
        Runtime.Screen.gaugeFocused = false
        Runtime.Screen.gaugeReplaceOnType = true
        return Runtime.request(sendCommand, "set_gauge", {
            gaugeCentiInch = math.floor(inches * 100 + 0.5),
        })
    end

    function Runtime.cutterCutReady()
        local view = Runtime.Screen.view or {}
        return not Runtime.Screen.waiting and not Runtime.Screen.safetyWaiting
            and view.loaded == true and view.clamp == true
            and view.barrierClear == true and view.emergencyStopped ~= true
            and view.step == "clamped"
    end

    function Runtime.handleCutterCut(sendCommand)
        if not Runtime.cutterCutReady() then
            Runtime.Screen.status = (Runtime.Screen.waiting or Runtime.Screen.safetyWaiting)
                and "Wait for the host to finish verifying the previous action."
                or "Position the paper, lower the clamp, clear the barrier, and reset E-STOP first."
            return true
        end
        return Runtime.request(sendCommand, "guarded_cut", {})
    end

    Runtime.windmillButtonEnabled = nil
    Runtime.cutterButtonEnabled = nil

    function Runtime.Screen.keypressed(key, state, sendCommand)
        if Runtime.Screen.sharedPress then
            Runtime.Screen.sendCommand=sendCommand
            return Runtime.Screen.sharedPress.keypressed(state,key)
        end
        if Runtime.Screen.sharedMachine then
            Runtime.Screen.sendCommand = sendCommand
            return Runtime.Screen.sharedMachine.keypressed(state,key)
        end
        if Runtime.Screen.sharedComputer then
            if Runtime.Screen.waiting then return true end
            Runtime.Screen.sendCommand, Runtime.Screen.guiState = sendCommand, Runtime.Projection.copy(state)
            return Runtime.Screen.sharedComputer.keypressed(Runtime.Screen.guiState, key)
        end
        key = string.lower(tostring(key or ""))
        if Runtime.Screen.resourceId == "windmill" then
            local view = Runtime.Screen.view or {}
            local action = ({
                m = "toggle_motor",
                f = "toggle_feeder",
                i = "toggle_impression",
                ["-"] = "speed_down",
                ["kp-"] = "speed_down",
                ["+"] = "speed_up",
                ["="] = "speed_up",
                ["kp+"] = "speed_up",
                x = "emergency_stop",
                r = "reset_safety",
                p = "take_proof",
                v = "verify_artwork",
            })[key]
            if key == "space" then
                action = view.status == "production" and "stop_run" or "start_run"
            end
            if action then
                if Runtime.windmillButtonEnabled and Runtime.windmillButtonEnabled(action, state) then
                    return Runtime.request(sendCommand, action, {})
                end
                Runtime.Screen.status = "The Windmill is not ready for that control."
                return true
            end
            return false
        end
        if Runtime.Screen.resourceId == "cutter" then
            if Runtime.Screen.cutterTab == "service" then return false end
            local view = Runtime.Screen.view or {}
            -- Safety remains available while typing or waiting on an ordinary action.
            if key == "x" then
                return Runtime.cutterButtonEnabled("emergency_stop")
                    and Runtime.request(sendCommand, "emergency_stop", {}) or true
            end
            if key == "b" then
                return Runtime.cutterButtonEnabled("set_barrier")
                    and Runtime.request(sendCommand, "set_barrier", { barrierClear = view.barrierClear ~= true }) or true
            end
            if not Runtime.Screen.gaugeFocused then
                local program = key == "[" and math.max(1, (view.programIndex or 1) - 1)
                    or key == "]" and math.min(4, (view.programIndex or 1) + 1) or tonumber(key)
                if program and program >= 1 and program <= 4 then
                    return Runtime.cutterButtonEnabled("select_program")
                        and Runtime.request(sendCommand, "select_program", { programIndex = program }) or true
                end
                if key == "l" then
                    local candidates = Runtime.cutterCandidates()
                    if #candidates == 1 and Runtime.cutterButtonEnabled("load_pallet") then
                        return Runtime.request(sendCommand, "load_pallet", { palletId = candidates[1].palletId })
                    elseif #candidates == 0 and (tonumber(view.genericSheets) or 0) > 0
                        and Runtime.cutterButtonEnabled("load_stock") then
                        return Runtime.request(sendCommand, "load_stock", {})
                    end
                    Runtime.Screen.status = "Choose the matching nearby pallet on screen."
                    return true
                end
                local action = ({ g = "auto_gauge", m = "save_gauge", v = "recall_gauge",
                    q = "rotate_paper", p = "position_paper", space = "set_clamp",
                    u = "return_to_pallet", t = "run_next_lift", r = "reset_safety" })[key]
                if action then
                    local args = action == "set_clamp" and { clamp = view.clamp ~= true } or {}
                    return Runtime.cutterButtonEnabled(action) and Runtime.request(sendCommand, action, args) or true
                end
            end
            if key == "j" or key == "k" then return Runtime.handleCutterCut(sendCommand) end
            if not Runtime.Screen.gaugeFocused then return false end
            if key == "backspace" then
                if Runtime.Screen.gaugeReplaceOnType then
                    Runtime.Screen.gaugeText = ""
                    Runtime.Screen.gaugeReplaceOnType = false
                else
                    local offset = Runtime.utf8.offset(Runtime.Screen.gaugeText, -1)
                    Runtime.Screen.gaugeText = offset and Runtime.Screen.gaugeText:sub(1, offset - 1) or ""
                end
                return true
            elseif key == "return" or key == "kpenter" then
                return Runtime.commitCutterGauge(sendCommand)
            end
            return false
        end
        return false
    end

    function Runtime.Screen.textinput(text)
        if Runtime.Screen.sharedMachine then return Runtime.Screen.sharedMachine.textinput(text) end
        if Runtime.Screen.sharedComputer then return not Runtime.Screen.waiting and Runtime.Screen.sharedComputer.textinput(Runtime.Screen.guiState, text) end
        if not Runtime.Screen:wantsTextInput() then return false end
        if Runtime.Screen.resourceId == "cutter" then
            local changed = false
            for character in tostring(text):gmatch(".") do
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
        for character in tostring(text):gmatch(".") do
            if character:match("%d") and #Runtime.Screen.quoteText < 8 then
                if Runtime.Screen.quoteReplaceOnType then
                    Runtime.Screen.quoteText = ""
                    Runtime.Screen.quoteReplaceOnType = false
                end
                Runtime.Screen.quoteText = Runtime.Screen.quoteText .. character
            end
        end
        return true
    end
end

return Component
