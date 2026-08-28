local Assets = require("src.assets")
local AssetErrorScreen = require("src.screens.asset_error_screen")
local BayDoor = require("src.bay_door")
local BusinessCalendar = require("src.business_calendar")
local CharacterAssets = require("src.character_assets")
local ComputerScreen = require("src.screens.computer_screen")
local Config = require("src.config")
local Controller = require("src.controller")
local CutterPlacement = require("src.cutter_placement")
local CutterZones = require("src.cutter_zones")
local Customer = require("src.customer")
local Hud = require("src.screens.hud")
local Input = require("src.input")
local Ui = require("src.screens.ui")
local JobOfferScreen = require("src.screens.job_offer_screen")
local LanScreen = require("src.screens.lan_screen")
local PalletWorkOrderScreen = require("src.screens.pallet_work_order_screen")
local JobService = require("src.job_service")
local Jobs = require("src.jobs")
local Machine = require("src.machine")
local MachineFleet = require("src.machine_fleet")
local MachineMaintenance = require("src.machine_maintenance")
local MobileControls = require("src.mobile_controls")
local MultiplayerHud = require("src.screens.multiplayer_hud")
local MultiplayerSession = require("src.net.session")
local Navigation = require("src.navigation")
local Procurement = require("src.procurement")
local Wrapper = require("src.wrapper")
local MachineScreen = require("src.screens.machine_screen")
local PalletJack = require("src.pallet_jack")
local PalletState = require("src.pallet_state")
local PalletLogistics = require("src.pallet_logistics")
local PlateService = require("src.plate_service")
local PressScreen = require("src.screens.press_screen")
local Receiving = require("src.receiving")
local Save = require("src.save")
local SaveSchema = require("src.save_schema")
local Shop = require("src.shop")
local Smoke = require("src.smoke")
local SpriteMotionLab = require("src.screens.sprite_motion_lab")
local State = require("src.state")
local TitleScreen = require("src.screens.title_screen")
local Technician = require("src.technician")
local Truck = require("src.truck")
local TruckInventoryScreen = require("src.screens.truck_inventory_screen")
local VendorScreen = require("src.screens.vendor_screen")
local Viewport = require("src.viewport")
local World = require("src.world")
local WorldRenderer = require("src.world_renderer")
local Windmill = require("src.windmill")
local WindmillPlacement = require("src.windmill_placement")
local WorkshopAuthority = require("src.workshop_authority")
local WorkshopRemoteScreen = require("src.screens.workshop_remote_screen")

local App = {}
local state = State.new()
local spriteLabActive = false
local mobileControls = nil
local controller = nil
local multiplayer = MultiplayerSession.new()
local workshopAuthority = nil
local localWorkshopLease = nil
local localWorkshopRequestId = 0

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
    if not State.applySave(state, payload) then return false, "That shop save could not be opened safely." end
    World.load(payload.player)
    if mode == "new" and not saveCurrent() then
        return false, "This device could not create the new shop save."
    end
    if payload.recovered then
        state.message = "Recovered this shop from its last valid " .. tostring(payload.recoverySource) .. " copy."
    end
    return true
end

local returnToTitle
local openLocalPlay

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

local function wrapperView()
    local runtime = Wrapper.snapshot()
    return {
        step = runtime.step,
        progress = runtime.progress,
        cycleTime = runtime.cycleTime,
        plasticWrapRolls = math.max(0, math.floor(tonumber(state.inventory.plasticWrapRolls) or 0)),
        plasticWrapUses = math.max(0, math.floor(tonumber(state.inventory.plasticWrapUses) or 0)),
        pallets = wrapperPalletView(),
        selectedPalletId = runtime.selectedPalletId,
        palletId = runtime.palletId,
    }
end

local function wrapperSnapshotView()
    local runtime = Wrapper.snapshot()
    runtime.pallets = wrapperPalletView()
    return runtime
end

local function findActiveJob(jobId)
    for _, job in ipairs((state.jobs and state.jobs.active) or {}) do
        if job.id == jobId then return job end
    end
end

local function createWorkshopAuthority()
    return WorkshopAuthority.new({
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
                    submit_quote = {
                        normalize = function(arguments)
                            local amount = type(arguments) == "table" and arguments.amount
                            if not exactArguments(arguments, { "amount" })
                                or type(amount) ~= "number" or amount ~= math.floor(amount)
                                or amount < 1 or amount > 100000000
                            then
                                return nil, "invalid_amount", "Enter a valid whole-dollar quote."
                            end
                            return { amount = amount }
                        end,
                        perform = function(lease, _, arguments)
                            local offer = lease.private and lease.private.offer
                            if not offer then return false, "offer_missing", "The customer paperwork expired." end
                            local succeeded, quote = JobService.submitQuote(
                                state, offer, arguments.amount, os.time())
                            if not succeeded then
                                return false, "quote_failed", "Could not submit the quote: " .. tostring(quote)
                            end
                            lease.private.resolved = true
                            World.resolveCustomer(quote.accepted and "accepted" or "declined", state)
                            saveCurrent()
                            local message = quote.accepted
                                and string.format("%s accepted the $%d quote.", offer.company, quote.amount)
                                or string.format("%s declined the $%d quote.", offer.company, quote.amount)
                            return true, quote.accepted and "quote_accepted" or "quote_declined", message
                        end,
                    },
                    decline = {
                        normalize = function(arguments)
                            if not exactArguments(arguments, {}) then
                                return nil, "invalid_arguments", "Decline takes no additional data."
                            end
                            return {}
                        end,
                        perform = function(lease)
                            local offer = lease.private and lease.private.offer
                            if not offer then return false, "offer_missing", "The customer paperwork expired." end
                            local succeeded, errorMessage = JobService.declineOffer(state, offer, os.time())
                            if not succeeded then
                                return false, "decline_failed", "Could not decline the job: " .. tostring(errorMessage)
                            end
                            lease.private.resolved = true
                            World.resolveCustomer("declined", state)
                            saveCurrent()
                            return true, "declined", "Declined " .. offer.id .. ". The customer is leaving."
                        end,
                    },
                },
            },
            office_computer = {
                canAcquire = function(player)
                    return World.validateNetworkWorkshopAccess(player, state, "office_computer")
                end,
                onAcquire = function()
                    return true, "acquired", "Office computer connected.", {}
                end,
                commands = {
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
            skid_wrapper = {
                canAcquire = function(player)
                    local allowed, code, message = World.validateNetworkWorkshopAccess(
                        player, state, "skid_wrapper")
                    if not allowed then return false, code, message end
                    if Wrapper.step == "wrapping" then
                        return false, "machine_busy", "The skid wrapper is already running a cycle."
                    end
                    return true
                end,
                onAcquire = function()
                    return true, "acquired", "Skid-wrapper console connected.", wrapperView()
                end,
                commands = {
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
                },
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
                onRelease = function(lease)
                    -- Timeout, disconnect, and normal release all use the same
                    -- safe recovery: stop the jack without inventing a drop.
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
                },
            },
        },
    })
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
end

local function startLanHost(slot, playerName)
    local payload, status = Save.load(slot)
    local mode = "continue"
    if not payload and status == "empty" then
        payload, mode = Save.newGame(slot), "new"
    elseif not payload then
        return false, "That host save is damaged. Choose another slot or delete it first."
    end
    local writable, writableError = Save.preflightWritable(slot)
    if not writable then return false, writableError end
    workshopAuthority = createWorkshopAuthority()
    localWorkshopLease = nil
    localWorkshopRequestId = 0
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
    local started, startError = startGame(payload, mode)
    if not started then
        multiplayer:stop("Host save could not be opened")
        clearWorkshopAuthority("host_save_failed")
        state.screen = "lan"
        return false, startError
    end
    if isAndroidPlatform() and love.window and love.window.setDisplaySleepEnabled then
        love.window.setDisplaySleepEnabled(false)
    end
    state.message = "LAN host active. Guests can join this shop by local IPv4 address."
    return true
end

local function startLanClient(address, playerName)
    return multiplayer:startClient(address, {
        name = playerName,
        character = Config.player.character,
    })
end

openLocalPlay = function(slot)
    multiplayer:stop("Opening Local Play")
    clearWorkshopAuthority("session_closed")
    state.screen = "lan"
    LanScreen.enter({
        slot = slot,
        host = startLanHost,
        join = startLanClient,
        cancel = function() multiplayer:stop("Connection cancelled") end,
        back = function()
            multiplayer:stop("Leaving Local Play")
            state.screen = "title"
            TitleScreen.enter(startGame, openLocalPlay)
        end,
    })
end

returnToTitle = function()
    saveCurrent()
    multiplayer:stop("Returned to title")
    clearWorkshopAuthority("session_closed")
    if isAndroidPlatform() and love.window and love.window.setDisplaySleepEnabled then
        love.window.setDisplaySleepEnabled(true)
    end
    state.screen = "title"
    TitleScreen.enter(startGame, openLocalPlay)
end

local function palletJackCommandFor(action)
    local jack = PalletJack.ensure(state, Config.palletJack)
    if action == "park" then return "park_jack", {} end
    if jack.carriedPalletId then
        return "lower_pallet", { palletId = jack.carriedPalletId }
    end
    local candidateId = jack.candidatePalletId
        or World.networkPalletJackSnapshot(state).candidatePalletId
    if candidateId then return "lift_pallet", { palletId = candidateId } end
    return "park_jack", {}
end

local function handlePalletJackControl(action)
    if machineRelocationActive() then
        state.message = "Place the moving machine before using or parking the pallet jack."
        return true
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
        local command, arguments = palletJackCommandFor(action)
        local requested, errorMessage = multiplayer:requestWorkshopCommand(
            command, arguments)
        state.message = requested
            and (command == "lift_pallet" and "Waiting for the host to verify that exact pallet..."
                or command == "lower_pallet" and "Waiting for the host to verify the drop space..."
                or "Waiting for the host to park the pallet jack...")
            or tostring(errorMessage or "The pallet-jack request could not be sent.")
        return true
    end
    if not multiplayer:isHost() then return false end
    if localWorkshopLease and localWorkshopLease.resourceId == "pallet_jack" then
        local command, arguments = palletJackCommandFor(action)
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
    palletJackControl = handlePalletJackControl,
    networkInteraction = function(selected)
        if not multiplayer:isActive() then return false end
        if not selected then
            if multiplayer:isClient() then
                state.message = "Move beside a workshop control before using it."
                return true
            end
            return false
        end
        local resourceId = World.workshopResourceId(selected.kind)
        if multiplayer:isHost() and resourceId then
            local lease = workshopAuthority and workshopAuthority:leaseForResource(resourceId)
            if lease and lease.ownerPlayerId ~= 1 then
                state.message = "Another worker is using that workshop control."
                return true
            end
            local acquired, acquireMessage = acquireLocalWorkshop(resourceId)
            if not acquired then
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
        if selected.kind ~= "loadingBayDoor" then
            state.message = "That shop-floor action is not worker-enabled yet."
            return true
        end
        local doorState = selected.target and selected.target.doorState
        if doorState ~= "closed" and doorState ~= "open" then
            state.message = "Wait for the loading-bay door to finish moving."
            return true
        end
        local desiredState = doorState == "closed" and "open" or "closed"
        local requested, errorMessage = multiplayer:requestInteraction(
            selected.kind, desiredState)
        state.message = requested
            and "Waiting for the host device to verify the loading-bay switch..."
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

local syncMobileKeyboard

local function dispatchGameMousePressed(gameX, gameY, button)
    if state.screen == "asset_error" then return end
    if button == 1 then Ui.notePress(gameX, gameY) end
    if App.sound then App.sound:pointerPressed(button, state.screen) end
    if state.screen == "lan" then
        local result = LanScreen.mousepressed(gameX, gameY, button)
        syncMobileKeyboard()
        return result
    end
    return Input.mousepressed(gameX, gameY, button, inputContext)
end

local function dispatchGameMouseReleased(gameX, gameY, button)
    if state.screen == "lan" then return LanScreen.mousereleased(gameX, gameY, button) end
    return Input.mousereleased(gameX, gameY, button, inputContext)
end

local function dispatchMousePressed(x, y, button)
    if state.screen == "asset_error" then return end
    local gameX, gameY = toPointerCoordinates(x, y)
    if button == 1 then Ui.notePress(gameX, gameY) end
    if App.sound then App.sound:pointerPressed(button, state.screen) end
    if state.screen == "lan" then
        local result = LanScreen.mousepressed(gameX, gameY, button)
        syncMobileKeyboard()
        return result
    end
    return Input.mousepressed(gameX, gameY, button, inputContext)
end

local function dispatchMouseReleased(x, y, button)
    local gameX, gameY = toPointerCoordinates(x, y)
    if state.screen == "lan" then return LanScreen.mousereleased(gameX, gameY, button) end
    return Input.mousereleased(gameX, gameY, button, inputContext)
end

local function dispatchMouseMoved(x, y)
    local gameX, gameY = toPointerCoordinates(x, y)
    return Input.mousemoved(gameX, gameY, inputContext)
end

local function wantsTextInput()
    if state.screen == "job_offer" and JobOfferScreen.wantsTextInput then
        return JobOfferScreen.wantsTextInput()
    elseif state.screen == "computer" and ComputerScreen.wantsTextInput then
        return ComputerScreen.wantsTextInput()
    elseif state.screen == "machine" and MachineScreen.wantsTextInput then
        return MachineScreen.wantsTextInput()
    elseif state.screen == "lan" then
        return LanScreen.wantsTextInput()
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
    if state.screen == "lan" then
        local result = LanScreen.keypressed(key)
        syncMobileKeyboard()
        return result
    end
    if multiplayer:isClient() and state.screen == "world"
        and (key == "m" or key == "q")
    then
        state.message = "Shop status is live. Relocation and vehicle controls remain host-owned."
        return true
    end
    return Input.keypressed(key, inputContext)
end

local function primaryMobileAction()
    if not multiplayer:isClient() and (state.cutter and state.cutter.moving
        or state.wrapper and state.wrapper.moving or state.windmill and state.windmill.moving)
    then
        return "e", "PLACE"
    end
    local selected = World.getInteraction()
    if not selected then return "e", "USE" end
    if multiplayer:isClient() and selected.kind ~= "loadingBayDoor"
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
        customer = "QUOTE", computer = "PC", vendor = "TALK", loadingBayDoor = "DOOR",
        truckCargoDoor = "TRUCK", cutter = "CUTTER", skidWrapper = "WRAP",
        windmill = "PRESS", palletJack = jackLabel,
    }
    return "e", labels[selected.kind] or "USE"
end

local function extraMobileActions()
    local actions = {}
    if multiplayer:isClient() then
        local info = multiplayer:workshopInfo()
        if info and info.resourceId == "pallet_jack" then
            actions[#actions + 1] = { key = "f", label = "PARK" }
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
        actions[#actions + 1] = { key = "f", label = "PARK" }
        local selected = World.getInteraction()
        local canRelocate = selected and (selected.kind == "cutter"
            or selected.kind == "skidWrapper" or selected.kind == "windmill")
        if not canRelocate then
            canRelocate = World.cutterNearby and World.cutterNearby(state)
                or World.wrapperNearby and World.wrapperNearby(state)
                or World.windmillNearby and World.windmillNearby(state)
        end
        if canRelocate then actions[#actions + 1] = { key = "m", label = "MOVE" } end
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
        Customer = Customer,
        config = Config,
        CutterPlacement = CutterPlacement,
        CutterZones = CutterZones,
        machine = Machine,
        machineFleet = MachineFleet,
        machineMaintenance = MachineMaintenance,
        machineScreen = MachineScreen,
        Navigation = Navigation,
        PalletJack = PalletJack,
        PalletState = PalletState,
        PalletLogistics = PalletLogistics,
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
        worldRenderer = WorldRenderer,
        windmill = Windmill,
        WindmillPlacement = WindmillPlacement,
        startupTextureBytes = startupTextureBytes,
        Sound = Sound,
    })
    if spriteLabActive then SpriteMotionLab.enter(CharacterAssets) end
end

function App.load()
    local Sound = require("src.sound")
    love.graphics.setDefaultFilter("nearest", "nearest")
    mobileControls = MobileControls.new({
        toGame = function(x, y) return Viewport.toGame(x, y, Config.baseWidth, Config.baseHeight) end,
        pressKey = dispatchKeyPressed,
        releaseKey = function(key) Input.keyreleased(key, inputContext) end,
        pressPointer = dispatchMousePressed,
        movePointer = dispatchMouseMoved,
        releasePointer = dispatchMouseReleased,
        gameplayActive = function() return state.screen == "world" end,
        gestureActive = function()
            return App.mobileCamera and App.mobileCamera:isEnabled() and not spriteLabActive
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
        worldMenuAction = returnToTitle,
    })
    Input.setMobileMovementProvider(function()
        if mobileControls then return mobileControls:movement() end
        return 0, 0
    end)
    if Smoke.requested() then love.filesystem.setIdentity("the-picture-shop-smoke") end
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
        TitleScreen.enter(startGame, openLocalPlay)
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
    if Smoke.requested() and not soundHealthy then
        error("Sound startup failed: " .. table.concat(soundErrors or {}, "; "))
    end
    print("[PICTURE SHOP] Startup complete")
end

local function handleMultiplayerEvents()
    for _, event in ipairs(multiplayer:drainEvents()) do
        if event.type == "ready" then
            if not State.applySharedSnapshot(state, event.state) then
                multiplayer:stop("Invalid shared shop snapshot")
                state.screen = "lan"
                LanScreen.showError("The host sent a shop snapshot this build could not apply.")
            else
                World.load(event.spawn)
                state.screen = "world"
                state.message = "Joined the host shop. Movement, doors, reception, office, and worker consoles are live."
            end
            syncMobileKeyboard()
        elseif event.type == "shop_state" then
            if not State.applySharedUpdate(state, event.state) then
                multiplayer:stop("Invalid durable shop update")
                state.screen = "lan"
                LanScreen.showError("The host sent a shop update this build could not apply.")
                syncMobileKeyboard()
            end
        elseif event.type == "pallet_jack_state" then
            local applied, applyError = World.applyNetworkPalletJackSnapshot(
                state, event.jack)
            if not applied and applyError ~= "awaiting_durable" then
                multiplayer:stop("Invalid pallet-jack update")
                state.screen = "lan"
                LanScreen.showError("The host sent a pallet-jack update this build could not apply.")
                syncMobileKeyboard()
            end
        elseif event.type == "visitor_state" then
            if not World.applyVisitorSnapshot(event.customer, event.vendor) then
                multiplayer:stop("Invalid visitor update")
                state.screen = "lan"
                LanScreen.showError("The host sent a visitor update this build could not apply.")
                syncMobileKeyboard()
            end
        elseif event.type == "environment_state" then
            if not World.applyEnvironmentSnapshot(event.bayDoor, event.truck) then
                multiplayer:stop("Invalid environment update")
                state.screen = "lan"
                LanScreen.showError("The host sent an environment update this build could not apply.")
                syncMobileKeyboard()
            end
        elseif event.type == "interaction_result" then
            state.message = tostring(event.message or (event.accepted
                and "The host accepted the interaction."
                or "The host rejected the interaction."))
        elseif event.type == "workshop_grant" then
            state.message = tostring(event.message or (event.granted
                and "Workshop control granted." or "Workshop control was not granted."))
            if event.granted then
                if event.resourceId == "skid_wrapper" and event.view then
                    Wrapper.applySnapshot(event.view, state)
                end
                if event.resourceId == "pallet_jack" then
                    state.screen = "world"
                else
                    WorkshopRemoteScreen.enter(event, state)
                end
            end
            syncMobileKeyboard()
        elseif event.type == "workshop_result" then
            if event.resourceId == "skid_wrapper" and event.view then
                Wrapper.applySnapshot(event.view, state)
            end
            if event.resourceId ~= "pallet_jack" then
                WorkshopRemoteScreen.applyResult(event)
            end
            state.message = tostring(event.message or (event.accepted
                and "Workshop action completed." or "Workshop action was rejected."))
            if event.accepted and event.resourceId == "reception_customer" then
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
                multiplayer:stop("Invalid workshop runtime")
                state.screen = "lan"
                LanScreen.showError("The host sent a workshop update this build could not apply.")
            else
                WorkshopRemoteScreen.applySnapshot(event)
            end
        elseif event.type == "workshop_lost" then
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
            end
            state.message = tostring(event.message or "The host released that workshop control.")
            syncMobileKeyboard()
        elseif event.type == "host_started" then
            local address = event.address or "the host device's Wi-Fi IPv4"
            state.message = "LAN host: guests join " .. tostring(address) .. ":" .. tostring(event.port or 22122) .. "."
        elseif event.type == "player_joined" then
            state.message = tostring(event.name or "A worker") .. " joined the LAN shop."
        elseif event.type == "player_left" then
            if workshopAuthority then
                workshopAuthority:cleanupPlayer({ id = event.playerId }, "disconnected",
                    { state = state })
            end
            state.message = tostring(event.name or "A worker") .. " left the LAN shop."
        elseif event.type == "disconnected" then
            multiplayer:stop("Host disconnected")
            WorkshopRemoteScreen.clear()
            state.screen = "lan"
            LanScreen.showError(event.message or "The host connection ended.")
            syncMobileKeyboard()
        elseif event.type == "error" then
            if state.screen == "lan" then
                multiplayer:stop("Connection error")
                LanScreen.showError(event.message or "The LAN connection failed.")
                syncMobileKeyboard()
            else
                state.message = "LAN: " .. tostring(event.message or "network error")
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
        if payload.jobId ~= nil then arguments.jobId = payload.jobId end
        if payload.palletId ~= nil then arguments.palletId = payload.palletId end
        return workshopAuthority:command(player, {
            requestId = payload.commandId,
            resourceId = payload.resourceId,
            leaseId = payload.leaseId,
            action = payload.action,
            args = arguments,
            expectedRevision = payload.expectedRevision,
        }, { state = state })
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
        getWorkshopSnapshot = function()
            return {
                resources = workshopAuthority and workshopAuthority:snapshot() or {},
                wrapper = wrapperSnapshotView(),
            }
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

function App.update(dt)
    if controller then controller:update(dt) end
    if spriteLabActive then SpriteMotionLab.update(dt, CharacterAssets); return end
    local networkInputX, networkInputY = 0, 0
    if not multiplayer:isClient() and state.screen ~= "title"
        and state.screen ~= "lan" and state.screen ~= "asset_error"
    then
        local calendarChanged = BusinessCalendar.update(state, dt)
        local emailArrived = JobService.updateClientEmails(state)
        local technicianChanged = MachineMaintenance.updateTechnician(state)
        if calendarChanged or emailArrived or technicianChanged then saveCurrent() end
    end
    if state.screen == "asset_error" then
        return
    elseif state.screen == "title" then
        TitleScreen.update(dt)
    elseif state.screen == "lan" then
        LanScreen.update(dt)
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
    elseif state.screen == "truck_inventory" and not multiplayer:isClient() then
        if World.update(dt, 0, 0, Assets, state) then saveCurrent() end
    elseif state.screen == "machine" and not multiplayer:isClient() then
        MachineScreen.update(dt)
        if state.machineType ~= "skid_wrapper" then
            local previousStep = Machine.step
            Machine.update(dt, state)
            if previousStep ~= "finished" and Machine.step == "finished" then saveCurrent() end
        end
    elseif state.screen == "press" and not multiplayer:isClient() then
        PressScreen.update(dt, state)
        if Windmill.update(dt, state) then saveCurrent() end
    end
    if not multiplayer:isClient() and state.screen ~= "title" and state.screen ~= "lan"
        and state.screen ~= "asset_error" and Wrapper.update(dt, state)
    then
        saveCurrent()
    end
    updateMultiplayer(dt, networkInputX, networkInputY)
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
    local desiredPack = (state.screen == "title" or state.screen == "lan") and "menu"
        or state.screen == "machine"
            and (state.machineType == "skid_wrapper" and "wrapper" or "cutter")
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
            MultiplayerHud.draw(multiplayer:hudInfo())
        elseif state.screen == "computer" then
            ComputerScreen.draw(state, mouseX, mouseY, Assets)
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
    if state.screen == "lan" then return false end
    Input.keyreleased(key, inputContext)
end

function App.textinput(text)
    if state.screen == "lan" then
        local result = LanScreen.textinput(text)
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
    if state.screen == "lan" then return false end
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
        if isAndroidPlatform() and multiplayer:isHost() then
            multiplayer:stop("Android host left the foreground")
            clearWorkshopAuthority("host_backgrounded")
            state.screen = "lan"
            LanScreen.showError("Hosting ended safely because the host phone left the foreground.")
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
    multiplayer:stop("Application closed")
    clearWorkshopAuthority("application_closed")
    if isAndroidPlatform() and love.window and love.window.setDisplaySleepEnabled then
        love.window.setDisplaySleepEnabled(true)
    end
    if App.sound then App.sound:shutdown() end
end

App.multiplayer = multiplayer

return App
