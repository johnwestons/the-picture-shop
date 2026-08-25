local BackButton = require("src.screens.back_button")
local BusinessCalendar = require("src.business_calendar")
local MachineFleet = require("src.machine_fleet")
local MachineMaintenance = require("src.machine_maintenance")
local Plates = require("src.plate_service")
local Windmill = require("src.windmill")

local Screen = {
    tab = "run", clock = 0, activeSetup = nil, setupHits = 0, setupMisses = 0,
    selectedCandidate = 1, selectedPlateJob = 1, selectedPlate = 1,
    maintenance = nil, lockoutStep = 1, tutorialStep = 1,
}

local BACK = { x = 34, y = 700, width = 150, height = 44 }
local tabs = {
    { id = "run", label = "RUN", x = 34 }, { id = "plates", label = "PLATES", x = 170 },
    { id = "setup", label = "SETUP", x = 306 }, { id = "proof", label = "PROOF", x = 442 },
    { id = "maintenance", label = "SERVICE", x = 578 }, { id = "tutorial", label = "HELP", x = 714 },
}

local function inside(rect, x, y)
    return x >= rect.x and x <= rect.x + rect.width and y >= rect.y and y <= rect.y + rect.height
end

local function button(x, y, width, height, label, enabled, pointerX, pointerY, danger)
    local hovered = pointerX and inside({ x = x, y = y, width = width, height = height }, pointerX, pointerY)
    local pressed = hovered and love.mouse and love.mouse.isDown and love.mouse.isDown(1)
    y = y + (pressed and 2 or 0)
    love.graphics.setColor(enabled == false and 0.16 or danger and 0.48 or hovered and 0.24 or 0.18,
        enabled == false and 0.17 or danger and 0.13 or hovered and 0.42 or 0.31,
        enabled == false and 0.18 or danger and 0.12 or hovered and 0.45 or 0.36, 1)
    love.graphics.rectangle("fill", x, y, width, height, 5, 5)
    love.graphics.setColor(enabled == false and 0.45 or 0.90, enabled == false and 0.45 or 0.94,
        enabled == false and 0.45 or 0.88, 1)
    love.graphics.rectangle("line", x, y, width, height, 5, 5)
    love.graphics.printf(label, x, y + height / 2 - 7, width, "center")
    return { x = x, y = y, width = width, height = height }
end

local function title(text, subtext)
    love.graphics.setColor(0.94, 0.82, 0.36)
    love.graphics.print(text, 40, 76)
    love.graphics.setColor(0.72, 0.80, 0.80)
    love.graphics.print(subtext or "", 40, 99)
end

function Screen.enter(state)
    Screen.tab, Screen.clock, Screen.activeSetup = "run", 0, nil
    Screen.setupHits, Screen.setupMisses, Screen.maintenance, Screen.lockoutStep = 0, 0, nil, 1
    Screen.tutorialStep = (state.windmill and state.windmill.tutorialComplete) and 8 or 1
end

function Screen.update(dt, state)
    Screen.clock = Screen.clock + math.max(0, dt or 0)
    Plates.update(state)
end

local function drawFrame()
    love.graphics.setColor(0.035, 0.045, 0.05, 0.98)
    love.graphics.rectangle("fill", 20, 20, 920, 744, 10, 10)
    love.graphics.setColor(0.44, 0.52, 0.52)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", 20, 20, 920, 744, 10, 10)
    love.graphics.setColor(0.90, 0.90, 0.84)
    love.graphics.print("ORIGINAL HEIDELBERG 10 x 15  •  WINDMILL CONTROL", 40, 40)
end

local function drawTabs(pointerX, pointerY)
    for _, tab in ipairs(tabs) do
        button(tab.x, 120, 122, 38, tab.label, true, pointerX, pointerY)
        if Screen.tab == tab.id then
            love.graphics.setColor(0.92, 0.72, 0.20)
            love.graphics.rectangle("fill", tab.x + 8, 154, 106, 3)
        end
    end
end

local function currentPlateJob(state)
    local jobs = {}
    for _, job in ipairs(state.jobs and state.jobs.active or {}) do
        if job.press then jobs[#jobs + 1] = job end
    end
    if #jobs == 0 then return nil, jobs end
    Screen.selectedPlateJob = math.max(1, math.min(Screen.selectedPlateJob, #jobs))
    return jobs[Screen.selectedPlateJob], jobs
end

local function drawRun(state, pointerX, pointerY)
    local p, job, pallet = Windmill.current(state)
    title("PRODUCTION", "Mechanical maximum 5,500 iph • shop quoting rate 3,000 good impressions/hour")
    love.graphics.setColor(0.10, 0.13, 0.14)
    love.graphics.rectangle("fill", 40, 178, 880, 140, 6, 6)
    love.graphics.setColor(0.82, 0.88, 0.86)
    love.graphics.print("STATUS: " .. tostring(p.status):upper(), 58, 195)
    love.graphics.print("JOB: " .. (job and job.id or "NO PALLET LOADED"), 58, 222)
    love.graphics.print("PALLET: " .. (pallet and pallet.id or "—"), 58, 249)
    love.graphics.print(string.format("COLOR PASS: %s / %s", tostring(p.colorIndex or "—"),
        job and tostring(job.press.colors) or "—"), 58, 276)
    love.graphics.print(string.format("SPEED: %d iph", p.speed), 360, 195)
    love.graphics.print(string.format("COUNTER: %d", p.counter), 360, 222)
    love.graphics.print(string.format("GOOD: %d   SPOILAGE: %d", p.goodSheets, p.spoilage), 360, 249)
    love.graphics.print(string.format("PROOF: %s", p.proofQuality and string.format("%d%%", p.proofQuality * 100)
        or "NOT PULLED"), 360, 276)
    local machine = MachineFleet.installed(state, "heidelberg_10x15")
    love.graphics.print(string.format("CONDITION: %d%%", machine and MachineFleet.condition(machine) or 0), 700, 195)
    love.graphics.setColor(p.motor and 0.28 or 0.50, p.motor and 0.82 or 0.18, 0.18)
    love.graphics.circle("fill", 820, 251, 14)
    love.graphics.setColor(0.82, 0.88, 0.86)
    love.graphics.print(p.motor and "MOTOR ON" or "MOTOR OFF", 845, 244)

    -- A compact operator-side mechanical view makes speed, cycling, and stops readable at a glance.
    local phase = p.motor and p.animationClock * (p.speed / 3000) * 4.5 or 0
    local cx, cy, arm = 746, 273, 47
    love.graphics.setColor(0.18, 0.21, 0.21)
    love.graphics.rectangle("fill", 680, 244, 132, 61, 5, 5)
    love.graphics.setColor(0.65, 0.68, 0.62)
    love.graphics.setLineWidth(7)
    love.graphics.line(cx - math.cos(phase) * arm, cy - math.sin(phase) * arm,
        cx + math.cos(phase) * arm, cy + math.sin(phase) * arm)
    love.graphics.line(cx - math.cos(phase + math.pi / 2) * arm, cy - math.sin(phase + math.pi / 2) * arm,
        cx + math.cos(phase + math.pi / 2) * arm, cy + math.sin(phase + math.pi / 2) * arm)
    love.graphics.setColor(0.90, 0.72, 0.18)
    love.graphics.circle("fill", cx, cy, 9)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(p.warning and 0.94 or 0.42, p.warning and 0.46 or 0.76, 0.30)
    love.graphics.printf(p.warning or Windmill.failureSummary(state), 650, 306, 250, "center")

    button(52, 340, 158, 54, p.motor and "STOP MOTOR" or "START MOTOR", true, pointerX, pointerY)
    button(224, 340, 158, 54, p.feeder and "FEEDER OFF" or "FEEDER ON", p.motor, pointerX, pointerY)
    button(396, 340, 158, 54, p.impression and "OFF IMPRESSION" or "ON IMPRESSION", p.motor, pointerX, pointerY)
    button(568, 340, 104, 54, "SPEED −", true, pointerX, pointerY)
    button(684, 340, 104, 54, "SPEED +", true, pointerX, pointerY)
    button(800, 340, 104, 54, "E-STOP", true, pointerX, pointerY, true)
    button(52, 412, 158, 54, "RESET", p.status ~= "production", pointerX, pointerY)
    button(224, 412, 158, 54, "PULL PROOF", Windmill.setupComplete(state), pointerX, pointerY)
    button(396, 412, 158, 54, "APPROVE PROOF", p.status == "proof", pointerX, pointerY)
    button(568, 412, 158, 54, p.status == "production" and "STOP RUN" or "START RUN",
        p.proofApproved or p.status == "production", pointerX, pointerY)
    button(740, 412, 164, 54, "CLEAN + UNLOAD", p.status == "pass_complete", pointerX, pointerY)

    local candidates = Windmill.candidates(state)
    love.graphics.setColor(0.82, 0.88, 0.86)
    love.graphics.print("PRINT-READY PALLETS", 52, 498)
    if p.status == "idle" then
        for index, item in ipairs(candidates) do
            local y = 526 + (index - 1) * 45
            button(52, y, 852, 38, string.format("LOAD %s  •  %s  •  COLOR %d", item.pallet.id,
                item.job.company, item.color), true, pointerX, pointerY)
        end
        if #candidates == 0 then
            love.graphics.setColor(0.68, 0.70, 0.68)
            love.graphics.printf("Cut the stock, prepare the correct plate, and allow prior ink to dry.", 52, 532, 852, "center")
        end
    else
        love.graphics.setColor(0.68, 0.70, 0.68)
        love.graphics.print("Unload the active pass before choosing another pallet.", 52, 532)
    end
end

local function drawPlates(state, pointerX, pointerY)
    local job, jobs = currentPlateJob(state)
    title("PLATE ROOM", "Outsource processed plates or expose, wash, dry, and mount them in-house")
    if not job then
        love.graphics.setColor(0.72, 0.76, 0.74)
        love.graphics.printf("No active Windmill jobs require plates.", 80, 260, 800, "center")
        return
    end
    love.graphics.setColor(0.82, 0.88, 0.86)
    love.graphics.print(string.format("JOB %s  •  %s", job.id, job.company), 52, 184)
    button(700, 176, 92, 34, "PREV JOB", #jobs > 1, pointerX, pointerY)
    button(804, 176, 92, 34, "NEXT JOB", #jobs > 1, pointerX, pointerY)
    local plates = Plates.ensureJob(job)
    Screen.selectedPlate = math.max(1, math.min(Screen.selectedPlate, #plates))
    local plate = plates[Screen.selectedPlate]
    for index, item in ipairs(plates) do
        button(52 + (index - 1) * 190, 228, 176, 42,
            string.format("COLOR %d: %s", index, item.status:upper()), true, pointerX, pointerY)
    end
    love.graphics.setColor(0.11, 0.13, 0.14)
    love.graphics.rectangle("fill", 52, 290, 844, 180, 5, 5)
    love.graphics.setColor(0.86, 0.89, 0.84)
    love.graphics.print("PLATE ID: " .. plate.id, 72, 312)
    love.graphics.print("INK: " .. plate.inkColor, 72, 340)
    love.graphics.print(string.format("ART: %.2f x %.2f in", plate.artworkSize.width, plate.artworkSize.height), 72, 368)
    love.graphics.print(string.format("QUALITY: %d%%  •  LIFE: %d%%  •  %s", plate.quality * 100,
        plate.life * 100, plate.mounted and "MOUNTED" or "UNMOUNTED"), 72, 396)
    if plate.status == "ordered" then
        love.graphics.print(string.format("OUTSOURCE READY IN ABOUT %d HOURS", math.max(0,
            math.ceil((plate.readyAtHours or 0) - BusinessCalendar.absoluteHours(state)))), 72, 424)
    elseif plate.status == "processing" then
        love.graphics.print("NEXT IN-HOUSE STEP: " .. tostring(Plates.actionFor(plate)):upper(), 72, 424)
    end
    button(52, 492, 240, 54, "ORDER PROCESSED PLATE", plate.status == "unprepared", pointerX, pointerY)
    button(310, 492, 240, 54, "START IN-HOUSE PLATE", plate.status == "unprepared", pointerX, pointerY)
    button(568, 492, 328, 54, plate.status == "processing"
        and ("TIME + LOCK " .. tostring(Plates.actionFor(plate)):upper()) or "IN-HOUSE PROCESS",
        plate.status == "processing", pointerX, pointerY)
    if plate.status == "processing" then
        local marker = (math.sin(Screen.clock * 2.2) + 1) / 2
        love.graphics.setColor(0.18, 0.20, 0.20)
        love.graphics.rectangle("fill", 130, 580, 690, 30)
        love.graphics.setColor(0.28, 0.70, 0.38)
        love.graphics.rectangle("fill", 130 + 690 * 0.58, 580, 690 * 0.18, 30)
        love.graphics.setColor(0.96, 0.82, 0.22)
        love.graphics.rectangle("fill", 126 + 690 * marker, 574, 8, 42)
        love.graphics.setColor(0.80, 0.84, 0.82)
        love.graphics.printf("Lock each process inside the green quality window.", 130, 625, 690, "center")
    end
end

local function setupTarget()
    return 490 + math.sin(Screen.clock * 1.7) * 210, 488 + math.cos(Screen.clock * 1.3) * 74
end

local function drawSetup(state, pointerX, pointerY)
    local p = Windmill.ensure(state)
    title("PRESS SETUP", "Complete chase, packing, roller, ink, feeder, and register checks")
    if not p.palletId then
        love.graphics.setColor(0.72, 0.76, 0.74)
        love.graphics.printf("Load a print-ready pallet from the RUN tab first.", 80, 250, 800, "center")
        return
    end
    if Screen.activeSetup then
        love.graphics.setColor(0.84, 0.88, 0.84)
        love.graphics.printf("" .. Screen.activeSetup:upper() .. " MINIGAME", 80, 190, 800, "center")
        love.graphics.printf("Click the moving inspection target three times. Misses reduce setup quality.", 80, 220, 800, "center")
        local tx, ty = setupTarget()
        love.graphics.setColor(0.92, 0.72, 0.18)
        love.graphics.circle("fill", tx, ty, 23)
        love.graphics.setColor(0.12, 0.18, 0.18)
        love.graphics.circle("fill", tx, ty, 9)
        love.graphics.setColor(0.80, 0.84, 0.82)
        love.graphics.printf(string.format("HITS %d / 3   •   MISSES %d", Screen.setupHits, Screen.setupMisses), 80, 610, 800, "center")
        button(380, 650, 200, 42, "CANCEL TASK", true, pointerX, pointerY)
        return
    end
    for index, task in ipairs(Windmill.setupTasks()) do
        local row, column = math.floor((index - 1) / 2), (index - 1) % 2
        local x, y = 52 + column * 426, 190 + row * 112
        local score = p.setup[task]
        button(x, y, 408, 90, string.format("%s\n%s", task:upper(), score and string.format("COMPLETE %d%%", score * 100)
            or "BEGIN CHECK"), true, pointerX, pointerY)
    end
    love.graphics.setColor(Windmill.setupComplete(state) and 0.32 or 0.70,
        Windmill.setupComplete(state) and 0.85 or 0.74, 0.32)
    love.graphics.printf(Windmill.setupComplete(state) and "SETUP COMPLETE — PULL A PROOF"
        or "ALL SIX CHECKS ARE REQUIRED BEFORE PROOFING", 80, 565, 800, "center")
end

local function drawProof(state, pointerX, pointerY)
    local p = Windmill.ensure(state)
    title("PROOF INSPECTION", "Approve register, ink density, impression, feeding, and plate detail")
    love.graphics.setColor(0.12, 0.14, 0.14)
    love.graphics.rectangle("fill", 80, 190, 800, 320, 6, 6)
    if not p.proofQuality then
        love.graphics.setColor(0.72, 0.76, 0.74)
        love.graphics.printf("No proof available. Complete setup, turn on motor, feeder and impression, then pull a proof.",
            130, 320, 700, "center")
    else
        local q = p.proofQuality
        love.graphics.setColor(q >= 0.82 and 0.28 or 0.82, q >= 0.82 and 0.82 or 0.34, 0.28)
        love.graphics.printf(string.format("PROOF QUALITY  %d%%", q * 100), 130, 220, 700, "center")
        local labels = {
            { "REGISTER", p.setup.register }, { "INK DENSITY", p.setup.ink },
            { "IMPRESSION", (p.setup.packing + p.setup.chase) / 2 }, { "ROLLER STRIPE", p.setup.rollers },
            { "SHEET FEED", p.setup.feeder }, { "PLATE DETAIL", q },
        }
        for index, item in ipairs(labels) do
            local y = 270 + (index - 1) * 34
            love.graphics.setColor(0.84, 0.87, 0.83)
            love.graphics.print(item[1], 180, y)
            love.graphics.setColor(item[2] >= 0.82 and 0.32 or 0.88, item[2] >= 0.82 and 0.82 or 0.42, 0.26)
            love.graphics.rectangle("fill", 390, y + 2, 330 * item[2], 15)
        end
    end
    button(230, 550, 220, 52, "PULL ANOTHER PROOF", Windmill.setupComplete(state), pointerX, pointerY)
    button(510, 550, 220, 52, "APPROVE PROOF", p.status == "proof", pointerX, pointerY)
end

local function drawMaintenance(state, pointerX, pointerY)
    local machine = MachineFleet.installed(state, "heidelberg_10x15")
    title("LOCKOUT + MAINTENANCE", "Service rollers, grippers, suction, ink train, lubrication, and safety")
    if not machine then return end
    if not Screen.maintenance then
        local plan = MachineFleet.maintenancePlan(state, machine.id)
        love.graphics.setColor(0.82, 0.86, 0.82)
        love.graphics.print(string.format("MACHINE CONDITION %d%%  •  MAINTENANCE KITS %d", MachineFleet.condition(machine),
            state.inventory.stock.maintenance_kit or 0), 52, 186)
        for index, task in ipairs(plan.tasks) do
            local y = 224 + (index - 1) * 55
            love.graphics.print(string.format("%s — %d%%", task.componentLabel, task.health), 72, y)
            love.graphics.setColor(0.22, 0.62, 0.38)
            love.graphics.rectangle("fill", 390, y + 2, 390 * task.health / 100, 14)
            love.graphics.setColor(0.82, 0.86, 0.82)
        end
        button(330, 590, 300, 56, "BEGIN LOCKOUT + SERVICE", (state.inventory.stock.maintenance_kit or 0) > 0
            and Windmill.ensure(state).status == "idle", pointerX, pointerY)
        local press = machine.maintenance.windmill
        love.graphics.setColor(0.70, 0.76, 0.74)
        love.graphics.printf(press.technicianDueDay and ("TECHNICIAN DUE DAY " .. press.technicianDueDay)
            or "Field service covers timing, lubrication, suction, and safety circuits.", 620, 535, 270, "center")
        button(650, 590, 240, 56, "BOOK TECHNICIAN  $350", not press.technicianDueDay
            and Windmill.ensure(state).status == "idle", pointerX, pointerY)
        return
    end
    if Screen.lockoutStep <= 3 then
        local labels = { "1. DISCONNECT POWER", "2. REMOVE + KEEP KEY", "3. ATTACH LOCKOUT TAG" }
        love.graphics.setColor(0.84, 0.88, 0.84)
        love.graphics.printf("ENERGY ISOLATION MUST BE COMPLETED IN ORDER", 100, 230, 760, "center")
        for index, label in ipairs(labels) do
            button(280, 290 + (index - 1) * 82, 400, 58, label, index == Screen.lockoutStep, pointerX, pointerY)
        end
    else
        local task = MachineMaintenance.activeTask(Screen.maintenance)
        if task then
            love.graphics.setColor(0.84, 0.88, 0.84)
            love.graphics.printf(task.label, 100, 250, 760, "center")
            love.graphics.printf("Inspect, clean, adjust, and verify this component before advancing.", 100, 285, 760, "center")
            button(300, 370, 360, 90, "COMPLETE INTERACTIVE CHECK", true, pointerX, pointerY)
            love.graphics.printf(string.format("SERVICE PROGRESS %d%%", MachineMaintenance.progress(Screen.maintenance) * 100),
                100, 500, 760, "center")
        else
            love.graphics.printf("All component checks complete.", 100, 300, 760, "center")
        end
    end
end

local tutorial = {
    { "1 — SAFETY AND JOB REVIEW", "Read the office job ticket first: finished size, stock, quantity, colors and packaging. Keep hands, tools and loose clothing outside the guarded platen area. Confirm the press is idle, the emergency stop is reset and no lockout tag is attached. Never bypass a guard or reach into a cycling Windmill." },
    { "2 — BUY THE REQUIRED SUPPLIES", "Open the office computer and choose STOCK. Buy Black Ink for black-only work or Color Ink for each non-black color, Windmill Tympan sheets, and either Processed Plates or In-house Plate Materials. Computer purchases are delivered later by truck; unload their product pallets with the pallet jack. A press-supplies salesman may offer cheaper bulk quantities." },
    { "3 — GET AN OUTSOURCED PLATE", "Open this console's PLATES tab, select the correct job and color, then choose ORDER PROCESSED PLATE. The charge is posted to the job and the plate room needs about 24 game-hours. Return after it is ready; the processed plate is mounted for that color automatically." },
    { "4 — MAKE A PLATE IN HOUSE", "Keep In-house Plate Materials in inventory. In PLATES, select the job/color and choose START IN-HOUSE PLATE. Complete each timed quality window in order: expose the image, wash away non-image coating, dry the plate completely, then mount and lock it squarely in the chase. Poor timing lowers plate quality and print quality." },
    { "5 — PREPARE AND STAGE STOCK", "Use the Polar cutter to finish the job's paper before printing. Confirm the pallet tooltip says the required press size and PAPER COMPLETE. Move that pallet near the Windmill output area. In RUN, choose its LOAD row. The press will reject uncut stock, wet repeat-color work, or a color without its mounted plate." },
    { "6 — CHASE AND PACKING", "In SETUP, begin CHASE and hit all three inspection targets to lock the plate/chase squarely. Then run PACKING: install a clean tympan sheet and set packing thickness for even impression. Packing consumes one tympan sheet. A low score causes weak or uneven impression and more spoilage." },
    { "7 — ROLLERS AND INK", "Complete ROLLERS to set a consistent stripe. Complete INK to charge the ink train with the color named on the mounted plate. Ink is taken from warehouse inventory only when this check completes. If the game reports missing ink, buy it from STOCK or the press-supplies salesman, receive the delivery, and return." },
    { "8 — FEEDER AND REGISTER", "Complete FEEDER to set pile height, suction and double-sheet control. Complete REGISTER to align side guide and grippers to the plate. Accurate feeder setup prevents misses and doubles; accurate register keeps the image in the intended position. All six setup checks are mandatory." },
    { "9 — START, PROOF AND APPROVE", "In RUN, START MOTOR, turn FEEDER ON, and turn IMPRESSION ON. Choose PULL PROOF, then inspect the PROOF tab. A proof must reach 82% before approval. Correct a weak setup check and pull another proof if needed. Choose APPROVE PROOF only when register, density, impression, feed and detail are acceptable." },
    { "10 — PRODUCTION RUN", "Set a safe speed with SPEED − / +. The shop quotes around 3,000 good impressions per hour; the mechanical ceiling is 5,500 iph, but high speed and poor setup increase spoilage. Choose START RUN and watch counter, good sheets, spoilage, warnings and machine condition. E-STOP halts an unsafe cycle; RESET is required afterward." },
    { "11 — CLEAN, DRY AND REPEAT COLORS", "When the pass is complete, choose CLEAN + UNLOAD. The pallet moves to press output and the ink train is cleaned. Multi-color work must dry before the next plate/color can load. Repeat plate selection, six setup checks, proof approval and production for every color. Do not package until every color pass is complete." },
    { "12 — SERVICE AND FINISH", "Use SERVICE only with the press idle and unloaded. Lock out power in order, use one maintenance kit, and complete every component check. BOOK TECHNICIAN schedules field service for timing, suction, lubrication and safety faults. After the last color, move the printed pallet to wrapping, apply the job's required packaging, then complete the job on the office computer." },
}

local function drawTutorial(state, pointerX, pointerY)
    title("OPERATOR TRAINING", "First-job guide for guarded Windmill production")
    love.graphics.setColor(0.12, 0.14, 0.14)
    love.graphics.rectangle("fill", 82, 190, 796, 360, 8, 8)
    love.graphics.setColor(0.90, 0.90, 0.84)
    local page = tutorial[Screen.tutorialStep]
    love.graphics.setColor(0.96, 0.82, 0.28)
    love.graphics.printf(page[1], 112, 222, 736, "center")
    love.graphics.setColor(0.88, 0.91, 0.87)
    love.graphics.printf(page[2], 122, 274, 716, "left")
    love.graphics.setColor(0.70, 0.78, 0.78)
    love.graphics.printf(string.format("PAGE %d / %d", Screen.tutorialStep, #tutorial), 160, 516, 640, "center")
    button(190, 580, 250, 54, "◀ PREVIOUS", Screen.tutorialStep > 1, pointerX, pointerY)
    button(520, 580, 250, 54, Screen.tutorialStep == #tutorial and "FINISH TRAINING" or "NEXT ▶",
        true, pointerX, pointerY)
end

function Screen.draw(state, assets, pointerX, pointerY)
    drawFrame()
    drawTabs(pointerX, pointerY)
    if Screen.tab == "run" then drawRun(state, pointerX, pointerY)
    elseif Screen.tab == "plates" then drawPlates(state, pointerX, pointerY)
    elseif Screen.tab == "setup" then drawSetup(state, pointerX, pointerY)
    elseif Screen.tab == "proof" then drawProof(state, pointerX, pointerY)
    elseif Screen.tab == "maintenance" then drawMaintenance(state, pointerX, pointerY)
    else drawTutorial(state, pointerX, pointerY) end
    BackButton.draw(assets, BACK, "EXIT", pointerX, pointerY, false)
end

local function runClick(state, x, y)
    local p = Windmill.ensure(state)
    local controls = {
        { {52,340,158,54}, "motor" }, { {224,340,158,54}, "feeder" },
        { {396,340,158,54}, "impression" }, { {568,340,104,54}, "speed_down" },
        { {684,340,104,54}, "speed_up" }, { {800,340,104,54}, "emergency" },
        { {52,412,158,54}, "reset" },
    }
    for _, entry in ipairs(controls) do
        local r = { x=entry[1][1], y=entry[1][2], width=entry[1][3], height=entry[1][4] }
        if inside(r,x,y) then return Windmill.control(state, entry[2]) end
    end
    if inside({x=224,y=412,width=158,height=54},x,y) then return Windmill.takeProof(state) end
    if inside({x=396,y=412,width=158,height=54},x,y) then return Windmill.approveProof(state) end
    if inside({x=568,y=412,width=158,height=54},x,y) then
        return p.status == "production" and Windmill.stopProduction(state) or Windmill.startProduction(state)
    end
    if inside({x=740,y=412,width=164,height=54},x,y) then return Windmill.cleanAndUnload(state) end
    if p.status == "idle" then
        for index, item in ipairs(Windmill.candidates(state)) do
            if inside({x=52,y=526+(index-1)*45,width=852,height=38},x,y) then return Windmill.load(state,item.pallet.id) end
        end
    end
    return false
end

local function plateClick(state, x, y)
    local job, jobs = currentPlateJob(state)
    if not job then return false end
    if inside({x=700,y=176,width=92,height=34},x,y) and #jobs>1 then Screen.selectedPlateJob=Screen.selectedPlateJob-1; return true end
    if inside({x=804,y=176,width=92,height=34},x,y) and #jobs>1 then Screen.selectedPlateJob=Screen.selectedPlateJob+1; return true end
    local plates = Plates.ensureJob(job)
    for index=1,#plates do if inside({x=52+(index-1)*190,y=228,width=176,height=42},x,y) then Screen.selectedPlate=index; return true end end
    local plate = plates[Screen.selectedPlate]
    if inside({x=52,y=492,width=240,height=54},x,y) then return Plates.order(state,job,Screen.selectedPlate) end
    if inside({x=310,y=492,width=240,height=54},x,y) then return Plates.beginInHouse(state,job,Screen.selectedPlate) end
    if inside({x=568,y=492,width=328,height=54},x,y) and plate.status=="processing" then
        local marker=(math.sin(Screen.clock*2.2)+1)/2
        local accuracy=math.max(0,1-math.abs(marker-0.67)/0.33)
        return Plates.process(plate,Plates.actionFor(plate),accuracy)
    end
    return false
end

local function setupClick(state, x, y)
    if Screen.activeSetup then
        if inside({x=380,y=650,width=200,height=42},x,y) then Screen.activeSetup=nil; return true end
        local tx,ty=setupTarget()
        if (x-tx)^2+(y-ty)^2<=32^2 then Screen.setupHits=Screen.setupHits+1 else Screen.setupMisses=Screen.setupMisses+1 end
        if Screen.setupHits>=3 then
            local score=math.max(0.55,1-Screen.setupMisses*0.1)
            local ok, result = Windmill.completeSetup(state,Screen.activeSetup,score)
            if ok then
                Screen.activeSetup,Screen.setupHits,Screen.setupMisses=nil,0,0
            else
                state.message = result
                Screen.setupHits = 0
            end
        end
        return true
    end
    for index,task in ipairs(Windmill.setupTasks()) do
        local row,column=math.floor((index-1)/2),(index-1)%2
        if inside({x=52+column*426,y=190+row*112,width=408,height=90},x,y) then
            Screen.activeSetup,Screen.setupHits,Screen.setupMisses=task,0,0; return true
        end
    end
    return false
end

local function maintenanceClick(state,x,y)
    local machine=MachineFleet.installed(state,"heidelberg_10x15")
    if not machine then return false end
    if not Screen.maintenance then
        if inside({x=330,y=590,width=300,height=56},x,y) then
            local session,errorMessage=MachineMaintenance.begin(state,machine.id)
            if not session then state.message=errorMessage; return false end
            Screen.maintenance,Screen.lockoutStep=session,1
            Windmill.ensure(state).motor=false
            return true
        end
        if inside({x=650,y=590,width=240,height=56},x,y) then
            return MachineMaintenance.requestWindmillTechnician(state)
        end
        return false
    end
    if Screen.lockoutStep<=3 then
        local y=290+(Screen.lockoutStep-1)*82
        if inside({x=280,y=y,width=400,height=58},x,y) then Screen.lockoutStep=Screen.lockoutStep+1; return true end
        return false
    end
    if inside({x=300,y=370,width=360,height=90},x,y) then
        local task=MachineMaintenance.activeTask(Screen.maintenance)
        if not task then return false end
        MachineMaintenance.submitTask(Screen.maintenance,task.id,0.92)
        if Screen.maintenance.finished then
            local ok,result=MachineMaintenance.commit(state,Screen.maintenance)
            Screen.maintenance,Screen.lockoutStep=nil,1
            return ok,result
        end
        return true
    end
    return false
end

function Screen.mousepressed(state,x,y,button)
    if button~=1 then return false end
    if BackButton.contains(BACK,x,y) then return {action="exit"} end
    for _,tab in ipairs(tabs) do
        if inside({x=tab.x,y=120,width=122,height=38},x,y) then Screen.tab=tab.id; return {action="tab",tab=tab.id} end
    end
    local ok,result
    if Screen.tab=="run" then ok,result=runClick(state,x,y)
    elseif Screen.tab=="plates" then ok,result=plateClick(state,x,y)
    elseif Screen.tab=="setup" then ok,result=setupClick(state,x,y)
    elseif Screen.tab=="proof" then
        if inside({x=230,y=550,width=220,height=52},x,y) then ok,result=Windmill.takeProof(state)
        elseif inside({x=510,y=550,width=220,height=52},x,y) then ok,result=Windmill.approveProof(state) end
    elseif Screen.tab=="maintenance" then ok,result=maintenanceClick(state,x,y)
    elseif inside({x=190,y=580,width=250,height=54},x,y) and Screen.tutorialStep>1 then
        Screen.tutorialStep=Screen.tutorialStep-1; ok=true
    elseif inside({x=520,y=580,width=250,height=54},x,y) then
        if Screen.tutorialStep<#tutorial then Screen.tutorialStep=Screen.tutorialStep+1
        else state.windmill.tutorialComplete=true; Screen.tab="run" end
        ok=true
    end
    if ok==false and type(result)=="string" then state.message=result end
    return ok and {action="press_action",result=result} or false
end

function Screen.keypressed(state,key)
    local map={m="motor",f="feeder",i="impression",["-"]="speed_down",["+"]="speed_up",x="emergency",r="reset"}
    if key=="escape" then return {action="exit"} end
    if Screen.tab=="tutorial" and key=="left" then Screen.tutorialStep=math.max(1,Screen.tutorialStep-1); return true end
    if Screen.tab=="tutorial" and key=="right" then Screen.tutorialStep=math.min(#tutorial,Screen.tutorialStep+1); return true end
    if map[key] then return Windmill.control(state,map[key]) end
    if key=="space" then
        local p=Windmill.ensure(state)
        return p.status=="production" and Windmill.stopProduction(state) or Windmill.startProduction(state)
    end
    return false
end

function Screen.hasModal() return Screen.activeSetup~=nil or Screen.maintenance~=nil end

return Screen
