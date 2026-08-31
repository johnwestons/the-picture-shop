local BridgeTransport = require("src.net.transport_ipv6_bridge")

local Test = {}

local KEY = string.rep("q", 32)
local INVITATION_ID = "bridge-session-1"
local GUEST_NONCE = "guest-nonce-0001"
local HOST_ADDRESS = "2606:4700:4700::1111"
local GUEST_ADDRESS = "2606:4700:4700::1001"

local function be32(value)
    return string.char(
        math.floor(value / 16777216) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 256) % 256,
        value % 256)
end

local function read32(value, offset)
    local a, b, c, d = value:byte(offset, offset + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
end

local function digest(value)
    local hash = 19
    for index = 1, #value do
        hash = (hash * 131 + value:byte(index)) % 2147483647
    end
    local word = string.format("%08x", hash)
    return word .. word
end

local function bridgeProvider()
    local provider = { productionReady = true }
    local function create(role, key, invitationId, guestNonce)
        local state = {
            role = role,
            key = key .. invitationId .. guestNonce,
            nextSequence = 0,
            received = {},
            closed = false,
        }
        function state:seal(plaintext, aad)
            local sequence = self.nextSequence
            self.nextSequence = sequence + 1
            local sequenceBytes = string.rep("\0", 4) .. be32(sequence)
            local direction = self.role == "guest" and "g2h" or "h2g"
            return sequenceBytes
                .. digest(self.key .. direction .. aad .. sequenceBytes .. plaintext)
                .. plaintext
        end
        function state:open(ciphertext, aad)
            if self.closed or #ciphertext < 24
                or ciphertext:sub(1, 4) ~= string.rep("\0", 4) then
                return false
            end
            local sequence = read32(ciphertext, 5)
            if self.received[sequence] then return false end
            local sequenceBytes = ciphertext:sub(1, 8)
            local tag, plaintext = ciphertext:sub(9, 24), ciphertext:sub(25)
            local direction = self.role == "host" and "g2h" or "h2g"
            if tag ~= digest(self.key .. direction .. aad
                .. sequenceBytes .. plaintext) then
                return false
            end
            self.received[sequence] = true
            return plaintext
        end
        function state:close()
            self.closed = true
            return true
        end
        return state
    end
    function provider.newBridgeHost(key, invitationId, guestNonce)
        return create("host", key, invitationId, guestNonce)
    end
    function provider.newBridgeGuest(key, invitationId, guestNonce)
        return create("guest", key, invitationId, guestNonce)
    end
    return provider
end

local function outerPair()
    local function newSocket(address, port)
        local socket = {
            address = address,
            port = port,
            inbound = {},
            closed = false,
        }
        function socket:settimeout() return 1 end
        function socket:receivefrom()
            local item = table.remove(self.inbound, 1)
            if not item then return nil, "timeout" end
            return item.packet, item.address, item.port
        end
        function socket:sendto(packet)
            self.peer.inbound[#self.peer.inbound + 1] = {
                packet = packet,
                address = self.address,
                port = self.port,
            }
            return 1
        end
        function socket:close()
            self.closed = true
            return 1
        end
        return socket
    end
    local host = newSocket(HOST_ADDRESS, 47001)
    local guest = newSocket(GUEST_ADDRESS, 47002)
    host.peer, guest.peer = guest, host
    return host, guest
end

local function opening(socket)
    local value = { status = "ready", socket = socket, takeCount = 0, closeCount = 0 }
    function value:isReady() return self.status == "ready" end
    function value:takeSocket()
        if self.status ~= "ready" then return nil, "not ready" end
        self.status = "handed_off"
        self.takeCount = self.takeCount + 1
        local result = self.socket
        self.socket = nil
        return result
    end
    function value:close()
        self.closeCount = self.closeCount + 1
        if self.status == "closed" then return true end
        local pending = self.socket
        self.socket = nil
        self.status = "closed"
        if pending then return pending:close() ~= nil end
        return true
    end
    return value
end

local function loopbackHub(firstPort)
    local hub = { endpoints = {}, nextPort = firstPort }

    function hub:allocate()
        local port = self.nextPort
        self.nextPort = port + 1
        return port
    end

    function hub:bind(port)
        if self.endpoints[port] then return nil end
        local endpoint = { inbound = {} }
        self.endpoints[port] = endpoint
        return endpoint
    end

    function hub:send(sourcePort, targetPort, packet)
        local target = self.endpoints[targetPort]
        if not target then return nil, "unreachable" end
        target.inbound[#target.inbound + 1] = {
            packet = packet,
            address = "127.0.0.1",
            port = sourcePort,
        }
        return 1
    end

    local socketModule = {}
    function socketModule.udp()
        local socket = { hub = hub, closed = false }
        function socket:settimeout() return 1 end
        function socket:setsockname(address, port)
            if address ~= "127.0.0.1" then return nil end
            if port == 0 then port = self.hub:allocate() end
            local endpoint = self.hub:bind(port)
            if not endpoint then return nil end
            self.address, self.port, self.endpoint = address, port, endpoint
            return 1
        end
        function socket:getsockname()
            return self.address, self.port, "inet"
        end
        function socket:receivefrom()
            local item = table.remove(self.endpoint.inbound, 1)
            if not item then return nil, "timeout" end
            return item.packet, item.address, item.port
        end
        function socket:sendto(packet, address, port)
            if self.closed or address ~= "127.0.0.1" then return nil end
            return self.hub:send(self.port, port, packet)
        end
        function socket:close()
            if not self.closed then
                self.closed = true
                self.hub.endpoints[self.port] = nil
            end
            return 1
        end
        return socket
    end
    return hub, socketModule
end

local function baseFactory(hub)
    local factory = {
        DEFAULT_PORT = 22122,
        MAX_GUESTS = 3,
        MAX_PEERS = 16,
        MIN_CHANNELS = 3,
        DEFAULT_CHANNELS = 3,
    }

    local function encodeData(channel, reliable, payload)
        return "D" .. string.char(channel, reliable and 1 or 0) .. payload
    end

    local function newBase(mode, endpoint, targetPort, channels, connectData)
        local base = {
            mode = mode,
            endpointState = endpoint,
            targetPort = targetPort,
            channels = channels or 3,
            peer = mode == "client" and { relayPort = targetPort } or nil,
            peers = {},
            closed = false,
        }
        function base:poll()
            local item = table.remove(self.endpointState.inbound, 1)
            if not item then return nil end
            local kind = item.packet:sub(1, 1)
            if kind == "C" and self.mode == "host" then
                local token = read32(item.packet, 2)
                local peer = self.peers[item.port] or { relayPort = item.port }
                self.peers[item.port] = peer
                hub:send(self.endpointState.port, item.port, "A" .. be32(token))
                return { type = "connect", peer = peer, data = token, code = token }
            elseif kind == "A" and self.mode == "client" then
                local token = read32(item.packet, 2)
                return { type = "connect", peer = self.peer, data = token, code = token }
            elseif kind == "D" then
                local peer = self.mode == "client"
                    and self.peer or self.peers[item.port]
                return {
                    type = "receive",
                    peer = peer,
                    channel = item.packet:byte(2),
                    reliable = item.packet:byte(3) == 1,
                    data = item.packet:sub(4),
                    payload = item.packet:sub(4),
                }
            end
            return nil
        end
        function base:send(peer, payload, channel, reliable)
            return hub:send(self.endpointState.port, peer.relayPort,
                encodeData(channel, reliable, payload))
        end
        function base:sendToServer(payload, channel, reliable)
            return self:send(self.peer, payload, channel, reliable)
        end
        function base:broadcast(payload, channel, reliable)
            for _, peer in pairs(self.peers) do
                if not self:send(peer, payload, channel, reliable) then return false end
            end
            return true
        end
        function base:flush() return true end
        function base:disconnect() return true end
        function base:close()
            if not self.closed then
                self.closed = true
                hub.endpoints[self.endpointState.port] = nil
            end
            return true
        end
        if mode == "client" then
            hub:send(endpoint.port, targetPort, "C" .. be32(connectData or 0))
        end
        return base
    end

    function factory.createHost(options)
        local endpoint = hub:bind(options.port)
        if not endpoint then return nil, "host bind failed" end
        endpoint.port = options.port
        factory.hostOptions = options
        return newBase("host", endpoint, nil, options.channels)
    end

    function factory.createClient(endpointText, options)
        local targetPort = tonumber(endpointText:match(":(%d+)$"))
        local port = hub:allocate()
        local endpoint = hub:bind(port)
        endpoint.port = port
        factory.clientEndpoint = endpointText
        return newBase("client", endpoint, targetPort,
            options.channels, options.connectData)
    end

    return factory
end

local function eventOf(events, eventType, payload)
    for _, event in ipairs(events) do
        if event.type == eventType
            and (payload == nil or event.data == payload) then
            return event
        end
    end
end

function Test.run(_, check)
    local hostOuter, guestOuter = outerPair()
    local hostOpening, guestOpening = opening(hostOuter), opening(guestOuter)
    local hostHub, hostSockets = loopbackHub(48000)
    local guestHub, guestSockets = loopbackHub(49000)
    local hostBase, guestBase = baseFactory(hostHub), baseFactory(guestHub)
    local provider = bridgeProvider()
    local hostFactory = assert(BridgeTransport.newFactory({
        role = "host",
        baseFactory = hostBase,
        socketModule = hostSockets,
        opening = hostOpening,
        provider = provider,
        masterKey = KEY,
        invitationId = INVITATION_ID,
        guestNonce = GUEST_NONCE,
        peerAddress = GUEST_ADDRESS,
        peerPort = 47002,
        loopbackHostPort = 46000,
    }))
    local guestFactory = assert(BridgeTransport.newFactory({
        role = "guest",
        baseFactory = guestBase,
        socketModule = guestSockets,
        opening = guestOpening,
        provider = provider,
        masterKey = KEY,
        invitationId = INVITATION_ID,
        guestNonce = GUEST_NONCE,
        peerAddress = HOST_ADDRESS,
        peerPort = 47001,
    }))
    local host = assert(hostFactory.createHost({ channels = 3, port = 22122 }))
    local client = assert(guestFactory.createClient("public-address-ignored", {
        channels = 3,
        connectData = 2468,
    }))

    local hostEvents, clientEvents = {}, {}
    for _ = 1, 4 do
        local hostEvent = host:poll()
        local clientEvent = client:poll()
        if hostEvent then hostEvents[#hostEvents + 1] = hostEvent end
        if clientEvent then clientEvents[#clientEvents + 1] = clientEvent end
    end
    local hostConnect = eventOf(hostEvents, "connect")
    local clientConnect = eventOf(clientEvents, "connect")
    check("ipv6_bridge_transport_hands_authenticated_socket_to_loopback_enet_once",
        hostConnect and clientConnect
        and hostConnect.code == 2468 and clientConnect.code == 2468
        and hostOpening.takeCount == 1 and guestOpening.takeCount == 1
        and hostOpening.status == "handed_off"
        and guestOpening.status == "handed_off"
        and hostBase.hostOptions.bind == "127.0.0.1"
        and hostBase.hostOptions.port == 46000
        and guestBase.clientEndpoint:match("^127%.0%.0%.1:%d+$"))

    local clientSent = client:sendToServer("client-enet-datagram", 2, false)
    local receivedAtHost
    for _ = 1, 3 do
        receivedAtHost = receivedAtHost or host:poll()
    end
    local hostFragmentsBefore = host.bridge.sentFragments
    local hostSent = host:send(hostConnect.peer,
        string.rep("H", 1390), 2, true)
    local receivedAtClient
    for _ = 1, 3 do
        receivedAtClient = receivedAtClient or client:poll()
    end
    check("ipv6_bridge_transport_carries_enet_channels_delivery_and_fragmented_datagrams",
        clientSent and hostSent
        and receivedAtHost and receivedAtHost.type == "receive"
        and receivedAtHost.data == "client-enet-datagram"
        and receivedAtHost.channel == 2 and receivedAtHost.reliable == false
        and receivedAtClient and receivedAtClient.type == "receive"
        and receivedAtClient.data == string.rep("H", 1390)
        and receivedAtClient.channel == 2 and receivedAtClient.reliable == true
        and host.bridge.sentFragments == hostFragmentsBefore + 2)

    local closedClient, closedHost = client:close(0, true), host:close(0, true)
    check("ipv6_bridge_transport_cleanup_closes_loopback_outer_and_crypto_owners",
        closedClient and closedHost and client:close() and host:close()
        and hostOuter.closed and guestOuter.closed)

    local rejected = BridgeTransport.newFactory({
        role = "host",
        baseFactory = hostBase,
        socketModule = hostSockets,
        opening = opening(select(1, outerPair())),
        provider = { productionReady = false },
        masterKey = KEY,
        invitationId = INVITATION_ID,
        guestNonce = GUEST_NONCE,
        peerAddress = GUEST_ADDRESS,
        peerPort = 47002,
        loopbackHostPort = 46001,
    })
    check("ipv6_bridge_transport_keeps_engineering_native_provider_fail_closed",
        rejected == nil)

    local abandonedOuter = select(1, outerPair())
    local abandonedOpening = opening(abandonedOuter)
    local abandonedHub, abandonedSockets = loopbackHub(50000)
    local abandonedFactory = assert(BridgeTransport.newFactory({
        role = "host",
        baseFactory = baseFactory(abandonedHub),
        socketModule = abandonedSockets,
        opening = abandonedOpening,
        provider = provider,
        masterKey = KEY,
        invitationId = INVITATION_ID,
        guestNonce = GUEST_NONCE,
        peerAddress = GUEST_ADDRESS,
        peerPort = 47002,
        loopbackHostPort = 46010,
    }))
    local disposed, disposeError = abandonedFactory.close()
    local disposedAgain, disposeAgainError = abandonedFactory.close()
    local createAfterDispose = abandonedFactory.createHost({ channels = 3 })
    check("ipv6_bridge_factory_dispose_closes_unclaimed_authenticated_opening_once",
        disposed and not disposeError and disposedAgain and not disposeAgainError
        and abandonedOpening.closeCount == 1 and abandonedOuter.closed
        and createAfterDispose == nil)

    local failedOuter = select(1, outerPair())
    local failedOpening = opening(failedOuter)
    local failedHub, failedSockets = loopbackHub(51000)
    local occupiedEndpoint = failedHub:bind(46011)
    occupiedEndpoint.port = 46011
    local failedFactory = assert(BridgeTransport.newFactory({
        role = "host",
        baseFactory = baseFactory(failedHub),
        socketModule = failedSockets,
        opening = failedOpening,
        provider = provider,
        masterKey = KEY,
        invitationId = INVITATION_ID,
        guestNonce = GUEST_NONCE,
        peerAddress = GUEST_ADDRESS,
        peerPort = 47002,
        loopbackHostPort = 46011,
    }))
    local failedHost = failedFactory.createHost({ channels = 3 })
    local failedDisposed = failedFactory.close()
    check("ipv6_bridge_factory_host_bind_failure_disposes_opening_and_secrets",
        failedHost == nil and failedDisposed and failedOpening.closeCount == 1
        and failedOuter.closed)

    local stickyOuter = select(1, outerPair())
    local stickyOpening = opening(stickyOuter)
    local stickyHub, stickySockets = loopbackHub(52000)
    local stickyFactory = assert(BridgeTransport.newFactory({
        role = "host",
        baseFactory = baseFactory(stickyHub),
        socketModule = stickySockets,
        opening = stickyOpening,
        provider = provider,
        masterKey = KEY,
        invitationId = INVITATION_ID,
        guestNonce = GUEST_NONCE,
        peerAddress = GUEST_ADDRESS,
        peerPort = 47002,
        loopbackHostPort = 46012,
    }))
    local stickyHost = assert(stickyFactory.createHost({ channels = 3 }))
    stickyHost.base.close = function() return false, "injected close failure" end
    local stickyClosed, stickyError = stickyHost:close()
    local stickyClosedAgain, stickyErrorAgain = stickyHost:close()
    check("ipv6_bridge_repeated_close_never_upgrades_unverified_cleanup",
        stickyClosed == false and stickyError ~= nil
        and stickyClosedAgain == false and stickyErrorAgain == stickyError
        and stickyOuter.closed)
end

return Test
