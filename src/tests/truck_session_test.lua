local Harness = require("src.tests.support.network_impairment_harness")
local Protocol = require("src.net.protocol")
local Session = require("src.net.session")
local TruckAuthority = require("src.truck_authority")
local WorkshopAuthority = require("src.workshop_authority")

local Test = {}

local function player(x, y)
    return {
        x = x, y = y, velocityX = 0, velocityY = 0,
        intentX = 0, intentY = 0, moving = false, facing = 1,
        animationDistance = 0, character = "rabbit-worker",
    }
end

local function eventNamed(events, name)
    for _, event in ipairs(events or {}) do
        if event.type == name then return event end
    end
end

function Test.run(context, check)
    local state = context.State.new()
    local job = assert(context.jobs.createOffer({
        id = "TRUCK-SESSION-DELIVERY",
        company = "Session Freight Co.",
        sourceSize = { width = 20, height = 16 },
        finishedSize = { width = 10, height = 8 },
        sheetCounts = { 500 }, packaging = "flat",
    }))
    assert(context.jobService.acceptOffer(state, job, 100))
    context.world.load()
    context.world.truck.state = "cargo_open"
    context.world.truck.mode = "delivery"
    context.world.truck.jobId = job.id
    context.world.truck.backingProgress = 1
    context.world.truck.cargoProgress = 1
    context.world._state = state
    local target = assert(context.world.truck:getInteraction())
    local saves = 0
    local authority = WorkshopAuthority.new({
        tokenGenerator = function(serial)
            return "truck-session-lease-" .. tostring(serial)
        end,
        resources = {
            truck = TruckAuthority.resource({
                state = state, world = context.world,
                save = function() saves = saves + 1 end,
            }),
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
    local hostPlayer = player(target.x - 20, target.y)
    local clientPlayer = player(target.x, target.y)
    local hostContext = {
        localPlayer = hostPlayer,
        resolveGuestSpawn = function() return target.x, target.y end,
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
    local observedCommand
    hostContext.performWorkshop = function(worker, operation, payload)
        if operation == "workshop_acquire" then
            return authority:acquire(worker, {
                requestId = payload.requestId, resourceId = payload.resourceId,
            }, {})
        elseif operation == "workshop_command" then
            observedCommand = payload
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
        name = "Truck Host", character = "rabbit-worker",
        addressOptions = { socket = { dns = {
            gethostname = function() return "truck-host" end,
            getaddrinfo = function() return { { addr = "192.168.1.91" } } end,
        } } },
    })
    host.sessionId = "truck-session-test"
    local clientStarted = client:startClient("192.168.1.91:22122", {
        name = "Truck Guest", character = "rabbit-worker",
    })
    client.clientNonce = "truck-session-client"
    if hostStarted and clientStarted then
        client:update(0, clientContext)
        host:update(0, hostContext)
        client:update(0, clientContext)
        host:update(0.1, hostContext)
        client:update(0, clientContext)
        client:drainEvents()
        host:drainEvents()
    end

    local acquireSent = client:requestWorkshopAcquire("truck")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local grant = eventNamed(client:drainEvents(), "workshop_grant")
    local duplicated = network:duplicateNext("client_to_host", 1, 1, true)
    local commandSent = client:requestWorkshopCommand("move_item", { itemIndex = 1 })
    host:update(0, hostContext)
    client:update(0, clientContext)
    local result = eventNamed(client:drainEvents(), "workshop_result")
    check("truck_session_guest_intent_round_trips_through_host_authority_exactly_once",
        hostStarted and clientStarted and client.ready
        and acquireSent and grant and grant.granted and grant.resourceId == "truck"
        and grant.view and grant.view.remaining == 1
        and duplicated and commandSent and observedCommand
        and observedCommand.itemIndex == 1 and observedCommand.palletId == nil
        and result and result.accepted and result.action == "move_item"
        and result.view and result.view.remaining == 0
        and job.pallets[1].location == "warehouse"
        and state.inventory.rawPallets == 1 and saves == 1)

    client:stop("test_complete")
    host:update(0, hostContext)
    host:stop("test_complete")
    context.world.load()
end

return Test
