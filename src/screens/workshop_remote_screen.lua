local BackButton = require("src.screens.back_button")
local Config = require("src.config")
local CutterPresentation = require("src.screens.cutter_presentation")
local MachineScreen = require("src.screens.machine_screen")
local JobService = require("src.job_service")
local MachineFleet = require("src.machine_fleet")
local MachineResource = require("src.machine_resource_id")
local PressSetupGames = require("src.press_setup_games")
local Ui = require("src.screens.ui")
local Wrapper = require("src.wrapper")
local WorkPhoneScreen = require("src.screens.work_phone_screen")
local ComputerScreen = require("src.screens.computer_screen")
local Projection = require("src.screens.gui_projection")
local OfficeIntent = require("src.office_intent")
local SharedMachineGui = require("src.screens.shared_machine_gui")
local SharedPressGui = require("src.screens.shared_press_gui")
local VendorScreen = require("src.screens.vendor_screen")
local JobOfferScreen = require("src.screens.job_offer_screen")
local TruckScreen = require("src.screens.truck_inventory_screen")
local request
local utf8 = require("utf8")

local Screen = {
    resourceId = nil,
    leaseResourceId = nil,
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
    cutterTab = "production",
    cutterPresentation = CutterPresentation.new(),
    wrapperTab = "production",
    wrapperClock = 0,
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
local TRUCK_PREVIOUS = { x = 142, y = 372, width = 150, height = 42 }
local TRUCK_NEXT = { x = 668, y = 372, width = 150, height = 42 }

local WRAPPER_TABS = {
    production = { x = 142, y = 124, width = 328, height = 34 },
    service = { x = 490, y = 124, width = 328, height = 34 },
}
local WRAPPER_SERVICE_BEGIN = { x = 250, y = 472, width = 460, height = 58 }
local WRAPPER_SERVICE_CANCEL = { x = 142, y = 548, width = 174, height = 40 }
local WRAPPER_SERVICE_WORK = { x = 142, y = 202, width = 476, height = 294 }

local CUTTER_SCENE = { x = 464, y = 120, width = 364, height = 243 }
local CUTTER_GAUGE_INPUT = { x = 122, y = 230, width = 106, height = 42 }
local CUTTER_CONTROLS = {
    gauge_set = { x = 236, y = 230, width = 78, height = 42 },
    auto_gauge = { x = 322, y = 230, width = 100, height = 42 },
    save_gauge = { x = 122, y = 280, width = 144, height = 42 },
    recall_gauge = { x = 278, y = 280, width = 144, height = 42 },
    rotate_paper = { x = 122, y = 374, width = 222, height = 44 },
    position_paper = { x = 356, y = 374, width = 222, height = 44 },
    set_clamp = { x = 590, y = 374, width = 222, height = 44 },
    set_barrier = { x = 122, y = 424, width = 222, height = 44 },
    reset_safety = { x = 356, y = 424, width = 222, height = 44 },
    emergency_stop = { x = 590, y = 424, width = 222, height = 44 },
    return_to_pallet = { x = 122, y = 474, width = 339, height = 42 },
    run_next_lift = { x = 473, y = 474, width = 339, height = 42 },
    cut_left = { x = 122, y = 526, width = 339, height = 62 },
    cut_right = { x = 473, y = 526, width = 339, height = 62 },
    load_stock = { x = 298, y = 354, width = 338, height = 46 },
}

local CUTTER_UNLOADED_CONTROLS = {
    load_stock = { x = 122, y = 374, width = 222, height = 44 },
    set_barrier = { x = 356, y = 374, width = 222, height = 44 },
    reset_safety = { x = 590, y = 374, width = 222, height = 44 },
    run_next_lift = { x = 122, y = 430, width = 456, height = 48 },
    emergency_stop = { x = 590, y = 430, width = 222, height = 48 },
}

local CUTTER_PROGRAMS = {
    { x = 122, y = 182, width = 68, height = 40 },
    { x = 200, y = 182, width = 68, height = 40 },
    { x = 278, y = 182, width = 68, height = 40 },
    { x = 356, y = 182, width = 68, height = 40 },
}

local CUTTER_SERVICE_NAV = { x = 638, y = 548, width = 174, height = 40 }
local CUTTER_SERVICE_CONTROLS = {
    lubrication = { x = 122, y = 210, width = 324, height = 54 },
    blade = { x = 488, y = 210, width = 324, height = 54 },
    technician = { x = 122, y = 292, width = 324, height = 54 },
    weekly = { x = 488, y = 292, width = 324, height = 54 },
    advance = { x = 222, y = 286, width = 516, height = 66 },
    pump = { x = 122, y = 430, width = 210, height = 48 },
    gear = { x = 350, y = 430, width = 210, height = 48 },
    finish = { x = 578, y = 430, width = 234, height = 48 },
    cancel = { x = 122, y = 548, width = 174, height = 40 },
    bladeAction = { x = 250, y = 360, width = 460, height = 60 },
}

local CUTTER_SERVICE_VIEWS = { "REAR", "FRONT", "SIDE", "GEAR", "CENTRAL" }
local CUTTER_SERVICE_TOOLS = { "RAG", "GREASE", "INSPECT", "GEAR OIL" }

local function cutterServiceViewRect(index)
    return { x = 122 + (index - 1) * 140, y = 200, width = 128, height = 38 }
end

local function cutterServiceToolRect(index)
    return { x = 122 + (index - 1) * 175, y = 252, width = 162, height = 38 }
end

local function cutterServiceItemRect(index)
    return { x = 122, y = 310 + (index - 1) * 52, width = 690, height = 44 }
end

local function cutterBladeBoltRect(index)
    return { x = 162 + (index - 1) * 170, y = 260, width = 126, height = 54 }
end

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
    return {
        x = 122,
        y = 206 + (index - 1) * 50,
        width = 318,
        height = 44,
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

local WRAPPER_SERVICE_COPY = {
    turntableBearing = {
        component = "TURNTABLE BEARING",
        instruction = "Grease the three bearing fittings around the turntable in order.",
        points = { { 300, 346 }, { 420, 408 }, { 538, 344 } },
    },
    filmCarriage = {
        component = "FILM CARRIAGE",
        instruction = "Follow the carriage service points from the upper roller to the lower guide.",
        points = { { 404, 224 }, { 404, 316 }, { 404, 408 } },
    },
    driveBelt = {
        component = "DRIVE BELT",
        instruction = "Tap the moving tension marker as it crosses the service bay.",
    },
    controlBoard = {
        component = "CONTROL BOARD",
        instruction = "Test the cabinet points in order: power, safety loop, then reset.",
        points = { { 470, 234 }, { 520, 322 }, { 556, 410 } },
    },
}

local function wrapperServiceTarget(view)
    local task = WRAPPER_SERVICE_COPY[tostring(view and view.serviceTaskId or "")]
    local phase = math.max(1, math.floor(tonumber(view and view.servicePhase) or 1))
    if not task then return nil end
    local x, y
    if view.serviceTaskId == "driveBelt" then
        x = 380 + math.sin((Screen.wrapperClock or 0) * 1.8) * 150
        y = 376
    else
        local point = task.points and task.points[phase]
        if point then x, y = point[1], point[2] end
    end
    if not x or not y then return nil end
    return { x = x - 30, y = y - 30, width = 60, height = 60 }, task
end

local function mergeWrapperView(incoming)
    if type(incoming) ~= "table" then return false end
    local merged = Screen.view or {}
    for key, value in pairs(incoming) do merged[key] = value end
    if incoming.serviceStep == nil then
        for _, field in ipairs({
            "serviceStep", "serviceTaskId", "serviceTaskIndex", "serviceTaskCount",
            "servicePhase", "serviceTargetCount", "serviceAttempts", "serviceMisses",
            "servicePermille",
        }) do
            merged[field] = nil
        end
    end
    Screen.view = merged
    Screen.selectedPalletId = incoming.selectedPalletId
    return true
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
    if incoming.serviceStep == nil then
        for _, field in ipairs({
            "serviceStep", "servicePermille", "serviceView", "serviceTool",
            "serviceItems", "centralInstalled", "gearInspected", "gearLevelPermille",
            "bladeBoltsDone", "bladeBoltMask",
        }) do
            merged[field] = nil
        end
    end
    if incoming.paper ~= nil then
        merged.candidates, merged.genericSheets = nil, nil
    elseif incoming.loaded == false then
        merged.paper = nil
        if incoming.candidates ~= nil and incoming.genericSheets == nil then
            merged.genericSheets = nil
        end
    end
    Screen.view = merged
    Screen.cutterPresentation:accept(merged)
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

local function wrapperRowRect(index)
    return { x = ROW_X, y = 214 + (index - 1) * (ROW_H + 4), width = ROW_W, height = ROW_H }
end

local function vendorBuyRect(index)
    local itemRow = rowRect(index)
    return {
        x = itemRow.x + itemRow.width - 146,
        y = itemRow.y + 5,
        width = 132,
        height = itemRow.height - 10,
    }
end

local function vendorRows()
    local rows = {}
    for _, item in ipairs((Screen.view and Screen.view.items) or {}) do
        rows[#rows + 1] = item
        if #rows >= 5 then break end
    end
    return rows
end

function Screen.enter(grant, state)
    Screen.leaseResourceId = grant and grant.resourceId or nil
    Screen.resourceId = MachineResource.parse(Screen.leaseResourceId)
        or Screen.leaseResourceId
    Screen.leaseId = grant and grant.leaseId or nil
    Screen.revision = tonumber(grant and grant.revision) or 0
    Screen.workshopTick = 0
    local incomingView = grant and (grant.view or grant.data) or nil
    Screen.view = nil
    if Screen.resourceId == "windmill" then
        mergeWindmillView(incomingView)
    elseif Screen.resourceId == "skid_wrapper" then
        mergeWrapperView(incomingView)
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
    Screen.cutterTab = "production"
    Screen.cutterPresentation = CutterPresentation.new()
    if Screen.resourceId == "cutter" then Screen.cutterPresentation:accept(Screen.view) end
    Screen.wrapperTab = "production"
    Screen.wrapperClock = 0
    Screen.windmillTab = "run"
    Screen.windmillJobId, Screen.windmillPlateId = nil, nil
    syncCutterGauge(true)
    if Screen.resourceId == "work_phone" then WorkPhoneScreen.enter(Projection.copy(state)) end
    Screen.hostLayout = grant and grant.useHostLayout == true
    Screen.sharedMachine = nil
    if Screen.hostLayout and (Screen.resourceId == "cutter" or Screen.resourceId == "skid_wrapper") then
        Screen.sharedMachine = SharedMachineGui.new(Screen.resourceId, function() return Screen.view end,
            Screen.cutterPresentation, function(action,args) return request(Screen.sendCommand,action,args) end)
        Screen.sharedMachine.sync(state)
    end
    Screen.sharedComputer, Screen.officePending = nil, nil
    Screen.sharedPress = nil
    if Screen.hostLayout and Screen.resourceId == "windmill" then
        Screen.sharedPress=SharedPressGui.new(function() return Screen.view end,
            function(action,args) return request(Screen.sendCommand,action,args) end)
    end
    if Screen.resourceId == "office_computer" then
        Screen.guiState = Projection.copy(state)
        Screen.sharedComputer = ComputerScreen.new({
            warehouseEnabled = Config.warehouse and Config.warehouse.enabled == true,
            warehouseFirstStorageOnly = Config.warehouse and Config.warehouse.firstStorageOnly == true,
            warehouseRequestPrefix = "WH-" .. tostring(Screen.leaseId or "guest"),
            remoteCommand = function(intent)
            if Screen.waiting then return false end
            local normalized, errorMessage = OfficeIntent.normalize(intent)
            if not normalized then Screen.status = errorMessage; return false end
            Screen.officePending = intent.kind
            return request(Screen.sendCommand, "office_action", { officeIntent = normalized })
        end })
        Screen.sharedComputer.enter(Screen.guiState)
    end
    if state then state.screen = "workshop_remote" end
    return Screen.resourceId ~= nil and Screen.leaseId ~= nil
end

function Screen.clear()
    Screen.sharedPress = nil
    Screen.sharedMachine = nil
    Screen.sharedComputer, Screen.guiState, Screen.sendCommand, Screen.officePending = nil, nil, nil, nil
    Screen.cutterPresentation = CutterPresentation.new()
    Screen.resourceId, Screen.leaseResourceId, Screen.leaseId, Screen.view = nil, nil, nil, nil
    Screen.quoteFocused, Screen.waiting, Screen.safetyWaiting = false, false, false
    Screen.selectedJobId, Screen.selectedPalletId = nil, nil
    Screen.gaugeFocused, Screen.gaugeReplaceOnType = false, true
    Screen.cutterTab = "production"
    Screen.wrapperTab = "production"
    Screen.wrapperClock = 0
    Screen.windmillTab = "run"
    Screen.windmillJobId, Screen.windmillPlateId = nil, nil
    Screen.workshopTick = 0
end

function Screen.isOpen() return Screen.resourceId ~= nil and Screen.leaseId ~= nil end
function Screen.canClose()
    return not Screen.waiting and not Screen.safetyWaiting
        and (Screen.resourceId ~= "skid_wrapper" or (Screen.view and Screen.view.step or Wrapper.step) ~= "wrapping")
        and (Screen.resourceId ~= "windmill"
            or not Screen.view or Screen.view.status ~= "production")
end
function Screen.hasMachineModal()
    return Screen.sharedMachine and Screen.sharedMachine.screen.hasModal() or false
end
function Screen.wantsTextInput()
    if Screen.sharedMachine then return Screen.sharedMachine.screen.wantsTextInput() end
    if Screen.sharedComputer then return Screen.sharedComputer.wantsTextInput() end
    return Screen.resourceId == "cutter" and Screen.gaugeFocused
end

function Screen.wrapperStartEnabled(state)
    return Screen.resourceId == "skid_wrapper"
        and not Screen.waiting
        and tostring(Screen.view and Screen.view.serviceStep or "idle") == "idle"
        and Wrapper.step ~= "wrapping"
        and selectedWrapperPallet(wrapperRows(state)) ~= nil
end

local function wrapperServiceBeginEnabled(state)
    local stock = state and state.inventory and state.inventory.stock or {}
    local view = Screen.view or {}
    return Screen.resourceId == "skid_wrapper" and not Screen.waiting
        and tostring(view.serviceStep or "idle") == "idle"
        and view.step ~= "wrapping" and #wrapperRows(state) == 0
        and (tonumber(stock.maintenance_kit) or 0) > 0
end

function Screen.applyResult(result)
    if type(result) ~= "table" or result.resourceId ~= Screen.leaseResourceId then return false end
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
    if Screen.sharedComputer and result.action == "office_action" then
        if Screen.officePending == "buy_upgrade" or Screen.officePending == "buy_forklift" then
            Screen.sharedComputer.resolveWarehouse(result.accepted == true, Screen.status)
        end
        if result.accepted then
            local computer = Screen.sharedComputer
            if Screen.officePending == "checkout" then computer.cart, computer.cartOpen = {}, false
            elseif Screen.officePending == "promotion" then computer.promoJobId, computer.promoText = nil, ""
            elseif Screen.officePending == "estimate" or Screen.officePending == "decline"
                or Screen.officePending == "archive" or Screen.officePending == "archive_service" then
                computer.selectedEmailId, computer.emailSelectionRequired = nil, true
            end
        end
        Screen.officePending = nil
    end
    if Screen.resourceId == "cutter" then
        if resourceCurrent then mergeCutterView(result.view or result.data) end
        if result.accepted and result.action == "cancel_service" then
            Screen.cutterTab = "production"
        end
    elseif Screen.resourceId == "windmill" then
        if resourceCurrent then mergeWindmillView(result.view or result.data) end
    elseif Screen.resourceId == "skid_wrapper" then
        mergeWrapperView(result.view or result.data)
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
    if Screen.leaseResourceId == "skid_wrapper" and type(wrapper) == "table" then
        mergeWrapperView(wrapper)
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
    if (snapshot.resourceId or "cutter") ~= Screen.leaseResourceId then return false end
    local resourceRevision = cutterResourceRevision(snapshot)
    if resourceRevision == nil or resourceRevision < Screen.revision then return false end
    local cutter = snapshot.view or snapshot.cutter or snapshot.data
    if type(cutter) ~= "table" or not mergeCutterView(cutter) then return false end
    Screen.revision = resourceRevision
    return true
end

function Screen.applyWrapperSnapshot(snapshot)
    if Screen.resourceId ~= "skid_wrapper" or type(snapshot) ~= "table"
        or snapshot.resourceId ~= Screen.leaseResourceId then return false end
    local resourceRevision = tonumber(snapshot.resourceRevision)
    if resourceRevision == nil or resourceRevision < Screen.revision then return false end
    if not mergeWrapperView(snapshot.view) then return false end
    Screen.revision = resourceRevision
    return true
end

function Screen.applyWindmillSnapshot(snapshot)
    if Screen.resourceId ~= "windmill" or type(snapshot) ~= "table" then return false end
    if (snapshot.resourceId or "windmill") ~= Screen.leaseResourceId then return false end
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

request = function(sendCommand, action, args)
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
local cutterButtonEnabled

function Screen.keypressed(key, state, sendCommand)
    if Screen.sharedPress then
        Screen.sendCommand=sendCommand
        return Screen.sharedPress.keypressed(state,key)
    end
    if Screen.sharedMachine then
        Screen.sendCommand = sendCommand
        return Screen.sharedMachine.keypressed(state,key)
    end
    if Screen.sharedComputer then
        if Screen.waiting then return true end
        Screen.sendCommand, Screen.guiState = sendCommand, Projection.copy(state)
        return Screen.sharedComputer.keypressed(Screen.guiState, key)
    end
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
        if Screen.cutterTab == "service" then return false end
        local view = Screen.view or {}
        -- Safety remains available while typing or waiting on an ordinary action.
        if key == "x" then
            return cutterButtonEnabled("emergency_stop")
                and request(sendCommand, "emergency_stop", {}) or true
        end
        if key == "b" then
            return cutterButtonEnabled("set_barrier")
                and request(sendCommand, "set_barrier", { barrierClear = view.barrierClear ~= true }) or true
        end
        if not Screen.gaugeFocused then
            local program = key == "[" and math.max(1, (view.programIndex or 1) - 1)
                or key == "]" and math.min(4, (view.programIndex or 1) + 1) or tonumber(key)
            if program and program >= 1 and program <= 4 then
                return cutterButtonEnabled("select_program")
                    and request(sendCommand, "select_program", { programIndex = program }) or true
            end
            if key == "l" then
                local candidates = cutterCandidates()
                if #candidates == 1 and cutterButtonEnabled("load_pallet") then
                    return request(sendCommand, "load_pallet", { palletId = candidates[1].palletId })
                elseif #candidates == 0 and (tonumber(view.genericSheets) or 0) > 0
                    and cutterButtonEnabled("load_stock") then
                    return request(sendCommand, "load_stock", {})
                end
                Screen.status = "Choose the matching nearby pallet on screen."
                return true
            end
            local action = ({ g = "auto_gauge", m = "save_gauge", v = "recall_gauge",
                q = "rotate_paper", p = "position_paper", space = "set_clamp",
                u = "return_to_pallet", t = "run_next_lift", r = "reset_safety" })[key]
            if action then
                local args = action == "set_clamp" and { clamp = view.clamp ~= true } or {}
                return cutterButtonEnabled(action) and request(sendCommand, action, args) or true
            end
        end
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
    return false
end

function Screen.textinput(text)
    if Screen.sharedMachine then return Screen.sharedMachine.textinput(text) end
    if Screen.sharedComputer then return not Screen.waiting and Screen.sharedComputer.textinput(Screen.guiState, text) end
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

cutterButtonEnabled = function(action)
    local view = Screen.view or {}
    if Screen.safetyWaiting then return false end
    if Screen.waiting then
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
        return cutterCutReady()
    elseif action == "load_stock" or action == "load_pallet" then
        return view.loaded ~= true and (view.step == "idle" or view.step == "finished")
    end
    return false
end

local function cutterMaintenanceStatus(state)
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

local function cutterServiceButtonEnabled(action, state)
    local view = Screen.view or {}
    local status = cutterMaintenanceStatus(state)
    if Screen.waiting or Screen.safetyWaiting then return false end
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
    if Screen.hostLayout and Screen.resourceId=="truck" then
        if button~=1 then return false end
        local action,args=TruckScreen.remoteIntent(Screen.view,x,y)
        if action=="close" then return Screen.canClose() and {action="close"} or true end
        return action and request(sendCommand,action,args) or false
    end
    if Screen.sharedPress then
        Screen.sendCommand=sendCommand
        local result=Screen.sharedPress.mousepressed(state,x,y,button)
        if type(result)=="table" and result.action=="exit" then return Screen.canClose() and {action="close"} or true end
        return result
    end
    if Screen.hostLayout and Screen.resourceId=="vendor" then
        if button~=1 then return false end
        local projected=Projection.copy(state); projected.vendorCategory=Screen.view.categoryIndex
        local action,args=VendorScreen.remoteIntent(projected,x,y)
        if action=="close" then return Screen.canClose() and {action="close"} or true end
        return action and request(sendCommand,action,args) or false
    elseif Screen.hostLayout and Screen.resourceId=="reception_customer" then
        if button~=1 then return false end
        local action=JobOfferScreen.hitTest(x,y)
        if action=="back" then return Screen.canClose() and {action="close"} or true end
        return action=="accept" and request(sendCommand,"request_details",{}) or false
    end
    if Screen.sharedMachine then
        Screen.sendCommand=sendCommand
        local result=Screen.sharedMachine.mousepressed(state,x,y,button)
        if not Screen.waiting and not Screen.safetyWaiting and Screen.sharedMachine.feedback then Screen.status=Screen.sharedMachine.feedback end
        if type(result)=="table" and result.action=="exit" then return Screen.canClose() and {action="close"} or true end
        return result
    end
    if Screen.sharedComputer then
        if Screen.waiting then return true end
        Screen.sendCommand, Screen.guiState = sendCommand, Projection.copy(state)
        local oldMessage=Screen.guiState.message
        local result = Screen.sharedComputer.mousepressed(Screen.guiState, x, y, button)
        if not Screen.waiting and Screen.guiState.message~=oldMessage then Screen.status=Screen.guiState.message end
        if result and result.action == "close" then return Screen.canClose() and { action = "close" } or true end
        if result and result.action == "pickup_ready" then return request(sendCommand, "request_pickup", { jobId = result.job.id }) end
        return result
    end
    if Screen.resourceId == "work_phone" then
        if button ~= 1 then return false end
        local action, args = WorkPhoneScreen.remoteIntent(state, x, y)
        if action == "close" then return Screen.canClose() and { action = "close" } or true end
        return action and request(sendCommand, action, args) or false
    end
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
        Screen.quoteFocused = false
        if contains(CONFIRM, x, y) then
            request(sendCommand, "request_details", {})
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
    elseif Screen.resourceId == "vendor" then
        for index, item in ipairs(vendorRows()) do
            if contains(vendorBuyRect(index), x, y) then
                local affordable = item.available == true
                    and (tonumber(Screen.view and Screen.view.cash) or 0)
                        >= (tonumber(item.price) or math.huge)
                if not affordable then
                    Screen.status = item.available ~= true
                        and tostring(item.detail or "That item is unavailable.")
                        or "The host shop does not have enough cash for that purchase."
                    return true
                end
                local action = Screen.view.kind == "machines"
                    and "purchase_machine" or "purchase_stock"
                return request(sendCommand, action, { itemIndex = item.itemIndex })
            end
        end
        if contains(CONFIRM, x, y) then
            return request(sendCommand, "dismiss", {})
        end
    elseif Screen.resourceId == "truck" then
        local view = Screen.view or {}
        for index, item in ipairs(view.items or {}) do
            if contains(vendorBuyRect(index), x, y) then
                if item.available ~= true then
                    Screen.status = "That manifest row was already handled."
                    return true
                end
                return request(sendCommand, "move_item", { itemIndex = item.itemIndex })
            end
        end
        if contains(TRUCK_PREVIOUS, x, y) then
            if (tonumber(view.page) or 1) > 1 then
                return request(sendCommand, "page_previous", {})
            end
            return true
        elseif contains(TRUCK_NEXT, x, y) then
            if (tonumber(view.page) or 1) < (tonumber(view.pageCount) or 1) then
                return request(sendCommand, "page_next", {})
            end
            return true
        elseif contains(CONFIRM, x, y) then
            if view.canClose ~= true then
                Screen.status = "Finish every available manifest row before releasing the truck."
                return true
            end
            return request(sendCommand, "close_truck", {})
        end
    elseif Screen.resourceId == "skid_wrapper" then
        local view = Screen.view or {}
        local serviceActive = tostring(view.serviceStep or "idle") ~= "idle"
        if contains(WRAPPER_TABS.production, x, y) then
            if not serviceActive then Screen.wrapperTab = "production" end
            return true
        elseif contains(WRAPPER_TABS.service, x, y) then
            Screen.wrapperTab = "service"
            return true
        end
        if Screen.wrapperTab == "service" then
            if serviceActive then
                if contains(WRAPPER_SERVICE_CANCEL, x, y) then
                    return not Screen.waiting
                        and request(sendCommand, "cancel_service", {}) or true
                end
                local target = wrapperServiceTarget(view)
                if target and contains(target, x, y) then
                    return not Screen.waiting and request(sendCommand, "service_target",
                        { itemIndex = tonumber(view.servicePhase) }) or true
                elseif contains(WRAPPER_SERVICE_WORK, x, y) then
                    return not Screen.waiting and request(sendCommand, "service_miss", {}) or true
                end
            elseif contains(WRAPPER_SERVICE_BEGIN, x, y) then
                if not wrapperServiceBeginEnabled(state) then
                    Screen.status = #wrapperRows(state) > 0
                        and "Move every eligible pallet away from the turntable first."
                        or "The host requires an idle wrapper and one maintenance kit."
                    return true
                end
                return request(sendCommand, "begin_service", {})
            end
            return true
        end
        local rows = wrapperRows(state)
        for index, item in ipairs(rows) do
            if contains(wrapperRowRect(index), x, y) then
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
        local serviceStep = tostring(view.serviceStep or "idle")
        if Screen.cutterTab == "service" then
            if contains(CUTTER_SERVICE_NAV, x, y) then
                if serviceStep ~= "idle" then
                    return cutterServiceButtonEnabled("cancel_service", state)
                        and request(sendCommand, "cancel_service", {}) or true
                end
                Screen.cutterTab = "production"
                return true
            elseif serviceStep == "idle" then
                if contains(CUTTER_SERVICE_CONTROLS.lubrication, x, y) then
                    return cutterServiceButtonEnabled("begin_lubrication", state)
                        and request(sendCommand, "begin_lubrication", {}) or true
                elseif contains(CUTTER_SERVICE_CONTROLS.blade, x, y) then
                    return cutterServiceButtonEnabled("begin_blade", state)
                        and request(sendCommand, "begin_blade", {}) or true
                elseif contains(CUTTER_SERVICE_CONTROLS.technician, x, y) then
                    return cutterServiceButtonEnabled("book_blade_technician", state)
                        and request(sendCommand, "book_blade_technician", {}) or true
                elseif contains(CUTTER_SERVICE_CONTROLS.weekly, x, y) then
                    return cutterServiceButtonEnabled("set_weekly_technician", state)
                        and request(sendCommand, "set_weekly_technician",
                            { enabled = cutterMaintenanceStatus(state).weeklyTechnician ~= true }) or true
                end
            elseif serviceStep == "lockout_disconnect" or serviceStep == "lockout_key"
                or serviceStep == "lockout_tag" or serviceStep == "prep_cartridge"
                or serviceStep == "prep_prime"
            then
                if contains(CUTTER_SERVICE_CONTROLS.advance, x, y) then
                    return cutterServiceButtonEnabled("service_advance", state)
                        and request(sendCommand, "service_advance", {}) or true
                end
            elseif serviceStep == "lubricate" then
                for index = 1, #CUTTER_SERVICE_VIEWS do
                    if contains(cutterServiceViewRect(index), x, y) then
                        if index == 5 and view.centralInstalled ~= true then return true end
                        return cutterServiceButtonEnabled("service_view", state)
                            and request(sendCommand, "service_view", { itemIndex = index }) or true
                    end
                end
                for index = 1, #CUTTER_SERVICE_TOOLS do
                    if contains(cutterServiceToolRect(index), x, y) then
                        return cutterServiceButtonEnabled("service_tool", state)
                            and request(sendCommand, "service_tool", { itemIndex = index }) or true
                    end
                end
                for index, item in ipairs(view.serviceItems or {}) do
                    if contains(cutterServiceItemRect(index), x, y) then
                        return cutterServiceButtonEnabled("service_point", state)
                            and request(sendCommand, "service_point",
                                { itemIndex = item.itemIndex }) or true
                    end
                end
                if contains(CUTTER_SERVICE_CONTROLS.pump, x, y) then
                    return cutterServiceButtonEnabled("service_pump", state)
                        and request(sendCommand, "service_pump", {}) or true
                elseif contains(CUTTER_SERVICE_CONTROLS.gear, x, y) then
                    return cutterServiceButtonEnabled("service_gear", state)
                        and request(sendCommand, "service_gear", {}) or true
                elseif contains(CUTTER_SERVICE_CONTROLS.finish, x, y) then
                    return cutterServiceButtonEnabled("finish_lubrication", state)
                        and request(sendCommand, "finish_lubrication", {}) or true
                end
            elseif serviceStep == "blade_bolts" then
                local nextBolt = (tonumber(view.bladeBoltsDone) or 0) + 1
                for index = 1, 4 do
                    if contains(cutterBladeBoltRect(index), x, y) then
                        return index == nextBolt
                            and cutterServiceButtonEnabled("remove_blade_bolt", state)
                            and request(sendCommand, "remove_blade_bolt", { itemIndex = index }) or true
                    end
                end
            elseif serviceStep == "blade_lift"
                and contains(CUTTER_SERVICE_CONTROLS.bladeAction, x, y)
            then
                return cutterServiceButtonEnabled("lift_blade", state)
                    and request(sendCommand, "lift_blade", {}) or true
            elseif serviceStep == "blade_sleeve"
                and contains(CUTTER_SERVICE_CONTROLS.bladeAction, x, y)
            then
                return cutterServiceButtonEnabled("sleeve_blade", state)
                    and request(sendCommand, "sleeve_blade", {}) or true
            end
            if serviceStep ~= "idle" and contains(CUTTER_SERVICE_CONTROLS.cancel, x, y) then
                return cutterServiceButtonEnabled("cancel_service", state)
                    and request(sendCommand, "cancel_service", {}) or true
            end
            return true
        end
        if view.loaded ~= true and contains(CUTTER_SERVICE_NAV, x, y) then
            if view.loaded == true or view.step ~= "idle" then
                Screen.status = "Unload the cutter and return it to idle before maintenance."
                return true
            end
            Screen.cutterTab = "service"
            Screen.gaugeFocused = false
            return true
        end
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
    love.graphics.rectangle("fill", 142, 354, 676, 128, 4, 4)
    love.graphics.setColor(0.94, 0.91, 0.79)
    love.graphics.printf("Review the sample work now. The client will email the complete written specifications before your shop prepares a price.",
        170, 382, 620, "center")
    button(CONFIRM, "REQUEST EMAIL DETAILS", pointerX, pointerY, not Screen.waiting, true)
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

local function drawVendor(pointerX, pointerY)
    local view = Screen.view or {}
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print(tostring(view.categoryName or "VENDOR CATALOG"), 142, 132)
    love.graphics.printf(tostring(view.salesman or "Supplier representative"),
        420, 132, 398, "right")
    love.graphics.print(string.format("HOST SHOP CASH  $%d",
        math.max(0, math.floor(tonumber(view.cash) or 0))), 142, 154)
    local rows = vendorRows()
    for index, item in ipairs(rows) do
        local rect = rowRect(index)
        local affordable = item.available == true
            and (tonumber(view.cash) or 0) >= (tonumber(item.price) or math.huge)
        love.graphics.setColor(0.79, 0.78, 0.73)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
        love.graphics.setColor(0.08, 0.10, 0.11)
        love.graphics.print(tostring(item.name or item.id), rect.x + 14, rect.y + 7)
        love.graphics.setColor(0.24, 0.28, 0.29)
        love.graphics.print(tostring(item.detail or "Host-verified purchase"),
            rect.x + 14, rect.y + 26)
        button(vendorBuyRect(index), item.available == true
            and string.format("BUY $%d", tonumber(item.price) or 0) or "LOCKED",
            pointerX, pointerY, not Screen.waiting and affordable, true)
    end
    if #rows == 0 then
        love.graphics.setColor(0.40, 0.42, 0.43)
        love.graphics.printf("This vendor has no active listings.", ROW_X, ROW_Y + 30,
            ROW_W, "center")
    end
    button(CONFIRM, "NO THANKS", pointerX, pointerY, not Screen.waiting, false)
end

local function drawTruck(pointerX, pointerY)
    local view = Screen.view or {}
    local pickup = view.mode == "pickup"
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print(tostring(view.manifestId or "TRUCK MANIFEST"), 142, 132)
    love.graphics.printf(tostring(view.title or "Truck manifest"), 420, 132, 398, "right")
    love.graphics.print(string.format("%d ITEM(S) REMAIN · PAGE %d / %d",
        math.max(0, tonumber(view.remaining) or 0), tonumber(view.page) or 1,
        tonumber(view.pageCount) or 1), 142, 154)
    for index, item in ipairs(view.items or {}) do
        local rect = rowRect(index)
        love.graphics.setColor(item.available == true and 0.79 or 0.68,
            item.available == true and 0.78 or 0.72, 0.73)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 4, 4)
        love.graphics.setColor(0.08, 0.10, 0.11)
        love.graphics.print(tostring(item.label or "Manifest item"), rect.x + 14, rect.y + 7)
        love.graphics.setColor(0.24, 0.28, 0.29)
        love.graphics.print(tostring(item.detail or "Host-owned cargo"), rect.x + 14, rect.y + 26)
        button(vendorBuyRect(index), item.available == true
            and (pickup and "LOAD" or "UNLOAD") or "DONE",
            pointerX, pointerY, not Screen.waiting and item.available == true, true)
    end
    button(TRUCK_PREVIOUS, "PREVIOUS", pointerX, pointerY,
        not Screen.waiting and (tonumber(view.page) or 1) > 1, false)
    button(TRUCK_NEXT, "NEXT", pointerX, pointerY,
        not Screen.waiting and (tonumber(view.page) or 1) < (tonumber(view.pageCount) or 1), false)
    button(CONFIRM, view.mode == "machine_delivery" and "RELEASE FLATBED" or "CLOSE CARGO",
        pointerX, pointerY, not Screen.waiting and view.canClose == true, true)
end

local function drawWrapperTabs(pointerX, pointerY)
    local activeService = tostring(Screen.view and Screen.view.serviceStep or "idle") ~= "idle"
    button(WRAPPER_TABS.production, "PRODUCTION", pointerX, pointerY,
        not Screen.waiting and not activeService, Screen.wrapperTab == "production")
    button(WRAPPER_TABS.service, activeService and "SERVICE ACTIVE" or "SERVICE",
        pointerX, pointerY, not Screen.waiting, Screen.wrapperTab == "service")
end

local function drawWrapperProduction(state, pointerX, pointerY)
    local runtime = Wrapper.snapshot()
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print("HOST CYCLE", 142, 174)
    love.graphics.print(string.upper(runtime.step), 270, 174)
    local ratio = math.min(1, runtime.progress / math.max(0.001, runtime.cycleTime))
    love.graphics.setColor(0.18, 0.21, 0.22)
    love.graphics.rectangle("fill", 420, 174, 380, 18, 3, 3)
    love.graphics.setColor(0.92, 0.72, 0.20)
    love.graphics.rectangle("fill", 420, 174, 380 * ratio, 18, 3, 3)
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print("NEARBY FINISHED PALLETS", 142, 198)
    local rows = wrapperRows(state)
    if #rows == 0 then
        love.graphics.setColor(0.40, 0.42, 0.43)
        love.graphics.printf("No eligible pallet is parked by the wrapper.", ROW_X, 254, ROW_W, "center")
    end
    for index, item in ipairs(rows) do
        local rect = wrapperRowRect(index)
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

local function drawWrapperService(state, pointerX, pointerY)
    local view = Screen.view or {}
    local stock = state and state.inventory and state.inventory.stock or {}
    local item = MachineFleet.installed(state, "skid_wrapper")
    local step = tostring(view.serviceStep or "idle")
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print("WRAPPER SERVICE  ·  HOST-OWNED QUALITY + SAVE", 142, 174)
    love.graphics.printf(string.format("KITS %d  ·  CONDITION %.1f%%",
        tonumber(stock.maintenance_kit) or 0,
        item and MachineFleet.condition(item) or 0), 490, 174, 328, "right")
    love.graphics.setColor(0.18, 0.21, 0.22)
    love.graphics.rectangle("fill", 142, 198, 676, 12, 3, 3)
    love.graphics.setColor(0.18, 0.58, 0.29)
    love.graphics.rectangle("fill", 142, 198,
        676 * math.max(0, math.min(1, (tonumber(view.servicePermille) or 0) / 1000)),
        12, 3, 3)

    if step == "idle" then
        local plan = item and MachineFleet.maintenancePlan(state, item.id)
        for index, task in ipairs(plan and plan.tasks or {}) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            local x, y = 142 + column * 342, 230 + row * 94
            love.graphics.setColor(0.79, 0.78, 0.72)
            love.graphics.rectangle("fill", x, y, 326, 78, 4, 4)
            love.graphics.setColor(0.10, 0.12, 0.13)
            love.graphics.print(string.upper(tostring(task.componentLabel)), x + 12, y + 10)
            love.graphics.printf(tostring(task.label), x + 12, y + 34, 302, "left")
        end
        love.graphics.setColor(0.22, 0.27, 0.27)
        love.graphics.printf("The turntable must be empty. One delivered maintenance kit is consumed only after all four host-ordered tasks are complete.",
            166, 424, 628, "center")
        button(WRAPPER_SERVICE_BEGIN, "START FULL SERVICE", pointerX, pointerY,
            wrapperServiceBeginEnabled(state), true)
        return
    end

    local target, task = wrapperServiceTarget(view)
    love.graphics.setColor(0.74, 0.76, 0.72)
    love.graphics.rectangle("fill", WRAPPER_SERVICE_WORK.x, WRAPPER_SERVICE_WORK.y + 18,
        WRAPPER_SERVICE_WORK.width, WRAPPER_SERVICE_WORK.height - 18, 5, 5)
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print(string.format("STEP %d / %d  ·  %s",
        tonumber(view.serviceTaskIndex) or 1,
        tonumber(view.serviceTaskCount) or 4,
        task and task.component or "SERVICE TASK"), 166, 236)
    love.graphics.printf(task and task.instruction or "Use the active service marker.",
        166, 266, 420, "left")
    love.graphics.print(string.format("TARGET %d / %d",
        tonumber(view.servicePhase) or 1,
        tonumber(view.serviceTargetCount) or 1), 166, 438)
    if target then
        local cx, cy = target.x + target.width / 2, target.y + target.height / 2
        local pulse = 24 + math.sin((Screen.wrapperClock or 0) * 6) * 5
        love.graphics.setColor(0.98, 0.72, 0.18, 0.24)
        love.graphics.circle("fill", cx, cy, pulse)
        love.graphics.setColor(0.95, 0.58, 0.08)
        love.graphics.circle("fill", cx, cy, 17)
        love.graphics.setColor(0.12, 0.14, 0.14)
        love.graphics.circle("fill", cx, cy, 6)
    end
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.printf(string.format("ATTEMPTS %d\nMISSES %d",
        tonumber(view.serviceAttempts) or 0, tonumber(view.serviceMisses) or 0),
        650, 254, 150, "left")
    love.graphics.setColor(0.22, 0.27, 0.27)
    love.graphics.printf("Tap the gold marker. Taps elsewhere in the service bay count as misses and reduce repair quality.",
        640, 354, 170, "center")
    button(WRAPPER_SERVICE_CANCEL, "CANCEL SERVICE", pointerX, pointerY,
        not Screen.waiting, false)
end

local function drawWrapper(state, pointerX, pointerY)
    drawWrapperTabs(pointerX, pointerY)
    if Screen.wrapperTab == "service" then
        drawWrapperService(state, pointerX, pointerY)
    else
        drawWrapperProduction(state, pointerX, pointerY)
    end
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

local function drawCutterService(state, pointerX, pointerY)
    local view = Screen.view or {}
    local status = cutterMaintenanceStatus(state)
    local step = tostring(view.serviceStep or "idle")
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print("CUTTER SERVICE  ·  HOST-AUTHORITATIVE LOCKOUT", 122, 132)
    love.graphics.printf(string.format("KITS %d  ·  BLADE %s  ·  TECHNICIAN %s",
        status.maintenanceKits,
        status.bladeInSleeve and "SLEEVED" or status.bladeRemoved and "REMOVED" or "INSTALLED",
        status.technicianScheduled and "SCHEDULED" or "NOT SCHEDULED"),
        122, 156, 690, "left")
    cutterBar(122, 180, 690, view.servicePermille, { 0.18, 0.58, 0.29 })

    if step == "idle" then
        button(CUTTER_SERVICE_CONTROLS.lubrication, "LUBRICATION SERVICE", pointerX, pointerY,
            cutterServiceButtonEnabled("begin_lubrication", state), true)
        button(CUTTER_SERVICE_CONTROLS.blade, "REMOVE + SLEEVE BLADE", pointerX, pointerY,
            cutterServiceButtonEnabled("begin_blade", state), true)
        button(CUTTER_SERVICE_CONTROLS.technician,
            status.technicianScheduled and "TECHNICIAN SCHEDULED" or "BOOK BLADE TECHNICIAN",
            pointerX, pointerY, cutterServiceButtonEnabled("book_blade_technician", state), true)
        button(CUTTER_SERVICE_CONTROLS.weekly,
            status.weeklyTechnician and "CANCEL WEEKLY SERVICE" or "SCHEDULE WEEKLY SERVICE",
            pointerX, pointerY, cutterServiceButtonEnabled("set_weekly_technician", state), true)
        love.graphics.setColor(0.32, 0.35, 0.36)
        love.graphics.printf("Lubrication consumes one delivered maintenance kit only after every point and the gearbox inspection pass. Blade removal becomes durable only when the blade reaches its wooden sleeve.",
            142, 386, 650, "center")
    elseif step == "lockout_disconnect" or step == "lockout_key"
        or step == "lockout_tag" or step == "prep_cartridge" or step == "prep_prime"
    then
        local labels = {
            lockout_disconnect = "OPEN MAIN DISCONNECT",
            lockout_key = "SECURE LOCKOUT KEY",
            lockout_tag = "ATTACH SERVICE TAG",
            prep_cartridge = "INSTALL GREASE CARTRIDGE",
            prep_prime = "PRIME GREASE GUN",
        }
        love.graphics.setColor(0.24, 0.28, 0.29)
        love.graphics.printf("Complete the displayed host-owned step in order.", 122, 230, 690, "center")
        button(CUTTER_SERVICE_CONTROLS.advance, labels[step], pointerX, pointerY,
            cutterServiceButtonEnabled("service_advance", state), true)
    elseif step == "lubricate" then
        for index, label in ipairs(CUTTER_SERVICE_VIEWS) do
            local available = index ~= 5 or view.centralInstalled == true
            button(cutterServiceViewRect(index), label, pointerX, pointerY,
                available and cutterServiceButtonEnabled("service_view", state),
                tonumber(view.serviceView) == index)
        end
        for index, label in ipairs(CUTTER_SERVICE_TOOLS) do
            button(cutterServiceToolRect(index), label, pointerX, pointerY,
                cutterServiceButtonEnabled("service_tool", state),
                tonumber(view.serviceTool) == index)
        end
        for index, item in ipairs(view.serviceItems or {}) do
            local status = item.complete and "DONE" or item.coupled and ("COUPLED · "
                .. tostring(item.strokes) .. " STROKE(S)") or item.cleaned and "CLEAN" or "DIRTY"
            button(cutterServiceItemRect(index), tostring(item.label) .. "  ·  " .. status,
                pointerX, pointerY, cutterServiceButtonEnabled("service_point", state), item.complete)
        end
        local gearLabel = view.gearInspected
            and string.format("GEAR %.0f%%", (tonumber(view.gearLevelPermille) or 0) / 10)
            or "INSPECT / TOP UP GEAR"
        button(CUTTER_SERVICE_CONTROLS.pump, "PUMP GREASE", pointerX, pointerY,
            cutterServiceButtonEnabled("service_pump", state), true)
        button(CUTTER_SERVICE_CONTROLS.gear, gearLabel, pointerX, pointerY,
            cutterServiceButtonEnabled("service_gear", state), true)
        button(CUTTER_SERVICE_CONTROLS.finish, "FINISH + SAVE", pointerX, pointerY,
            cutterServiceButtonEnabled("finish_lubrication", state), true)
    elseif step == "blade_bolts" then
        love.graphics.setColor(0.24, 0.28, 0.29)
        love.graphics.printf("Remove each blade bolt. The host tracks every distinct fastener.",
            122, 220, 690, "center")
        local done = tonumber(view.bladeBoltsDone) or 0
        for index = 1, 4 do
            button(cutterBladeBoltRect(index), index <= done and "REMOVED" or ("BOLT " .. index),
                pointerX, pointerY, index == done + 1
                    and cutterServiceButtonEnabled("remove_blade_bolt", state),
                index <= done)
        end
    elseif step == "blade_lift" then
        button(CUTTER_SERVICE_CONTROLS.bladeAction, "LIFT RELEASED BLADE SAFELY",
            pointerX, pointerY, cutterServiceButtonEnabled("lift_blade", state), true)
    elseif step == "blade_sleeve" then
        button(CUTTER_SERVICE_CONTROLS.bladeAction, "PLACE BLADE IN WOODEN SLEEVE + SAVE",
            pointerX, pointerY, cutterServiceButtonEnabled("sleeve_blade", state), true)
    end

    if step ~= "idle" then
        button(CUTTER_SERVICE_CONTROLS.cancel, "CANCEL SERVICE", pointerX, pointerY,
            cutterServiceButtonEnabled("cancel_service", state), false)
    end
    button(CUTTER_SERVICE_NAV, "PRODUCTION", pointerX, pointerY,
        not Screen.waiting and not Screen.safetyWaiting, false)
end

local function drawCutter(state, pointerX, pointerY, assets)
    local view = Screen.view or {}
    if Screen.cutterTab == "service" then
        drawCutterService(state, pointerX, pointerY)
        return
    end
    local model = Screen.cutterPresentation:model(state, view)
    love.graphics.setColor(0.045, 0.055, 0.07)
    love.graphics.rectangle("fill", CUTTER_SCENE.x, CUTTER_SCENE.y,
        CUTTER_SCENE.width, CUTTER_SCENE.height, 4, 4)
    MachineScreen.drawCutterScene(assets, model,
        { x = CUTTER_SCENE.x + 12, y = CUTTER_SCENE.y, width = 340, height = 227 })
    if model.paper then
        love.graphics.setColor(model.paper.offSpec and 1 or 0.84,
            model.paper.offSpec and 0.4 or 0.92, model.paper.offSpec and 0.3 or 0.92)
        love.graphics.printf(string.format("%s  %.2f x %.2f in",
            model.paper.offSpec and "SPOILED" or "ON BED",
            model.paper.currentSize.width, model.paper.currentSize.height),
            474, 348, 344, "center")
    end
    local step = tostring(view.step or "idle"):gsub("_", " "):upper()
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.print("HOST: " .. step, 122, 126)
    if model.loaded and not model.paper then
        love.graphics.setColor(0.84, 0.92, 0.92)
        love.graphics.printf("Waiting for host paper details", 474, 348, 344, "center")
        love.graphics.setColor(0.10, 0.12, 0.13)
    end

    local paper = type(view.paper) == "table" and view.paper or nil
    if paper then
        local label = cutterPalletLabel(state, paper.palletId)
        love.graphics.printf(string.format("%s\nLIFT %d/%d  ·  %d LEFT  ·  %d°",
            compactLabel(label, 36), tonumber(paper.activeLift) or 1,
            tonumber(paper.requiredLifts) or 1, tonumber(paper.remainingSheets) or 0,
            tonumber(paper.orientation) or 0), 122, 146, 326, "left")
        local cut = type(paper.selectedCut) == "table" and paper.selectedCut or nil
        if cut then
            love.graphics.printf(string.format("TICKET: CUT %d %s · TRIM %.2f · GAUGE %.2f",
                tonumber(cut.number) or tonumber(paper.activeCut) or 1,
                tostring(cut.edge or "edge"):upper(),
                (tonumber(cut.marginCentiInch) or 0) / 100,
                (tonumber(cut.gaugeCentiInch) or 0) / 100), 122, 344, 326, "left")
        end
    else
        love.graphics.printf("No paper is on the cutting bed.", 122, 154, 326, "left")
    end

    if view.loaded ~= true then
        love.graphics.setColor(0.10, 0.12, 0.13)
        love.graphics.print("NEARBY CUTTER PALLETS [L]", 122, 184)
        local candidates = cutterCandidates()
        if #candidates == 0 then
            love.graphics.setColor(0.40, 0.42, 0.43)
            love.graphics.printf("Park an unfinished pallet beside the cutter, or use generic stock.",
                122, 260, 318, "center")
        end
        for index, candidate in ipairs(candidates) do
            local distance = math.max(0, math.floor(tonumber(candidate.distancePixels) or 0))
            local label = string.format("%s  ·  %d px",
                compactLabel(cutterPalletLabel(state, candidate.palletId), 24), distance)
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
        button(CUTTER_SERVICE_NAV, "SERVICE", pointerX, pointerY,
            not Screen.waiting and view.step == "idle", false)
        return
    end

    for index, rect in ipairs(CUTTER_PROGRAMS) do
        button(rect, "CUT " .. index, pointerX, pointerY,
            cutterButtonEnabled("select_program"), tonumber(view.programIndex) == index)
    end
    local memory = {}
    for _, centi in ipairs(view.memoryCentiInch or {}) do
        memory[#memory + 1] = string.format("%.2f", (tonumber(centi) or 0) / 100)
    end
    love.graphics.setColor(0.10, 0.12, 0.13)
    love.graphics.printf("P" .. tostring(tonumber(view.programIndex) or 1) .. " MEMORY  "
        .. (#memory > 0 and table.concat(memory, " / ") or "EMPTY"), 122, 328, 326, "left")

    love.graphics.setColor(Screen.gaugeFocused and 0.98 or 0.88, 0.96, 0.82)
    love.graphics.rectangle("fill", CUTTER_GAUGE_INPUT.x, CUTTER_GAUGE_INPUT.y,
        CUTTER_GAUGE_INPUT.width, CUTTER_GAUGE_INPUT.height, 4, 4)
    love.graphics.setColor(0.08, 0.10, 0.11)
    love.graphics.printf(Screen.gaugeText .. " in", CUTTER_GAUGE_INPUT.x,
        CUTTER_GAUGE_INPUT.y + 13, CUTTER_GAUGE_INPUT.width, "center")
    button(CUTTER_CONTROLS.gauge_set, "SET", pointerX, pointerY,
        cutterButtonEnabled("gauge_set"), true)
    button(CUTTER_CONTROLS.auto_gauge, "AUTO [G]", pointerX, pointerY,
        cutterButtonEnabled("auto_gauge"), true)
    button(CUTTER_CONTROLS.save_gauge, "SAVE [M]", pointerX, pointerY,
        cutterButtonEnabled("save_gauge"), true)
    button(CUTTER_CONTROLS.recall_gauge, "RECALL [V]", pointerX, pointerY,
        cutterButtonEnabled("recall_gauge"), true)

    button(CUTTER_CONTROLS.rotate_paper, "ROTATE PAPER [Q]", pointerX, pointerY,
        cutterButtonEnabled("rotate_paper"), true)
    button(CUTTER_CONTROLS.position_paper, "POSITION PAPER [P]", pointerX, pointerY,
        cutterButtonEnabled("position_paper"), true)
    button(CUTTER_CONTROLS.set_clamp, view.clamp == true and "RAISE CLAMP [SPACE]" or "LOWER CLAMP [SPACE]",
        pointerX, pointerY, cutterButtonEnabled("set_clamp"), true)
    button(CUTTER_CONTROLS.set_barrier,
        view.barrierClear == true and "BLOCK BARRIER [B]" or "CLEAR BARRIER [B]",
        pointerX, pointerY, cutterButtonEnabled("set_barrier"), false)
    button(CUTTER_CONTROLS.reset_safety, "RESET SAFETY [R]", pointerX, pointerY,
        cutterButtonEnabled("reset_safety"), true)
    button(CUTTER_CONTROLS.emergency_stop, "E-STOP [X]", pointerX, pointerY,
        cutterButtonEnabled("emergency_stop"), false)
    button(CUTTER_CONTROLS.return_to_pallet, "RETURN TO PALLET [U]", pointerX, pointerY,
        cutterButtonEnabled("return_to_pallet"), true)
    button(CUTTER_CONTROLS.run_next_lift, "RUN NEXT LIFT [T]", pointerX, pointerY,
        cutterButtonEnabled("run_next_lift"), true)

    button(CUTTER_CONTROLS.cut_left, "CUT  ·  J",
        pointerX, pointerY, cutterButtonEnabled("cut_left"), true)
    button(CUTTER_CONTROLS.cut_right, "CUT  ·  K",
        pointerX, pointerY, cutterButtonEnabled("cut_right"), true)
    for _, rect in ipairs({ CUTTER_CONTROLS.cut_left, CUTTER_CONTROLS.cut_right }) do
        MachineScreen.drawCutterButton(assets, { x = rect.x + 10, y = rect.y + 3,
            width = 56, height = 56, label = "" }, false,
            view.step == "armed" or view.step == "cutting")
    end
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
    if Screen.hostLayout and Screen.resourceId=="truck" then
        TruckScreen.draw(Projection.copy(state),nil,assets,pointerX,pointerY,Screen.view)
        love.graphics.setColor(0.8,0.9,0.9); love.graphics.printf(Screen.status,82,526,790,"center")
        return
    end
    if Screen.sharedPress then
        Screen.sharedPress.draw(state,assets,pointerX,pointerY,Screen.status)
        return
    end
    if Screen.hostLayout and Screen.resourceId=="vendor" then
        local projected=Projection.copy(state); projected.vendorCategory=Screen.view.categoryIndex
        projected.money=Screen.view.cash or projected.money
        VendorScreen.draw(projected,assets,pointerX,pointerY)
        love.graphics.setColor(0.8,0.9,0.9); love.graphics.printf(Screen.status,82,590,790,"center")
        return
    elseif Screen.hostLayout and Screen.resourceId=="reception_customer" then
        local projected=Projection.copy(state)
        if not projected.currentOffer then
            projected.currentOffer=JobOfferScreen.fromNetwork(Screen.view)
        end
        JobOfferScreen.draw(projected,pointerX,pointerY,assets)
        return
    end
    if Screen.sharedMachine then
        Screen.sharedMachine.draw(state,assets,pointerX,pointerY,Screen.status)
        return
    end
    if Screen.sharedComputer then
        Screen.guiState = Projection.copy(state)
        Screen.guiState.message = Screen.status
        Screen.sharedComputer.draw(Screen.guiState, pointerX, pointerY, assets)
        return
    end
    if Screen.resourceId == "work_phone" then
        WorkPhoneScreen.draw(Projection.copy(state), pointerX, pointerY, assets, Screen.waiting)
        love.graphics.setColor(0.8, 0.9, 0.9)
        love.graphics.printf(Screen.status, 68, 612, 812, "center")
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
    local copy = titles[Screen.resourceId] or { "REMOTE WORKSHOP", "Host-authoritative console" }
    header(copy[1], copy[2], pointerX, pointerY, assets)
    if Screen.resourceId == "reception_customer" then drawCustomer(pointerX, pointerY)
    elseif Screen.resourceId == "vendor" then drawVendor(pointerX, pointerY)
    elseif Screen.resourceId == "truck" then drawTruck(pointerX, pointerY)
    elseif Screen.resourceId == "office_computer" then drawComputer(state, pointerX, pointerY)
    elseif Screen.resourceId == "skid_wrapper" then drawWrapper(state, pointerX, pointerY)
    elseif Screen.resourceId == "cutter" then drawCutter(state, pointerX, pointerY, assets)
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
    local rect = Screen.resourceId == "skid_wrapper"
        and wrapperRowRect(index) or rowRect(index)
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end


function Screen.wrapperTabCenter(tab)
    local rect = WRAPPER_TABS[tab]
    if not rect then return nil end
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function Screen.wrapperServiceCenter(action)
    local rect
    if action == "begin_service" then
        rect = WRAPPER_SERVICE_BEGIN
    elseif action == "cancel_service" then
        rect = WRAPPER_SERVICE_CANCEL
    elseif action == "service_target" then
        rect = wrapperServiceTarget(Screen.view or {})
    elseif action == "service_miss" then
        rect = { x = WRAPPER_SERVICE_WORK.x + 8, y = WRAPPER_SERVICE_WORK.y + 8,
            width = 2, height = 2 }
    end
    if not rect then return nil end
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function Screen.update(dt)
    if Screen.sharedPress then Screen.sharedPress.screen.update(dt); return true end
    if Screen.sharedMachine then Screen.sharedMachine.screen.update(dt) end
    if Screen.resourceId == "cutter" then
        Screen.cutterPresentation:update(dt)
        return true
    end
    if Screen.resourceId ~= "skid_wrapper" then return false end
    Screen.wrapperClock = (Screen.wrapperClock + math.max(0, tonumber(dt) or 0)) % 10000
    return true
end

function Screen.requiredAssetPack()
    return ({ cutter = "cutter", skid_wrapper = "wrapper", windmill = "press" })[Screen.resourceId]
end

function Screen.wheelmoved(state, x, y)
    if Screen.sharedComputer then return Screen.sharedComputer.wheelmoved(Projection.copy(state), x, y) end
    return false
end

function Screen.vendorBuyCenter(index)
    local rect = vendorBuyRect(index)
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function Screen.vendorDismissCenter()
    return CONFIRM.x + CONFIRM.width / 2, CONFIRM.y + CONFIRM.height / 2
end

function Screen.truckMoveCenter(index)
    local rect = vendorBuyRect(index)
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function Screen.truckPageCenter(direction)
    local rect = direction == "previous" and TRUCK_PREVIOUS or TRUCK_NEXT
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function Screen.truckCloseCenter()
    return CONFIRM.x + CONFIRM.width / 2, CONFIRM.y + CONFIRM.height / 2
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

function Screen.cutterServiceCenter(action, value)
    local rect
    if action == "tab" or action == "production" then
        rect = CUTTER_SERVICE_NAV
    elseif action == "begin_lubrication" then
        rect = CUTTER_SERVICE_CONTROLS.lubrication
    elseif action == "begin_blade" then
        rect = CUTTER_SERVICE_CONTROLS.blade
    elseif action == "book_blade_technician" then
        rect = CUTTER_SERVICE_CONTROLS.technician
    elseif action == "set_weekly_technician" then
        rect = CUTTER_SERVICE_CONTROLS.weekly
    elseif action == "service_advance" then
        rect = CUTTER_SERVICE_CONTROLS.advance
    elseif action == "service_view" then
        rect = cutterServiceViewRect(tonumber(value) or 1)
    elseif action == "service_tool" then
        rect = cutterServiceToolRect(tonumber(value) or 1)
    elseif action == "service_point" then
        rect = cutterServiceItemRect(tonumber(value) or 1)
    elseif action == "service_pump" then
        rect = CUTTER_SERVICE_CONTROLS.pump
    elseif action == "service_gear" then
        rect = CUTTER_SERVICE_CONTROLS.gear
    elseif action == "finish_lubrication" then
        rect = CUTTER_SERVICE_CONTROLS.finish
    elseif action == "cancel_service" then
        rect = CUTTER_SERVICE_CONTROLS.cancel
    elseif action == "remove_blade_bolt" then
        rect = cutterBladeBoltRect(tonumber(value) or 1)
    elseif action == "lift_blade" or action == "sleeve_blade" then
        rect = CUTTER_SERVICE_CONTROLS.bladeAction
    end
    if not rect then return nil end
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

return Screen
