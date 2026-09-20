local CutterMaintenanceAuthority = require("src.cutter_maintenance_authority")
local Harness = require("src.tests.support.network_impairment_harness")
local Protocol = require("src.net.protocol")
local Session = require("src.net.session")
local WorkshopAuthority = require("src.workshop_authority")

local Test = {}

local function player(x, y)
    return {
        x = x, y = y, velocityX = 0, velocityY = 0,
        intentX = 0, intentY = 0, moving = false, facing = 1,
        animationDistance = 0, character = "rabbit-worker",
    }
end

local function cutterView()
    return {
        runtimeRevision = 1, step = "idle", phasePermille = 0,
        loaded = false, clamp = false, clampPermille = 0, bladePermille = 0,
        barrierClear = true, emergencyStopped = false, gaugeCentiInch = 0,
        programIndex = 1, memoryCentiInch = {}, candidates = {}, genericSheets = 1000,
    }
end

local function eventNamed(events, name)
    for _, event in ipairs(events or {}) do
        if event.type == name then return event end
    end
end

function Test.run(context, check)
    local state = context.State.new()
    state.inventory.stock.maintenance_kit = 1
    local saves = 0
    local service = CutterMaintenanceAuthority.create({
        state = state,
        baseView = cutterView,
        validateAccess = function() return true end,
        save = function() saves = saves + 1 end,
        machineReady = function() return true end,
    })
    local authority = WorkshopAuthority.new({
        tokenGenerator = function(serial)
            return "cutter-service-session-lease-" .. tostring(serial)
        end,
        resources = {
            cutter = {
                canAcquire = function() return true end,
                onAcquire = function()
                    local private = CutterMaintenanceAuthority.newSession()
                    return true, "acquired", "Cutter connected.",
                        service.view(private, true), private
                end,
                commands = service.commands,
            },
        },
    })
    local network = Harness.new({
        maxClients = 1,
        classify = function(bytes)
            local envelope = Protocol.decode(bytes)
            return envelope and envelope.type or "invalid"
        end,
    })
    local host = Session.new({ transportFactory = network.factory })
    local client = Session.new({ transportFactory = network.factory })
    local hostPlayer, clientPlayer = player(100, 100), player(110, 100)
    local observed = {}
    local hostContext = {
        localPlayer = hostPlayer,
        resolveGuestSpawn = function() return 110, 100 end,
        getShopSnapshot = function()
            return {
                state = { money = state.money, screen = "world",
                    inventory = { paper = 0, prints = 0 },
                    jobs = { active = {}, completed = {} } },
                player = { x = hostPlayer.x, y = hostPlayer.y,
                    character = hostPlayer.character },
            }
        end,
        getWorkshopSnapshot = function()
            return {
                resources = authority:snapshot(),
                wrapper = { step = "idle", progress = 0, cycleTime = 3, pallets = {} },
            }
        end,
        moveRemote = function() end,
        touchWorkshop = function(worker) authority:touchPlayer(worker) end,
        updateWorkshop = function() authority:update({}) end,
    }
    hostContext.performWorkshop = function(worker, operation, payload)
        if operation == "workshop_acquire" then
            return authority:acquire(worker, {
                requestId = payload.requestId, resourceId = payload.resourceId,
            }, {})
        elseif operation == "workshop_command" then
            observed[#observed + 1] = payload
            local arguments = {}
            if payload.itemIndex ~= nil then arguments.itemIndex = payload.itemIndex end
            if payload.enabled ~= nil then arguments.enabled = payload.enabled end
            return authority:command(worker, {
                requestId = payload.commandId, resourceId = payload.resourceId,
                leaseId = payload.leaseId, action = payload.action,
                args = arguments, expectedRevision = payload.expectedRevision,
            }, {})
        elseif operation == "workshop_release" then
            return authority:release(worker, {
                requestId = payload.requestId, resourceId = payload.resourceId,
                leaseId = payload.leaseId, reason = payload.reason,
            }, {})
        end
    end
    local clientContext = { localPlayer = clientPlayer, inputX = 0, inputY = 0 }
    local hostStarted = host:startHost({
        name = "Cutter Host", character = "rabbit-worker",
        addressOptions = { socket = { dns = {
            gethostname = function() return "cutter-host" end,
            getaddrinfo = function() return { { addr = "192.168.1.92" } } end,
        } } },
    })
    host.sessionId = "cutter-maintenance-session-test"
    local clientStarted = client:startClient("192.168.1.92:22122", {
        name = "Cutter Guest", character = "rabbit-worker",
    })
    client.clientNonce = "cutter-maintenance-client"
    if hostStarted and clientStarted then
        client:update(0, clientContext)
        host:update(0, hostContext)
        client:update(0, clientContext)
        host:update(0.1, hostContext)
        client:update(0, clientContext)
        client:drainEvents()
        host:drainEvents()
    end

    local acquireSent = client:requestWorkshopAcquire("cutter")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local grant = eventNamed(client:drainEvents(), "workshop_grant")

    local duplicateWeekly = network:duplicateNext("client_to_host", 1, 1, true)
    local weeklySent = client:requestWorkshopCommand(
        "set_weekly_technician", { enabled = true })
    host:update(0, hostContext)
    client:update(0, clientContext)
    local weeklyResult = eventNamed(client:drainEvents(), "workshop_result")

    local beginSent = client:requestWorkshopCommand("begin_lubrication", {})
    host:update(0, hostContext)
    client:update(0, clientContext)
    local beginResult = eventNamed(client:drainEvents(), "workshop_result")

    local advanced = true
    for _ = 1, 5 do
        advanced = advanced and client:requestWorkshopCommand("service_advance", {})
        host:update(0, hostContext)
        client:update(0, clientContext)
        advanced = advanced and eventNamed(client:drainEvents(), "workshop_result") ~= nil
    end
    local viewSent = client:requestWorkshopCommand("service_view", { itemIndex = 2 })
    host:update(0, hostContext)
    client:update(0, clientContext)
    local viewResult = eventNamed(client:drainEvents(), "workshop_result")
    local weeklyPayload, viewPayload
    for _, payload in ipairs(observed) do
        if payload.action == "set_weekly_technician" then weeklyPayload = payload end
        if payload.action == "service_view" then viewPayload = payload end
    end
    local _, cutter = context.machineMaintenance.cutterStatus(state)
    check("cutter_maintenance_session_round_trip_preserves_bounded_intent_and_exact_once_save",
        hostStarted and clientStarted and client.ready and acquireSent and grant and grant.granted
        and duplicateWeekly and weeklySent and weeklyResult and weeklyResult.accepted
        and weeklyPayload and weeklyPayload.enabled == true and weeklyPayload.itemIndex == nil
        and cutter.weeklyTechnician and saves == 1
        and beginSent and beginResult and beginResult.accepted
        and advanced and viewSent and viewResult and viewResult.accepted
        and viewResult.view.serviceStep == "lubricate"
        and viewResult.view.serviceView == 2
        and viewPayload and viewPayload.itemIndex == 2 and viewPayload.enabled == nil)

    client:stop("test_complete")
    host:update(0, hostContext)
    host:stop("test_complete")
end

return Test
