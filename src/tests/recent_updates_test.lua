local Calendar = require("src.business_calendar")
local Codec = require("src.net.codec")
local Contracts = require("src.employment_contracts")
local Employees = require("src.employees")
local EmployeeAI = require("src.employee_ai")
local EmployeeSchedule = require("src.employee_schedule")
local JobService = require("src.job_service")
local Jobs = require("src.jobs")
local Jukebox = require("src.jukebox")
local MachineFleet = require("src.machine_fleet")
local OptionsScreen = require("src.screens.options_screen")
local PalletState = require("src.pallet_state")
local Protocol = require("src.net.protocol")
local RabbitColorways = require("src.rabbit_colorways")
local Settings = require("src.settings")
local ShopClock = require("src.screens.shop_clock")
local Wrapper = require("src.wrapper")
local Work = require("src.employee_work")

local Test = {}

local function computerSpeedPoint(index)
    local rect = { x = 82, y = 184, width = 792, height = 444 }
    local buttonWidth, buttonHeight, gap = 94, 44, 14
    local total = 4 * buttonWidth + 3 * gap
    return rect.x + (rect.width - total) / 2 + (index - 1) * (buttonWidth + gap)
            + buttonWidth / 2,
        rect.y + 170 + buttonHeight / 2
end

local function employeeState(context, wrappingSkill)
    local state = context.State.new()
    local worker = {
        id = "EMP-RECENT-001", name = "Test Operator", status = "employed",
        cutterSkill = 70, pressSkill = 60, wrappingSkill = wrappingSkill,
        visible = false, clockedIn = false, phase = "hidden", x = 645, y = 235,
        intentX = 0, intentY = 1, distance = 0, idleClock = 0,
        fatigue = 0, focus = 100, breaksTaken = 0, breakRemaining = 0,
        sentHomeShiftDay = -1, terminationRequested = false, stopRequested = false,
        weeks = {}, schedule = EmployeeSchedule.defaultState(),
        contract = { wageCents = 2300, days = 127, startHour = 9, endHour = 17,
            startDay = 0, payWeeks = 1 },
    }
    state.employment = Employees.defaultState(0)
    state.employment.staff = { worker }
    return state, worker
end

local function drawScreen(screen, state, assets)
    love.graphics.push("all")
    local okay, message = pcall(screen.draw, state, nil, nil, assets)
    love.graphics.pop()
    return okay, message
end

function Test.run(context, check)
    local furIndex = math.min(2, RabbitColorways.count("fur"))
    local overallsIndex = math.min(3, RabbitColorways.count("overalls"))
    local optionSettings = Settings.normalize({ furColorway = 1, overallsColorway = 1 })
    local previousSave, previousAudio, previousDisplay = Settings.save,
        Settings.applyAudio, Settings.applyDisplay
    local savedSettings, appliedFur, appliedOveralls
    Settings.save = function(value) savedSettings = Settings.normalize(value);return true end
    Settings.applyAudio = function() end
    Settings.applyDisplay = function() end
    OptionsScreen.enter({ settings = optionSettings, save = { SLOT_COUNT = 3 }, state = {},
        applyPlayerColorways = function(fur, overalls)
            appliedFur, appliedOveralls = fur, overalls
        end })
    OptionsScreen.mousepressed(625, 114, 1)
    OptionsScreen.mousepressed(292 + (furIndex - 1) * 80 + 36, 301, 1)
    OptionsScreen.mousepressed(292 + (overallsIndex - 1) * 80 + 36, 461, 1)
    Settings.save, Settings.applyAudio, Settings.applyDisplay = previousSave, previousAudio, previousDisplay

    local hello = Protocol.make("hello", { clientNonce = "palette-test", name = "Guest",
        character = "rabbit-worker", furColorway = furIndex, overallsColorway = overallsIndex })
    local input = Protocol.make("input", { sessionId = "palette-test", sequence = 1,
        moveX = 0, moveY = 0, furColorway = furIndex, overallsColorway = overallsIndex })
    local roster = Protocol.make("snapshot", { sessionId = "palette-test", serverTick = 1,
        players = Codec.array({ { id = 2, name = "Guest", x = 500, y = 500,
            velocityX = 0, velocityY = 0, intentX = 0, intentY = 0, moving = false,
            facing = 1, animationDistance = 0, character = "rabbit-worker",
            furColorway = furIndex, overallsColorway = overallsIndex, inputSequence = 1 } }) })
    check("recent_rabbit_colorways_save_and_reach_multiplayer_packets",
        savedSettings and savedSettings.furColorway == furIndex
        and savedSettings.overallsColorway == overallsIndex
        and appliedFur == furIndex and appliedOveralls == overallsIndex
        and hello and hello.payload.furColorway == furIndex
        and input and input.payload.overallsColorway == overallsIndex
        and roster and roster.payload.players[1].furColorway == furIndex
        and roster.payload.players[1].overallsColorway == overallsIndex)

    local clockScreen = context.computerScreen.new()
    local currentSpeed, speedCalls = 1, 0
    clockScreen.configureGameClock({ getSpeed = function() return currentSpeed end,
        canChange = function() return true end,
        setSpeed = function(speed) currentSpeed = speed;speedCalls = speedCalls + 1;return true end })
    local clockState = context.State.new()
    clockScreen.enter(clockState)
    clockScreen.tab = "clock"
    local speedChecks = true
    for index, speed in ipairs({ 1, 2, 5, 10 }) do
        local x, y = computerSpeedPoint(index)
        local result = clockScreen.mousepressed(clockState, x, y, 1)
        speedChecks = speedChecks and result and result.action == "clock_speed_changed"
            and result.speed == speed and currentSpeed == speed
    end
    local clientSetCalls = 0
    local clientClock = context.computerScreen.new({ remoteCommand = function() end })
    clientClock.configureGameClock({ getSpeed = function() return currentSpeed end,
        canChange = function() return false end,
        setSpeed = function() clientSetCalls = clientSetCalls + 1;return true end })
    clientClock.enter(clockState)
    clientClock.tab = "clock"
    local x, y = computerSpeedPoint(3)
    local clientResult = clientClock.mousepressed(clockState, x, y, 1)
    check("recent_clock_offers_1x_2x_5x_10x_and_blocks_client_changes",
        speedChecks and speedCalls == 4 and clientResult and clientResult.action == "blocked"
        and clientSetCalls == 0 and clockState.message == "Only the host can change game speed.")

    local app = context.app
    local oldGameSpeed = app.gameClockSpeed
    local multiplayer = app.multiplayer
    local oldClientMethod = multiplayer.isClient
    multiplayer.isClient = function() return false end
    local acceptedSpeed = app.setGameClockSpeed(5)
    local singlePlayerSpeed = acceptedSpeed and app.gameClockSpeed == 5
    multiplayer.isClient = function() return true end
    local clientRejected = not app.setGameClockSpeed(10) and app.gameClockSpeed == 5
    multiplayer.isClient = oldClientMethod
    app.setGameClockSpeed(oldGameSpeed)
    check("recent_clock_speed_authority_is_host_only", singlePlayerSpeed and clientRejected)

    local originalDrawFace = ShopClock.drawFace
    local analogDraws, digitalTextSeen = 0, false
    local activeScreen = context.computerScreen.new()
    local statusState = context.State.new()
    local expectedTime = Calendar.timeText(statusState)
    local originalPrintf = love.graphics.printf
    ShopClock.drawFace = function(...) analogDraws = analogDraws + 1;return originalDrawFace(...) end
    love.graphics.printf = function(text, ...)
        if text == expectedTime then digitalTextSeen = true end
        return originalPrintf(text, ...)
    end
    activeScreen.enter(statusState)
    local activeDrawOkay = drawScreen(activeScreen, statusState, context.assets)
    activeScreen.tab = "clock"
    local clockDrawOkay = drawScreen(activeScreen, statusState, context.assets)
    love.graphics.printf = originalPrintf
    ShopClock.drawFace = originalDrawFace
    check("recent_computer_keeps_digital_status_time_without_analog_clock",
        activeDrawOkay and clockDrawOkay and digitalTextSeen and analogDraws == 0)

    local earlyExpressCount = 0
    local expressWindowsValid = true
    for sequence = 1, 5 do
        local service = JobService.deliveryServiceFor({ id = "JOB-EARLY-" .. sequence }, sequence)
        if service.id == "express" then earlyExpressCount = earlyExpressCount + 1 end
        if service.id == "express" then
            expressWindowsValid = expressWindowsValid and service.delayHours >= 2 and service.delayHours <= 6
        end
    end
    local etaState = context.State.new()
    local etaText = JobService.expectedStockArrivalText(etaState,
        { id = "JOB-ETA-RECENT", sequence = 1, deliveryService = { id = "express", delayHours = 3 } })
    check("recent_jobs_offer_more_early_express_and_estimates_show_stock_eta",
        earlyExpressCount >= 3 and expressWindowsValid and type(etaText) == "string"
        and #etaText > 0 and etaText ~= "Not assigned")

    local profiles = require("src.worker_catalog").profiles
    local readyToWrap, needsWrapTraining = false, false
    for _, profile in ipairs(profiles) do
        if (profile.wrappingSkill or 0) >= 50 then readyToWrap = true
        else needsWrapTraining = true end
    end
    local lowWrapWorker = { wrappingSkill = 25, contract = { wageCents = 2300 } }
    local trainingPlan = Employees.trainingPlan(lowWrapWorker, "wrapping")
    local allowedReady, allowedReadyReason = EmployeeSchedule.skillAllows(
        { wrappingSkill = 65 }, { difficulty = "easy" }, "wrapping")
    local allowedLow = EmployeeSchedule.skillAllows(
        { wrappingSkill = 25 }, { difficulty = "easy" }, "wrapping")
    check("recent_workers_mix_wrapper_ready_and_trainable_scores",
        readyToWrap and needsWrapTraining and allowedReady and not allowedReadyReason
        and not allowedLow and trainingPlan and trainingPlan.target == 50
        and trainingPlan.remainingHours == 4 and trainingPlan.expectedWageCents == 9200)

    local trainingState, trainee = employeeState(context, 25)
    local trainStarted = Employees.command(trainingState, {
        kind = "train_employee", employeeId = trainee.id, skill = "wrapping",
    }, 9.1)
    local initialTrainingHours = trainee.training and trainee.training.remainingHours
    EmployeeAI.worker(trainingState, trainee, 1, 8.5, {})
    local staysPausedOffShift = trainee.training and trainee.training.remainingHours == initialTrainingHours
    local paidSlice = 0.06 * Calendar.secondsPerDay(trainingState) / 24
    local trainingContext = {
        canClaim = function() return true end,
        operatorPoint = function(_, worker) return { x = worker.x, y = worker.y } end,
    }
    EmployeeAI.worker(trainingState, trainee, paidSlice, 9.1, trainingContext)
    local advancesByPaidHours = trainee.training
        and math.abs(trainee.training.remainingHours - (initialTrainingHours - 0.06)) < 0.0001
    trainee.training.remainingHours = 0.05
    EmployeeAI.worker(trainingState, trainee, paidSlice, 9.2, trainingContext)
    check("recent_wrapper_training_runs_on_paid_shift_hours_and_improves_skill",
        trainStarted and staysPausedOffShift and advancesByPaidHours
        and trainee.wrappingSkill == 50 and trainee.training == nil)

    local homeState, homeWorker = employeeState(context, 65)
    homeWorker.visible, homeWorker.clockedIn, homeWorker.phase = true, true, "idle"
    local sentHome = Employees.command(homeState, {
        kind = "send_employee_home", employeeId = homeWorker.id,
    }, 9.1)
    EmployeeAI.worker(homeState, homeWorker, 0.05, 9.1, {})
    check("recent_employee_send_home_ends_only_the_current_paid_shift",
        sentHome and homeWorker.sentHomeShiftDay == Contracts.shiftDay(homeWorker.contract, 9.1)
        and not homeWorker.visible and not homeWorker.clockedIn and homeWorker.status == "employed")

    local transferState = context.State.new()
    local transferJob = Jobs.createOffer({ id = "JOB-RECENT-WRAP", company = "Wrapper Transfer Test",
        sourceSize = { width = 20, height = 16 }, finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 }, packaging = "flat" })
    Jobs.accept(transferJob)
    transferState.jobs.active[1] = transferJob
    local pallet = transferJob.pallets[1]
    context.PalletLogistics.unload(transferState, transferJob.id, pallet.id,
        context.config.palletLogistics.spawnPoints, context.config.palletLogistics.unloadOrigin)
    pallet.paper.status = "complete"
    local cutterPosition = transferState.cutter or context.config.cutterPlacement
    pallet.world = { x = cutterPosition.x + 78, y = cutterPosition.y + 38,
        direction = "northwest", fromX = cutterPosition.x + 78,
        fromY = cutterPosition.y + 38, spawnProgress = 1 }
    local stagedAtCutter, cutterStageError = PalletState.transition(transferState, pallet, "at_cutter", { world = {
        x = cutterPosition.x + 78, y = cutterPosition.y + 38,
        direction = "northwest", fromX = cutterPosition.x + 78,
        fromY = cutterPosition.y + 38, spawnProgress = 1,
    } })
    local staged, outputStageError = false, nil
    if stagedAtCutter then
        staged, outputStageError = PalletState.transition(transferState, pallet,
            "cutter_output", { status = "cut", world = {
            x = 460, y = 520, direction = "northwest", fromX = 460, fromY = 520,
            spawnProgress = 1,
            } })
    end
    pallet.finishedSheets, pallet.remainingSheets = 500, 0
    local _, operator = employeeState(context, 65)
    transferState.employment.staff = { operator }
    local cutter = MachineFleet.installedUnits(transferState, "polar_115")[1]
    local wrapperMachine = MachineFleet.installedUnits(transferState, "skid_wrapper")[1]
    operator.visible, operator.clockedIn, operator.phase = true, true, "idle"
    operator.assignment = { jobId = transferJob.id, palletId = pallet.id,
        machineId = cutter.id, cutterMachineId = cutter.id, machineModel = cutter.modelId }
    local oldMessage = transferState.message
    local workContext = {
        canClaim = function() return true end,
        operatorPoint = function(_, worker) return { x = worker.x, y = worker.y } end,
        palletApproachPoint = function(item) return { x = item.world.x, y = item.world.y } end,
        palletDropPoint = function()
            return { x = transferState.wrapper.x + 80, y = transferState.wrapper.y }
        end,
        palletEmergencyDropPoint = function(_, item) return item.world end,
        move = function(worker, point) worker.x, worker.y = point.x, point.y;return true end,
    }
    Wrapper.forId(wrapperMachine.id).reset(transferState)
    Work.update(transferState, operator, 0.1, workContext)
    local carried = pallet.location == "on_employee" and pallet.carrierEmployeeId == operator.id
        and operator.carryingPalletId == pallet.id
    Work.update(transferState, operator, 0.1, workContext)
    local stagedAtWrapper = pallet.location == "warehouse" and operator.carryingPalletId == nil
        and pallet.world and math.abs(pallet.world.x - (transferState.wrapper.x + 80)) < 0.001
    local startedWrapping = false
    for _ = 1, 8 do
        Work.update(transferState, operator, 0.1, workContext)
        if Wrapper.forId(wrapperMachine.id).isActive() then startedWrapping = true;break end
    end
    Wrapper.updateAll(Wrapper.forId(wrapperMachine.id).cycleTime + 0.1, transferState)
    check("recent_employee_carries_finished_skid_to_wrapper_and_runs_it",
        staged and carried and stagedAtWrapper and startedWrapping and pallet.status == "wrapped",
        string.format("staged=%s carried=%s stagedAtWrapper=%s startedWrapping=%s status=%s location=%s activity=%s wrapperStep=%s",
            tostring(staged), tostring(carried), tostring(stagedAtWrapper),
            tostring(startedWrapping), tostring(pallet.status), tostring(pallet.location),
            tostring(operator.activity), tostring(Wrapper.forId(wrapperMachine.id).step))
            .. " stageErrors=" .. tostring(cutterStageError) .. "/" .. tostring(outputStageError)
            .. " cutter=" .. tostring(cutterPosition.x) .. "," .. tostring(cutterPosition.y))
    transferState.message = oldMessage

    local oldJukeboxState = { trackIndex = Jukebox.trackIndex, source = Jukebox.source,
        active = Jukebox.active, paused = Jukebox.paused }
    local originalNewSource = love.audio.newSource
    local trackPaths = {}
    love.audio.newSource = function(path)
        trackPaths[#trackPaths + 1] = path
        return {
            setLooping = function() end, setVolume = function() end, play = function() end,
            pause = function() end, stop = function() end, tell = function() return 0 end,
            seek = function() end, isPlaying = function() return true end,
        }
    end
    Jukebox.trackIndex, Jukebox.source, Jukebox.active, Jukebox.paused = 1, nil, false, true
    local radioState = { screen = "jukebox" }
    Jukebox.mousepressed(radioState, 420, 583, 1)
    for _ = 2, 9 do Jukebox.mousepressed(radioState, 540, 583, 1) end
    local vibesOnly, tracksExist = #trackPaths == 9, #trackPaths == 9
    for _, path in ipairs(trackPaths) do
        vibesOnly = vibesOnly and path:match("^assets/audio/music/vibes/") ~= nil
        tracksExist = tracksExist and love.filesystem.getInfo(path, "file") ~= nil
    end
    if Jukebox.source then Jukebox.source:stop() end
    love.audio.newSource = originalNewSource
    Jukebox.trackIndex, Jukebox.source, Jukebox.active, Jukebox.paused =
        oldJukeboxState.trackIndex, oldJukeboxState.source,
        oldJukeboxState.active, oldJukeboxState.paused
    check("recent_jukebox_plays_only_the_bundled_vibes_playlist", vibesOnly and tracksExist)
end

return Test
