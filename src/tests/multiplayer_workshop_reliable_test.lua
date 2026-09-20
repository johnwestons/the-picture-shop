local Protocol = require("src.net.protocol")
local Session = require("src.net.session")
local WorkshopAuthority = require("src.workshop_authority")
local Harness = require("src.tests.support.network_impairment_harness")

local Test = {}

local RESOURCE_ID = "office_computer"
local ACTION = "request_pickup"

local function player(x, y)
    return {
        x = x,
        y = y,
        velocityX = 0,
        velocityY = 0,
        intentX = 0,
        intentY = 0,
        moving = false,
        facing = 1,
        animationDistance = 0,
        character = "rabbit-worker",
    }
end

local function clientContext(index)
    return {
        localPlayer = player(420 + index * 20, 500),
        inputX = 0,
        inputY = 0,
    }
end

local function eventNamed(events, name)
    for _, event in ipairs(events or {}) do
        if event.type == name then return event end
    end
end

local function packetCount(network, direction, peerIndex, kind)
    local count = 0
    for _, item in ipairs(network.log) do
        if item.direction == direction and item.peerIndex == peerIndex
            and item.outcome ~= "failed" and item.outcome ~= "dropped"
            and item.kind == kind
        then
            count = count + 1
        end
    end
    return count
end

local function exactJobArguments(arguments)
    if type(arguments) ~= "table" or type(arguments.jobId) ~= "string"
        or not arguments.jobId:match("^[A-Za-z0-9_.%-]+$")
    then
        return nil, "invalid_arguments", "Job ID is invalid."
    end
    for key in pairs(arguments) do
        if key ~= "jobId" then
            return nil, "invalid_arguments", "Only a job ID is allowed."
        end
    end
    return { jobId = arguments.jobId }
end

function Test.run(_, check)
    local now = 2000
    local clock = function() return now end
    local network = Harness.new({
        maxClients = 3,
        classify = function(payload)
            local envelope = Protocol.decode(payload)
            return envelope and envelope.type or "invalid",
                envelope and envelope.type == "error" and envelope.payload.code or nil
        end,
    })
    local mutations, releases = {}, {}
    local authority = WorkshopAuthority.new({
        clock = clock,
        leaseTimeout = 30,
        tokenGenerator = function(serial)
            return "reliable-lease-" .. tostring(serial)
        end,
        resources = {
            [RESOURCE_ID] = {
                canAcquire = function() return true end,
                onAcquire = function()
                    return true, "acquired", "Office computer connected.", {}
                end,
                onRelease = function(_, _, reason)
                    releases[#releases + 1] = reason
                    return true
                end,
                commands = {
                    [ACTION] = {
                        normalize = exactJobArguments,
                        perform = function(_, _, arguments)
                            mutations[#mutations + 1] = arguments.jobId
                            return true, "pickup_requested", "Pickup requested.", {}
                        end,
                    },
                },
            },
        },
    })
    local host = Session.new({ transportFactory = network.factory, clock = clock })
    local hostPlayer = player(400, 500)
    local clients, clientContexts = {}, {}
    local ownerIndex = 2

    local context = {
        localPlayer = hostPlayer,
        resolveGuestSpawn = function(_, _, index)
            return 400 + index * 20, 500
        end,
        getShopSnapshot = function()
            return {
                state = {
                    money = 1200,
                    screen = "world",
                    inventory = { paper = 2500, prints = 0 },
                    jobs = { active = {}, completed = {} },
                },
                player = {
                    x = hostPlayer.x,
                    y = hostPlayer.y,
                    character = "rabbit-worker",
                },
            }
        end,
        getWorkshopSnapshot = function()
            return {
                resources = authority:snapshot(),
                wrapper = { step = "idle", progress = 0, cycleTime = 3, pallets = {} },
            }
        end,
        moveRemote = function(remote, dt, inputX, inputY)
            remote.x = remote.x + inputX * 100 * dt
            remote.y = remote.y + inputY * 100 * dt
        end,
        touchWorkshop = function(worker)
            authority:touchPlayer(worker)
        end,
        updateWorkshop = function()
            authority:update({})
        end,
    }
    context.performWorkshop = function(worker, operation, payload)
        if operation == "workshop_acquire" then
            local revision = authority:resourceRevision(payload.resourceId) or 0
            if payload.expectedRevision ~= revision then
                return {
                    accepted = false,
                    code = "revision_conflict",
                    message = "That workshop changed; try again.",
                    revision = revision,
                }
            end
            return authority:acquire(worker, {
                requestId = payload.requestId,
                resourceId = payload.resourceId,
            }, {})
        elseif operation == "workshop_command" then
            local arguments = {}
            if payload.jobId ~= nil then arguments.jobId = payload.jobId end
            return authority:command(worker, {
                requestId = payload.commandId,
                resourceId = payload.resourceId,
                leaseId = payload.leaseId,
                action = payload.action,
                args = arguments,
                expectedRevision = payload.expectedRevision,
            }, {})
        elseif operation == "workshop_release" then
            return authority:release(worker, {
                requestId = payload.requestId,
                resourceId = payload.resourceId,
                leaseId = payload.leaseId,
                reason = payload.reason,
            }, {})
        end
    end

    local hostStarted = host:startHost({
        name = "Reliable Host",
        character = "rabbit-worker",
        addressOptions = { socket = { dns = {
            gethostname = function() return "reliable-host" end,
            getaddrinfo = function() return { { addr = "192.168.1.90" } } end,
        } } },
    })
    host.sessionId = "workshop-reliable-session"
    local clientsStarted = true
    for index = 1, 3 do
        clients[index] = Session.new({ transportFactory = network.factory, clock = clock })
        clientContexts[index] = clientContext(index)
        local started = clients[index]:startClient("192.168.1.90:22122", {
            name = "Reliable Guest " .. tostring(index),
            character = "rabbit-worker",
        })
        clients[index].clientNonce = "reliable-initial-" .. tostring(index)
        clientsStarted = clientsStarted and started == true
    end
    if hostStarted and clientsStarted then
        for index = 1, 3 do clients[index]:update(0, clientContexts[index]) end
        host:update(0, context)
        for index = 1, 3 do clients[index]:update(0, clientContexts[index]) end
        host:update(0.1, context)
        for index = 1, 3 do
            clients[index]:update(0, clientContexts[index])
            clients[index]:drainEvents()
        end
    end

    local ownerClient = clients[ownerIndex]
    local ownerPeer = network:peer(ownerIndex)
    local ownerId = host.peerToId[ownerPeer]
    local owner = ownerId and host.players[ownerId]
    host:drainEvents()
    check("multiplayer_workshop_reliable_four_device_lab_is_ready",
        hostStarted and clientsStarted and owner and ownerClient.ready
        and host:hudInfo().playerCount == 4)

    local acquireSent = ownerClient:requestWorkshopAcquire(RESOURCE_ID)
    host:update(0, context)
    ownerClient:update(0, clientContexts[ownerIndex])
    local acquireEvent = eventNamed(ownerClient:drainEvents(), "workshop_grant")
    local firstWorkshop = ownerClient:workshopInfo()
    check("multiplayer_workshop_reliable_owner_acquires_real_authority_lease",
        acquireSent and acquireEvent and acquireEvent.granted and firstWorkshop
        and firstWorkshop.revision == 1
        and authority:leaseForPlayer(owner) ~= nil)

    local resultPacketsBeforeReplay = packetCount(
        network, "host_to_client", ownerIndex, "workshop_result")
    local duplicateArmed = network:duplicateNext(
        "client_to_host", ownerIndex, 1, true)
    local firstCommandSent = ownerClient:requestWorkshopCommand(
        ACTION, { jobId = "JOB-A" })
    host:update(0, context)
    ownerClient:update(0, clientContexts[ownerIndex])
    local firstResult = eventNamed(ownerClient:drainEvents(), "workshop_result")
    local exactReplay = firstWorkshop and Protocol.encode("workshop_command", {
        sessionId = host.sessionId,
        commandId = 2,
        leaseId = firstWorkshop.leaseId,
        resourceId = RESOURCE_ID,
        action = ACTION,
        expectedRevision = 1,
        jobId = "JOB-A",
    })
    local replayInjected = exactReplay and network:injectToHost(
        ownerIndex, exactReplay, Protocol.CHANNEL_CONTROL, 1)
    host:update(0, context)
    ownerClient:update(0, clientContexts[ownerIndex])
    ownerClient:drainEvents()
    local replayAndFirstExactlyOnce = duplicateArmed and firstCommandSent
        and firstResult and firstResult.accepted and replayInjected
        and #mutations == 1 and mutations[1] == "JOB-A"
        and authority:resourceRevision(RESOURCE_ID) == 2
        and packetCount(network, "host_to_client", ownerIndex, "workshop_result")
            == resultPacketsBeforeReplay + 2

    local delayedArmed = network:delayNext("client_to_host", ownerIndex, 3)
    local delayedSent = ownerClient:requestWorkshopCommand(
        ACTION, { jobId = "JOB-DELAY" })
    host:update(0, context)
    local secondBlocked = not ownerClient:requestWorkshopCommand(
        ACTION, { jobId = "JOB-TOO-EARLY" })
    local heldAtFirstStep = #mutations == 1 and network:advanceSteps(2)
    host:update(0, context)
    local heldAtSecondStep = #mutations == 1 and network:advanceSteps(1)
    host:update(0, context)
    ownerClient:update(0, clientContexts[ownerIndex])
    local delayedResult = eventNamed(ownerClient:drainEvents(), "workshop_result")
    local nextSent = ownerClient:requestWorkshopCommand(
        ACTION, { jobId = "JOB-NEXT" })
    host:update(0, context)
    ownerClient:update(0, clientContexts[ownerIndex])
    local nextResult = eventNamed(ownerClient:drainEvents(), "workshop_result")
    local replayAndDelayExactlyOnce = replayAndFirstExactlyOnce
        and delayedArmed and delayedSent and secondBlocked
        and heldAtFirstStep and heldAtSecondStep
        and delayedResult and delayedResult.accepted
        and nextSent and nextResult and nextResult.accepted
        and #mutations == 3
        and mutations[1] == "JOB-A"
        and mutations[2] == "JOB-DELAY"
        and mutations[3] == "JOB-NEXT"
        and authority:resourceRevision(RESOURCE_ID) == 4
        and ownerClient:workshopInfo().revision == 4
    check("multiplayer_workshop_reliable_replay_and_delay_execute_commands_exactly_once",
        replayAndDelayExactlyOnce)

    local oldLeaseId = ownerClient:workshopInfo().leaseId
    local staleArmed = network:delayNext("client_to_host", ownerIndex, 3)
    local staleSent = ownerClient:requestWorkshopCommand(
        ACTION, { jobId = "JOB-STALE" })
    local disconnected = network:disconnectPeer(ownerIndex, 71)
    host:update(0, context)
    local leftEvent = eventNamed(host:drainEvents(), "player_left")
    local cleanupEvents = authority:cleanupPlayer(
        { id = ownerId }, "disconnected", {})
    ownerClient:update(0, clientContexts[ownerIndex])
    local oldClientStopped = ownerClient:stop("Reliable boundary replacement")
    for index = 1, 3 do
        if index ~= ownerIndex then
            clients[index]:update(0, clientContexts[index])
            clients[index]:drainEvents()
        end
    end

    local replacement = Session.new({ transportFactory = network.factory, clock = clock })
    local replacementContext = clientContext(ownerIndex)
    local replacementStarted = replacement:startClient("192.168.1.90:22122", {
        name = "Reliable Replacement",
        character = "rabbit-worker",
    })
    replacement.clientNonce = "reliable-replacement"
    replacement:update(0, replacementContext)
    host:update(0, context)
    replacement:update(0, replacementContext)
    replacement:drainEvents()
    host:update(0.1, context)
    replacement:update(0, replacementContext)
    replacement:drainEvents()
    clients[ownerIndex], clientContexts[ownerIndex] = replacement, replacementContext
    local replacementPeer = network:peer(ownerIndex)
    local replacementOwner = host.players[ownerId]
    local replacementAcquireSent = replacement:requestWorkshopAcquire(RESOURCE_ID)
    host:update(0, context)
    replacement:update(0, replacementContext)
    local replacementGrant = eventNamed(replacement:drainEvents(), "workshop_grant")
    local replacementWorkshop = replacement:workshopInfo()
    local resultPacketsBeforeStale = packetCount(
        network, "host_to_client", ownerIndex, "workshop_result")

    local staleReleased = network:advanceSteps(3)
    host:update(0, context)
    replacement:update(0, replacementContext)
    local replacementEventsAfterStale = replacement:drainEvents()
    local replacementLeaseAfterStale = authority:leaseForPlayer(replacementOwner)
    local staleBlocked = staleArmed and staleSent and disconnected
        and leftEvent and leftEvent.playerId == ownerId
        and #cleanupEvents == 1 and cleanupEvents[1].reason == "disconnected"
        and oldClientStopped and not ownerClient:isActive()
        and replacementStarted and replacement.ready
        and replacementPeer ~= ownerPeer and host.peerToId[replacementPeer] == ownerId
        and replacementAcquireSent and replacementGrant and replacementGrant.granted
        and replacementWorkshop and replacementWorkshop.leaseId ~= oldLeaseId
        and replacementWorkshop.revision == 6
        and replacementLeaseAfterStale
        and replacementLeaseAfterStale.leaseId == replacementWorkshop.leaseId
        and staleReleased and #mutations == 3
        and eventNamed(replacementEventsAfterStale, "workshop_result") == nil
        and packetCount(network, "host_to_client", ownerIndex, "workshop_result")
            == resultPacketsBeforeStale

    local freshSent = replacement:requestWorkshopCommand(
        ACTION, { jobId = "JOB-FRESH" })
    host:update(0, context)
    replacement:update(0, replacementContext)
    local freshResult = eventNamed(replacement:drainEvents(), "workshop_result")
    local disconnectBarrierWorked = staleBlocked and freshSent
        and freshResult and freshResult.accepted
        and #mutations == 4 and mutations[4] == "JOB-FRESH"
        and authority:resourceRevision(RESOURCE_ID) == 7
        and replacement:workshopInfo().revision == 7
    check("multiplayer_workshop_reliable_disconnect_barrier_blocks_stale_generation_command",
        disconnectBarrierWorked)

    authority:cleanupPlayer({ id = ownerId }, "test_complete", {})
    host:stop("Reliable workshop test complete")
    for index = 1, 3 do clients[index]:stop("Reliable workshop test complete") end
    local disposed = network:dispose()
    check("multiplayer_workshop_reliable_teardown_releases_all_test_state",
        disposed and network:isQuiescent() and not host:isActive()
        and not clients[1]:isActive() and not clients[2]:isActive()
        and not clients[3]:isActive()
        and authority:leaseForResource(RESOURCE_ID) == nil
        and releases[1] == "disconnected" and releases[2] == "test_complete")
end

return Test
