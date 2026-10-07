-- Multiplayer session regression scenarios.
-- A fresh Context belongs to each invocation; closures keep its live values.
local Component = {}

function Component.run(Context)
    Context.runStaleWorkshopGrantRevisionRegression(Context.check)
    Context.runHudExperienceRegression(Context.check)
    Context.now = 100
    Context.clock = function() return Context.now end
    Context.network = Context.fakeNetwork()
    Context.host = Context.Session.new({ transportFactory = Context.network.factory, clock = Context.clock })
    Context.client = Context.Session.new({ transportFactory = Context.network.factory, clock = Context.clock })
    Context.hostPlayer = Context.motionPlayer(400, 500)
    Context.guestPlayer = Context.motionPlayer(428, 500)
    Context.moveCalls = {}
    Context.interactionCalls = {}
    Context.interactionMutations = 0
    Context.interactionX, Context.interactionY, Context.interactionRadius = 300, 285, 72
    Context.hostContext = {
        localPlayer = Context.hostPlayer,
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
            Context.moveCalls[#Context.moveCalls + 1] = {
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
            Context.interactionCalls[#Context.interactionCalls + 1] = {
                player = player, x = player.x, y = player.y, targetKind = targetKind,
                desiredState = desiredState,
            }
            local dx, dy = player.x - Context.interactionX, player.y - Context.interactionY
            if dx * dx + dy * dy > Context.interactionRadius * Context.interactionRadius then
                return false, "out_of_range", "Move closer to the loading-bay wall switch."
            end
            Context.interactionMutations = Context.interactionMutations + 1
            return true, "accepted", "Opening the loading bay door..."
        end,
    }
    Context.clientContext = {
        localPlayer = Context.guestPlayer,
        inputX = 0.75,
        inputY = -0.25,
    }
    Context.addressOptions = { socket = { dns = {
        gethostname = function() return "picture-shop-host" end,
        getaddrinfo = function() return { { addr = "192.168.1.50" } } end,
    } } }

    Context.hostStarted = Context.host:startHost({
        name = "PC Host",
        character = "rabbit-worker",
        x = Context.hostPlayer.x,
        y = Context.hostPlayer.y,
        addressOptions = Context.addressOptions,
    })
    Context.host.sessionId = "session-test"
    Context.clientStarted = Context.client:startClient("192.168.1.50:22122", {
        name = "Phone Guest",
        character = "rabbit-worker",
    })
    Context.client.clientNonce = "nonce-test"
    Context.check("multiplayer_session_fake_pair_starts_without_real_socket",
        Context.hostStarted and Context.clientStarted and Context.host:isHost() and Context.client:isClient()
        and Context.network.hostOptions.maxGuests == 3 and Context.network.hostOptions.channels == 3
        and Context.network.clientOptions.channels == 3
        and Context.network.clientEndpoint == "192.168.1.50:22122")

    Context.client:update(0, Context.clientContext)
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.hostEvents = Context.host:drainEvents()
    Context.clientEvents = Context.client:drainEvents()
    Context.joined = Context.eventNamed(Context.hostEvents, "player_joined")
    Context.ready = Context.eventNamed(Context.clientEvents, "ready")
    Context.hello = Context.network:messages("client_to_host", "hello")[1]
    Context.welcome = Context.network:messages("host_to_client", "welcome")[1]
    Context.shopSnapshot = Context.network:messages("host_to_client", "shop_snapshot")[1]
    Context.check("multiplayer_session_hello_welcome_and_shop_snapshot_make_guest_ready",
        Context.hello and Context.hello.channel == Context.Protocol.CHANNEL_CONTROL and Context.hello.reliable
        and Context.welcome and Context.welcome.channel == Context.Protocol.CHANNEL_CONTROL and Context.welcome.reliable
        and Context.shopSnapshot and Context.shopSnapshot.channel == Context.Protocol.CHANNEL_DURABLE and Context.shopSnapshot.reliable
        and Context.joined and Context.joined.playerId == 2 and Context.joined.name == "Phone Guest"
        and Context.ready and Context.ready.playerId == 2 and Context.ready.state.money == 2345
        and Context.ready.revision == 0 and Context.client.lastShopRevision == 0
        and Context.ready.hostPlayer.x == 400 and Context.ready.spawn.x == 450 and Context.ready.spawn.y == 510
        and Context.client.ready and Context.client.sessionId == "session-test")

    Context.check("multiplayer_session_assigns_numeric_guest_id_and_shared_roster",
        Context.host.localId == 1 and Context.client.localId == 2
        and type(Context.host.localId) == "number" and type(Context.client.localId) == "number"
        and Context.host.players[1].name == "PC Host" and Context.host.players[2].name == "Phone Guest"
        and Context.client.players[1].name == "PC Host" and Context.client.players[2].name == "Phone Guest"
        and Context.host.peerToId[Context.network.peer] == 2 and Context.host.idToPeer[2] == Context.network.peer)

    Context.moveCalls = {}
    Context.client:update(0.05, Context.clientContext)
    Context.host:update(0.05, Context.hostContext)
    Context.authoritativeGuest = Context.host.players[2]
    Context.input = Context.network:messages("client_to_host", "input")[1]
    Context.check("multiplayer_session_host_accepts_guest_input_authoritatively",
        Context.input and Context.input.channel == Context.Protocol.CHANNEL_STATE and not Context.input.reliable
        and Context.authoritativeGuest and Context.authoritativeGuest.inputSequence == 1
        and Context.authoritativeGuest.inputX == 0.75 and Context.authoritativeGuest.inputY == -0.25
        and #Context.moveCalls == 1 and Context.moveCalls[1].id == 2
        and math.abs(Context.authoritativeGuest.x - 453.75) < 0.0001
        and math.abs(Context.authoritativeGuest.y - 508.75) < 0.0001,
        string.format("input=%s channel=%s reliable=%s seq=%s axes=%s,%s calls=%d pos=%s,%s",
            tostring(Context.input and Context.input.kind), tostring(Context.input and Context.input.channel),
            tostring(Context.input and Context.input.reliable),
            tostring(Context.authoritativeGuest and Context.authoritativeGuest.inputSequence),
            tostring(Context.authoritativeGuest and Context.authoritativeGuest.inputX),
            tostring(Context.authoritativeGuest and Context.authoritativeGuest.inputY),
            #Context.moveCalls, tostring(Context.authoritativeGuest and Context.authoritativeGuest.x),
            tostring(Context.authoritativeGuest and Context.authoritativeGuest.y)))

    Context.host:update(0.04, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.authoritativeX, Context.authoritativeY = Context.host.players[2].x, Context.host.players[2].y
    Context.snapshots = Context.network:messages("host_to_client", "snapshot")
    Context.guestSnapshot, Context.sharedSnapshotTick = nil
    Context.snapshotShardsValid = #Context.snapshots == 2
    for _, message in ipairs(Context.snapshots) do
        local payload = Context.decodedPayload(message)
        Context.snapshotShardsValid = Context.snapshotShardsValid and payload ~= nil
            and #payload.players == 1
            and #message.payload <= Context.Protocol.MAX_PACKET_BYTES
        if payload then
            Context.sharedSnapshotTick = Context.sharedSnapshotTick or payload.serverTick
            Context.snapshotShardsValid = Context.snapshotShardsValid
                and payload.serverTick == Context.sharedSnapshotTick
            if payload.players[1].id == 2 then Context.guestSnapshot = payload end
        end
    end
    Context.check("multiplayer_session_host_snapshot_returns_guest_motion_to_client",
        Context.snapshotShardsValid and Context.guestSnapshot
        and Context.snapshots[1].channel == Context.Protocol.CHANNEL_STATE
        and not Context.snapshots[1].reliable and Context.host.serverTick == 1 and Context.client.lastServerTick == 1
        and Context.client.localTarget and Context.client.localTarget.id == 2
        and math.abs(Context.client.localTarget.x - Context.authoritativeX) < 0.0001
        and math.abs(Context.client.localTarget.y - Context.authoritativeY) < 0.0001)

    Context.runFourDeviceShardingRegression(Context.check, Context.clock, Context.addressOptions)

    Context.staleInput = Context.Protocol.encode("input", {
        sessionId = Context.host.sessionId,
        sequence = 1,
        moveX = -1,
        moveY = 1,
    })
    Context.network:sendRawToHost(Context.staleInput)
    Context.host:update(0, Context.hostContext)
    Context.wrongSessionInput = Context.Protocol.encode("input", {
        sessionId = "spoofed-session",
        sequence = 99,
        moveX = -1,
        moveY = 1,
    })
    Context.network:sendRawToHost(Context.wrongSessionInput)
    Context.host:update(0, Context.hostContext)
    Context.check("multiplayer_session_stale_and_spoofed_inputs_are_ignored",
        Context.host.players[2].inputSequence == 1
        and Context.host.players[2].inputX == 0.75 and Context.host.players[2].inputY == -0.25)

    -- A guest USE request carries no coordinates. The callback must receive
    -- the peer-derived authoritative host player even when client prediction
    -- places the phone somewhere completely different.
    Context.host.players[2].x, Context.host.players[2].y = Context.interactionX, Context.interactionY
    Context.guestPlayer.x, Context.guestPlayer.y = 900, 620
    Context.requestedInteraction = Context.client:requestInteraction("loadingBayDoor", "open")
    Context.firstInteractionRequest = Context.network:messages("client_to_host", "interaction_request")[1]
    Context.firstWireRequest = Context.decodedPayload(Context.firstInteractionRequest)
    Context.host:update(0, Context.hostContext)
    Context.client:update(0, Context.clientContext)
    Context.firstInteractionEvents = Context.client:drainEvents()
    Context.firstInteractionResult = Context.eventNamed(Context.firstInteractionEvents, "interaction_result")
    Context.interactionResults = Context.network:messages("host_to_client", "interaction_result")
    Context.firstWireResult = Context.decodedPayload(Context.interactionResults[1])
    Context.check("multiplayer_session_guest_use_executes_at_authoritative_peer_position",
        Context.requestedInteraction and Context.firstInteractionRequest
        and Context.firstInteractionRequest.channel == Context.Protocol.CHANNEL_CONTROL
        and Context.firstInteractionRequest.reliable
        and Context.firstWireRequest and Context.firstWireRequest.desiredState == "open"
        and #Context.interactionCalls == 1
        and Context.interactionCalls[1].player == Context.host.players[2]
        and Context.interactionCalls[1].x == Context.interactionX and Context.interactionCalls[1].y == Context.interactionY
        and Context.interactionCalls[1].x ~= Context.guestPlayer.x and Context.interactionCalls[1].y ~= Context.guestPlayer.y
        and Context.interactionCalls[1].targetKind == "loadingBayDoor"
        and Context.interactionCalls[1].desiredState == "open"
        and Context.interactionMutations == 1
        and Context.firstInteractionResult and Context.firstInteractionResult.accepted
        and Context.firstInteractionResult.code == "accepted"
        and Context.firstWireResult and Context.firstWireResult.requestId == 1
        and Context.interactionResults[1].channel == Context.Protocol.CHANNEL_CONTROL
        and Context.interactionResults[1].reliable
        and #Context.network:messages("host_broadcast", "interaction_result") == 0)

    -- Reliable transport should already suppress duplicates, but the command
    -- itself is also idempotent: replay the exact packet and require the host
    -- to replay its cached result without invoking the world callback again.
end

return Component
