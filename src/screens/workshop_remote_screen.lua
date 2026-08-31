local BackButton = require("src.screens.back_button")
local Config = require("src.config")
local JobService = require("src.job_service")
local PressSetupGames = require("src.press_setup_games")
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
    windmillTab = "run",
    windmillJobId = nil,
    windmillPlateId = nil,
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

local WINDMILL_TAB_ORDER = { "run", "plates", "setup", "service" }
local WINDMILL_TABS = {
    run = { x = 112, y = 124, width = 172, height = 34 },
    plates = { x = 292, y = 124, width = 172, height = 34 },
    setup = { x = 472, y = 124, width = 172, height = 34 },
    service = { x = 652, y = 124, width = 176, height = 34 },
}

local WINDMILL_RUN_CONTROLS = {
    toggle_motor = { x = 112, y = 252, width = 116, height = 42 },
    toggle_feeder = { x = 236, y = 252, width = 116, height = 42 },
    toggle_impression = { x = 360, y = 252, width = 132, height = 42 },
    speed_down = { x = 500, y = 252, width = 92, height = 42 },
    speed_up = { x = 600, y = 252, width = 92, height = 42 },
    emergency_stop = { x = 700, y = 252, width = 128, height = 42 },
    reset_safety = { x = 112, y = 302, width = 120, height = 42 },
    take_proof = { x = 240, y = 302, width = 140, height = 42 },
    verify_artwork = { x = 388, y = 302, width = 140, height = 42 },
    approve_proof = { x = 536, y = 302, width = 140, height = 42 },
    run = { x = 684, y = 302, width = 144, height = 42 },
    clean_unload = { x = 112, y = 352, width = 220, height = 44 },
}

local WINDMILL_PLATE_CONTROLS = {
    order_plate = { x = 112, y = 430, width = 220, height = 46 },
    begin_plate = { x = 354, y = 430, width = 220, height = 46 },
    process_plate = { x = 596, y = 430, width = 232, height = 46 },
}

local WINDMILL_SERVICE_CONTROLS = {
    begin_service = { x = 180, y = 432, width = 280, height = 50 },
    book_technician = { x = 500, y = 432, width = 280, height = 50 },
    service_lockout = { x = 260, y = 338, width = 440, height = 58 },
    service_task = { x = 260, y = 338, width = 440, height = 72 },
}

local WINDMILL_SETUP_TASKS = { "chase", "packing", "rollers", "ink", "feeder", "register" }

local function windmillCandidateRect(index)
    return { x = 112, y = 430 + (index - 1) * 42, width = 716, height = 34 }
end

local function windmillPlateJobRect(index)
    return { x = 112, y = 184 + (index - 1) * 42, width = 220, height = 36 }
end

local function windmillPlateRect(index)
    return { x = 344, y = 184 + (index - 1) * 48, width = 484, height = 42 }
end

local function windmillSetupTaskRect(index)
    local column = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    return { x = 112 + column * 366, y = 198 + row * 82, width = 350, height = 64 }
end

local function windmillSetupControlRect(task, index)
    local controls = PressSetupGames.controls(task)
    local gap, totalWidth = 8, 716
    local width = math.floor((totalWidth - gap * (#controls - 1)) / math.max(1, #controls))
    return { x = 112 + (index - 1) * (width + gap), y = 350, width = width, height = 50 }
end

local WINDMILL_SETUP_CANCEL = { x = 330, y = 426, width = 300, height = 48 }

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

local function windmillRuntimeRevision(view)
    return type(view) == "table" and tonumber(view.runtimeRevision) or nil
end

local function mergeWindmillView(incoming)
    if type(incoming) ~= "table" then return false end
    local incomingRevision = windmillRuntimeRevision(incoming)
    local currentRevision = windmillRuntimeRevision(Screen.view) or -1
    if incomingRevision == nil or incomingRevision < currentRevision then return false end
    local merged = {}
    for key, value in pairs(incoming) do merged[key] = value end
    Screen.view = merged
    return true
end

local function windmillResourceRevision(snapshot)
    local direct = tonumber(snapshot.resourceRevision)
    if direct then return direct end
    local windmill = snapshot.windmill or snapshot.view or snapshot.data
    direct = type(windmill) == "table" and tonumber(windmill.resourceRevision) or nil
    if direct then return direct end
    for _, record in ipairs(snapshot.resources or {}) do
        if record.resourceId == "windmill" then return tonumber(record.revision) end
    end
    return nil
end

local function windmillCandidates()
    local rows = {}
    for _, candidate in ipairs((Screen.view and Screen.view.candidates) or {}) do
        rows[#rows + 1] = candidate
        if #rows >= 3 then break end
    end
    return rows
end

local function windmillPressJobs(state)
    local rows = {}
    for _, job in ipairs((state and state.jobs and state.jobs.active) or {}) do
        if type(job.press) == "table" then
            rows[#rows + 1] = job
            if #rows >= 5 then break end
        end
    end
    return rows
end

local function windmillSelectedJob(state)
    local jobs = windmillPressJobs(state)
    local selected
    for _, job in ipairs(jobs) do
        if job.id == Screen.windmillJobId then selected = job; break end
    end
    selected = selected or jobs[1]
    Screen.windmillJobId = selected and selected.id or nil
    return selected, jobs
end

local function windmillSelectedPlate(state)
    local job, jobs = windmillSelectedJob(state)
    local plates = job and job.press and job.press.plates or {}
    local selected
    for _, plate in ipairs(plates) do
        if plate.id == Screen.windmillPlateId then selected = plate; break end
    end
    selected = selected or plates[1]
    Screen.windmillPlateId = selected and selected.id or nil
    return selected, plates, job, jobs
end

local function windmillSetupComplete(view)
    for _, score in ipairs((view and view.setupPermille) or {}) do
        if (tonumber(score) or 0) <= 0 then return false end
    end
    return type(view and view.setupPermille) == "table" and #view.setupPermille == 6
end

local function windmillActivePlateReady(state, view)
    if not view or not view.jobId or not view.colorIndex then return false end
    for _, job in ipairs((state and state.jobs and state.jobs.active) or {}) do
        if job.id == view.jobId then
            local plate = job.press and job.press.plates and job.press.plates[view.colorIndex]
            return type(plate) == "table" and plate.status == "ready"
                and plate.mounted == true and (tonumber(plate.life) or 0) > 0
        end
    end
    return false
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
    local incomingView = grant and (grant.view or grant.data) or nil
    Screen.view = nil
    if Screen.resourceId == "windmill" then
        mergeWindmillView(incomingView)
    else
        Screen.view = incomingView
    end
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
    Screen.windmillTab = "run"
    Screen.windmillJobId, Screen.windmillPlateId = nil, nil
    syncCutterGauge(true)
    if state then state.screen = "workshop_remote" end
    return Screen.resourceId ~= nil and Screen.leaseId ~= nil
end

function Screen.clear()
    Screen.resourceId, Screen.leaseId, Screen.view = nil, nil, nil
    Screen.quoteFocused, Screen.waiting, Screen.safetyWaiting = false, false, false
    Screen.selectedJobId, Screen.selectedPalletId = nil, nil
    Screen.gaugeFocused, Screen.gaugeReplaceOnType = false, true
    Screen.windmillTab = "run"
    Screen.windmillJobId, Screen.windmillPlateId = nil, nil
    Screen.workshopTick = 0
end

function Screen.isOpen() return Screen.resourceId ~= nil and Screen.leaseId ~= nil end
function Screen.canClose()
    return not Screen.waiting and not Screen.safetyWaiting
        and (Screen.resourceId ~= "skid_wrapper" or Wrapper.step ~= "wrapping")
        and (Screen.resourceId ~= "windmill"
            or not Screen.view or Screen.view.status ~= "production")
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
    local priorRevision = Screen.revision
    local resultRevision = tonumber(result.revision)
    local resourceCurrent = resultRevision ~= nil and resultRevision >= priorRevision
    Screen.revision = math.max(priorRevision, resultRevision or priorRevision)
    Screen.status = tostring(result.message or (result.accepted and "Action completed." or "Action rejected."))
    if Screen.resourceId == "cutter" then
        mergeCutterView(result.view or result.data)
    elseif Screen.resourceId == "windmill" then
        if resourceCurrent then mergeWindmillView(result.view or result.data) end
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
    elseif Screen.resourceId == "windmill" then
        local resourceRevision = windmillResourceRevision(snapshot)
        if resourceRevision and resourceRevision >= Screen.revision then
            local windmill = snapshot.windmill
            if windmill == nil or mergeWindmillView(windmill) then
                Screen.revision = resourceRevision
            end
        end
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

function Screen.applyWindmillSnapshot(snapshot)
    if Screen.resourceId ~= "windmill" or type(snapshot) ~= "table" then return false end
    local resourceRevision = windmillResourceRevision(snapshot)
    if resourceRevision == nil or resourceRevision < Screen.revision then return false end
    local windmill = snapshot.view or snapshot.windmill or snapshot.data
    if type(windmill) ~= "table" or not mergeWindmillView(windmill) then return false end
    Screen.revision = resourceRevision
    return true
end

local function urgentWorkshopSafety(action, args)
    if action == "emergency_stop" then
        return Screen.resourceId == "cutter" or Screen.resourceId == "windmill"
    end
    return Screen.resourceId == "cutter" and action == "set_barrier"
        and type(args) == "table" and args.barrierClear == false
end

local function request(sendCommand, action, args)
    args = args or {}
    local urgentSafety = urgentWorkshopSafety(action, args)
    if Screen.safetyWaiting or (Screen.waiting and not urgentSafety) then return false end
    if type(sendCommand) ~= "function" then
        Screen.status = "The remote console is not connected to the host command channel."
        return true
    end
    local ok, errorMessage = sendCommand(action, args)
    if ok then
        if urgentSafety then
            Screen.safetyWaiting = true
            Screen.status = Screen.resourceId == "windmill"
                and "Urgent Windmill safety action sent to the host device..."
                or "Urgent cutter safety action sent to the host device..."
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

local windmillButtonEnabled

function Screen.keypressed(key, state, sendCommand)
    key = string.lower(tostring(key or ""))
    if Screen.resourceId == "windmill" then
        local view = Screen.view or {}
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
            if windmillButtonEnabled and windmillButtonEnabled(action, state) then
                return request(sendCommand, action, {})
            end
            Screen.status = "The Windmill is not ready for that control."
            return true
        end
        return false
    end
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

windmillButtonEnabled = function(action, state)
    local view = Screen.view or {}
    if Screen.safetyWaiting then return false end
    if Screen.waiting then return action == "emergency_stop" end
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
            and windmillActivePlateReady(state, view) and windmillSetupComplete(view)
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
        local plate = windmillSelectedPlate(state)
        if not plate then return false end
        if action == "process_plate" then return plate.status == "processing" end
        return plate.status == "unprepared"
    end
    return false
end

local function windmillMousepressed(state, x, y, sendCommand)
    for _, tab in ipairs(WINDMILL_TAB_ORDER) do
        if contains(WINDMILL_TABS[tab], x, y) then
            Screen.windmillTab = tab
            Screen.status = tab:sub(1, 1):upper() .. tab:sub(2) .. " controls opened."
            return true
        end
    end

    local view = Screen.view or {}
    if Screen.windmillTab == "run" then
        if view.status == "idle" then
            for index, candidate in ipairs(windmillCandidates()) do
                if contains(windmillCandidateRect(index), x, y) then
                    return windmillButtonEnabled("load_pallet", state)
                        and request(sendCommand, "load_pallet", { palletId = candidate.palletId }) or true
                end
            end
        end
        for action, rect in pairs(WINDMILL_RUN_CONTROLS) do
            if contains(rect, x, y) then
                local command = action
                if action == "run" then
                    command = view.status == "production" and "stop_run" or "start_run"
                end
                return windmillButtonEnabled(command, state)
                    and request(sendCommand, command, {}) or true
            end
        end
    elseif Screen.windmillTab == "plates" then
        local selected, plates, _, jobs = windmillSelectedPlate(state)
        for index, job in ipairs(jobs) do
            if contains(windmillPlateJobRect(index), x, y) then
                Screen.windmillJobId, Screen.windmillPlateId = job.id, nil
                windmillSelectedPlate(state)
                Screen.status = "Selected plate job " .. tostring(job.id) .. "."
                return true
            end
        end
        for index, plate in ipairs(plates) do
            if contains(windmillPlateRect(index), x, y) then
                Screen.windmillPlateId = plate.id
                Screen.status = "Selected " .. tostring(plate.id) .. "."
                return true
            end
        end
        for action, rect in pairs(WINDMILL_PLATE_CONTROLS) do
            if contains(rect, x, y) then
                if not selected or not windmillButtonEnabled(action, state) then return true end
                return request(sendCommand, action, { plateId = selected.id })
            end
        end
    elseif Screen.windmillTab == "setup" then
        if view.setupTask then
            if contains(WINDMILL_SETUP_CANCEL, x, y) then
                return windmillButtonEnabled("cancel_setup", state)
                    and request(sendCommand, "cancel_setup", {}) or true
            end
            for index, control in ipairs(PressSetupGames.controls(view.setupTask)) do
                if contains(windmillSetupControlRect(view.setupTask, index), x, y) then
                    return windmillButtonEnabled("setup_action", state)
                        and request(sendCommand, "setup_action", { setupAction = control[1] }) or true
                end
            end
        else
            for index, task in ipairs(WINDMILL_SETUP_TASKS) do
                if contains(windmillSetupTaskRect(index), x, y) then
                    return windmillButtonEnabled("begin_setup", state)
                        and request(sendCommand, "begin_setup", { setupTask = task }) or true
                end
            end
        end
    elseif Screen.windmillTab == "service" then
        local step = tostring(view.serviceStep or "idle")
        if step == "idle" then
            if contains(WINDMILL_SERVICE_CONTROLS.begin_service, x, y) then
                return windmillButtonEnabled("begin_service", state)
                    and request(sendCommand, "begin_service", {}) or true
            elseif contains(WINDMILL_SERVICE_CONTROLS.book_technician, x, y) then
                return windmillButtonEnabled("book_technician", state)
                    and request(sendCommand, "book_technician", {}) or true
            end
        elseif step == "task" then
            if contains(WINDMILL_SERVICE_CONTROLS.service_task, x, y) then
                return windmillButtonEnabled("service_task", state)
                    and request(sendCommand, "service_task", {}) or true
            end
        elseif contains(WINDMILL_SERVICE_CONTROLS.service_lockout, x, y) then
            return windmillButtonEnabled("service_lockout", state)
                and request(sendCommand, "service_lockout", {}) or true
        end
    end
    return false
end

function Screen.mousepressed(state, x, y, button, sendCommand)
    if button ~= 1 or not Screen:isOpen() then return false end
    if contains(BACK, x, y) then
        if Screen.canClose() then return { action = "close" } end
        if Screen.resourceId == "windmill" and Screen.view
            and Screen.view.status == "production"
        then
            Screen.status = "Stop the production run before closing the remote Windmill console."
        end
        return true
    end
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
    elseif Screen.resourceId == "windmill" then
        return windmillMousepressed(state, x, y, sendCommand)
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

local function drawWindmillTabs(pointerX, pointerY)
    for _, tab in ipairs(WINDMILL_TAB_ORDER) do
        button(WINDMILL_TABS[tab], tab:upper(), pointerX, pointerY, true,
            Screen.windmillTab == tab)
    end
end

local function drawWindmillRun(state, pointerX, pointerY)
    local view = Screen.view or {}
    local proof = view.proofPermille and string.format("%d%%",
        math.floor((tonumber(view.proofPermille) or 0) / 10 + 0.5)) or "NOT PULLED"
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print("STATUS  " .. tostring(view.status or "idle"):gsub("_", " "):upper(), 112, 170)
    love.graphics.printf(string.format("SPEED  %d IPH", tonumber(view.speed) or 3000), 592, 170, 236, "right")
    love.graphics.print("JOB  " .. tostring(view.jobId or "NO PALLET LOADED"), 112, 194)
    love.graphics.printf(string.format("COLOR  %s / %s", tostring(view.colorIndex or "—"),
        tostring(view.colorCount or "—")), 592, 194, 236, "right")
    love.graphics.print(string.format("COUNTER  %d   GOOD  %d / %d   SPOIL  %d",
        tonumber(view.counter) or 0, tonumber(view.goodSheets) or 0,
        tonumber(view.targetSheets) or 0, tonumber(view.spoilage) or 0), 112, 218)
    love.graphics.printf(string.format("FEED  %d / %d   PROOF  %s",
        tonumber(view.feedRemaining) or 0, tonumber(view.feedStart) or 0, proof),
        468, 218, 360, "right")
    if view.warning then
        love.graphics.setColor(0.78, 0.24, 0.18)
        love.graphics.printf(tostring(view.warning), 112, 235, 716, "center")
    end

    button(WINDMILL_RUN_CONTROLS.toggle_motor, view.motor and "STOP MOTOR" or "START MOTOR",
        pointerX, pointerY, windmillButtonEnabled("toggle_motor", state), true)
    button(WINDMILL_RUN_CONTROLS.toggle_feeder, view.feeder and "FEEDER OFF" or "FEEDER ON",
        pointerX, pointerY, windmillButtonEnabled("toggle_feeder", state), true)
    button(WINDMILL_RUN_CONTROLS.toggle_impression,
        view.impression and "IMPRESSION OFF" or "IMPRESSION ON",
        pointerX, pointerY, windmillButtonEnabled("toggle_impression", state), true)
    button(WINDMILL_RUN_CONTROLS.speed_down, "SPEED −", pointerX, pointerY,
        windmillButtonEnabled("speed_down", state), true)
    button(WINDMILL_RUN_CONTROLS.speed_up, "SPEED +", pointerX, pointerY,
        windmillButtonEnabled("speed_up", state), true)
    button(WINDMILL_RUN_CONTROLS.emergency_stop, "E-STOP", pointerX, pointerY,
        windmillButtonEnabled("emergency_stop", state), false)
    button(WINDMILL_RUN_CONTROLS.reset_safety, "RESET", pointerX, pointerY,
        windmillButtonEnabled("reset_safety", state), true)
    button(WINDMILL_RUN_CONTROLS.take_proof, "PULL PROOF", pointerX, pointerY,
        windmillButtonEnabled("take_proof", state), true)
    button(WINDMILL_RUN_CONTROLS.verify_artwork,
        view.artworkVerified and "ART VERIFIED" or "VERIFY ART", pointerX, pointerY,
        windmillButtonEnabled("verify_artwork", state), true)
    button(WINDMILL_RUN_CONTROLS.approve_proof,
        view.proofApproved and "APPROVED" or "APPROVE", pointerX, pointerY,
        windmillButtonEnabled("approve_proof", state), true)
    local runAction = view.status == "production" and "stop_run" or "start_run"
    button(WINDMILL_RUN_CONTROLS.run, view.status == "production" and "STOP RUN" or "START RUN",
        pointerX, pointerY, windmillButtonEnabled(runAction, state), true)
    button(WINDMILL_RUN_CONTROLS.clean_unload, "CLEAN + UNLOAD", pointerX, pointerY,
        windmillButtonEnabled("clean_unload", state), true)

    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print(view.status == "idle" and "PRINT-READY PALLETS" or "ACTIVE PRESS PASS",
        112, 408)
    if view.status == "idle" then
        local candidates = windmillCandidates()
        if #candidates == 0 then
            love.graphics.setColor(0.40, 0.42, 0.43)
            love.graphics.printf("Stage cut stock beside the press and prepare its mounted plate.",
                112, 456, 716, "center")
        end
        for index, candidate in ipairs(candidates) do
            local label = string.format("LOAD %s  ·  COLOR %d",
                compactLabel(cutterPalletLabel(state, candidate.palletId), 44),
                tonumber(candidate.colorIndex) or 1)
            button(windmillCandidateRect(index), label, pointerX, pointerY,
                windmillButtonEnabled("load_pallet", state), true)
        end
    else
        love.graphics.setColor(0.40, 0.42, 0.43)
        love.graphics.printf(tostring(view.palletId or "The host owns the active pallet."),
            112, 448, 716, "center")
    end
end

local function drawWindmillPlates(state, pointerX, pointerY)
    local selected, plates, job, jobs = windmillSelectedPlate(state)
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print("ACTIVE PRINT JOBS", 112, 164)
    love.graphics.print("JOB PLATES", 344, 164)
    if #jobs == 0 then
        love.graphics.setColor(0.40, 0.42, 0.43)
        love.graphics.printf("No active Windmill jobs require plates.", 112, 260, 716, "center")
        return
    end
    for index, item in ipairs(jobs) do
        button(windmillPlateJobRect(index), compactLabel(tostring(item.id), 24), pointerX, pointerY,
            not Screen.waiting, item.id == Screen.windmillJobId)
    end
    for index, plate in ipairs(plates) do
        if index > 4 then break end
        local quality = math.floor((tonumber(plate.quality) or 0) * 100 + 0.5)
        local label = string.format("%s  ·  %s  ·  %d%%  ·  %s",
            compactLabel(plate.id, 25), tostring(plate.status or "unprepared"):upper(), quality,
            plate.mounted and "MOUNTED" or tostring(plate.inkColor or "INK"))
        button(windmillPlateRect(index), label, pointerX, pointerY, not Screen.waiting,
            plate.id == Screen.windmillPlateId)
    end
    if not selected then return end
    button(WINDMILL_PLATE_CONTROLS.order_plate, "ORDER PROCESSED PLATE", pointerX, pointerY,
        windmillButtonEnabled("order_plate", state), true)
    button(WINDMILL_PLATE_CONTROLS.begin_plate, "START IN-HOUSE PLATE", pointerX, pointerY,
        windmillButtonEnabled("begin_plate", state), true)
    local processNames = { "EXPOSE", "WASH", "DRY", "MOUNT" }
    local processLabel = processNames[math.max(1, math.min(4,
        math.floor(tonumber(selected.processStep) or 1)))]
    button(WINDMILL_PLATE_CONTROLS.process_plate, "TIME + LOCK " .. processLabel,
        pointerX, pointerY, windmillButtonEnabled("process_plate", state), true)

    love.graphics.setColor(0.18, 0.21, 0.22)
    love.graphics.rectangle("fill", 112, 508, 716, 24, 3, 3)
    love.graphics.setColor(0.18, 0.58, 0.29)
    love.graphics.rectangle("fill", 112 + 716 * 0.58, 508, 716 * 0.18, 24, 3, 3)
    local marker = math.max(0, math.min(1000,
        tonumber(Screen.view and Screen.view.plateMarkerPermille) or 0)) / 1000
    love.graphics.setColor(0.92, 0.72, 0.20)
    love.graphics.rectangle("fill", 108 + 716 * marker, 502, 8, 36)
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.printf("Lock the host-timed marker inside the green quality window.",
        112, 544, 716, "center")
    if job then
        love.graphics.printf(compactLabel(tostring(job.company or job.id), 56), 112, 570, 716, "center")
    end
end

local function drawWindmillSetup(state, pointerX, pointerY)
    local view = Screen.view or {}
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.printf("Host-verified chase, packing, roller, ink, feeder, and register checks",
        112, 170, 716, "center")
    if view.setupTask then
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.printf(tostring(view.setupTask):upper() .. " SETUP", 112, 218, 716, "center")
        love.graphics.setColor(0.40, 0.42, 0.43)
        love.graphics.printf(tostring(view.setupSummary or "Use the controls to finish this check."),
            112, 260, 716, "center")
        for index, control in ipairs(PressSetupGames.controls(view.setupTask)) do
            button(windmillSetupControlRect(view.setupTask, index), control[2], pointerX, pointerY,
                windmillButtonEnabled("setup_action", state), true)
        end
        button(WINDMILL_SETUP_CANCEL, "CANCEL SETUP", pointerX, pointerY,
            windmillButtonEnabled("cancel_setup", state), false)
        return
    end
    for index, task in ipairs(WINDMILL_SETUP_TASKS) do
        local score = tonumber((view.setupPermille or {})[index]) or 0
        local label = task:upper() .. "\n" .. (score > 0
            and string.format("COMPLETE %d%%", math.floor(score / 10 + 0.5)) or "BEGIN CHECK")
        button(windmillSetupTaskRect(index), label, pointerX, pointerY,
            windmillButtonEnabled("begin_setup", state), score > 0)
    end
    if not view.palletId then
        love.graphics.setColor(0.40, 0.42, 0.43)
        love.graphics.printf("Load a print-ready pallet from RUN before beginning setup.",
            112, 470, 716, "center")
    end
end

local function drawWindmillService(state, pointerX, pointerY)
    local view = Screen.view or {}
    local machine
    for _, item in ipairs(state and state.machines and state.machines.items or {}) do
        if item.modelId == "heidelberg_10x15" and item.status == "installed" then machine = item; break end
    end
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.printf(string.format("MACHINE CONDITION  %d%%   ·   MAINTENANCE KITS  %d",
        tonumber(machine and machine.condition) or 0,
        tonumber(state and state.inventory and state.inventory.stock
            and state.inventory.stock.maintenance_kit) or 0), 112, 176, 716, "center")
    love.graphics.setColor(0.18, 0.21, 0.22)
    love.graphics.rectangle("fill", 160, 224, 640, 20, 3, 3)
    love.graphics.setColor(0.18, 0.58, 0.29)
    love.graphics.rectangle("fill", 160, 224, 640 * math.max(0, math.min(1000,
        tonumber(view.servicePermille) or 0)) / 1000, 20, 3, 3)
    local step = tostring(view.serviceStep or "idle")
    if step == "idle" then
        love.graphics.setColor(0.40, 0.42, 0.43)
        love.graphics.printf("Routine service requires an idle, unloaded press and one maintenance kit.",
            112, 300, 716, "center")
        button(WINDMILL_SERVICE_CONTROLS.begin_service, "BEGIN LOCKOUT + SERVICE",
            pointerX, pointerY, windmillButtonEnabled("begin_service", state), true)
        button(WINDMILL_SERVICE_CONTROLS.book_technician, "BOOK TECHNICIAN  $350",
            pointerX, pointerY, windmillButtonEnabled("book_technician", state), true)
    elseif step == "task" then
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.printf(tostring(view.serviceTask or "Inspect and service the active component."),
            160, 282, 640, "center")
        button(WINDMILL_SERVICE_CONTROLS.service_task, "COMPLETE INTERACTIVE CHECK",
            pointerX, pointerY, windmillButtonEnabled("service_task", state), true)
    else
        local labels = {
            lockout_disconnect = "1. DISCONNECT POWER",
            lockout_key = "2. REMOVE + KEEP KEY",
            lockout_tag = "3. ATTACH LOCKOUT TAG",
        }
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.printf("Complete energy isolation in the host-verified order.",
            160, 282, 640, "center")
        button(WINDMILL_SERVICE_CONTROLS.service_lockout, labels[step] or "ADVANCE LOCKOUT",
            pointerX, pointerY, windmillButtonEnabled("service_lockout", state), true)
    end
end

local function drawWindmill(state, pointerX, pointerY)
    drawWindmillTabs(pointerX, pointerY)
    if Screen.windmillTab == "run" then drawWindmillRun(state, pointerX, pointerY)
    elseif Screen.windmillTab == "plates" then drawWindmillPlates(state, pointerX, pointerY)
    elseif Screen.windmillTab == "setup" then drawWindmillSetup(state, pointerX, pointerY)
    else drawWindmillService(state, pointerX, pointerY) end
end

function Screen.draw(state, pointerX, pointerY, assets)
    local titles = {
        reception_customer = { "REMOTE RECEPTION", "The host device owns the customer and verifies your quote" },
        office_computer = { "REMOTE OFFICE COMPUTER", "Shared shop records are live; transactions run on the host device" },
        skid_wrapper = { "REMOTE SKID WRAPPER", "The host device owns the machine cycle and saved pallet state" },
        cutter = { "REMOTE POLAR CUTTER", "The host device owns the blade cycle and saved paper state" },
        windmill = { "REMOTE HEIDELBERG WINDMILL", "The host device owns press safety, production, and saved paper state" },
    }
    local copy = titles[Screen.resourceId] or { "REMOTE WORKSHOP", "Host-authoritative console" }
    header(copy[1], copy[2], pointerX, pointerY, assets)
    if Screen.resourceId == "reception_customer" then drawCustomer(pointerX, pointerY)
    elseif Screen.resourceId == "office_computer" then drawComputer(state, pointerX, pointerY)
    elseif Screen.resourceId == "skid_wrapper" then drawWrapper(state, pointerX, pointerY)
    elseif Screen.resourceId == "cutter" then drawCutter(state, pointerX, pointerY)
    elseif Screen.resourceId == "windmill" then drawWindmill(state, pointerX, pointerY) end
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

function Screen.windmillButtonCenter(action, value)
    local rect
    if action == "load_pallet" then
        local index = tonumber(value)
        if not index and value ~= nil then
            for candidateIndex, candidate in ipairs(windmillCandidates()) do
                if candidate.palletId == value then index = candidateIndex; break end
            end
        end
        rect = windmillCandidateRect(index or 1)
    elseif action == "start_run" or action == "stop_run" or action == "run" then
        rect = WINDMILL_RUN_CONTROLS.run
    elseif action == "begin_setup" then
        local index = tonumber(value)
        if not index and value ~= nil then
            for taskIndex, task in ipairs(WINDMILL_SETUP_TASKS) do
                if task == value then index = taskIndex; break end
            end
        end
        rect = windmillSetupTaskRect(index or 1)
    elseif action == "setup_action" then
        local task = Screen.view and Screen.view.setupTask
        if not task then return nil end
        local controls = PressSetupGames.controls(task)
        local index = tonumber(value)
        if not index and value ~= nil then
            for controlIndex, control in ipairs(controls) do
                if control[1] == value then index = controlIndex; break end
            end
        end
        if #controls > 0 then rect = windmillSetupControlRect(task, index or 1) end
    elseif action == "cancel_setup" then
        rect = WINDMILL_SETUP_CANCEL
    elseif action == "select_job" or action == "select_plate_job" then
        rect = windmillPlateJobRect(tonumber(value) or 1)
    elseif action == "select_plate" then
        rect = windmillPlateRect(tonumber(value) or 1)
    else
        rect = WINDMILL_RUN_CONTROLS[action]
            or WINDMILL_PLATE_CONTROLS[action]
            or WINDMILL_SERVICE_CONTROLS[action]
    end
    if not rect then return nil end
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function Screen.windmillTabCenter(tab)
    local rect = WINDMILL_TABS[tab]
    if not rect then return nil end
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function Screen.buttonCenter(action, value)
    if Screen.resourceId == "windmill" then
        return Screen.windmillButtonCenter(action, value)
    end
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
