local Protocol = require("src.net.protocol")
local Session = require("src.net.session")
local Harness = require("src.tests.support.network_impairment_harness")

local Test = {}

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

local function errorCodeCount(network, peerIndex, code)
    local count = 0
    for _, item in ipairs(network.log) do
        if item.direction == "host_to_client" and item.peerIndex == peerIndex
            and item.outcome ~= "failed" and item.outcome ~= "dropped"
            and item.kind == "error" and item.code == code
        then
            count = count + 1
        end
    end
    return count
end

local function transmissionRecorded(network, direction, peerIndex, kind, expected)
    for index = #network.log, 1, -1 do
        local item = network.log[index]
        if item.direction == direction and item.peerIndex == peerIndex
            and item.kind == kind
        then
            local matches = true
            for key, value in pairs(expected or {}) do
                if item[key] ~= value then
                    matches = false
                    break
                end
            end
            if matches then return true end
        end
    end
    return false
end

local function hostContext(hostPlayer)
    return {
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
        moveRemote = function(remote, dt, inputX, inputY)
            remote.x = remote.x + inputX * 100 * dt
            remote.y = remote.y + inputY * 100 * dt
            remote.inputX, remote.inputY = inputX, inputY
        end,
    }
end

local function clientContext(index)
    return {
        localPlayer = player(420 + index * 20, 500),
        inputX = index / 4,
        inputY = -index / 5,
    }
end

function Test.run(_, check)
    local now = 200
    local clock = function() return now end
    local network = Harness.new({
        maxClients = 3,
        classify = function(payload)
            local envelope = Protocol.decode(payload)
            return envelope and envelope.type or "invalid",
                envelope and envelope.type == "error" and envelope.payload.code or nil
        end,
    })
    local host = Session.new({ transportFactory = network.factory, clock = clock })
    local hostPlayer = player(400, 500)
    local context = hostContext(hostPlayer)
    local clients, clientContexts = {}, {}

    local hostStarted = host:startHost({
        name = "Impairment Host",
        character = "rabbit-worker",
        addressOptions = { socket = { dns = {
            gethostname = function() return "impairment-host" end,
            getaddrinfo = function() return { { addr = "192.168.1.50" } } end,
        } } },
    })
    host.sessionId = "impairment-session"

    local clientsStarted = true
    for index = 1, 3 do
        clients[index] = Session.new({
            transportFactory = network.factory,
            clock = clock,
        })
        clientContexts[index] = clientContext(index)
        local started = clients[index]:startClient("192.168.1.50:22122", {
            name = "Impairment Guest " .. tostring(index),
            character = "rabbit-worker",
        })
        clients[index].clientNonce = "impairment-nonce-" .. tostring(index)
        clientsStarted = clientsStarted and started == true
    end

    local fourthTransport, fourthError = network.factory.createClient(
        "192.168.1.50:22122", { channels = Protocol.CHANNEL_COUNT })
    check("multiplayer_impairment_four_device_lab_starts_without_real_sockets",
        network ~= nil and hostStarted and clientsStarted
        and network.hostOptions.maxGuests == 3
        and network.hostOptions.channels == Protocol.CHANNEL_COUNT
        and fourthTransport == nil and fourthError == "impairment network is full")
    if not hostStarted or not clientsStarted then return end

    local duplicateQueued = network:duplicateNext("client_to_host", 1, 1, true)
    local delayedQueued = network:delayNext("client_to_host", 2, 2)
    for index = 1, 3 do clients[index]:update(0, clientContexts[index]) end
    host:update(0, context)
    local reorderedBeforeAdvance = host.peerToId[network:peer(2)] == nil
    network:advanceSteps(2)
    host:update(0, context)
    for index = 1, 3 do clients[index]:update(0, clientContexts[index]) end
    host:update(0.1, context)
    for index = 1, 3 do clients[index]:update(0, clientContexts[index]) end

    local allReady = true
    for index = 1, 3 do
        allReady = allReady and clients[index].ready == true
            and host.peerToId[network:peer(index)] ~= nil
            and clients[index]:hudInfo().playerCount == 4
    end
    check("multiplayer_impairment_duplicate_and_reordered_admission_converges_to_four_players",
        duplicateQueued and delayedQueued and reorderedBeforeAdvance and allReady
        and host:hudInfo().playerCount == 4
        and errorCodeCount(network, 1, "already_joined") == 1)

    local firstId = host.peerToId[network:peer(1)]
    local secondId = host.peerToId[network:peer(2)]
    local thirdId = host.peerToId[network:peer(3)]

    local dropQueued = network:dropNext("client_to_host", 1)
    clients[1]:update(0.05, clientContexts[1])
    local dropRecorded = transmissionRecorded(network,
        "client_to_host", 1, "input", {
            outcome = "dropped",
            deliveries = 0,
            reliable = false,
            channel = Protocol.CHANNEL_STATE,
        })
    host:update(0, context)
    local droppedDidNotAdvance = host.players[firstId].lastInputSequence == -1
    clients[1]:update(0.05, clientContexts[1])
    host:update(0, context)

    local reorderQueued = network:delayNext("client_to_host", 2, 2)
    clients[2]:update(0.05, clientContexts[2])
    clients[2]:update(0.05, clientContexts[2])
    local reorderRecorded = transmissionRecorded(network,
        "client_to_host", 2, "input", {
            outcome = "queued", delay = 0,
            reliable = false, channel = Protocol.CHANNEL_STATE,
        })
        and transmissionRecorded(network,
            "client_to_host", 2, "input", {
                outcome = "queued", delay = 2,
                reliable = false, channel = Protocol.CHANNEL_STATE,
            })
    local reorderServiceStart = #network.serviceCalls
    host:update(0, context)
    local reorderedDelivery = network.serviceCalls[reorderServiceStart + 1]
    local newerBeatDelayed = host.players[secondId].lastInputSequence == 2
    network:advanceSteps(2)
    local delayedServiceStart = #network.serviceCalls
    host:update(0, context)
    local delayedDelivery = network.serviceCalls[delayedServiceStart + 1]

    local duplicateInputQueued = network:duplicateNext("client_to_host", 3, 2)
    clients[3]:update(0.05, clientContexts[3])
    local duplicateRecorded = transmissionRecorded(network,
        "client_to_host", 3, "input", {
            outcome = "queued", deliveries = 3,
            reliable = false, channel = Protocol.CHANNEL_STATE,
        })
    local duplicateServiceStart = #network.serviceCalls
    host:update(0, context)
    local duplicateDelivery = network.serviceCalls[duplicateServiceStart + 1]
    check("multiplayer_impairment_inputs_recover_from_loss_reordering_and_duplication",
        dropQueued and dropRecorded and droppedDidNotAdvance
        and host.players[firstId].lastInputSequence == 2
        and reorderQueued and reorderRecorded and newerBeatDelayed
        and reorderedDelivery and reorderedDelivery.delivered == 1
        and delayedDelivery and delayedDelivery.delivered == 1
        and host.players[secondId].lastInputSequence == 2
        and duplicateInputQueued and duplicateRecorded
        and duplicateDelivery and duplicateDelivery.delivered == 3
        and host.players[thirdId].lastInputSequence == 1)

    now = now + 1.01
    local rejectionWindowStart = now
    local workshopGuard = {
        quietTouched = false,
        noisyTouched = false,
        checked = false,
        survived = false,
    }
    context.touchWorkshop = function(worker)
        if worker and worker.id == secondId then workshopGuard.quietTouched = true end
        if worker and worker.id == firstId then workshopGuard.noisyTouched = true end
    end
    context.updateWorkshop = function()
        workshopGuard.checked = true
        workshopGuard.survived = workshopGuard.quietTouched
    end

    local malformedQueued = network:injectToHost(
        1, "not-a-canonical-picture-shop-packet", Protocol.CHANNEL_STATE, 70)
    local ping = Protocol.encode("ping", {
        sessionId = host.sessionId,
        nonce = 4242,
    })
    local pingQueued = network:injectToHost(2, ping, Protocol.CHANNEL_STATE, 1)
    local serviceStart = #network.serviceCalls
    local pongStart = packetCount(network, "host_to_client", 2, "pong")
    local badPacketStart = errorCodeCount(network, 1, "bad_packet")
    local messageNotAllowedStart = errorCodeCount(network, 1, "message_not_allowed")
    host:update(0, context)
    local pongAfterFirst = packetCount(network, "host_to_client", 2, "pong")
    local badPacketAfterFirst = errorCodeCount(network, 1, "bad_packet")
    local workshopOrderingHeld = workshopGuard.checked and workshopGuard.survived
        and workshopGuard.quietTouched and not workshopGuard.noisyTouched
    host:update(0, context)
    local firstFloodCall = network.serviceCalls[serviceStart + 1]
    local secondFloodCall = network.serviceCalls[serviceStart + 2]
    local badPacketAfterDrain = errorCodeCount(network, 1, "bad_packet")

    local forbiddenPong = Protocol.encode("pong", {
        sessionId = host.sessionId,
        nonce = 5150,
    })
    now = rejectionWindowStart + 0.5
    local forbiddenQueued = network:injectToHost(
        1, forbiddenPong, Protocol.CHANNEL_STATE, 1)
    host:update(0, context)
    local messageNotAllowedBeforeExpiry =
        errorCodeCount(network, 1, "message_not_allowed")
    now = rejectionWindowStart + 1.01
    local boundaryPacketQueued = network:injectToHost(
        1, "another-invalid-picture-shop-packet", Protocol.CHANNEL_STATE, 1)
    host:update(0, context)
    local badPacketAfterBoundary = errorCodeCount(network, 1, "bad_packet")
    clients[1]:update(0, clientContexts[1])
    clients[1]:update(0, clientContexts[1])
    clients[1]:drainEvents()
    clients[2]:update(0, clientContexts[2])
    local floodQueuesDrained = network:pendingFor("host") == 0
        and network:pendingFor("client", 1) == 0
        and network:pendingFor("client", 2) == 0
        and network:pendingFor("client", 3) == 0
    check("multiplayer_impairment_round_robin_flood_preserves_quiet_peer_and_throttles_replies",
        malformedQueued and pingQueued
        and network.hostDispatch == "enet_round_robin"
        and firstFloodCall and firstFloodCall.requested == Protocol.MAX_EVENTS_PER_UPDATE
        and firstFloodCall.delivered == Protocol.MAX_EVENTS_PER_UPDATE
        and firstFloodCall.dispatch == "enet_round_robin"
        and secondFloodCall and secondFloodCall.requested == Protocol.MAX_EVENTS_PER_UPDATE
        and secondFloodCall.delivered <= Protocol.MAX_EVENTS_PER_UPDATE
        and firstFloodCall.delivered + secondFloodCall.delivered == 71
        and pongAfterFirst == pongStart + 1
        and badPacketAfterFirst == badPacketStart + 1
        and badPacketAfterDrain == badPacketStart + 1
        and forbiddenPong and forbiddenQueued
        and messageNotAllowedBeforeExpiry == messageNotAllowedStart
        and boundaryPacketQueued and badPacketAfterBoundary == badPacketStart + 2
        and workshopOrderingHeld and floodQueuesDrained
        and not host.terminal and host:hudInfo().playerCount == 4)

    local firstSequence = host.players[firstId].lastInputSequence
    local secondSequence = host.players[secondId].lastInputSequence
    local oldFirstPeer = network:peer(1)
    local delayedOldInputQueued = network:delayNext("client_to_host", 1, 4)
    local delayedOldInputSent = clients[1]:sendNeutralInput()
    local failed = network:failPeer(1, "simulated radio loss")
    local staleDropQueued = network:dropNext("client_to_host", 1)
    local failedSend = clients[1]:sendNeutralInput()
    local healthySend = clients[2]:sendNeutralInput()
    host:update(0, context)
    local isolated = delayedOldInputQueued and delayedOldInputSent
        and failed and staleDropQueued and failedSend == false and healthySend == true
        and host.players[firstId].lastInputSequence == firstSequence
        and host.players[secondId].lastInputSequence == secondSequence + 1
        and not host.terminal

    local disconnected = network:disconnectPeer(1, 19)
    host:update(0, context)
    local oldFirstClient = clients[1]
    oldFirstClient:update(0, clientContexts[1])
    local oldFirstTransportClosed = oldFirstClient.terminal
        and oldFirstClient.transport == nil
    local oldFirstStopped = oldFirstClient:stop("Replacing failed impairment guest")
    clients[2]:update(0, clientContexts[2])
    clients[3]:update(0, clientContexts[3])
    local leftSecond = eventNamed(clients[2]:drainEvents(), "player_left")
    local leftThird = eventNamed(clients[3]:drainEvents(), "player_left")
    local removalIsolated = isolated and disconnected
        and oldFirstTransportClosed and oldFirstStopped
        and not oldFirstClient:isActive()
        and host.players[firstId] == nil
        and leftSecond and leftSecond.playerId == firstId
        and leftThird and leftThird.playerId == firstId
        and clients[2].ready and clients[3].ready
        and host:hudInfo().playerCount == 3 and not host.terminal

    local replacement = Session.new({
        transportFactory = network.factory,
        clock = clock,
    })
    local replacementContext = clientContext(1)
    local replacementStarted = replacement:startClient("192.168.1.50:22122", {
        name = "Replacement Guest",
        character = "rabbit-worker",
    })
    replacement.clientNonce = "impairment-replacement-nonce"
    replacement:update(0, replacementContext)
    host:update(0, context)
    replacement:update(0, replacementContext)
    host:update(0.1, context)
    replacement:update(0, replacementContext)
    clients[2]:update(0, clientContexts[2])
    clients[3]:update(0, clientContexts[3])
    local freshGenerationErrorStart = errorCodeCount(network, 1, "bad_packet")
    local freshGenerationReplyStart = packetCount(network, "host_to_client", 1, "error")
    local freshGenerationMalformedQueued = network:injectToHost(
        1, "fresh-generation-invalid-packet", Protocol.CHANNEL_STATE, 1)
    host:update(0, context)
    local freshGenerationGotDiagnostic =
        errorCodeCount(network, 1, "bad_packet") == freshGenerationErrorStart + 1
        and packetCount(network, "host_to_client", 1, "error")
            == freshGenerationReplyStart + 1
    replacement:update(0, replacementContext)
    network:advanceSteps(4)
    host:update(0, context)
    local staleGenerationRejected = host.players[firstId].lastInputSequence == -1
        and errorCodeCount(network, 1, "bad_packet") == freshGenerationErrorStart + 1
        and packetCount(network, "host_to_client", 1, "error")
            == freshGenerationReplyStart + 1
    check("multiplayer_impairment_client_send_failure_disconnect_and_rejoin_are_isolated",
        removalIsolated and replacementStarted and replacement.ready
        and replacement.localId == firstId and network:peer(1) ~= oldFirstPeer
        and host.peerToId[network:peer(1)] == firstId
        and freshGenerationMalformedQueued and freshGenerationGotDiagnostic
        and staleGenerationRejected
        and host:hudInfo().playerCount == 4
        and replacement:hudInfo().playerCount == 4
        and clients[2].ready and clients[3].ready and not host.terminal)

    clients[1] = replacement

    host:stop("Impairment lab complete")
    for index = 1, 3 do clients[index]:stop("Impairment lab complete") end
    local disposed = network:dispose()
    check("multiplayer_impairment_lab_teardown_discards_all_test_packet_state",
        disposed and network:isQuiescent()
        and not host:isActive()
        and not clients[1]:isActive()
        and not clients[2]:isActive()
        and not clients[3]:isActive()
        and not oldFirstClient:isActive()
        and next(host.protocolRejectionAt) == nil)
end

return Test
