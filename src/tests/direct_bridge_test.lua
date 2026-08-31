local DirectBridge = require("src.net.direct_bridge")

local Test = {}

local KEY = string.rep("k", 32)
local INVITATION_ID = "0123456789abcdef"
local GUEST_NONCE = "fedcba9876543210"
local HOST_ADDRESS = "2606:4700:4700::1111"
local GUEST_ADDRESS = "2606:4700:4700::1001"
local HOST_PORT = 42001
local GUEST_PORT = 42002

local function digest(value)
    local hash = 2166136261
    for index = 1, #value do
        hash = (hash * 16777619 + value:byte(index)) % 4294967291
    end
    local word = string.format("%08x", hash)
    return word .. word
end

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

local function fakeProvider(log)
    local provider = {}

    local function newState(role, key, invitationId, guestNonce)
        local state = {
            role = role,
            material = key .. invitationId .. guestNonce,
            nextSequence = 0,
            received = {},
            closed = false,
        }

        function state:seal(plaintext, aad)
            if self.closed then return nil, "closed" end
            local sequence = self.nextSequence
            self.nextSequence = sequence + 1
            local sequenceBytes = string.rep("\0", 4) .. be32(sequence)
            local direction = self.role == "guest" and "g2h" or "h2g"
            local tag = digest(self.material .. direction .. aad
                .. sequenceBytes .. plaintext)
            return sequenceBytes .. tag .. plaintext
        end

        function state:open(ciphertext, aad)
            if self.closed then return nil, "closed" end
            if type(ciphertext) ~= "string" or #ciphertext < 24 then return false end
            if ciphertext:sub(1, 4) ~= string.rep("\0", 4) then return false end
            local sequence = read32(ciphertext, 5)
            if self.received[sequence] then return false end
            local sequenceBytes = ciphertext:sub(1, 8)
            local tag = ciphertext:sub(9, 24)
            local plaintext = ciphertext:sub(25)
            local direction = self.role == "host" and "g2h" or "h2g"
            local expected = digest(self.material .. direction .. aad
                .. sequenceBytes .. plaintext)
            if tag ~= expected then return false end
            self.received[sequence] = true
            return plaintext
        end

        function state:close()
            if not self.closed then
                self.closed = true
                log.closed = log.closed + 1
            end
            return true
        end

        return state
    end

    function provider.newBridgeHost(key, invitationId, guestNonce)
        log.created = log.created + 1
        return newState("host", key, invitationId, guestNonce)
    end

    function provider.newBridgeGuest(key, invitationId, guestNonce)
        log.created = log.created + 1
        return newState("guest", key, invitationId, guestNonce)
    end

    return provider
end

local function fakeSocket(address, port)
    local socket = {
        address = address,
        port = port,
        inbound = {},
        sent = {},
        closed = false,
        timeout = nil,
    }

    function socket:settimeout(timeout)
        self.timeout = timeout
        return 1
    end

    function socket:receivefrom()
        local item = table.remove(self.inbound, 1)
        if not item then return nil, "timeout" end
        return item.packet, item.address, item.port
    end

    function socket:sendto(packet, targetAddress, targetPort)
        if self.closed then return nil, "closed" end
        self.sent[#self.sent + 1] = {
            packet = packet,
            address = targetAddress,
            port = targetPort,
        }
        if self.route then
            self.route.inbound[#self.route.inbound + 1] = {
                packet = packet,
                address = self.address,
                port = self.port,
            }
        end
        return 1
    end

    function socket:getsockname()
        return self.address, self.port, "inet"
    end

    function socket:close()
        self.closed = true
        return 1
    end

    return socket
end

local function inject(socket, packet, address, port)
    socket.inbound[#socket.inbound + 1] = {
        packet = packet,
        address = address,
        port = port,
    }
end

local function newPair(clock, overrides)
    overrides = overrides or {}
    local hostOuter = fakeSocket(HOST_ADDRESS, HOST_PORT)
    local guestOuter = fakeSocket(GUEST_ADDRESS, GUEST_PORT)
    hostOuter.route = guestOuter
    guestOuter.route = hostOuter
    local hostInner = fakeSocket("127.0.0.1", 43001)
    local guestInner = fakeSocket("127.0.0.1", 43002)
    local log = { created = 0, closed = 0 }
    local provider = fakeProvider(log)
    local common = {
        provider = provider,
        masterKey = KEY,
        invitationId = INVITATION_ID,
        guestNonce = GUEST_NONCE,
        clock = clock,
    }
    local hostOptions = {}
    local guestOptions = {}
    for key, value in pairs(common) do
        hostOptions[key], guestOptions[key] = value, value
    end
    for key, value in pairs(overrides) do
        hostOptions[key], guestOptions[key] = value, value
    end
    hostOptions.role = "host"
    hostOptions.outerSocket = hostOuter
    hostOptions.innerSocket = hostInner
    hostOptions.peerAddress = GUEST_ADDRESS
    hostOptions.peerPort = GUEST_PORT
    hostOptions.localTargetPort = 22122
    guestOptions.role = "guest"
    guestOptions.outerSocket = guestOuter
    guestOptions.innerSocket = guestInner
    guestOptions.peerAddress = HOST_ADDRESS
    guestOptions.peerPort = HOST_PORT
    local host = assert(DirectBridge.create(hostOptions))
    local guest = assert(DirectBridge.create(guestOptions))
    return {
        host = host,
        guest = guest,
        hostOuter = hostOuter,
        guestOuter = guestOuter,
        hostInner = hostInner,
        guestInner = guestInner,
        log = log,
    }
end

local function last(items)
    return items[#items]
end

function Test.run(_, check)
    local header = DirectBridge.encodeHeader(
        2, INVITATION_ID, 7, 1, 2, 1400)
    local parsed = header and DirectBridge.parseHeader(
        header .. string.rep("w", 224 + DirectBridge.CRYPTO_OVERHEAD_BYTES))
    check("direct_bridge_header_is_fixed_bounded_and_big_endian",
        header and #header == 32
        and parsed and parsed.roleByte == 2 and parsed.datagramId == 7
        and parsed.fragmentIndex == 1 and parsed.fragmentCount == 2
        and parsed.totalLength == 1400 and parsed.fragmentBytes == 224)
    check("direct_bridge_header_rejects_impossible_fragment_layouts",
        DirectBridge.encodeHeader(2, INVITATION_ID, 1, 1, 1, 20) == nil
        and DirectBridge.encodeHeader(2, INVITATION_ID, 0, 0, 1, 20) == nil
        and DirectBridge.parseHeader("TPSB") == nil)

    local now = 10
    local pair = newPair(function() return now end)
    local guestAddress, guestRelayPort = pair.guest:localEndpoint()
    local maximumDatagram = string.rep("A", DirectBridge.MAX_FRAGMENT_BYTES)
        .. string.rep("B", DirectBridge.MAX_INNER_BYTES
            - DirectBridge.MAX_FRAGMENT_BYTES)
    inject(pair.guestInner, maximumDatagram, "127.0.0.1", 51001)
    pair.guest:update()
    local firstOuter = table.remove(pair.hostOuter.inbound, 1)
    local secondOuter = table.remove(pair.hostOuter.inbound, 1)
    check("direct_bridge_fragments_1400_byte_enet_datagram_under_ipv6_budget",
        pair.guest.sentDatagrams == 1 and pair.guest.sentFragments == 2
        and firstOuter and #firstOuter.packet == DirectBridge.MAX_OUTER_BYTES
        and secondOuter and #secondOuter.packet == 280
        and guestAddress == "127.0.0.1" and guestRelayPort == 43002)

    pair.hostOuter.inbound[#pair.hostOuter.inbound + 1] = secondOuter
    pair.hostOuter.inbound[#pair.hostOuter.inbound + 1] = firstOuter
    pair.host:update()
    local hostDelivery = last(pair.hostInner.sent)
    check("direct_bridge_reassembles_authenticated_fragments_after_reordering",
        hostDelivery and hostDelivery.packet == maximumDatagram
        and hostDelivery.address == "127.0.0.1" and hostDelivery.port == 22122
        and pair.host.receivedFragments == 2
        and pair.host.receivedDatagrams == 1)

    pair.hostOuter.inbound[#pair.hostOuter.inbound + 1] = firstOuter
    pair.hostOuter.inbound[#pair.hostOuter.inbound + 1] = secondOuter
    pair.host:update()
    check("direct_bridge_rejects_outer_fragment_replay_without_duplicate_delivery",
        #pair.hostInner.sent == 1 and pair.host.rejectedFragments == 2
        and pair.host.status == "running")

    local reply = "host-to-guest-enet"
    inject(pair.hostInner, reply, "127.0.0.1", 22122)
    pair.host:update()
    pair.guest:update()
    local guestDelivery = last(pair.guestInner.sent)
    check("direct_bridge_learns_only_the_guest_loopback_peer_and_carries_reverse_traffic",
        guestDelivery and guestDelivery.packet == reply
        and guestDelivery.address == "127.0.0.1" and guestDelivery.port == 51001
        and pair.guest.receivedDatagrams == 1)

    inject(pair.guestInner, "tamper-source", "127.0.0.1", 51001)
    pair.guest:update()
    local tamperedOuter = table.remove(pair.hostOuter.inbound, 1)
    tamperedOuter.packet = tamperedOuter.packet:sub(1, -2)
        .. string.char((tamperedOuter.packet:byte(-1) + 1) % 256)
    local deliveriesBeforeTamper = #pair.hostInner.sent
    inject(pair.hostOuter, tamperedOuter.packet, GUEST_ADDRESS, GUEST_PORT)
    inject(pair.hostOuter, tamperedOuter.packet, HOST_ADDRESS, GUEST_PORT)
    inject(pair.hostOuter, "malformed", GUEST_ADDRESS, GUEST_PORT)
    pair.host:update()
    check("direct_bridge_ignores_tampered_wrong_source_and_malformed_outer_packets",
        #pair.hostInner.sent == deliveriesBeforeTamper
        and pair.host.rejectedFragments == 3
        and pair.host.status == "running")

    inject(pair.guestInner, string.rep("L", 1400), "127.0.0.1", 51001)
    pair.guest:update()
    local lostFirst = table.remove(pair.hostOuter.inbound, 1)
    local lostSecond = table.remove(pair.hostOuter.inbound, 1)
    inject(pair.hostOuter, lostFirst.packet, GUEST_ADDRESS, GUEST_PORT)
    pair.host:update()
    now = now + 2.1
    pair.host:update()
    check("direct_bridge_expires_incomplete_loss_without_delivering_partial_datagrams",
        lostSecond ~= nil and pair.host._pendingCount == 0
        and pair.host.droppedDatagrams == 1
        and #pair.hostInner.sent == deliveriesBeforeTamper)

    local hostClosed = pair.host:close()
    local guestClosed = pair.guest:close()
    check("direct_bridge_close_zeroizes_state_and_closes_both_socket_layers_once",
        hostClosed and guestClosed and pair.host:close() and pair.guest:close()
        and pair.log.created == 2 and pair.log.closed == 2
        and pair.hostOuter.closed and pair.guestOuter.closed
        and pair.hostInner.closed and pair.guestInner.closed)

    local rollbackNow = 20
    local rollbackPair = newPair(function() return rollbackNow end)
    rollbackPair.host:update()
    rollbackNow = 19
    local rollbackStatus, rollbackError = rollbackPair.host:update()
    check("direct_bridge_nonmonotonic_clock_fails_closed_and_cleans_up",
        rollbackStatus == "failed"
        and rollbackError == "Direct bridge clock failed."
        and rollbackPair.hostOuter.closed and rollbackPair.hostInner.closed)
    rollbackPair.guest:close()
end

return Test
