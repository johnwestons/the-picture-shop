local DirectTransport = require("src.net.transport_direct")
local Protocol = require("src.net.protocol")
local Session = require("src.net.session")

local Test = {}

local SHARED_KEY = string.rep("s", DirectTransport.KEY_BYTES)
local WRONG_KEY = string.rep("w", DirectTransport.KEY_BYTES)

local function digest(value)
    local hash = 7
    for index = 1, #value do
        hash = (hash * 131 + value:byte(index)) % 2147483647
    end
    return string.format("%08x", hash)
end

local function fakeAdmissionToken(key)
    return tonumber(digest("direct-admission|" .. key), 16)
end

local function hexEncode(value)
    return (value:gsub(".", function(character)
        return string.format("%02x", character:byte())
    end))
end

local function hexDecode(value)
    if #value % 2 ~= 0 or value:find("[^0-9a-f]") then return nil end
    return (value:gsub("..", function(pair)
        return string.char(tonumber(pair, 16))
    end))
end

-- This deterministic provider models the high-level authenticated transport
-- contract. It is deliberately test-only: productionReady proves that the
-- wrapper's fail-closed provider gate composes with Session without weakening
-- that gate for tests.
local function fakeCryptoProvider(log)
    local provider = { productionReady = true }

    function provider.admissionToken(key)
        log[#log + 1] = { action = "admissionToken" }
        return fakeAdmissionToken(key)
    end

    local function newState(role, key)
        local state = {
            role = role,
            key = key,
            ready = false,
            closed = false,
            phase = role == "initiator" and "new" or "wait-initiator",
        }

        function state:start()
            log[#log + 1] = { action = "start", role = self.role }
            if self.role == "initiator" then
                self.phase = "wait-responder"
                return "initiator:" .. digest(self.key .. ":initiator")
            end
            return nil
        end

        function state:handshake(message)
            log[#log + 1] = {
                action = "handshake",
                role = self.role,
                message = message,
            }
            if self.role == "responder" then
                if self.phase == "wait-initiator"
                    and message == "initiator:" .. digest(self.key .. ":initiator")
                then
                    self.phase = "wait-finish"
                    return "responder:" .. digest(self.key .. ":responder")
                end
                if self.phase == "wait-finish"
                    and message == "finish:" .. digest(self.key .. ":finish")
                then
                    self.phase = "ready"
                    self.ready = true
                    return "ack:" .. digest(self.key .. ":ack")
                end
                if self.phase == "wait-initiator" then
                    return nil, "initiator authentication failed"
                end
                return nil, "initiator finish failed"
            end
            if self.phase == "wait-responder"
                and message == "responder:" .. digest(self.key .. ":responder")
            then
                self.phase = "wait-ack"
                return "finish:" .. digest(self.key .. ":finish")
            end
            if self.phase == "wait-ack"
                and message == "ack:" .. digest(self.key .. ":ack")
            then
                self.phase = "ready"
                self.ready = true
                return nil
            end
            if self.phase == "wait-responder" then
                return nil, "responder authentication failed"
            end
            return nil, "responder acknowledgement failed"
        end

        function state:isReady()
            return self.ready
        end

        function state:seal(plaintext, aad)
            if not self.ready then return nil, "state is not authenticated" end
            local envelope = Protocol.decode(plaintext)
            local encoded = hexEncode(plaintext)
            local tag = digest(self.key .. "|" .. aad .. "|" .. encoded)
            log[#log + 1] = {
                action = "seal",
                role = self.role,
                ready = self.ready,
                aad = aad,
                messageType = envelope and envelope.type or nil,
            }
            return tag .. ":" .. encoded
        end

        function state:open(ciphertext, aad)
            if not self.ready then return nil, "state is not authenticated" end
            local tag, encoded = ciphertext:match("^([0-9a-f]+):([0-9a-f]*)$")
            if not tag then return nil, "malformed ciphertext" end
            local expected = digest(self.key .. "|" .. aad .. "|" .. encoded)
            if tag ~= expected then return nil, "authentication tag mismatch" end
            local plaintext = hexDecode(encoded)
            if plaintext == nil then return nil, "malformed plaintext" end
            local envelope = Protocol.decode(plaintext)
            log[#log + 1] = {
                action = "open",
                role = self.role,
                ready = self.ready,
                messageType = envelope and envelope.type or nil,
            }
            return plaintext
        end

        function state:close()
            self.closed = true
            log[#log + 1] = { action = "close", role = self.role }
            return true
        end

        return state
    end

    function provider.newInitiator(key)
        return newState("initiator", key)
    end

    function provider.newResponder(key)
        return newState("responder", key)
    end

    return provider
end

local function fakeBaseNetwork()
    local network = {
        rawSends = {},
        disconnects = {},
        closes = {},
        clients = {},
        peer = { id = "direct-session-guest" },
        factory = {
            DEFAULT_PORT = 22122,
            DEFAULT_CHANNELS = 3,
            MIN_CHANNELS = 3,
            MAX_GUESTS = 3,
        },
    }

    local function newBase(mode, peer, channels)
        local base = {
            mode = mode,
            peer = peer,
            channels = channels or 3,
            inbound = {},
            closed = false,
        }

        function base:poll()
            return table.remove(self.inbound, 1)
        end

        function base:send(targetPeer, payload, channel, reliable)
            if self.closed then return false, "base transport is closed" end
            local destination
            if self.mode == "host" then
                destination = network.clients[targetPeer]
            elseif targetPeer == self.peer then
                destination = network.host
            end
            if not destination or destination.closed then
                return false, "base peer is unavailable"
            end
            network.rawSends[#network.rawSends + 1] = {
                sender = self.mode,
                peer = targetPeer,
                payload = payload,
                channel = channel,
                reliable = reliable == true,
                frameType = type(payload) == "string" and payload:byte(6) or nil,
            }
            destination.inbound[#destination.inbound + 1] = {
                type = "receive",
                peer = targetPeer,
                data = payload,
                payload = payload,
                channel = channel,
                reliable = reliable == true,
            }
            return true
        end

        function base:disconnect(targetPeer, code, immediate)
            network.disconnects[#network.disconnects + 1] = {
                sender = self.mode,
                peer = targetPeer,
                code = code,
                immediate = immediate == true,
            }
            local destination = self.mode == "host"
                and network.clients[targetPeer] or network.host
            if destination and not destination.closed then
                destination.inbound[#destination.inbound + 1] = {
                    type = "disconnect",
                    peer = targetPeer,
                    data = code,
                    code = code,
                }
            end
            return true
        end

        function base:flush()
            return true
        end

        function base:close(code, immediate)
            if self.closed then return true end
            self.closed = true
            network.closes[#network.closes + 1] = {
                mode = self.mode,
                code = code,
                immediate = immediate == true,
            }
            return true
        end

        return base
    end

    function network.factory.createHost(options)
        network.hostOptions = options
        network.host = newBase("host", nil, options and options.channels)
        network.host.endpoint = "*:22122"
        network.host.maxGuests = 3
        network.host.peerCapacity = options and options.peerCapacity or 3
        return network.host
    end

    function network.factory.createClient(endpoint, options)
        if not network.host then return nil, "base host has not started" end
        network.clientEndpoint = endpoint
        network.clientOptions = options
        local client = newBase("client", network.peer, options and options.channels)
        network.client = client
        network.clients[network.peer] = client
        network.host.inbound[#network.host.inbound + 1] = {
            type = "connect",
            peer = network.peer,
            data = options and options.connectData,
            code = options and options.connectData,
        }
        client.inbound[#client.inbound + 1] = {
            type = "connect",
            peer = network.peer,
            data = options and options.connectData,
            code = options and options.connectData,
        }
        return client
    end

    return network
end

local function directFactory(network, key, cryptoLog, clock)
    return DirectTransport.newFactory({
        baseFactory = network.factory,
        cryptoProvider = fakeCryptoProvider(cryptoLog),
        key = key,
        clock = clock,
        handshakeTimeout = 5,
    })
end

local function motionPlayer(x, y)
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
        inputSequence = 0,
    }
end

local function eventNamed(events, eventType)
    for _, event in ipairs(events or {}) do
        if event.type == eventType then return event end
    end
end

local function cryptoCall(log, action, messageType)
    for _, call in ipairs(log) do
        if call.action == action
            and (messageType == nil or call.messageType == messageType)
        then
            return call
        end
    end
end

local function countDataFrames(network)
    local count = 0
    for _, item in ipairs(network.rawSends) do
        if item.frameType == DirectTransport.TYPE_DATA then count = count + 1 end
    end
    return count
end

local function addressOptions()
    return { socket = { dns = {
        gethostname = function() return "direct-test-host" end,
        getaddrinfo = function()
            return { { addr = "192.168.1.50" } }
        end,
    } } }
end

function Test.run(_, check)
    local now = 100
    local clock = function() return now end
    local network = fakeBaseNetwork()
    local hostCryptoLog, clientCryptoLog = {}, {}
    local hostFactory = directFactory(network, SHARED_KEY, hostCryptoLog, clock)
    local clientFactory = directFactory(network, SHARED_KEY, clientCryptoLog, clock)
    local host = Session.new({ transportFactory = hostFactory, clock = clock })
    local client = Session.new({ transportFactory = clientFactory, clock = clock })
    local hostPlayer = motionPlayer(400, 500)
    local guestPlayer = motionPlayer(430, 500)
    local snapshotCalls = 0
    local hostContext = {
        localPlayer = hostPlayer,
        resolveGuestSpawn = function() return 450, 510 end,
        getShopSnapshot = function()
            snapshotCalls = snapshotCalls + 1
            return {
                state = {
                    money = 2468,
                    screen = "world",
                    inventory = { paper = 1200, prints = 8 },
                    jobs = { active = {}, completed = {} },
                },
                player = { x = 400, y = 500, character = "rabbit-worker" },
            }
        end,
    }
    local clientContext = {
        localPlayer = guestPlayer,
        inputX = 0,
        inputY = 0,
    }

    local hostStarted = host:startHost({
        name = "Direct Host",
        character = "rabbit-worker",
        networkKind = "direct",
        -- Direct approval is a security boundary, not a caller preference.
        requireHostApproval = false,
        x = hostPlayer.x,
        y = hostPlayer.y,
        addressOptions = addressOptions(),
    })
    host.sessionId = "direct-session-test"
    local clientStarted = client:startClient("198.51.100.10:22122", {
        name = "Direct Guest",
        character = "rabbit-worker",
        networkKind = "direct",
    })
    client.clientNonce = "direct-session-nonce"
    host:drainEvents()

    -- Complete the four mutually confirmed authentication messages. Neither
    -- Session has received application data at this boundary.
    client:update(0, clientContext)
    host:update(0, hostContext)
    client:update(0, clientContext)
    host:update(0, hostContext)
    local dataBeforeAuthentication = countDataFrames(network)
    local hostSawAuthenticatedPeer = host.pendingPeers[network.peer] ~= nil

    -- The authenticated client connect is now visible to Session, which emits
    -- its existing hello through the encrypted wrapper.
    client:update(0, clientContext)
    local sealedHello = cryptoCall(clientCryptoLog, "seal", "hello")
    local first, second, third, fourth, fifth = network.rawSends[1],
        network.rawSends[2], network.rawSends[3], network.rawSends[4],
        network.rawSends[5]
    check("direct_session_authenticates_before_session_hello",
        hostStarted and clientStarted
        and dataBeforeAuthentication == 0
        and hostSawAuthenticatedPeer
        and snapshotCalls == 0 and host.players[2] == nil
        and sealedHello and sealedHello.ready
        and first and first.sender == "client"
        and first.frameType == DirectTransport.TYPE_HANDSHAKE
        and second and second.sender == "host"
        and second.frameType == DirectTransport.TYPE_HANDSHAKE
        and third and third.sender == "client"
        and third.frameType == DirectTransport.TYPE_HANDSHAKE
        and fourth and fourth.sender == "host"
        and fourth.frameType == DirectTransport.TYPE_HANDSHAKE
        and fifth and fifth.sender == "client"
        and fifth.frameType == DirectTransport.TYPE_DATA
        and Protocol.decode(fifth.payload) == nil)

    -- The authenticated hello becomes a bounded host decision. It must not
    -- allocate a player or disclose the durable host save before approval.
    host:update(0, hostContext)
    local approvalEvents = host:drainEvents()
    local requested = eventNamed(approvalEvents, "join_requested")
    local approvalInfo = host:hudInfo()
    check("direct_session_authenticated_hello_waits_for_explicit_host_approval",
        requested and requested.name == "Direct Guest"
        and type(requested.requestId) == "number"
        and host.requireHostApproval == true
        and approvalInfo.canManage and approvalInfo.pendingJoinCount == 1
        and approvalInfo.pendingJoins[1].requestId == requested.requestId
        and snapshotCalls == 0 and host.players[2] == nil
        and cryptoCall(hostCryptoLog, "seal", "welcome") == nil
        and cryptoCall(hostCryptoLog, "seal", "shop_snapshot") == nil)
    local approved = host:approveJoin(requested and requested.requestId)
    host:update(0, hostContext)
    client:update(0, clientContext)
    local hostEvents = host:drainEvents()
    local clientEvents = client:drainEvents()
    local joined = eventNamed(hostEvents, "player_joined")
    local ready = eventNamed(clientEvents, "ready")
    local sealedWelcome = cryptoCall(hostCryptoLog, "seal", "welcome")
    local sealedShop = cryptoCall(hostCryptoLog, "seal", "shop_snapshot")
    local openedWelcome = cryptoCall(clientCryptoLog, "open", "welcome")
    local openedShop = cryptoCall(clientCryptoLog, "open", "shop_snapshot")
    check("direct_session_existing_welcome_and_shop_snapshot_make_guest_ready",
        approved and snapshotCalls == 1
        and sealedWelcome and sealedWelcome.ready
        and sealedShop and sealedShop.ready
        and DirectTransport.DURABLE_CHANNEL == Protocol.CHANNEL_DURABLE
        and sealedShop.aad == DirectTransport.aadForChannel(Protocol.CHANNEL_DURABLE)
        and openedWelcome and openedWelcome.ready
        and openedShop and openedShop.ready
        and joined and joined.playerId == 2 and joined.name == "Direct Guest"
        and ready and ready.playerId == 2 and ready.state.money == 2468
        and ready.hostPlayer.x == 400
        and ready.spawn.x == 450 and ready.spawn.y == 510
        and host.players[2] and host.players[2].name == "Direct Guest"
        and host.peerToId[network.peer] == 2
        and client.ready and client.localId == 2
        and client.sessionId == "direct-session-test")

    client:stop("Direct session success test complete")
    host:stop("Direct session success test complete")

    local rejectedNetwork = fakeBaseNetwork()
    local rejectedHostLog, rejectedClientLog = {}, {}
    local rejectedHostFactory = directFactory(
        rejectedNetwork, SHARED_KEY, rejectedHostLog, clock)
    local rejectedClientFactory = directFactory(
        rejectedNetwork, WRONG_KEY, rejectedClientLog, clock)
    local rejectedHost = Session.new({
        transportFactory = rejectedHostFactory,
        clock = clock,
    })
    local rejectedClient = Session.new({
        transportFactory = rejectedClientFactory,
        clock = clock,
    })
    local rejectedSnapshotCalls = 0
    local rejectedHostContext = {
        localPlayer = motionPlayer(400, 500),
        getShopSnapshot = function()
            rejectedSnapshotCalls = rejectedSnapshotCalls + 1
            return {
                state = { money = 999 },
                player = { x = 400, y = 500, character = "rabbit-worker" },
            }
        end,
    }
    local rejectedClientContext = {
        localPlayer = motionPlayer(430, 500),
        inputX = 0,
        inputY = 0,
    }

    rejectedHost:startHost({
        name = "Rejecting Host",
        character = "rabbit-worker",
        networkKind = "direct",
        x = 400,
        y = 500,
        addressOptions = addressOptions(),
    })
    rejectedClient:startClient("198.51.100.10:22122", {
        name = "Wrong Key Guest",
        character = "rabbit-worker",
        networkKind = "direct",
    })
    rejectedHost:drainEvents()
    rejectedClient:update(0, rejectedClientContext)
    rejectedHost:update(0, rejectedHostContext)
    rejectedClient:update(0, rejectedClientContext)

    local rejectedHostEvents = rejectedHost:drainEvents()
    local rejectedClientEvents = rejectedClient:drainEvents()
    local authenticationDisconnect = rejectedNetwork.disconnects[1]
    check("direct_session_wrong_key_never_reaches_host_session_or_shop_snapshot",
        rejectedSnapshotCalls == 0
        and rejectedHost.players[1] ~= nil and rejectedHost.players[2] == nil
        and rejectedHost.peerToId[rejectedNetwork.peer] == nil
        and rejectedHost.pendingPeers[rejectedNetwork.peer] == nil
        and eventNamed(rejectedHostEvents, "player_joined") == nil
        and eventNamed(rejectedHostEvents, "join_requested") == nil
        and cryptoCall(rejectedClientLog, "seal", "hello") == nil
        and countDataFrames(rejectedNetwork) == 0)
    check("direct_session_wrong_key_disconnects_client_before_hello",
        authenticationDisconnect
        and authenticationDisconnect.sender == "host"
        and authenticationDisconnect.code
            == DirectTransport.DISCONNECT_AUTHENTICATION
        and eventNamed(rejectedClientEvents, "disconnected") ~= nil
        and rejectedClient.terminal and not rejectedClient.ready
        and rejectedClient.transport == nil)

    rejectedClient:stop("Direct session rejection test complete")
    rejectedHost:stop("Direct session rejection test complete")
end

return Test
