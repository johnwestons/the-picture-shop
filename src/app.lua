local Assets = require("src.assets")
local AcceptanceHostBootstrap = require("src.acceptance_host_bootstrap")
local AssetErrorScreen = require("src.screens.asset_error_screen")
local BayDoor = require("src.bay_door")
local BusinessCalendar = require("src.business_calendar")
local CharacterAssets = require("src.character_assets")
local ComputerScreen = require("src.screens.computer_screen")
local Config = require("src.config")
local Controller = require("src.controller")
local CutterMaintenanceAuthority = require("src.cutter_maintenance_authority")
local CutterPlacement = require("src.cutter_placement")
local CutterZones = require("src.cutter_zones")
local Customer = require("src.customer")
local CryptoNative = require("src.net.crypto_native")
local DirectConnection = require("src.net.direct_connection")
local DirectCompositeTransport = require("src.net.transport_direct_composite")
local DirectScreen = require("src.screens.direct_screen")
local Hud = require("src.screens.hud")
local Input = require("src.input")
local Ui = require("src.screens.ui")
local JobOfferScreen = require("src.screens.job_offer_screen")
local LanScreen = require("src.screens.lan_screen")
local PalletWorkOrderScreen = require("src.screens.pallet_work_order_screen")
local JobService = require("src.job_service")
local Jobs = require("src.jobs")
local LanDiscovery = require("src.net.lan_discovery")
local LanReconnect = require("src.net.lan_reconnect")
local Machine = require("src.machine")
local MachineFleet = require("src.machine_fleet")
local MachineResource = require("src.machine_resource_id")
local MachineMaintenance = require("src.machine_maintenance")
local MachineRelocationAuthority = require("src.machine_relocation_authority")
local MobileControls = require("src.mobile_controls")
local MultiplayerHud = require("src.screens.multiplayer_hud")
local MultiplayerSession = require("src.net.session")
local Navigation = require("src.navigation")
local OptionsScreen = require("src.screens.options_screen")
local Procurement = require("src.procurement")
local Wrapper = require("src.wrapper")
local WrapperMaintenanceAuthority = require("src.wrapper_maintenance_authority")
local MachineScreen = require("src.screens.machine_screen")
local PalletJack = require("src.pallet_jack")
local PalletState = require("src.pallet_state")
local PalletLogistics = require("src.pallet_logistics")
local PaperWork = require("src.paper_work")
local PlateService = require("src.plate_service")
local PressSetupGames = require("src.press_setup_games")
local PressScreen = require("src.screens.press_screen")
local Receiving = require("src.receiving")
local Save = require("src.save")
local SaveSchema = require("src.save_schema")
local Settings = require("src.settings")
local Shop = require("src.shop")
local Smoke = require("src.smoke")
local SpriteMotionLab = require("src.screens.sprite_motion_lab")
local State = require("src.state")
local TitleScreen = require("src.screens.title_screen")
local Technician = require("src.technician")
local Truck = require("src.truck")
local TruckAuthority = require("src.truck_authority")
local TruckInventoryScreen = require("src.screens.truck_inventory_screen")
local VendorScreen = require("src.screens.vendor_screen")
local VendorAuthority = require("src.vendor_authority")
local Viewport = require("src.viewport")
local World = require("src.world")
local WorldRenderer = require("src.world_renderer")
local Windmill = require("src.windmill")
local WindmillPlacement = require("src.windmill_placement")
local WorkPhone = require("src.work_phone")
local PhoneAuthority = require("src.phone_authority")
local OfficeAuthority = require("src.office_authority")
local WorkPhoneScreen = require("src.screens.work_phone_screen")
local WorkshopAuthority = require("src.workshop_authority")
local WorkshopRemoteScreen = require("src.screens.workshop_remote_screen")
local Forklift = require("src.forklift")
local WarehouseAuthority = require("src.warehouse_authority")
local WarehouseControls = require("src.screens.warehouse_controls")

local App = {}
local state = State.new()
local acceptanceHostPlan = nil
local acceptanceHostRelocationSignature = nil
local spriteLabActive = false
local mobileControls = nil
local controller = nil
local multiplayer = MultiplayerSession.new()
local lanDiscovery = LanDiscovery.new()
local lanReconnect = LanReconnect.new()
local lanReconnectArmed = false
local workshopAuthority = nil
local localWorkshopLease = nil
local localWorkshopRequestId = 0
local activeCutterRemote = nil
local cutterMaintenanceAuthority = nil
local activeWrapperRemote = nil
local wrapperMaintenanceAuthority = nil
local activeWindmillRemote = nil
local machineRemoteSessions = {}
local directConnection = nil
local pendingDirectSession = nil
local directHostComposite = nil
local directHostInvitationGeneration = 0
local lastDirectSlot = 1
local serviceNetworkBeforeMachine
local warehouseControls
local warehousePendingIntent
local warehouseSaveClock = 0

MachineFleet.setSaleGuard(function(currentState, item)
    local placementKey = item and MachineFleet.definitions[item.modelId]
        and MachineFleet.definitions[item.modelId].placementKey
    if item and item.status == "installed" and placementKey
        and currentState and currentState[placementKey]
        and currentState[placementKey].moving
    then
        return false, "Place the moving machine before listing it for sale."
    end
    local windmillLeaseActive = workshopAuthority
        and workshopAuthority:leaseForResource("windmill") ~= nil
    if windmillLeaseActive and item and item.modelId == "heidelberg_10x15"
        and item.status == "installed"
    then
        return false, "Close the active Windmill console before listing the press for sale."
    end
    local cutterLeaseActive = workshopAuthority
        and workshopAuthority:leaseForResource("cutter") ~= nil
    local wrapperLeaseActive = workshopAuthority
        and workshopAuthority:leaseForResource("skid_wrapper") ~= nil
    if wrapperLeaseActive and item and item.modelId == "skid_wrapper"
        and item.status == "installed"
    then
        return false, "Close the active skid-wrapper console before listing it for sale."
    end
    return Machine.validateSale(item, cutterLeaseActive)
end)

local function isAndroidPlatform()
    return love and love.system and love.system.getOS
        and love.system.getOS() == "Android"
end

local function cameraTransformsUi()
    return App.mobileCamera and App.mobileCamera:isEnabled() and state.screen ~= "world"
end

local function cameraViewKey()
    if state.screen == "machine" then return "machine:" .. tostring(state.machineType or "unknown") end
    return tostring(state.screen)
end

local function toPointerCoordinates(x, y)
    local gameX, gameY = Viewport.toGame(x, y, Config.baseWidth, Config.baseHeight)
    if cameraTransformsUi() then return App.mobileCamera:screenToWorld(gameX, gameY) end
    return gameX, gameY
end

local function saveCurrent()
    if multiplayer:isClient() then return false end
    if not state.activeSlot then return false end
    local saved = Save.save(state.activeSlot, state, World.snapshot())
    if saved and multiplayer:isHost() then multiplayer:markShopDirty(true) end
    return saved
end

local function startGame(payload, mode)
    local applied, windmillSanitized = State.applyLocalSave(state, payload)
    if not applied then return false, "That shop save could not be opened safely." end
    World.load(payload.player)
    Machine.reset()
    Wrapper.clearInstances()
    Windmill.resetNetworkRuntime()
    activeCutterRemote = nil
    activeWrapperRemote = nil
    activeWindmillRemote = nil
    machineRemoteSessions = {}
    if (mode == "new" or windmillSanitized) and not saveCurrent() then
        return false, mode == "new"
            and "This device could not create the new shop save."
            or "This device could not save the safely stopped Windmill state."
    end
    if payload.recovered then
        state.message = "Recovered this shop from its last valid " .. tostring(payload.recoverySource) .. " copy."
    end
    return true
end

local returnToTitle
local openLocalPlay
local openDirectPlay
local openDirectInvite
local closeDirectConnection
local closeDirectHostComposite
local syncMobileKeyboard
local openOptions

local function exactArguments(arguments, required)
    if type(arguments) ~= "table" then return false end
    local allowed = {}
    for _, name in ipairs(required or {}) do allowed[name] = true end
    for key in pairs(arguments) do
        if type(key) ~= "string" or not allowed[key] then return false end
    end
    for _, name in ipairs(required or {}) do
        if arguments[name] == nil then return false end
    end
    return true
end

local function machineRelocationActive()
    return state.cutter and state.cutter.moving
        or state.wrapper and state.wrapper.moving
        or state.windmill and state.windmill.moving
end

local function customerView(offer)
    local rows = {}
    for _, row in ipairs((offer.quote and offer.quote.pallets) or {}) do
        local projected = {
            number = math.floor(tonumber(row.number) or (#rows + 1)),
            sheetCount = math.floor(tonumber(row.sheetCount) or 0),
            requiredLifts = math.floor(tonumber(row.requiredLifts) or 0),
        }
        if offer.press then
            projected.requestedCopies = math.floor(tonumber(row.requestedCopies) or 0)
            projected.spoilageAllowance = math.floor(tonumber(row.spoilageAllowance)
                or math.max(0, projected.sheetCount - projected.requestedCopies))
        else
            projected.price = math.floor(tonumber(row.price) or 0)
        end
        rows[#rows + 1] = projected
    end
    local stock = offer.stockSpec and offer.stockSpec.description
        or offer.details and offer.details.stockDescription or "Customer-supplied paper"
    local artwork = offer.artwork or {}
    return {
        jobId = tostring(offer.id),
        company = tostring(offer.company),
        sourceSize = { width = offer.sourceSize.width, height = offer.sourceSize.height },
        finishedSize = { width = offer.finishedSize.width, height = offer.finishedSize.height },
        stock = tostring(stock),
        packaging = offer.packaging == "boxed" and "boxed" or "flat",
        delivery = tostring(JobService.deliverySummary(offer)),
        artworkKey = tostring(artwork.key or offer.artworkKey or "flower"),
        artworkName = tostring(artwork.displayName or artwork.fileName
            or offer.artworkKey or "Client artwork"),
        printJob = offer.press ~= nil,
        colorCount = offer.press and offer.press.colors or nil,
        colorSequence = offer.press and table.concat(offer.press.colorSequence or {}, " then ") or nil,
        quoteRows = rows,
        recommendedTotal = math.floor(tonumber(offer.quote and
            (offer.quote.recommendedPrice or offer.quote.totalPrice)) or 0),
    }
end

local function wrapperPalletView()
    local pallets = {}
    for _, item in ipairs(Wrapper.nearbyPallets(state)) do
        pallets[#pallets + 1] = {
            palletId = tostring(item.pallet.id),
            jobLabel = tostring((item.job.company or "Client") .. " · " .. item.job.id),
            packaging = item.pallet.packaging == "boxed" and "boxed" or "flat",
            distance = math.sqrt(math.max(0, tonumber(item.distance) or 0)),
        }
        if #pallets >= 5 then break end
    end
    return pallets
end

local function wrapperView(detailed)
    local runtime = Wrapper.snapshot()
    local view = {
        step = runtime.step,
        progress = runtime.progress,
        cycleTime = runtime.cycleTime,
        pallets = wrapperPalletView(),
        selectedPalletId = runtime.selectedPalletId,
        palletId = runtime.palletId,
    }
    if detailed ~= false then
        view.plasticWrapRolls = math.max(0,
            math.floor(tonumber(state.inventory.plasticWrapRolls) or 0))
        view.plasticWrapUses = math.max(0,
            math.floor(tonumber(state.inventory.plasticWrapUses) or 0))
    end
    return view
end

local function wrapperSnapshotView()
    if wrapperMaintenanceAuthority then
        return wrapperMaintenanceAuthority.view(activeWrapperRemote, false)
    end
    return wrapperView(false)
end

local function cutterView(includeCandidates)
    return Machine.networkView(state, includeCandidates == true)
end

local function cutterNoArguments(arguments)
    if not exactArguments(arguments, {}) then
        return nil, "invalid_arguments", "That cutter action takes no additional data."
    end
    return {}
end

local function performCutterAction(player, operation, durable)
    local allowed, code, accessMessage = World.validateNetworkWorkshopAccess(
        player, state, state._activeWorkshopResourceId or "cutter")
    if not allowed then
        return false, code, accessMessage, cutterView(true)
    end
    local previousMessage = state.message
    local accepted = operation() == true
    local resultMessage = state.message
    if resultMessage == nil or resultMessage == previousMessage then
        resultMessage = accepted and "Cutter action completed."
            or "The cutter is not ready for that action."
    end
    if accepted and durable then saveCurrent() end
    return accepted, accepted and "completed" or "machine_blocked",
        tostring(resultMessage or (accepted and "Cutter action completed."
            or "The cutter rejected that action.")), cutterView(true)
end

local function findActiveJob(jobId)
    for _, job in ipairs((state.jobs and state.jobs.active) or {}) do
        if job.id == jobId then return job end
    end
end

local UINT32_MAX = 4294967295

local function uint32(value)
    return math.max(0, math.min(UINT32_MAX, math.floor(tonumber(value) or 0)))
end

local function windmillRuntimeClock()
    if love and love.timer and love.timer.getTime then return love.timer.getTime() end
    return os.clock()
end

local function windmillPlateMarkerPermille()
    return math.max(0, math.min(1000,
        math.floor(((math.sin(windmillRuntimeClock() * 2.2) + 1) * 500) + 0.5)))
end

local function findPlateById(plateId)
    for _, job in ipairs((state.jobs and state.jobs.active) or {}) do
        if job.press then
            for colorIndex, plate in ipairs(PlateService.ensureJob(job)) do
                if plate.id == plateId then return job, plate, colorIndex end
            end
        end
    end
end

local function windmillView(session)
    local process, job = Windmill.current(state)
    local setupPermille = {}
    for index, task in ipairs(Windmill.setupTasks()) do
        setupPermille[index] = math.max(0, math.min(1000,
            math.floor((tonumber(process.setup[task]) or 0) * 1000 + 0.5)))
    end
    local candidates = {}
    for _, item in ipairs(Windmill.candidates(state)) do
        candidates[#candidates + 1] = {
            palletId = tostring(item.pallet.id),
            colorIndex = math.max(1, math.min(4, math.floor(tonumber(item.color) or 1))),
        }
        if #candidates >= 3 then break end
    end
    local view = {
        runtimeRevision = uint32(Windmill.networkRuntimeRevision()),
        status = tostring(process.status),
        speed = math.max(1000, math.min(5500, math.floor(tonumber(process.speed) or 3000))),
        motor = process.motor == true,
        feeder = process.feeder == true,
        impression = process.impression == true,
        emergency = process.emergency == true,
        counter = uint32(process.counter),
        goodSheets = uint32(process.goodSheets),
        spoilage = uint32(process.spoilage),
        targetSheets = uint32(process.targetSheets),
        feedStart = uint32(process.feedStart),
        feedRemaining = uint32(process.feedRemaining),
        proofApproved = process.proofApproved == true,
        artworkVerified = process.artworkVerified == true,
        setupPermille = setupPermille,
        candidates = candidates,
        serviceStep = "idle",
        servicePermille = 0,
        plateMarkerPermille = windmillPlateMarkerPermille(),
    }
    if process.jobId then view.jobId = tostring(process.jobId) end
    if process.palletId then view.palletId = tostring(process.palletId) end
    if process.colorIndex then
        view.colorIndex = math.max(1, math.min(4, math.floor(process.colorIndex)))
    end
    if job and job.press then
        view.colorCount = math.max(1, math.min(4,
            math.floor(tonumber(job.press.colors) or 1)))
    end
    if process.proofQuality ~= nil then
        view.proofPermille = math.max(0, math.min(1000,
            math.floor((tonumber(process.proofQuality) or 0) * 1000 + 0.5)))
    end
    local warning = process.warning or Windmill.failureSummary(state)
    if warning then view.warning = tostring(warning) end
    if type(session) == "table" then
        if session.setupGame and session.setupTask then
            view.warning = nil
            view.setupTask = session.setupTask
            view.setupSummary = session.setupTask == "feeder" and PressSetupGames.instruction(session.setupGame)
                or PressSetupGames.summary(session.setupGame)
            view.setupVisual = require("src.press_setup_view").encode(session.setupGame)
        end
        if session.maintenance then
            view.warning = nil
            local step = math.max(1, math.floor(tonumber(session.lockoutStep) or 1))
            if step == 1 then view.serviceStep = "lockout_disconnect"
            elseif step == 2 then view.serviceStep = "lockout_key"
            elseif step == 3 then view.serviceStep = "lockout_tag"
            else view.serviceStep = "task" end
            if step <= 3 then
                view.servicePermille = (step - 1) * 80
            else
                view.servicePermille = math.max(0, math.min(1000,
                    math.floor(250 + MachineMaintenance.progress(session.maintenance) * 750 + 0.5)))
                local task = MachineMaintenance.activeTask(session.maintenance)
                if task then view.serviceTask = tostring(task.label or task.id) end
            end
        end
    end
    return view
end

local function windmillNoArguments(arguments)
    if not exactArguments(arguments, {}) then
        return nil, "invalid_arguments", "That Windmill action takes no additional data."
    end
    return {}
end

local function windmillTokenArguments(field, invalidCode, invalidMessage)
    return function(arguments)
        local value = type(arguments) == "table" and arguments[field]
        if not exactArguments(arguments, { field }) or type(value) ~= "string"
            or #value < 1 or #value > 64
            or not value:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
        then
            return nil, invalidCode, invalidMessage
        end
        return { [field] = value }
    end
end

local function performWindmillAction(player, lease, operation, durable, allowDuringService)
    local allowed, code, accessMessage = World.validateNetworkWorkshopAccess(
        player, state, state._activeWorkshopResourceId or "windmill")
    if not allowed then
        return false, code, accessMessage, windmillView(lease and lease.private)
    end
    local session = lease and lease.private
    if session and session.maintenance and not allowDuringService then
        return false, "service_active",
            "Finish or release the active Windmill service lockout before operating the press.",
            windmillView(session)
    end
    local previousMessage = state.message
    local accepted, detail = operation()
    accepted = accepted == true
    local resultMessage
    if type(detail) == "string" then resultMessage = detail end
    if not resultMessage and state.message ~= nil and state.message ~= previousMessage then
        resultMessage = tostring(state.message)
    end
    if not resultMessage then
        resultMessage = accepted and "Windmill action completed."
            or "The Windmill is not ready for that action."
    end
    state.message = resultMessage
    if accepted and durable then saveCurrent() end
    return accepted, accepted and "completed" or "machine_blocked",
        resultMessage, windmillView(lease and lease.private)
end

local function windmillSimpleCommand(operation, durable, allowDuringService)
    return {
        normalize = windmillNoArguments,
        perform = function(lease, player)
            return performWindmillAction(player, lease,
                function() return operation(state) end, durable ~= false,
                allowDuringService == true)
        end,
    }
end

local function createWindmillCommands()
    local commands = {
        load_pallet = {
            normalize = windmillTokenArguments("palletId", "invalid_pallet",
                "Choose a valid nearby print pallet."),
            perform = function(lease, player, arguments)
                return performWindmillAction(player, lease,
                    function() return Windmill.load(state, arguments.palletId) end, true)
            end,
        },
        toggle_motor = windmillSimpleCommand(function(targetState)
            return Windmill.control(targetState, "motor")
        end),
        toggle_feeder = windmillSimpleCommand(function(targetState)
            return Windmill.control(targetState, "feeder")
        end),
        toggle_impression = windmillSimpleCommand(function(targetState)
            return Windmill.control(targetState, "impression")
        end),
        speed_up = windmillSimpleCommand(function(targetState)
            return Windmill.control(targetState, "speed_up")
        end),
        speed_down = windmillSimpleCommand(function(targetState)
            return Windmill.control(targetState, "speed_down")
        end),
        emergency_stop = windmillSimpleCommand(function(targetState)
            return Windmill.control(targetState, "emergency")
        end, nil, true),
        reset_safety = windmillSimpleCommand(function(targetState)
            return Windmill.control(targetState, "reset")
        end),
        take_proof = windmillSimpleCommand(Windmill.takeProof),
        verify_artwork = windmillSimpleCommand(Windmill.verifyArtwork),
        approve_proof = windmillSimpleCommand(Windmill.approveProof),
        start_run = windmillSimpleCommand(Windmill.startProduction),
        stop_run = windmillSimpleCommand(Windmill.stopProduction),
        clean_unload = windmillSimpleCommand(Windmill.cleanAndUnload),
        order_plate = {
            normalize = windmillTokenArguments("plateId", "invalid_plate",
                "Choose a valid press plate."),
            perform = function(lease, player, arguments)
                return performWindmillAction(player, lease, function()
                    local job, plate, colorIndex = findPlateById(arguments.plateId)
                    if not job or not plate then return false, "That press plate no longer exists." end
                    local accepted, result = PlateService.order(state, job, colorIndex)
                    if not accepted then return false, result end
                    Windmill.bumpNetworkRevision()
                    return true, "Plate ordered from the trade platemaker."
                end, true)
            end,
        },
        begin_plate = {
            normalize = windmillTokenArguments("plateId", "invalid_plate",
                "Choose a valid press plate."),
            perform = function(lease, player, arguments)
                return performWindmillAction(player, lease, function()
                    local job, plate, colorIndex = findPlateById(arguments.plateId)
                    if not job or not plate then return false, "That press plate no longer exists." end
                    local accepted, result = PlateService.beginInHouse(state, job, colorIndex)
                    if not accepted then return false, result end
                    Windmill.bumpNetworkRevision()
                    return true, "In-house platemaking started."
                end, true)
            end,
        },
        process_plate = {
            normalize = windmillTokenArguments("plateId", "invalid_plate",
                "Choose a valid press plate."),
            perform = function(lease, player, arguments)
                return performWindmillAction(player, lease, function()
                    local _, plate = findPlateById(arguments.plateId)
                    if not plate then return false, "That press plate no longer exists." end
                    local action = PlateService.actionFor(plate)
                    if not action then return false, "That plate is already complete." end
                    local marker = windmillPlateMarkerPermille()
                    local accuracy = math.max(0, math.min(1,
                        1 - math.abs(marker - 670) / 330))
                    local accepted, result = PlateService.process(plate, action, accuracy)
                    if not accepted then return false, result end
                    Windmill.bumpNetworkRevision()
                    return true, string.format("%s step completed at %d%% accuracy.",
                        action:gsub("^%l", string.upper), math.floor(accuracy * 100 + 0.5))
                end, true)
            end,
        },
    }

    local setupTasks = {}
    for _, task in ipairs(Windmill.setupTasks()) do setupTasks[task] = true end
    commands.begin_setup = {
        normalize = function(arguments)
            local task = type(arguments) == "table" and arguments.setupTask
            if not exactArguments(arguments, { "setupTask" }) or not setupTasks[task] then
                return nil, "invalid_setup", "Choose one of the six Windmill setup checks."
            end
            return { setupTask = task }
        end,
        perform = function(lease, player, arguments)
            return performWindmillAction(player, lease, function()
                local process, job = Windmill.current(state)
                if not process.palletId or not job then
                    return false, "Load a print-ready pallet before setup."
                end
                local session = lease.private
                if session.setupGame then return false, "Finish or cancel the open setup check first." end
                session.setupTask = arguments.setupTask
                session.setupGame = PressSetupGames.new(arguments.setupTask, job)
                Windmill.bumpNetworkRevision()
                return true, arguments.setupTask:upper() .. " setup check opened."
            end, false)
        end,
    }

    local setupActions = {}
    for _, task in ipairs(Windmill.setupTasks()) do
        for _, control in ipairs(PressSetupGames.controls(task)) do
            setupActions[control[1]] = true
        end
    end
    commands.setup_action = {
        normalize = function(arguments)
            local action = type(arguments) == "table" and arguments.setupAction
            if not exactArguments(arguments, { "setupAction" }) or not setupActions[action] then
                return nil, "invalid_setup_action", "Choose a valid setup control."
            end
            return { setupAction = action }
        end,
        perform = function(lease, player, arguments)
            return performWindmillAction(player, lease, function()
                local session = lease.private
                local game, task = session.setupGame, session.setupTask
                if not game or not task then return false, "Open a setup check first." end
                local valid = false
                for _, control in ipairs(PressSetupGames.controls(task)) do
                    if control[1] == arguments.setupAction then valid = true; break end
                end
                if not valid then return false, "That control does not belong to this setup check." end
                local complete, score = PressSetupGames.apply(game, arguments.setupAction)
                if complete then
                    local accepted, result = Windmill.completeSetup(state, task, score)
                    session.setupGame, session.setupTask = nil, nil
                    if not accepted then return false, result end
                    saveCurrent()
                    return true, task:upper() .. " setup check completed."
                end
                Windmill.bumpNetworkRevision()
                return true, PressSetupGames.summary(game)
            end, false)
        end,
    }
    commands.cancel_setup = {
        normalize = windmillNoArguments,
        perform = function(lease, player)
            return performWindmillAction(player, lease, function()
                local session = lease.private
                if not session or not session.setupGame then
                    return false, "No setup check is open."
                end
                session.setupGame, session.setupTask = nil, nil
                Windmill.bumpNetworkRevision()
                return true, "Setup check cancelled."
            end, false)
        end,
    }

    commands.begin_service = {
        normalize = windmillNoArguments,
        perform = function(lease, player)
            return performWindmillAction(player, lease, function()
                local process = Windmill.ensure(state)
                if process.status ~= "idle" or process.palletId then
                    return false, "Unload the Windmill and return it to idle before service."
                end
                if lease.private.maintenance then return false, "Windmill service is already open." end
                local item = MachineFleet.installed(state, "heidelberg_10x15")
                if not item then return false, "No Heidelberg Windmill is installed." end
                local maintenance, errorMessage = MachineMaintenance.begin(state, item.id)
                if not maintenance then return false, errorMessage end
                Windmill.releaseOperator(state)
                lease.private.setupGame, lease.private.setupTask = nil, nil
                lease.private.maintenance, lease.private.lockoutStep = maintenance, 1
                Windmill.bumpNetworkRevision()
                return true, "Windmill service opened. Begin the lockout sequence."
            end, true)
        end,
    }
    commands.service_lockout = {
        normalize = windmillNoArguments,
        perform = function(lease, player)
            return performWindmillAction(player, lease, function()
                local session = lease.private
                if not session.maintenance then return false, "Begin Windmill service first." end
                local step = math.max(1, math.floor(tonumber(session.lockoutStep) or 1))
                if step > 3 then return false, "The service lockout is already complete." end
                local labels = { "Disconnect opened.", "Lockout key secured.", "Service tag attached." }
                session.lockoutStep = step + 1
                Windmill.bumpNetworkRevision()
                return true, labels[step]
            end, false, true)
        end,
    }
    commands.service_task = {
        normalize = windmillNoArguments,
        perform = function(lease, player)
            return performWindmillAction(player, lease, function()
                local session, maintenance = lease.private, lease.private.maintenance
                if not maintenance then return false, "Begin Windmill service first." end
                if (session.lockoutStep or 1) <= 3 then
                    return false, "Complete disconnect, key, and tag lockout first."
                end
                local task = MachineMaintenance.activeTask(maintenance)
                if not task then return false, "No maintenance task is ready." end
                if not MachineMaintenance.submitTask(maintenance, task.id, 0.92) then
                    return false, "That maintenance task could not be completed."
                end
                if maintenance.finished then
                    local accepted, result = MachineMaintenance.commit(state, maintenance)
                    if not accepted then
                        MachineMaintenance.rollbackLastTask(maintenance, task.id)
                        return false, result
                    end
                    session.maintenance, session.lockoutStep = nil, nil
                    Windmill.bumpNetworkRevision()
                    saveCurrent()
                    return true, "Windmill maintenance completed and returned to service."
                end
                Windmill.bumpNetworkRevision()
                return true, tostring(task.label or task.id) .. " completed."
            end, false, true)
        end,
    }
    commands.book_technician = windmillSimpleCommand(function(targetState)
        local accepted, result = MachineMaintenance.requestWindmillTechnician(targetState)
        if accepted then Windmill.bumpNetworkRevision() end
        return accepted, accepted and "Windmill field technician booked for the next business day." or result
    end)
    return commands
end

local function withWorkshopUnit(base, machineId, resourceId, callback)
    local previousResource = state._activeWorkshopResourceId
    state._activeWorkshopResourceId = resourceId
    if base == "cutter" then Machine.select(machineId, state)
    elseif base == "skid_wrapper" then Wrapper.select(machineId, state) end
    local results = { pcall(function()
        return MachineFleet.withUnit(state, machineId, callback)
    end) }
    state._activeWorkshopResourceId = previousResource
    if base == "cutter" then Machine.select(state._localWorkshopMachineId, state)
    elseif base == "skid_wrapper" then Wrapper.select(state._localWorkshopMachineId, state) end
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2)
end

local function registerInstalledMachineResources(authority)
    if not authority then return end
    for _, base in ipairs({ "cutter", "skid_wrapper", "windmill" }) do
        for _, unit in ipairs(MachineFleet.installedUnits(state, MachineResource.model(base))) do
            local machineId = unit.id
            local resourceId = MachineResource.forUnit(base, machineId)
            if not authority.resources[resourceId] then
                local source = authority.resources[base]
                local spec = {}
                for key, value in pairs(source) do spec[key] = value end
                for _, callbackName in ipairs({ "canAcquire", "onAcquire", "onRelease" }) do
                    local callback = source[callbackName]
                    if callback then
                        spec[callbackName] = function(...)
                            local arguments = { ... }
                            local count = select("#", ...)
                            return withWorkshopUnit(base, machineId, resourceId, function()
                                return callback(unpack(arguments, 1, count))
                            end)
                        end
                    end
                end
                spec.commands = {}
                for action, command in pairs(source.commands or {}) do
                    local perform = command.perform
                    local wrapped = {}
                    for key, value in pairs(command) do wrapped[key] = value end
                    wrapped.perform = function(...)
                        local arguments = { ... }
                        local count = select("#", ...)
                        return withWorkshopUnit(base, machineId, resourceId, function()
                            return perform(unpack(arguments, 1, count))
                        end)
                    end
                    spec.commands[action] = wrapped
                end
                assert(authority:registerResource(resourceId, spec))
            end
        end
    end
end

local function createWorkshopAuthority()
    cutterMaintenanceAuthority = CutterMaintenanceAuthority.create({
        state = state,
        baseView = cutterView,
        validateAccess = function(player)
            return World.validateNetworkWorkshopAccess(player, state,
                state._activeWorkshopResourceId or "cutter")
        end,
        save = saveCurrent,
        machineReady = function()
            if Machine.loaded or Machine.step ~= "idle" then
                return false, "Unload the cutter and return it to idle before beginning maintenance."
            end
            return true
        end,
    })
    wrapperMaintenanceAuthority = WrapperMaintenanceAuthority.create({
        state = state,
        baseView = wrapperView,
        validateAccess = function(player)
            return World.validateNetworkWorkshopAccess(player, state,
                state._activeWorkshopResourceId or "skid_wrapper")
        end,
        save = saveCurrent,
        machineReady = function()
            if Wrapper.isActive() then
                return false, "machine_busy",
                    "Wait for the wrapping cycle to finish before beginning maintenance."
            end
            if Wrapper.nearbyPallet(state) then
                return false, "turntable_occupied",
                    "Move every eligible pallet away from the wrapper before beginning maintenance."
            end
            return true
        end,
        resetRuntime = function()
            return Wrapper.reset(state)
        end,
    })
    local authority = WorkshopAuthority.new({
        leaseTimeout = 12,
        resources = {
            reception_customer = {
                canAcquire = function(player)
                    return World.validateNetworkWorkshopAccess(
                        player, state, "reception_customer")
                end,
                onAcquire = function(_, player)
                    if player.id == 1 then
                        return true, "acquired", "Reception reserved for the host player."
                    end
                    local offer, errors = JobService.createNextOffer(state, os.time())
                    if not offer then
                        return false, "offer_failed",
                            "Could not prepare the customer job: " .. table.concat(errors or {}, "; ")
                    end
                    if not World.customer:beginReview() then
                        return false, "customer_unavailable", "That customer is no longer waiting."
                    end
                    return true, "acquired", "Customer conversation opened.",
                        customerView(offer), { offer = offer, remote = true, resolved = false }
                end,
                onRelease = function(lease)
                    if lease.private and lease.private.remote and not lease.private.resolved then
                        World.customer:cancelReview()
                    end
                    return true
                end,
                commands = {
                    request_details = {
                        normalize = function(arguments)
                            if not exactArguments(arguments, {}) then
                                return nil, "invalid_arguments", "Request details takes no additional data."
                            end
                            return {}
                        end,
                        perform = function(lease)
                            local offer = lease.private and lease.private.offer
                            if not offer then return false, "offer_missing", "The customer paperwork expired." end
                            local succeeded, result = JobService.requestEstimateDetails(
                                state, offer, os.time())
                            if not succeeded then
                                return false, "details_failed", "Could not request the details: " .. tostring(result)
                            end
                            lease.private.resolved = true
                            World.resolveCustomer("accepted", state)
                            saveCurrent()
                            return true, "details_requested",
                                offer.company .. " will email the written job details."
                        end,
                    },
                },
            },
            vendor = VendorAuthority.resource({
                state = state,
                world = World,
                save = saveCurrent,
            }),
            truck = TruckAuthority.resource({
                state = state,
                world = World,
                save = saveCurrent,
            }),
            work_phone = PhoneAuthority.resource({ state = state, world = World, save = saveCurrent }),
            office_computer = {
                canAcquire = function(player)
                    return World.validateNetworkWorkshopAccess(player, state, "office_computer")
                end,
                onAcquire = function()
                    return true, "acquired", "Office computer connected.", {}
                end,
                commands = {
                    office_action = OfficeAuthority.command({ state = state, world = World, save = saveCurrent,
                        warehouseEnabled = Config.warehouse.enabled,
                        warehouseFirstStorageOnly = Config.warehouse.firstStorageOnly }),
                    request_pickup = {
                        normalize = function(arguments)
                            local jobId = type(arguments) == "table" and arguments.jobId
                            if not exactArguments(arguments, { "jobId" })
                                or type(jobId) ~= "string" or #jobId < 1 or #jobId > 64
                                or not jobId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                            then
                                return nil, "invalid_job", "Choose a valid active job."
                            end
                            return { jobId = jobId }
                        end,
                        perform = function(_, _, arguments)
                            local job = findActiveJob(arguments.jobId)
                            if not job then return false, "job_not_found", "That active job no longer exists." end
                            local succeeded, result = JobService.requestPickup(state, job, os.time())
                            if not succeeded then
                                return false, "pickup_blocked", "Could not request pickup: " .. tostring(result)
                            end
                            saveCurrent()
                            return true, "pickup_requested", job.id .. " is awaiting customer pickup.", {}
                        end,
                    },
                },
            },
            cutter = {
                canAcquire = function(player)
                    return World.validateNetworkWorkshopAccess(player, state,
                        state._activeWorkshopResourceId or "cutter")
                end,
                onAcquire = function()
                    Machine.open(state)
                    local session = CutterMaintenanceAuthority.newSession()
                    activeCutterRemote = session
                    machineRemoteSessions[state._activeWorkshopResourceId or "cutter"] = session
                    return true, "acquired", "Cutter console connected.",
                        cutterMaintenanceAuthority.view(session, true), session
                end,
                onRelease = function(lease)
                    local changed = Machine.releaseOperator(state)
                    machineRemoteSessions[state._activeWorkshopResourceId or "cutter"] = nil
                    if activeCutterRemote == (lease and lease.private) then
                        activeCutterRemote = nil
                    end
                    if changed then saveCurrent() end
                    return true, "released", "Cutter controls released safely."
                end,
                commands = cutterMaintenanceAuthority.withProductionCommands({
                    load_pallet = {
                        normalize = function(arguments)
                            local palletId = type(arguments) == "table" and arguments.palletId
                            if not exactArguments(arguments, { "palletId" })
                                or type(palletId) ~= "string" or #palletId < 1 or #palletId > 64
                                or not palletId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                            then
                                return nil, "invalid_pallet", "Choose a valid nearby pallet."
                            end
                            return { palletId = palletId }
                        end,
                        perform = function(_, player, arguments)
                            return performCutterAction(player,
                                function() return Machine.load(state, arguments.palletId) end, true)
                        end,
                    },
                    load_stock = {
                        normalize = cutterNoArguments,
                        perform = function(_, player)
                            return performCutterAction(player,
                                function() return Machine.load(state, "__generic_stock__") end, false)
                        end,
                    },
                    select_program = {
                        normalize = function(arguments)
                            local index = type(arguments) == "table" and arguments.programIndex
                            if not exactArguments(arguments, { "programIndex" })
                                or type(index) ~= "number" or index ~= math.floor(index)
                                or index < 1 or index > 4
                            then
                                return nil, "invalid_program", "Choose cutter program 1 through 4."
                            end
                            return { programIndex = index }
                        end,
                        perform = function(_, player, arguments)
                            return performCutterAction(player, function()
                                return Machine.selectProgram(arguments.programIndex, state)
                            end, false)
                        end,
                    },
                    set_gauge = {
                        normalize = function(arguments)
                            local gauge = type(arguments) == "table" and arguments.gaugeCentiInch
                            if not exactArguments(arguments, { "gaugeCentiInch" })
                                or type(gauge) ~= "number" or gauge ~= math.floor(gauge)
                                or gauge < 0 or gauge > 2500
                            then
                                return nil, "invalid_gauge", "Enter a gauge from 0.00 to 25.00 inches."
                            end
                            return { gaugeCentiInch = gauge }
                        end,
                        perform = function(_, player, arguments)
                            return performCutterAction(player, function()
                                return Machine.setGauge(arguments.gaugeCentiInch / 100, state)
                            end, false)
                        end,
                    },
                    auto_gauge = {
                        normalize = cutterNoArguments,
                        perform = function(_, player)
                            return performCutterAction(player,
                                function() return Machine.autoGauge(state) end, false)
                        end,
                    },
                    save_gauge = {
                        normalize = cutterNoArguments,
                        perform = function(_, player)
                            return performCutterAction(player,
                                function() return Machine.saveGauge(state) end, true)
                        end,
                    },
                    recall_gauge = {
                        normalize = cutterNoArguments,
                        perform = function(_, player)
                            return performCutterAction(player,
                                function() return Machine.recallGauge(state) end, false)
                        end,
                    },
                    rotate_paper = {
                        normalize = cutterNoArguments,
                        perform = function(_, player)
                            return performCutterAction(player,
                                function() return Machine.rotate(state) end, true)
                        end,
                    },
                    position_paper = {
                        normalize = cutterNoArguments,
                        perform = function(_, player)
                            return performCutterAction(player,
                                function() return Machine.position(state) end, false)
                        end,
                    },
                    set_clamp = {
                        normalize = function(arguments)
                            local clamp = type(arguments) == "table" and arguments.clamp
                            if not exactArguments(arguments, { "clamp" }) or type(clamp) ~= "boolean" then
                                return nil, "invalid_clamp", "Clamp state must be true or false."
                            end
                            return { clamp = clamp }
                        end,
                        perform = function(_, player, arguments)
                            return performCutterAction(player,
                                function() return Machine.setClamp(arguments.clamp, state) end, false)
                        end,
                    },
                    set_barrier = {
                        normalize = function(arguments)
                            local clear = type(arguments) == "table" and arguments.barrierClear
                            if not exactArguments(arguments, { "barrierClear" })
                                or type(clear) ~= "boolean"
                            then
                                return nil, "invalid_barrier", "Barrier state must be true or false."
                            end
                            return { barrierClear = clear }
                        end,
                        perform = function(_, player, arguments)
                            return performCutterAction(player, function()
                                return Machine.setBarrier(arguments.barrierClear, state)
                            end, false)
                        end,
                    },
                    guarded_cut = {
                        normalize = cutterNoArguments,
                        perform = function(_, player)
                            return performCutterAction(player,
                                function() return Machine.guardedCut(state) end, false)
                        end,
                    },
                    emergency_stop = {
                        normalize = cutterNoArguments,
                        perform = function(_, player)
                            return performCutterAction(player,
                                function() return Machine.emergencyStop(state) end, false)
                        end,
                    },
                    reset_safety = {
                        normalize = cutterNoArguments,
                        perform = function(_, player)
                            return performCutterAction(player,
                                function() return Machine.resetSafety(state) end, false)
                        end,
                    },
                    return_to_pallet = {
                        normalize = cutterNoArguments,
                        perform = function(_, player)
                            return performCutterAction(player,
                                function() return Machine.unload(state) end, false)
                        end,
                    },
                    run_next_lift = {
                        normalize = cutterNoArguments,
                        perform = function(_, player)
                            return performCutterAction(player,
                                function() return Machine.repeatLift(state) end, true)
                        end,
                    },
                }),
            },
            windmill = {
                canAcquire = function(player)
                    return World.validateNetworkWorkshopAccess(player, state,
                        state._activeWorkshopResourceId or "windmill")
                end,
                onAcquire = function(lease)
                    local session = {
                        setupTask = nil,
                        setupGame = nil,
                        maintenance = nil,
                        lockoutStep = nil,
                    }
                    activeWindmillRemote = session
                    machineRemoteSessions[state._activeWorkshopResourceId or "windmill"] = session
                    return true, "acquired", "Windmill console connected.",
                        windmillView(session), session
                end,
                onRelease = function(lease, _, reason)
                    local changed = reason ~= "closed" and Windmill.releaseOperator(state)
                    machineRemoteSessions[state._activeWorkshopResourceId or "windmill"] = nil
                    if activeWindmillRemote == (lease and lease.private) then
                        activeWindmillRemote = nil
                    end
                    if changed then saveCurrent() end
                    return true, "released", "Windmill controls released safely."
                end,
                commands = createWindmillCommands(),
            },
            skid_wrapper = {
                canAcquire = function(player)
                    local allowed, code, message = World.validateNetworkWorkshopAccess(
                        player, state, state._activeWorkshopResourceId or "skid_wrapper")
                    if not allowed then return false, code, message end
                    if Wrapper.step == "wrapping" then
                        return false, "machine_busy", "The skid wrapper is already running a cycle."
                    end
                    return true
                end,
                onAcquire = function()
                    local session = WrapperMaintenanceAuthority.newSession()
                    activeWrapperRemote = session
                    machineRemoteSessions[state._activeWorkshopResourceId or "skid_wrapper"] = session
                    return true, "acquired", "Skid-wrapper console connected.",
                        wrapperMaintenanceAuthority.view(session, true), session
                end,
                onRelease = function(lease)
                    machineRemoteSessions[state._activeWorkshopResourceId or "skid_wrapper"] = nil
                    if activeWrapperRemote == (lease and lease.private) then
                        activeWrapperRemote = nil
                    end
                    return true, "released", "Skid-wrapper controls released safely."
                end,
                commands = wrapperMaintenanceAuthority.withProductionCommands({
                    select_pallet = {
                        normalize = function(arguments)
                            local palletId = type(arguments) == "table" and arguments.palletId
                            if not exactArguments(arguments, { "palletId" })
                                or type(palletId) ~= "string" or #palletId < 1 or #palletId > 64
                                or not palletId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                            then
                                return nil, "invalid_pallet", "Choose a valid nearby pallet."
                            end
                            return { palletId = palletId }
                        end,
                        perform = function(_, _, arguments)
                            if not Wrapper.selectPallet(state, arguments.palletId) then
                                return false, "pallet_unavailable", tostring(state.message)
                            end
                            return true, "pallet_selected", tostring(state.message), wrapperView()
                        end,
                    },
                    start_cycle = {
                        normalize = function(arguments)
                            local palletId = type(arguments) == "table" and arguments.palletId
                            if not exactArguments(arguments, { "palletId" })
                                or type(palletId) ~= "string" or #palletId < 1 or #palletId > 64
                                or not palletId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                            then
                                return nil, "invalid_pallet", "Choose a valid nearby pallet."
                            end
                            return { palletId = palletId }
                        end,
                        perform = function(_, _, arguments)
                            if not Wrapper.selectPallet(state, arguments.palletId)
                                or not Wrapper.start(state)
                            then
                                return false, "cycle_blocked", tostring(state.message)
                            end
                            return true, "cycle_started", tostring(state.message), wrapperView()
                        end,
                    },
                }),
            },
            pallet_jack = {
                canAcquire = function(player)
                    local allowed, code, message = World.validateNetworkWorkshopAccess(
                        player, state, "pallet_jack")
                    if not allowed then return false, code, message end
                    if machineRelocationActive() then
                        return false, "machine_moving",
                            "Finish locking the moving machine onto the floor first."
                    end
                    return true
                end,
                onAcquire = function(_, player)
                    local accepted, code, message = World.operateNetworkPalletJack(
                        player, state)
                    return accepted, code, message, accepted and {} or nil
                end,
                onRelease = function(lease, player)
                    -- Timeout, disconnect, and normal release all use the same
                    -- safe recovery. An attached machine is locked to a valid
                    -- snapped cell (or its relocation origin) before the jack
                    -- relinquishes ownership.
                    World.recoverNetworkMachineMove(state, Assets, player)
                    PalletJack.forceRelease(state, Config.palletJack,
                        lease and lease.ownerPlayerId or nil)
                    saveCurrent()
                    return true, "released", state.palletJack.carriedPalletId
                        and "Loaded pallet jack parked safely."
                        or "Pallet jack parked."
                end,
                commands = {
                    lift_pallet = {
                        normalize = function(arguments)
                            local palletId = type(arguments) == "table" and arguments.palletId
                            if not exactArguments(arguments, { "palletId" })
                                or type(palletId) ~= "string" or #palletId < 1 or #palletId > 64
                                or not palletId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                            then
                                return nil, "invalid_pallet", "Choose a valid nearby pallet."
                            end
                            return { palletId = palletId }
                        end,
                        perform = function(_, player, arguments)
                            if machineRelocationActive() then
                                return false, "equipment_moving",
                                    "Place the moving machine before lifting a pallet."
                            end
                            local accepted, code, message = World.liftNetworkPallet(
                                player, state, arguments.palletId)
                            if accepted then saveCurrent() end
                            return accepted, code, message
                        end,
                    },
                    lower_pallet = {
                        normalize = function(arguments)
                            local palletId = type(arguments) == "table" and arguments.palletId
                            if not exactArguments(arguments, { "palletId" })
                                or type(palletId) ~= "string" or #palletId < 1 or #palletId > 64
                                or not palletId:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")
                            then
                                return nil, "invalid_pallet", "Choose the pallet currently on the forks."
                            end
                            return { palletId = palletId }
                        end,
                        perform = function(_, player, arguments)
                            if machineRelocationActive() then
                                return false, "equipment_moving",
                                    "Place the moving machine before lowering a pallet."
                            end
                            local accepted, code, message = World.lowerNetworkPallet(
                                player, state, Assets, arguments.palletId)
                            if accepted then saveCurrent() end
                            return accepted, code, message
                        end,
                    },
                    park_jack = {
                        normalize = function(arguments)
                            if not exactArguments(arguments, {}) then
                                return nil, "invalid_arguments", "Parking takes no additional data."
                            end
                            return {}
                        end,
                        perform = function(_, player)
                            if machineRelocationActive() then
                                return false, "equipment_moving",
                                    "Place the moving machine before parking the jack."
                            end
                            local accepted, code, message = World.releaseNetworkPalletJack(
                                player, state, false)
                            if accepted then saveCurrent() end
                            return accepted, code, message
                        end,
                    },
                    move_machine = {
                        normalize = function(arguments)
                            local machineIndex = type(arguments) == "table"
                                and arguments.machineIndex
                            if not exactArguments(arguments, { "machineIndex" })
                                or type(machineIndex) ~= "number"
                                or machineIndex % 1 ~= 0
                                or machineIndex < 1 or machineIndex > 3
                            then
                                return nil, "invalid_machine", "Choose a valid nearby machine."
                            end
                            return { machineIndex = machineIndex }
                        end,
                        perform = function(_, player, arguments)
                            local resources = { "cutter", "skid_wrapper", "windmill" }
                            local resourceId = resources[arguments.machineIndex]
                            local occupied = workshopAuthority
                                and workshopAuthority:leaseForResource(resourceId) ~= nil
                            local accepted, code, message = World.beginNetworkMachineMove(
                                player, state, arguments.machineIndex, occupied)
                            if accepted then saveCurrent() end
                            return accepted, code, message
                        end,
                    },
                    rotate_machine = {
                        normalize = function(arguments)
                            if not exactArguments(arguments, {}) then
                                return nil, "invalid_arguments", "Rotation takes no additional data."
                            end
                            return {}
                        end,
                        perform = function(_, player)
                            local accepted, code, message = World.rotateNetworkMachine(
                                player, state)
                            if accepted then saveCurrent() end
                            return accepted, code, message
                        end,
                    },
                    place_machine = {
                        normalize = function(arguments)
                            local cell = type(arguments) == "table" and arguments.placementCell
                            local column, row
                            if type(cell) == "string" then
                                column, row = cell:match("^c(%d+)r(%d+)$")
                            end
                            column, row = tonumber(column), tonumber(row)
                            if not exactArguments(arguments, { "placementCell" })
                                or not column or not row or column > 64 or row > 64
                            then
                                return nil, "invalid_cell", "Choose a valid highlighted placement cell."
                            end
                            return { placementCell = cell }
                        end,
                        perform = function(_, player, arguments)
                            local accepted, code, message = World.placeNetworkMachine(
                                player, state, Assets, arguments.placementCell)
                            if accepted then saveCurrent() end
                            return accepted, code, message
                        end,
                    },
                },
            },
        },
    })
    authority.resources.pallet_jack = MachineRelocationAuthority.resource({
        state = state,
        assets = Assets,
        world = World,
        palletJack = PalletJack,
        config = Config,
        save = saveCurrent,
        controlOccupied = function(machineIndex)
            local resources = { "cutter", "skid_wrapper", "windmill" }
            local base = resources[machineIndex]
            for _, unit in ipairs(MachineFleet.installedUnits(state, MachineResource.model(base))) do
                if authority:leaseForResource(MachineResource.forUnit(base, unit.id)) then
                    return true
                end
            end
            return authority:leaseForResource(base) ~= nil
        end,
    })
    local warehouseCommand = WarehouseAuthority.command({state=state,world=World,save=saveCurrent})
    authority.resources.pallet_jack.commands.warehouse_action = warehouseCommand
    authority.resources.warehouse = {
        canAcquire=function(player) return World.warehouseAccess(player,state) end,
        onAcquire=function() return true,"acquired","Warehouse controls connected.",{} end,
        commands={warehouse_action=warehouseCommand},
        onRelease=function(_,player)
            if state.forklift and state.forklift.operatorPlayerId==player.id then
                World.forceReleaseForklift(player,state)
                saveCurrent()
            end
            return true,"released","Forklift safely stopped.",{}
        end,
        view=function() return {} end,
    }
    registerInstalledMachineResources(authority)
    return authority
end

local function localAuthorityPlayer()
    return {
        id = 1,
        x = World.player.x,
        y = World.player.y,
        intentX = World.player.intentX,
        intentY = World.player.intentY,
        facing = World.player.facing,
    }
end

local function acquireLocalWorkshop(resourceId)
    if not workshopAuthority then return false, "Workshop authority is unavailable." end
    localWorkshopRequestId = localWorkshopRequestId + 1
    local result = workshopAuthority:acquire(localAuthorityPlayer(), {
        requestId = localWorkshopRequestId,
        resourceId = resourceId,
    }, { state = state })
    if result.accepted then localWorkshopLease = result end
    return result.accepted, result.message
end

local function commandLocalWorkshop(action, arguments)
    if not workshopAuthority or not localWorkshopLease then
        return false, "No host-authorized workshop control is active."
    end
    localWorkshopRequestId = localWorkshopRequestId + 1
    local result = workshopAuthority:command(localAuthorityPlayer(), {
        requestId = localWorkshopRequestId,
        resourceId = localWorkshopLease.resourceId,
        leaseId = localWorkshopLease.leaseId,
        action = action,
        args = type(arguments) == "table" and arguments or {},
        expectedRevision = localWorkshopLease.revision,
    }, { state = state })
    if result.accepted then localWorkshopLease.revision = result.revision end
    return result.accepted, result.message, result
end

local function releaseLocalWorkshop(reason)
    if not workshopAuthority or not localWorkshopLease then return false end
    localWorkshopRequestId = localWorkshopRequestId + 1
    local result = workshopAuthority:release(localAuthorityPlayer(), {
        requestId = localWorkshopRequestId,
        resourceId = localWorkshopLease.resourceId,
        leaseId = localWorkshopLease.leaseId,
        reason = reason == "cancelled" and "cancelled" or "closed",
    }, { state = state })
    localWorkshopLease = nil
    state._localWorkshopMachineId = nil
    return result.accepted
end

local function clearWorkshopAuthority(reason)
    if workshopAuthority then
        for playerId = 1, 4 do
            workshopAuthority:cleanupPlayer({ id = playerId }, reason or "session_closed",
                { state = state })
        end
    end
    workshopAuthority = nil
    localWorkshopLease = nil
    state._localWorkshopMachineId = nil
    activeCutterRemote = nil
    cutterMaintenanceAuthority = nil
    activeWrapperRemote = nil
    wrapperMaintenanceAuthority = nil
    activeWindmillRemote = nil
    machineRemoteSessions = {}
end

local function prepareHostSave(slot)
    local payload, status = Save.load(slot)
    local mode = "continue"
    if not payload and status == "empty" then
        payload, mode = Save.newGame(slot), "new"
    elseif not payload then
        return nil, nil, "That host save is damaged. Choose another slot or delete it first."
    end
    local writable, writableError = Save.preflightWritable(slot)
    if not writable then return nil, nil, writableError end
    return payload, mode
end

local function startLanHost(slot, playerName)
    local payload, mode, loadError = prepareHostSave(slot)
    if not payload then return false, loadError end
    workshopAuthority = createWorkshopAuthority()
    localWorkshopLease = nil
    localWorkshopRequestId = 0
    activeCutterRemote = nil
    activeWrapperRemote = nil
    activeWindmillRemote = nil
    machineRemoteSessions = {}
    local hostName = tostring(playerName or "LAN Worker"):gsub("Worker", "Host")
    local ok, errorMessage = multiplayer:startHost({
        port = 22122,
        name = hostName,
        character = Config.player.character,
    })
    if not ok then
        clearWorkshopAuthority("host_start_failed")
        return false, errorMessage
    end
    lanReconnect:cancel(true)
    lanReconnectArmed = false
    local discoveryOk, discoveryError = lanDiscovery:startHost({
        gamePort = 22122,
        name = hostName .. " - Slot " .. tostring(slot),
    })
    local started, startError = startGame(payload, mode)
    if not started then
        lanDiscovery:stop()
        multiplayer:stop("Host save could not be opened")
        clearWorkshopAuthority("host_save_failed")
        state.screen = "lan"
        return false, startError
    end
    if isAndroidPlatform() and love.window and love.window.setDisplaySleepEnabled then
        love.window.setDisplaySleepEnabled(false)
    end
    state.message = discoveryOk
        and "LAN host active. Nearby workers can find this shop automatically or join by IPv4 address."
        or ("LAN host active at " .. tostring(multiplayer.localAddress or "this device")
            .. ". Automatic discovery is unavailable: " .. tostring(discoveryError))
    return true
end

local function startLanSearch()
    local ok, message = lanDiscovery:startSearch()
    local _, status = lanDiscovery:status()
    LanScreen.setDiscovery({}, ok and status or message)
    return ok, message
end

local function startLanClient(address, playerName, reconnecting)
    if reconnecting ~= true then
        lanReconnect:cancel(false)
        lanReconnect:remember(address, playerName)
        lanReconnectArmed = false
    end
    lanDiscovery:stop()
    local ok, message = multiplayer:startClient(address, {
        name = playerName,
        character = Config.player.character,
    })
    if not ok and reconnecting ~= true then startLanSearch() end
    return ok, message
end

openLocalPlay = function(slot)
    local sessionClean, sessionError = multiplayer:stop("Opening Local Play")
    clearWorkshopAuthority("session_closed")
    lanReconnect:cancel(true)
    lanReconnectArmed = false
    local connectionClean, connectionError = closeDirectConnection()
    local hostClean, hostError = closeDirectHostComposite()
    if not sessionClean or not connectionClean or not hostClean then
        state.screen = "direct"
        DirectScreen.showCleanupError(sessionError or connectionError or hostError)
        return false
    end
    state.screen = "lan"
    LanScreen.enter({
        slot = slot,
        host = startLanHost,
        join = startLanClient,
        cancel = function()
            lanReconnect:cancel(true)
            lanReconnectArmed = false
            multiplayer:stop("Connection cancelled")
            startLanSearch()
        end,
        back = function()
            lanDiscovery:stop()
            lanReconnect:cancel(true)
            lanReconnectArmed = false
            multiplayer:stop("Leaving Local Play")
            state.screen = "title"
            TitleScreen.enter(startGame, openLocalPlay,
                CryptoNative.productionReady == true and openDirectPlay or nil)
        end,
    })
    startLanSearch()
end

closeDirectConnection = function()
    local connection = directConnection
    if not connection then
        pendingDirectSession = nil
        return true
    end
    local called, cleaned = pcall(connection.close, connection)
    if not called or cleaned ~= true then
        return false,
            "Direct connection cleanup could not be verified; restart the game before creating another invitation."
    end
    directConnection = nil
    pendingDirectSession = nil
    return true
end

closeDirectHostComposite = function()
    local controller = directHostComposite
    if not controller then
        directHostInvitationGeneration = 0
        return true
    end
    local called, cleaned = pcall(controller.close, controller)
    if not called or cleaned ~= true then
        return false,
            "Direct host cleanup could not be verified; restart the game before hosting again."
    end
    directHostComposite = nil
    directHostInvitationGeneration = 0
    return true
end

local function disposeDirectTransportFactory(factory)
    if type(factory) ~= "table" or type(factory.close) ~= "function" then
        return false
    end
    local called, cleaned = pcall(factory.close, factory)
    return called and cleaned == true
end

local DIRECT_HOST_PORT_SLOTS = {
    { loopback = 22122, outer = 22123 },
    { loopback = 22124, outer = 22125 },
    { loopback = 22126, outer = 22127 },
}

local function directHostCanInvite()
    if directConnection or not directHostComposite
        or not multiplayer:isHost() or multiplayer.networkKind ~= "direct"
    then
        return false
    end
    local countOk, count = pcall(directHostComposite.linkCount, directHostComposite)
    local capacityOk, capacity = pcall(directHostComposite.capacity, directHostComposite)
    local hudOk, info = pcall(multiplayer.hudInfo, multiplayer)
    return countOk and capacityOk and type(count) == "number" and type(capacity) == "number"
        and hudOk and type(info) == "table"
        and (tonumber(info.pendingJoinCount) or 0) == 0
        and count >= 0 and count < capacity
end

local function createDirectConnection(loopbackHostPort)
    local ok, socketModule = pcall(require, "socket")
    if not ok then return nil, "Direct Internet sockets are unavailable on this device." end
    return DirectConnection.new({
        provider = CryptoNative,
        socketModule = socketModule,
        loopbackHostPort = loopbackHostPort,
    })
end

local function startDirectHostConnection(localAddress)
    local slotCount = #DIRECT_HOST_PORT_SLOTS
    local firstSlot = (directHostInvitationGeneration % slotCount) + 1
    local lastError = "No Direct guest port slot is available."
    for offset = 0, slotCount - 1 do
        local slotIndex = ((firstSlot + offset - 1) % slotCount) + 1
        local slot = DIRECT_HOST_PORT_SLOTS[slotIndex]
        local connection, connectionError = createDirectConnection(slot.loopback)
        if not connection then return nil, connectionError end
        local started, codeOrError = connection:startHost(localAddress, slot.outer)
        if started then
            directHostInvitationGeneration = slotIndex
            return connection, codeOrError
        end
        lastError = codeOrError or lastError
        local closeOk, cleaned = pcall(connection.close, connection)
        if not closeOk or cleaned ~= true then
            return nil,
                "A Direct port attempt could not be cleaned up safely; restart the game before hosting again.",
                connection
        end
    end
    return nil, lastError
end

local function prepareDirectHost(slot, playerName, localAddress)
    local connectionClean, connectionError = closeDirectConnection()
    if not connectionClean then return false, connectionError end
    local hostClean, hostError = closeDirectHostComposite()
    if not hostClean then return false, hostError end
    local payload, mode, loadError = prepareHostSave(slot)
    if not payload then return false, loadError end
    local connection, codeOrError, cleanupOwner = startDirectHostConnection(localAddress)
    if not connection then
        if cleanupOwner then directConnection = cleanupOwner end
        return false, codeOrError
    end
    directConnection = connection
    pendingDirectSession = {
        role = "host",
        kind = "initial_host",
        payload = payload,
        saveMode = mode,
        name = tostring(playerName or "Direct Worker"):gsub("Worker", "Host"),
    }
    return true, codeOrError
end

local function prepareDirectGuest(hostCode, localAddress, playerName)
    local connectionClean, connectionError = closeDirectConnection()
    if not connectionClean then return false, connectionError end
    local hostClean, hostError = closeDirectHostComposite()
    if not hostClean then return false, hostError end
    local connection, connectionError = createDirectConnection()
    if not connection then return false, connectionError end
    local started, codeOrError = connection:startGuest(hostCode, localAddress)
    if not started then
        local closeCalled, cleaned = pcall(connection.close, connection)
        if not closeCalled or cleaned ~= true then
            directConnection = connection
            return false,
                "Direct guest setup failed and its cleanup could not be verified; restart the game before trying again."
        end
        return false, codeOrError
    end
    directConnection = connection
    pendingDirectSession = {
        role = "guest",
        name = tostring(playerName or "Direct Worker"),
    }
    return true, codeOrError
end

local function prepareAdditionalDirectHost(_, _, localAddress)
    local connectionClean, connectionError = closeDirectConnection()
    if not connectionClean then return false, connectionError end
    if not directHostCanInvite() then
        return false, "Direct guest capacity is full or another invitation is still being prepared."
    end
    local connection, codeOrError, cleanupOwner = startDirectHostConnection(localAddress)
    if not connection then
        if cleanupOwner then directConnection = cleanupOwner end
        return false, codeOrError
    end
    directConnection = connection
    pendingDirectSession = {
        role = "host",
        kind = "additional_host",
    }
    return true, codeOrError
end

local function submitDirectResponse(responseCode)
    if not directConnection or not pendingDirectSession
        or pendingDirectSession.role ~= "host" then
        return false, "No Direct host invitation is waiting for a reply."
    end
    return directConnection:submitResponse(responseCode)
end

openDirectPlay = function(slot)
    lanDiscovery:stop()
    lanReconnect:cancel(true)
    lanReconnectArmed = false
    local sessionClean, sessionError = multiplayer:stop("Opening Direct Play")
    clearWorkshopAuthority("session_closed")
    local connectionClean, connectionError = closeDirectConnection()
    local hostClean, hostError = closeDirectHostComposite()
    if not sessionClean or not connectionClean or not hostClean then
        state.screen = "direct"
        DirectScreen.showCleanupError(sessionError or connectionError or hostError)
        return false
    end
    DirectScreen.leave()
    lastDirectSlot = tonumber(slot) or lastDirectSlot or 1
    state.screen = "direct"
    DirectScreen.enter({
        slot = lastDirectSlot,
        host = prepareDirectHost,
        join = prepareDirectGuest,
        response = submitDirectResponse,
        cancel = closeDirectConnection,
        back = function()
            local cleaned, cleanupError = closeDirectConnection()
            if not cleaned then
                DirectScreen.showCleanupError(cleanupError)
                return false, cleanupError
            end
            state.screen = "title"
            TitleScreen.enter(startGame, openLocalPlay,
                CryptoNative.productionReady == true and openDirectPlay or nil)
            return true
        end,
    })
end

openDirectInvite = function()
    if not directHostCanInvite() then
        state.message = "Direct guest capacity is full or another invitation is still active."
        return false
    end
    MultiplayerHud.close()
    state.screen = "direct"
    DirectScreen.enter({
        slot = lastDirectSlot,
        inviteOnly = true,
        host = prepareAdditionalDirectHost,
        response = submitDirectResponse,
        cancel = function()
            local cleaned, cleanupError = closeDirectConnection()
            if not cleaned then return false, cleanupError end
            DirectScreen.leave()
            state.screen = "world"
            state.message = "The pending Direct invitation was cancelled; connected workers stayed online."
            return true
        end,
        back = function()
            local cleaned, cleanupError = closeDirectConnection()
            if not cleaned then return false, cleanupError end
            DirectScreen.leave()
            state.screen = "world"
            return true
        end,
    })
    if syncMobileKeyboard then syncMobileKeyboard() end
    return true
end

returnToTitle = function()
    saveCurrent()
    lanDiscovery:stop()
    lanReconnect:cancel(true)
    lanReconnectArmed = false
    local sessionClean, sessionError = multiplayer:stop("Returned to title")
    clearWorkshopAuthority("session_closed")
    local connectionClean, connectionError = closeDirectConnection()
    local hostClean, hostError = closeDirectHostComposite()
    DirectScreen.leave()
    if isAndroidPlatform() and love.window and love.window.setDisplaySleepEnabled then
        love.window.setDisplaySleepEnabled(true)
    end
    state.screen = "title"
    if not sessionClean or not connectionClean or not hostClean then
        state.message = sessionError or connectionError or hostError
    end
    TitleScreen.enter(startGame, openLocalPlay,
        CryptoNative.productionReady == true and openDirectPlay or nil)
end

local function closeOptions()
    local returnScreen = state.optionsReturnScreen or "title"
    state.optionsReturnScreen = nil
    state.screen = returnScreen
    if syncMobileKeyboard then syncMobileKeyboard() end
    return true
end

openOptions = function()
    if state.screen == "asset_error" or spriteLabActive then return false end
    if state.screen == "options" then return OptionsScreen.leave() end
    local returnScreen = state.screen
    local liveShop = state.activeSlot ~= nil
        and (returnScreen ~= "title" and returnScreen ~= "lan" and returnScreen ~= "direct"
            or multiplayer:isHost())
    state.optionsReturnScreen = returnScreen
    OptionsScreen.enter({
        settings = App.settings or Settings.normalize(),
        sound = App.sound,
        save = Save,
        state = state,
        saveCurrent = saveCurrent,
        isNetworkClient = function() return multiplayer:isClient() end,
        useActiveState = liveShop,
        preferredSlot = returnScreen == "title" and (TitleScreen.selected or 1)
            or state.activeSlot or TitleScreen.selected or 1,
        getControlLayout = function()
            return mobileControls and mobileControls:layout()
                or App.settings.controlLayout
        end,
        setControlLayout = function(layout)
            App.settings.controlLayout = mobileControls and mobileControls:setLayout(layout)
                or Settings.normalizeControlLayout(layout)
        end,
        commitControlLayout = function()
            Settings.save(App.settings)
        end,
        resetControlLayout = function()
            local layout = MobileControls.defaultLayout()
            App.settings.controlLayout = mobileControls and mobileControls:setLayout(layout)
                or layout
            Settings.save(App.settings)
        end,
        onClose = closeOptions,
    })
    state.screen = "options"
    if syncMobileKeyboard then syncMobileKeyboard() end
    return true
end

local function warehousePlayer()
    return {id=World.player.id or 1,x=World.player.x,y=World.player.y}
end

local function sendWarehouseIntent(intent)
    local function refused(message)
        state.message=message or "The warehouse action could not be sent."
        return false,state.message
    end
    if multiplayer:isClient() then
        if warehousePendingIntent then return refused("Wait for the host to finish the current warehouse action.") end
        warehousePendingIntent=intent
        local info=multiplayer:workshopInfo()
        local jackTransfer=info and info.resourceId=="pallet_jack"
            and intent.vehicle=="pallet_jack" and (intent.kind=="store" or intent.kind=="retrieve")
        local sent,message
        if info and (info.resourceId=="warehouse" or jackTransfer) then
            sent,message=multiplayer:requestWorkshopCommand("warehouse_action",{warehouseIntent=intent})
        elseif info then
            warehousePendingIntent=nil
            return refused("Close or park the other workshop control first.")
        else sent,message=multiplayer:requestWorkshopAcquire("warehouse") end
        if not sent then warehousePendingIntent=nil; return refused(message) end
        state.message="Waiting for the host to confirm the warehouse action..."
        return nil
    end
    local accepted,message,result
    if multiplayer:isHost() then
        local jackTransfer=localWorkshopLease and localWorkshopLease.resourceId=="pallet_jack"
            and intent.vehicle=="pallet_jack" and (intent.kind=="store" or intent.kind=="retrieve")
        if not localWorkshopLease or (localWorkshopLease.resourceId~="warehouse" and not jackTransfer) then
            if localWorkshopLease then return refused("Close or park the other workshop control first.") end
            accepted,message=acquireLocalWorkshop("warehouse")
            if not accepted then state.message=message; return false,message end
        end
        accepted,message,result=commandLocalWorkshop("warehouse_action",{warehouseIntent=intent})
        if accepted and intent.kind=="release" then releaseLocalWorkshop("closed") end
        if not accepted and intent.kind=="operate" and localWorkshopLease
            and localWorkshopLease.resourceId=="warehouse" then releaseLocalWorkshop("cancelled") end
    else
        local command=WarehouseAuthority.command({state=state,world=World,save=saveCurrent})
        local code
        accepted,code,message=command.perform({},warehousePlayer(),{warehouseIntent=intent})
    end
    state.message=message or (accepted and "Warehouse action completed." or "Warehouse action refused.")
    return accepted,state.message
end

warehouseControls=WarehouseControls.new({state=state,world=World,player=warehousePlayer,command=sendWarehouseIntent})

local function palletJackCommandFor(action, selected)
    local jack = PalletJack.ensure(state, Config.palletJack)
    if action == "park" then return "park_jack", {} end
    if action == "rotate_machine" then return "rotate_machine", {} end
    if action == "place_machine" then
        local placementCell = World.networkPlacementCellId(state, Assets)
        if not placementCell then
            return nil, nil, "Choose a green placement cell before setting the machine down."
        end
        return "place_machine", { placementCell = placementCell }
    end
    if action == "move_machine" then
        local machineIndex = selected and ({
            cutter = 1,
            skidWrapper = 2,
            windmill = 3,
        })[selected.kind]
        if not machineIndex then return nil, nil, "Move beside the machine you want to relocate." end
        return "move_machine", { machineIndex = machineIndex }
    end
    if action == "lift" then
        local selectedPallet = selected and selected.target
            and selected.target.item and selected.target.item.pallet
        local palletId = selectedPallet and selectedPallet.id
        if type(palletId) ~= "string" or palletId == "" then
            return nil, nil, "Tap a valid skid to lift it."
        end
        if jack.carriedPalletId then
            return nil, nil, "Lower the skid already on the forks before lifting another one."
        end
        return "lift_pallet", { palletId = palletId }
    end
    if jack.carriedPalletId then
        return "lower_pallet", { palletId = jack.carriedPalletId }
    end
    local candidateId = jack.candidatePalletId
        or World.networkPalletJackSnapshot(state).candidatePalletId
    if candidateId then return "lift_pallet", { palletId = candidateId } end
    return "park_jack", {}
end

local function handlePalletJackControl(action, selected)
    if machineRelocationActive() then
        local targetsPalletJack = action == "park" or action == "use"
            or action == "lift"
        if targetsPalletJack and action ~= "place_machine" then
            state.message = "Place the moving machine before using or parking the pallet jack."
            return true
        end
    end
    if multiplayer:isClient() then
        local info = multiplayer:workshopInfo()
        if not info or info.resourceId ~= "pallet_jack" then
            if action == "park" then
                state.message = state.palletJack and state.palletJack.operating
                    and "Another worker is operating the pallet jack."
                    or "Acquire the pallet jack before parking it."
                return true
            end
            return false
        end
        local command, arguments, commandError = palletJackCommandFor(action, selected)
        if not command then state.message = commandError; return true end
        local requested, errorMessage = multiplayer:requestWorkshopCommand(
            command, arguments)
        state.message = requested
            and (command == "lift_pallet" and "Waiting for the host to verify that exact pallet..."
                or command == "lower_pallet" and "Waiting for the host to verify the drop space..."
                or command == "move_machine" and "Waiting for the host to attach that machine..."
                or command == "rotate_machine" and "Waiting for the host to rotate the machine..."
                or command == "place_machine" and "Waiting for the host to verify that floor cell..."
                or "Waiting for the host to park the pallet jack...")
            or tostring(errorMessage or "The pallet-jack request could not be sent.")
        return true
    end
    if not multiplayer:isHost() then return false end
    if localWorkshopLease and localWorkshopLease.resourceId == "pallet_jack" then
        local command, arguments, commandError = palletJackCommandFor(action, selected)
        if not command then state.message = commandError; return true end
        local accepted, message = commandLocalWorkshop(command, arguments)
        state.message = tostring(message or (accepted
            and "Pallet-jack action completed." or "Pallet-jack action was rejected."))
        if accepted and command == "park_jack" then releaseLocalWorkshop("closed") end
        return true
    end
    local jack = PalletJack.ensure(state, Config.palletJack)
    if action == "park" and jack.operating and jack.operatorPlayerId ~= 1 then
        state.message = "Another worker is operating the pallet jack."
        return true
    end
    return false
end

local inputContext = {
    state = state,
    assets = Assets,
    computerScreen = ComputerScreen,
    workPhoneScreen = WorkPhoneScreen,
    hud = Hud,
    world = World,
    shop = Shop,
    jobOfferScreen = JobOfferScreen,
    workshopRemoteScreen = WorkshopRemoteScreen,
    jobService = JobService,
    machine = Machine,
    wrapper = Wrapper,
    machineScreen = MachineScreen,
    truckInventoryScreen = TruckInventoryScreen,
    vendorScreen = VendorScreen,
    palletWorkOrderScreen = PalletWorkOrderScreen,
    pressScreen = PressScreen,
    windmill = Windmill,
    title = TitleScreen,
    saveCurrent = saveCurrent,
    isNetworkClient = function() return multiplayer:isClient() end,
    cutterControlOccupied = function()
        local target = World.selectedInteraction and World.selectedInteraction.target
        local resourceId = World.workshopResourceId("cutter", target)
        return workshopAuthority and workshopAuthority:leaseForResource(resourceId) ~= nil
    end,
    wrapperControlOccupied = function()
        local target = World.selectedInteraction and World.selectedInteraction.target
        local resourceId = World.workshopResourceId("skidWrapper", target)
        return workshopAuthority and workshopAuthority:leaseForResource(resourceId) ~= nil
    end,
    windmillControlOccupied = function()
        local target = World.selectedInteraction and World.selectedInteraction.target
        local resourceId = World.workshopResourceId("windmill", target)
        return workshopAuthority and workshopAuthority:leaseForResource(resourceId) ~= nil
    end,
    palletJackControl = handlePalletJackControl,
    networkInteraction = function(selected)
        if selected and selected.kind=="forklift" then sendWarehouseIntent({kind="operate"}); return true end
        if selected and selected.kind=="palletRack" then
            return warehouseControls:openRack(selected.target and selected.target.rackId)
        end
        if not multiplayer:isActive() then return false end
        if not selected then
            if multiplayer:isClient() then
                state.message = "Move beside a workshop control before using it."
                return true
            end
            return false
        end
        local resourceId = World.workshopResourceId(selected.kind, selected.target)
        if multiplayer:isHost() and resourceId then
            state._localWorkshopMachineId = selected.target and selected.target.machineId
            local lease = workshopAuthority and workshopAuthority:leaseForResource(resourceId)
            if lease and lease.ownerPlayerId ~= 1 then
                state._localWorkshopMachineId = nil
                state.message = "Another worker is using that workshop control."
                return true
            end
            local acquired, acquireMessage = acquireLocalWorkshop(resourceId)
            if not acquired then
                state._localWorkshopMachineId = nil
                state.message = tostring(acquireMessage or "That workshop control is unavailable.")
                return true
            end
            if resourceId == "pallet_jack" then
                state.message = tostring(acquireMessage
                    or "Operating pallet jack. Drive with movement controls.")
                return true
            end
            return false
        end
        if not multiplayer:isClient() then return false end
        if resourceId then
            local requested, errorMessage = multiplayer:requestWorkshopAcquire(resourceId)
            state.message = requested
                and "Waiting for the host device to reserve that workshop control..."
                or tostring(errorMessage or "The workshop request could not be sent.")
            return true
        end
        if selected.kind ~= "loadingBayDoor" and selected.kind ~= "truckCargoDoor" then
            state.message = "That shop-floor action is not worker-enabled yet."
            return true
        end
        local doorState = selected.kind == "truckCargoDoor"
            and selected.target and selected.target.truckState
            or selected.target and selected.target.doorState
        if selected.kind == "truckCargoDoor" then
            if doorState == "parked_closed" then doorState = "closed"
            elseif doorState == "cargo_open" then doorState = "open"
            else doorState = nil end
        end
        if doorState ~= "closed" and doorState ~= "open" then
            state.message = selected.kind == "truckCargoDoor"
                and "Wait for the truck cargo door to finish moving."
                or "Wait for the loading-bay door to finish moving."
            return true
        end
        local desiredState = doorState == "closed" and "open" or "closed"
        local requested, errorMessage = multiplayer:requestInteraction(
            selected.kind, desiredState)
        state.message = requested
            and (selected.kind == "truckCargoDoor"
                and "Waiting for the host device to verify the truck cargo door..."
                or "Waiting for the host device to verify the loading-bay switch...")
            or tostring(errorMessage or "The interaction request could not be sent.")
        return true
    end,
    requestWorkshopCommand = function(action, arguments)
        return multiplayer:requestWorkshopCommand(action, arguments)
    end,
    releaseWorkshopInteraction = function(reason)
        if multiplayer:isClient() then return multiplayer:releaseWorkshop(reason) end
        if multiplayer:isHost() then return releaseLocalWorkshop(reason) end
        return false
    end,
    returnToTitle = returnToTitle,
    worldPointerCoordinates = function(x, y)
        if state.screen == "world" and App.mobileCamera and App.mobileCamera:isEnabled() then
            return App.mobileCamera:screenToWorld(x, y)
        end
        return x, y
    end,
}

local function pointerPosition()
    if controller and controller:isActive() and state.screen ~= "world" then
        return controller:pointer()
    end
    if mobileControls and mobileControls:isEnabled() then
        local x, y = mobileControls:pointer()
        if x and y then
            if cameraTransformsUi() then return App.mobileCamera:screenToWorld(x, y) end
            return x, y
        end
    end
    local x, y = love.mouse.getPosition()
    return toPointerCoordinates(x, y)
end

local function multiplayerHudInfo()
    local info = multiplayer:hudInfo()
    info.canInvite = directHostCanInvite()
    if multiplayer:isHost() then
        info.workshopResources = workshopAuthority and workshopAuthority:snapshot() or {}
    end
    return info
end

local function handleMultiplayerHudAction(action)
    if action == true then return true end
    if type(action) ~= "table" then return false end
    local ok, message
    if action.kind == "approve" then
        ok, message = multiplayer:approveJoin(action.requestId)
    elseif action.kind == "deny" then
        ok, message = multiplayer:rejectJoin(action.requestId)
    elseif action.kind == "remove" then
        ok, message = multiplayer:kickPlayer(action.playerId)
    elseif action.kind == "invite" then
        openDirectInvite()
        return true
    else
        return true
    end
    state.message = tostring(message or (ok
        and "Direct player control completed."
        or "That Direct player action is no longer available."))
    return true
end

local function multiplayerHudMousepressed(gameX, gameY, button)
    if state.screen ~= "world" then return false end
    local action = MultiplayerHud.mousepressed(
        gameX, gameY, button, multiplayerHudInfo())
    if not action then return false end
    return handleMultiplayerHudAction(action)
end

local function multiplayerHudMousereleased(gameX, gameY, button)
    if state.screen ~= "world" then return false end
    return MultiplayerHud.mousereleased(
        gameX, gameY, button, multiplayerHudInfo()) == true
end

local function dispatchGameMousePressed(gameX, gameY, button)
    if state.screen == "asset_error" then return end
    if button == 1 then Ui.notePress(gameX, gameY) end
    if App.sound then App.sound:pointerPressed(button, state.screen) end
    if state.screen == "options" then
        local result = OptionsScreen.mousepressed(gameX, gameY, button)
        syncMobileKeyboard()
        return result
    elseif button == 1 and OptionsScreen.accessHit(gameX, gameY) then
        return openOptions()
    elseif state.screen == "lan" then
        local result = LanScreen.mousepressed(gameX, gameY, button)
        syncMobileKeyboard()
        return result
    elseif state.screen == "direct" then
        local result = DirectScreen.mousepressed(gameX, gameY, button)
        syncMobileKeyboard()
        return result
    end
    if multiplayerHudMousepressed(gameX, gameY, button) then return true end
    if warehouseControls:mousepressed(gameX,gameY,button) then return true end
    return Input.mousepressed(gameX, gameY, button, inputContext)
end

local function dispatchGameMouseReleased(gameX, gameY, button)
    if state.screen == "options" then return OptionsScreen.mousereleased(gameX, gameY, button) end
    if state.screen == "lan" then return LanScreen.mousereleased(gameX, gameY, button) end
    if state.screen == "direct" then return DirectScreen.mousereleased(gameX, gameY, button) end
    if multiplayerHudMousereleased(gameX, gameY, button) then return true end
    return Input.mousereleased(gameX, gameY, button, inputContext)
end

local function dispatchMousePressed(x, y, button)
    if state.screen == "asset_error" then return end
    local gameX, gameY = toPointerCoordinates(x, y)
    if button == 1 then Ui.notePress(gameX, gameY) end
    if App.sound then App.sound:pointerPressed(button, state.screen) end
    if state.screen == "options" then
        local result = OptionsScreen.mousepressed(gameX, gameY, button)
        syncMobileKeyboard()
        return result
    elseif button == 1 and OptionsScreen.accessHit(gameX, gameY) then
        return openOptions()
    elseif state.screen == "lan" then
        local result = LanScreen.mousepressed(gameX, gameY, button)
        syncMobileKeyboard()
        return result
    elseif state.screen == "direct" then
        local result = DirectScreen.mousepressed(gameX, gameY, button)
        syncMobileKeyboard()
        return result
    end
    if multiplayerHudMousepressed(gameX, gameY, button) then return true end
    if warehouseControls:mousepressed(gameX,gameY,button) then return true end
    return Input.mousepressed(gameX, gameY, button, inputContext)
end

local function dispatchMouseReleased(x, y, button)
    local gameX, gameY = toPointerCoordinates(x, y)
    if state.screen == "options" then return OptionsScreen.mousereleased(gameX, gameY, button) end
    if state.screen == "lan" then return LanScreen.mousereleased(gameX, gameY, button) end
    if state.screen == "direct" then return DirectScreen.mousereleased(gameX, gameY, button) end
    if multiplayerHudMousereleased(gameX, gameY, button) then return true end
    return Input.mousereleased(gameX, gameY, button, inputContext)
end

local function dispatchMouseMoved(x, y)
    local gameX, gameY = toPointerCoordinates(x, y)
    if state.screen == "options" then return OptionsScreen.mousemoved(gameX, gameY) end
    return Input.mousemoved(gameX, gameY, inputContext)
end

local function wantsTextInput()
    if state.screen == "options" then
        return OptionsScreen.wantsTextInput()
    elseif state.screen == "job_offer" and JobOfferScreen.wantsTextInput then
        return JobOfferScreen.wantsTextInput()
    elseif state.screen == "computer" and ComputerScreen.wantsTextInput then
        return ComputerScreen.wantsTextInput()
    elseif state.screen == "machine" and MachineScreen.wantsTextInput then
        return MachineScreen.wantsTextInput()
    elseif state.screen == "lan" then
        return LanScreen.wantsTextInput()
    elseif state.screen == "direct" then
        return DirectScreen.wantsTextInput()
    elseif state.screen == "workshop_remote" then
        return WorkshopRemoteScreen.wantsTextInput()
    end
    return false
end

syncMobileKeyboard = function()
    if mobileControls and mobileControls:isEnabled() and love.keyboard.setTextInput then
        love.keyboard.setTextInput(wantsTextInput())
    end
end

local function dispatchKeyPressed(key)
    if state.screen == "options" then
        local result = OptionsScreen.keypressed(key)
        syncMobileKeyboard()
        return result
    elseif (key == "o" and not wantsTextInput())
        or (key == "escape" and state.screen == "world")
    then
        return openOptions()
    elseif state.screen == "lan" then
        local result = LanScreen.keypressed(key)
        syncMobileKeyboard()
        return result
    elseif state.screen == "direct" then
        local result = DirectScreen.keypressed(key)
        syncMobileKeyboard()
        return result
    end
    if state.screen == "world"
        and MultiplayerHud.keypressed(key, multiplayerHudInfo())
    then
        return true
    end
    if warehouseControls:keypressed(key) then return true end
    return Input.keypressed(key, inputContext)
end

local function primaryMobileAction()
    if warehouseControls:ownsLift() then
        return "e",state.forklift.carriedPalletId and "DROP" or "PICK UP"
    end
    local movingMachine = state.cutter and state.cutter.moving
        or state.wrapper and state.wrapper.moving or state.windmill and state.windmill.moving
    if movingMachine then
        local localPlayerId = tonumber(World.player.id) or 1
        local ownsRelocation = state.palletJack and state.palletJack.operating
            and state.palletJack.operatorPlayerId == localPlayerId
        if ownsRelocation then return "e", "PLACE" end
        return "e", "BUSY"
    end
    local selected = World.getInteraction()
    if not selected then return "e", "USE" end
    if multiplayer:isClient() and selected.kind ~= "loadingBayDoor"
        and selected.kind ~= "truckCargoDoor"
        and selected.kind ~= "palletWorkOrder"
        and selected.kind ~= "forklift" and selected.kind ~= "palletRack"
        and not World.workshopResourceId(selected.kind)
    then
        return "e", "HOST"
    end
    local jackLabel = "DRIVE"
    if state.palletJack and state.palletJack.operating then
        local localPlayerId = tonumber(World.player.id) or 1
        if state.palletJack.operatorPlayerId ~= localPlayerId then
            jackLabel = "BUSY"
        else
            local candidateId = state.palletJack.candidatePalletId
                or World.networkPalletJackSnapshot(state).candidatePalletId
            jackLabel = state.palletJack.carriedPalletId and "LOWER"
                or candidateId and "LIFT" or "PARK"
        end
    end
    local labels = {
        customer = "JOB", computer = "PC", vendor = "TALK", loadingBayDoor = "DOOR",
        truckCargoDoor = "TRUCK", cutter = "CUTTER", skidWrapper = "WRAP",
        windmill = "PRESS", palletJack = jackLabel, palletWorkOrder = "VIEW",
        forklift = "DRIVE", palletRack = "SHELVES",
    }
    return "e", labels[selected.kind] or "USE"
end

local function extraMobileActions()
    local actions = {}
    if multiplayer:isClient() then
        local info = multiplayer:workshopInfo()
        if info and info.resourceId == "pallet_jack" then
            local movingMachine = state.cutter and state.cutter.moving
                or state.wrapper and state.wrapper.moving
                or state.windmill and state.windmill.moving
            if movingMachine then
                actions[#actions + 1] = { key = "q", label = "TURN" }
            else
                local carryingPallet = state.palletJack
                    and state.palletJack.carriedPalletId ~= nil
                if carryingPallet then
                    actions[#actions + 1] = { key = "l", label = "LOWER" }
                else
                    actions[#actions + 1] = { key = "f", label = "PARK" }
                    local selected = World.getInteraction()
                    local extraMachine = selected and selected.target
                        and selected.target.relocatable == false
                    local canRelocate = selected and (selected.kind == "cutter"
                        or selected.kind == "skidWrapper" or selected.kind == "windmill")
                        and not extraMachine
                    if not canRelocate and not extraMachine then
                        canRelocate = World.cutterNearby and World.cutterNearby(state)
                            or World.wrapperNearby and World.wrapperNearby(state)
                            or World.windmillNearby and World.windmillNearby(state)
                    end
                    if canRelocate then
                        actions[#actions + 1] = { key = "m", label = "MOVE" }
                    end
                end
            end
        end
        return actions
    end
    if state.cutter and state.cutter.moving or state.wrapper and state.wrapper.moving
        or state.windmill and state.windmill.moving
    then
        actions[#actions + 1] = { key = "q", label = "TURN" }
        return actions
    end
    if state.palletJack and state.palletJack.operating
        and state.palletJack.operatorPlayerId == 1
    then
        local carryingPallet = state.palletJack.carriedPalletId ~= nil
        if carryingPallet then
            actions[#actions + 1] = { key = "l", label = "LOWER" }
        else
            actions[#actions + 1] = { key = "f", label = "PARK" }
            local selected = World.getInteraction()
            local extraMachine = selected and selected.target
                and selected.target.relocatable == false
            local canRelocate = selected and (selected.kind == "cutter"
                or selected.kind == "skidWrapper" or selected.kind == "windmill")
                and not extraMachine
            if not canRelocate and not extraMachine then
                canRelocate = World.cutterNearby and World.cutterNearby(state)
                    or World.wrapperNearby and World.wrapperNearby(state)
                    or World.windmillNearby and World.windmillNearby(state)
            end
            if canRelocate then actions[#actions + 1] = { key = "m", label = "MOVE" } end
        end
    end
    return actions
end

local function runSmoke(startupTextureBytes, Sound)
    if not Smoke.requested() then return end
    if #state.assetErrors == 0 then
        startGame(Save.newGame(1), "smoke")
        -- Advance the transient visitor to reception so the smoke render
        -- includes the customer sprite and depth-sorting path.
        World.update(10, 0, 0, Assets, state)
    end
    Smoke.start({
        assets = Assets,
        assetErrorScreen = AssetErrorScreen,
        BayDoor = BayDoor,
        businessCalendar = BusinessCalendar,
        characterAssets = CharacterAssets,
        wrapper = Wrapper,
        computerScreen = ComputerScreen,
        workPhone = WorkPhone,
        workPhoneScreen = WorkPhoneScreen,
        Customer = Customer,
        config = Config,
        CutterPlacement = CutterPlacement,
        CutterZones = CutterZones,
        machine = Machine,
        serviceNetworkBeforeMachine = serviceNetworkBeforeMachine,
        machineFleet = MachineFleet,
        machineMaintenance = MachineMaintenance,
        machineScreen = MachineScreen,
        Navigation = Navigation,
        PalletJack = PalletJack,
        PalletState = PalletState,
        PalletLogistics = PalletLogistics,
        PaperWork = PaperWork,
        plateService = PlateService,
        pressScreen = PressScreen,
        Receiving = Receiving,
        procurement = Procurement,
        jobs = Jobs,
        jobOfferScreen = JobOfferScreen,
        jobService = JobService,
        input = Input,
        inputContext = inputContext,
        save = Save,
        SaveEditor = require("src.save_editor"),
        Settings = Settings,
        shop = Shop,
        state = state,
        State = State,
        title = TitleScreen,
        Technician = Technician,
        Truck = Truck,
        truckInventoryScreen = TruckInventoryScreen,
        vendorScreen = VendorScreen,
        palletWorkOrderScreen = inputContext.palletWorkOrderScreen,
        world = World,
        app = App,
        worldRenderer = WorldRenderer,
        windmill = Windmill,
        createWorkshopAuthority = createWorkshopAuthority,
        windmillNetworkView = windmillView,
        wrapperNetworkView = wrapperSnapshotView,
        windmillLiveNetworkView = function() return windmillView(activeWindmillRemote) end,
        WindmillPlacement = WindmillPlacement,
        startupTextureBytes = startupTextureBytes,
        Sound = Sound,
    })
    if spriteLabActive then SpriteMotionLab.enter(CharacterAssets) end
end

function App.load()
    ComputerScreen.configureWarehouse({enabled=Config.warehouse.enabled,
        firstStorageOnly=Config.warehouse.firstStorageOnly,
        command=function(intent)
            if multiplayer:isClient() then return false,"Use the host-authorized office screen." end
            if multiplayer:isHost() then
                local ok,message=commandLocalWorkshop("office_action",{officeIntent=intent})
                return ok,ok and "completed" or "blocked",message
            end
            return OfficeAuthority.command({state=state,world=World,save=saveCurrent,
                warehouseEnabled=Config.warehouse.enabled,
                warehouseFirstStorageOnly=Config.warehouse.firstStorageOnly})
                .perform({},warehousePlayer(),{officeIntent=intent})
        end})
    local Sound = require("src.sound")
    local acceptanceHost, acceptanceHostError = AcceptanceHostBootstrap.plan({
        osName = love.system and love.system.getOS and love.system.getOS() or nil,
        getenv = os.getenv,
    })
    if acceptanceHostError then
        error("Acceptance host bootstrap refused: " .. acceptanceHostError)
    end
    if acceptanceHost and Smoke.requested() then
        error("Acceptance host bootstrap cannot run at the same time as the smoke suite.")
    end
    acceptanceHostPlan = acceptanceHost
    acceptanceHostRelocationSignature = nil
    love.graphics.setDefaultFilter("nearest", "nearest")
    App.settings = Settings.load()
    Settings.applyDisplay(App.settings)
    mobileControls = MobileControls.new({
        layout = App.settings.controlLayout,
        toGame = function(x, y) return Viewport.toGame(x, y, Config.baseWidth, Config.baseHeight) end,
        pressKey = dispatchKeyPressed,
        releaseKey = function(key) Input.keyreleased(key, inputContext) end,
        pressPointer = dispatchMousePressed,
        movePointer = dispatchMouseMoved,
        releasePointer = dispatchMouseReleased,
        gameplayActive = function() return state.screen == "world" end,
        gestureActive = function()
            return App.mobileCamera and App.mobileCamera:isEnabled() and not spriteLabActive
                and not (state.screen == "options" and OptionsScreen.isControlsTab())
        end,
        primaryAction = primaryMobileAction,
        extraActions = extraMobileActions,
        afterInput = syncMobileKeyboard,
        beginGesture = function(x, y, distance)
            if App.mobileCamera then App.mobileCamera:beginGesture(x, y, distance) end
        end,
        updateGesture = function(x, y, distance)
            if App.mobileCamera then App.mobileCamera:updateGesture(x, y, distance) end
        end,
        endGesture = function()
            if App.mobileCamera then App.mobileCamera:endGesture() end
        end,
    })
    App.mobileCamera = require("src.mobile_camera").new({
        enabled = mobileControls:isEnabled(),
        baseWidth = Config.baseWidth,
        baseHeight = Config.baseHeight,
    })
    controller = Controller.new({
        pressKey = dispatchKeyPressed,
        releaseKey = function(key) Input.keyreleased(key, inputContext) end,
        pressPointer = dispatchGameMousePressed,
        releasePointer = dispatchGameMouseReleased,
        screenInfo = function() return state.screen, state.machineType end,
        menuAction = openOptions,
    })
    Input.setMobileMovementProvider(function()
        if mobileControls then return mobileControls:movement() end
        return 0, 0
    end)
    if acceptanceHost then
        love.filesystem.setIdentity(acceptanceHost.identity)
    elseif Smoke.requested() then
        love.filesystem.setIdentity("the-picture-shop-smoke")
    end
    Assets.load()
    CharacterAssets.load()
    spriteLabActive = Smoke.spriteLabRequested()
    local startupTextureBytes = Assets.textureBytes() + CharacterAssets.textureBytes()
    local assetsHealthy, assetFailures = Assets.assertHealthy()
    local charactersHealthy, characterFailures = CharacterAssets.assertHealthy()
    state.assetErrors = AssetErrorScreen.normalize(
        assetsHealthy and nil or assetFailures,
        charactersHealthy and nil or characterFailures)
    if #state.assetErrors == 0 then
        World.load()
        TitleScreen.enter(startGame, openLocalPlay,
            CryptoNative.productionReady == true and openDirectPlay or nil)
    else
        state.screen = "asset_error"
        state.message = string.format("Startup stopped: %d required asset error(s).", #state.assetErrors)
    end
    Machine.setOutputResolver(function(targetState, pallet)
        return World.findCutterOutput(targetState, Assets, pallet and pallet.id)
    end)

    runSmoke(startupTextureBytes, Sound)
    App.sound = Sound.new({
        state = state,
        world = World,
        machine = Machine,
        wrapper = Wrapper,
        windmill = Windmill,
    })
    local soundHealthy, soundErrors = App.sound:initialize()
    Settings.applyAudio(App.settings, App.sound)
    if Smoke.requested() and not soundHealthy then
        error("Sound startup failed: " .. table.concat(soundErrors or {}, "; "))
    end
    if acceptanceHost then
        if #state.assetErrors > 0 then
            error("Acceptance host bootstrap stopped because required assets failed validation.")
        end
        local hosted, hostError = startLanHost(
            acceptanceHost.slot, acceptanceHost.playerName)
        if not hosted then
            error("Acceptance host bootstrap could not start LAN hosting: "
                .. tostring(hostError))
        end
        if acceptanceHost.screen == "computer" then
            ComputerScreen.enter(state)
            state.screen = "computer"
            print("[ACCEPTANCE HOST] SCREEN computer")
        end
        print(string.format("[ACCEPTANCE HOST] READY identity=%s slot=%d address=%s:%d",
            acceptanceHost.identity, acceptanceHost.slot,
            tostring(multiplayer.localAddress or "unknown"),
            tonumber(multiplayer.port) or 22122))
        io.flush()
    end
    print("[PICTURE SHOP] Startup complete")
end

local function showConnectionError(message, stopReason)
    local direct = multiplayer.networkKind == "direct"
    if not direct and tostring(stopReason or ""):match("^Invalid") then
        -- Malformed authoritative state is not a transient link failure. Do
        -- not loop back into the same incompatible or unsafe snapshot.
        lanReconnect:cancel(false)
        lanReconnectArmed = false
    end
    local cleaned, cleanupError = multiplayer:stop(stopReason or "Connection error")
    if not cleaned then
        if direct then
            state.screen = "direct"
            DirectScreen.showCleanupError(cleanupError)
        else
            state.screen = "lan"
            LanScreen.showError(cleanupError)
        end
        syncMobileKeyboard()
        return
    end
    if direct then
        openDirectPlay(lastDirectSlot)
        DirectScreen.showError(message or "The Direct connection ended.")
    else
        state.screen = "lan"
        LanScreen.showError(message or "The LAN connection ended.")
        startLanSearch()
    end
    syncMobileKeyboard()
end

local FATAL_LAN_RECONNECT_ERRORS = {
    invalid_join = true,
    shop_full = true,
    kicked = true,
    protocol_mismatch = true,
    message_not_allowed = true,
}

local function handleLanReconnectFailure(message)
    local snapshot = lanReconnect:snapshot()
    if snapshot.active and snapshot.state == "waiting" then
        -- An error and its following disconnect may arrive in the same drain.
        -- The first event already scheduled the next attempt.
        return true
    end
    if not snapshot.active and not lanReconnectArmed then return false end
    local cleaned, cleanupError = multiplayer:stop("Preparing LAN reconnect")
    if not cleaned then
        lanReconnect:cancel(false)
        lanReconnectArmed = false
        state.screen = "lan"
        LanScreen.showError(cleanupError)
        startLanSearch()
        return true
    end
    local scheduled, scheduleError
    if snapshot.active and snapshot.state == "connecting" then
        scheduled, scheduleError = lanReconnect:failed(message)
    elseif not snapshot.active then
        scheduled, scheduleError = lanReconnect:begin(message)
    else
        return true
    end
    clearWorkshopAuthority("transport_failed")
    WorkshopRemoteScreen.clear()
    state.screen = "lan"
    startLanSearch()
    if scheduled then
        LanScreen.showReconnect(lanReconnect:snapshot())
    else
        lanReconnectArmed = false
        LanScreen.showError(scheduleError or
            "Automatic reconnect ended. Choose a found shop or enter its address.")
    end
    syncMobileKeyboard()
    return true
end

local function updateLanConvenience(dt)
    lanDiscovery:update(dt)
    if state.screen == "lan" and not lanReconnect:isActive() then
        local _, discoveryMessage = lanDiscovery:status()
        LanScreen.setDiscovery(lanDiscovery:results(), discoveryMessage)
    end
    local attempt = lanReconnect:update(dt)
    if not attempt then
        if state.screen == "lan" and lanReconnect:isActive() then
            LanScreen.showReconnect(lanReconnect:snapshot())
        end
        return
    end
    local cleaned, cleanupError = multiplayer:stop("Starting LAN reconnect attempt")
    local connected, connectError = false, cleanupError
    if cleaned then
        connected, connectError = startLanClient(
            attempt.address, attempt.playerName, true)
    end
    if not connected then
        local scheduled, exhaustedMessage = lanReconnect:failed(connectError)
        startLanSearch()
        if not scheduled then
            lanReconnectArmed = false
            state.screen = "lan"
            LanScreen.showError(exhaustedMessage)
            return
        end
    end
    state.screen = "lan"
    LanScreen.showReconnect(lanReconnect:snapshot())
end

local function handleMultiplayerEvents()
    for _, event in ipairs(multiplayer:drainEvents()) do
        if event.type == "ready" then
            warehouseControls:resolve(warehousePendingIntent,false,"The warehouse connection was restarted.")
            warehousePendingIntent=nil
            warehouseControls:reset("The warehouse connection was restarted.")
            Machine.resetNetworkReplica()
            if not State.applySharedSnapshot(state, event.state) then
                showConnectionError(
                    "The host sent a shop snapshot this build could not apply.",
                    "Invalid shared shop snapshot")
            else
                if multiplayer:isClient() and multiplayer.networkKind == "lan" then
                    lanReconnectArmed = true
                    lanReconnect:succeeded()
                    lanDiscovery:stop()
                end
                World.load(event.spawn)
                state.screen = "world"
                state.message = "Joined the host shop. Movement, doors, reception, office, cutter, wrapper, and Windmill controls are live."
                DirectScreen.leave()
            end
            syncMobileKeyboard()
        elseif event.type == "shop_state" then
            if not State.applySharedUpdate(state, event.state) then
                showConnectionError(
                    "The host sent a shop update this build could not apply.",
                    "Invalid durable shop update")
            end
        elseif event.type == "forklift_state" then
            local applied,reason=Forklift.applySnapshot(state,event.forklift,Config.forklift)
            if not applied and reason~="awaiting_durable" and reason~="operator_conflict" then
                state.message="Forklift update waiting for a fresh host state: "..tostring(reason)
            end
        elseif event.type == "pallet_jack_state" then
            local applied, applyError = World.applyNetworkPalletJackSnapshot(
                state, event.jack, event.machines)
            if not applied and applyError ~= "awaiting_durable" then
                showConnectionError(
                    "The host sent a pallet-jack update this build could not apply.",
                    "Invalid pallet-jack update")
            end
        elseif event.type == "visitor_state" then
            if not World.applyVisitorSnapshot(event.customer, event.vendor) then
                showConnectionError(
                    "The host sent a visitor update this build could not apply.",
                    "Invalid visitor update")
            end
        elseif event.type == "environment_state" then
            if not World.applyEnvironmentSnapshot(event.bayDoor, event.truck) then
                showConnectionError(
                    "The host sent an environment update this build could not apply.",
                    "Invalid environment update")
            end
        elseif event.type == "interaction_result" then
            state.message = tostring(event.message or (event.accepted
                and "The host accepted the interaction."
                or "The host rejected the interaction."))
        elseif event.type == "workshop_grant" then
            state.message = tostring(event.message or (event.granted
                and "Workshop control granted." or "Workshop control was not granted."))
            if event.granted then
                local machineBase, machineId = MachineResource.parse(event.resourceId)
                if machineBase == "skid_wrapper" and event.view then
                    Wrapper.select(machineId, state)
                    Wrapper.applySnapshot(event.view, state)
                elseif machineBase == "cutter" and event.view then
                    Machine.select(machineId, state)
                    Machine.applyNetworkView(event.view)
                end
                if event.resourceId == "warehouse" then
                    if warehousePendingIntent then
                        local sent,message=multiplayer:requestWorkshopCommand("warehouse_action",
                            {warehouseIntent=warehousePendingIntent})
                        if not sent then
                            warehouseControls:resolve(warehousePendingIntent,false,message)
                            warehousePendingIntent=nil
                            state.message=message
                            multiplayer:releaseWorkshop("cancelled")
                        end
                    end
                elseif event.resourceId == "pallet_jack" then
                    state.screen = "world"
                else
                    event.useHostLayout = true
                    WorkshopRemoteScreen.enter(event, state)
                end
            end
            if not event.granted and event.resourceId=="warehouse" then
                warehouseControls:resolve(warehousePendingIntent,false,event.message)
                warehousePendingIntent=nil
            end
            syncMobileKeyboard()
        elseif event.type == "workshop_result" then
            if event.action=="warehouse_action" then
                warehouseControls:resolve(warehousePendingIntent,event.accepted,event.message)
                if event.accepted and warehousePendingIntent and warehousePendingIntent.kind=="release" then
                    multiplayer:releaseWorkshop("closed")
                elseif not event.accepted and event.resourceId=="warehouse"
                    and warehousePendingIntent and warehousePendingIntent.kind=="operate" then
                    multiplayer:releaseWorkshop("cancelled")
                end
                warehousePendingIntent=nil
            end
            local machineBase, machineId = MachineResource.parse(event.resourceId)
            if machineBase == "skid_wrapper" and event.view then
                Wrapper.select(machineId, state)
                Wrapper.applySnapshot(event.view, state)
            elseif machineBase == "cutter" and event.view then
                Machine.select(machineId, state)
                Machine.applyNetworkView(event.view)
            end
            if event.resourceId ~= "pallet_jack" and event.resourceId ~= "warehouse" then
                WorkshopRemoteScreen.applyResult(event)
            end
            state.message = tostring(event.message or (event.accepted
                and "Workshop action completed." or "Workshop action was rejected."))
            if event.accepted and event.resourceId == "reception_customer" then
                multiplayer:releaseWorkshop("closed")
                WorkshopRemoteScreen.clear()
                state.screen = "world"
            elseif event.accepted and event.resourceId == "vendor"
                and event.action == "dismiss"
            then
                multiplayer:releaseWorkshop("closed")
                WorkshopRemoteScreen.clear()
                state.screen = "world"
            elseif event.accepted and event.resourceId == "truck"
                and event.action == "close_truck"
            then
                multiplayer:releaseWorkshop("closed")
                WorkshopRemoteScreen.clear()
                state.screen = "world"
            elseif event.accepted and event.resourceId == "pallet_jack"
                and event.action == "park_jack"
            then
                multiplayer:releaseWorkshop("closed")
            end
            syncMobileKeyboard()
        elseif event.type == "workshop_snapshot" then
            if not Wrapper.applySnapshot(event.wrapper, state) then
                showConnectionError(
                    "The host sent a workshop update this build could not apply.",
                    "Invalid workshop runtime")
            else
                WorkshopRemoteScreen.applySnapshot(event)
            end
        elseif event.type == "cutter_state" then
            if WorkshopRemoteScreen.leaseResourceId == event.resourceId then
                local _, machineId = MachineResource.parse(event.resourceId)
                Machine.select(machineId, state)
                Machine.applyNetworkView(event.view)
            end
            if WorkshopRemoteScreen.applyCutterSnapshot then
                WorkshopRemoteScreen.applyCutterSnapshot(event)
            end
        elseif event.type == "windmill_state" then
            if WorkshopRemoteScreen.applyWindmillSnapshot then
                WorkshopRemoteScreen.applyWindmillSnapshot(event)
            end
        elseif event.type == "wrapper_state" then
            if WorkshopRemoteScreen.leaseResourceId == event.resourceId then
                local _, machineId = MachineResource.parse(event.resourceId)
                Wrapper.select(machineId, state)
                Wrapper.applySnapshot(event.view, state)
                WorkshopRemoteScreen.applyWrapperSnapshot(event)
            end
        elseif event.type == "workshop_lost" then
            warehouseControls:resolve(warehousePendingIntent,false,event.message or "Warehouse control disconnected.")
            warehousePendingIntent=nil
            warehouseControls:reset(event.message or "Warehouse control disconnected.")
            if state.screen == "workshop_remote" then
                WorkshopRemoteScreen.clear()
                state.screen = "world"
            end
            if event.resourceId == "pallet_jack" then
                local jack = PalletJack.ensure(state, Config.palletJack)
                local localId = tonumber(World.player.id)
                if jack.operatorPlayerId == localId then
                    PalletJack.forceRelease(state, Config.palletJack, localId)
                end
            elseif event.resourceId == "warehouse" then
                local localId=tonumber(World.player.id)
                if state.forklift and state.forklift.operatorPlayerId==localId then
                    World.forceReleaseForklift(World.player,state)
                end
            end
            state.message = tostring(event.message or "The host released that workshop control.")
            syncMobileKeyboard()
        elseif event.type == "host_started" then
            if event.networkKind == "direct" then
                state.message = "Direct host active. Each invited worker needs separate approval before any shop data is shared."
            else
                local address = event.address or "the host device's Wi-Fi IPv4"
                state.message = "LAN host: nearby workers can find this shop, or join manually at "
                    .. tostring(address) .. ":" .. tostring(event.port or 22122) .. "."
            end
        elseif event.type == "approval_waiting" then
            DirectScreen.setMessage(event.message
                or "Encrypted request sent. Waiting for the host to approve this player.",
                "connecting")
        elseif event.type == "join_requested" then
            MultiplayerHud.open(multiplayerHudInfo())
            state.message = tostring(event.name or "A player")
                .. " requested access. Choose APPROVE or DENY in the Players panel."
        elseif event.type == "join_cancelled" then
            state.message = "The pending Direct player disconnected. That invitation is now closed."
        elseif event.type == "join_rejected" then
            state.message = "Join declined. The old Direct codes can no longer be used."
        elseif event.type == "join_expired" then
            state.message = "The Direct join request expired. Create fresh codes to try again."
        elseif event.type == "player_joined" then
            state.message = tostring(event.name or "A worker") .. " joined the shop."
        elseif event.type == "player_left" then
            if workshopAuthority then
                workshopAuthority:cleanupPlayer({ id = event.playerId }, "disconnected",
                    { state = state })
            end
            local label = multiplayer.networkKind == "direct" and "Direct" or "LAN"
            state.message = tostring(event.name or "A worker") .. " left the " .. label .. " shop."
        elseif event.type == "player_kicked" then
            state.message = tostring(event.name or "A worker") .. " was removed by the host."
        elseif event.type == "direct_closed" then
            local message = tostring(event.message or
                "This Direct invitation is closed. Create fresh codes before reconnecting.")
            multiplayer:stop("Direct invitation closed")
            clearWorkshopAuthority("direct_invitation_closed")
            MultiplayerHud.reset()
            state.message = message
        elseif event.type == "disconnected" then
            -- A host transport failure is terminal too. Release every workshop
            -- lease before leaving gameplay so its safety callback stops the
            -- Windmill and persists that stopped state.
            clearWorkshopAuthority("transport_failed")
            WorkshopRemoteScreen.clear()
            local lanClient = multiplayer:isClient() and multiplayer.networkKind == "lan"
            if not lanClient or not handleLanReconnectFailure(
                event.message or "The host connection ended.")
            then
                showConnectionError(event.message or "The host connection ended.", "Host disconnected")
            end
        elseif event.type == "error" then
            local lanClient = multiplayer:isClient() and multiplayer.networkKind == "lan"
            if lanClient and FATAL_LAN_RECONNECT_ERRORS[event.code] then
                lanReconnectArmed = false
                lanReconnect:cancel(false)
            end
            local addingDirectWorker = state.screen == "direct"
                and multiplayer:isHost() and multiplayer.networkKind == "direct"
                and DirectScreen.inviteOnly == true
            if addingDirectWorker then
                -- A joined worker can fail while the host is exchanging a
                -- different worker's invitation.  Keep both the authoritative
                -- shop and the fresh invitation alive; the Session/composite
                -- transport isolates and retires only the failed link.
                DirectScreen.setMessage(
                    "One existing worker link ended; this fresh invitation is still active.")
            elseif state.screen == "lan" and lanClient and lanReconnect:isActive() then
                handleLanReconnectFailure(event.message or "The host did not answer.")
            elseif state.screen == "lan" or state.screen == "direct" then
                showConnectionError(event.message or "The multiplayer connection failed.",
                    "Connection error")
            else
                local label = multiplayer.networkKind == "direct" and "Direct" or "LAN"
                state.message = label .. ": " .. tostring(event.message or "network error")
            end
        end
    end
end

local function performWorkshopRequest(player, operation, payload)
    if not workshopAuthority then
        return {
            accepted = false, code = "unavailable",
            message = "Workshop authority is unavailable on the host device.", revision = 0,
        }
    end
    if operation == "workshop_acquire" then
        local revision = workshopAuthority:resourceRevision(payload.resourceId) or 0
        if payload.expectedRevision ~= revision then
            return {
                accepted = false, code = "revision_conflict",
                message = "That workshop changed; try the control again.", revision = revision,
            }
        end
        return workshopAuthority:acquire(player, {
            requestId = payload.requestId,
            resourceId = payload.resourceId,
        }, { state = state })
    elseif operation == "workshop_command" then
        local arguments = {}
        if payload.amount ~= nil then arguments.amount = payload.amount end
        if payload.callId ~= nil then arguments.callId = payload.callId end
        if payload.officeIntent ~= nil then arguments.officeIntent = payload.officeIntent end
        if payload.warehouseIntent ~= nil then arguments.warehouseIntent = payload.warehouseIntent end
        if payload.itemIndex ~= nil then arguments.itemIndex = payload.itemIndex end
        if payload.machineIndex ~= nil then arguments.machineIndex = payload.machineIndex end
        if payload.placementCell ~= nil then arguments.placementCell = payload.placementCell end
        if payload.jobId ~= nil then arguments.jobId = payload.jobId end
        if payload.palletId ~= nil then arguments.palletId = payload.palletId end
        if payload.plateId ~= nil then arguments.plateId = payload.plateId end
        if payload.setupTask ~= nil then arguments.setupTask = payload.setupTask end
        if payload.setupAction ~= nil then arguments.setupAction = payload.setupAction end
        if payload.programIndex ~= nil then arguments.programIndex = payload.programIndex end
        if payload.gaugeCentiInch ~= nil then
            arguments.gaugeCentiInch = payload.gaugeCentiInch
        end
        if payload.clamp ~= nil then arguments.clamp = payload.clamp end
        if payload.barrierClear ~= nil then arguments.barrierClear = payload.barrierClear end
        if payload.enabled ~= nil then arguments.enabled = payload.enabled end
        local result = workshopAuthority:command(player, {
            requestId = payload.commandId,
            resourceId = payload.resourceId,
            leaseId = payload.leaseId,
            action = payload.action,
            args = arguments,
            expectedRevision = payload.expectedRevision,
        }, { state = state })
        if acceptanceHostPlan and payload.resourceId == "pallet_jack" then
            print(string.format(
                "[ACCEPTANCE HOST] COMMAND action=%s accepted=%s code=%s cutter=%s wrapper=%s windmill=%s",
                tostring(payload.action), tostring(result.accepted), tostring(result.code),
                tostring(state.cutter and state.cutter.moving == true),
                tostring(state.wrapper and state.wrapper.moving == true),
                tostring(state.windmill and state.windmill.moving == true)))
            io.flush()
        end
        return result
    elseif operation == "workshop_release" then
        return workshopAuthority:release(player, {
            requestId = payload.requestId,
            resourceId = payload.resourceId,
            leaseId = payload.leaseId,
            reason = payload.reason,
        }, { state = state })
    end
    return {
        accepted = false, code = "not_allowed",
        message = "That workshop operation is not allowed.", revision = 0,
    }
end

local function updateMultiplayer(dt, inputX, inputY)
    if not multiplayer:isActive() then return end
    if multiplayer:isHost() then registerInstalledMachineResources(workshopAuthority) end
    if workshopAuthority and localWorkshopLease then
        workshopAuthority:touchPlayer(localAuthorityPlayer())
    end
    multiplayer:update(dt, {
        localPlayer = World.player,
        inputX = inputX or 0,
        inputY = inputY or 0,
        moveRemote = function(player, moveDt, moveX, moveY)
            World.updateRemotePlayer(player, moveDt, moveX, moveY, Assets, state)
        end,
        resolveGuestSpawn = function(hostX, hostY, guestIndex, players)
            return World.resolveNetworkSpawn(hostX, hostY, guestIndex, Assets, state, players)
        end,
        getShopSnapshot = function()
            return {
                state = SaveSchema.snapshot(state),
                player = World.snapshot(),
            }
        end,
        getVisitorSnapshot = function()
            return {
                customer = World.customerSnapshot(),
                vendor = World.vendorSnapshot(),
            }
        end,
        getEnvironmentSnapshot = function()
            return World.environmentSnapshot()
        end,
        getPalletJackSnapshot = function()
            return World.networkPalletJackSnapshot(state)
        end,
        getForkliftSnapshot=function() return Forklift.snapshot(state,Config.forklift) end,
        getMachinePoseSnapshot = function()
            return World.networkMachinePoseSnapshot(state)
        end,
        getWorkshopSnapshot = function()
            return {
                resources = workshopAuthority and workshopAuthority:snapshot() or {},
                wrapper = wrapperSnapshotView(),
            }
        end,
        getCutterSnapshot = function()
            local snapshots = {}
            for _, unit in ipairs(MachineFleet.installedUnits(state, "polar_115")) do
                local resourceId = MachineResource.forUnit("cutter", unit.id)
                snapshots[#snapshots + 1] = {
                    resourceId = resourceId,
                    resourceRevision = workshopAuthority
                        and workshopAuthority:resourceRevision(resourceId) or 0,
                    view = withWorkshopUnit("cutter", unit.id, resourceId, function()
                        return cutterMaintenanceAuthority.view(
                            machineRemoteSessions[resourceId], true)
                    end),
                }
            end
            return snapshots
        end,
        getWindmillSnapshot = function()
            local snapshots = {}
            for _, unit in ipairs(MachineFleet.installedUnits(state, "heidelberg_10x15")) do
                local resourceId = MachineResource.forUnit("windmill", unit.id)
                snapshots[#snapshots + 1] = {
                    resourceId = resourceId,
                    resourceRevision = workshopAuthority
                        and workshopAuthority:resourceRevision(resourceId) or 0,
                    view = withWorkshopUnit("windmill", unit.id, resourceId, function()
                        return windmillView(machineRemoteSessions[resourceId])
                    end),
                }
            end
            return snapshots
        end,
        getWrapperSnapshots = function()
            local snapshots = {}
            for _, unit in ipairs(MachineFleet.installedUnits(state, "skid_wrapper")) do
                local resourceId = MachineResource.forUnit("skid_wrapper", unit.id)
                snapshots[#snapshots + 1] = {
                    resourceId = resourceId,
                    resourceRevision = workshopAuthority
                        and workshopAuthority:resourceRevision(resourceId) or 0,
                    view = withWorkshopUnit("skid_wrapper", unit.id, resourceId, function()
                        return wrapperMaintenanceAuthority.view(
                            machineRemoteSessions[resourceId], false)
                    end),
                }
            end
            return snapshots
        end,
        performWorkshop = performWorkshopRequest,
        touchWorkshop = function(player)
            if workshopAuthority then workshopAuthority:touchPlayer(player) end
        end,
        updateWorkshop = function()
            if not workshopAuthority then return end
            local events = workshopAuthority:update({ state = state })
            for _, event in ipairs(events) do
                if localWorkshopLease and event.leaseId == localWorkshopLease.leaseId then
                    localWorkshopLease = nil
                end
            end
        end,
        performInteraction = function(player, targetKind, desiredState)
            return World.performNetworkInteraction(player, state, targetKind, desiredState)
        end,
    })
    handleMultiplayerEvents()
    if acceptanceHostPlan and multiplayer:isHost() then
        local jack = PalletJack.ensure(state, Config.palletJack)
        local signature = table.concat({
            tostring(jack.operating == true),
            tostring(jack.operatorPlayerId or "none"),
            tostring(state.cutter and state.cutter.moving == true),
            tostring(state.wrapper and state.wrapper.moving == true),
            tostring(state.windmill and state.windmill.moving == true),
        }, ":")
        if signature ~= acceptanceHostRelocationSignature then
            acceptanceHostRelocationSignature = signature
            print(string.format(
                "[ACCEPTANCE HOST] RELOCATION jack=%s owner=%s cutter=%s wrapper=%s windmill=%s",
                tostring(jack.operating == true), tostring(jack.operatorPlayerId or "none"),
                tostring(state.cutter and state.cutter.moving == true),
                tostring(state.wrapper and state.wrapper.moving == true),
                tostring(state.windmill and state.windmill.moving == true)))
            io.flush()
        end
    end
    if multiplayer:isClient() then
        local jack = PalletJack.ensure(state, Config.palletJack)
        if jack.operating and jack.operatorPlayerId ~= World.player.id then
            local operatorX, operatorY = PalletJack.operatorPosition(
                state, Config.palletJack)
            for _, player in ipairs(multiplayer:remotePlayers()) do
                if player.id == jack.operatorPlayerId then
                    player.x, player.y = operatorX, operatorY
                    player.moving = jack.moving
                    player.facing = (jack.direction == "northeast"
                        or jack.direction == "east" or jack.direction == "southeast")
                        and 1 or -1
                    break
                end
            end
        end
    end
end

local function directScreenError(message, keepActiveHost)
    local cleaned, cleanupError = closeDirectConnection()
    if not cleaned then
        state.screen = "direct"
        DirectScreen.showCleanupError(cleanupError)
        if syncMobileKeyboard then syncMobileKeyboard() end
        return
    end
    if keepActiveHost and multiplayer:isHost() and multiplayer.networkKind == "direct" then
        DirectScreen.leave()
        state.screen = "world"
        state.message = tostring(message or "The additional Direct invitation could not start.")
        if syncMobileKeyboard then syncMobileKeyboard() end
        return
    end
    state.screen = "direct"
    DirectScreen.showError(message or "The Direct connection could not start.")
    if syncMobileKeyboard then syncMobileKeyboard() end
end

local function updateDirectConnection()
    local connection = directConnection
    if not connection then return end
    local connectionState, connectionError = connection:update()
    if connectionState == "failed" then
        directScreenError(connectionError,
            pendingDirectSession and pendingDirectSession.kind == "additional_host")
        return
    end
    if connectionState ~= "ready" then return end

    local transportFactory, roleOrError = connection:takeTransportFactory()
    if not transportFactory then
        directScreenError(roleOrError,
            pendingDirectSession and pendingDirectSession.kind == "additional_host")
        return
    end
    local pending = pendingDirectSession
    directConnection = nil
    pendingDirectSession = nil
    connection:close()
    if not pending or pending.role ~= roleOrError then
        local disposed = disposeDirectTransportFactory(transportFactory)
        if not disposed then
            DirectScreen.showCleanupError(
                "The Direct connection role failed and its cleanup could not be verified; restart the game.")
            return
        end
        directScreenError("The Direct connection role could not be verified.",
            pending and pending.kind == "additional_host")
        return
    end

    if roleOrError == "host" then
        if pending.kind == "additional_host" then
            if not directHostComposite or type(directHostComposite.attachFactory) ~= "function" then
                if not disposeDirectTransportFactory(transportFactory) then
                    DirectScreen.showCleanupError(
                        "The additional Direct link could not be attached or cleaned up; restart the game.")
                    return
                end
                directScreenError("The active Direct host cannot accept another encrypted link.", true)
                return
            end
            local attached, attachError = directHostComposite:attachFactory(
                transportFactory, { channels = 3 })
            if not attached then
                directScreenError(attachError or
                    "The additional encrypted Direct link could not start.", true)
                return
            end
            DirectScreen.leave()
            state.screen = "world"
            state.message = "The new encrypted link is ready. Approve that worker in the Players panel when requested."
            if syncMobileKeyboard then syncMobileKeyboard() end
            return
        end

        local compositeFactory, compositeController = DirectCompositeTransport.newFactory({
            maxGuests = 3,
            channels = 3,
        })
        if not compositeFactory or not compositeController then
            if not disposeDirectTransportFactory(transportFactory) then
                DirectScreen.showCleanupError(
                    "The first Direct link could not be attached or cleaned up; restart the game.")
                return
            end
            directScreenError(compositeController or
                "The multi-worker Direct host transport could not start.")
            return
        end
        -- Retain the controller before attachment so any unverified cleanup
        -- remains owned and blocks another invitation until process restart.
        directHostComposite = compositeController
        local attached, attachError = compositeController:attachFactory(
            transportFactory, { channels = 3 })
        if not attached then
            local cleaned, cleanupError = closeDirectHostComposite()
            if not cleaned then
                DirectScreen.showCleanupError(cleanupError)
                return
            end
            directScreenError(attachError or "The first encrypted Direct link could not start.")
            return
        end
        workshopAuthority = createWorkshopAuthority()
        localWorkshopLease = nil
        localWorkshopRequestId = 0
        activeCutterRemote = nil
        activeWrapperRemote = nil
        activeWindmillRemote = nil
        local hosted, hostError = multiplayer:startHost({
            port = 22122,
            name = pending.name,
            character = Config.player.character,
            networkKind = "direct",
            transportFactory = compositeFactory,
        })
        if not hosted then
            local cleaned, cleanupError = closeDirectHostComposite()
            clearWorkshopAuthority("host_start_failed")
            if not cleaned then
                DirectScreen.showCleanupError(cleanupError)
                return
            end
            directScreenError(hostError)
            return
        end
        local started, startError = startGame(pending.payload, pending.saveMode)
        if not started then
            multiplayer:stop("Direct host save could not be opened")
            local cleaned, cleanupError = closeDirectHostComposite()
            clearWorkshopAuthority("host_save_failed")
            if not cleaned then
                DirectScreen.showCleanupError(cleanupError)
                return
            end
            directScreenError(startError)
            return
        end
        DirectScreen.leave()
        if isAndroidPlatform() and love.window and love.window.setDisplaySleepEnabled then
            love.window.setDisplaySleepEnabled(false)
        end
        state.message = "Direct host active. Each worker uses a fresh invitation and must be approved before joining."
    else
        local joined, joinError = multiplayer:startClient("127.0.0.1:22122", {
            name = pending.name,
            character = Config.player.character,
            networkKind = "direct",
            transportFactory = transportFactory,
        })
        if not joined then
            directScreenError(joinError)
            return
        end
        state.screen = "direct"
        DirectScreen.setMessage(
            "Encrypted request is ready. Waiting for the host to approve this player.",
            "connecting")
        if syncMobileKeyboard then syncMobileKeyboard() end
    end
end

serviceNetworkBeforeMachine = function(dt, targetState, networkService, windmillService)
    networkService()
    local machineDurable = Machine.updateAll(dt, targetState)
    local windmillChanged, windmillDurable = false, false
    if windmillService then
        windmillChanged, windmillDurable = windmillService(dt, targetState)
    end
    return machineDurable or windmillDurable, windmillChanged, windmillDurable
end

function App.update(dt)
    if controller then controller:update(dt) end
    if spriteLabActive then SpriteMotionLab.update(dt, CharacterAssets); return end
    updateDirectConnection()
    updateLanConvenience(dt)
    Machine.setMultiplayerSingleControl(multiplayer:isActive())
    local networkInputX, networkInputY = 0, 0
    local simulationScreen = state.screen == "options" and state.optionsReturnScreen
        or state.screen
    local simulationActive = simulationScreen ~= "title"
        and simulationScreen ~= "lan" and simulationScreen ~= "direct"
        and simulationScreen ~= "asset_error"
    if not multiplayer:isClient() and simulationActive then
        local calendarChanged = BusinessCalendar.update(state, dt)
        local emailArrived = JobService.updateClientEmails(state)
        local technicianChanged = MachineMaintenance.updateTechnician(state)
        if state.screen~="world" and state.forklift and state.forklift.operating
            and state.forklift.operatorPlayerId==1 then
            World.updateNetworkForklift(World.player,0,0,0,Assets,state)
        end
        local warehouseChanged=World.updateWarehouse(dt,state,Assets)
        local phoneChanged = WorkPhone.update(state)
        if calendarChanged or emailArrived or technicianChanged or phoneChanged then saveCurrent() end
        warehouseSaveClock=warehouseSaveClock+dt
        if warehouseChanged and multiplayer:isHost() then multiplayer:markShopDirty() end
        if warehouseSaveClock>=1 and (warehouseChanged or state.constructionWorker) then
            saveCurrent(); warehouseSaveClock=0
        end
    end
    if state.screen == "asset_error" then
        return
    elseif state.screen == "title" then
        TitleScreen.update(dt)
    elseif state.screen == "lan" then
        LanScreen.update(dt)
    elseif state.screen == "direct" then
        DirectScreen.update(dt)
    elseif state.screen == "world" then
        local directionX, directionY = Input.movement()
        networkInputX, networkInputY = directionX, directionY
        if multiplayer:isClient() then
            local cursorX, cursorY
            if not (controller and controller:isActive()) then
                cursorX, cursorY = pointerPosition()
                if App.mobileCamera and App.mobileCamera:isEnabled() then
                    cursorX, cursorY = App.mobileCamera:screenToWorld(cursorX, cursorY)
                end
            end
            local workshopInfo = multiplayer:workshopInfo()
            local jack = PalletJack.ensure(state, Config.palletJack)
            local controlsJack = workshopInfo
                and workshopInfo.resourceId == "pallet_jack"
                and jack.operatorPlayerId == World.player.id
            if controlsJack then
                World.updateNetworkPalletJack(
                    World.player, dt, directionX, directionY,
                    Assets, state, cursorX, cursorY)
            else
                World.updateNetworkPlayer(
                    dt, directionX, directionY, Assets, state, cursorX, cursorY)
            end
        else
            local cursorX, cursorY
            if not (controller and controller:isActive()) then
                cursorX, cursorY = pointerPosition()
                if App.mobileCamera and App.mobileCamera:isEnabled() then
                    cursorX, cursorY = App.mobileCamera:screenToWorld(cursorX, cursorY)
                end
            end
            if World.update(dt, directionX, directionY, Assets, state, cursorX, cursorY) then saveCurrent() end
        end
    elseif state.screen == "machine" and not multiplayer:isClient() then
        MachineScreen.update(dt)
    elseif state.screen == "press" and not multiplayer:isClient() then
        PressScreen.update(dt, state)
    elseif state.screen == "workshop_remote" then
        WorkshopRemoteScreen.update(dt)
    end
    -- World events belong to the host simulation, not to its current screen.
    -- Guests may keep walking and working while the host reads any shop menu.
    if not multiplayer:isClient() and simulationActive and state.screen ~= "world" then
        if World.updateSimulation(dt, Assets, state) then saveCurrent() end
    end
    local advanceAuthoritativeMachines = not multiplayer:isClient() and simulationActive
    if advanceAuthoritativeMachines then
        if serviceNetworkBeforeMachine(dt, state, function()
            updateMultiplayer(dt, networkInputX, networkInputY)
        end, function(machineDt, targetState)
            return Windmill.updateAll(machineDt, targetState)
        end) then
            saveCurrent()
        end
    else
        updateMultiplayer(dt, networkInputX, networkInputY)
    end
    if not multiplayer:isClient() and simulationActive and Wrapper.updateAll(dt, state)
    then
        saveCurrent()
    end
    if App.sound then App.sound:update(dt) end
end

function App.draw()
    love.graphics.clear(0.04, 0.05, 0.07)
    local viewBounds = Viewport.gameBounds(Config.baseWidth, Config.baseHeight)
    if mobileControls then mobileControls:setBounds(viewBounds) end
    if App.mobileCamera then App.mobileCamera:setViewport(viewBounds.width, viewBounds.height) end
    local mobileCameraActive = App.mobileCamera and App.mobileCamera:isEnabled()
    if mobileCameraActive then App.mobileCamera:selectView(cameraViewKey(), state.screen == "world") end
    local mobileWorld = state.screen == "world" and mobileCameraActive
    local mobileUi = state.screen ~= "world" and mobileCameraActive
    Viewport.beginDraw(Config.baseWidth, Config.baseHeight, not mobileCameraActive)
    if spriteLabActive then
        SpriteMotionLab.draw(CharacterAssets)
        Viewport.endDraw()
        Smoke.drawn()
        return
    end
    local desiredPack = (state.screen == "title" or state.screen == "lan"
        or state.screen == "direct" or state.screen == "options") and "menu"
        or state.screen == "machine"
            and (state.machineType == "skid_wrapper" and "wrapper" or "cutter")
        or state.screen == "workshop_remote" and WorkshopRemoteScreen.requiredAssetPack()
        or state.screen == "press" and "press" or nil
    if not Assets.activatePack(desiredPack) then
        local _, failures = Assets.assertHealthy()
        state.assetErrors = AssetErrorScreen.normalize(failures)
        state.screen = "asset_error"
        state.message = "A screen asset pack could not be loaded."
    end
    if mobileUi then App.mobileCamera:beginDraw() end
    if state.screen == "asset_error" then
        CharacterAssets.retainCharacters({})
        AssetErrorScreen.draw(state.assetErrors)
    elseif state.screen == "title" then
        CharacterAssets.retainCharacters({})
        local mouseX, mouseY = pointerPosition()
        TitleScreen.draw(Assets, mouseX, mouseY)
    elseif state.screen == "lan" then
        CharacterAssets.retainCharacters({})
        LanScreen.draw()
    elseif state.screen == "direct" then
        CharacterAssets.retainCharacters({})
        DirectScreen.draw()
    elseif state.screen == "options" then
        CharacterAssets.retainCharacters({})
        local mouseX, mouseY = pointerPosition()
        OptionsScreen.draw(mouseX, mouseY)
    else
        local mouseX, mouseY = pointerPosition()
        if mobileWorld then
            local worldX, worldY = App.mobileCamera:screenToWorld(mouseX, mouseY)
            App.mobileCamera:beginDraw()
            World.draw(Assets, CharacterAssets, state, worldX, worldY, multiplayer:remotePlayers())
            App.mobileCamera:endDraw()
        else
            World.draw(Assets, CharacterAssets, state,
                state.screen == "world" and mouseX or nil,
                state.screen == "world" and mouseY or nil,
                multiplayer:remotePlayers())
        end
        if state.screen == "world" then
            Hud.draw(state, World.prompt(), Assets, mouseX, mouseY,
                mobileControls and mobileControls:isEnabled(), controller and controller:isActive(), viewBounds)
            MultiplayerHud.draw(multiplayerHudInfo())
        elseif state.screen == "computer" then
            ComputerScreen.draw(state, mouseX, mouseY, Assets)
        elseif state.screen == "work_phone" then
            WorkPhoneScreen.draw(state, mouseX, mouseY, Assets)
        elseif state.screen == "machine" then
            MachineScreen.draw(state, Assets, mouseX, mouseY)
        elseif state.screen == "press" then
            PressScreen.draw(state, Assets, mouseX, mouseY)
        elseif state.screen == "job_offer" then
            JobOfferScreen.draw(state, mouseX, mouseY, Assets)
        elseif state.screen == "workshop_remote" then
            WorkshopRemoteScreen.draw(state, mouseX, mouseY, Assets)
        elseif state.screen == "truck_inventory" then
            TruckInventoryScreen.draw(state, World, Assets, mouseX, mouseY)
        elseif state.screen == "vendor" then
            VendorScreen.draw(state, Assets, mouseX, mouseY)
        elseif state.screen == "pallet_work_order" then
            PalletWorkOrderScreen.draw(state, Assets, mouseX, mouseY)
        end
        warehouseControls:draw(Assets)
    end
    if state.screen ~= "options" and state.screen ~= "asset_error" then
        local optionsX, optionsY = pointerPosition()
        OptionsScreen.drawAccessButton(optionsX, optionsY)
    end
    Ui.drawPressFeedback()
    if controller then controller:draw() end
    if mobileUi then App.mobileCamera:endDraw() end
    if mobileControls then mobileControls:draw() end
    Viewport.endDraw()
    Smoke.drawn()
end

function App.keypressed(key)
    if spriteLabActive then SpriteMotionLab.keypressed(key, CharacterAssets); return end
    if state.screen == "asset_error" then
        if key == "escape" or key == "q" then love.event.quit() end
        return
    end
    dispatchKeyPressed(key)
end

function App.keyreleased(key)
    if state.screen == "lan" or state.screen == "direct" then return false end
    Input.keyreleased(key, inputContext)
end

function App.textinput(text)
    if state.screen == "options" then
        local result = OptionsScreen.textinput(text)
        syncMobileKeyboard()
        return result
    elseif state.screen == "lan" then
        local result = LanScreen.textinput(text)
        syncMobileKeyboard()
        return result
    elseif state.screen == "direct" then
        local result = DirectScreen.textinput(text)
        syncMobileKeyboard()
        return result
    end
    Input.textinput(text, inputContext)
end

function App.mousepressed(x, y, button, isTouch)
    if mobileControls and mobileControls:ignoreSyntheticMouse(isTouch) then return end
    return dispatchMousePressed(x, y, button)
end

function App.mousereleased(x, y, button, isTouch)
    if mobileControls and mobileControls:ignoreSyntheticMouse(isTouch) then return end
    return dispatchMouseReleased(x, y, button)
end

function App.mousemoved(x, y, _, _, isTouch)
    if mobileControls and mobileControls:ignoreSyntheticMouse(isTouch) then return end
    return dispatchMouseMoved(x, y)
end

function App.wheelmoved(x, y)
    if state.screen == "options" or state.screen == "lan" or state.screen == "direct" then
        return false
    end
    Input.wheelmoved(x, y, inputContext)
end

function App.touchpressed(id, x, y)
    if mobileControls then return mobileControls:touchpressed(id, x, y) end
end

function App.touchmoved(id, x, y, dx, dy)
    if mobileControls then return mobileControls:touchmoved(id, x, y, dx, dy) end
end

function App.touchreleased(id, x, y)
    if mobileControls then return mobileControls:touchreleased(id, x, y) end
end

function App.gamepadpressed(joystick, button)
    if controller then return controller:gamepadpressed(joystick, button) end
end

function App.gamepadreleased(joystick, button)
    if controller then return controller:gamepadreleased(joystick, button) end
end

function App.focus(focused)
    if not focused and mobileControls then
        mobileControls:cancelAll()
    end
    if not focused then
        multiplayer:sendNeutralInput()
        if controller then controller:cancelAll() end
        saveCurrent()
        local activeDirectHost = multiplayer:isHost()
            and multiplayer.networkKind == "direct"
        if directConnection then
            local cleaned, cleanupError = closeDirectConnection()
            if not cleaned then
                state.screen = "direct"
                DirectScreen.showCleanupError(cleanupError)
            elseif activeDirectHost and not isAndroidPlatform() then
                DirectScreen.leave()
                state.screen = "world"
                state.message = "The pending Direct invitation was cancelled because the app lost focus; connected workers stayed online."
            elseif not activeDirectHost then
                state.screen = "direct"
                DirectScreen.showError(
                    "Direct setup was cancelled safely because the app left the foreground.")
            end
            syncMobileKeyboard()
        elseif state.screen == "direct" and multiplayer:isClient()
            and multiplayer.networkKind == "direct" then
            multiplayer:stop("Direct client left the foreground during setup")
            openDirectPlay(lastDirectSlot)
            DirectScreen.showError(
                "Direct setup ended safely because this device left the foreground.")
            syncMobileKeyboard()
        end
        if isAndroidPlatform() and multiplayer:isHost() then
            local direct = multiplayer.networkKind == "direct"
            if not direct then lanDiscovery:stop() end
            multiplayer:stop("Android host left the foreground")
            clearWorkshopAuthority("host_backgrounded")
            if direct then
                openDirectPlay(lastDirectSlot)
                DirectScreen.showError(
                    "Direct hosting ended safely because the host phone left the foreground.")
            else
                state.screen = "lan"
                LanScreen.showError("Hosting ended safely because the host phone left the foreground.")
            end
            if love.window and love.window.setDisplaySleepEnabled then
                love.window.setDisplaySleepEnabled(true)
            end
            syncMobileKeyboard()
        end
    end
    if App.sound then App.sound:setPaused(not focused) end
end

function App.quit()
    if not spriteLabActive then saveCurrent() end
    lanDiscovery:stop()
    lanReconnect:cancel(true)
    multiplayer:stop("Application closed")
    clearWorkshopAuthority("application_closed")
    closeDirectConnection()
    closeDirectHostComposite()
    DirectScreen.leave()
    if isAndroidPlatform() and love.window and love.window.setDisplaySleepEnabled then
        love.window.setDisplaySleepEnabled(true)
    end
    if App.sound then App.sound:shutdown() end
end

App.multiplayer = multiplayer

return App
