local Protocol = require("src.net.protocol")
local Session = require("src.net.session")
local Harness = require("src.tests.support.network_impairment_harness")

local Test = {}

local SOAK_CYCLES = 9

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

local function countEntries(values)
    local count = 0
    for _ in pairs(values or {}) do count = count + 1 end
    return count
end

local function packetCount(network, direction, peerIndex, kind, code)
    local count = 0
    for _, item in ipairs(network.log) do
        if item.direction == direction and item.peerIndex == peerIndex
            and item.outcome ~= "failed" and item.outcome ~= "dropped"
            and item.kind == kind and (code == nil or item.code == code)
        then
            count = count + 1
        end
    end
    return count
end

local function clientContext(index)
    return {
        localPlayer = player(420 + index * 20, 500),
        inputX = 0,
        inputY = 0,
    }
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

function Test.run(_, check)
    local now = 700
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
    local clients, clientContexts, stoppedClients = {}, {}, {}

    local hostStarted = host:startHost({
        name = "Soak Host",
        character = "rabbit-worker",
        addressOptions = { socket = { dns = {
            gethostname = function() return "soak-host" end,
            getaddrinfo = function() return { { addr = "192.168.1.70" } } end,
        } } },
    })
    host.sessionId = "multiplayer-soak-session"

    local clientsStarted = true
    for index = 1, 3 do
        clients[index] = Session.new({
            transportFactory = network.factory,
            clock = clock,
        })
        clientContexts[index] = clientContext(index)
        local started = clients[index]:startClient("192.168.1.70:22122", {
            name = "Soak Guest " .. tostring(index),
            character = "rabbit-worker",
        })
        clients[index].clientNonce = "soak-initial-" .. tostring(index)
        clientsStarted = clientsStarted and started == true
    end
    if hostStarted and clientsStarted then
        for index = 1, 3 do clients[index]:update(0, clientContexts[index]) end
        host:update(0, context)
        for index = 1, 3 do clients[index]:update(0, clientContexts[index]) end
        host:update(0.1, context)
        for index = 1, 3 do clients[index]:update(0, clientContexts[index]) end
    end

    local allGood = hostStarted and clientsStarted and host:hudInfo().playerCount == 4
    check("multiplayer_soak_initial_four_device_roster_is_ready",
        allGood and clients[1].ready and clients[2].ready and clients[3].ready)
    local completedCycles = 0
    for cycle = 1, SOAK_CYCLES do
        local target = ((cycle - 1) % 3) + 1
        local quiet = (target % 3) + 1
        local targetId = host.peerToId[network:peer(target)]
        local quietId = host.peerToId[network:peer(quiet)]
        local oldPeer = network:peer(target)
        local oldClient = clients[target]

        now = now + 1.01
        local cycleTouches = {}
        local quietTouchedBeforeWorkshop = false
        context.touchWorkshop = function(worker)
            if worker then cycleTouches[worker.id] = true end
        end
        context.updateWorkshop = function()
            if quietId and cycleTouches[quietId] then
                quietTouchedBeforeWorkshop = true
            end
        end

        local errorStart = packetCount(
            network, "host_to_client", target, "error", "bad_packet")
        local pongStart = packetCount(network, "host_to_client", quiet, "pong")
        local malformedQueued = network:injectToHost(
            target, "soak-invalid-packet", Protocol.CHANNEL_STATE, 64)
        local ping = Protocol.encode("ping", {
            sessionId = host.sessionId,
            nonce = 6000 + cycle,
        })
        local pingQueued = network:injectToHost(
            quiet, ping, Protocol.CHANNEL_STATE, 1)
        local serviceStart = #network.serviceCalls
        host:update(0, context)
        local firstFloodService = network.serviceCalls[serviceStart + 1]
        local firstFrameFair = firstFloodService
            and firstFloodService.delivered == Protocol.MAX_EVENTS_PER_UPDATE
            and packetCount(network, "host_to_client", quiet, "pong") == pongStart + 1
            and packetCount(network, "host_to_client", target, "error", "bad_packet")
                == errorStart + 1
            and quietTouchedBeforeWorkshop and not cycleTouches[targetId]
        host:update(0, context)
        local secondFloodService = network.serviceCalls[serviceStart + 2]
        local floodDrained = secondFloodService and secondFloodService.delivered == 1
            and packetCount(network, "host_to_client", target, "error", "bad_packet")
                == errorStart + 1
            and network:pendingFor("host") == 0

        local delayedOldInputQueued = network:delayNext("client_to_host", target, 3)
        local delayedOldInputSent = oldClient:sendNeutralInput()
        local disconnected = network:disconnectPeer(target, 40 + cycle)
        host:update(0, context)
        oldClient:update(0, clientContexts[target])
        local oldClientStopped = oldClient:stop("Soak replacement")
        stoppedClients[#stoppedClients + 1] = oldClient
        for index = 1, 3 do
            if index ~= target then
                clients[index]:update(0, clientContexts[index])
                clients[index]:drainEvents()
            end
        end
        local removedCleanly = disconnected and oldClientStopped
            and not oldClient:isActive() and host.players[targetId] == nil
            and host:hudInfo().playerCount == 3 and not host.terminal

        local replacement = Session.new({
            transportFactory = network.factory,
            clock = clock,
        })
        local replacementContext = clientContext(target)
        local replacementStarted = replacement:startClient("192.168.1.70:22122", {
            name = "Soak Replacement " .. tostring(cycle),
            character = "rabbit-worker",
        })
        replacement.clientNonce = "soak-replacement-" .. tostring(cycle)
        replacement:update(0, replacementContext)
        host:update(0, context)
        replacement:update(0, replacementContext)
        clients[target], clientContexts[target] = replacement, replacementContext
        local newPeer = network:peer(target)
        local replacementReady = replacementStarted and replacement.ready
            and newPeer ~= oldPeer and replacement.localId == targetId
            and host.peerToId[newPeer] == targetId
            and host:hudInfo().playerCount == 4

        local freshErrorStart = packetCount(
            network, "host_to_client", target, "error", "bad_packet")
        local freshMalformedQueued = network:injectToHost(
            target, "soak-fresh-generation-invalid", Protocol.CHANNEL_STATE, 1)
        host:update(0, context)
        local freshGenerationReplied = packetCount(
            network, "host_to_client", target, "error", "bad_packet")
                == freshErrorStart + 1
        replacement:update(0, replacementContext)

        local staleReplyStart = packetCount(network, "host_to_client", target, "error")
        network:advanceSteps(3)
        host:update(0, context)
        local staleGenerationIgnored = host.players[targetId]
            and host.players[targetId].lastInputSequence == -1
            and packetCount(network, "host_to_client", target, "error") == staleReplyStart

        local sequences, expectedSequences, inputsSent = {}, {}, true
        for index = 1, 3 do
            local id = host.peerToId[network:peer(index)]
            sequences[index] = id and host.players[id].lastInputSequence or nil
            inputsSent = clients[index]:sendNeutralInput() and inputsSent
            expectedSequences[index] = clients[index].inputSequence
        end
        host:update(0, context)
        local allInputsAdvanced = true
        for index = 1, 3 do
            local id = host.peerToId[network:peer(index)]
            allInputsAdvanced = allInputsAdvanced and id ~= nil
                and host.players[id].lastInputSequence == expectedSequences[index]
                and host.players[id].lastInputSequence > sequences[index]
        end
        host:update(0.1, context)
        for index = 1, 3 do clients[index]:update(0, clientContexts[index]) end
        local allClientsReady = true
        for index = 1, 3 do
            allClientsReady = allClientsReady and clients[index].ready
                and clients[index]:hudInfo().playerCount == 4
                and network:pendingFor("client", index) == 0
        end

        local boundedBookkeeping = countEntries(host.pendingPeers) == 0
            and countEntries(host.approvalRequests) == 0
            and countEntries(host.protocolRejectionAt) <= 3
            and network:pendingFor("host") == 0
        local ingressGood = targetId and quietId and malformedQueued and ping and pingQueued
            and firstFrameFair and floodDrained
        local removalGood = delayedOldInputQueued and delayedOldInputSent and removedCleanly
        local replacementGood = replacementReady and freshMalformedQueued
            and freshGenerationReplied
        local recoveryGood = staleGenerationIgnored and inputsSent and allInputsAdvanced
            and allClientsReady and boundedBookkeeping and not host.terminal
        local cycleGood = ingressGood and removalGood and replacementGood and recoveryGood
        check("multiplayer_soak_cycle_" .. tostring(cycle)
            .. "_flood_preserves_quiet_peer", ingressGood)
        check("multiplayer_soak_cycle_" .. tostring(cycle)
            .. "_disconnect_retires_only_target", removalGood)
        check("multiplayer_soak_cycle_" .. tostring(cycle)
            .. "_replacement_gets_fresh_generation", replacementGood)
        check("multiplayer_soak_cycle_" .. tostring(cycle)
            .. "_stale_input_is_ignored", staleGenerationIgnored)
        check("multiplayer_soak_cycle_" .. tostring(cycle)
            .. "_all_guest_inputs_advance", inputsSent and allInputsAdvanced)
        check("multiplayer_soak_cycle_" .. tostring(cycle)
            .. "_all_rosters_reconverge", allClientsReady)
        check("multiplayer_soak_cycle_" .. tostring(cycle)
            .. "_bookkeeping_remains_bounded", boundedBookkeeping and not host.terminal)
        allGood = allGood and cycleGood
        if cycleGood then completedCycles = completedCycles + 1 end
    end

    local allStoppedClientsInactive = true
    for _, stopped in ipairs(stoppedClients) do
        allStoppedClientsInactive = allStoppedClientsInactive and not stopped:isActive()
    end
    local generationsBounded = network.generations[1] == 4
        and network.generations[2] == 4 and network.generations[3] == 4
        and #network.allLinks == 12 and host.nextConnectionGeneration == 12

    host:stop("Multiplayer soak complete")
    for index = 1, 3 do clients[index]:stop("Multiplayer soak complete") end
    local disposed = network:dispose()
    check("multiplayer_soak_nine_rotating_rejoins_keep_host_and_guests_bounded",
        allGood and completedCycles == SOAK_CYCLES and generationsBounded
        and allStoppedClientsInactive and disposed and network:isQuiescent()
        and not host:isActive() and next(host.protocolRejectionAt) == nil
        and not clients[1]:isActive() and not clients[2]:isActive()
        and not clients[3]:isActive())
end

return Test
