local BackButton = require("src.screens.back_button")
local BusinessCalendar = require("src.business_calendar")
local MachineFleet = require("src.machine_fleet")
local MachineMaintenance = require("src.machine_maintenance")
local Plates = require("src.plate_service")
local PressArtworkCompositor = require("src.press_artwork_compositor")
local PressSetupGames = require("src.press_setup_games")
local Windmill = require("src.windmill")

local Screen = {
    tab = "run", clock = 0, activeSetup = nil, setupHits = 0, setupMisses = 0,
    selectedCandidate = 1, selectedPlateJob = 1, selectedPlate = 1,
    maintenance = nil, lockoutStep = 1, tutorialStep = 1, buttonFlash = nil,
    feedbackText = nil, feedbackTone = "info", setupGame = nil,
}

local BACK = { x = 34, y = 630, width = 150, height = 36 }
local tabs = {
    { id = "run", label = "RUN", x = 34 }, { id = "plates", label = "PLATES", x = 170 },
    { id = "setup", label = "SETUP", x = 306 }, { id = "proof", label = "PROOF", x = 442 },
    { id = "maintenance", label = "SERVICE", x = 578 }, { id = "tutorial", label = "HELP", x = 714 },
}

local function inside(rect, x, y)
    return x >= rect.x and x <= rect.x + rect.width and y >= rect.y and y <= rect.y + rect.height
end

local function button(x, y, width, height, label, enabled, pointerX, pointerY, danger)
    local rect = { x = x, y = y, width = width, height = height }
    local hovered = pointerX and inside(rect, pointerX, pointerY)
    local pressed = hovered and love.mouse and love.mouse.isDown and love.mouse.isDown(1)
    local flashed = Screen.buttonFlash and Screen.clock <= Screen.buttonFlash.expires
        and inside(rect, Screen.buttonFlash.x, Screen.buttonFlash.y)
    local down = pressed or flashed
    y = y + (down and 2 or 0)
    love.graphics.setColor(enabled == false and flashed and 0.46 or enabled == false and 0.16
            or flashed and 0.42 or danger and 0.48 or hovered and 0.24 or 0.18,
        enabled == false and flashed and 0.15 or enabled == false and 0.17
            or flashed and 0.48 or danger and 0.13 or hovered and 0.42 or 0.31,
        enabled == false and flashed and 0.12 or enabled == false and 0.18
            or flashed and 0.16 or danger and 0.12 or hovered and 0.45 or 0.36, 1)
    love.graphics.rectangle("fill", x, y, width, height, 5, 5)
    love.graphics.setLineWidth(flashed and 4 or 1)
    love.graphics.setColor(enabled == false and flashed and 0.98 or enabled == false and 0.45
            or flashed and 1.00 or 0.90,
        enabled == false and flashed and 0.36 or enabled == false and 0.45
            or flashed and 0.84 or 0.94,
        enabled == false and flashed and 0.22 or enabled == false and 0.45
            or flashed and 0.24 or 0.88, 1)
    love.graphics.rectangle("line", x, y, width, height, 5, 5)
    if flashed then
        love.graphics.setColor(enabled == false and 0.98 or 1.0, enabled == false and 0.30 or 0.86, 0.20, 0.75)
        love.graphics.rectangle("line", x - 3, y - 3, width + 6, height + 6, 7, 7)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(enabled == false and 0.45 or 0.94, enabled == false and 0.45 or 0.96,
        enabled == false and 0.45 or 0.90, 1)
    love.graphics.printf(label, x, y + height / 2 - 7, width, "center")
    return rect
end

local function title(text, subtext)
    love.graphics.setColor(0.94, 0.82, 0.36)
    love.graphics.print(text, 40, 76)
    love.graphics.setColor(0.72, 0.80, 0.80)
    love.graphics.print(subtext or "", 40, 99)
end

local function setFeedback(state, text, tone)
    Screen.feedbackText = tostring(text or "Press console ready.")
    Screen.feedbackTone = tone or "info"
    if state then state.message = Screen.feedbackText end
end

local function drawFeedback(state)
    local text = Screen.feedbackText or state.message or "Press console ready."
    local tone = Screen.feedbackTone
    local color = tone == "error" and { 0.94, 0.32, 0.22 }
        or tone == "success" and { 0.30, 0.86, 0.38 }
        or { 0.90, 0.72, 0.22 }
    love.graphics.setColor(0.07, 0.09, 0.09, 0.98)
    love.graphics.rectangle("fill", 202, 630, 718, 36, 5, 5)
    love.graphics.setColor(color)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", 202, 630, 718, 36, 5, 5)
    love.graphics.setLineWidth(1)
    love.graphics.printf(text, 216, 641, 690, "center")
end

local function artworkKey(job)
    return job and job.artwork and job.artwork.key or job and job.artworkKey or "flower"
end

local function artworkName(job)
    return job and job.artwork and (job.artwork.displayName or job.artwork.fileName)
        or tostring(artworkKey(job)):gsub("%-", " ")
end

-- The generated atlas intentionally contains blank image areas. Every use of
-- it receives the live job artwork here, keeping the client's design visible
-- from intake through plate, proof, and finished stack.
local function drawProcessStage(assets, stage, job, x, y, width, height, quality)
    local image = assets and assets.get and assets.get("pressProcessStages")
    local sprite = assets and assets.getQuad and assets.getQuad("pressProcessStage" .. tostring(stage))
    if not image or not sprite then return false end
    local scale = math.min(width / sprite.width, height / sprite.height)
    local drawWidth, drawHeight = sprite.width * scale, sprite.height * scale
    local left, top = x + (width - drawWidth) / 2, y + (height - drawHeight) / 2
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, sprite.quad, left, top, 0, scale, scale)
    local art = assets and assets.getArtwork and assets.getArtwork(artworkKey(job))
    PressArtworkCompositor.draw(art, job, stage, left, top, drawWidth, drawHeight, quality)
    return true
end

function Screen.enter(state)
    Screen.tab, Screen.clock, Screen.activeSetup = "run", 0, nil
    Screen.setupGame = nil
    Screen.setupHits, Screen.setupMisses, Screen.maintenance, Screen.lockoutStep = 0, 0, nil, 1
    Screen.tutorialStep, Screen.buttonFlash = 1, nil
    Screen.feedbackText, Screen.feedbackTone = "Press console ready.", "info"
end

function Screen.update(dt, state)
    Screen.clock = Screen.clock + math.max(0, dt or 0)
end

local function drawFrame()
    love.graphics.setColor(0.035, 0.045, 0.05, 0.98)
    love.graphics.rectangle("fill", 20, 20, 920, 648, 10, 10)
    love.graphics.setColor(0.44, 0.52, 0.52)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", 20, 20, 920, 648, 10, 10)
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

local function drawRun(state, assets, pointerX, pointerY)
    local p, job, pallet = Windmill.current(state)
    local proofReady = Windmill.proofReadiness(state)
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
    love.graphics.print(string.format("GOOD: %d / %d   SPOIL: %d", p.goodSheets,
        p.targetSheets or 0, p.spoilage), 360, 249)
    love.graphics.print(string.format("FEED: %d / %d", p.feedRemaining or 0, p.feedStart or 0), 360, 276)
    love.graphics.print(string.format("PROOF: %s", p.proofQuality and string.format("%d%%", p.proofQuality * 100)
        or "NOT PULLED"), 560, 276)
    local machine = MachineFleet.installed(state, "heidelberg_10x15")
    love.graphics.print(string.format("CONDITION: %d%%", machine and MachineFleet.condition(machine) or 0), 580, 195)
    love.graphics.setColor(p.motor and 0.28 or 0.50, p.motor and 0.82 or 0.18, 0.18)
    love.graphics.circle("fill", 594, 249, 11)
    love.graphics.setColor(0.82, 0.88, 0.86)
    love.graphics.print(p.motor and "MOTOR ON" or "MOTOR OFF", 613, 242)
    local visualStage = p.status == "pass_complete" and 4
        or (p.status == "proof" or p.status == "approved" or p.status == "production") and 3
        or p.palletId and 2 or 1
    if job then drawProcessStage(assets, visualStage, job, 735, 181, 166, 132,
        p.proofQuality or (p.status == "production" and 0.96 or 1)) end
    love.graphics.setColor(p.warning and 0.94 or 0.42, p.warning and 0.46 or 0.76, 0.30)
    love.graphics.printf(p.warning or Windmill.failureSummary(state), 570, 303, 330, "center")

    button(52, 340, 158, 54, p.motor and "STOP MOTOR" or "START MOTOR", true, pointerX, pointerY)
    button(224, 340, 158, 54, p.feeder and "FEEDER OFF" or "FEEDER ON", p.motor, pointerX, pointerY)
    button(396, 340, 158, 54, p.impression and "OFF IMPRESSION" or "ON IMPRESSION", p.motor, pointerX, pointerY)
    button(568, 340, 104, 54, "SPEED −", true, pointerX, pointerY)
    button(684, 340, 104, 54, "SPEED +", true, pointerX, pointerY)
    button(800, 340, 104, 54, "E-STOP", true, pointerX, pointerY, true)
    button(52, 412, 158, 54, "RESET", p.emergency, pointerX, pointerY)
    button(224, 412, 158, 54, "PULL PROOF", proofReady, pointerX, pointerY)
    button(396, 412, 158, 54, "APPROVE PROOF", p.status == "proof" and p.artworkVerified,
        pointerX, pointerY)
    button(568, 412, 158, 54, p.status == "production" and "STOP RUN" or "START RUN",
        (p.status == "approved" and p.proofApproved) or p.status == "production",
        pointerX, pointerY)
    button(740, 412, 164, 54, "CLEAN + UNLOAD", p.status == "pass_complete", pointerX, pointerY)

    local candidates = Windmill.candidates(state)
    local dryingPallets = Windmill.dryingPallets(state)
    love.graphics.setColor(0.82, 0.88, 0.86)
    love.graphics.print(#dryingPallets > 0 and "PRESS OUTPUT — READY + DRYING"
        or "PRINT-READY PALLETS", 52, 498)
    if p.status == "idle" then
        for index, item in ipairs(candidates) do
            local y = 526 + (index - 1) * 45
            button(52, y, 852, 38, string.format("LOAD %s  •  %s  •  %s  •  %d ORDERED / %d SUPPLIED  •  COLOR %d",
                item.pallet.id, item.job.company, artworkName(item.job):upper(),
                item.pallet.requestedCopies or item.pallet.initialSheets,
                item.pallet.initialSheets, item.color), true, pointerX, pointerY)
        end
        for index, item in ipairs(dryingPallets) do
            local y = 526 + (#candidates + index - 1) * 45
            if y <= 646 then
                local drying = item.drying
                local totalMinutes = math.max(0, math.ceil(drying.remainingHours * 60))
                local hours, minutes = math.floor(totalMinutes / 60), totalMinutes % 60
                love.graphics.setColor(0.10, 0.13, 0.14)
                love.graphics.rectangle("fill", 52, y, 852, 38, 4, 4)
                love.graphics.setColor(0.86, 0.78, 0.38)
                love.graphics.print(string.format("DRYING %s  •  COLOR %d / %d  •  %dh %02dm",
                    item.pallet.id, item.pallet.press.completedColors or 0,
                    item.job.press.colors or 1, hours, minutes), 62, y + 5)
                love.graphics.setColor(0.18, 0.22, 0.22)
                love.graphics.rectangle("fill", 548, y + 12, 336, 14, 3, 3)
                love.graphics.setColor(0.88, 0.64, 0.18)
                love.graphics.rectangle("fill", 548, y + 12, 336 * drying.progress, 14, 3, 3)
                love.graphics.setColor(0.96, 0.94, 0.84)
                love.graphics.printf(string.format("%d%%", math.floor(drying.progress * 100 + 0.5)),
                    548, y + 11, 336, "center")
            end
        end
        if #candidates == 0 and #dryingPallets == 0 then
            love.graphics.setColor(0.68, 0.70, 0.68)
            love.graphics.printf("Stage cut client stock beside the press, prepare its plate, and allow prior ink to dry.", 52, 532, 852, "center")
        end
    else
        love.graphics.setColor(0.68, 0.70, 0.68)
        love.graphics.print("Unload the active pass before choosing another pallet.", 52, 532)
    end
end

local function drawPlates(state, assets, pointerX, pointerY)
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
    drawProcessStage(assets, 2, job, 662, 282, 214, 182, plate.quality > 0 and plate.quality or 0.72)
    love.graphics.setColor(0.70, 0.77, 0.76)
    love.graphics.printf("CLIENT ART: " .. artworkName(job):upper(), 620, 452, 280, "center")
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

local SETUP_VISUALS = {
    chase = { manual = 3, interaction = 1, hint = "ALIGN + SQUARE THE FORM BEFORE TIGHTENING BOTH QUOINS" },
    packing = { manual = 4, interaction = 2, hint = "TARGET: 3 PACKING LAYERS, SMOOTH TYMPAN, CLAMP CLOSED" },
    rollers = { manual = 5, interaction = 3, hint = "ADJUST BOTH ROLLER STRIPES INTO THE MANUAL'S 10–12 PT RANGE" },
    ink = { manual = 6, interaction = 4, hint = "BALANCE ALL THREE FOUNTAIN ZONES, THEN ENGAGE THE DUCTOR" },
    feeder = { manual = 7, interaction = 5, hint = "MATCH THE STOCK RESPONSE, THEN LIFT 3 SINGLE SHEETS" },
    register = { manual = 8, interaction = 6, hint = "MOVE THE GUIDES UNTIL X 0 / Y 0, THEN PULL A REGISTER TEST" },
}

local function drawQuadFit(image, sprite, x, y, width, height)
    if not image or not sprite then return false end
    local scale = math.min(width / sprite.width, height / sprite.height)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, sprite.quad, x + (width - sprite.width * scale) / 2,
        y + (height - sprite.height * scale) / 2, 0, scale, scale)
    return true
end

local function setupControlRects(game)
    local controls = PressSetupGames.controls(game.task)
    local gap, totalWidth = 8, 840
    local width = math.floor((totalWidth - gap * (#controls - 1)) / #controls)
    local result = {}
    for index, control in ipairs(controls) do
        result[index] = {
            action = control[1], label = control[2],
            x = 60 + (index - 1) * (width + gap), y = 574, width = width, height = 48,
        }
    end
    return result
end

function Screen.beginSetup(state, task)
    if not SETUP_VISUALS[task] then return false, "Unknown press setup task." end
    local p, job = Windmill.current(state)
    if not p.palletId or not job then return false, "Load a print-ready pallet before setup." end
    Screen.activeSetup, Screen.setupGame = task, PressSetupGames.new(task, job)
    return true, Screen.setupGame
end

local function drawSetup(state, assets, pointerX, pointerY)
    local p = Windmill.ensure(state)
    title("PRESS SETUP", "Complete chase, packing, roller, ink, feeder, and register checks")
    if not p.palletId then
        love.graphics.setColor(0.72, 0.76, 0.74)
        love.graphics.printf("Load a print-ready pallet from the RUN tab first.", 80, 250, 800, "center")
        return
    end
    if Screen.activeSetup and Screen.setupGame then
        local game, visual = Screen.setupGame, SETUP_VISUALS[Screen.activeSetup]
        love.graphics.setColor(0.84, 0.88, 0.84)
        love.graphics.printf(Screen.activeSetup:upper() .. " SETUP", 80, 184, 800, "center")
        love.graphics.setColor(0.62, 0.70, 0.69)
        love.graphics.printf(visual.hint, 80, 207, 800, "center")
        local manualImage = assets and assets.get and assets.get("pressOperatorHandbook")
        local manualSprite = assets and assets.getQuad and assets.getQuad("pressHandbookPage" .. visual.manual)
        drawQuadFit(manualImage, manualSprite, 62, 230, 390, 282)
        local interactionImage = assets and assets.get and assets.get("pressSetupInteractions")
        local interactionSprite = assets and assets.getQuad
            and assets.getQuad("pressSetupInteraction" .. visual.interaction)
        if interactionImage and interactionSprite then
            local angle, dx, dy = 0, 0, 0
            if game.task == "chase" then angle, dx = math.rad(game.angle * 3), game.offset * 8
            elseif game.task == "packing" then dy = game.clamped and 10 or -8
            elseif game.task == "rollers" then dx = math.sin(Screen.clock * 4) * (game.leftStripe + game.rightStripe) / 4
            elseif game.task == "ink" and game.ductor then angle = math.sin(Screen.clock * 5) * 0.035
            elseif game.task == "feeder" then dy = -game.tests * 6 + math.sin(Screen.clock * 6) * 3
            elseif game.task == "register" then dx, dy = game.xOffset * 6, game.yOffset * 6 end
            local scale = math.min(360 / interactionSprite.width, 282 / interactionSprite.height)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(interactionImage, interactionSprite.quad, 680 + dx, 371 + dy,
                angle, scale, scale, interactionSprite.width / 2, interactionSprite.height / 2)
        end
        love.graphics.setColor(0.92, 0.76, 0.28)
        love.graphics.printf(PressSetupGames.summary(game), 80, 526, 800, "center")
        if game.task == "feeder" then
            love.graphics.setColor(0.70, 0.78, 0.78)
            love.graphics.printf(game.target.hint, 80, 548, 800, "center")
        end
        for _, control in ipairs(setupControlRects(game)) do
            button(control.x, control.y, control.width, control.height, control.label,
                true, pointerX, pointerY)
        end
        button(40, 174, 130, 38, "CANCEL", true, pointerX, pointerY)
        return
    end
    for index, task in ipairs(Windmill.setupTasks()) do
        local row, column = math.floor((index - 1) / 2), (index - 1) % 2
        local x, y = 52 + column * 426, 190 + row * 112
        local score = p.setup[task]
        button(x, y, 408, 90, string.format("%s\n%s", task:upper(), score and string.format("COMPLETE %d%%", score * 100)
            or "BEGIN CHECK"), true, pointerX, pointerY)
    end
    local setupComplete = Windmill.setupComplete(state)
    local proofReady = Windmill.proofReadiness(state)
    button(300, 552, 360, 56, not setupComplete and "FINISH ALL SIX CHECKS"
        or proofReady and "PULL PROOF" or "GO TO RUN CONTROLS",
        setupComplete, pointerX, pointerY)
end

local function setupScore(p, task)
    local score = p and p.setup and tonumber(p.setup[task]) or 0
    return math.max(0, math.min(1, score))
end

function Screen.proofMetrics(state)
    local p = Windmill.ensure(state)
    local quality = math.max(0, math.min(1, tonumber(p.proofQuality) or 0))
    return {
        { "REGISTER", setupScore(p, "register") },
        { "INK DENSITY", setupScore(p, "ink") },
        { "IMPRESSION", (setupScore(p, "packing") + setupScore(p, "chase")) / 2 },
        { "ROLLER STRIPE", setupScore(p, "rollers") },
        { "SHEET FEED", setupScore(p, "feeder") },
        { "PLATE DETAIL", quality },
    }
end

local function drawProof(state, assets, pointerX, pointerY)
    local p, job = Windmill.current(state)
    local proofReady, proofReason = Windmill.proofReadiness(state)
    title("PROOF INSPECTION", "Compare the live job artwork, inspect quality, then verify before approval")
    love.graphics.setColor(0.12, 0.14, 0.14)
    love.graphics.rectangle("fill", 70, 178, 820, 350, 6, 6)
    if not p.proofQuality then
        love.graphics.setColor(0.72, 0.76, 0.74)
        if job then drawProcessStage(assets, 1, job, 118, 202, 310, 280, 1) end
        love.graphics.printf("No press proof yet. " .. proofReason,
            470, 300, 360, "center")
    else
        local q = p.proofQuality
        drawProcessStage(assets, 3, job, 92, 194, 350, 312, q)
        love.graphics.setColor(q >= 0.82 and 0.28 or 0.82, q >= 0.82 and 0.82 or 0.34, 0.28)
        love.graphics.printf(string.format("PROOF QUALITY  %d%%", q * 100), 474, 205, 360, "center")
        local labels = Screen.proofMetrics(state)
        for index, item in ipairs(labels) do
            local y = 250 + (index - 1) * 34
            love.graphics.setColor(0.84, 0.87, 0.83)
            love.graphics.print(item[1], 478, y)
            love.graphics.setColor(item[2] >= 0.82 and 0.32 or 0.88, item[2] >= 0.82 and 0.82 or 0.42, 0.26)
            love.graphics.rectangle("fill", 620, y + 2, 216 * item[2], 15)
        end
        love.graphics.setColor(p.artworkVerified and 0.32 or 0.88,
            p.artworkVerified and 0.84 or 0.52, 0.25)
        love.graphics.printf(p.artworkVerified and "ARTWORK MATCH VERIFIED"
            or "COMPARE IMAGE TO CLIENT FILE", 474, 462, 360, "center")
    end
    button(104, 558, 220, 52, p.proofQuality and "PULL ANOTHER PROOF" or "PULL PROOF",
        proofReady, pointerX, pointerY)
    button(370, 558, 220, 52, p.artworkVerified and "ARTWORK VERIFIED" or "VERIFY CLIENT ART",
        p.status == "proof", pointerX, pointerY)
    button(636, 558, 220, 52, "APPROVE PROOF",
        p.status == "proof" and p.artworkVerified, pointerX, pointerY)
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
        button(330, 570, 300, 56, "BEGIN LOCKOUT + SERVICE", (state.inventory.stock.maintenance_kit or 0) > 0
            and Windmill.ensure(state).status == "idle", pointerX, pointerY)
        local press = machine.maintenance.windmill
        love.graphics.setColor(0.70, 0.76, 0.74)
        love.graphics.printf(press.technicianDueDay and ("TECHNICIAN DUE DAY " .. press.technicianDueDay)
            or "Field service covers timing, lubrication, suction, and safety circuits.", 620, 535, 270, "center")
        button(650, 570, 240, 56, "BOOK TECHNICIAN  $350", not press.technicianDueDay
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
    { "1 — SAFETY AND JOB REVIEW", "GAMEPLAY: Read the office ticket for size, stock, quantity, colors, artwork and packaging. At the press, RESET clears an E-STOP only after the cause is safe. SERVICE requires the press idle and unloaded. REAL PRESS: keep hands, tools, jewelry and loose clothing outside the platen area; never bypass a guard or reach into a cycling Windmill." },
    { "2 — SUPPLIES AND PLATES", "GAMEPLAY: Stock the correct black or color ink, tympan sheets and press wash. In PLATES, choose a job/color and order a processed plate, or use in-house materials and lock four quality windows in order: EXPOSE, WASH, DRY and MOUNT. A mounted plate is required before the matching pallet can load." },
    { "3 — PREPARE AND STAGE STOCK", "GAMEPLAY: Finish the customer stock on the Polar, move the PAPER COMPLETE pallet beside the Windmill, then select its LOAD row in RUN. Supplied sheets minus ordered copies are the only allowance for proofs and spoilage. The next color cannot load until the prior pass has dried.", 2, "MANUAL PP. 64-65" },
    { "4 — CHASE LOCKUP", "GAMEPLAY: Use ALIGN FORM until the offset is zero, SQUARE FORM until rotation is zero, then TIGHTEN QUOINS twice. Tightening early records a fault and lowers the score. REAL PRESS: keep the gripper edge clear, position the form with furniture and tighten the quoins evenly so no type or plate can shift.", 3, "MANUAL PP. 43-45" },
    { "5 — TYMPAN AND PACKING", "GAMEPLAY: Set three packing layers, smooth both wrinkles, then close the clamp. Completing this check the first time consumes one clean tympan sheet. REAL PRESS: clamp a smooth tympan and full-size packing firmly. The manual's 10x15 total is 0.040 inch including the sheet being printed.", 4, "MANUAL PP. 46-51" },
    { "6 — FORM ROLLER HEIGHT", "GAMEPLAY: Use the four end-adjustment controls until both displayed stripes read 10–12 points. The result becomes the proof's roller-stripe rating. REAL PRESS: gauge both ends of both form rollers; correct unequal contact at the tracks.", 5, "MANUAL PP. 84-85" },
    { "7 — INK FOUNTAIN AND DISTRIBUTION", "GAMEPLAY: Cycle the three fountain keys until their values are balanced at 2–3, then engage the ductor. The first completion consumes the mounted plate's ink color. REAL PRESS: form a thin even film, use fountain keys for cross-sheet zones and the fountain lever for overall flow.", 6, "MANUAL PP. 86-89" },
    { "8 — FEEDER AND SUCTION", "GAMEPLAY: Match pile height, suction and air blast to the displayed stock hint, then pass three single-sheet tests. A bad test resets the count and lowers the score. REAL PRESS: fan and square the pile, center the sucker bar, disable suckers outside the sheet, and balance suction and air so exactly one sheet lifts.", 7, "MANUAL PP. 63-74" },
    { "9 — GUIDES AND REGISTER", "GAMEPLAY: Move the guides until the display reads X 0 and Y 0, then pull a register test. Testing while misaligned records a fault. REAL PRESS: choose gripper and guide edges, bring every sheet to the same guide corner and verify clearance from the form and grippers.", 8, "MANUAL PP. 52-60" },
    { "10 — START AND PULL A PROOF", "GAMEPLAY: All six setup checks must be complete. In RUN, START MOTOR, turn FEEDER ON, then turn ON IMPRESSION. PULL PROOF enables only when those controls are on, E-STOP is clear and at least one allowance sheet remains. Each proof consumes one sheet.", 1, "MANUAL PP. 38-39" },
    { "11 — INSPECT AND MAKEREADY", "GAMEPLAY: In PROOF, review register, ink density, impression, roller stripe, sheet feed and plate detail. Quality must reach 82%. Rerun weak setup checks and pull another proof if needed. Compare the live proof image with the client file, choose VERIFY CLIENT ART, then APPROVE PROOF." },
    { "12 — PRODUCTION RUN", "GAMEPLAY: After approval, choose START RUN. SPEED − / + ranges from 1,000 to 5,500 impressions per hour; speed above 3,000 and weak setup increase spoilage. Watch GOOD, SPOIL, FEED, warnings and condition. E-STOP halts the run; investigate, RESET and re-enable the operating controls." },
    { "13 — CLEAN, DRY AND REPEAT COLORS", "GAMEPLAY: When the pass reaches its target, use CLEAN + UNLOAD. Cleanup consumes press wash and returns the pallet to press output. RUN shows a live drying percentage and countdown: uncoated stock takes 2 game-hours and gloss stock takes 8. At 100%, load the next mounted color and repeat the workflow.", 9, "MANUAL PP. 90-94" },
    { "14 — SERVICE AND FINISH", "GAMEPLAY: With the press idle and unloaded, SERVICE consumes one maintenance kit. Complete DISCONNECT POWER, REMOVE + KEEP KEY and ATTACH LOCKOUT TAG in order, then finish each component check. BOOK TECHNICIAN handles field-service faults. Package the final printed pallet and close the job in the office.", 10, "MANUAL PP. 10-16" },
    { "15 — HANDBOOK SOURCES", "The face-free pixel illustrations are transformations of mechanic-specific photographs in Manual for the Operation of Heidelberg Platens for the 10x15 and 13x18 Original Heidelberg. Gameplay notes describe this build; REAL PRESS notes summarize the historical manual. This educational game is not a substitute for hands-on training, modern guarding, local safety rules or a qualified operator." },
}

local function drawTutorial(state, assets, pointerX, pointerY)
    title("WINDMILL OPERATOR HANDBOOK", "Pixel-art field guide grounded in the Original Heidelberg operating manual")
    love.graphics.setColor(0.12, 0.14, 0.14)
    love.graphics.rectangle("fill", 82, 190, 796, 360, 8, 8)
    love.graphics.setColor(0.90, 0.90, 0.84)
    local page = tutorial[Screen.tutorialStep]
    love.graphics.setColor(0.96, 0.82, 0.28)
    love.graphics.printf(page[1], 112, 222, 736, "center")
    love.graphics.setColor(0.88, 0.91, 0.87)
    local manualFrame = page[3]
    if manualFrame then
        local image = assets and assets.get and assets.get("pressOperatorHandbook")
        local sprite = assets and assets.getQuad and assets.getQuad("pressHandbookPage" .. manualFrame)
        if image and sprite then
            local scale = math.min(276 / sprite.width, 258 / sprite.height)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(image, sprite.quad, 108, 272, 0, scale, scale)
            love.graphics.setColor(0.62, 0.70, 0.69)
            love.graphics.printf("PIXEL ART  •  " .. tostring(page[4] or "MANUAL REFERENCE"),
                108, 536, 276, "center")
        end
        love.graphics.setColor(0.88, 0.91, 0.87)
        love.graphics.printf(page[2], 410, 274, 428, "left")
    else
        love.graphics.printf(page[2], 122, 274, 716, "left")
    end
    love.graphics.setColor(0.70, 0.78, 0.78)
    love.graphics.printf(string.format("PAGE %d / %d", Screen.tutorialStep, #tutorial), 160, 516, 640, "center")
    button(190, 568, 250, 54, "< PREVIOUS", Screen.tutorialStep > 1, pointerX, pointerY)
    button(520, 568, 250, 54, Screen.tutorialStep == #tutorial and "FINISH TRAINING" or "NEXT >",
        true, pointerX, pointerY)
end

function Screen.draw(state, assets, pointerX, pointerY)
    drawFrame()
    drawTabs(pointerX, pointerY)
    if Screen.tab == "run" then drawRun(state, assets, pointerX, pointerY)
    elseif Screen.tab == "plates" then drawPlates(state, assets, pointerX, pointerY)
    elseif Screen.tab == "setup" then drawSetup(state, assets, pointerX, pointerY)
    elseif Screen.tab == "proof" then drawProof(state, assets, pointerX, pointerY)
    elseif Screen.tab == "maintenance" then drawMaintenance(state, pointerX, pointerY)
    else drawTutorial(state, assets, pointerX, pointerY) end
    BackButton.draw(assets, BACK, "EXIT", pointerX, pointerY, false)
    drawFeedback(state)
end

local function pullProof(state)
    local ready, reason = Windmill.proofReadiness(state)
    if not ready then return false, reason, "proof" end
    local ok, result = Windmill.takeProof(state)
    if ok then Screen.tab = "proof" end
    return ok, result, "proof"
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
    if inside({x=224,y=412,width=158,height=54},x,y) then return pullProof(state) end
    if inside({x=396,y=412,width=158,height=54},x,y) then
        if p.status ~= "proof" then return false, "Pull a proof before approval." end
        if not p.artworkVerified then return false, "Verify the client artwork before approval." end
        return Windmill.approveProof(state)
    end
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
    if Screen.activeSetup and Screen.setupGame then
        if inside({x=40,y=174,width=130,height=38},x,y) then
            Screen.activeSetup, Screen.setupGame = nil, nil
            return true, "Setup check cancelled.", "setup_cancel"
        end
        for _, control in ipairs(setupControlRects(Screen.setupGame)) do
            if inside(control, x, y) then
                local complete, score = PressSetupGames.apply(Screen.setupGame, control.action)
                if complete then
                    local task = Screen.activeSetup
                    local ok, result = Windmill.completeSetup(state, task, score)
                    if ok then
                        Screen.activeSetup, Screen.setupGame = nil, nil
                        return true, string.format("%s check complete at %d%%.", task:upper(), score * 100),
                            "setup_complete"
                    end
                    return false, result, "setup_error"
                end
                return true, PressSetupGames.summary(Screen.setupGame), "setup_progress"
            end
        end
        return false
    end
    for index,task in ipairs(Windmill.setupTasks()) do
        local row,column=math.floor((index-1)/2),(index-1)%2
        if inside({x=52+column*426,y=190+row*112,width=408,height=90},x,y) then
            local ok, result = Screen.beginSetup(state, task)
            if not ok then return false, result, "setup_error" end
            return true, task:upper() .. " setup opened.", "setup_open"
        end
    end
    if inside({x=300,y=552,width=360,height=56},x,y) then
        if not Windmill.setupComplete(state) then
            return false, "Complete all six setup checks first.", "setup_footer"
        end
        local ready, reason = Windmill.proofReadiness(state)
        if ready then return pullProof(state) end
        Screen.tab = "run"
        return true, reason, "run_controls"
    end
    return false
end

local function maintenanceClick(state,x,y)
    local machine=MachineFleet.installed(state,"heidelberg_10x15")
    if not machine then return false end
    if not Screen.maintenance then
        if inside({x=330,y=570,width=300,height=56},x,y) then
            local process = Windmill.ensure(state)
            if process.status ~= "idle" or process.palletId then
                return false, "Unload the Windmill and return it to idle before service."
            end
            local session,errorMessage=MachineMaintenance.begin(state,machine.id)
            if not session then state.message=errorMessage; return false end
            Screen.maintenance,Screen.lockoutStep=session,1
            Screen.activeSetup, Screen.setupGame = nil, nil
            Windmill.releaseOperator(state)
            return true
        end
        if inside({x=650,y=570,width=240,height=56},x,y) then
            local process = Windmill.ensure(state)
            if process.status ~= "idle" or process.palletId then
                return false, "Unload the Windmill before booking press service."
            end
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
            if not ok then
                MachineMaintenance.rollbackLastTask(Screen.maintenance,task.id)
                return false,result
            end
            Screen.maintenance,Screen.lockoutStep=nil,1
            return ok,result
        end
        return true
    end
    return false
end

function Screen.mousepressed(state,x,y,button)
    if button~=1 then return false end
    Screen.buttonFlash = { x = x, y = y, expires = Screen.clock + 0.22 }
    if BackButton.contains(BACK,x,y) then return {action="exit"} end
    for _,tab in ipairs(tabs) do
        if inside({x=tab.x,y=120,width=122,height=38},x,y) then
            if Screen.maintenance and tab.id ~= "maintenance" then
                setFeedback(state, "Finish or exit the active service lockout before operating the press.", "error")
                return false
            end
            Screen.tab=tab.id
            setFeedback(state, tab.label .. " opened.", "info")
            return {action="tab",tab=tab.id}
        end
    end
    if Screen.maintenance and Screen.tab ~= "maintenance" then
        setFeedback(state, "Finish or exit the active service lockout before operating the press.", "error")
        return false
    end
    local ok,result,intent
    if Screen.tab=="run" then ok,result,intent=runClick(state,x,y)
    elseif Screen.tab=="plates" then ok,result,intent=plateClick(state,x,y)
    elseif Screen.tab=="setup" then ok,result,intent=setupClick(state,x,y)
    elseif Screen.tab=="proof" then
        if inside({x=104,y=558,width=220,height=52},x,y) then ok,result,intent=pullProof(state)
        elseif inside({x=370,y=558,width=220,height=52},x,y) then ok,result=Windmill.verifyArtwork(state)
        elseif inside({x=636,y=558,width=220,height=52},x,y) then ok,result=Windmill.approveProof(state) end
    elseif Screen.tab=="maintenance" then ok,result=maintenanceClick(state,x,y)
    elseif inside({x=190,y=568,width=250,height=54},x,y) and Screen.tutorialStep>1 then
        Screen.tutorialStep=Screen.tutorialStep-1; ok=true
    elseif inside({x=520,y=568,width=250,height=54},x,y) then
        if Screen.tutorialStep<#tutorial then Screen.tutorialStep=Screen.tutorialStep+1
        else state.windmill.tutorialComplete=true; Screen.tab="run" end
        ok=true
    end
    if ok==false and type(result)=="string" then
        setFeedback(state, result, "error")
    elseif ok then
        if intent=="proof" then
            setFeedback(state, "Proof pulled successfully. Inspect it before approval.", "success")
        elseif intent=="run_controls" then
            setFeedback(state, result, "info")
        elseif intent=="setup_progress" or intent=="setup_open" or intent=="setup_cancel" then
            setFeedback(state, result, "info")
        elseif intent=="setup_complete" then
            setFeedback(state, result, "success")
        else
            setFeedback(state, "Press action completed.", "success")
        end
    end
    return ok and {action="press_action",result=result} or false
end

function Screen.keypressed(state,key)
    local map={m="motor",f="feeder",i="impression",["-"]="speed_down",["+"]="speed_up",x="emergency",r="reset"}
    if key=="escape" then return {action="exit"} end
    if Screen.maintenance then
        if key == "x" then return Windmill.control(state, "emergency") end
        local message = "Finish or exit the active service lockout before operating the press."
        setFeedback(state, message, "error")
        return false, message
    end
    if Screen.tab=="tutorial" and key=="left" then Screen.tutorialStep=math.max(1,Screen.tutorialStep-1); return true end
    if Screen.tab=="tutorial" and key=="right" then Screen.tutorialStep=math.min(#tutorial,Screen.tutorialStep+1); return true end
    local ok, result, intent
    if map[key] then ok,result=Windmill.control(state,map[key])
    elseif key=="p" and (Screen.tab=="run" or Screen.tab=="proof" or Screen.tab=="setup") then
        ok,result,intent=pullProof(state)
    elseif key=="v" and Screen.tab=="proof" then ok,result=Windmill.verifyArtwork(state)
    end
    if key=="space" then
        local p=Windmill.ensure(state)
        ok,result=p.status=="production" and Windmill.stopProduction(state) or Windmill.startProduction(state)
    end
    if ok==false and type(result)=="string" then setFeedback(state,result,"error")
    elseif ok then setFeedback(state,intent=="proof" and "Proof pulled successfully. Inspect it before approval."
        or "Press action completed.","success") end
    return ok,result
end

function Screen.hasModal() return Screen.activeSetup~=nil or Screen.maintenance~=nil end

return Screen
