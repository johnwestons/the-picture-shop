local function create(dependencies)
dependencies = dependencies or {}
local Config = require("src.config")
local Machine = dependencies.Machine or require("src.machine")
local MachineFleet = require("src.machine_fleet")
local MachineMaintenance = require("src.machine_maintenance")
local BusinessCalendar = require("src.business_calendar")
local PalletJack = require("src.pallet_jack")
local Procurement = require("src.procurement")
local Wrapper = dependencies.Wrapper or require("src.wrapper")
local BackButton = require("src.screens.back_button")
local utf8 = require("utf8")

local Screen = {
    pressedAction = nil,
    gaugeFocused = false,
    gaugeText = "0.00",
    gaugeReplaceOnType = true,
    loadMenu = nil,
    maintenanceView = nil,
    oilSession = nil,
    bladeStage = nil,
    bladeBolts = nil,
    wrapperSession = nil,
    helpOpen = false,
    helpStep = 1,
}
local buttons = {}
local gaugeInput = { x = 55, y = 263, width = 182, height = 28 }
local exitButton = { x = 790, y = 28, width = 132, height = 42 }
local wrapButton = { x = 650, y = 520, width = 220, height = 54 }
local wrapperMaintenanceButton = { x = 50, y = 520, width = 220, height = 54 }
local wrapperPalletList = { x = 42, y = 92, width = 330, rowHeight = 48, maxRows = 5 }
local helpButton = { x = 500, y = 82, width = 174, height = 40 }
local maintenanceButton = { x = 692, y = 82, width = 198, height = 40 }
local helpBack = { x = 72, y = 582, width = 180, height = 44 }
local helpPrevious = { x = 280, y = 582, width = 180, height = 44 }
local helpNext = { x = 706, y = 582, width = 180, height = 44 }
local maintenanceBack = { x = 54, y = 594, width = 188, height = 42 }
local oilServiceButton = { x = 92, y = 244, width = 342, height = 122 }
local bladeServiceButton = { x = 526, y = 244, width = 342, height = 122 }
local technicianButton = { x = 526, y = 390, width = 342, height = 72 }
local weeklyButton = { x = 526, y = 478, width = 342, height = 82 }
local lockoutButtons = {
    disconnect = { x = 105, y = 235, width = 210, height = 150 },
    key = { x = 375, y = 235, width = 210, height = 150 },
    tag = { x = 645, y = 235, width = 210, height = 150 },
}
local prepButtons = {
    cartridge = { x = 190, y = 220, width = 240, height = 220 },
    prime = { x = 530, y = 220, width = 240, height = 220 },
}
local lubricationViews = { "rear", "front", "side", "central", "gear" }
local lubricationTools = { "rag", "grease", "inspect", "gear_oil" }
local pumpButton = { x = 670, y = 462, width = 225, height = 58 }
local finishLubricationButton = { x = 670, y = 532, width = 225, height = 48 }
local loadMenuRect = { x = 190, y = 126, width = 580, rowHeight = 54 }
local loadMenuPageSize = 7

local function inside(button, x, y)
    return x >= button.x and x <= button.x + button.width and y >= button.y and y <= button.y + button.height
end

local function box(x, y, width, height, fill, line, radius)
    love.graphics.setColor(fill)
    love.graphics.rectangle("fill", x, y, width, height, radius or 0, radius or 0)
    love.graphics.setColor(line)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, width, height, radius or 0, radius or 0)
end

local function drawCondition(state, modelId, x, y, width)
    local item = MachineFleet.installed(state, modelId)
    if not item then return end
    local condition = MachineFleet.condition(item)
    local status = MachineFleet.conditionStatus(condition)
    love.graphics.setColor(0.72, 0.80, 0.81)
    love.graphics.printf(string.format("%s  •  %s  •  %.1f%%", item.id, status, condition),
        x, y, width, "right")
    love.graphics.setColor(0.12, 0.15, 0.17)
    love.graphics.rectangle("fill", x, y + 19, width, 7, 2, 2)
    if condition >= 75 then love.graphics.setColor(0.28, 0.72, 0.43)
    elseif condition >= 55 then love.graphics.setColor(0.88, 0.67, 0.22)
    else love.graphics.setColor(0.89, 0.31, 0.22) end
    love.graphics.rectangle("fill", x, y + 19, width * condition / 100, 7, 2, 2)
end

local function addButton(action, label, x, y, width, height, key, value)
    buttons[#buttons + 1] = { action = action, label = label, x = x, y = y, width = width, height = height, key = key, value = value }
end

local function layout()
    buttons = {}
    for index = 1, 4 do addButton("program", "CUT " .. index, 55 + (index - 1) * 72, 228, 64, 28, nil, index) end
    addButton("set_gauge", "SET", 245, 263, 46, 28)
    addButton("gauge", "-1", 55, 298, 48, 28, nil, -1)
    addButton("gauge", "-.1", 109, 298, 48, 28, nil, -0.1)
    addButton("gauge", "+.1", 163, 298, 48, 28, nil, 0.1)
    addButton("gauge", "+1", 217, 298, 48, 28, nil, 1)
    addButton("auto", "AUTO SET", 271, 298, 72, 28, "g")
    addButton("save", "SAVE", 55, 334, 62, 28, "m")
    addButton("recall", "RECALL", 123, 334, 70, 28, "v")
    addButton("repeat", "RUN NEXT LIFT", 201, 334, 142, 28, "t")
    addButton("load", "LOAD JOB", 54, 478, 96, 34, "l")
    addButton("position", "PUSH / POS", 158, 478, 100, 34, "p")
    addButton("rotate", "ROTATE CCW", 266, 478, 100, 34, "q")
    addButton("clamp", "CLAMP", 374, 478, 84, 34, "space")
    addButton("unload", "TO PALLET", 466, 478, 96, 34, "u")
    addButton("barrier", "BARRIER", 570, 478, 86, 34, "b")
    addButton("reset", "RESET", 664, 478, 72, 34, "r")
    addButton("estop", "E-STOP", 752, 470, 74, 74, "x")
    addButton("cut_left", "J", 674, 565, 82, 82, "j")
    addButton("cut_right", "K", 804, 565, 82, 82, "k")
end

local function formatGauge()
    Screen.gaugeText = string.format("%.2f", Machine.gauge or 0)
    Screen.gaugeReplaceOnType = true
end

local function commitGauge(state)
    local succeeded = Machine.setGauge(Screen.gaugeText, state)
    if succeeded then formatGauge() end
    return succeeded
end

function Screen.enter()
    Screen.pressedAction = nil
    Screen.gaugeFocused = false
    Screen.loadMenu = nil
    Screen.maintenanceView = nil
    Screen.oilSession = nil
    Screen.bladeStage = nil
    Screen.bladeBolts = nil
    Screen.wrapperSession = nil
    Screen.helpOpen, Screen.helpStep = false, 1
    formatGauge()
end

local cutterHelp = {
    { "1 — REVIEW AND SAFETY", "Read the pallet tooltip and job ticket: starting size, finished size, lift count, artwork margins and packaging. Wear cut-resistant gloves only while handling the blade—not near a running cutter. Keep the light barrier clear, close the cutting area and reset E-STOP before loading." },
    { "2 — LOAD THE CORRECT PALLET", "Move a received paper pallet to the cutter staging area. Press L or click LOAD, then choose the pallet ID that matches the job. Its unique paper record follows every size and rotation change. Wait for the stack animation to settle on the bed before setting the gauge." },
    { "3 — READ THE CUT PROGRAM", "The active cut number identifies the margin currently nearest the operator/screen. Compare the required measurement to the job's cut list. Easy work often repeats one margin; harder work has four different values. Never guess: the displayed target and pallet ID are the source of truth." },
    { "4 — SET OR PROGRAM THE BACK GAUGE", "Click the gauge number field, type inches with decimals, then press ENTER or SET. SAVE stores the measurement in the selected P1–P4 program. RECALL restores saved values. AUTOSET recalls the next saved cut, moves to its cut number automatically and prepares the next repeat measurement." },
    { "5 — POSITION AND ROTATE", "Press P or POSITION to push the stack against the back gauge. The red active margin must face the operator/screen. Press Q or ROTATE for a 90-degree counter-clockwise turn between sides. Reposition against the gauge after every rotation or measurement change." },
    { "6 — CLAMP AND CUT", "Clear the light barrier. Press SPACE or CLAMP to lower the clamp. Offline, trigger both CUT buttons (J and K) within 0.30 seconds. The safety controls prevent injury, but they do not check your measurement. A wrong gauge, program, or rotation ruins the whole lift, creates a customer-stock claim, and lowers reputation." },
    { "7 — FINISH ALL LIFTS", "The cutter holds a maximum 500 sheets per lift. Repeat the programmed sides for each lift until the pallet's full sheet count is processed. Verify the size after every side. When all required margins are removed, press U or UNLOAD; the animated stack returns to its pallet at cutter output." },
    { "8 — TROUBLESHOOTING", "If the blade will not cycle, check: pallet loaded, transfer animation finished, paper positioned, barrier clear, clamp down, the required offline or multiplayer cut control pressed, and E-STOP reset. The cutter intentionally permits off-size work—compare the selected program, rotation, and gauge to the ticket yourself." },
    { "9 — ROUTINE MAINTENANCE", "Unload the bed and return to IDLE. Open MAINTENANCE. Lubrication requires one delivered maintenance kit and an ordered lockout sequence: disconnect, keep the key and attach the tag. Clean and grease each marked point, inspect the gearbox sight glass, pump lubricant, then finish inspection." },
    { "10 — CHANGE THE BLADE", "With the bed empty, lock out power in order. Open REMOVE & SLEEVE BLADE. Release all four blade bolts, support the blade, lower/remove it without touching the edge, and place it immediately in the wooden sleeve. Book the blade technician; the on-site technician services and reinstalls it. Never run with the blade removed." },
}

local function drawHelp(state, assets, pointerX, pointerY)
    box(18, 18, 924, 642, { 0.035, 0.055, 0.065, 0.995 }, { 0.35, 0.68, 0.61, 1 }, 5)
    love.graphics.setColor(0.96, 0.82, 0.26)
    love.graphics.print("POLAR 115 OPERATOR HELP", 46, 38)
    love.graphics.setColor(0.11, 0.15, 0.17)
    love.graphics.rectangle("fill", 72, 104, 814, 430, 7, 7)
    local page = cutterHelp[Screen.helpStep]
    love.graphics.setColor(0.96, 0.82, 0.28)
    love.graphics.printf(page[1], 108, 142, 742, "center")
    love.graphics.setColor(0.86, 0.91, 0.90)
    love.graphics.printf(page[2], 118, 208, 722, "left")
    love.graphics.setColor(0.66, 0.76, 0.76)
    love.graphics.printf(string.format("PAGE %d / %d", Screen.helpStep, #cutterHelp), 118, 490, 722, "center")
    BackButton.draw(assets, helpBack, "BACK", pointerX, pointerY, false)
    BackButton.draw(assets, helpPrevious, "◀ PREV", pointerX, pointerY, false)
    BackButton.draw(assets, helpNext, Screen.helpStep == #cutterHelp and "DONE" or "NEXT ▶", pointerX, pointerY, false)
end

local function drawHelpButton(pointerX, pointerY)
    local hovered = pointerX and inside(helpButton, pointerX, pointerY)
    box(helpButton.x, helpButton.y, helpButton.width, helpButton.height,
        hovered and { 0.20, 0.39, 0.49, 1 } or { 0.12, 0.27, 0.34, 1 },
        { 0.48, 0.74, 0.80, 1 }, 3)
    love.graphics.setColor(0.94, 0.97, 0.92)
    love.graphics.printf("HELP / INSTRUCTIONS", helpButton.x, helpButton.y + 13, helpButton.width, "center")
end

local function drawMaintenanceButton(pointerX, pointerY)
    local hovered = pointerX and inside(maintenanceButton, pointerX, pointerY)
    box(maintenanceButton.x, maintenanceButton.y, maintenanceButton.width, maintenanceButton.height,
        hovered and { 0.16, 0.43, 0.34, 1 } or { 0.11, 0.30, 0.26, 1 },
        { 0.42, 0.72, 0.58, 1 }, 3)
    love.graphics.setColor(0.94, 0.97, 0.92)
    love.graphics.printf("MAINTENANCE", maintenanceButton.x, maintenanceButton.y + 13,
        maintenanceButton.width, "center")
end

local function drawMaintenanceCard(rect, title, detail, enabled, pointerX, pointerY)
    local hovered = enabled and pointerX and inside(rect, pointerX, pointerY)
    box(rect.x, rect.y, rect.width, rect.height,
        enabled and (hovered and { 0.13, 0.34, 0.31, 1 } or { 0.08, 0.20, 0.20, 1 })
            or { 0.09, 0.10, 0.11, 1 },
        enabled and { 0.34, 0.65, 0.57, 1 } or { 0.25, 0.29, 0.30, 1 }, 4)
    love.graphics.setColor(enabled and 0.96 or 0.48, enabled and 0.84 or 0.53, enabled and 0.30 or 0.52)
    love.graphics.print(title, rect.x + 18, rect.y + 16)
    love.graphics.setColor(enabled and 0.76 or 0.46, enabled and 0.84 or 0.51, enabled and 0.83 or 0.51)
    love.graphics.printf(detail, rect.x + 18, rect.y + 46, rect.width - 36, "left")
end

local function drawMaintenanceHub(state, assets, pointerX, pointerY)
    local item, cutter = MachineMaintenance.cutterStatus(state)
    local stock = state.inventory and state.inventory.stock or {}
    box(18, 18, 924, 642, { 0.035, 0.055, 0.065, 0.995 }, { 0.35, 0.68, 0.61, 1 }, 5)
    love.graphics.setColor(0.96, 0.82, 0.26)
    love.graphics.print("POLAR 115 MAINTENANCE CENTER", 46, 38)
    love.graphics.setColor(0.72, 0.82, 0.82)
    love.graphics.print("Choose a service procedure. Each task opens its own interactive work area.", 46, 68)
    drawCondition(state, "polar_115", 580, 36, 310)
    box(54, 108, 836, 92, { 0.07, 0.10, 0.12, 1 }, { 0.25, 0.42, 0.43, 1 }, 3)
    love.graphics.setColor(0.76, 0.84, 0.84)
    love.graphics.print("MAINTENANCE KITS", 74, 126)
    love.graphics.setColor((stock.maintenance_kit or 0) > 0 and 0.48 or 0.94,
        (stock.maintenance_kit or 0) > 0 and 0.88 or 0.34, 0.36)
    love.graphics.print(tostring(stock.maintenance_kit or 0) .. " AVAILABLE", 74, 153)
    love.graphics.setColor(0.76, 0.84, 0.84)
    love.graphics.print("BLADE", 330, 126)
    love.graphics.print(cutter.bladeInSleeve and "SECURED IN WOODEN SLEEVE"
        or cutter.bladeRemoved and "REMOVED" or "INSTALLED", 330, 153)
    love.graphics.print("TECHNICIAN", 620, 126)
    local appointment = cutter.nextTechnicianDay
        and BusinessCalendar.dateFromTotalDay(cutter.nextTechnicianDay) or nil
    love.graphics.print(appointment and string.format("%s %d", BusinessCalendar.monthName(appointment.month), appointment.day)
        or "NOT SCHEDULED", 620, 153)
    drawMaintenanceCard(oilServiceButton, "LUBRICATE THE CUTTER",
        "Lockout, clean and grease the service fittings, then inspect the gearbox sight glass. Uses one kit.",
        (stock.maintenance_kit or 0) > 0 and not cutter.bladeRemoved, pointerX, pointerY)
    drawMaintenanceCard(bladeServiceButton, "REMOVE & SLEEVE BLADE",
        cutter.bladeInSleeve and "Blade is ready for Precision Blade Service."
            or "Release the fasteners, remove the knife, and secure it inside the wooden transport sleeve.",
        not cutter.bladeInSleeve, pointerX, pointerY)
    drawMaintenanceCard(technicianButton, "REQUEST TECHNICIAN",
        cutter.bladeInSleeve and "Book the next available blade-sharpening visit."
            or "Prepare the blade in its sleeve before booking.",
        cutter.bladeInSleeve and not cutter.nextTechnicianDay, pointerX, pointerY)
    drawMaintenanceCard(weeklyButton, cutter.weeklyTechnician and "WEEKLY SERVICE: ON" or "WEEKLY SERVICE: OFF",
        cutter.weeklyTechnician and "Click to cancel the recurring appointment."
            or "Schedule a technician every seven game days. Delays or missed visits arrive by email.",
        true, pointerX, pointerY)
    drawMaintenanceCard(maintenanceBack, "RETURN TO CUTTER", "", true, pointerX, pointerY)
    love.graphics.setColor(0.70, 0.78, 0.79)
    love.graphics.print(state.message or "", 270, 610)
end

local wrapperServiceButton = { x = 650, y = 520, width = 240, height = 54 }

local function wrapperHealthColor(value)
    if value >= 75 then return 0.30, 0.82, 0.48
    elseif value >= 50 then return 0.94, 0.70, 0.22 end
    return 0.92, 0.32, 0.24
end

local function drawWrapperHealthBar(x, y, width, value)
    local r, g, b = wrapperHealthColor(value)
    love.graphics.setColor(0.10, 0.13, 0.14)
    love.graphics.rectangle("fill", x, y, width, 7, 2, 2)
    love.graphics.setColor(r, g, b)
    love.graphics.rectangle("fill", x, y, width * math.max(0, math.min(100, value)) / 100, 7, 2, 2)
end

local function drawWrapperMaintenanceHub(state, pointerX, pointerY)
    local item = MachineFleet.installed(state, "skid_wrapper")
    local stock = state.inventory and state.inventory.stock or {}
    local plan = item and MachineFleet.maintenancePlan(state, item.id)
    local nearby = Wrapper.nearbyPallet(state)
    local safetyReady = not Wrapper.isActive() and not nearby
    local kitReady = (stock.maintenance_kit or 0) > 0
    box(18, 18, 924, 642, { 0.025, 0.05, 0.055, 0.995 }, { 0.35, 0.72, 0.60, 1 }, 5)
    love.graphics.setColor(0.96, 0.82, 0.26)
    love.graphics.print("SKID WRAPPER SERVICE BAY", 46, 36)
    love.graphics.setColor(0.70, 0.82, 0.82)
    love.graphics.print("Hands-on inspection follows the turntable, film carriage, drive, and controls.", 46, 66)
    drawCondition(state, "skid_wrapper", 562, 36, 328)

    box(54, 98, 836, 50, { 0.07, 0.11, 0.12, 1 }, { 0.25, 0.43, 0.43, 1 }, 3)
    love.graphics.setColor(0.76, 0.84, 0.84)
    love.graphics.print("SAFETY CHECK", 74, 116)
    love.graphics.setColor(safetyReady and 0.35 or 0.94, safetyReady and 0.86 or 0.34, 0.42)
    love.graphics.print(safetyReady and "CLEAR: STOPPED / TURNTABLE EMPTY" or
        (Wrapper.isActive() and "BLOCKED: WRAPPING CYCLE ACTIVE" or "BLOCKED: MOVE PALLET AWAY FIRST"), 250, 116)
    love.graphics.setColor(0.76, 0.84, 0.84)
    love.graphics.print("KIT", 720, 116)
    love.graphics.setColor(kitReady and 0.35 or 0.94, kitReady and 0.86 or 0.34, 0.42)
    love.graphics.print(tostring(stock.maintenance_kit or 0), 770, 116)

    if plan then
        for index, task in ipairs(plan.tasks) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            local x, y = 54 + column * 412, 168 + row * 142
            local value = tonumber(item.variables[task.id]) or 0
            local r, g, b = wrapperHealthColor(value)
            box(x, y, 390, 122, { 0.065, 0.105, 0.11, 1 }, { 0.24, 0.40, 0.41, 1 }, 4)
            love.graphics.setColor(0.95, 0.85, 0.38)
            love.graphics.print(string.format("%d  %s", index, task.componentLabel:upper()), x + 16, y + 14)
            love.graphics.setColor(0.72, 0.81, 0.81)
            love.graphics.printf(task.label, x + 16, y + 42, 350, "left")
            love.graphics.setColor(r, g, b)
            love.graphics.print(string.format("HEALTH  %.1f%%", value), x + 16, y + 78)
            drawWrapperHealthBar(x + 150, y + 84, 220, value)
        end
    end
    local startEnabled = item and safetyReady and kitReady
    local hovered = startEnabled and inside(wrapperServiceButton, pointerX or -1, pointerY or -1)
    box(wrapperServiceButton.x, wrapperServiceButton.y, wrapperServiceButton.width, wrapperServiceButton.height,
        startEnabled and (hovered and { 0.18, 0.50, 0.36, 1 } or { 0.12, 0.38, 0.28, 1 })
            or { 0.14, 0.17, 0.17, 1 }, { 0.35, 0.70, 0.50, 1 }, 3)
    love.graphics.setColor(0.95, 0.98, 0.92)
    love.graphics.printf(startEnabled and "START FULL SERVICE" or "SERVICE LOCKED",
        wrapperServiceButton.x, wrapperServiceButton.y + 19, wrapperServiceButton.width, "center")
    drawMaintenanceCard(maintenanceBack, "RETURN TO WRAPPER", "", true, pointerX, pointerY)
    love.graphics.setColor(0.70, 0.78, 0.79)
    love.graphics.print(state.message or "", 270, 610)
end

local function drawWrapperTarget(x, y, active, complete, clock)
    if complete then
        love.graphics.setColor(0.24, 0.85, 0.48, 0.92)
        love.graphics.circle("fill", x, y, 16)
    elseif active then
        local pulse = 24 + math.sin(clock * 6) * 5
        love.graphics.setColor(0.98, 0.72, 0.18, 0.22)
        love.graphics.circle("fill", x, y, pulse)
        love.graphics.setColor(1, 0.84, 0.30, 1)
        love.graphics.circle("line", x, y, 18)
    else
        love.graphics.setColor(0.42, 0.53, 0.52, 0.68)
        love.graphics.circle("line", x, y, 13)
    end
    love.graphics.setColor(0.04, 0.06, 0.06, 1)
    love.graphics.circle("fill", x, y, 5)
end

local function drawWrapperMaintenanceTask(state, assets, pointerX, pointerY)
    local session = Screen.wrapperSession
    local task = session and MachineMaintenance.activeTask(session)
    local taskState = session and MachineMaintenance.wrapperTaskState(session)
    if not session or not task or not taskState then return end
    local image = assets.get("wrapperMaintenanceAtlas")
    local sprite = assets.getQuad("wrapperMaintenance" .. ({
        turntableBearing = 1, filmCarriage = 2, driveBelt = 3, controlBoard = 4,
    })[task.id])
    box(18, 18, 924, 642, { 0.025, 0.04, 0.05, 0.995 }, { 0.45, 0.72, 0.60, 1 }, 5)
    love.graphics.setColor(0.96, 0.82, 0.26)
    love.graphics.print(string.format("WRAPPER SERVICE  /  STEP %d OF %d", session.activeIndex, #session.tasks), 42, 34)
    love.graphics.setColor(0.72, 0.81, 0.81)
    love.graphics.print("Use the marked service points in sequence. Every miss reduces the repair quality.", 42, 62)
    box(54, 104, 520, 438, { 0.06, 0.075, 0.08, 1 }, { 0.25, 0.39, 0.40, 1 }, 4)
    if image and sprite then
        local scale = math.min(430 / sprite.width, 360 / sprite.height)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(image, sprite.quad, 314, 324, 0, scale, scale, sprite.width / 2, sprite.height / 2)
    end
    local targetCount = task.id == "driveBelt" and 1 or 3
    for index = 1, targetCount do
        local tx, ty = MachineMaintenance.wrapperTarget(session, index)
        if tx and ty then
            drawWrapperTarget(tx, ty, index == taskState.phase,
                index < taskState.phase, session.animationClock)
        end
    end
    local rightX, rightY, rightW = 612, 104, 278
    box(rightX, rightY, rightW, 438, { 0.065, 0.10, 0.105, 1 }, { 0.25, 0.43, 0.42, 1 }, 4)
    love.graphics.setColor(0.95, 0.85, 0.38)
    love.graphics.printf(task.componentLabel:upper(), rightX + 18, rightY + 18, rightW - 36, "left")
    love.graphics.setColor(0.82, 0.88, 0.87)
    love.graphics.printf(task.label, rightX + 18, rightY + 52, rightW - 36, "left")
    local instruction = task.id == "turntableBearing" and "Click the three bearing grease fittings around the turntable."
        or task.id == "filmCarriage" and "Follow the carriage service points from the upper roller to the lower guide."
        or task.id == "driveBelt" and "Click the moving tension target when it crosses the green timing band."
        or "Test the control cabinet points in order: power, safety loop, then reset."
    love.graphics.setColor(0.64, 0.75, 0.75)
    love.graphics.printf(instruction, rightX + 18, rightY + 102, rightW - 36, "left")
    love.graphics.setColor(0.78, 0.86, 0.84)
    love.graphics.print(string.format("TARGET  %d / %d", math.min(taskState.phase, targetCount), targetCount), rightX + 18, rightY + 200)
    love.graphics.print(string.format("ATTEMPTS  %d", taskState.attempts), rightX + 18, rightY + 232)
    love.graphics.print(string.format("MISSES  %d", taskState.misses), rightX + 18, rightY + 264)
    local progress = math.min(1, (taskState.phase - 1) / targetCount)
    love.graphics.setColor(0.10, 0.14, 0.14)
    love.graphics.rectangle("fill", rightX + 18, rightY + 310, rightW - 36, 12, 3, 3)
    love.graphics.setColor(0.30, 0.82, 0.48)
    love.graphics.rectangle("fill", rightX + 18, rightY + 310, (rightW - 36) * progress, 12, 3, 3)
    love.graphics.setColor(0.96, 0.74, 0.24)
    love.graphics.printf(task.id == "driveBelt" and "TIMING TARGET MOVING" or "SEQUENCE TARGET ACTIVE",
        rightX + 18, rightY + 346, rightW - 36, "center")
    drawMaintenanceCard(maintenanceBack, "CANCEL SERVICE", "", true, pointerX, pointerY)
    love.graphics.setColor(0.72,0.82,0.82)
    love.graphics.printf("No kit is consumed until all four tasks are complete.",280,608,590,"left")
end

local function drawSmallAction(rect, label, active, complete, pointerX, pointerY)
    local hovered = pointerX and inside(rect, pointerX, pointerY)
    box(rect.x, rect.y, rect.width, rect.height,
        complete and { 0.12, 0.38, 0.24, 1 } or active and { 0.12, 0.34, 0.36, 1 }
            or hovered and { 0.15, 0.22, 0.23, 1 } or { 0.08, 0.12, 0.13, 1 },
        complete and { 0.35, 0.88, 0.48, 1 } or { 0.34, 0.56, 0.56, 1 }, 3)
    love.graphics.setColor(complete and { 0.55, 1, 0.65 } or { 0.88, 0.91, 0.88 })
    love.graphics.printf(label, rect.x, rect.y + rect.height / 2 - 7, rect.width, "center")
end

local function drawToolSprite(assets, frame, x, y, scale)
    local image, quad = assets.get("cutterMaintenanceTools"), assets.getQuad("cutterMaintenanceTool" .. frame)
    if image and quad then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(image, quad.quad, x, y, 0, scale or 0.45, scale or 0.45,
            quad.width / 2, quad.height / 2)
    end
end

local function drawOilingGame(state, assets, pointerX, pointerY)
    local session = Screen.oilSession
    box(18, 18, 924, 642, { 0.025, 0.04, 0.05, 0.995 }, { 0.42, 0.72, 0.61, 1 }, 5)
    love.graphics.setColor(0.96, 0.82, 0.26)
    love.graphics.print("POLAR 115 LUBRICATION PROCEDURE", 42, 34)
    love.graphics.setColor(0.70, 0.80, 0.81)
    love.graphics.print("Lock out power, prepare the grease gun, clean each fitting, couple, then pump 2-3 strokes.", 42, 62)
    love.graphics.setColor(0.10, 0.14, 0.14)
    love.graphics.rectangle("fill", 42, 88, 860, 10, 3, 3)
    love.graphics.setColor(0.30, 0.82, 0.48)
    love.graphics.rectangle("fill", 42, 88, 860 * MachineMaintenance.lubricationProgress(session), 10, 3, 3)
    if session.stage == "lockout" then
        love.graphics.setColor(0.92, 0.70, 0.22)
        love.graphics.printf("STEP 1  /  LOCKOUT-TAGOUT — COMPLETE IN ORDER", 80, 135, 800, "center")
        drawSmallAction(lockoutButtons.disconnect, "1. MAIN DISCONNECT OFF",
            not session.lockout.disconnect, session.lockout.disconnect, pointerX, pointerY)
        drawSmallAction(lockoutButtons.key, "2. REMOVE KEY",
            session.lockout.disconnect and not session.lockout.key, session.lockout.key, pointerX, pointerY)
        drawSmallAction(lockoutButtons.tag, "3. APPLY LOCK + TAG",
            session.lockout.key and not session.lockout.tag, session.lockout.tag, pointerX, pointerY)
        drawToolSprite(assets, 5, 750, 310, 0.46)
        love.graphics.setColor(0.70, 0.78, 0.78)
        love.graphics.printf("The cutter cannot be serviced while energized.", 170, 455, 620, "center")
    elseif session.stage == "prep" then
        love.graphics.setColor(0.92, 0.70, 0.22)
        love.graphics.printf("STEP 2  /  PREPARE THE HIGH-PRESSURE GREASE GUN", 80, 135, 800, "center")
        drawSmallAction(prepButtons.cartridge, "1. INSTALL GREASE CARTRIDGE",
            not session.prep.cartridge, session.prep.cartridge, pointerX, pointerY)
        drawSmallAction(prepButtons.prime, "2. PRIME THE GUN",
            session.prep.cartridge and not session.prep.primed, session.prep.primed, pointerX, pointerY)
        drawToolSprite(assets, 6, 310, 325, 0.55)
        drawToolSprite(assets, session.prep.cartridge and 2 or 1, 650, 325, 0.50)
    else
        for index, view in ipairs(lubricationViews) do
            local rect = { x = 42 + (index - 1) * 113, y = 112, width = 105, height = 34 }
            local disabled = view == "central" and not session.centralInstalled
            drawSmallAction(rect, disabled and "CENTRAL N/A" or view:upper(),
                session.activeView == view, false, pointerX, pointerY)
        end
        box(42, 158, 570, 386, { 0.06, 0.075, 0.08, 1 }, { 0.25, 0.39, 0.40, 1 }, 4)
        local sceneFrames = { rear = 1, front = 2, side = 3, central = 2, gear = 4 }
        local image = assets.get("cutterMaintenanceScenes")
        local quad = assets.getQuad("cutterMaintenanceScene" .. sceneFrames[session.activeView])
        if image and quad then
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(image, quad.quad, 48, 160, 0, 1.09, 1.0)
        end
        if session.activeView == "gear" then
            love.graphics.setColor(session.gear.inspected and { 0.30, 0.90, 0.48 } or { 1, 0.76, 0.22 })
            love.graphics.circle("line", 490, 340, 34 + math.sin(session.animationClock * 4) * 3)
            love.graphics.printf(string.format("SIGHT GLASS  %d%%", math.floor(session.gear.level * 100 + 0.5)), 350, 475, 230, "center")
        elseif session.activeView == "central" then
            local p = session.central
            love.graphics.setColor(p.complete and { 0.30, 0.90, 0.48 } or { 1, 0.76, 0.22 })
            love.graphics.circle("line", 370, 330, 23 + math.sin(session.animationClock * 4) * 3)
        else
            for _, p in ipairs(session.points) do if p.view == session.activeView then
                love.graphics.setColor(p.complete and { 0.30, 0.90, 0.48 }
                    or p.cleaned and { 0.32, 0.76, 0.88 } or { 1, 0.72, 0.18 })
                love.graphics.circle("fill", p.x, p.y, p.complete and 11 or 8)
                love.graphics.circle("line", p.x, p.y, 18 + math.sin(session.animationClock * 5) * 3)
            end end
        end
        box(632, 158, 270, 386, { 0.055, 0.09, 0.095, 1 }, { 0.25, 0.43, 0.42, 1 }, 4)
        for index, tool in ipairs(lubricationTools) do
            local rect = { x = 650, y = 176 + (index - 1) * 48, width = 234, height = 39 }
            drawSmallAction(rect, ({ rag="CLEANING RAG", grease="GREASE GUN", inspect="INSPECT LIGHT", gear_oil="GEAR OIL" })[tool],
                session.activeTool == tool, false, pointerX, pointerY)
        end
        local status = session.coupledPoint and (session.coupledPoint == "central" and session.central
            or MachineMaintenance.lubricationPoint(session, session.coupledPoint)) or nil
        love.graphics.setColor(0.72, 0.82, 0.82)
        love.graphics.printf(status and string.format("COUPLED  /  %d STROKES", status.strokes) or
            "RAG: clean fitting\nGUN: click fitting to couple\nINSPECT: click sight glass", 650, 372, 234, "center")
        if status then
            local gunFrame = session.pumpPulse and session.pumpPulse > 0
                and (session.pumpPulse > 0.14 and 3 or 2) or 1
            drawToolSprite(assets, gunFrame, 767, 424, 0.25)
        end
        drawSmallAction(pumpButton, "PUMP GREASE-GUN LEVER", status ~= nil, false, pointerX, pointerY)
        drawSmallAction(finishLubricationButton, "RETURN TO SERVICE",
            MachineMaintenance.canFinishCutterLubrication(session), false, pointerX, pointerY)
    end
    drawSmallAction(maintenanceBack, "CANCEL PROCEDURE", false, false, pointerX, pointerY)
end

local function bladeBoltPositions()
    return { { 332, 258 }, { 628, 258 }, { 332, 350 }, { 628, 350 } }
end

local function drawBladeGame(state, pointerX, pointerY)
    box(18, 18, 924, 642, { 0.03, 0.045, 0.055, 0.995 }, { 0.55, 0.46, 0.30, 1 }, 5)
    love.graphics.setColor(0.96, 0.82, 0.26)
    love.graphics.print("CUTTER BLADE REMOVAL", 42, 34)
    love.graphics.setColor(0.72, 0.80, 0.81)
    local instruction = Screen.bladeStage == "bolts" and "Click all four blade-carrier fasteners."
        or Screen.bladeStage == "blade" and "Click the released steel blade to remove it."
        or "Click the wooden sleeve to secure the blade for transport."
    love.graphics.print(instruction, 42, 64)
    box(140, 120, 680, 420, { 0.08, 0.09, 0.095, 1 }, { 0.34, 0.36, 0.37, 1 }, 4)
    love.graphics.setColor(0.56, 0.59, 0.60)
    love.graphics.rectangle("fill", 280, 220, 400, 178, 4, 4)
    love.graphics.setColor(0.82, 0.84, 0.80)
    love.graphics.rectangle("fill", 304, 294, 352, 34, 2, 2)
    for index, pos in ipairs(bladeBoltPositions()) do
        local removed = Screen.bladeBolts[index]
        love.graphics.setColor(removed and 0.18 or 0.76, removed and 0.20 or 0.68, removed and 0.20 or 0.28)
        love.graphics.circle("fill", pos[1], pos[2], 14)
        love.graphics.setColor(0.15, 0.16, 0.16)
        love.graphics.line(pos[1] - 7, pos[2], pos[1] + 7, pos[2])
    end
    love.graphics.setColor(0.46, 0.25, 0.10)
    love.graphics.rectangle("fill", 330, 445, 300, 60, 5, 5)
    love.graphics.setColor(0.72, 0.47, 0.22)
    love.graphics.rectangle("line", 330, 445, 300, 60, 5, 5)
    love.graphics.printf("WOODEN BLADE SLEEVE", 330, 469, 300, "center")
    drawMaintenanceCard(maintenanceBack, "CANCEL BLADE WORK", "", true, pointerX, pointerY)
end

local function openLoadMenu(state)
    if Machine.step ~= "idle" and Machine.step ~= "finished" then
        state.message = "Finish or unload the current cutter batch before choosing another pallet."
        return false
    end
    local options = {}
    for _, candidate in ipairs(Machine.availablePapers(state)) do
        local world = candidate.pallet.world or {}
        options[#options + 1] = {
            palletId = candidate.pallet.id,
            title = candidate.pallet.id .. "  |  " .. tostring(candidate.job.company or candidate.job.id),
            detail = string.format("%s  |  %d sheets  |  %.0f px from feed zone",
                tostring(candidate.paper.artworkKey or "artwork"),
                candidate.pallet.remainingSheets or candidate.pallet.initialSheets or 0,
                math.sqrt(candidate.inputDistance or 0)),
            x = world.x, y = world.y,
        }
    end
    if #options == 0 and Procurement.paperAvailable(state) > 0 then
        options[1] = {
            palletId = "__generic_stock__",
            title = "GENERIC SHOP STOCK",
            detail = string.format("%d stock sheets available", Procurement.paperAvailable(state)),
        }
    end
    if #options == 0 then
        state.message = "No unfinished pallet is inside the cutter's expanded load radius."
        return false
    end
    Screen.loadMenu = { options = options, selected = 1 }
    Screen.gaugeFocused = false
    state.message = "Choose which nearby pallet to load onto the cutter."
    return true
end

local function loadSelected(state, index)
    local menu = Screen.loadMenu
    local option = menu and menu.options[index or menu.selected]
    if not option then return false end
    local succeeded = Machine.load(state, option.palletId)
    if succeeded then
        Screen.loadMenu = nil
        formatGauge()
    end
    return succeeded
end

function Screen.syncGauge()
    formatGauge()
end

local function drawButton(button)
    if button.action == "cut_left" or button.action == "cut_right" or button.action == "estop" then return end
    local active = Screen.pressedAction == button.action
    if button.action == "program" then active = Machine.programIndex == button.value end
    box(button.x, button.y + (active and 2 or 0), button.width, button.height,
        active and { 0.18, 0.52, 0.68, 1 } or { 0.13, 0.18, 0.23, 1 },
        active and { 0.55, 0.90, 1, 1 } or { 0.35, 0.48, 0.56, 1 }, 3)
    love.graphics.setColor(0.92, 0.95, 0.95)
    love.graphics.printf(button.label, button.x, button.y + 9 + (active and 2 or 0), button.width, "center")
end

local function drawSpriteButton(assets, button, red, pressed)
    local image = assets.get("cutterControlButtons")
    local frame = red and (pressed and 4 or 3) or (pressed and 2 or 1)
    local sprite = assets.getQuad("cutterControlButton" .. frame)
    if not image or not sprite then return end
    local scale = math.min(button.width / sprite.width, button.height / sprite.height)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(image, sprite.quad, button.x + button.width / 2, button.y,
        0, scale, scale, sprite.width / 2, 0)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(button.label, button.x, button.y + button.height - 12, button.width, "center")
end

function Screen.drawCutterButton(assets, button, red, pressed)
    drawSpriteButton(assets, button, red, pressed)
end

local function artworkColor(id, offset)
    local hash = offset * 97
    for index = 1, #(id or "ART") do hash = (hash * 33 + id:byte(index)) % 997 end
    return 0.25 + (hash % 55) / 100, 0.25 + ((hash * 3) % 55) / 100, 0.25 + ((hash * 7) % 55) / 100
end

local function drawPaper(assets, machine)
    local paper = machine.paper
    if not machine.loaded or not paper then return end
    local step, t = machine.step, 1
    if step == "loading" then t = math.min(1, machine.progress / machine.transferTime)
    elseif step == "positioning" then t = math.min(1, machine.progress / machine.transferTime)
    elseif step == "unloading" or step == "lift_returning" then
        t = 1 - math.min(1, machine.progress / machine.transferTime)
    end
    local startY, bedY, gaugeY = 355, 264, 218
    local y
    if step == "loading" then y = startY + (bedY - startY) * t
    elseif step == "loaded" then y = bedY
    elseif step == "positioning" then y = bedY + (gaugeY - bedY) * t
    elseif step == "unloading" or step == "lift_returning" then y = startY + (gaugeY - startY) * t
    else y = gaugeY end
    local rotated = paper.orientation % 180 == 90
    local widthValue = rotated and paper.currentSize.height or paper.currentSize.width
    local heightValue = rotated and paper.currentSize.width or paper.currentSize.height
    local width = math.max(100, math.min(270, widthValue / 25 * 270))
    local height = math.max(50, math.min(125, heightValue / 25 * 125))
    local x = 662 - width / 2
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.rectangle("fill", x + 5, y + 8, width, height)
    love.graphics.setColor(0.96, 0.95, 0.86)
    love.graphics.rectangle("fill", x, y, width, height)
    love.graphics.setColor(0.72, 0.74, 0.72)
    love.graphics.rectangle("line", x, y, width, height)
    local removed = {}
    for _, cut in ipairs(paper.history or {}) do removed[cut.edge] = true end
    local margins = {
        left = removed.left and 0 or paper.margins.left,
        right = removed.right and 0 or paper.margins.right,
        top = removed.top and 0 or paper.margins.top,
        bottom = removed.bottom and 0 or paper.margins.bottom,
    }
    local orientation = paper.orientation % 360
    local screenMargins
    if orientation == 90 then
        screenMargins = { left = margins.bottom, right = margins.top, top = margins.left, bottom = margins.right }
    elseif orientation == 180 then
        screenMargins = { left = margins.right, right = margins.left, top = margins.bottom, bottom = margins.top }
    elseif orientation == 270 then
        screenMargins = { left = margins.top, right = margins.bottom, top = margins.right, bottom = margins.left }
    else
        screenMargins = margins
    end
    local innerX = x + math.min(width * 0.45, screenMargins.left / widthValue * width)
    local innerY = y + math.min(height * 0.45, screenMargins.top / heightValue * height)
    local innerRight = x + width - math.min(width * 0.45, screenMargins.right / widthValue * width)
    local innerBottom = y + height - math.min(height * 0.45, screenMargins.bottom / heightValue * height)
    local innerWidth, innerHeight = math.max(8, innerRight - innerX), math.max(8, innerBottom - innerY)
    local r1, g1, b1 = artworkColor(paper.artworkId, 1)
    local r2, g2, b2 = artworkColor(paper.artworkId, 2)
    love.graphics.setColor(r1, g1, b1)
    love.graphics.rectangle("fill", innerX, innerY, innerWidth, innerHeight)
    local artwork = assets and assets.getArtwork and assets.getArtwork(paper.artworkKey)
    if artwork then
        local angle = Screen.artworkRotation(paper)
        local quarterTurn = paper.orientation % 180 == 90
        local scaleX = (quarterTurn and innerHeight or innerWidth) / artwork:getWidth()
        local scaleY = (quarterTurn and innerWidth or innerHeight) / artwork:getHeight()
        love.graphics.setColor(1, 1, 1, 0.96)
        love.graphics.draw(artwork, innerX + innerWidth / 2, innerY + innerHeight / 2,
            angle, scaleX, scaleY, artwork:getWidth() / 2, artwork:getHeight() / 2)
    else
        love.graphics.setColor(r2, g2, b2)
        love.graphics.rectangle("fill", innerX + innerWidth * 0.25, innerY + innerHeight * 0.25,
            innerWidth * 0.5, innerHeight * 0.5)
    end
    love.graphics.setColor(0.86, 0.18, 0.18, 0.9)
    love.graphics.setLineStyle("rough")
    love.graphics.rectangle("line", innerX, innerY, innerWidth, innerHeight)
    if paper.offSpec then
        local lineWidth = love.graphics.getLineWidth()
        love.graphics.setLineWidth(3)
        love.graphics.line(x, y, x + width, y + height)
        love.graphics.line(x + width, y, x, y + height)
        love.graphics.setLineWidth(lineWidth)
    end
    love.graphics.setLineStyle("smooth")
end

local function motionFrame(progress)
    return math.max(1, math.min(5, math.floor(progress * 4 + 0.5) + 1))
end

local function drawMotion(assets, name, imageName, progress)
    local image, sprite = assets.get(imageName), assets.getQuad(name .. motionFrame(progress))
    if not image or not sprite then return end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(image, sprite.quad, 400, 78, 0, 520 / 768, 347 / 512)
end

local function drawMachine(assets, machine)
    machine = machine or Machine
    local image = assets.get("polarOperatorConsole")
    if image then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(image, 400, 78, 0, 520 / image:getWidth(), 347 / image:getHeight())
    end
    drawPaper(assets, machine)
    drawMotion(assets, "cutterClamp", "cutterClamp", machine.clampProgress)
    if machine.step == "cutting" then drawMotion(assets, "cutterBlade", "cutterBlade", machine.progress / machine.cycleTime) end
end

-- Shared, read-only scene: remote callers supply a presentation model, never
-- replace the Machine singleton or execute local production to animate it.
function Screen.drawCutterScene(assets, machine, rect)
    love.graphics.push("all")
    love.graphics.translate(rect.x, rect.y)
    love.graphics.scale(rect.width / 520, rect.height / 347)
    love.graphics.translate(-400, -78)
    drawMachine(assets, machine)
    love.graphics.pop()
end

local function drawTouchscreen()
    if Screen.gaugeReplaceOnType then
        Screen.gaugeText = string.format("%.2f", Machine.gauge or 0)
    end
    box(38, 54, 326, 334, { 0.04, 0.075, 0.105, 1 }, { 0.44, 0.64, 0.72, 1 }, 4)
    box(50, 66, 302, 150, { 0.055, 0.13, 0.19, 1 }, { 0.20, 0.55, 0.72, 1 }, 2)
    love.graphics.setColor(0.52, 0.88, 1)
    love.graphics.print("PROGRAMMABLE BACKGAUGE", 62, 76)
    love.graphics.setColor(0.92, 0.96, 0.92)
    love.graphics.print(string.format("GAUGE  %06.2f in", Machine.gauge), 62, 101)
    if Machine.paper then
        local cut = Machine.paper.cuts[Machine.programIndex]
        love.graphics.print(string.format("P%d  %-6s  trim %.2f", Machine.programIndex, cut.edge:upper(), cut.margin), 62, 126)
        love.graphics.print(string.format("TARGET %06.2f   ROT %03d", cut.gauge, cut.orientation), 62, 149)
        love.graphics.print(string.format("NOW    %.2f x %.2f in", Machine.paper.currentSize.width, Machine.paper.currentSize.height), 62, 172)
        if Machine.pallet then
            love.graphics.setColor(0.35, 0.95, 0.38)
            love.graphics.print(string.format("LIFT %d/%d   %d SHEETS LEFT",
                Machine.pallet.activeLift or 1, Machine.pallet.requiredLifts or 1,
                Machine.pallet.remainingSheets or 0), 62, 195)
        else
            love.graphics.setColor(Machine.programIndex == Machine.paper.activeCut and 0.35 or 0.95,
                Machine.programIndex == Machine.paper.activeCut and 0.95 or 0.45, 0.38)
            love.graphics.print(Machine.programIndex == Machine.paper.activeCut and "PROGRAM READY" or "SELECT NEXT CUT", 62, 195)
        end
    else
        love.graphics.print("NO PAPER BATCH LOADED", 62, 130)
    end
    box(gaugeInput.x, gaugeInput.y, gaugeInput.width, gaugeInput.height,
        Screen.gaugeFocused and { 0.07, 0.22, 0.29, 1 } or { 0.08, 0.11, 0.14, 1 },
        Screen.gaugeFocused and { 0.52, 0.88, 1, 1 } or { 0.32, 0.46, 0.52, 1 }, 3)
    love.graphics.setColor(0.68, 0.78, 0.80)
    love.graphics.print("TYPE", gaugeInput.x + 7, gaugeInput.y + 8)
    love.graphics.setColor(0.96, 0.98, 0.92)
    local shown = Screen.gaugeText .. (Screen.gaugeFocused and "_" or "")
    love.graphics.printf(shown, gaugeInput.x + 50, gaugeInput.y + 8, gaugeInput.width - 58, "right")
    for _, button in ipairs(buttons) do
        if button.y < 400 then drawButton(button) end
    end
end

local function drawLoadMenu()
    local menu = Screen.loadMenu
    if not menu then return end
    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle("fill", 0, 0, Config.baseWidth, Config.baseHeight)
    local pageStart = math.floor((menu.selected - 1) / loadMenuPageSize) * loadMenuPageSize + 1
    local pageEnd = math.min(#menu.options, pageStart + loadMenuPageSize - 1)
    local visibleCount = pageEnd - pageStart + 1
    local height = 86 + visibleCount * loadMenuRect.rowHeight
    box(loadMenuRect.x, loadMenuRect.y, loadMenuRect.width, height,
        { 0.035, 0.07, 0.095, 0.99 }, { 0.48, 0.76, 0.83, 1 }, 5)
    love.graphics.setColor(0.96, 0.82, 0.26)
    love.graphics.print("SELECT A PALLET FOR THE CUTTER", loadMenuRect.x + 20, loadMenuRect.y + 16)
    love.graphics.setColor(0.70, 0.80, 0.82)
    love.graphics.print("Click a row or press 1-7. Up/Down pages; Esc cancels.", loadMenuRect.x + 20, loadMenuRect.y + 40)
    for index = pageStart, pageEnd do
        local option = menu.options[index]
        local displayIndex = index - pageStart + 1
        local y = loadMenuRect.y + 68 + (displayIndex - 1) * loadMenuRect.rowHeight
        local selected = menu.selected == index
        box(loadMenuRect.x + 16, y, loadMenuRect.width - 32, loadMenuRect.rowHeight - 6,
            selected and { 0.12, 0.35, 0.43, 1 } or { 0.08, 0.12, 0.15, 1 },
            selected and { 0.52, 0.88, 1, 1 } or { 0.26, 0.39, 0.43, 1 }, 3)
        love.graphics.setColor(0.96, 0.98, 0.92)
        love.graphics.print(tostring(displayIndex) .. ".  " .. option.title, loadMenuRect.x + 28, y + 8)
        love.graphics.setColor(0.67, 0.78, 0.80)
        love.graphics.print(option.detail, loadMenuRect.x + 48, y + 27)
    end
end

function Screen.draw(state, assets, pointerX, pointerY)
    if Screen.helpOpen then drawHelp(state, assets, pointerX, pointerY); return end
    if Screen.maintenanceView == "hub" then
        drawMaintenanceHub(state, assets, pointerX, pointerY)
        return
    elseif Screen.maintenanceView == "wrapper_hub" then
        drawWrapperMaintenanceHub(state, pointerX, pointerY)
        return
    elseif Screen.maintenanceView == "wrapper_task" then
        drawWrapperMaintenanceTask(state, assets, pointerX, pointerY)
        return
    elseif Screen.maintenanceView == "oil" then
        drawOilingGame(state, assets, pointerX, pointerY)
        return
    elseif Screen.maintenanceView == "blade" then
        drawBladeGame(state, pointerX, pointerY)
        return
    end
    if state.machineType == "skid_wrapper" then
        box(18, 18, 924, 642, { 0.045, 0.055, 0.07, 0.99 }, { 0.38, 0.56, 0.62, 1 }, 5)
        love.graphics.setColor(0.96, 0.82, 0.26)
        love.graphics.print("SKID WRAPPER / PALLET PACKAGING CONSOLE", 38, 30)
        drawCondition(state, "skid_wrapper", 458, 28, 308)
        BackButton.draw(assets, exitButton, Wrapper.isActive() and "WAIT" or "EXIT", pointerX, pointerY, false)
        local image = assets.get("skidWrapperDirections")
        local sprite = assets.getQuad("skidWrapperDirection1")
        if image and sprite then
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(image, sprite.quad, 520, 360, 0, 0.72, 0.72, sprite.width / 2, sprite.height * 0.92)
        end
        local nearbyPallets = Wrapper.nearbyPallets(state)
        local nearby = Wrapper.nearbyPallet(state)
        local inventory = state.inventory or {}
        local packaging = nearby and (nearby.pallet.packaging or nearby.job.packaging or "flat") or nil
        local hasPackaging = packaging ~= "boxed" or Procurement.cartonsAvailable(state) > 0
        if nearby then
            local palletImage, palletQuad
            if Wrapper.step == "wrapping" or Wrapper.step == "finished" then
                local stage = Wrapper.step == "finished" and 3
                    or math.max(1, math.min(3, math.ceil(Wrapper.progress / Wrapper.cycleTime * 3)))
                palletImage = assets.get("wrappedPalletStages")
                palletQuad = assets.getQuad("wrappedPalletStage" .. stage)
            else
                palletImage = assets.get("loadedPaperPallet")
            end
            love.graphics.setColor(1, 1, 1)
            if palletImage and palletQuad then
                love.graphics.draw(palletImage, palletQuad.quad, 450, 390, 0, 0.42, 0.42, palletQuad.width / 2, palletQuad.height * 0.94)
            elseif palletImage then
                love.graphics.draw(palletImage, 450, 390, 0, 0.72, 0.72, palletImage:getWidth() / 2, palletImage:getHeight() * 0.94)
            end
        end
        love.graphics.setColor(0.96, 0.82, 0.26)
        love.graphics.print("CLICK A NEARBY PALLET", wrapperPalletList.x, wrapperPalletList.y - 22)
        if #nearbyPallets == 0 then
            box(wrapperPalletList.x, wrapperPalletList.y, wrapperPalletList.width,
                wrapperPalletList.rowHeight - 6, { 0.09, 0.11, 0.13, 0.94 },
                { 0.28, 0.34, 0.36, 1 }, 3)
            love.graphics.setColor(0.58, 0.66, 0.67)
            love.graphics.print("No finished pallets in range", wrapperPalletList.x + 12,
                wrapperPalletList.y + 13)
        else
            for index = 1, math.min(#nearbyPallets, wrapperPalletList.maxRows) do
                local option = nearbyPallets[index]
                local y = wrapperPalletList.y + (index - 1) * wrapperPalletList.rowHeight
                local selected = nearby and nearby.pallet.id == option.pallet.id
                local hovered = pointerX and inside({ x = wrapperPalletList.x, y = y,
                    width = wrapperPalletList.width, height = wrapperPalletList.rowHeight - 6 },
                    pointerX, pointerY)
                box(wrapperPalletList.x, y, wrapperPalletList.width,
                    wrapperPalletList.rowHeight - 6,
                    selected and { 0.12, 0.38, 0.27, 0.98 }
                        or (hovered and { 0.13, 0.24, 0.27, 0.98 } or { 0.08, 0.12, 0.14, 0.96 }),
                    selected and { 0.42, 0.90, 0.54, 1 } or { 0.28, 0.43, 0.46, 1 }, 3)
                love.graphics.setColor(0.94, 0.98, 0.92)
                love.graphics.print(tostring(index) .. ".  " .. option.pallet.id,
                    wrapperPalletList.x + 12, y + 6)
                love.graphics.setColor(0.66, 0.78, 0.78)
                love.graphics.print(string.format("%s  |  %s  |  %d px away",
                    tostring(option.job.company or option.job.id or "JOB"),
                    tostring(option.pallet.packaging or option.job.packaging or "flat"):upper(),
                    math.floor(math.sqrt(option.distance) + 0.5)),
                    wrapperPalletList.x + 30, y + 23)
            end
        end
        love.graphics.setColor(0.82, 0.88, 0.89)
        love.graphics.print("STATUS: " .. Wrapper.step:upper(), 50, 410)
        love.graphics.print("NEARBY PALLET: " .. (nearby and nearby.pallet.id or "NONE"), 50, 438)
        love.graphics.print("PACKAGE: " .. (packaging and packaging:upper() or "--"), 50, 466)
        love.graphics.print(string.format("PLASTIC: %d ROLL(S)  |  %d / 11 WRAPS", inventory.plasticWrapRolls or 0, inventory.plasticWrapUses or 0), 50, 494)
        local serviceHovered = pointerX and inside(wrapperMaintenanceButton, pointerX, pointerY)
        box(wrapperMaintenanceButton.x, wrapperMaintenanceButton.y,
            wrapperMaintenanceButton.width, wrapperMaintenanceButton.height,
            serviceHovered and { 0.16, 0.43, 0.34, 1 } or { 0.11, 0.30, 0.26, 1 },
            { 0.42, 0.72, 0.58, 1 }, 3)
        love.graphics.setColor(0.94, 0.97, 0.92)
        love.graphics.printf("SERVICE MACHINE", wrapperMaintenanceButton.x,
            wrapperMaintenanceButton.y + 19, wrapperMaintenanceButton.width, "center")
        box(wrapButton.x, wrapButton.y, wrapButton.width, wrapButton.height,
            nearby and hasPackaging and (inventory.plasticWrapUses or 0) > 0
                and { 0.15, 0.40, 0.27, 1 } or { 0.15, 0.17, 0.18, 1 },
            { 0.35, 0.65, 0.48, 1 }, 3)
        love.graphics.setColor(0.95, 0.98, 0.92)
        local jackReady = PalletJack.ensure(state, Config.palletJack).operating
            and not state.palletJack.carriedPalletId
        local wrapLabel = Wrapper.step == "wrapping"
            and string.format("WRAPPING %d%%", math.floor(Wrapper.progress / Wrapper.cycleTime * 100))
            or (jackReady and "WRAP PALLET [L]  RELOCATE [M]" or "WRAP PALLET [L]")
        love.graphics.printf(wrapLabel, wrapButton.x, wrapButton.y + 19, wrapButton.width, "center")
        love.graphics.print(state.message or "", 48, 635)
        return
    end
    layout()
    box(18, 18, 924, 642, { 0.045, 0.055, 0.07, 0.99 }, { 0.38, 0.56, 0.62, 1 }, 5)
    love.graphics.setColor(0.96, 0.82, 0.26)
    love.graphics.print("POLAR 115 / JOB CUTTING CONSOLE", 38, 30)
    drawCondition(state, "polar_115", 430, 28, 336)
    BackButton.draw(assets, exitButton, "EXIT", pointerX, pointerY, false)
    drawTouchscreen()
    drawMachine(assets)
    -- Top-level controls are deliberately drawn after the machine art so the
    -- cabinet can never cover them.
    drawHelpButton(pointerX, pointerY)
    drawMaintenanceButton(pointerX, pointerY)
    box(38, 400, 884, 58, { 0.075, 0.09, 0.11, 1 }, { 0.28, 0.40, 0.44, 1 }, 3)
    love.graphics.setColor(0.82, 0.88, 0.89)
    love.graphics.print("STATUS: " .. Machine.step:upper(), 50, 411)
    love.graphics.print("BARRIER: " .. (Machine.barrierClear and "CLEAR" or "BLOCKED"), 260, 411)
    love.graphics.print("CLAMP: " .. (Machine.clamp and "DOWN" or "UP"), 460, 411)
    love.graphics.print(Machine.paperTooltip(), 50, 435)
    for _, button in ipairs(buttons) do
        if button.y >= 400 and button.action ~= "cut_left" and button.action ~= "cut_right" and button.action ~= "estop" then drawButton(button) end
    end
    for _, button in ipairs(buttons) do
        if button.action == "cut_left" then drawSpriteButton(assets, button, false, Machine.leftDown)
        elseif button.action == "cut_right" then drawSpriteButton(assets, button, false, Machine.rightDown)
        elseif button.action == "estop" then drawSpriteButton(assets, button, true, Machine.emergencyStopped) end
    end
    love.graphics.setColor(0.75, 0.82, 0.83)
    love.graphics.print("Gauge + ENTER | L load | G auto | P position | Q rotate | SPACE clamp | "
        .. (Machine.multiplayerSingleControl and "J or K cut" or "J+K cut")
        .. " | T repeat | U unload", 48, 535)
    local memory = Machine.savedMeasurements(state, Machine.programIndex)
    local formattedMemory = {}
    for index, value in ipairs(memory) do formattedMemory[index] = string.format("%.2f", value) end
    local memoryText = #formattedMemory > 0 and table.concat(formattedMemory, " / ") or "NONE"
    love.graphics.print(string.format("P%d SAVED: %s", Machine.programIndex, memoryText), 50, 563)
    love.graphics.print(state.message or "", 48, 635)
    drawLoadMenu()
end

function Screen.mousepressed(state, x, y, button)
    if dependencies.remoteCommand and Screen.remoteServiceInput then
        local handled = Screen.remoteServiceInput(state, x, y, button)
        if handled ~= nil then return handled end
    end
    if button ~= 1 then return false end
    -- Android text input is opt-in: every non-field tap releases the gauge
    -- before the gauge hit target below can explicitly focus it again.
    Screen.gaugeFocused = false
    if Screen.helpOpen then
        if inside(helpBack, x, y) then Screen.helpOpen = false; return { action = "help_close" } end
        if inside(helpPrevious, x, y) then Screen.helpStep = math.max(1, Screen.helpStep - 1); return true end
        if inside(helpNext, x, y) then
            if Screen.helpStep < #cutterHelp then Screen.helpStep = Screen.helpStep + 1 else Screen.helpOpen = false end
            return true
        end
        return true
    end
    if Screen.maintenanceView == "wrapper_task" then
        if inside(maintenanceBack, x, y) then
            Screen.maintenanceView, Screen.wrapperSession = "wrapper_hub", nil
            return { action = "maintenance_cancel" }
        end
        local result = MachineMaintenance.wrapperTaskClick(Screen.wrapperSession, x, y)
        if result.hit then
            if result.finished then
                local completed, itemOrError = MachineMaintenance.commit(state, Screen.wrapperSession)
                if completed then
                    Screen.wrapperSession, Screen.maintenanceView = nil, "wrapper_hub"
                    state.message = string.format("Wrapper service complete. Condition is now %.1f%%.",
                        MachineFleet.condition(itemOrError))
                    return { action = "maintenance_completed" }
                end
                MachineMaintenance.rollbackLastTask(Screen.wrapperSession, result.task.id)
                Screen.wrapperSession.taskState[result.task.id] = nil
                state.message = tostring(itemOrError)
            elseif result.completedTask then
                local nextTask = MachineMaintenance.activeTask(Screen.wrapperSession)
                state.message = "Step complete. Next: " .. (nextTask and nextTask.componentLabel or "final inspection") .. "."
            end
        else
            state.message = "Missed the service point. Re-align and try again."
        end
        return true
    elseif Screen.maintenanceView == "wrapper_hub" then
        local item = MachineFleet.installed(state, "skid_wrapper")
        local stock = state.inventory and state.inventory.stock or {}
        local safetyReady = not Wrapper.isActive() and not Wrapper.nearbyPallet(state)
        if inside(maintenanceBack, x, y) then
            Screen.maintenanceView = nil
            return { action = "maintenance_close" }
        elseif inside(wrapperServiceButton, x, y) and item and safetyReady
            and (stock.maintenance_kit or 0) > 0 then
            local session, errorMessage = MachineMaintenance.beginWrapperService(state)
            if not session then state.message = tostring(errorMessage); return true end
            Screen.wrapperSession, Screen.maintenanceView = session, "wrapper_task"
            state.message = "Begin with the marked " .. session.tasks[1].componentLabel .. " service points."
            return { action = "maintenance_minigame", game = "wrapper_service" }
        end
        return true
    elseif Screen.maintenanceView == "oil" then
        if inside(maintenanceBack, x, y) then
            Screen.maintenanceView, Screen.oilSession = "hub", nil
            return { action = "maintenance_cancel" }
        end
        local session = Screen.oilSession
        if session.stage == "lockout" then
            for action, rect in pairs(lockoutButtons) do
                if inside(rect, x, y) then
                    MachineMaintenance.lubricationLockout(session, action)
                    return true
                end
            end
        elseif session.stage == "prep" then
            for action, rect in pairs(prepButtons) do
                if inside(rect, x, y) then
                    MachineMaintenance.lubricationPrepare(session, action)
                    return true
                end
            end
        else
            for index, view in ipairs(lubricationViews) do
                local rect = { x = 42 + (index - 1) * 113, y = 112, width = 105, height = 34 }
                if inside(rect, x, y) then
                    MachineMaintenance.selectLubricationView(session, view)
                    return true
                end
            end
            for index, tool in ipairs(lubricationTools) do
                local rect = { x = 650, y = 176 + (index - 1) * 48, width = 234, height = 39 }
                if inside(rect, x, y) then
                    MachineMaintenance.selectLubricationTool(session, tool)
                    return true
                end
            end
            if inside(pumpButton, x, y) then
                MachineMaintenance.pumpLubricationGun(session)
                return true
            elseif inside(finishLubricationButton, x, y) then
                local completed, result = MachineMaintenance.finishCutterLubrication(state, session)
                if completed then
                    Screen.maintenanceView, Screen.oilSession = "hub", nil
                    state.message = string.format("Cutter lubrication complete. Quality %.0f%%; condition %.1f%%.",
                        result.maintenance.lastServiceQuality * 100, result.condition)
                    return { action = "maintenance_completed" }
                end
                state.message = tostring(result)
                return true
            elseif session.activeView == "gear" and (x - 490) ^ 2 + (y - 340) ^ 2 <= 55 ^ 2 then
                if session.activeTool == "inspect" then MachineMaintenance.inspectGearOil(session)
                elseif session.activeTool == "gear_oil" then MachineMaintenance.topUpGearOil(session) end
                return true
            elseif session.activeView == "central" and (x - 370) ^ 2 + (y - 330) ^ 2 <= 45 ^ 2 then
                MachineMaintenance.serviceLubricationPoint(session, "central")
                return true
            else
                for _, point in ipairs(session.points) do
                    if point.view == session.activeView
                        and (x - point.x) ^ 2 + (y - point.y) ^ 2 <= 38 ^ 2 then
                        MachineMaintenance.serviceLubricationPoint(session, point.id)
                        return true
                    end
                end
            end
        end
        return true
    elseif Screen.maintenanceView == "blade" then
        if inside(maintenanceBack, x, y) then
            Screen.maintenanceView, Screen.bladeStage, Screen.bladeBolts = "hub", nil, nil
            return { action = "maintenance_cancel" }
        end
        if Screen.bladeStage == "bolts" then
            for index, pos in ipairs(bladeBoltPositions()) do
                if not Screen.bladeBolts[index] and (x - pos[1]) ^ 2 + (y - pos[2]) ^ 2 <= 24 ^ 2 then
                    Screen.bladeBolts[index] = true
                    local allRemoved = true
                    for bolt = 1, 4 do allRemoved = allRemoved and Screen.bladeBolts[bolt] end
                    if allRemoved then Screen.bladeStage = "blade" end
                    return true
                end
            end
        elseif Screen.bladeStage == "blade" and x >= 304 and x <= 656 and y >= 280 and y <= 342 then
            Screen.bladeStage = "sleeve"
            return true
        elseif Screen.bladeStage == "sleeve" and x >= 330 and x <= 630 and y >= 445 and y <= 505 then
            local completed, result = MachineMaintenance.prepareBladeForTechnician(state)
            if completed then
                Screen.maintenanceView, Screen.bladeStage, Screen.bladeBolts = "hub", nil, nil
                state.message = "Cutter blade removed and secured in its wooden sleeve. Book the technician when ready."
                return { action = "blade_sleeved" }
            end
            state.message = tostring(result)
        end
        return true
    elseif Screen.maintenanceView == "hub" then
        local _, cutter = MachineMaintenance.cutterStatus(state)
        local stock = state.inventory and state.inventory.stock or {}
        if inside(maintenanceBack, x, y) then
            Screen.maintenanceView = nil
            return { action = "maintenance_close" }
        elseif inside(oilServiceButton, x, y) and (stock.maintenance_kit or 0) > 0 and not cutter.bladeRemoved then
            local session, errorMessage = MachineMaintenance.beginCutterLubrication(state)
            if not session then state.message = tostring(errorMessage); return true end
            Screen.oilSession, Screen.maintenanceView = session, "oil"
            state.message = "Begin by locking out the cutter's main disconnect."
            return { action = "maintenance_minigame", game = "cutter_lubrication" }
        elseif inside(bladeServiceButton, x, y) and not cutter.bladeInSleeve then
            Screen.maintenanceView, Screen.bladeStage = "blade", "bolts"
            Screen.bladeBolts = { false, false, false, false }
            return { action = "maintenance_minigame", game = "blade_removal" }
        elseif inside(technicianButton, x, y) and cutter.bladeInSleeve and not cutter.nextTechnicianDay then
            local booked, day = MachineMaintenance.requestTechnician(state)
            if booked then state.message = "Blade technician booked for game day " .. tostring(day) .. "." end
            return { action = "technician_booked" }
        elseif inside(weeklyButton, x, y) then
            MachineMaintenance.setWeeklyTechnician(state, not cutter.weeklyTechnician)
            state.message = cutter.weeklyTechnician and "Weekly blade service scheduled."
                or "Weekly blade service cancelled."
            return { action = "technician_schedule" }
        end
        return true
    end
    if Screen.loadMenu then
        local pageStart = math.floor((Screen.loadMenu.selected - 1) / loadMenuPageSize)
            * loadMenuPageSize + 1
        local pageEnd = math.min(#Screen.loadMenu.options, pageStart + loadMenuPageSize - 1)
        for index = pageStart, pageEnd do
            local displayIndex = index - pageStart + 1
            local row = {
                x = loadMenuRect.x + 16,
                y = loadMenuRect.y + 68 + (displayIndex - 1) * loadMenuRect.rowHeight,
                width = loadMenuRect.width - 32,
                height = loadMenuRect.rowHeight - 6,
            }
            if inside(row, x, y) then return loadSelected(state, index) end
        end
        return true
    end
    if inside(exitButton, x, y) then return { action = "exit" } end
    if state.machineType == "skid_wrapper" then
        local nearbyPallets = Wrapper.nearbyPallets(state)
        for index = 1, math.min(#nearbyPallets, wrapperPalletList.maxRows) do
            local row = { x = wrapperPalletList.x,
                y = wrapperPalletList.y + (index - 1) * wrapperPalletList.rowHeight,
                width = wrapperPalletList.width, height = wrapperPalletList.rowHeight - 6 }
            if inside(row, x, y) then
                return Wrapper.selectPallet(state, nearbyPallets[index].pallet.id)
            end
        end
        if inside(wrapperMaintenanceButton, x, y) then
            if Wrapper.isActive() then
                state.message = "Wait for the wrapping cycle to finish before opening maintenance."
                return true
            end
            Screen.maintenanceView = "wrapper_hub"
            return { action = "maintenance_hub" }
        end
        return inside(wrapButton, x, y) and Wrapper.start(state) or false
    end
    if inside(helpButton, x, y) then
        Screen.helpOpen, Screen.helpStep, Screen.gaugeFocused = true, 1, false
        return { action = "help_open" }
    end
    if inside(maintenanceButton, x, y) then
        if Machine.loaded or Machine.step ~= "idle" then
            state.message = "Unload the cutter and return it to idle before opening maintenance."
            return true
        end
        Screen.maintenanceView = "hub"
        Screen.gaugeFocused = false
        return { action = "maintenance_hub" }
    end
    layout()
    if inside(gaugeInput, x, y) then
        Screen.gaugeFocused = true
        Screen.gaugeReplaceOnType = true
        return true
    end
    for _, target in ipairs(buttons) do
        if inside(target, x, y) then
            Screen.pressedAction = target.action
            local succeeded
            if target.action == "program" then succeeded = Machine.selectProgram(target.value, state)
            elseif target.action == "set_gauge" then succeeded = commitGauge(state)
            elseif target.action == "gauge" then succeeded = Machine.adjustGauge(target.value, state)
            elseif target.action == "auto" then succeeded = Machine.autoGauge(state)
            elseif target.action == "save" then succeeded = Machine.saveGauge(state)
            elseif target.action == "recall" then succeeded = Machine.recallGauge(state)
            elseif target.action == "load" then succeeded = openLoadMenu(state)
            else succeeded = Machine.keypressed(target.key, state) end
            if succeeded and target.action ~= "program" then formatGauge() end
            return succeeded
        end
    end
    Screen.gaugeFocused = false
    return false
end

function Screen.keypressed(state, key)
    if Screen.helpOpen then
        if key == "escape" then Screen.helpOpen = false
        elseif key == "left" then Screen.helpStep = math.max(1, Screen.helpStep - 1)
        elseif key == "right" then Screen.helpStep = math.min(#cutterHelp, Screen.helpStep + 1) end
        return true
    end
    if Screen.maintenanceView then
        if key == "escape" then
            if dependencies.remoteCommand and (Screen.maintenanceView=="wrapper_task"
                or Screen.maintenanceView=="oil" or Screen.maintenanceView=="blade") then
                return dependencies.remoteCommand("cancel_service",{})
            end
            if Screen.maintenanceView == "wrapper_hub" then
                Screen.maintenanceView = nil
            elseif Screen.maintenanceView == "wrapper_task" then
                Screen.maintenanceView, Screen.wrapperSession = "wrapper_hub", nil
            elseif Screen.maintenanceView == "hub" then Screen.maintenanceView = nil
            else Screen.maintenanceView, Screen.oilSession, Screen.bladeStage = "hub", nil, nil end
            return true
        end
        return true
    end
    if Screen.loadMenu then
        if key == "escape" then Screen.loadMenu = nil; return true end
        if key == "up" then
            Screen.loadMenu.selected = math.max(1, Screen.loadMenu.selected - 1); return true
        elseif key == "down" then
            Screen.loadMenu.selected = math.min(#Screen.loadMenu.options, Screen.loadMenu.selected + 1); return true
        elseif key == "return" or key == "kpenter" then
            return loadSelected(state)
        end
        local number = tonumber(key)
        if number and number >= 1 and number <= loadMenuPageSize then
            local pageStart = math.floor((Screen.loadMenu.selected - 1) / loadMenuPageSize)
                * loadMenuPageSize + 1
            local optionIndex = pageStart + number - 1
            if optionIndex <= #Screen.loadMenu.options then return loadSelected(state, optionIndex) end
        end
        return true
    end
    if key == "l" then return openLoadMenu(state) end
    if not Screen.gaugeFocused then return false end
    if key == "backspace" then
        if Screen.gaugeReplaceOnType then
            Screen.gaugeText = ""
            Screen.gaugeReplaceOnType = false
            return true
        end
        local byteOffset = utf8.offset(Screen.gaugeText, -1)
        if byteOffset then Screen.gaugeText = string.sub(Screen.gaugeText, 1, byteOffset - 1) end
        return true
    elseif key == "return" or key == "kpenter" then
        return commitGauge(state)
    end
    return false
end

function Screen.update(dt)
    if dependencies.remoteCommand then
        for _, session in ipairs({ Screen.oilSession or false, Screen.wrapperSession or false }) do
            if session then session.animationClock = (session.animationClock or 0) + dt end
        end
        return false
    end
    if Screen.maintenanceView == "wrapper_task" and Screen.wrapperSession then
        return MachineMaintenance.update(Screen.wrapperSession, dt)
    elseif Screen.maintenanceView == "oil" and Screen.oilSession then
        return MachineMaintenance.update(Screen.oilSession, dt)
    end
    return false
end

function Screen.textinput(state, text)
    if Screen.loadMenu then return false end
    if not Screen.gaugeFocused then return false end
    local changed = false
    for character in text:gmatch(".") do
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

function Screen.wantsTextInput()
    return Screen.gaugeFocused and not Screen.loadMenu
end

function Screen.gaugeInputCenter()
    return gaugeInput.x + gaugeInput.width / 2, gaugeInput.y + gaugeInput.height / 2
end

function Screen.mousereleased(state, x, y, button)
    if button ~= 1 then return false end
    local action = Screen.pressedAction
    Screen.pressedAction = nil
    -- Offline mouse cut controls stay latched for the same 0.30-second
    -- simultaneity window used by the physical keys. Multiplayer input starts
    -- the cut during mousepressed, so release only clears the visual action.
    if action == "cut_left" or action == "cut_right" then return true end
    return action ~= nil
end

function Screen.buttonCenter(action, value)
    layout()
    for _, button in ipairs(buttons) do
        if button.action == action and (value == nil or button.value == value) then
            return button.x + button.width / 2, button.y + button.height / 2
        end
    end
end

function Screen.exitCenter()
    return exitButton.x + exitButton.width / 2, exitButton.y + exitButton.height / 2
end

function Screen.maintenanceCenter()
    return maintenanceButton.x + maintenanceButton.width / 2,
        maintenanceButton.y + maintenanceButton.height / 2
end

function Screen.wrapperMaintenanceCenter()
    return wrapperMaintenanceButton.x + wrapperMaintenanceButton.width / 2,
        wrapperMaintenanceButton.y + wrapperMaintenanceButton.height / 2
end

function Screen.wrapperServiceCenter()
    return wrapperServiceButton.x + wrapperServiceButton.width / 2,
        wrapperServiceButton.y + wrapperServiceButton.height / 2
end

function Screen.wrapperPalletCenter(index)
    index = math.max(1, math.min(wrapperPalletList.maxRows, index or 1))
    return wrapperPalletList.x + wrapperPalletList.width / 2,
        wrapperPalletList.y + (index - 0.5) * wrapperPalletList.rowHeight - 3
end

function Screen.wrapperTaskTargetCenter()
    return MachineMaintenance.wrapperTarget(Screen.wrapperSession)
end

function Screen.maintenanceTaskCenter(task)
    local rect = task == "oil" and oilServiceButton
        or task == "blade" and bladeServiceButton
        or task == "technician" and technicianButton
        or task == "weekly" and weeklyButton
        or maintenanceBack
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

function Screen.oilingTargetCenter(index)
    local point = Screen.oilSession and Screen.oilSession.points[index]
    return point and point.x, point and point.y
end

function Screen.lubricationLockoutCenter(action)
    local rect = lockoutButtons[action]; return rect.x + rect.width / 2, rect.y + rect.height / 2
end
function Screen.lubricationPrepCenter(action)
    local rect = prepButtons[action]; return rect.x + rect.width / 2, rect.y + rect.height / 2
end
function Screen.lubricationViewCenter(view)
    for index, name in ipairs(lubricationViews) do if name == view then return 94.5 + (index - 1) * 113, 129 end end
end
function Screen.lubricationToolCenter(tool)
    for index, name in ipairs(lubricationTools) do if name == tool then return 767, 195.5 + (index - 1) * 48 end end
end
function Screen.lubricationPointCenter(pointId)
    local point = MachineMaintenance.lubricationPoint(Screen.oilSession, pointId)
    return point and point.x, point and point.y
end
function Screen.lubricationPumpCenter() return pumpButton.x + pumpButton.width / 2, pumpButton.y + pumpButton.height / 2 end
function Screen.lubricationFinishCenter() return finishLubricationButton.x + finishLubricationButton.width / 2,
    finishLubricationButton.y + finishLubricationButton.height / 2 end
function Screen.lubricationGearSightCenter() return 490, 340 end

function Screen.bladeBoltCenter(index)
    local position = bladeBoltPositions()[index]
    return position[1], position[2]
end

function Screen.bladeCenter() return 480, 311 end
function Screen.bladeSleeveCenter() return 480, 475 end

function Screen.hasModal() return Screen.loadMenu ~= nil or Screen.maintenanceView ~= nil or Screen.helpOpen end

function Screen.loadMenuOptions()
    return Screen.loadMenu and Screen.loadMenu.options or {}
end

function Screen.loadMenuRowCenter(index)
    local displayIndex = ((index or 1) - 1) % loadMenuPageSize + 1
    return loadMenuRect.x + loadMenuRect.width / 2,
        loadMenuRect.y + 68 + (displayIndex - 0.5) * loadMenuRect.rowHeight
end

function Screen.artworkRotation(paper)
    return math.rad(((paper and paper.orientation) or 0) % 360)
end

-- The same service hit targets feed bounded intent on guests. No local service
-- task, bolt, kit or condition is advanced before the host confirms it.
function Screen.remoteServiceInput(state, x, y, button)
    if button ~= 1 or Screen.helpOpen then return nil end
    local send = dependencies.remoteCommand
    local function action(name, args) send(name, args or {}); return true end
    local view = Screen.remoteView or {}
    if Screen.maintenanceView == "hub" then
        if inside(maintenanceBack, x, y) then Screen.maintenanceView = nil; return true end
        if inside(oilServiceButton, x, y) then return action("begin_lubrication") end
        if inside(bladeServiceButton, x, y) then return action("begin_blade") end
        if inside(technicianButton, x, y) then return action("book_blade_technician") end
        if inside(weeklyButton, x, y) then
            local _, cutter = MachineMaintenance.cutterStatus(state)
            return action("set_weekly_technician", { enabled = not cutter.weeklyTechnician })
        end
        return true
    elseif Screen.maintenanceView == "oil" then
        if inside(maintenanceBack, x, y) then return action("cancel_service") end
        local session = Screen.oilSession
        if session.stage == "lockout" or session.stage == "prep" then
            local expected = ({ lockout_disconnect = "disconnect", lockout_key = "key", lockout_tag = "tag",
                prep_cartridge = "cartridge", prep_prime = "prime" })[view.serviceStep]
            local rect = lockoutButtons[expected] or prepButtons[expected]
            if rect and inside(rect, x, y) then return action("service_advance") end
        else
            for index in ipairs(lubricationViews) do
                if inside({ x=42+(index-1)*113,y=112,width=105,height=34 },x,y) then return action("service_view",{itemIndex=index}) end
            end
            for index in ipairs(lubricationTools) do
                if inside({x=650,y=176+(index-1)*48,width=234,height=39},x,y) then return action("service_tool",{itemIndex=index}) end
            end
            if inside(pumpButton,x,y) then return action("service_pump") end
            if inside(finishLubricationButton,x,y) then return action("finish_lubrication") end
            if session.activeView == "gear" and (x-490)^2+(y-340)^2 <= 55^2 then return action("service_gear") end
            if session.activeView == "central" and (x-370)^2+(y-330)^2 <= 45^2 then return action("service_point",{itemIndex=7}) end
            for index, point in ipairs(session.points) do
                if point.view == session.activeView and (x-point.x)^2+(y-point.y)^2 <= 38^2 then return action("service_point",{itemIndex=index}) end
            end
        end
        return true
    elseif Screen.maintenanceView == "blade" then
        if inside(maintenanceBack,x,y) then return action("cancel_service") end
        if Screen.bladeStage == "bolts" then
            for index,pos in ipairs(bladeBoltPositions()) do
                if (x-pos[1])^2+(y-pos[2])^2 <= 24^2 then return action("remove_blade_bolt",{itemIndex=index}) end
            end
        elseif Screen.bladeStage == "blade" and x>=304 and x<=656 and y>=280 and y<=342 then return action("lift_blade")
        elseif Screen.bladeStage == "sleeve" and x>=330 and x<=630 and y>=445 and y<=505 then return action("sleeve_blade") end
        return true
    elseif Screen.maintenanceView == "wrapper_hub" then
        if inside(maintenanceBack,x,y) then Screen.maintenanceView=nil; return true end
        if inside(wrapperServiceButton,x,y) then return action("begin_service") end
        return true
    elseif Screen.maintenanceView == "wrapper_task" then
        if inside(maintenanceBack,x,y) then return action("cancel_service") end
        local phase = view.servicePhase or 1
        local tx,ty = MachineMaintenance.wrapperTarget(Screen.wrapperSession,phase)
        if tx and (x-tx)^2+(y-ty)^2 <= 38^2 then return action("service_target",{itemIndex=phase}) end
        if x>=54 and x<=574 and y>=104 and y<=542 then return action("service_miss") end
        return true
    end
end

function Screen.syncRemoteService(state, view)
    Screen.remoteView = view
    local step = view.serviceStep or "idle"
    if state.machineType == "skid_wrapper" then
        if step == "task" then
            local session = Screen.wrapperSession or MachineMaintenance.beginWrapperService(state)
            if not session then return end
            session.activeIndex = view.serviceTaskIndex or 1
            local task = session.tasks[session.activeIndex]
            session.taskState[task.id] = { phase=view.servicePhase or 1, attempts=view.serviceAttempts or 0,
                misses=view.serviceMisses or 0, hits=(view.servicePhase or 1)-1, completed=false }
            Screen.wrapperSession, Screen.maintenanceView = session,"wrapper_task"
        elseif Screen.maintenanceView == "wrapper_task" then Screen.wrapperSession,Screen.maintenanceView=nil,"wrapper_hub" end
    elseif step:sub(1,6) == "blade_" then
        Screen.maintenanceView = "blade"
        Screen.bladeStage = step == "blade_lift" and "blade" or step:sub(7)
        Screen.bladeBolts = {}
        for index=1,4 do
            Screen.bladeBolts[index]=view.bladeBoltMask and math.floor(view.bladeBoltMask/2^(index-1))%2==1
                or (view.bladeBoltMask==nil and index <= (view.bladeBoltsDone or 0))
        end
    elseif step ~= "idle" then
        local session = Screen.oilSession or MachineMaintenance.beginCutterLubrication(state)
        if not session then return end
        session.stage = step:find("lockout",1,true) and "lockout" or step:find("prep",1,true) and "prep" or "service"
        session.lockout = { disconnect=step~="lockout_disconnect",key=step~="lockout_disconnect" and step~="lockout_key",tag=session.stage~="lockout" }
        session.prep = { cartridge=step=="prep_prime" or session.stage=="service",primed=session.stage=="service" }
        session.activeView=lubricationViews[view.serviceView or 1]
        session.activeTool=lubricationTools[view.serviceTool or 1]
        session.centralInstalled=view.centralInstalled==true
        session.gear.inspected,session.gear.level=view.gearInspected==true,(view.gearLevelPermille or 480)/1000
        session.coupledPoint=nil
        for _,item in ipairs(view.serviceItems or {}) do
            local point=item.itemIndex==7 and session.central or session.points[item.itemIndex]
            if point then
                point.cleaned,point.coupled,point.strokes,point.complete=item.cleaned,item.coupled,item.strokes,item.complete
                if point.coupled then session.coupledPoint=item.itemIndex==7 and "central" or point.id end
            end
        end
        Screen.oilSession,Screen.maintenanceView=session,"oil"
    elseif Screen.maintenanceView == "oil" or Screen.maintenanceView == "blade" then
        Screen.oilSession,Screen.bladeStage,Screen.bladeBolts,Screen.maintenanceView=nil,nil,nil,"hub"
    end
end

return Screen
end

local default = create()
default.new = create
return default
