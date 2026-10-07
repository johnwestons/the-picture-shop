-- Per-machine console state, dependencies, layout, and gauge controls.
-- Runtime is private to this screen instance; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.dependencies = Runtime.dependencies or {}
    Runtime.Config = require("src.config")
    Runtime.Machine = Runtime.dependencies.Machine or require("src.machine")
    Runtime.MachineFleet = require("src.machine_fleet")
    Runtime.MachineMaintenance = require("src.machine_maintenance")
    Runtime.BusinessCalendar = require("src.business_calendar")
    Runtime.CutGuide = require("src.cutter_cut_guide")
    Runtime.PalletJack = require("src.pallet_jack")
    Runtime.Procurement = require("src.procurement")
    Runtime.Wrapper = Runtime.dependencies.Wrapper or require("src.wrapper")
    Runtime.BackButton = require("src.screens.back_button")
    Runtime.CutterSkin = require("src.screens.cutter_skin")
    Runtime.utf8 = require("utf8")

    Runtime.Screen = {
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
    Runtime.buttons = {}
    Runtime.gaugeInput = { x = 55, y = 263, width = 182, height = 28 }
    Runtime.exitButton = { x = 790, y = 28, width = 132, height = 42 }
    Runtime.wrapButton = { x = 650, y = 520, width = 220, height = 54 }
    Runtime.wrapperMaintenanceButton = { x = 50, y = 520, width = 220, height = 54 }
    Runtime.wrapperPalletList = { x = 42, y = 92, width = 330, rowHeight = 48, maxRows = 5 }
    Runtime.helpButton = { x = 500, y = 82, width = 174, height = 40 }
    Runtime.maintenanceButton = { x = 692, y = 82, width = 198, height = 40 }
    Runtime.helpBack = { x = 72, y = 582, width = 180, height = 44 }
    Runtime.helpPrevious = { x = 280, y = 582, width = 180, height = 44 }
    Runtime.helpNext = { x = 706, y = 582, width = 180, height = 44 }
    Runtime.maintenanceBack = { x = 54, y = 594, width = 188, height = 42 }
    Runtime.oilServiceButton = { x = 92, y = 244, width = 342, height = 122 }
    Runtime.bladeServiceButton = { x = 526, y = 244, width = 342, height = 122 }
    Runtime.technicianButton = { x = 526, y = 390, width = 342, height = 72 }
    Runtime.weeklyButton = { x = 526, y = 478, width = 342, height = 82 }
    Runtime.lockoutButtons = {
        disconnect = { x = 105, y = 235, width = 210, height = 150 },
        key = { x = 375, y = 235, width = 210, height = 150 },
        tag = { x = 645, y = 235, width = 210, height = 150 },
    }
    Runtime.prepButtons = {
        cartridge = { x = 190, y = 220, width = 240, height = 220 },
        prime = { x = 530, y = 220, width = 240, height = 220 },
    }
    Runtime.lubricationViews = { "rear", "front", "side", "central", "gear" }
    Runtime.lubricationTools = { "rag", "grease", "inspect", "gear_oil" }
    Runtime.pumpButton = { x = 670, y = 462, width = 225, height = 58 }
    Runtime.finishLubricationButton = { x = 670, y = 532, width = 225, height = 48 }
    Runtime.loadMenuRect = { x = 190, y = 126, width = 580, rowHeight = 54 }
    Runtime.loadMenuPageSize = 7

    function Runtime.inside(button, x, y)
        return x >= button.x and x <= button.x + button.width and y >= button.y and y <= button.y + button.height
    end

    function Runtime.box(x, y, width, height, fill, line, radius)
        love.graphics.setColor(fill)
        love.graphics.rectangle("fill", x, y, width, height, radius or 0, radius or 0)
        love.graphics.setColor(line)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, width, height, radius or 0, radius or 0)
    end

    function Runtime.drawCondition(state, modelId, x, y, width)
        local item = Runtime.MachineFleet.installed(state, modelId)
        if not item then return end
        local condition = Runtime.MachineFleet.condition(item)
        local status = Runtime.MachineFleet.conditionStatus(condition)
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

    function Runtime.addButton(action, label, x, y, width, height, key, value)
        Runtime.buttons[#Runtime.buttons + 1] = { action = action, label = label, x = x, y = y, width = width, height = height, key = key, value = value }
    end

    function Runtime.layout()
        Runtime.buttons = {}
        for index = 1, 4 do Runtime.addButton("program", "CUT " .. index, 55 + (index - 1) * 72, 228, 64, 28, nil, index) end
        Runtime.addButton("set_gauge", "SET", 245, 263, 46, 28)
        Runtime.addButton("gauge", "-1", 55, 298, 48, 28, nil, -1)
        Runtime.addButton("gauge", "-.1", 109, 298, 48, 28, nil, -0.1)
        Runtime.addButton("gauge", "+.1", 163, 298, 48, 28, nil, 0.1)
        Runtime.addButton("gauge", "+1", 217, 298, 48, 28, nil, 1)
        Runtime.addButton("auto", "AUTO SET", 271, 298, 72, 28, "g")
        Runtime.addButton("save", "SAVE", 55, 334, 62, 28, "m")
        Runtime.addButton("recall", "RECALL", 123, 334, 70, 28, "v")
        Runtime.addButton("repeat", "RUN NEXT LIFT", 201, 334, 142, 28, "t")
        Runtime.addButton("load", "LOAD JOB", 54, 478, 96, 34, "l")
        Runtime.addButton("position", "PUSH / POS", 158, 478, 100, 34, "p")
        Runtime.addButton("rotate", "ROTATE CCW", 266, 478, 100, 34, "q")
        Runtime.addButton("clamp", "CLAMP", 374, 478, 84, 34, "space")
        Runtime.addButton("unload", "TO PALLET", 466, 478, 96, 34, "u")
        Runtime.addButton("barrier", "BARRIER", 570, 478, 86, 34, "b")
        Runtime.addButton("reset", "RESET", 664, 478, 72, 34, "r")
        Runtime.addButton("estop", "E-STOP", 752, 470, 74, 74, "x")
        Runtime.addButton("cut_left", "J", 674, 565, 82, 82, "j")
        Runtime.addButton("cut_right", "K", 804, 565, 82, 82, "k")
    end

    function Runtime.formatGauge()
        Runtime.Screen.gaugeText = string.format("%.2f", Runtime.Machine.gauge or 0)
        Runtime.Screen.gaugeReplaceOnType = true
    end

    function Runtime.commitGauge(state)
        local succeeded = Runtime.Machine.setGauge(Runtime.Screen.gaugeText, state)
        if succeeded then Runtime.formatGauge() end
        return succeeded
    end

    function Runtime.Screen.enter()
        Runtime.Screen.pressedAction = nil
        Runtime.Screen.gaugeFocused = false
        Runtime.Screen.loadMenu = nil
        Runtime.Screen.maintenanceView = nil
        Runtime.Screen.oilSession = nil
        Runtime.Screen.bladeStage = nil
        Runtime.Screen.bladeBolts = nil
        Runtime.Screen.wrapperSession = nil
        Runtime.Screen.helpOpen, Runtime.Screen.helpStep = false, 1
        Runtime.formatGauge()
    end

    Runtime.cutterHelp = {
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
end

return Component
