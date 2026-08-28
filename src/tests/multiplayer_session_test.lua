local Codec = require("src.net.codec")
local Protocol = require("src.net.protocol")
local Session = require("src.net.session")

local Test = {}

local function queuedTransport(network, mode)
    local transport = {
        mode = mode,
        inbound = {},
        closed = false,
    }

    local function record(direction, payload, channel, reliable)
        local envelope = Protocol.decode(payload)
        network.log[#network.log + 1] = {
            direction = direction,
            kind = envelope and envelope.type or "invalid",
            payload = payload,
            channel = channel,
            reliable = reliable == true,
        }
    end

    function transport:service(maxEvents)
        if self.serviceError then return nil, self.serviceError end
        local events = {}
        for _ = 1, math.min(tonumber(maxEvents) or 0, #self.inbound) do
            events[#events + 1] = table.remove(self.inbound, 1)
        end
        return events
    end

    function transport:send(peer, payload, channel, reliable)
        if self.closed or mode ~= "host" or peer ~= network.peer then
            return false, "fake peer is unavailable"
        end
        record("host_to_client", payload, channel, reliable)
        if network.client and not network.client.closed then
            network.client.inbound[#network.client.inbound + 1] = {
                type = "receive", peer = network.peer, data = payload, channel = channel,
            }
        end
        return true
    end

    function transport:sendToServer(payload, channel, reliable)
        if self.closed or mode ~= "client" or not network.host or network.host.closed then
            return false, "fake host is unavailable"
        end
        record("client_to_host", payload, channel, reliable)
        network.host.inbound[#network.host.inbound + 1] = {
            type = "receive", peer = network.peer, data = payload, channel = channel,
        }
        return true
    end

    function transport:broadcast(payload, channel, reliable)
        if self.closed or mode ~= "host" then return false, "fake host is unavailable" end
        record("host_broadcast", payload, channel, reliable)
        if network.client and not network.client.closed then
            network.client.inbound[#network.client.inbound + 1] = {
                type = "receive", peer = network.peer, data = payload, channel = channel,
            }
        end
        return true
    end

    function transport:disconnect(peer, code, immediate)
        if self.closed or mode ~= "host" or peer ~= network.peer then
            return false, "fake peer is unavailable"
        end
        network.disconnects[#network.disconnects + 1] = {
            code = code, immediate = immediate == true,
        }
        if network.client and not network.client.closed then
            network.client.inbound[#network.client.inbound + 1] = {
                type = "disconnect", peer = network.peer, code = code,
            }
        end
        return true
    end

    function transport:flush()
        network.flushes = network.flushes + 1
        return true
    end

    function transport:close(code, immediate)
        if self.closed then return true end
        self.closed = true
        network.closes[#network.closes + 1] = {
            mode = mode, code = code, immediate = immediate == true,
        }
        if mode == "client" and network.host and not network.host.closed then
            network.host.inbound[#network.host.inbound + 1] = {
                type = "disconnect", peer = network.peer, code = code,
            }
        elseif mode == "host" and network.client and not network.client.closed then
            network.client.inbound[#network.client.inbound + 1] = {
                type = "disconnect", peer = network.peer, code = code,
            }
        end
        return true
    end

    return transport
end

local function fakeNetwork()
    local network = {
        log = {},
        disconnects = {},
        closes = {},
        flushes = 0,
        peer = { id = "guest-peer" },
        factory = {},
    }

    function network.factory.createHost(options)
        network.hostOptions = options
        network.host = queuedTransport(network, "host")
        return network.host
    end

    function network.factory.createClient(endpoint, options)
        if not network.host then return nil, "fake host has not started" end
        network.clientEndpoint = endpoint
        network.clientOptions = options
        network.client = queuedTransport(network, "client")
        network.host.inbound[#network.host.inbound + 1] = {
            type = "connect", peer = network.peer,
        }
        network.client.inbound[#network.client.inbound + 1] = {
            type = "connect", peer = network.peer,
        }
        return network.client
    end

    function network:sendRawToHost(payload, channel, reliable)
        return self.client:sendToServer(payload, channel or Protocol.CHANNEL_STATE, reliable == true)
    end

    function network:messages(direction, kind)
        local matches = {}
        for _, item in ipairs(self.log) do
            if (not direction or item.direction == direction) and (not kind or item.kind == kind) then
                matches[#matches + 1] = item
            end
        end
        return matches
    end

    return network
end

local function motionPlayer(x, y)
    return {
        x = x,
        y = y,
        velocityX = 0,
        velocityY = 0,
        intentX = 1,
        intentY = 0,
        moving = false,
        facing = 1,
        animationDistance = 0,
        character = "rabbit-worker",
    }
end

local function visitorState(state, visible, x, y, character)
    return {
        state = state,
        visible = visible,
        x = x,
        y = y,
        waypoint = visible and 2 or 1,
        seatIndex = visible and 1 or 0,
        character = character or "business-cat",
        facing = 1,
        intentX = 0,
        intentY = 1,
        motionX = 0,
        motionY = 0,
        currentSpeed = 0,
        animationDistance = 0,
        animationClock = 0,
        idleClock = 0,
        waitTimer = 0,
        arrivalTimer = visible and 0 or 8,
        inMotion = state == "entering" or state == "exiting",
    }
end

local function eventNamed(events, name)
    for _, event in ipairs(events or {}) do
        if event.type == name then return event end
    end
end

local function decodedPayload(message)
    local envelope = message and Protocol.decode(message.payload)
    return envelope and envelope.payload
end

function Test.run(_, check)
    local now = 100
    local clock = function() return now end
    local network = fakeNetwork()
    local host = Session.new({ transportFactory = network.factory, clock = clock })
    local client = Session.new({ transportFactory = network.factory, clock = clock })
    local hostPlayer = motionPlayer(400, 500)
    local guestPlayer = motionPlayer(428, 500)
    local moveCalls = {}
    local interactionCalls = {}
    local interactionMutations = 0
    local interactionX, interactionY, interactionRadius = 300, 285, 72
    local hostContext = {
        localPlayer = hostPlayer,
        resolveGuestSpawn = function()
            return 450, 510
        end,
        getShopSnapshot = function()
            return {
                state = {
                    money = 2345,
                    screen = "world",
                    inventory = { paper = 2500, prints = 12 },
                    jobs = { active = {}, completed = {} },
                },
                player = { x = 400, y = 500, character = "rabbit-worker" },
            }
        end,
        moveRemote = function(player, dt, inputX, inputY)
            moveCalls[#moveCalls + 1] = {
                id = player.id, dt = dt, inputX = inputX, inputY = inputY,
            }
            player.x = player.x + inputX * 100 * dt
            player.y = player.y + inputY * 100 * dt
            player.velocityX = inputX * 100
            player.velocityY = inputY * 100
            player.intentX, player.intentY = inputX, inputY
            player.moving = inputX ~= 0 or inputY ~= 0
            player.animationDistance = player.animationDistance
                + math.sqrt((inputX * 100 * dt) ^ 2 + (inputY * 100 * dt) ^ 2)
        end,
        performInteraction = function(player, targetKind, desiredState)
            interactionCalls[#interactionCalls + 1] = {
                player = player, x = player.x, y = player.y, targetKind = targetKind,
                desiredState = desiredState,
            }
            local dx, dy = player.x - interactionX, player.y - interactionY
            if dx * dx + dy * dy > interactionRadius * interactionRadius then
                return false, "out_of_range", "Move closer to the loading-bay wall switch."
            end
            interactionMutations = interactionMutations + 1
            return true, "accepted", "Opening the loading bay door..."
        end,
    }
    local clientContext = {
        localPlayer = guestPlayer,
        inputX = 0.75,
        inputY = -0.25,
    }
    local addressOptions = { socket = { dns = {
        gethostname = function() return "picture-shop-host" end,
        getaddrinfo = function() return { { addr = "192.168.1.50" } } end,
    } } }

    local hostStarted = host:startHost({
        name = "PC Host",
        character = "rabbit-worker",
        x = hostPlayer.x,
        y = hostPlayer.y,
        addressOptions = addressOptions,
    })
    host.sessionId = "session-test"
    local clientStarted = client:startClient("192.168.1.50:22122", {
        name = "Phone Guest",
        character = "rabbit-worker",
    })
    client.clientNonce = "nonce-test"
    check("multiplayer_session_fake_pair_starts_without_real_socket",
        hostStarted and clientStarted and host:isHost() and client:isClient()
        and network.hostOptions.maxGuests == 3 and network.hostOptions.channels == 3
        and network.clientOptions.channels == 3
        and network.clientEndpoint == "192.168.1.50:22122")

    client:update(0, clientContext)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local hostEvents = host:drainEvents()
    local clientEvents = client:drainEvents()
    local joined = eventNamed(hostEvents, "player_joined")
    local ready = eventNamed(clientEvents, "ready")
    local hello = network:messages("client_to_host", "hello")[1]
    local welcome = network:messages("host_to_client", "welcome")[1]
    local shopSnapshot = network:messages("host_to_client", "shop_snapshot")[1]
    check("multiplayer_session_hello_welcome_and_shop_snapshot_make_guest_ready",
        hello and hello.channel == Protocol.CHANNEL_CONTROL and hello.reliable
        and welcome and welcome.channel == Protocol.CHANNEL_CONTROL and welcome.reliable
        and shopSnapshot and shopSnapshot.channel == Protocol.CHANNEL_DURABLE and shopSnapshot.reliable
        and joined and joined.playerId == 2 and joined.name == "Phone Guest"
        and ready and ready.playerId == 2 and ready.state.money == 2345
        and ready.revision == 0 and client.lastShopRevision == 0
        and ready.hostPlayer.x == 400 and ready.spawn.x == 450 and ready.spawn.y == 510
        and client.ready and client.sessionId == "session-test")

    check("multiplayer_session_assigns_numeric_guest_id_and_shared_roster",
        host.localId == 1 and client.localId == 2
        and type(host.localId) == "number" and type(client.localId) == "number"
        and host.players[1].name == "PC Host" and host.players[2].name == "Phone Guest"
        and client.players[1].name == "PC Host" and client.players[2].name == "Phone Guest"
        and host.peerToId[network.peer] == 2 and host.idToPeer[2] == network.peer)

    moveCalls = {}
    client:update(0.05, clientContext)
    host:update(0.05, hostContext)
    local authoritativeGuest = host.players[2]
    local input = network:messages("client_to_host", "input")[1]
    check("multiplayer_session_host_accepts_guest_input_authoritatively",
        input and input.channel == Protocol.CHANNEL_STATE and not input.reliable
        and authoritativeGuest and authoritativeGuest.inputSequence == 1
        and authoritativeGuest.inputX == 0.75 and authoritativeGuest.inputY == -0.25
        and #moveCalls == 1 and moveCalls[1].id == 2
        and math.abs(authoritativeGuest.x - 453.75) < 0.0001
        and math.abs(authoritativeGuest.y - 508.75) < 0.0001,
        string.format("input=%s channel=%s reliable=%s seq=%s axes=%s,%s calls=%d pos=%s,%s",
            tostring(input and input.kind), tostring(input and input.channel),
            tostring(input and input.reliable),
            tostring(authoritativeGuest and authoritativeGuest.inputSequence),
            tostring(authoritativeGuest and authoritativeGuest.inputX),
            tostring(authoritativeGuest and authoritativeGuest.inputY),
            #moveCalls, tostring(authoritativeGuest and authoritativeGuest.x),
            tostring(authoritativeGuest and authoritativeGuest.y)))

    host:update(0.04, hostContext)
    client:update(0, clientContext)
    local authoritativeX, authoritativeY = host.players[2].x, host.players[2].y
    local snapshots = network:messages("host_broadcast", "snapshot")
    check("multiplayer_session_host_snapshot_returns_guest_motion_to_client",
        #snapshots == 1 and snapshots[1].channel == Protocol.CHANNEL_STATE
        and not snapshots[1].reliable and host.serverTick == 1 and client.lastServerTick == 1
        and client.localTarget and client.localTarget.id == 2
        and math.abs(client.localTarget.x - authoritativeX) < 0.0001
        and math.abs(client.localTarget.y - authoritativeY) < 0.0001)

    local staleInput = Protocol.encode("input", {
        sessionId = host.sessionId,
        sequence = 1,
        moveX = -1,
        moveY = 1,
    })
    network:sendRawToHost(staleInput)
    host:update(0, hostContext)
    local wrongSessionInput = Protocol.encode("input", {
        sessionId = "spoofed-session",
        sequence = 99,
        moveX = -1,
        moveY = 1,
    })
    network:sendRawToHost(wrongSessionInput)
    host:update(0, hostContext)
    check("multiplayer_session_stale_and_spoofed_inputs_are_ignored",
        host.players[2].inputSequence == 1
        and host.players[2].inputX == 0.75 and host.players[2].inputY == -0.25)

    -- A guest USE request carries no coordinates. The callback must receive
    -- the peer-derived authoritative host player even when client prediction
    -- places the phone somewhere completely different.
    host.players[2].x, host.players[2].y = interactionX, interactionY
    guestPlayer.x, guestPlayer.y = 900, 620
    local requestedInteraction = client:requestInteraction("loadingBayDoor", "open")
    local firstInteractionRequest = network:messages("client_to_host", "interaction_request")[1]
    local firstWireRequest = decodedPayload(firstInteractionRequest)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local firstInteractionEvents = client:drainEvents()
    local firstInteractionResult = eventNamed(firstInteractionEvents, "interaction_result")
    local interactionResults = network:messages("host_to_client", "interaction_result")
    local firstWireResult = decodedPayload(interactionResults[1])
    check("multiplayer_session_guest_use_executes_at_authoritative_peer_position",
        requestedInteraction and firstInteractionRequest
        and firstInteractionRequest.channel == Protocol.CHANNEL_CONTROL
        and firstInteractionRequest.reliable
        and firstWireRequest and firstWireRequest.desiredState == "open"
        and #interactionCalls == 1
        and interactionCalls[1].player == host.players[2]
        and interactionCalls[1].x == interactionX and interactionCalls[1].y == interactionY
        and interactionCalls[1].x ~= guestPlayer.x and interactionCalls[1].y ~= guestPlayer.y
        and interactionCalls[1].targetKind == "loadingBayDoor"
        and interactionCalls[1].desiredState == "open"
        and interactionMutations == 1
        and firstInteractionResult and firstInteractionResult.accepted
        and firstInteractionResult.code == "accepted"
        and firstWireResult and firstWireResult.requestId == 1
        and interactionResults[1].channel == Protocol.CHANNEL_CONTROL
        and interactionResults[1].reliable
        and #network:messages("host_broadcast", "interaction_result") == 0)

    -- Reliable transport should already suppress duplicates, but the command
    -- itself is also idempotent: replay the exact packet and require the host
    -- to replay its cached result without invoking the world callback again.
    network:sendRawToHost(firstInteractionRequest.payload,
        Protocol.CHANNEL_CONTROL, true)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local duplicateEvents = client:drainEvents()
    interactionResults = network:messages("host_to_client", "interaction_result")
    local duplicateWireResult = decodedPayload(interactionResults[#interactionResults])
    check("multiplayer_session_duplicate_use_replays_result_without_reexecution",
        #interactionCalls == 1 and interactionMutations == 1
        and #interactionResults == 2
        and duplicateWireResult and firstWireResult
        and duplicateWireResult.requestId == firstWireResult.requestId
        and duplicateWireResult.accepted == firstWireResult.accepted
        and duplicateWireResult.code == firstWireResult.code
        and eventNamed(duplicateEvents, "interaction_result") == nil)

    -- A new request inside the host cooldown consumes its id and returns a
    -- stable rejection without entering the world callback.
    local rateRequest = client:requestInteraction("loadingBayDoor", "open")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local rateResult = eventNamed(client:drainEvents(), "interaction_result")
    check("multiplayer_session_unique_use_spam_is_rate_limited",
        rateRequest and rateResult and not rateResult.accepted
        and rateResult.requestId == 2 and rateResult.code == "rate_limited"
        and #interactionCalls == 1 and interactionMutations == 1
        and host.players[2].lastInteractionRequestId == 2)

    -- The phone now predicts itself at the switch while the host's player is
    -- far away. Only the latter is passed to performInteraction.
    now = now + 0.21
    host.players[2].x, host.players[2].y = 700, 600
    guestPlayer.x, guestPlayer.y = interactionX, interactionY
    local outOfRangeRequest = client:requestInteraction("loadingBayDoor", "open")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local outOfRangeResult = eventNamed(client:drainEvents(), "interaction_result")
    check("multiplayer_session_out_of_range_use_uses_host_position",
        outOfRangeRequest and outOfRangeResult and not outOfRangeResult.accepted
        and outOfRangeResult.requestId == 3 and outOfRangeResult.code == "out_of_range"
        and #interactionCalls == 2
        and interactionCalls[2].player == host.players[2]
        and interactionCalls[2].x == 700 and interactionCalls[2].y == 600
        and interactionCalls[2].x ~= guestPlayer.x and interactionCalls[2].y ~= guestPlayer.y
        and interactionMutations == 1)

    local staleInteractionPacket = Protocol.encode("interaction_request", {
        sessionId = host.sessionId, requestId = 2, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    network:sendRawToHost(staleInteractionPacket, Protocol.CHANNEL_CONTROL, true)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local staleInteractionEvents = client:drainEvents()
    interactionResults = network:messages("host_to_client", "interaction_result")
    local staleWireResult = decodedPayload(interactionResults[#interactionResults])
    check("multiplayer_session_stale_use_is_rejected_without_reexecution",
        staleWireResult and staleWireResult.requestId == 2
        and not staleWireResult.accepted and staleWireResult.code == "stale_request"
        and host.players[2].lastInteractionRequestId == 3
        and #interactionCalls == 2 and interactionMutations == 1
        and eventNamed(staleInteractionEvents, "interaction_result") == nil)

    local resultCountBeforeWrongSession = #interactionResults
    local wrongSessionInteraction = Protocol.encode("interaction_request", {
        sessionId = "spoofed-session", requestId = 4, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    network:sendRawToHost(wrongSessionInteraction, Protocol.CHANNEL_CONTROL, true)
    host:update(0, hostContext)
    check("multiplayer_session_wrong_session_use_is_ignored_without_consuming_id",
        #network:messages("host_to_client", "interaction_result")
            == resultCountBeforeWrongSession
        and host.players[2].lastInteractionRequestId == 3
        and #interactionCalls == 2 and interactionMutations == 1)

    now = now + 0.21
    host.players[2].x, host.players[2].y = interactionX, interactionY
    guestPlayer.x, guestPlayer.y = 900, 620
    local validAfterSpoof = client:requestInteraction("loadingBayDoor", "open")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local validAfterSpoofResult = eventNamed(client:drainEvents(), "interaction_result")
    check("multiplayer_session_valid_use_after_spoof_keeps_monotonic_sequence",
        validAfterSpoof and validAfterSpoofResult and validAfterSpoofResult.accepted
        and validAfterSpoofResult.requestId == 4
        and host.players[2].lastInteractionRequestId == 4
        and #interactionCalls == 3 and interactionMutations == 2)

    local duplicateAcceptedResult = Protocol.encode("interaction_result", {
        sessionId = host.sessionId, requestId = 4, targetKind = "loadingBayDoor",
        accepted = true, code = "accepted", message = "Opening the loading bay door...",
    })
    local wrongSessionResult = Protocol.encode("interaction_result", {
        sessionId = "spoofed-session", requestId = 5, targetKind = "loadingBayDoor",
        accepted = true, code = "accepted", message = "Opening the loading bay door...",
    })
    now = now + 0.21
    local pendingFifthRequest = client:requestInteraction("loadingBayDoor", "open")
    network.host:send(network.peer, duplicateAcceptedResult,
        Protocol.CHANNEL_CONTROL, true)
    network.host:send(network.peer, wrongSessionResult,
        Protocol.CHANNEL_CONTROL, true)
    client:update(0, clientContext)
    local ignoredResultEvents = client:drainEvents()
    check("multiplayer_session_guest_ignores_stale_and_wrong_session_results",
        pendingFifthRequest
        and eventNamed(ignoredResultEvents, "interaction_result") == nil
        and client.pendingInteraction and client.pendingInteraction.requestId == 5)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local fifthResult = eventNamed(client:drainEvents(), "interaction_result")
    check("multiplayer_session_matching_result_clears_only_its_pending_request",
        fifthResult and fifthResult.requestId == 5 and fifthResult.accepted
        and client.pendingInteraction == nil
        and host.players[2].lastInteractionRequestId == 5
        and #interactionCalls == 4 and interactionMutations == 3)

    local malformedInteraction = Codec.encode({
        version = Protocol.VERSION,
        type = "interaction_request",
        payload = {
            sessionId = host.sessionId, requestId = 5, targetKind = "loadingBayDoor",
            desiredState = "open", playerId = 2, x = interactionX, y = interactionY,
        },
    })
    local errorsBeforeSpoof = #network:messages("host_to_client", "error")
    network:sendRawToHost(malformedInteraction, Protocol.CHANNEL_CONTROL, true)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local malformedInteractionError = eventNamed(client:drainEvents(), "error")
    check("multiplayer_session_position_and_identity_spoof_returns_bad_packet",
        malformedInteractionError and malformedInteractionError.code == "bad_packet"
        and #network:messages("host_to_client", "error") == errorsBeforeSpoof + 1
        and host.players[2].lastInteractionRequestId == 5
        and #interactionCalls == 4 and interactionMutations == 3)

    local errorCountBeforeInvalid = #network:messages("host_to_client", "error")
    network:sendRawToHost("this-is-not-a-protocol-packet")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local invalidEvents = client:drainEvents()
    local invalidError = eventNamed(invalidEvents, "error")
    local errorPackets = network:messages("host_to_client", "error")
    check("multiplayer_session_invalid_packet_returns_bad_packet_error",
        invalidError and invalidError.code == "bad_packet"
        and #errorPackets == errorCountBeforeInvalid + 1
        and #errorPackets[#errorPackets].payload <= Protocol.MAX_PACKET_BYTES
        and errorPackets[#errorPackets].channel == Protocol.CHANNEL_CONTROL
        and errorPackets[#errorPackets].reliable)

    local wrongChannelCount = #errorPackets
    local wrongChannelInteraction = Protocol.encode("interaction_request", {
        sessionId = host.sessionId, requestId = 6, targetKind = "loadingBayDoor",
        desiredState = "open",
    })
    network:sendRawToHost(wrongChannelInteraction, Protocol.CHANNEL_STATE, true)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local wrongChannelError = eventNamed(client:drainEvents(), "error")
    check("multiplayer_session_guest_command_on_wrong_channel_is_rejected_before_execution",
        wrongChannelError and wrongChannelError.code == "bad_packet"
        and #network:messages("host_to_client", "error") == wrongChannelCount + 1
        and host.players[2].lastInteractionRequestId == 5
        and #interactionCalls == 4 and interactionMutations == 3)

    local oversizedCount = #network:messages("host_to_client", "error")
    network:sendRawToHost(string.rep("x", Protocol.MAX_PACKET_BYTES + 1),
        Protocol.CHANNEL_DURABLE, true)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local oversizedGuestError = eventNamed(client:drainEvents(), "error")
    check("multiplayer_session_guest_packets_are_capped_before_large_codec_decode",
        oversizedGuestError and oversizedGuestError.code == "bad_packet"
        and #network:messages("host_to_client", "error") == oversizedCount + 1
        and host.players[2].lastInteractionRequestId == 5
        and #interactionCalls == 4 and interactionMutations == 3)

    local workshopRevision, workshopLease, workshopResource, workshopMutation = 0, nil, nil, 0
    local workshopPallets = {}
    local workshopCalls, workshopTouches = {}, 0
    hostContext.touchWorkshop = function(player)
        if player and player.id == 2 then workshopTouches = workshopTouches + 1 end
    end
    hostContext.performWorkshop = function(player, operation, payload)
        workshopCalls[#workshopCalls + 1] = {
            player = player, operation = operation, payload = payload,
        }
        if operation == "workshop_acquire" then
            workshopRevision = workshopRevision + 1
            workshopResource = payload.resourceId
            workshopLease = workshopResource == "skid_wrapper"
                and "lease-wrapper-test" or "lease-office-test"
            local data = {}
            if workshopResource == "skid_wrapper" then
                data = {
                    step = "idle", progress = 0, cycleTime = 3,
                    plasticWrapRolls = 2, plasticWrapUses = 8,
                    pallets = workshopPallets,
                }
            end
            return {
                accepted = true, code = "acquired", message = "Workshop console connected.",
                revision = workshopRevision, leaseId = workshopLease, data = data,
            }
        elseif operation == "workshop_command" then
            if payload.leaseId ~= workshopLease then
                return { accepted = false, code = "lease_not_found", message = "Lease missing.",
                    revision = workshopRevision }
            end
            workshopRevision, workshopMutation = workshopRevision + 1, workshopMutation + 1
            return {
                accepted = true, code = "pickup_requested", message = "Pickup requested.",
                revision = workshopRevision, data = {},
            }
        elseif operation == "workshop_release" then
            workshopRevision, workshopLease, workshopResource = workshopRevision + 1, nil, nil
            return { accepted = true, code = "released", message = "Released.",
                revision = workshopRevision }
        end
    end
    hostContext.getWorkshopSnapshot = function()
        return {
            resources = {
                { resourceId = "reception_customer", revision = 0, occupied = false },
                { resourceId = "office_computer", revision = workshopRevision,
                    occupied = workshopLease ~= nil and workshopResource == "office_computer",
                    ownerPlayerId = workshopLease and workshopResource == "office_computer"
                        and 2 or nil },
                { resourceId = "skid_wrapper", revision = workshopRevision,
                    occupied = workshopLease ~= nil and workshopResource == "skid_wrapper",
                    ownerPlayerId = workshopLease and workshopResource == "skid_wrapper"
                        and 2 or nil },
            },
            wrapper = {
                step = "idle", progress = 0, cycleTime = 3,
                pallets = workshopPallets,
            },
        }
    end

    local workshopRequested = client:requestWorkshopAcquire("office_computer")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local workshopGrant = eventNamed(client:drainEvents(), "workshop_grant")
    local acquireWire = decodedPayload(
        network:messages("client_to_host", "workshop_acquire")[1])
    local grantMessage = network:messages("host_to_client", "workshop_grant")[1]
    check("multiplayer_session_worker_acquires_host_owned_office_without_spoofable_identity",
        workshopRequested and workshopGrant and workshopGrant.granted
        and workshopGrant.leaseId == workshopLease
        and acquireWire and acquireWire.resourceId == "office_computer"
        and acquireWire.expectedRevision == 0
        and acquireWire.playerId == nil and acquireWire.x == nil and acquireWire.y == nil
        and workshopCalls[1] and workshopCalls[1].player == host.players[2]
        and grantMessage and grantMessage.channel == Protocol.CHANNEL_CONTROL
        and grantMessage.reliable and client:workshopInfo().revision == 1)

    local workshopCommanded = client:requestWorkshopCommand(
        "request_pickup", { jobId = "JOB-0001" })
    host:update(0, hostContext)
    client:update(0, clientContext)
    local workshopResult = eventNamed(client:drainEvents(), "workshop_result")
    local commandMessage = network:messages("client_to_host", "workshop_command")[1]
    local commandWire = decodedPayload(commandMessage)
    check("multiplayer_session_worker_command_is_semantic_reliable_and_updates_revision_once",
        workshopCommanded and workshopResult and workshopResult.accepted
        and workshopResult.action == "request_pickup" and workshopMutation == 1
        and commandWire and commandWire.jobId == "JOB-0001"
        and commandWire.expectedRevision == 1 and commandWire.state == nil
        and commandMessage.channel == Protocol.CHANNEL_CONTROL and commandMessage.reliable
        and client:workshopInfo().revision == 2 and workshopTouches > 0)

    local workshopReleased = client:releaseWorkshop("closed")
    host:update(0, hostContext)
    check("multiplayer_session_worker_release_clears_client_and_host_resource_ownership",
        workshopReleased and client:workshopInfo() == nil and workshopLease == nil
        and workshopRevision == 3 and workshopCalls[#workshopCalls].operation == "workshop_release")

    workshopPallets = {}
    local wrapperRequested = client:requestWorkshopAcquire("skid_wrapper")
    host:update(0, hostContext)
    client:update(0, clientContext)
    local wrapperGrant = eventNamed(client:drainEvents(), "workshop_grant")
    host:update(0.09, hostContext)
    client:update(0, clientContext)
    local emptyWrapperSnapshot = eventNamed(client:drainEvents(), "workshop_snapshot")

    workshopPallets = {
        { palletId = "JOB-LIVE-P01", jobLabel = "Live Client · JOB-LIVE",
            packaging = "boxed", distance = 28 },
    }
    host:update(0.09, hostContext)
    client:update(0, clientContext)
    local liveWrapperSnapshot = eventNamed(client:drainEvents(), "workshop_snapshot")
    local workshopPackets = network:messages("host_to_client", "workshop_snapshot")
    local liveWorkshopWire = decodedPayload(workshopPackets[#workshopPackets])
    check("multiplayer_session_open_wrapper_receives_empty_to_eligible_live_pallet_update",
        wrapperRequested and wrapperGrant and wrapperGrant.granted
        and wrapperGrant.resourceId == "skid_wrapper"
        and wrapperGrant.view and #wrapperGrant.view.pallets == 0
        and emptyWrapperSnapshot and #emptyWrapperSnapshot.wrapper.pallets == 0
        and liveWrapperSnapshot and #liveWrapperSnapshot.wrapper.pallets == 1
        and liveWrapperSnapshot.wrapper.pallets[1].palletId == "JOB-LIVE-P01"
        and liveWrapperSnapshot.wrapper.pallets[1].packaging == "boxed"
        and liveWorkshopWire and #liveWorkshopWire.wrapper.pallets == 1
        and #workshopPackets[#workshopPackets].payload <= Protocol.MAX_PACKET_BYTES
        and client:workshopInfo() and client:workshopInfo().resourceId == "skid_wrapper")
    client:releaseWorkshop("closed")
    host:update(0, hostContext)

    client:stop("Guest signed off")
    host:update(0, hostContext)
    local leavePackets = network:messages("client_to_host", "leave")
    local hostLeaveBroadcasts = network:messages("host_broadcast", "leave")
    local finalHostEvents = host:drainEvents()
    local left = eventNamed(finalHostEvents, "player_left")
    local leftCount = 0
    for _, event in ipairs(finalHostEvents) do
        if event.type == "player_left" then leftCount = leftCount + 1 end
    end
    check("multiplayer_session_disconnect_leave_cleans_guest_once",
        #leavePackets == 1 and #hostLeaveBroadcasts == 1
        and left and left.playerId == 2 and left.name == "Phone Guest"
        and leftCount == 1 and host.players[2] == nil
        and host.peerToId[network.peer] == nil and host.idToPeer[2] == nil
        and host:hudInfo().playerCount == 1 and not client:isActive())

    host:stop("Test complete")

    local expiryNetwork = fakeNetwork()
    local expiryHost = Session.new({ transportFactory = expiryNetwork.factory, clock = clock })
    expiryHost:startHost({ name = "Expiry Host", character = "rabbit-worker",
        addressOptions = addressOptions })
    expiryHost.pendingPeers[expiryNetwork.peer] = now - 11
    expiryHost:update(0, { localPlayer = motionPlayer(400, 500) })
    check("multiplayer_session_silent_prehello_peer_expires",
        expiryHost.pendingPeers[expiryNetwork.peer] == nil
        and #expiryNetwork.disconnects == 1 and expiryNetwork.disconnects[1].code == 3
        and #expiryNetwork:messages("host_to_client", "error") == 1)
    expiryHost:stop("Expiry test complete")

    local timeoutNetwork = fakeNetwork()
    local timeoutHost = Session.new({ transportFactory = timeoutNetwork.factory, clock = clock })
    local timeoutClient = Session.new({ transportFactory = timeoutNetwork.factory, clock = clock })
    timeoutHost:startHost({ name = "Timeout Host", character = "rabbit-worker",
        addressOptions = addressOptions })
    timeoutClient:startClient("192.168.1.50:22122", {
        name = "Timeout Guest", character = "rabbit-worker",
    })
    timeoutClient.sessionId, timeoutClient.localId, timeoutClient.ready = "timeout-test", 2, true
    timeoutClient.players[2] = motionPlayer(428, 500)
    local timeoutRequested = timeoutClient:requestInteraction("loadingBayDoor", "open")
    now = now + 3.01
    timeoutClient:update(0, { localPlayer = timeoutClient.players[2], inputX = 0, inputY = 0 })
    local timeoutResult = eventNamed(timeoutClient:drainEvents(), "interaction_result")
    check("multiplayer_session_unanswered_use_times_out_and_becomes_retryable",
        timeoutRequested and timeoutResult and not timeoutResult.accepted
        and timeoutResult.code == "timeout" and timeoutResult.requestId == 1
        and timeoutResult.targetKind == "loadingBayDoor"
        and timeoutClient.pendingInteraction == nil
        and timeoutClient:requestInteraction("loadingBayDoor", "open"))
    timeoutClient:stop("Timeout test complete")
    timeoutHost:stop("Timeout test complete")

    local failureNetwork = fakeNetwork()
    local failureHost = Session.new({ transportFactory = failureNetwork.factory, clock = clock })
    failureHost:startHost({ name = "Failure Host", character = "rabbit-worker",
        addressOptions = addressOptions })
    failureNetwork.host.serviceError = "synthetic ENet service failure"
    failureHost:update(0, { localPlayer = motionPlayer(400, 500) })
    local failureEvents = failureHost:drainEvents()
    local failureDisconnect = eventNamed(failureEvents, "disconnected")
    check("multiplayer_session_transport_service_failure_is_terminal",
        failureDisconnect and failureDisconnect.message:find("synthetic ENet", 1, true)
        and failureHost.terminal and not failureHost.ready and failureHost.transport == nil)
    failureHost:stop("Failure test complete")

    local disconnectNetwork = fakeNetwork()
    local disconnectHost = Session.new({ transportFactory = disconnectNetwork.factory, clock = clock })
    local disconnectClient = Session.new({ transportFactory = disconnectNetwork.factory, clock = clock })
    disconnectHost:startHost({ name = "Disconnect Host", character = "rabbit-worker",
        addressOptions = addressOptions })
    disconnectClient:startClient("192.168.1.50:22122", {
        name = "Disconnect Guest", character = "rabbit-worker",
    })
    disconnectClient.sessionId, disconnectClient.localId, disconnectClient.ready = "disconnect-test", 2, true
    disconnectClient.players[2] = motionPlayer(428, 500)
    disconnectNetwork.client.inbound = {
        { type = "disconnect", peer = disconnectNetwork.peer, code = 1 },
    }
    disconnectClient:update(0.05, { localPlayer = motionPlayer(428, 500), inputX = 1, inputY = 0 })
    local disconnectEvents = disconnectClient:drainEvents()
    local disconnectCount, errorCount = 0, 0
    for _, event in ipairs(disconnectEvents) do
        if event.type == "disconnected" then disconnectCount = disconnectCount + 1 end
        if event.type == "error" then errorCount = errorCount + 1 end
    end
    check("multiplayer_session_disconnect_does_not_queue_followup_send_error",
        disconnectCount == 1 and errorCount == 0 and disconnectClient.terminal
        and disconnectClient.transport == nil)
    disconnectClient:stop("Disconnect test complete")
    disconnectHost:stop("Disconnect test complete")

    local syncNetwork = fakeNetwork()
    local syncHost = Session.new({ transportFactory = syncNetwork.factory, clock = clock })
    local syncClient = Session.new({ transportFactory = syncNetwork.factory, clock = clock })
    local syncHostPlayer = motionPlayer(500, 520)
    local syncGuestPlayer = motionPlayer(530, 520)
    local authoritativeState = {
        money = 180,
        inventory = { paper = 40, prints = 0, stock = { shipping_cartons = 20 } },
        calendar = { year = 2026, month = 1, day = 3, weekday = 6,
            elapsed = 20, totalDays = 2 },
        jobs = { active = {}, completed = {}, declined = {} },
        clientEmails = { nextEmailId = 1, nextPromotionId = 1,
            pending = {}, inbox = {}, archive = {}, sentPromotions = {} },
    }
    local authoritativeVisitors = {
        customer = visitorState("entering", true, 580, 350, "business-cat"),
        vendor = visitorState("scheduled", false, 500, 300, "green-blazer-cat"),
    }
    local authoritativeEnvironment = {
        bayDoor = { state = "closed", progress = 0 },
        truck = { state = "absent", backingProgress = 0, cargoProgress = 0 },
    }
    local syncHostContext = {
        localPlayer = syncHostPlayer,
        resolveGuestSpawn = function() return 530, 520 end,
        getShopSnapshot = function()
            return {
                state = authoritativeState,
                player = { x = syncHostPlayer.x, y = syncHostPlayer.y,
                    character = syncHostPlayer.character },
            }
        end,
        getVisitorSnapshot = function() return authoritativeVisitors end,
        getEnvironmentSnapshot = function() return authoritativeEnvironment end,
        moveRemote = function() end,
    }
    local syncClientContext = {
        localPlayer = syncGuestPlayer,
        inputX = 0,
        inputY = 0,
    }
    syncHost:startHost({ name = "State Host", character = "rabbit-worker",
        x = syncHostPlayer.x, y = syncHostPlayer.y, addressOptions = addressOptions })
    syncHost.sessionId = "shop-state-test"
    syncClient:startClient("192.168.1.50:22122", {
        name = "State Guest", character = "rabbit-worker",
    })
    syncClient.clientNonce = "shop-state-nonce"
    syncClient:update(0, syncClientContext)
    syncHost:update(0, syncHostContext)
    syncClient:update(0, syncClientContext)
    syncHost:drainEvents()
    syncClient:drainEvents()

    -- Let the host establish its comparison baseline, then prove that an
    -- unchanged normalized shop never consumes durable bandwidth or revisions.
    syncHost:update(1, syncHostContext)
    syncClient:update(0, syncClientContext)
    syncClient:drainEvents()
    local baselineStatePackets = #syncNetwork:messages("host_to_client", "shop_state")
    syncHost:update(1, syncHostContext)
    syncClient:update(0, syncClientContext)
    local unchangedEvents = syncClient:drainEvents()
    check("multiplayer_session_unchanged_shop_state_is_not_rebroadcast",
        #syncNetwork:messages("host_to_client", "shop_state") == baselineStatePackets
        and eventNamed(unchangedEvents, "shop_state") == nil)

    authoritativeState.money = 925
    authoritativeState.inventory.paper = 2375
    authoritativeState.inventory.prints = 18
    authoritativeState.calendar.day = 5
    authoritativeState.calendar.weekday = 1
    authoritativeState.calendar.totalDays = 4
    authoritativeState.jobs.active = {
        { id = "LAN-JOB-0001", company = "Cross-platform Customer", status = "accepted" },
    }
    authoritativeState.clientEmails.inbox = {
        { id = "EMAIL-0001", sender = "Cross-platform Customer", subject = "Print quote" },
    }
    authoritativeVisitors.customer.state = "waiting"
    authoritativeVisitors.customer.x = 612
    authoritativeVisitors.customer.y = 318
    authoritativeVisitors.customer.waypoint = 3
    authoritativeVisitors.customer.waitTimer = 22
    authoritativeVisitors.vendor.arrivalTimer = 9
    authoritativeEnvironment.bayDoor.state = "opening"
    authoritativeEnvironment.bayDoor.progress = 0.5
    authoritativeEnvironment.truck = {
        state = "parked_closed", jobId = "LAN-JOB-0001", mode = "delivery",
        backingProgress = 1, cargoProgress = 0,
    }
    syncHost:markShopDirty()
    syncHost:update(1, syncHostContext)
    syncClient:update(0, syncClientContext)
    local changedEvents = syncClient:drainEvents()
    local changed = eventNamed(changedEvents, "shop_state")
    local visitorChanged = eventNamed(changedEvents, "visitor_state")
    local environmentChanged = eventNamed(changedEvents, "environment_state")
    local durablePackets = syncNetwork:messages("host_to_client", "shop_state")
    local visitorPackets = syncNetwork:messages("host_to_client", "visitor_snapshot")
    local environmentPackets = syncNetwork:messages("host_to_client", "environment_snapshot")
    check("multiplayer_session_host_broadcasts_authoritative_shop_state_to_guest",
        #durablePackets == baselineStatePackets + 1
        and durablePackets[#durablePackets].channel == Protocol.CHANNEL_DURABLE
        and durablePackets[#durablePackets].reliable
        and changed and changed.revision > 0
        and changed.state.money == 925
        and changed.state.inventory.paper == 2375
        and changed.state.inventory.prints == 18
        and changed.state.calendar.day == 5
        and changed.state.jobs.active[1].id == "LAN-JOB-0001"
        and changed.state.clientEmails.inbox[1].sender == "Cross-platform Customer"
        and syncClient.lastShopRevision == changed.revision)
    check("multiplayer_session_host_streams_customer_and_vendor_state_to_guest",
        #visitorPackets > 0
        and visitorPackets[#visitorPackets].channel == Protocol.CHANNEL_STATE
        and not visitorPackets[#visitorPackets].reliable
        and visitorChanged and visitorChanged.serverTick == syncHost.serverTick
        and visitorChanged.customer.state == "waiting"
        and visitorChanged.customer.x == 612 and visitorChanged.customer.y == 318
        and visitorChanged.customer.waitTimer == 22
        and visitorChanged.vendor.state == "scheduled"
        and visitorChanged.vendor.arrivalTimer == 9)
    check("multiplayer_session_host_streams_environment_state_to_guest",
        #environmentPackets > 0
        and environmentPackets[#environmentPackets].channel == Protocol.CHANNEL_STATE
        and not environmentPackets[#environmentPackets].reliable
        and environmentChanged and environmentChanged.serverTick == syncHost.serverTick
        and environmentChanged.bayDoor.state == "opening"
        and environmentChanged.bayDoor.progress == 0.5
        and environmentChanged.truck.state == "parked_closed"
        and environmentChanged.truck.jobId == "LAN-JOB-0001"
        and environmentChanged.truck.mode == "delivery"
        and environmentChanged.truck.backingProgress == 1
        and environmentChanged.truck.cargoProgress == 0
        and syncClient.lastEnvironmentTick == environmentChanged.serverTick)

    local deliveredRevision = changed and changed.revision or 1
    local stalePacket = Protocol.encode("shop_state", {
        sessionId = syncHost.sessionId,
        revision = deliveredRevision,
        state = { money = 1, inventory = { paper = 1 } },
    })
    local wrongSessionPacket = Protocol.encode("shop_state", {
        sessionId = "other-shop",
        revision = deliveredRevision + 1,
        state = { money = 2, inventory = { paper = 2 } },
    })
    local staleVisitorPacket = Protocol.encode("visitor_snapshot", {
        sessionId = syncHost.sessionId,
        serverTick = visitorChanged and visitorChanged.serverTick or syncHost.serverTick,
        customer = visitorState("scheduled", false, 1, 1, "business-cat"),
        vendor = visitorState("waiting", true, 2, 2, "green-blazer-cat"),
    })
    local wrongSessionVisitorPacket = Protocol.encode("visitor_snapshot", {
        sessionId = "other-shop",
        serverTick = (visitorChanged and visitorChanged.serverTick or syncHost.serverTick) + 1,
        customer = authoritativeVisitors.customer,
        vendor = authoritativeVisitors.vendor,
    })
    local staleEnvironmentPacket = Protocol.encode("environment_snapshot", {
        sessionId = syncHost.sessionId,
        serverTick = environmentChanged and environmentChanged.serverTick or syncHost.serverTick,
        bayDoor = { state = "closed", progress = 0 },
        truck = { state = "absent", backingProgress = 0, cargoProgress = 0 },
    })
    local wrongSessionEnvironmentPacket = Protocol.encode("environment_snapshot", {
        sessionId = "other-shop",
        serverTick = (environmentChanged and environmentChanged.serverTick
            or syncHost.serverTick) + 1,
        bayDoor = { state = "open", progress = 1 },
        truck = authoritativeEnvironment.truck,
    })
    syncNetwork.host:send(syncNetwork.peer, stalePacket,
        Protocol.CHANNEL_DURABLE, true)
    syncNetwork.host:send(syncNetwork.peer, wrongSessionPacket,
        Protocol.CHANNEL_DURABLE, true)
    syncNetwork.host:send(syncNetwork.peer, staleVisitorPacket,
        Protocol.CHANNEL_STATE, false)
    syncNetwork.host:send(syncNetwork.peer, wrongSessionVisitorPacket,
        Protocol.CHANNEL_STATE, false)
    syncNetwork.host:send(syncNetwork.peer, staleEnvironmentPacket,
        Protocol.CHANNEL_STATE, false)
    syncNetwork.host:send(syncNetwork.peer, wrongSessionEnvironmentPacket,
        Protocol.CHANNEL_STATE, false)
    syncClient:update(0, syncClientContext)
    local rejectedStateEvents = syncClient:drainEvents()
    check("multiplayer_session_guest_ignores_stale_and_wrong_session_shop_state",
        eventNamed(rejectedStateEvents, "shop_state") == nil
        and syncClient.lastShopRevision == deliveredRevision)
    check("multiplayer_session_guest_ignores_stale_and_wrong_session_visitor_state",
        eventNamed(rejectedStateEvents, "visitor_state") == nil)
    check("multiplayer_session_guest_ignores_stale_and_wrong_session_environment_state",
        eventNamed(rejectedStateEvents, "environment_state") == nil
        and syncClient.lastEnvironmentTick == environmentChanged.serverTick)

    local forgedStatePacket = Protocol.encode("shop_state", {
        sessionId = syncHost.sessionId,
        revision = deliveredRevision + 100,
        state = { money = 999999, inventory = { paper = 999999 } },
    })
    syncNetwork:sendRawToHost(forgedStatePacket, Protocol.CHANNEL_DURABLE, true)
    syncHost:update(0, syncHostContext)
    syncClient:update(0, syncClientContext)
    local rejectionEvents = syncClient:drainEvents()
    local rejected = eventNamed(rejectionEvents, "error")
    local forgedPackets = syncNetwork:messages("client_to_host", "shop_state")
    check("multiplayer_session_guest_cannot_mutate_authoritative_shop_state",
        #forgedPackets == 1
        and forgedPackets[1].channel == Protocol.CHANNEL_DURABLE
        and forgedPackets[1].reliable
        and rejected and rejected.code == "message_not_allowed"
        and authoritativeState.money == 925
        and authoritativeState.inventory.paper == 2375
        and authoritativeState.jobs.active[1].id == "LAN-JOB-0001")

    syncClient:stop("State sync test complete")
    syncHost:update(0, syncHostContext)
    syncHost:stop("State sync test complete")
end

return Test
