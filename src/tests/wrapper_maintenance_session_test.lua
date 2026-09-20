local Harness = require("src.tests.support.network_impairment_harness")
local MachineFleet = require("src.machine_fleet")
local Protocol = require("src.net.protocol")
local Session = require("src.net.session")
local WorkshopAuthority = require("src.workshop_authority")
local WrapperMaintenanceAuthority = require("src.wrapper_maintenance_authority")

local Test = {}

local function player(x, y)
    return {
        x = x, y = y, velocityX = 0, velocityY = 0,
        intentX = 0, intentY = 0, moving = false, facing = 1,
        animationDistance = 0, character = "rabbit-worker",
    }
end

local function wrapperView(detailed)
    local view = { step = "idle", progress = 0, cycleTime = 3, pallets = {} }
    if detailed ~= false then
        view.plasticWrapRolls, view.plasticWrapUses = 1, 11
    end
    return view
end

local function eventNamed(events, name)
    for _, event in ipairs(events or {}) do
        if event.type == name then return event end
    end
end

function Test.run(context, check)
    local state = context.State.new()
    state.inventory.stock.maintenance_kit = 1
    MachineFleet.recordUse(state, "skid_wrapper", 18)
    local saves, active, observed = 0, nil, {}
    local service = WrapperMaintenanceAuthority.create({
        state = state,
        baseView = wrapperView,
        validateAccess = function() return true end,
        machineReady = function() return true end,
        resetRuntime = function() return true end,
        save = function() saves = saves + 1 end,
    })
    local authority = WorkshopAuthority.new({
        tokenGenerator = function(serial)
            return "wrapper-session-lease-" .. tostring(serial)
        end,
        resources = {
            skid_wrapper = {
                canAcquire = function() return true end,
                onAcquire = function()
                    active = WrapperMaintenanceAuthority.newSession()
                    return true, "acquired", "Wrapper connected.",
                        service.view(active, true), active
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
                wrapper = service.view(active, false),
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
        name = "Wrapper Host", character = "rabbit-worker",
        addressOptions = { socket = { dns = {
            gethostname = function() return "wrapper-host" end,
            getaddrinfo = function() return { { addr = "192.168.1.93" } } end,
        } } },
    })
    host.sessionId = "wrapper-maintenance-session-test"
    local clientStarted = client:startClient("192.168.1.93:22122", {
        name = "Wrapper Guest", character = "rabbit-worker",
    })
    client.clientNonce = "wrapper-maintenance-client"
    if hostStarted and clientStarted then
        client:update(0, clientContext)
        host:update(0, hostContext)
        client:update(0, clientContext)
        host:update(0.1, hostContext)
        client:update(0, clientContext)
        client:drainEvents()
        host:drainEvents()
    end

    local function command(action, arguments)
        local sent = client:requestWorkshopCommand(action, arguments or {})
        host:update(0, hostContext)
        client:update(0, clientContext)
        return sent, eventNamed(client:drainEvents(), "workshop_result")
    end

    local acquireSent = client:requestWorkshopAcquire("skid_wrapper")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local grant = eventNamed(client:drainEvents(), "workshop_grant")
    local beginSent, begun = command("begin_service", {})

    local duplicateMiss = network:duplicateNext("client_to_host", 1, 1, true)
    local missSent, missed = command("service_miss", {})
    local current = missed and missed.view
    local finalDuplicated, completed, allTargets = false, nil, true
    local guard = 0
    while current and current.serviceStep == "task" and guard < 16 do
        if current.serviceTaskIndex == 4
            and current.servicePhase == current.serviceTargetCount
        then
            finalDuplicated = network:duplicateNext("client_to_host", 1, 1, true)
        end
        local sent, result = command("service_target", {
            itemIndex = current.servicePhase,
        })
        allTargets = allTargets and sent and result ~= nil and result.accepted
        completed = result
        current = result and result.view
        guard = guard + 1
    end

    local wrapper = MachineFleet.installed(state, "skid_wrapper")
    local targetPayload
    for _, payload in ipairs(observed) do
        if payload.action == "service_target" then targetPayload = payload end
    end
    check("wrapper_maintenance_session_round_trip_is_bounded_host_scored_and_exact_once",
        hostStarted and clientStarted and client.ready and acquireSent
        and grant and grant.granted and beginSent and begun and begun.accepted
        and duplicateMiss and missSent and missed and missed.accepted
        and missed.view.serviceAttempts == 1 and missed.view.serviceMisses == 1
        and allTargets and guard == 10 and finalDuplicated
        and completed and completed.accepted and completed.code == "maintenance_completed"
        and state.inventory.stock.maintenance_kit == 0
        and wrapper.maintenance.serviceCount == 1 and saves == 1
        and targetPayload and targetPayload.itemIndex ~= nil
        and targetPayload.palletId == nil and targetPayload.amount == nil)

    client:stop("test_complete")
    host:update(0, hostContext)
    host:stop("test_complete")
end

return Test
