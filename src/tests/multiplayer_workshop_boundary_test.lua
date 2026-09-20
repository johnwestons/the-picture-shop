local Protocol = require("src.net.protocol")
local Session = require("src.net.session")
local WorkshopAuthority = require("src.workshop_authority")
local Harness = require("src.tests.support.network_impairment_harness")

local Test = {}

local LEASE_TIMEOUT = 10
local RESOURCE_ID = "office_computer"

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

function Test.run(_, check)
    local now = 1000
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
    local clients, clientContexts = {}, {}
    local ownerIndex, noisyIndex = 2, 1
    local activeAuthority, authorityTrace
    local authoritySerial = 0

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
        moveRemote = function(remote, dt, inputX, inputY)
            remote.x = remote.x + inputX * 100 * dt
            remote.y = remote.y + inputY * 100 * dt
        end,
    }

    local function activateAuthority(owner, acquiredAt)
        now = acquiredAt
        authoritySerial = authoritySerial + 1
        local trace = { touches = {}, timeoutEvents = {}, releases = {} }
        local serial = authoritySerial
        local authority = WorkshopAuthority.new({
            clock = clock,
            leaseTimeout = LEASE_TIMEOUT,
            tokenGenerator = function(tokenSerial)
                return "boundary-" .. tostring(serial) .. "-" .. tostring(tokenSerial)
            end,
            resources = {
                [RESOURCE_ID] = {
                    canAcquire = function() return true end,
                    onRelease = function(_, _, reason)
                        trace.releases[#trace.releases + 1] = reason
                        return true
                    end,
                    commands = {},
                },
            },
        })
        local acquired = authority:acquire(owner, {
            requestId = 1,
            resourceId = RESOURCE_ID,
        }, {})
        activeAuthority, authorityTrace = authority, trace
        context.touchWorkshop = function(worker)
            if worker then
                trace.touches[worker.id] = (trace.touches[worker.id] or 0) + 1
                authority:touchPlayer(worker)
            end
        end
        context.updateWorkshop = function()
            local events = authority:update({})
            for _, event in ipairs(events) do
                trace.timeoutEvents[#trace.timeoutEvents + 1] = event
            end
        end
        return authority, trace, acquired
    end

    local hostStarted = host:startHost({
        name = "Workshop Boundary Host",
        character = "rabbit-worker",
        addressOptions = { socket = { dns = {
            gethostname = function() return "workshop-boundary-host" end,
            getaddrinfo = function() return { { addr = "192.168.1.80" } } end,
        } } },
    })
    host.sessionId = "workshop-boundary-session"
    local clientsStarted = true
    for index = 1, 3 do
        clients[index] = Session.new({
            transportFactory = network.factory,
            clock = clock,
        })
        clientContexts[index] = clientContext(index)
        local started = clients[index]:startClient("192.168.1.80:22122", {
            name = "Boundary Guest " .. tostring(index),
            character = "rabbit-worker",
        })
        clients[index].clientNonce = "workshop-boundary-" .. tostring(index)
        clientsStarted = clientsStarted and started == true
    end
    if hostStarted and clientsStarted then
        for index = 1, 3 do clients[index]:update(0, clientContexts[index]) end
        host:update(0, context)
        for index = 1, 3 do clients[index]:update(0, clientContexts[index]) end
        host:update(0.1, context)
        for index = 1, 3 do clients[index]:update(0, clientContexts[index]) end
    end
    local ownerPeer = network:peer(ownerIndex)
    local ownerId = host.peerToId[ownerPeer]
    local owner = ownerId and host.players[ownerId]
    check("multiplayer_workshop_boundary_host_starts", hostStarted)
    check("multiplayer_workshop_boundary_three_clients_start", clientsStarted)
    check("multiplayer_workshop_boundary_host_admits_three_guests",
        host:hudInfo().playerCount == 4)
    check("multiplayer_workshop_boundary_owner_identity_is_mapped", owner ~= nil)
    check("multiplayer_workshop_boundary_all_guest_rosters_are_ready",
        clients[1].ready and clients[2].ready and clients[3].ready
        and clients[1]:hudInfo().playerCount == 4
        and clients[2]:hudInfo().playerCount == 4
        and clients[3]:hudInfo().playerCount == 4)

    local authority, trace, acquired = activateAuthority(owner, 1000)
    now = 1010
    local serviceStart = #network.serviceCalls
    local malformedQueued = network:injectToHost(
        noisyIndex, "workshop-boundary-invalid", Protocol.CHANNEL_STATE, 64)
    local ownerInputSent = clients[ownerIndex]:sendNeutralInput()
    host:update(0, context)
    local firstService = network.serviceCalls[serviceStart + 1]
    local survivedFirstUpdate = authority:leaseForPlayer(owner) ~= nil
        and #trace.timeoutEvents == 0
    host:update(0, context)
    local secondService = network.serviceCalls[serviceStart + 2]
    local currentOwnerSurvived = acquired.accepted and malformedQueued and ownerInputSent
        and firstService and firstService.delivered == Protocol.MAX_EVENTS_PER_UPDATE
        and secondService and secondService.delivered == 1
        and survivedFirstUpdate and authority:leaseForPlayer(owner) ~= nil
        and #trace.timeoutEvents == 0
        and trace.touches[ownerId] == 1 and trace.touches[host.localId] == 2
        and trace.touches[host.peerToId[network:peer(noisyIndex)]] == nil
        and host.players[ownerId].lastInputSequence == clients[ownerIndex].inputSequence
        and not host.terminal
    check("multiplayer_workshop_boundary_current_owner_input_survives_noisy_exact_timeout",
        currentOwnerSurvived)

    now = 1019.999
    host:update(0, context)
    local survivedBeforeNextDeadline = authority:leaseForPlayer(owner) ~= nil
        and #trace.timeoutEvents == 0
    now = 1020
    host:update(0, context)
    check("multiplayer_workshop_boundary_refreshed_lease_expires_at_next_exact_deadline",
        survivedBeforeNextDeadline and authority:leaseForPlayer(owner) == nil
        and #trace.timeoutEvents == 1
        and trace.timeoutEvents[1].reason == "timeout"
        and trace.timeoutEvents[1].ownerPlayerId == ownerId
        and trace.releases[1] == "timeout")

    local malformedAuthority, malformedTrace, malformedLease = activateAuthority(owner, 1100)
    now = 1110
    local ownerSequenceBeforeInvalid = host.players[ownerId].lastInputSequence
    local ownerMalformedQueued = network:injectToHost(
        ownerIndex, "owner-malformed-packet", Protocol.CHANNEL_STATE, 1)
    host:update(0, context)
    local malformedCannotRenew = malformedLease.accepted and ownerMalformedQueued
        and malformedAuthority:leaseForPlayer(owner) == nil
        and malformedTrace.touches[ownerId] == nil
        and #malformedTrace.timeoutEvents == 1
        and malformedTrace.timeoutEvents[1].reason == "timeout"
        and host.players[ownerId].lastInputSequence == ownerSequenceBeforeInvalid
    clients[ownerIndex]:update(0, clientContexts[ownerIndex])
    clients[ownerIndex]:drainEvents()
    check("multiplayer_workshop_boundary_malformed_owner_packet_cannot_renew_lease",
        malformedCannotRenew)

    local wrongSessionAuthority, wrongSessionTrace, wrongSessionLease =
        activateAuthority(owner, 1200)
    now = 1210
    local wrongSessionInput = Protocol.encode("input", {
        sessionId = "wrong-workshop-session",
        sequence = clients[ownerIndex].inputSequence + 1,
        moveX = 0,
        moveY = 0,
    })
    local wrongSessionQueued = network:injectToHost(
        ownerIndex, wrongSessionInput, Protocol.CHANNEL_STATE, 1)
    host:update(0, context)
    local wrongSessionCannotRenew = wrongSessionLease.accepted and wrongSessionInput
        and wrongSessionQueued and wrongSessionAuthority:leaseForPlayer(owner) == nil
        and wrongSessionTrace.touches[ownerId] == nil
        and #wrongSessionTrace.timeoutEvents == 1
        and wrongSessionTrace.timeoutEvents[1].reason == "timeout"
        and host.players[ownerId].lastInputSequence == ownerSequenceBeforeInvalid
    check("multiplayer_workshop_boundary_wrong_session_input_cannot_renew_lease",
        wrongSessionCannotRenew)

    local wrongChannelAuthority, wrongChannelTrace, wrongChannelLease =
        activateAuthority(owner, 1300)
    now = 1310
    local wrongChannelInput = Protocol.encode("input", {
        sessionId = host.sessionId,
        sequence = clients[ownerIndex].inputSequence + 1,
        moveX = 0,
        moveY = 0,
    })
    local wrongChannelQueued = network:injectToHost(
        ownerIndex, wrongChannelInput, Protocol.CHANNEL_CONTROL, 1)
    host:update(0, context)
    local wrongChannelCannotRenew = wrongChannelLease.accepted and wrongChannelInput
        and wrongChannelQueued and wrongChannelAuthority:leaseForPlayer(owner) == nil
        and wrongChannelTrace.touches[ownerId] == nil
        and #wrongChannelTrace.timeoutEvents == 1
        and wrongChannelTrace.timeoutEvents[1].reason == "timeout"
        and host.players[ownerId].lastInputSequence == ownerSequenceBeforeInvalid
    clients[ownerIndex]:update(0, clientContexts[ownerIndex])
    clients[ownerIndex]:drainEvents()
    check("multiplayer_workshop_boundary_wrong_channel_input_cannot_renew_lease",
        wrongChannelCannotRenew)

    local oldOwnerPeer = network:peer(ownerIndex)
    local oldOwnerClient = clients[ownerIndex]
    local delayedOldInputQueued = network:delayNext("client_to_host", ownerIndex, 3)
    local delayedOldInputSent = oldOwnerClient:sendNeutralInput()
    local disconnected = network:disconnectPeer(ownerIndex, 61)
    host:update(0, context)
    oldOwnerClient:update(0, clientContexts[ownerIndex])
    local oldOwnerStopped = oldOwnerClient:stop("Workshop boundary replacement")
    for index = 1, 3 do
        if index ~= ownerIndex then
            clients[index]:update(0, clientContexts[index])
            clients[index]:drainEvents()
        end
    end

    local replacement = Session.new({
        transportFactory = network.factory,
        clock = clock,
    })
    local replacementContext = clientContext(ownerIndex)
    local replacementStarted = replacement:startClient("192.168.1.80:22122", {
        name = "Boundary Replacement",
        character = "rabbit-worker",
    })
    replacement.clientNonce = "workshop-boundary-replacement"
    replacement:update(0, replacementContext)
    host:update(0, context)
    replacement:update(0, replacementContext)
    clients[ownerIndex], clientContexts[ownerIndex] = replacement, replacementContext
    local replacementPeer = network:peer(ownerIndex)
    local replacementOwner = host.players[ownerId]
    local staleAuthority, staleTrace, staleLease = activateAuthority(replacementOwner, 1400)
    now = 1410
    local staleReplyStart = packetCount(network, "host_to_client", ownerIndex, "error")
    network:advanceSteps(3)
    host:update(0, context)
    local staleCannotRenew = delayedOldInputQueued and delayedOldInputSent
        and disconnected and oldOwnerStopped and not oldOwnerClient:isActive()
        and replacementStarted and replacement.ready and replacementPeer ~= oldOwnerPeer
        and staleLease.accepted and staleAuthority:leaseForPlayer(replacementOwner) == nil
        and staleTrace.touches[ownerId] == nil and #staleTrace.timeoutEvents == 1
        and staleTrace.timeoutEvents[1].reason == "timeout"
        and host.players[ownerId].lastInputSequence == -1
        and packetCount(network, "host_to_client", ownerIndex, "error") == staleReplyStart
        and host.peerToId[replacementPeer] == ownerId and not host.terminal
    check("multiplayer_workshop_boundary_stale_generation_input_cannot_renew_replacement_lease",
        staleCannotRenew)
    check("multiplayer_workshop_boundary_invalid_and_stale_traffic_cannot_renew_lease",
        malformedCannotRenew and wrongSessionCannotRenew
        and wrongChannelCannotRenew and staleCannotRenew)

    host:stop("Workshop boundary test complete")
    for index = 1, 3 do clients[index]:stop("Workshop boundary test complete") end
    local disposed = network:dispose()
    check("multiplayer_workshop_boundary_teardown_releases_all_test_state",
        disposed and network:isQuiescent() and not host:isActive()
        and not clients[1]:isActive() and not clients[2]:isActive()
        and not clients[3]:isActive() and not oldOwnerClient:isActive()
        and activeAuthority:leaseForResource(RESOURCE_ID) == nil
        and #authorityTrace.timeoutEvents == 1)
end

return Test
