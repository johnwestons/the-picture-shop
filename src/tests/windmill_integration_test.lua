local Test = {}
local PalletState = require("src.pallet_state")
local PressArtworkCompositor = require("src.press_artwork_compositor")
local PressSetupGames = require("src.press_setup_games")

local function makePressJob()
    return require("src.jobs").createOffer({
        id = "PRESS-TEST-001", company = "Windmill Test Client",
        sourceSize = { width = 10, height = 15 }, finishedSize = { width = 5, height = 7 },
        sheetCounts = { 1050 }, packaging = "flat", difficulty = "easy", artworkKey = "flower",
        press = { colors = 1, coverage = 0.35, artworkSize = { width = 4.25, height = 6.25 },
            colorSequence = { "Black" }, requestedCopies = { 1000 } },
        details = { stockDescription = "80 lb uncoated cover" },
    })
end

local function emergencyResetPreservesTerminalState(context)
    local state = context.State.new()
    local process = context.windmill.ensure(state)
    process.palletId = "RESET-PALLET"
    process.status, process.targetSheets, process.goodSheets = "pass_complete", 100, 100
    process.feedRemaining = 12
    local resetWithoutStop, resetReason = context.windmill.control(state, "reset")
    local stopped = context.windmill.control(state, "emergency")
    local restoredPass = context.windmill.control(state, "reset")
    local passPreserved = process.status == "pass_complete" and not process.emergency

    process.status, process.targetSheets, process.goodSheets = "stopped", 100, 90
    process.feedRemaining, process.emergency, process.proofApproved = 0, true, false
    local restoredShortage = context.windmill.control(state, "reset")
    local shortagePreserved = process.status == "stock_shortage" and not process.emergency
    return not resetWithoutStop and resetReason == "E-STOP is not active."
        and stopped and restoredPass and passPreserved
        and restoredShortage and shortagePreserved
end

local function nativeServiceInterlockWorks(context, state)
    state.inventory.stock.maintenance_kit = math.max(
        1, tonumber(state.inventory.stock.maintenance_kit) or 0)
    local process = context.windmill.ensure(state)
    if not context.windmill.control(state, "motor")
        or not context.windmill.control(state, "feeder")
        or not context.windmill.control(state, "impression")
    then
        return false
    end
    context.pressScreen.enter(state)
    context.pressScreen.tab = "maintenance"
    local serviceStarted = context.pressScreen.mousepressed(state, 480, 598, 1)
    local modalActive = context.pressScreen.hasModal()
    local tabBlocked = context.pressScreen.mousepressed(state, 95, 139, 1)
    local remainedOnService = context.pressScreen.tab == "maintenance"
    context.pressScreen.tab = "run"
    local clickBlocked = context.pressScreen.mousepressed(state, 131, 367, 1)
    local keyBlocked = context.pressScreen.keypressed(state, "m")
    local emergencyAccepted = context.pressScreen.keypressed(state, "x")
    local safeDuringService = not process.motor and not process.feeder
        and not process.impression and process.emergency
    local resetAccepted = context.windmill.control(state, "reset")
    context.pressScreen.enter(state)
    return type(serviceStarted) == "table" and modalActive
        and not tabBlocked and remainedOnService and not clickBlocked and not keyBlocked
        and emergencyAccepted and safeDuringService and resetAccepted
        and process.status == "idle" and not context.pressScreen.hasModal()
end

local function remoteServiceKitRaceRecovers(context)
    -- App workshop callbacks close over the live app state, so exercise that
    -- exact authority boundary instead of an isolated state passed as context.
    local state = context.state
    state.money = math.max(20000, tonumber(state.money) or 0)
    state.inventory.stock.maintenance_kit = 1
    if not context.machineFleet.installed(state, "heidelberg_10x15")
        and not context.machineFleet.buy(state, "dealer", 3)
    then
        return false, "buy"
    end
    local process = context.windmill.ensure(state)
    process.status, process.jobId, process.palletId = "idle", nil, nil
    process.motor, process.feeder, process.impression, process.emergency = false, false, false, false
    local authority = context.createWorkshopAuthority()
    local player = { id = 2, x = state.windmill.x, y = state.windmill.y }
    local requestId = 1
    local lease = authority:acquire(player, {
        requestId = requestId, resourceId = "windmill",
    }, { state = state })
    if not lease.accepted then return false, "acquire:" .. tostring(lease.message) end
    local function command(action)
        requestId = requestId + 1
        local result = authority:command(player, {
            requestId = requestId,
            resourceId = "windmill",
            leaseId = lease.leaseId,
            action = action,
            args = {},
            expectedRevision = lease.revision,
        }, { state = state })
        if result.accepted then lease.revision = result.revision end
        return result
    end
    local started = command("begin_service")
    if not started.accepted then return false, "begin:" .. tostring(started.message) end
    for _ = 1, 3 do
        local locked = command("service_lockout")
        if not locked.accepted then return false, "lockout:" .. tostring(locked.message) end
    end
    state.inventory.stock.maintenance_kit = 0
    local kitFailure
    for _ = 1, 12 do
        local result = command("service_task")
        if not result.accepted then kitFailure = result; break end
    end
    if not kitFailure or kitFailure.message ~= "A machine maintenance kit is required."
        or not kitFailure.data or kitFailure.data.serviceStep ~= "task"
    then
        return false, string.format("failure=%s/%s/%s",
            tostring(kitFailure and kitFailure.code),
            tostring(kitFailure and kitFailure.message),
            tostring(kitFailure and kitFailure.data and kitFailure.data.serviceStep))
    end
    state.inventory.stock.maintenance_kit = 1
    local completed = command("service_task")
    requestId = requestId + 1
    local released = authority:release(player, {
        requestId = requestId,
        resourceId = "windmill",
        leaseId = lease.leaseId,
        reason = "closed",
    }, { state = state })
    local passed = completed.accepted and completed.data and completed.data.serviceStep == "idle"
        and state.inventory.stock.maintenance_kit == 0 and released.accepted
    return passed, string.format("complete=%s/%s/%s kit=%s release=%s/%s",
        tostring(completed.accepted), tostring(completed.code),
        tostring(completed.data and completed.data.serviceStep),
        tostring(state.inventory.stock.maintenance_kit), tostring(released.accepted),
        tostring(released.message))
end

local function upvalue(fn, targetName)
    if type(fn) ~= "function" or not debug or not debug.getupvalue then return nil end
    for index = 1, 64 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == targetName then return index, value end
    end
end

local function runHostTransportFailureCleanupRegression(context, check)
    local App = require("src.app")
    local _, updateMultiplayer = upvalue(App.update, "updateMultiplayer")
    local _, handleMultiplayerEvents = upvalue(
        updateMultiplayer, "handleMultiplayerEvents")
    local authorityIndex, previousAuthority = upvalue(
        handleMultiplayerEvents, "workshopAuthority")
    local authority = context.createWorkshopAuthority()
    local player = {
        id = 2,
        x = context.state.windmill.x,
        y = context.state.windmill.y,
    }
    local lease = authority:acquire(player, {
        requestId = 1,
        resourceId = "windmill",
    }, { state = context.state })
    local process = context.windmill.ensure(context.state)
    process.status = "production"
    process.motor, process.feeder, process.impression = true, true, true
    process.emergency = false

    local multiplayer = App.multiplayer
    local originalDrainEvents, originalStop = multiplayer.drainEvents, multiplayer.stop
    local previousScreen = context.state.screen
    local stopCalled = false
    if authorityIndex and lease.accepted then
        debug.setupvalue(handleMultiplayerEvents, authorityIndex, authority)
    end
    multiplayer.drainEvents = function()
        return { { type = "disconnected", message = "Synthetic host transport failure" } }
    end
    multiplayer.stop = function(_, reason)
        stopCalled = reason == "Host disconnected"
        return true
    end
    local handled, handleError = pcall(handleMultiplayerEvents)
    local authorityAfterEvent
    if authorityIndex then
        local ignored
        ignored, authorityAfterEvent = debug.getupvalue(
            handleMultiplayerEvents, authorityIndex)
    end
    local authorityCleared = authorityAfterEvent == nil
        and authority:leaseForResource("windmill") == nil
    local stoppedSafely = process.status == "approved"
        and not process.motor and not process.feeder and not process.impression
    local routedToLan = context.state.screen == "lan"

    multiplayer.drainEvents, multiplayer.stop = originalDrainEvents, originalStop
    if authorityIndex then
        debug.setupvalue(handleMultiplayerEvents, authorityIndex, previousAuthority)
    end
    context.state.screen = previousScreen
    process.status = "idle"
    process.motor, process.feeder, process.impression = false, false, false

    check("app_host_transport_failure_clears_authority_and_stops_windmill_controls",
        updateMultiplayer and handleMultiplayerEvents and authorityIndex
        and lease.accepted and handled and handleError == nil
        and stopCalled and routedToLan and authorityCleared and stoppedSafely,
        tostring(handleError))
end

function Test.run(context, check)
    local setupSequences = {
        chase = { "align", "align", "square", "square", "tighten", "tighten" },
        packing = { "layer", "layer", "layer", "smooth", "smooth", "clamp" },
        rollers = { "left_up", "left_up", "right_down", "right_down" },
        ink = { "key_1", "key_1", "key_2", "key_2", "key_2", "key_2", "key_3", "ductor" },
        feeder = { "prepare", "suction_up", "air_down", "test", "test", "test" },
        register = { "left", "left", "left", "down", "down", "test" },
    }
    local setupGamesComplete, controlSignatures = true, {}
    for task, sequence in pairs(setupSequences) do
        local game = PressSetupGames.new(task, { stockSpec = { grade = "cover", weight = 100 } })
        local complete, score = false, nil
        for _, action in ipairs(sequence) do complete, score = PressSetupGames.apply(game, action) end
        setupGamesComplete = setupGamesComplete and complete and score == 1
        local labels = {}
        for _, control in ipairs(PressSetupGames.controls(task)) do labels[#labels + 1] = control[2] end
        controlSignatures[table.concat(labels, "|")] = true
    end
    local signatureCount = 0
    for _ in pairs(controlSignatures) do signatureCount = signatureCount + 1 end
    local lightFeeder = PressSetupGames.new("feeder", { stockSpec = { grade = "text", weight = 50 } })
    local coverFeeder = PressSetupGames.new("feeder", { stockSpec = { grade = "cover", weight = 100 } })
    check("six_manual_based_press_setup_games_have_distinct_controls_and_solvable_scoring",
        setupGamesComplete and signatureCount == 6)
    check("feeder_setup_uses_distinct_light_and_cover_stock_profiles",
        lightFeeder.target.pile ~= coverFeeder.target.pile
        and lightFeeder.target.suction ~= coverFeeder.target.suction
        and lightFeeder.target.air ~= coverFeeder.target.air
        and lightFeeder.target.profile == "LIGHT STOCK"
        and coverFeeder.target.profile == "HEAVY STOCK")

    local auditedFeeder = PressSetupGames.new(
        "feeder", { stockSpec = { grade = "cover", weight = 100 } })
    PressSetupGames.apply(auditedFeeder, "test")
    local blocksUnloadedTest = auditedFeeder.cleanFeeds == 0
        and auditedFeeder.faults == 1
        and PressSetupGames.instruction(auditedFeeder):find("fan and load", 1, true)
    PressSetupGames.apply(auditedFeeder, "prepare")
    PressSetupGames.apply(auditedFeeder, "test")
    local diagnosesSuction = auditedFeeder.cleanFeeds == 0
        and PressSetupGames.instruction(auditedFeeder):find("INCREASE SUCTION", 1, true)
    PressSetupGames.apply(auditedFeeder, "suction_up")
    PressSetupGames.apply(auditedFeeder, "test")
    local diagnosesAir = auditedFeeder.cleanFeeds == 0
        and PressSetupGames.instruction(auditedFeeder):find("REDUCE SEPARATING AIR", 1, true)
    PressSetupGames.apply(auditedFeeder, "air_down")
    PressSetupGames.apply(auditedFeeder, "test")
    local provesSingleSheet = auditedFeeder.cleanFeeds == 1
        and PressSetupGames.instruction(auditedFeeder):find("CLEAN SINGLE%-SHEET FEED")
    PressSetupGames.apply(auditedFeeder, "suction_down")
    local adjustmentResetsProof = auditedFeeder.cleanFeeds == 0
    check("feeder_setup_guides_load_calibration_and_three_clean_feed_proof",
        blocksUnloadedTest and diagnosesSuction and diagnosesAir
        and provesSingleSheet and adjustmentResetsProof)

    local compositorCases = {
        { finishedSize = { width = 6, height = 9 }, press = { artworkSize = { width = 5.4, height = 8.2 } } },
        { finishedSize = { width = 9, height = 6 }, press = { artworkSize = { width = 8, height = 4 } } },
        { finishedSize = { width = 6, height = 6 }, press = { artworkSize = { width = 4, height = 4 } } },
        { finishedSize = { width = 10, height = 15 }, press = { artworkSize = { width = 0.5, height = 0.5 } } },
        { finishedSize = { width = 5, height = 7 }, press = { artworkSize = { width = 12, height = 18 } } },
    }
    local compositorSafe = true
    for _, jobCase in ipairs(compositorCases) do
        for stage = 1, 4 do
            local layout = PressArtworkCompositor.layout(jobCase, stage, 0.7)
            local bounds = layout.bounds
            compositorSafe = compositorSafe and bounds.u0 >= 0.08 and bounds.u1 <= 0.92
                and bounds.v0 >= 0.14 and bounds.v1 <= 0.92
                and bounds.u0 < bounds.u1 and bounds.v0 < bounds.v1
            for _, corner in ipairs(layout.corners) do
                compositorSafe = compositorSafe and corner[1] >= 0 and corner[1] <= 1
                    and corner[2] >= 0 and corner[2] <= 1
            end
        end
    end
    check("press_artwork_compositor_clips_portrait_landscape_square_minimum_and_maximum_art",
        compositorSafe and PressArtworkCompositor.layout(compositorCases[1], 2, 1).reversed)

    local partialSetupState = context.State.new()
    local partialProcess = context.windmill.ensure(partialSetupState)
    partialProcess.proofQuality = 0.91
    partialProcess.setup = { chase = 0.96 }
    local partialMetrics = context.pressScreen.proofMetrics(partialSetupState)
    check("proof_display_tolerates_partial_setup_scores_from_older_saves",
        partialMetrics[1][2] == 0 and partialMetrics[2][2] == 0
        and partialMetrics[3][2] == 0.48 and partialMetrics[4][2] == 0
        and partialMetrics[5][2] == 0 and partialMetrics[6][2] == 0.91)

    local networkRuntimeState = context.State.new()
    context.windmill.resetNetworkRuntime()
    local emergencyAccepted = context.windmill.control(networkRuntimeState, "emergency")
    local emergencyRevision = context.windmill.networkRuntimeRevision()
    local networkProcess = context.windmill.ensure(networkRuntimeState)
    networkProcess.status = "production"
    networkProcess.motor, networkProcess.feeder, networkProcess.impression = true, true, true
    local released = context.windmill.releaseOperator(networkRuntimeState)
    local releaseRevision = context.windmill.networkRuntimeRevision()
    local releasedAgain = context.windmill.releaseOperator(networkRuntimeState)
    check("windmill_network_revision_and_release_preserve_emergency_while_stopping_motion",
        emergencyAccepted and emergencyRevision == 1 and released and not releasedAgain
        and releaseRevision == 2 and context.windmill.networkRuntimeRevision() == 2
        and networkProcess.status == "approved" and not networkProcess.motor
        and not networkProcess.feeder and not networkProcess.impression
        and networkProcess.emergency)
    check("windmill_reset_requires_an_active_estop_and_preserves_terminal_run_states",
        emergencyResetPreservesTerminalState(context))

    local plateRuntimeState = context.State.new()
    local plateRuntimeJob = makePressJob()
    plateRuntimeState.jobs.active = { plateRuntimeJob }
    local runtimePlate = context.plateService.ensureJob(plateRuntimeJob)[1]
    runtimePlate.status, runtimePlate.source, runtimePlate.readyAtHours = "ordered", "outsourced", 0
    context.windmill.resetNetworkRuntime()
    context.pressScreen.update(0, plateRuntimeState)
    local plateChanged, plateDurable = context.windmill.update(0, plateRuntimeState)
    check("windmill_global_runtime_owns_and_saves_outsourced_plate_readiness",
        plateChanged and plateDurable and runtimePlate.status == "ready"
        and runtimePlate.mounted and context.windmill.networkRuntimeRevision() == 1)

    local updateOrder = {}
    local machineOrDurable, windmillLive, windmillDurable = context.serviceNetworkBeforeMachine(
        0, context.State.new(),
        function() updateOrder[#updateOrder + 1] = "network" end,
        function()
            updateOrder[#updateOrder + 1] = "windmill"
            return true, false
        end)
    local terminalDirty = context.serviceNetworkBeforeMachine(
        0, context.State.new(), function() end, function() return true, true end)
    check("network_safety_is_serviced_before_global_windmill_advancement",
        updateOrder[1] == "network" and updateOrder[2] == "windmill"
        and not machineOrDurable and windmillLive and not windmillDurable and terminalDirty)

    local appAuthority = context.createWorkshopAuthority()
    local appWindmillPlayer = {
        id = 2,
        x = context.state.windmill.x,
        y = context.state.windmill.y,
    }
    local appWindmillLease = appAuthority:acquire(appWindmillPlayer, {
        requestId = 1, resourceId = "windmill",
    }, { state = context.state })
    local staleOrdinary = appWindmillLease.accepted and appAuthority:command(appWindmillPlayer, {
        requestId = 2, resourceId = "windmill", leaseId = appWindmillLease.leaseId,
        action = "speed_up", args = {}, expectedRevision = 0,
    }, { state = context.state }) or {}
    local urgentStop = appWindmillLease.accepted and appAuthority:command(appWindmillPlayer, {
        requestId = 3, resourceId = "windmill", leaseId = appWindmillLease.leaseId,
        action = "emergency_stop", args = {}, expectedRevision = 0,
    }, { state = context.state }) or {}
    local releasedWindmillLease = appWindmillLease.accepted and appAuthority:release(
        appWindmillPlayer, {
            requestId = 4, resourceId = "windmill", leaseId = appWindmillLease.leaseId,
            reason = "closed",
        }, { state = context.state }) or {}
    local appWindmillProcess = context.windmill.ensure(context.state)
    check("app_windmill_authority_builds_a_bounded_view_and_preempts_stale_commands_for_estop",
        appWindmillLease.accepted and appWindmillLease.data
        and type(appWindmillLease.data.setupPermille) == "table"
        and #appWindmillLease.data.setupPermille == 6
        and type(appWindmillLease.data.plateMarkerPermille) == "number"
        and not staleOrdinary.accepted and staleOrdinary.code == "revision_conflict"
        and urgentStop.accepted and urgentStop.data and urgentStop.data.emergency
        and releasedWindmillLease.accepted
        and appAuthority:leaseForResource("windmill") == nil
        and appWindmillProcess.emergency and not appWindmillProcess.motor
        and not appWindmillProcess.feeder and not appWindmillProcess.impression)
    runHostTransportFailureCleanupRegression(context, check)

    context.state.inventory.stock.maintenance_kit = 1
    appWindmillProcess.status, appWindmillProcess.jobId, appWindmillProcess.palletId = "idle", nil, nil
    appWindmillProcess.emergency = false
    appWindmillProcess.motor, appWindmillProcess.feeder, appWindmillProcess.impression = true, true, true
    local serviceAuthority = context.createWorkshopAuthority()
    local serviceLease = serviceAuthority:acquire(appWindmillPlayer, {
        requestId = 1, resourceId = "windmill",
    }, { state = context.state })
    local serviceStarted = serviceLease.accepted and serviceAuthority:command(appWindmillPlayer, {
        requestId = 2, resourceId = "windmill", leaseId = serviceLease.leaseId,
        action = "begin_service", args = {}, expectedRevision = serviceLease.revision,
    }, { state = context.state }) or {}
    local operationBlocked = serviceStarted.accepted and serviceAuthority:command(appWindmillPlayer, {
        requestId = 3, resourceId = "windmill", leaseId = serviceLease.leaseId,
        action = "toggle_motor", args = {}, expectedRevision = serviceStarted.revision,
    }, { state = context.state }) or {}
    local serviceEmergency = serviceStarted.accepted and serviceAuthority:command(appWindmillPlayer, {
        requestId = 4, resourceId = "windmill", leaseId = serviceLease.leaseId,
        action = "emergency_stop", args = {}, expectedRevision = serviceStarted.revision,
    }, { state = context.state }) or {}
    local lockoutAdvanced = serviceEmergency.accepted and serviceAuthority:command(appWindmillPlayer, {
        requestId = 5, resourceId = "windmill", leaseId = serviceLease.leaseId,
        action = "service_lockout", args = {}, expectedRevision = serviceEmergency.revision,
    }, { state = context.state }) or {}
    local serviceReleased = serviceLease.accepted and serviceAuthority:release(appWindmillPlayer, {
        requestId = 6, resourceId = "windmill", leaseId = serviceLease.leaseId,
        reason = "closed",
    }, { state = context.state }) or {}
    check("windmill_service_lockout_blocks_operation_but_preserves_estop_and_service_controls",
        serviceStarted.accepted and serviceStarted.data
        and serviceStarted.data.serviceStep == "lockout_disconnect"
        and not appWindmillProcess.motor and not appWindmillProcess.feeder
        and not appWindmillProcess.impression
        and not operationBlocked.accepted and operationBlocked.code == "service_active"
        and serviceEmergency.accepted and serviceEmergency.data.emergency
        and lockoutAdvanced.accepted and lockoutAdvanced.data.serviceStep == "lockout_key"
        and serviceReleased.accepted and serviceAuthority:leaseForResource("windmill") == nil)
    local serviceRacePassed, serviceRaceDetail = remoteServiceKitRaceRecovers(context)
    check("windmill_remote_service_can_retry_if_another_machine_consumes_the_shared_kit",
        serviceRacePassed, serviceRaceDetail)

    local state = context.State.new()
    state.money = 20000
    local bought, machine = context.machineFleet.buy(state, "dealer", 3)
    check("windmill_can_be_purchased_as_the_first_installed_press", bought and machine
        and machine.modelId == "heidelberg_10x15" and machine.status == "installed")

    context.computerScreen.enter(state)
    local dropdownX, dropdownY = context.computerScreen.dropdownCenter()
    context.computerScreen.mousepressed(state, dropdownX, dropdownY, 1)
    local wwwX, wwwY = context.computerScreen.tabCenter("www")
    context.computerScreen.mousepressed(state, wwwX, wwwY, 1)
    local pressSiteX, pressSiteY = context.computerScreen.wwwSiteCenter(2)
    local selectedSite = context.computerScreen.mousepressed(state, pressSiteX, pressSiteY, 1)
    local plateKitX, plateKitY = context.computerScreen.retailButtonCenter(5)
    local plateKitAdded = context.computerScreen.mousepressed(state, plateKitX, plateKitY, 1)
    local cartX, cartY = context.computerScreen.cartButtonCenter()
    context.computerScreen.mousepressed(state, cartX, cartY, 1)
    local checkoutX, checkoutY = context.computerScreen.cartCheckoutCenter()
    local plateKitCheckout = context.computerScreen.mousepressed(state, checkoutX, checkoutY, 1)
    local plateKitOrder = plateKitCheckout and plateKitCheckout.result.orders[1]
    check("critter_net_pressroom_lists_all_press_supply_products", selectedSite
        and selectedSite.site.url == "www.thecritternet.com/pressroom"
        and plateKitAdded and plateKitAdded.action == "cart_item_added"
        and plateKitCheckout and plateKitCheckout.action == "cart_checked_out"
        and plateKitOrder.item == "plate_room_kit")

    local job = makePressJob()
    job.status = "in_progress"
    state.jobs.active = { job }
    local pallet = job.pallets[1]
    pallet.location, pallet.status = "cutter_output", "cut"
    pallet.world = { x = state.windmill.x - 60, y = state.windmill.y + 30,
        direction = state.windmill.direction, spawnProgress = 1 }
    pallet.paper.status, pallet.remainingSheets, pallet.finishedSheets = "complete", 0, pallet.initialSheets
    state.inventory.inProcessPallets, state.inventory.finishedPallets = 1, 0

    local stock = state.inventory.stock
    stock.raw_press_plates, stock.negative_film, stock.plate_adhesive, stock.plate_chemistry = 1, 1, 1, 1
    stock.black_ink, stock.tympan_sheets, stock.press_wash = 2, 2, 2
    local plateStarted, plate = context.plateService.beginInHouse(state, job, 1)
    for _, action in ipairs({ "expose", "wash", "dry", "mount" }) do
        context.plateService.process(plate, action, 0.98)
    end
    check("windmill_plate_room_tracks_unique_plate_and_four_real_process_steps", plateStarted
        and plate.id == "PRESS-TEST-001-PLATE-01" and plate.status == "ready"
        and plate.mounted and plate.quality == 0.98 and job.press.actual.inHousePlates == 1)

    local loaded = context.windmill.load(state, pallet.id)
    context.pressScreen.enter(state)
    context.pressScreen.tab = "setup"
    local setupUiComplete = true
    for taskIndex, task in ipairs(context.windmill.setupTasks()) do
        local row, column = math.floor((taskIndex - 1) / 2), (taskIndex - 1) % 2
        local opened = context.pressScreen.mousepressed(state, 256 + column * 426, 235 + row * 112, 1)
        setupUiComplete = setupUiComplete and type(opened) == "table"
        local controls = PressSetupGames.controls(task)
        local controlWidth = math.floor((840 - 8 * (#controls - 1)) / #controls)
        for _, action in ipairs(setupSequences[task]) do
            local controlIndex
            for index, control in ipairs(controls) do
                if control[1] == action then controlIndex = index; break end
            end
            local controlX = 60 + (controlIndex - 1) * (controlWidth + 8) + controlWidth / 2
            local clicked = context.pressScreen.mousepressed(state, controlX, 598, 1)
            setupUiComplete = setupUiComplete and type(clicked) == "table"
        end
        setupUiComplete = setupUiComplete and context.windmill.ensure(state).setup[task] == 1
    end
    check("all_six_manual_based_setup_games_complete_through_the_visible_gui_buttons", setupUiComplete)
    context.pressScreen.enter(state)
    context.pressScreen.tab = "setup"
    local setupFooter = context.pressScreen.mousepressed(state, 480, 580, 1)
    check("setup_footer_routes_to_run_controls_with_specific_proof_feedback",
        setupFooter and context.pressScreen.tab == "run"
        and state.message == "Start the motor before proofing.")
    local readyBeforeMotor, beforeMotorReason = context.windmill.proofReadiness(state)
    local motorClick = context.pressScreen.mousepressed(state, 131, 367, 1)
    local readyBeforeFeeder, beforeFeederReason = context.windmill.proofReadiness(state)
    local feederClick = context.pressScreen.mousepressed(state, 303, 367, 1)
    local readyBeforeImpression, beforeImpressionReason = context.windmill.proofReadiness(state)
    local impressionClick = context.pressScreen.mousepressed(state, 475, 367, 1)
    local proofReady, proofReadyReason = context.windmill.proofReadiness(state)
    check("pull_proof_readiness_matches_motor_feeder_and_impression_controls",
        motorClick and feederClick and impressionClick
        and not readyBeforeMotor and beforeMotorReason == "Start the motor before proofing."
        and not readyBeforeFeeder and beforeFeederReason == "Turn the feeder on before proofing."
        and not readyBeforeImpression and beforeImpressionReason == "Turn impression on before proofing."
        and proofReady and proofReadyReason == "Ready to pull one proof sheet.")
    local proofClick = context.pressScreen.mousepressed(state, 303, 439, 1)
    local proofed, proofQuality = type(proofClick) == "table", context.windmill.ensure(state).proofQuality
    check("pull_proof_mouse_button_opens_the_proof_tab_and_consumes_one_sheet",
        proofed and context.pressScreen.tab == "proof" and proofQuality
        and context.windmill.ensure(state).counter == 1
        and context.windmill.ensure(state).feedRemaining == 1049)
    local beforeKeyboardProof = context.windmill.ensure(state).feedRemaining
    local keyboardProof = context.pressScreen.keypressed(state, "p")
    check("pull_proof_keyboard_path_uses_the_same_readiness_and_opens_proof",
        keyboardProof and context.pressScreen.tab == "proof"
        and context.windmill.ensure(state).feedRemaining == beforeKeyboardProof - 1)
    local verified = context.windmill.verifyArtwork(state)
    local approved = context.windmill.approveProof(state)
    local started = context.windmill.startProduction(state)
    local proofCounterBeforeRun = context.windmill.ensure(state).counter
    local proofDuringRun, proofDuringRunReason = context.windmill.takeProof(state)
    check("windmill_rejects_proof_pull_during_a_live_production_run",
        started and not proofDuringRun
        and proofDuringRunReason == "Stop production before pulling another proof."
        and context.windmill.ensure(state).status == "production"
        and context.windmill.ensure(state).counter == proofCounterBeforeRun)
    local feederPaused = context.windmill.control(state, "feeder")
    local counterBeforePause = context.windmill.ensure(state).counter
    local pauseChanged, pauseDurable = context.windmill.update(1, state)
    local feederResumed = context.windmill.control(state, "feeder")
    check("windmill_production_does_not_consume_sheets_with_a_required_control_off",
        feederPaused and feederResumed and not pauseChanged and not pauseDurable
        and context.windmill.ensure(state).status == "production"
        and context.windmill.ensure(state).counter == counterBeforePause)
    local finishedPass = context.windmill.update(10, state)
    local restartedPass, restartedPassReason = context.windmill.startProduction(state)
    check("windmill_completed_pass_cannot_restart_without_a_new_approved_workflow",
        finishedPass and not restartedPass
        and restartedPassReason == "Approve a proof before starting or resuming production."
        and context.windmill.ensure(state).status == "pass_complete")
    local washBeforeRejectedCleanup = stock.press_wash
    local washUnitsBeforeRejectedCleanup = job.press.actual.washUnits
    local historyBeforeRejectedCleanup = #pallet.press.passHistory
    local originalTransition = PalletState.transition
    PalletState.transition = function() return false, "forced transition rejection" end
    local rejectedCleanup, rejectedCleanupReason = context.windmill.cleanAndUnload(state)
    PalletState.transition = originalTransition
    check("windmill_cleanup_transition_rejection_is_atomic_and_retry_safe",
        not rejectedCleanup and rejectedCleanupReason == "forced transition rejection"
        and stock.press_wash == washBeforeRejectedCleanup
        and job.press.actual.washUnits == washUnitsBeforeRejectedCleanup
        and #pallet.press.passHistory == historyBeforeRejectedCleanup
        and context.windmill.ensure(state).status == "pass_complete")
    local unloaded = context.windmill.cleanAndUnload(state)
    check("windmill_full_operator_loop_runs_setup_proof_production_and_cleanup", loaded and proofed
        and proofQuality >= 0.82 and verified and approved and started and finishedPass and unloaded
        and pallet.press.status == "complete" and pallet.location == "press_output"
        and pallet.status == "printed" and job.press.actual.impressions >= 1001
        and pallet.finishedSheets == 1000 and pallet.press.availableSheets == 1000
        and state.inventory.inProcessPallets == 0 and state.inventory.finishedPallets == 1
        and job.press.actual.inkUnits == 1 and job.press.actual.tympanSheets == 1
        and job.press.actual.washUnits == 1)
    check("native_windmill_service_lockout_stops_motion_and_blocks_normal_controls",
        nativeServiceInterlockWorks(context, state))

    local multiState = context.State.new()
    multiState.money = 20000
    context.machineFleet.buy(multiState, "dealer", 3)
    local multiJob = context.jobs.createOffer({
        id = "PRESS-TEST-MULTI", company = "Two Color Test Client",
        sourceSize = { width = 10, height = 15 }, finishedSize = { width = 5, height = 7 },
        sheetCounts = { 1050 }, packaging = "flat", artworkKey = "ad-pizza",
        stockSpec = { suppliedBy = "client", grade = "cover", weight = 80,
            finish = "uncoated", color = "white", grain = "long",
            description = "80 lb uncoated cover" },
        press = { colors = 2, coverage = 0.4, artworkSize = { width = 4.25, height = 6.25 },
            colorSequence = { "Red", "Black" }, requestedCopies = { 1000 } },
    })
    multiJob.status, multiState.jobs.active = "in_production", { multiJob }
    local multiPallet = multiJob.pallets[1]
    multiPallet.location, multiPallet.status = "cutter_output", "cut"
    multiPallet.world = { x = multiState.windmill.x - 60, y = multiState.windmill.y + 30,
        direction = multiState.windmill.direction, spawnProgress = 1 }
    multiPallet.paper.status, multiPallet.remainingSheets = "complete", 0
    multiPallet.finishedSheets = multiPallet.initialSheets
    multiState.inventory.inProcessPallets, multiState.inventory.finishedPallets = 1, 0
    multiState.inventory.stock.color_ink, multiState.inventory.stock.black_ink = 1, 1
    multiState.inventory.stock.tympan_sheets, multiState.inventory.stock.press_wash = 2, 2
    for _, multiPlate in ipairs(context.plateService.ensureJob(multiJob)) do
        multiPlate.status, multiPlate.quality, multiPlate.mounted = "ready", 0.98, true
    end
    local function runColorPass()
        if not context.windmill.load(multiState, multiPallet.id) then return false end
        local target = context.windmill.ensure(multiState).targetSheets
        for _, task in ipairs(context.windmill.setupTasks()) do
            if not context.windmill.completeSetup(multiState, task, 0.98) then return false end
        end
        if not context.windmill.control(multiState, "motor") then return false end
        if not context.windmill.control(multiState, "feeder") then return false end
        if not context.windmill.control(multiState, "impression") then return false end
        if not context.windmill.takeProof(multiState) then return false end
        if not context.windmill.verifyArtwork(multiState) then return false end
        if not context.windmill.approveProof(multiState) then return false end
        if not context.windmill.startProduction(multiState) then return false end
        if not context.windmill.update(10, multiState) then return false end
        if not context.windmill.cleanAndUnload(multiState) then return false end
        return true, target
    end
    local firstColor, firstTarget = runColorPass()
    local initialDrying = firstColor and context.windmill.dryingStatus(multiState, multiJob, multiPallet)
    local heldDuringDrying = firstColor and multiPallet.press.status == "drying"
        and multiPallet.press.completedColors == 1 and multiPallet.press.availableSheets == 1025
        and multiPallet.finishedSheets == 1025
        and multiState.inventory.inProcessPallets == 1 and multiState.inventory.finishedPallets == 0
    context.businessCalendar.update(multiState,
        context.config.businessCalendar.secondsPerDay / 24)
    local halfwayDrying = context.windmill.dryingStatus(multiState, multiJob, multiPallet)
    local blockedHalfway = #context.windmill.candidates(multiState) == 0
    context.businessCalendar.update(multiState,
        context.config.businessCalendar.secondsPerDay / 24 + 0.01)
    local finishedDrying = context.windmill.dryingStatus(multiState, multiJob, multiPallet)
    local loadableAfterDrying = #context.windmill.candidates(multiState) == 1
    check("windmill_drying_progress_counts_down_and_unlocks_the_next_color",
        initialDrying and initialDrying.progress == 0 and initialDrying.remainingHours == 2
        and halfwayDrying and math.abs(halfwayDrying.progress - 0.5) < 0.001
        and math.abs(halfwayDrying.remainingHours - 1) < 0.001 and blockedHalfway
        and finishedDrying and finishedDrying.ready and finishedDrying.progress == 1
        and finishedDrying.remainingHours == 0 and loadableAfterDrying)
    local secondColor, secondTarget = runColorPass()
    check("windmill_multicolor_reserves_stock_between_passes_and_finishes_exact_order",
        firstColor and secondColor and firstTarget == 1025 and secondTarget == 1000
        and heldDuringDrying and multiPallet.press.status == "complete"
        and multiPallet.press.completedColors == 2 and #multiPallet.press.passHistory == 2
        and multiPallet.finishedSheets == 1000 and multiPallet.press.availableSheets == 1000
        and multiState.inventory.inProcessPallets == 0 and multiState.inventory.finishedPallets == 1)

    job.status = "completed"
    local scheduled = context.jobService.scheduleRepeatEmail(state, job)
    local pending = state.clientEmails.pending[1]
    check("completed_press_clients_can_request_repeat_print_work_by_email", scheduled and pending
        and pending.job.press and pending.job.press.colors == 1
        and pending.subject == "Request for another print job")

    local conditionBefore = context.machineFleet.condition(machine)
    machine.variables.gripperTiming, machine.variables.safetyCircuit = 30, 30
    local booked = context.machineMaintenance.requestWindmillTechnician(state)
    context.businessCalendar.update(state, context.config.businessCalendar.secondsPerDay)
    local serviced = context.machineMaintenance.updateWindmillTechnician(state)
    context.Technician.update(0, state, false)
    context.Technician.update(20, state, false)
    context.Technician.update(context.config.technician.serviceDuration, state, false)
    check("windmill_field_technician_restores_timing_lubrication_and_safety", booked and serviced
        and machine.variables.gripperTiming >= 88 and machine.variables.safetyCircuit >= 88
        and context.machineFleet.condition(machine) > conditionBefore - 25
        and #context.machineFleet.serviceInbox(state) == 1)
end

return Test
