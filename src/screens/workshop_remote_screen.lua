local BackButton = require("src.screens.back_button")
local Config = require("src.config")
local JobService = require("src.job_service")
local Ui = require("src.screens.ui")
local Wrapper = require("src.wrapper")
local utf8 = require("utf8")

local Screen = {
    resourceId = nil,
    leaseId = nil,
    revision = 0,
    workshopTick = 0,
    view = nil,
    quoteText = "",
    quoteFocused = false,
    quoteReplaceOnType = true,
    selectedJobId = nil,
    selectedPalletId = nil,
    waiting = false,
    safetyWaiting = false,
    status = "",
    gaugeText = "0.00",
    gaugeFocused = false,
    gaugeReplaceOnType = true,
}

local PANEL = { x = 92, y = 44, width = 776, height = 590 }
local BACK = { x = 714, y = 58, width = 126, height = 40 }
local QUOTE_INPUT = { x = 566, y = 452, width = 180, height = 42 }
local DECLINE = { x = 246, y = 538, width = 174, height = 48 }
local CONFIRM = { x = 540, y = 538, width = 174, height = 48 }
local ROW_X, ROW_Y, ROW_W, ROW_H, ROW_GAP = 142, 174, 676, 48, 8

local CUTTER_GAUGE_INPUT = { x = 122, y = 246, width = 106, height = 42 }
local CUTTER_CONTROLS = {
    gauge_set = { x = 236, y = 246, width = 78, height = 42 },
    auto_gauge = { x = 322, y = 246, width = 100, height = 42 },
    save_gauge = { x = 430, y = 246, width = 100, height = 42 },
    recall_gauge = { x = 538, y = 246, width = 120, height = 42 },
    rotate_paper = { x = 122, y = 300, width = 222, height = 44 },
    position_paper = { x = 356, y = 300, width = 222, height = 44 },
    set_clamp = { x = 590, y = 300, width = 222, height = 44 },
    set_barrier = { x = 122, y = 356, width = 222, height = 44 },
    reset_safety = { x = 356, y = 356, width = 222, height = 44 },
    emergency_stop = { x = 590, y = 356, width = 222, height = 44 },
    return_to_pallet = { x = 122, y = 412, width = 339, height = 42 },
    run_next_lift = { x = 473, y = 412, width = 339, height = 42 },
    cut_left = { x = 122, y = 466, width = 339, height = 68 },
    cut_right = { x = 473, y = 466, width = 339, height = 68 },
    load_stock = { x = 298, y = 354, width = 338, height = 46 },
}

local CUTTER_UNLOADED_CONTROLS = {
    load_stock = { x = 122, y = 356, width = 222, height = 44 },
    set_barrier = { x = 356, y = 356, width = 222, height = 44 },
    reset_safety = { x = 590, y = 356, width = 222, height = 44 },
    run_next_lift = { x = 122, y = 412, width = 456, height = 48 },
    emergency_stop = { x = 590, y = 412, width = 222, height = 48 },
}

local CUTTER_PROGRAMS = {
    { x = 122, y = 198, width = 104, height = 38 },
    { x = 234, y = 198, width = 104, height = 38 },
    { x = 346, y = 198, width = 104, height = 38 },
    { x = 458, y = 198, width = 104, height = 38 },
}

local function cutterCandidateRect(index)
    local column = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    return {
        x = 122 + column * 358,
        y = 218 + row * 44,
        width = 346,
        height = 36,
    }
end

local function contains(rect, x, y)
    return Ui.contains(rect, x, y)
end

local function button(rect, label, pointerX, pointerY, enabled, green)
    local hovered = enabled and pointerX and pointerY and contains(rect, pointerX, pointerY)
    if not enabled then
        love.graphics.setColor(0.24, 0.27, 0.29)
    elseif green then
        love.graphics.setColor(hovered and 0.18 or 0.11, hovered and 0.58 or 0.45, 0.29)
    else
        love.graphics.setColor(hovered and 0.72 or 0.57, hovered and 0.28 or 0.20, 0.18)
    end
    love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 5, 5)
    love.graphics.setColor(enabled and 0.98 or 0.60, enabled and 0.98 or 0.63,
        enabled and 0.96 or 0.65)
    love.graphics.printf(label, rect.x, rect.y + math.floor(rect.height / 2) - 6,
        rect.width, "center")
end

local function header(title, subtitle, pointerX, pointerY, assets)
    love.graphics.setColor(0.01, 0.02, 0.03, 0.76)
    love.graphics.rectangle("fill", 0, 0, Config.baseWidth, Config.baseHeight)
    love.graphics.setColor(0.91, 0.90, 0.83)
    love.graphics.rectangle("fill", PANEL.x, PANEL.y, PANEL.width, PANEL.height, 6, 6)
    love.graphics.setColor(0.16, 0.21, 0.24)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", PANEL.x, PANEL.y, PANEL.width, PANEL.height, 6, 6)
    love.graphics.rectangle("fill", PANEL.x, PANEL.y, PANEL.width, 72, 6, 6)
    love.graphics.setColor(0.97, 0.84, 0.30)
    love.graphics.printf(title, PANEL.x + 16, PANEL.y + 14, PANEL.width - 32, "center")
    love.graphics.setColor(0.82, 0.87, 0.88)
    love.graphics.printf(subtitle, PANEL.x + 16, PANEL.y + 40, PANEL.width - 32, "center")
    BackButton.draw(assets, BACK, "BACK", pointerX, pointerY,
        Screen.waiting or Screen.safetyWaiting)
end

local function activeJobs(state)
    local rows = {}
    for _, job in ipairs((state.jobs and state.jobs.active) or {}) do
        rows[#rows + 1] = job
        if #rows >= 6 then break end
    end
    return rows
end

local function wrapperRows(state)
    local rows = {}
    if Screen.view and type(Screen.view.pallets) == "table" then
        for _, item in ipairs(Screen.view.pallets) do rows[#rows + 1] = item end
        return rows
    end
    for _, item in ipairs(Wrapper.nearbyPallets(state)) do
        rows[#rows + 1] = {
            palletId = item.pallet.id,
            jobLabel = item.job and ((item.job.company or "Client") .. " · " .. item.job.id)
                or "Client pallet",
            packaging = item.pallet.packaging or "flat",
        }
        if #rows >= 6 then break end
    end
    return rows
end

local function selectedWrapperPallet(rows)
    if Screen.selectedPalletId == nil then return nil end
    for _, item in ipairs(rows) do
        if item.palletId == Screen.selectedPalletId then return item end
    end
    return nil
end

local function cutterPalletLabel(state, palletId)
    for _, job in ipairs((state and state.jobs and state.jobs.active) or {}) do
        for _, pallet in ipairs(job.pallets or {}) do
            if pallet.id == palletId then
                return string.format("%s · %s", tostring(job.company or "Client"),
                    tostring(job.id or palletId))
            end
        end
    end
    return tostring(palletId or "Pallet")
end

local function cutterRuntimeRevision(view)
    return type(view) == "table" and tonumber(view.runtimeRevision) or nil
end

local function syncCutterGauge(force)
    if Screen.resourceId ~= "cutter" or (Screen.gaugeFocused and not force) then return end
    local centi = math.max(0, math.floor(tonumber(Screen.view and Screen.view.gaugeCentiInch) or 0))
    Screen.gaugeText = string.format("%.2f", centi / 100)
    Screen.gaugeReplaceOnType = true
end

local function mergeCutterView(incoming)
    if type(incoming) ~= "table" then return false end
    local incomingRevision = cutterRuntimeRevision(incoming)
    local currentRevision = cutterRuntimeRevision(Screen.view) or -1
    if incomingRevision == nil or incomingRevision < currentRevision then return false end
    local merged = Screen.view or {}
    for key, value in pairs(incoming) do merged[key] = value end
    if incoming.paper ~= nil then
        merged.candidates, merged.genericSheets = nil, nil
    elseif incoming.loaded == false then
        merged.paper = nil
        if incoming.candidates ~= nil and incoming.genericSheets == nil then
            merged.genericSheets = nil
        end
    end
    Screen.view = merged
    syncCutterGauge(false)
    return true
end

local function cutterResourceRevision(snapshot)
    local direct = tonumber(snapshot.resourceRevision)
    if direct then return direct end
    local cutter = snapshot.cutter or snapshot.view or snapshot.data
    direct = type(cutter) == "table" and tonumber(cutter.resourceRevision) or nil
    if direct then return direct end
    for _, record in ipairs(snapshot.resources or {}) do
        if record.resourceId == "cutter" then return tonumber(record.revision) end
    end
    return nil
end

local function cutterCandidates()
    local rows = {}
    for _, candidate in ipairs((Screen.view and Screen.view.candidates) or {}) do
        rows[#rows + 1] = candidate
        if #rows >= 3 then break end
    end
    return rows
end

local function rowRect(index)
    return { x = ROW_X, y = ROW_Y + (index - 1) * (ROW_H + ROW_GAP), width = ROW_W, height = ROW_H }
end

function Screen.enter(grant, state)
    Screen.resourceId = grant and grant.resourceId or nil
    Screen.leaseId = grant and grant.leaseId or nil
    Screen.revision = tonumber(grant and grant.revision) or 0
    Screen.workshopTick = 0
    Screen.view = grant and (grant.view or grant.data) or nil
    Screen.quoteText = tostring(Screen.view and Screen.view.recommendedTotal or "")
    Screen.quoteFocused = false
    Screen.quoteReplaceOnType = true
    Screen.selectedJobId = nil
    Screen.selectedPalletId = Screen.view and Screen.view.selectedPalletId or nil
    Screen.waiting = false
    Screen.safetyWaiting = false
    Screen.status = tostring(grant and grant.message or "Remote console ready.")
    Screen.gaugeFocused = false
    Screen.gaugeReplaceOnType = true
    syncCutterGauge(true)
    if state then state.screen = "workshop_remote" end
    return Screen.resourceId ~= nil and Screen.leaseId ~= nil
end

function Screen.clear()
    Screen.resourceId, Screen.leaseId, Screen.view = nil, nil, nil
    Screen.quoteFocused, Screen.waiting, Screen.safetyWaiting = false, false, false
    Screen.selectedJobId, Screen.selectedPalletId = nil, nil
    Screen.gaugeFocused, Screen.gaugeReplaceOnType = false, true
    Screen.workshopTick = 0
end

function Screen.isOpen() return Screen.resourceId ~= nil and Screen.leaseId ~= nil end
function Screen.canClose()
    return not Screen.waiting and not Screen.safetyWaiting
        and (Screen.resourceId ~= "skid_wrapper" or Wrapper.step ~= "wrapping")
end
function Screen.wantsTextInput()
    return (Screen.resourceId == "reception_customer" and Screen.quoteFocused)
        or (Screen.resourceId == "cutter" and Screen.gaugeFocused)
end

function Screen.wrapperStartEnabled(state)
    return Screen.resourceId == "skid_wrapper"
        and not Screen.waiting
        and Wrapper.step ~= "wrapping"
        and selectedWrapperPallet(wrapperRows(state)) ~= nil
end

function Screen.applyResult(result)
    if type(result) ~= "table" or result.resourceId ~= Screen.resourceId then return false end
    if result.urgentSafety == true then
        Screen.safetyWaiting = false
    else
        Screen.waiting = false
    end
    Screen.revision = math.max(Screen.revision, tonumber(result.revision) or Screen.revision)
    Screen.status = tostring(result.message or (result.accepted and "Action completed." or "Action rejected."))
    if Screen.resourceId == "cutter" then
        mergeCutterView(result.view or result.data)
    elseif result.view or result.data then
        Screen.view = result.view or result.data
    end
    if result.accepted and result.action == "select_pallet" then
        Screen.selectedPalletId = result.palletId
            or (Screen.view and Screen.view.selectedPalletId) or Screen.selectedPalletId
    end
    return true
end

function Screen.applySnapshot(snapshot)
    if type(snapshot) ~= "table" then return false end
    Screen.workshopTick = tonumber(snapshot.revision) or Screen.workshopTick
    local wrapper = snapshot.wrapper
    if Screen.resourceId == "skid_wrapper" and type(wrapper) == "table" then
        Screen.selectedPalletId = wrapper.selectedPalletId
        Screen.view = Screen.view or {}
        for key, value in pairs(wrapper) do Screen.view[key] = value end
    end
    return true
end

function Screen.applyCutterSnapshot(snapshot)
    if Screen.resourceId ~= "cutter" or type(snapshot) ~= "table" then return false end
    local resourceRevision = cutterResourceRevision(snapshot)
    if resourceRevision == nil or resourceRevision < Screen.revision then return false end
    local cutter = snapshot.view or snapshot.cutter or snapshot.data
    if type(cutter) ~= "table" or not mergeCutterView(cutter) then return false end
    Screen.revision = resourceRevision
    return true
end

local function urgentCutterSafety(action, args)
    return Screen.resourceId == "cutter" and (action == "emergency_stop"
        or (action == "set_barrier" and type(args) == "table"
            and args.barrierClear == false))
end

local function request(sendCommand, action, args)
    args = args or {}
    local urgentSafety = urgentCutterSafety(action, args)
    if Screen.safetyWaiting or (Screen.waiting and not urgentSafety) then return false end
    if type(sendCommand) ~= "function" then
        Screen.status = "The remote console is not connected to the host command channel."
        return true
    end
    local ok, errorMessage = sendCommand(action, args)
    if ok then
        if urgentSafety then
            Screen.safetyWaiting = true
            Screen.status = "Urgent cutter safety action sent to the host device..."
        else
            Screen.waiting = true
            Screen.status = "Waiting for the host device to verify that action..."
        end
    else
        Screen.status = tostring(errorMessage or "The command could not be sent.")
    end
    return true
end

local function commitCutterGauge(sendCommand)
    local inches = tonumber(Screen.gaugeText)
    if not inches or inches < 0 or inches > 25 then
        Screen.status = "Enter a backgauge position from 0.00 to 25.00 inches."
        return true
    end
    Screen.gaugeText = string.format("%.2f", inches)
    Screen.gaugeFocused = false
    Screen.gaugeReplaceOnType = true
    return request(sendCommand, "set_gauge", {
        gaugeCentiInch = math.floor(inches * 100 + 0.5),
    })
end

local function cutterCutReady()
    local view = Screen.view or {}
    return not Screen.waiting and not Screen.safetyWaiting
        and view.loaded == true and view.clamp == true
        and view.barrierClear == true and view.emergencyStopped ~= true
        and view.step == "clamped"
end

local function handleCutterCut(sendCommand)
    if not cutterCutReady() then
        Screen.status = (Screen.waiting or Screen.safetyWaiting)
            and "Wait for the host to finish verifying the previous action."
            or "Position the paper, lower the clamp, clear the barrier, and reset E-STOP first."
        return true
    end
    return request(sendCommand, "guarded_cut", {})
end

function Screen.keypressed(key, state, sendCommand)
    key = string.lower(tostring(key or ""))
    if Screen.resourceId == "cutter" then
        if key == "j" or key == "k" then return handleCutterCut(sendCommand) end
        if not Screen.gaugeFocused then return false end
        if key == "backspace" then
            if Screen.gaugeReplaceOnType then
                Screen.gaugeText = ""
                Screen.gaugeReplaceOnType = false
            else
                local offset = utf8.offset(Screen.gaugeText, -1)
                Screen.gaugeText = offset and Screen.gaugeText:sub(1, offset - 1) or ""
            end
            return true
        elseif key == "return" or key == "kpenter" then
            return commitCutterGauge(sendCommand)
        end
        return false
    end
    if Screen.resourceId ~= "reception_customer" or not Screen.quoteFocused then return false end
    if key == "backspace" then
        if Screen.quoteReplaceOnType then
            Screen.quoteText = ""
            Screen.quoteReplaceOnType = false
        else
            local offset = utf8.offset(Screen.quoteText, -1)
            Screen.quoteText = offset and Screen.quoteText:sub(1, offset - 1) or ""
        end
        return true
    end
    return false
end

function Screen.textinput(text)
    if not Screen:wantsTextInput() then return false end
    if Screen.resourceId == "cutter" then
        local changed = false
        for character in tostring(text):gmatch(".") do
            if character:match("%d") and #Screen.gaugeText < 7 then
                if Screen.gaugeReplaceOnType then
                    Screen.gaugeText = ""
                    Screen.gaugeReplaceOnType = false
                end
                Screen.gaugeText = Screen.gaugeText .. character
                changed = true
            elseif character == "." and not Screen.gaugeText:find(".", 1, true) then
                if Screen.gaugeReplaceOnType then
                    Screen.gaugeText = "0"
                    Screen.gaugeReplaceOnType = false
                end
                Screen.gaugeText = Screen.gaugeText .. character
                changed = true
            end
        end
        return changed
    end
    for character in tostring(text):gmatch(".") do
        if character:match("%d") and #Screen.quoteText < 8 then
            if Screen.quoteReplaceOnType then
                Screen.quoteText = ""
                Screen.quoteReplaceOnType = false
            end
            Screen.quoteText = Screen.quoteText .. character
        end
    end
    return true
end

local function cutterButtonEnabled(action)
    local view = Screen.view or {}
    if Screen.safetyWaiting then return false end
    if Screen.waiting then
        return action == "emergency_stop"
            or (action == "set_barrier" and view.barrierClear == true)
    end
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
        return cutterCutReady()
    elseif action == "load_stock" or action == "load_pallet" then
        return view.loaded ~= true and (view.step == "idle" or view.step == "finished")
    end
    return false
end

function Screen.mousepressed(state, x, y, button, sendCommand)
    if button ~= 1 or not Screen:isOpen() then return false end
    if contains(BACK, x, y) then return Screen.canClose() and { action = "close" } or true end
    if Screen.resourceId == "reception_customer" then
        if contains(QUOTE_INPUT, x, y) then
            Screen.quoteFocused, Screen.quoteReplaceOnType = true, true
            return true
        end
        Screen.quoteFocused = false
        if contains(DECLINE, x, y) then
            request(sendCommand, "decline", {})
            return true
        elseif contains(CONFIRM, x, y) then
            local amount = tonumber(Screen.quoteText)
            if not amount or amount < 1 then
                Screen.status = "Enter a whole-dollar quote first."
                return true
            end
            request(sendCommand, "submit_quote", { amount = math.floor(amount) })
            return true
        end
    elseif Screen.resourceId == "office_computer" then
        local jobs = activeJobs(state)
        for index, job in ipairs(jobs) do
            if contains(rowRect(index), x, y) then
                Screen.selectedJobId = job.id
                Screen.status = JobService.completionReady(job)
                    and "Ready to request customer pickup."
                    or "This job is visible, but every pallet must be finished and wrapped first."
                return true
            end
        end
        if contains(CONFIRM, x, y) and Screen.selectedJobId then
            return request(sendCommand, "request_pickup", { jobId = Screen.selectedJobId })
        end
    elseif Screen.resourceId == "skid_wrapper" then
        local rows = wrapperRows(state)
        for index, item in ipairs(rows) do
            if contains(rowRect(index), x, y) then
                Screen.selectedPalletId = item.palletId
                return request(sendCommand, "select_pallet", { palletId = item.palletId })
            end
        end
        if contains(CONFIRM, x, y) then
            local selected = selectedWrapperPallet(rows)
            if not Screen.wrapperStartEnabled(state) then
                if Screen.waiting or Wrapper.step == "wrapping" then return true end
                Screen.status = #rows == 0
                    and "Park a finished, unwrapped pallet beside the skid wrapper first."
                    or "Select a nearby finished pallet first."
                return true
            end
            return request(sendCommand, "start_cycle", { palletId = selected.palletId })
        end
    elseif Screen.resourceId == "cutter" then
        local view = Screen.view or {}
        if view.loaded ~= true then
            for index, candidate in ipairs(cutterCandidates()) do
                if contains(cutterCandidateRect(index), x, y) then
                    Screen.gaugeFocused = false
                    if cutterButtonEnabled("load_pallet") then
                        return request(sendCommand, "load_pallet", { palletId = candidate.palletId })
                    end
                    return true
                end
            end
            if contains(CUTTER_UNLOADED_CONTROLS.load_stock, x, y) then
                Screen.gaugeFocused = false
                if not cutterButtonEnabled("load_stock") then return true end
                if (tonumber(view.genericSheets) or 0) <= 0 then
                    Screen.status = "No generic production stock is available on the host device."
                    return true
                end
                return request(sendCommand, "load_stock", {})
            end
            if contains(CUTTER_UNLOADED_CONTROLS.set_barrier, x, y) then
                return cutterButtonEnabled("set_barrier")
                    and request(sendCommand, "set_barrier", { barrierClear = view.barrierClear ~= true }) or true
            elseif contains(CUTTER_UNLOADED_CONTROLS.reset_safety, x, y) then
                return cutterButtonEnabled("reset_safety")
                    and request(sendCommand, "reset_safety", {}) or true
            elseif contains(CUTTER_UNLOADED_CONTROLS.run_next_lift, x, y) then
                return cutterButtonEnabled("run_next_lift")
                    and request(sendCommand, "run_next_lift", {}) or true
            elseif contains(CUTTER_UNLOADED_CONTROLS.emergency_stop, x, y) then
                return cutterButtonEnabled("emergency_stop")
                    and request(sendCommand, "emergency_stop", {}) or true
            end
            return false
        end
        if contains(CUTTER_GAUGE_INPUT, x, y) then
            Screen.gaugeFocused, Screen.gaugeReplaceOnType = true, true
            return true
        end
        Screen.gaugeFocused = false
        for index, rect in ipairs(CUTTER_PROGRAMS) do
            if contains(rect, x, y) then
                if cutterButtonEnabled("select_program") then
                    return request(sendCommand, "select_program", { programIndex = index })
                end
                return true
            end
        end
        if contains(CUTTER_CONTROLS.gauge_set, x, y) then
            return cutterButtonEnabled("gauge_set") and commitCutterGauge(sendCommand) or true
        elseif contains(CUTTER_CONTROLS.auto_gauge, x, y) then
            return cutterButtonEnabled("auto_gauge") and request(sendCommand, "auto_gauge", {}) or true
        elseif contains(CUTTER_CONTROLS.save_gauge, x, y) then
            return cutterButtonEnabled("save_gauge") and request(sendCommand, "save_gauge", {}) or true
        elseif contains(CUTTER_CONTROLS.recall_gauge, x, y) then
            return cutterButtonEnabled("recall_gauge") and request(sendCommand, "recall_gauge", {}) or true
        elseif contains(CUTTER_CONTROLS.rotate_paper, x, y) then
            return cutterButtonEnabled("rotate_paper") and request(sendCommand, "rotate_paper", {}) or true
        elseif contains(CUTTER_CONTROLS.position_paper, x, y) then
            return cutterButtonEnabled("position_paper") and request(sendCommand, "position_paper", {}) or true
        elseif contains(CUTTER_CONTROLS.set_clamp, x, y) then
            return cutterButtonEnabled("set_clamp")
                and request(sendCommand, "set_clamp", { clamp = view.clamp ~= true }) or true
        elseif contains(CUTTER_CONTROLS.set_barrier, x, y) then
            return cutterButtonEnabled("set_barrier")
                and request(sendCommand, "set_barrier", { barrierClear = view.barrierClear ~= true }) or true
        elseif contains(CUTTER_CONTROLS.reset_safety, x, y) then
            return cutterButtonEnabled("reset_safety") and request(sendCommand, "reset_safety", {}) or true
        elseif contains(CUTTER_CONTROLS.emergency_stop, x, y) then
            return cutterButtonEnabled("emergency_stop") and request(sendCommand, "emergency_stop", {}) or true
        elseif contains(CUTTER_CONTROLS.return_to_pallet, x, y) then
            return cutterButtonEnabled("return_to_pallet")
                and request(sendCommand, "return_to_pallet", {}) or true
        elseif contains(CUTTER_CONTROLS.run_next_lift, x, y) then
            return cutterButtonEnabled("run_next_lift")
                and request(sendCommand, "run_next_lift", {}) or true
        elseif contains(CUTTER_CONTROLS.cut_left, x, y) then
            return handleCutterCut(sendCommand)
        elseif contains(CUTTER_CONTROLS.cut_right, x, y) then
            return handleCutterCut(sendCommand)
        end
    end
    return false
end

local function drawCustomer(pointerX, pointerY)
    local view = Screen.view or {}
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print("CLIENT", 142, 150)
    love.graphics.printf(tostring(view.company or "Waiting customer"), 260, 150, 500, "left")
    love.graphics.print("JOB", 142, 184)
    love.graphics.printf(tostring(view.jobId or "Pending ticket"), 260, 184, 500, "left")
    love.graphics.print("WORK", 142, 218)
    local source = view.sourceSize or {}
    local finished = view.finishedSize or {}
    local description = string.format("%gx%g stock to %gx%g finished · %s · %s",
        tonumber(source.width) or 0, tonumber(source.height) or 0,
        tonumber(finished.width) or 0, tonumber(finished.height) or 0,
        tostring(view.stock or "customer stock"),
        view.packaging == "boxed" and "boxed" or "flat pallet")
    love.graphics.printf(description, 260, 218, 500, "left")
    love.graphics.print("DELIVERY", 142, 288)
    love.graphics.printf(tostring(view.delivery or "Host-calculated service"), 260, 288, 500, "left")
    love.graphics.setColor(0.18, 0.21, 0.22)
    love.graphics.rectangle("fill", 142, 354, 676, 104, 4, 4)
    love.graphics.setColor(0.94, 0.91, 0.79)
    love.graphics.printf(string.format("Recommended shop quote: $%d",
        tonumber(view.recommendedTotal) or 0), 160, 378, 640, "center")
    love.graphics.setColor(Screen.quoteFocused and 0.98 or 0.88, 0.96, 0.82)
    love.graphics.rectangle("fill", QUOTE_INPUT.x, QUOTE_INPUT.y, QUOTE_INPUT.width,
        QUOTE_INPUT.height, 4, 4)
    love.graphics.setColor(0.08, 0.10, 0.11)
    love.graphics.printf("$" .. Screen.quoteText, QUOTE_INPUT.x, QUOTE_INPUT.y + 13,
        QUOTE_INPUT.width, "center")
    button(DECLINE, "DECLINE", pointerX, pointerY, not Screen.waiting, false)
    button(CONFIRM, "SEND QUOTE", pointerX, pointerY, not Screen.waiting, true)
end

local function drawComputer(state, pointerX, pointerY)
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print(string.format("CASH  $%d", math.floor(tonumber(state.money) or 0)), 142, 136)
    love.graphics.print(string.format("A/R  $%d", math.floor(tonumber(state.accountsReceivable) or 0)), 350, 136)
    love.graphics.print("ACTIVE JOBS — select one to inspect pickup readiness", 142, 158)
    local jobs = activeJobs(state)
    if #jobs == 0 then
        love.graphics.setColor(0.40, 0.42, 0.43)
        love.graphics.printf("No active jobs are in the host shop.", ROW_X, ROW_Y + 30, ROW_W, "center")
    end
    for index, job in ipairs(jobs) do
        local rect = rowRect(index)
        local selected = job.id == Screen.selectedJobId
        love.graphics.setColor(selected and 0.91 or 0.79, selected and 0.72 or 0.78,
            selected and 0.24 or 0.73)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
        love.graphics.setColor(0.08, 0.10, 0.11)
        love.graphics.print(tostring(job.id), rect.x + 14, rect.y + 9)
        love.graphics.printf(tostring(job.company or "Client"), rect.x + 110, rect.y + 9, 280, "left")
        love.graphics.printf(JobService.completionReady(job) and "READY" or tostring(job.status or "ACTIVE"),
            rect.x + 470, rect.y + 9, 184, "right")
    end
    button(CONFIRM, "REQUEST PICKUP", pointerX, pointerY,
        not Screen.waiting and Screen.selectedJobId ~= nil, true)
end

local function drawWrapper(state, pointerX, pointerY)
    local runtime = Wrapper.snapshot()
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print("HOST CYCLE", 142, 136)
    love.graphics.print(string.upper(runtime.step), 270, 136)
    local ratio = math.min(1, runtime.progress / math.max(0.001, runtime.cycleTime))
    love.graphics.setColor(0.18, 0.21, 0.22)
    love.graphics.rectangle("fill", 420, 136, 380, 18, 3, 3)
    love.graphics.setColor(0.92, 0.72, 0.20)
    love.graphics.rectangle("fill", 420, 136, 380 * ratio, 18, 3, 3)
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print("NEARBY FINISHED PALLETS", 142, 158)
    local rows = wrapperRows(state)
    if #rows == 0 then
        love.graphics.setColor(0.40, 0.42, 0.43)
        love.graphics.printf("No eligible pallet is parked by the wrapper.", ROW_X, ROW_Y + 34, ROW_W, "center")
    end
    for index, item in ipairs(rows) do
        local rect = rowRect(index)
        local selected = item.palletId == Screen.selectedPalletId
        love.graphics.setColor(selected and 0.91 or 0.79, selected and 0.72 or 0.78,
            selected and 0.24 or 0.73)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
        love.graphics.setColor(0.08, 0.10, 0.11)
        love.graphics.print(tostring(item.palletId), rect.x + 14, rect.y + 9)
        love.graphics.printf(tostring(item.jobLabel or "Client pallet"),
            rect.x + 170, rect.y + 9, 300, "left")
        love.graphics.printf(string.upper(tostring(item.packaging or "flat")),
            rect.x + 520, rect.y + 9, 134, "right")
    end
    button(CONFIRM, runtime.step == "wrapping" and "WRAPPING..." or "START CYCLE",
        pointerX, pointerY, Screen.wrapperStartEnabled(state), true)
end

local function compactLabel(value, limit)
    local label = tostring(value or "")
    if #label <= limit then return label end
    return label:sub(1, math.max(1, limit - 3)) .. "..."
end

local function cutterBar(x, y, width, permille, color)
    local ratio = math.max(0, math.min(1, (tonumber(permille) or 0) / 1000))
    love.graphics.setColor(0.18, 0.21, 0.22)
    love.graphics.rectangle("fill", x, y, width, 14, 3, 3)
    love.graphics.setColor(color[1], color[2], color[3])
    love.graphics.rectangle("fill", x, y, width * ratio, 14, 3, 3)
end

local function drawCutter(state, pointerX, pointerY)
    local view = Screen.view or {}
    local step = tostring(view.step or "idle"):gsub("_", " "):upper()
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print("HOST PHASE  " .. step, 122, 130)
    cutterBar(344, 132, 468, view.phasePermille, { 0.92, 0.72, 0.20 })
    love.graphics.print("CLAMP", 122, 154)
    cutterBar(178, 155, 172, view.clampPermille, { 0.22, 0.56, 0.76 })
    love.graphics.print("BLADE", 370, 154)
    cutterBar(426, 155, 172, view.bladePermille, { 0.76, 0.25, 0.18 })
    love.graphics.printf(string.format("BARRIER %s  ·  E-STOP %s",
        view.barrierClear == true and "CLEAR" or "BLOCKED",
        view.emergencyStopped == true and "ACTIVE" or "RESET"),
        608, 154, 204, "right")

    local paper = type(view.paper) == "table" and view.paper or nil
    if paper then
        local label = cutterPalletLabel(state, paper.palletId)
        love.graphics.printf(string.format("%s  ·  LIFT %d/%d  ·  %d LEFT  ·  %d°",
            compactLabel(label, 28), tonumber(paper.activeLift) or 1,
            tonumber(paper.requiredLifts) or 1, tonumber(paper.remainingSheets) or 0,
            tonumber(paper.orientation) or 0), 122, 176, 430, "left")
        local cut = type(paper.selectedCut) == "table" and paper.selectedCut or nil
        if cut then
            love.graphics.printf(string.format("CUT %d  %s  M %.2f  G %.2f",
                tonumber(cut.number) or tonumber(paper.activeCut) or 1,
                tostring(cut.edge or "edge"):upper(),
                (tonumber(cut.marginCentiInch) or 0) / 100,
                (tonumber(cut.gaugeCentiInch) or 0) / 100), 552, 176, 260, "right")
        end
    else
        love.graphics.printf("No paper is on the cutting bed.", 122, 176, 690, "left")
    end

    if view.loaded ~= true then
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.print("NEARBY CUTTER PALLETS", 122, 198)
        local candidates = cutterCandidates()
        if #candidates == 0 then
            love.graphics.setColor(0.40, 0.42, 0.43)
            love.graphics.printf("Park an unfinished pallet beside the cutter, or use generic stock.",
                122, 260, 690, "center")
        end
        for index, candidate in ipairs(candidates) do
            local distance = math.max(0, math.floor(tonumber(candidate.distancePixels) or 0))
            local label = string.format("%s  ·  %d px",
                compactLabel(cutterPalletLabel(state, candidate.palletId), 28), distance)
            button(cutterCandidateRect(index), label, pointerX, pointerY,
                cutterButtonEnabled("load_pallet"), true)
        end
        button(CUTTER_UNLOADED_CONTROLS.load_stock,
            string.format("LOAD STOCK (%d)", math.max(0, math.floor(tonumber(view.genericSheets) or 0))),
            pointerX, pointerY, cutterButtonEnabled("load_stock")
                and (tonumber(view.genericSheets) or 0) > 0, true)
        button(CUTTER_UNLOADED_CONTROLS.set_barrier,
            view.barrierClear == true and "BLOCK BARRIER" or "CLEAR BARRIER",
            pointerX, pointerY, cutterButtonEnabled("set_barrier"), false)
        button(CUTTER_UNLOADED_CONTROLS.reset_safety, "RESET SAFETY",
            pointerX, pointerY, cutterButtonEnabled("reset_safety"), true)
        button(CUTTER_UNLOADED_CONTROLS.run_next_lift, "RUN NEXT LIFT",
            pointerX, pointerY, cutterButtonEnabled("run_next_lift"), true)
        button(CUTTER_UNLOADED_CONTROLS.emergency_stop, "E-STOP",
            pointerX, pointerY, cutterButtonEnabled("emergency_stop"), false)
        return
    end

    for index, rect in ipairs(CUTTER_PROGRAMS) do
        button(rect, "PROGRAM " .. index, pointerX, pointerY,
            cutterButtonEnabled("select_program"), tonumber(view.programIndex) == index)
    end
    local memory = {}
    for _, centi in ipairs(view.memoryCentiInch or {}) do
        memory[#memory + 1] = string.format("%.2f", (tonumber(centi) or 0) / 100)
    end
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.printf("P" .. tostring(tonumber(view.programIndex) or 1) .. " MEMORY  "
        .. (#memory > 0 and table.concat(memory, " / ") or "EMPTY"), 574, 208, 238, "right")

    love.graphics.setColor(Screen.gaugeFocused and 0.98 or 0.88, 0.96, 0.82)
    love.graphics.rectangle("fill", CUTTER_GAUGE_INPUT.x, CUTTER_GAUGE_INPUT.y,
        CUTTER_GAUGE_INPUT.width, CUTTER_GAUGE_INPUT.height, 4, 4)
    love.graphics.setColor(0.08, 0.10, 0.11)
    love.graphics.printf(Screen.gaugeText .. " in", CUTTER_GAUGE_INPUT.x,
        CUTTER_GAUGE_INPUT.y + 13, CUTTER_GAUGE_INPUT.width, "center")
    button(CUTTER_CONTROLS.gauge_set, "SET", pointerX, pointerY,
        cutterButtonEnabled("gauge_set"), true)
    button(CUTTER_CONTROLS.auto_gauge, "AUTO", pointerX, pointerY,
        cutterButtonEnabled("auto_gauge"), true)
    button(CUTTER_CONTROLS.save_gauge, "SAVE", pointerX, pointerY,
        cutterButtonEnabled("save_gauge"), true)
    button(CUTTER_CONTROLS.recall_gauge, "RECALL", pointerX, pointerY,
        cutterButtonEnabled("recall_gauge"), true)

    button(CUTTER_CONTROLS.rotate_paper, "ROTATE PAPER", pointerX, pointerY,
        cutterButtonEnabled("rotate_paper"), true)
    button(CUTTER_CONTROLS.position_paper, "POSITION PAPER", pointerX, pointerY,
        cutterButtonEnabled("position_paper"), true)
    button(CUTTER_CONTROLS.set_clamp, view.clamp == true and "RELEASE CLAMP" or "LOWER CLAMP",
        pointerX, pointerY, cutterButtonEnabled("set_clamp"), true)
    button(CUTTER_CONTROLS.set_barrier,
        view.barrierClear == true and "BLOCK BARRIER" or "CLEAR BARRIER",
        pointerX, pointerY, cutterButtonEnabled("set_barrier"), false)
    button(CUTTER_CONTROLS.reset_safety, "RESET SAFETY", pointerX, pointerY,
        cutterButtonEnabled("reset_safety"), true)
    button(CUTTER_CONTROLS.emergency_stop, "E-STOP", pointerX, pointerY,
        cutterButtonEnabled("emergency_stop"), false)
    button(CUTTER_CONTROLS.return_to_pallet, "RETURN TO PALLET", pointerX, pointerY,
        cutterButtonEnabled("return_to_pallet"), true)
    button(CUTTER_CONTROLS.run_next_lift, "RUN NEXT LIFT", pointerX, pointerY,
        cutterButtonEnabled("run_next_lift"), true)

    button(CUTTER_CONTROLS.cut_left, "CUT  ·  J",
        pointerX, pointerY, cutterButtonEnabled("cut_left"), false)
    button(CUTTER_CONTROLS.cut_right, "CUT  ·  K",
        pointerX, pointerY, cutterButtonEnabled("cut_right"), false)
end

function Screen.draw(state, pointerX, pointerY, assets)
    local titles = {
        reception_customer = { "REMOTE RECEPTION", "The host device owns the customer and verifies your quote" },
        office_computer = { "REMOTE OFFICE COMPUTER", "Shared shop records are live; transactions run on the host device" },
        skid_wrapper = { "REMOTE SKID WRAPPER", "The host device owns the machine cycle and saved pallet state" },
        cutter = { "REMOTE POLAR CUTTER", "The host device owns the blade cycle and saved paper state" },
    }
    local copy = titles[Screen.resourceId] or { "REMOTE WORKSHOP", "Host-authoritative console" }
    header(copy[1], copy[2], pointerX, pointerY, assets)
    if Screen.resourceId == "reception_customer" then drawCustomer(pointerX, pointerY)
    elseif Screen.resourceId == "office_computer" then drawComputer(state, pointerX, pointerY)
    elseif Screen.resourceId == "skid_wrapper" then drawWrapper(state, pointerX, pointerY)
    elseif Screen.resourceId == "cutter" then drawCutter(state, pointerX, pointerY) end
    love.graphics.setColor(0.18, 0.21, 0.22)
    love.graphics.printf(Screen.status, PANEL.x + 24, PANEL.y + PANEL.height - 30,
        PANEL.width - 48, "center")
end

function Screen.backCenter() return BACK.x + BACK.width / 2, BACK.y + BACK.height / 2 end
function Screen.confirmCenter() return CONFIRM.x + CONFIRM.width / 2, CONFIRM.y + CONFIRM.height / 2 end
function Screen.quoteInputCenter()
    return QUOTE_INPUT.x + QUOTE_INPUT.width / 2, QUOTE_INPUT.y + QUOTE_INPUT.height / 2
end
function Screen.rowCenter(index)
    local rect = rowRect(index)
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function Screen.cutterButtonCenter(action, value)
    local rect
    if action == "select_program" then
        rect = CUTTER_PROGRAMS[tonumber(value) or 1]
    elseif action == "load_pallet" then
        rect = cutterCandidateRect(tonumber(value) or 1)
    elseif action == "set_gauge" or action == "gauge_set" then
        rect = CUTTER_CONTROLS.gauge_set
    elseif (Screen.view and Screen.view.loaded) ~= true and CUTTER_UNLOADED_CONTROLS[action] then
        rect = CUTTER_UNLOADED_CONTROLS[action]
    else
        rect = CUTTER_CONTROLS[action]
    end
    if not rect then return nil end
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function Screen.buttonCenter(action, value)
    return Screen.cutterButtonCenter(action, value)
end

function Screen.cutterGaugeInputCenter()
    return CUTTER_GAUGE_INPUT.x + CUTTER_GAUGE_INPUT.width / 2,
        CUTTER_GAUGE_INPUT.y + CUTTER_GAUGE_INPUT.height / 2
end

function Screen.cutterCandidateCenter(index)
    local rect = cutterCandidateRect(index)
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

return Screen
