local DirectTransport = require("src.net.transport_direct")

local Test = {}

local SHARED_KEY = string.rep("k", DirectTransport.KEY_BYTES)

local function directFrame(frameType, body)
    return DirectTransport.MAGIC
        .. string.char(DirectTransport.VERSION, frameType)
        .. body
end

local function digest(value)
    local hash = 7
    for index = 1, #value do
        -- Keep every intermediate below Lua 5.1's exact-integer range.
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

local function fakeCryptoProvider(log)
    local provider = { productionReady = true }
    local nextStateId = 0

    function provider.admissionToken(key)
        log.calls[#log.calls + 1] = { kind = "admissionToken" }
        return fakeAdmissionToken(key)
    end

    local function newState(role, key)
        nextStateId = nextStateId + 1
        local state = {
            id = nextStateId,
            role = role,
            key = key,
            ready = false,
            sendCounter = 0,
            closed = false,
            phase = role == "initiator" and "new" or "wait-client",
        }
        log.states[#log.states + 1] = state

        function state:start()
            log.calls[#log.calls + 1] = { kind = "start", state = self.id, role = self.role }
            if self.role == "initiator" then
                self.phase = "wait-server"
                return "client:" .. digest(self.key .. ":client")
            end
            return nil
        end

        function state:handshake(message)
            log.calls[#log.calls + 1] = {
                kind = "handshake", state = self.id, role = self.role, message = message,
            }
            if self.role == "responder" then
                if self.phase == "wait-client"
                    and message == "client:" .. digest(self.key .. ":client")
                then
                    self.phase = "wait-finish"
                    return "server:" .. digest(self.key .. ":server")
                end
                if self.phase == "wait-finish"
                    and message == "finish:" .. digest(self.key .. ":finish")
                then
                    self.phase = "ready"
                    self.ready = true
                    return "ack:" .. digest(self.key .. ":ack")
                end
                if self.phase == "wait-client" then
                    return nil, "client authentication failed"
                end
                return nil, "client finish failed"
            end
            if self.phase == "wait-server"
                and message == "server:" .. digest(self.key .. ":server")
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
            if self.phase == "wait-server" then
                return nil, "server authentication failed"
            end
            return nil, "server acknowledgement failed"
        end

        function state:isReady()
            return self.ready
        end

        function state:seal(plaintext, aad)
            self.sendCounter = self.sendCounter + 1
            local counter = tostring(self.sendCounter)
            local encoded = hexEncode(plaintext)
            local tag = digest(self.key .. "|" .. aad .. "|" .. counter .. "|" .. encoded)
            log.calls[#log.calls + 1] = {
                kind = "seal", state = self.id, aad = aad,
                plaintext = plaintext, counter = self.sendCounter,
            }
            return counter .. ":" .. tag .. ":" .. encoded
        end

        function state:open(ciphertext, aad)
            log.calls[#log.calls + 1] = {
                kind = "open", state = self.id, ready = self.ready,
                aad = aad, ciphertext = ciphertext,
            }
            local counter, tag, encoded = ciphertext:match("^(%d+):([0-9a-f]+):([0-9a-f]*)$")
            if not counter then return nil, "malformed ciphertext" end
            local expected = digest(self.key .. "|" .. aad .. "|" .. counter .. "|" .. encoded)
            if tag ~= expected then return nil, "authentication tag mismatch" end
            local plaintext = hexDecode(encoded)
            if plaintext == nil then return nil, "malformed plaintext encoding" end
            return plaintext
        end

        function state:close()
            if not self.closed then
                self.closed = true
                log.calls[#log.calls + 1] = {
                    kind = "close", state = self.id, role = self.role,
                }
            end
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

local function stallingCryptoProvider(log)
    local provider = { productionReady = true }
    function provider.admissionToken(key) return fakeAdmissionToken(key) end
    local function newState(role)
        local state = { role = role, closed = false }
        function state:start()
            return role == "initiator" and "client-stall" or nil
        end
        function state:handshake(message)
            log.handshakes = log.handshakes + 1
            log.bytes = log.bytes + #message
            return nil
        end
        function state:isReady() return false end
        function state:seal() return nil, "not ready" end
        function state:open() return nil, "not ready" end
        function state:close()
            self.closed = true
            return true
        end
        return state
    end
    function provider.newInitiator() return newState("initiator") end
    function provider.newResponder() return newState("responder") end
    return provider
end

local function fakeNetwork()
    local network = {
        sends = {},
        disconnects = {},
        closes = {},
        broadcastCalls = 0,
        clients = {},
        nextPeerId = 0,
        factory = {
            DEFAULT_PORT = 22122,
            DEFAULT_CHANNELS = 3,
            MIN_CHANNELS = 3,
            MAX_GUESTS = 3,
        },
    }

    local function transport(mode, peer, channels)
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
            if not destination or destination.closed then return false, "peer is unavailable" end
            network.sends[#network.sends + 1] = {
                sender = self.mode,
                peer = targetPeer,
                payload = payload,
                channel = channel,
                reliable = reliable == true,
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

        function base:broadcast(payload, channel, reliable)
            network.broadcastCalls = network.broadcastCalls + 1
            for targetPeer in pairs(network.clients) do
                self:send(targetPeer, payload, channel, reliable)
            end
            return true
        end

        function base:disconnect(targetPeer, code, immediate)
            network.disconnects[#network.disconnects + 1] = {
                sender = self.mode,
                peer = targetPeer,
                code = code,
                immediate = immediate == true,
            }
            local destination
            if self.mode == "host" then
                destination = network.clients[targetPeer]
            else
                destination = network.host
            end
            if destination and not destination.closed then
                destination.inbound[#destination.inbound + 1] = {
                    type = "disconnect", peer = targetPeer, data = code, code = code,
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
                mode = self.mode, peer = self.peer, code = code,
                immediate = immediate == true,
            }
            return true
        end

        return base
    end

    function network.factory.createHost(options)
        network.hostOptions = options
        network.host = transport("host", nil, options and options.channels)
        network.host.endpoint = "*:22122"
        network.host.maxGuests = 3
        network.host.peerCapacity = options and options.peerCapacity or 3
        return network.host
    end

    function network.factory.createClient(_, options)
        if not network.host then return nil, "host has not started" end
        network.lastClientOptions = options
        network.nextPeerId = network.nextPeerId + 1
        local peer = { id = "peer-" .. tostring(network.nextPeerId) }
        local client = transport("client", peer, options and options.channels)
        network.clients[peer] = client
        network.host.inbound[#network.host.inbound + 1] = {
            type = "connect", peer = peer, connectionId = network.nextPeerId,
            data = options and options.connectData,
            code = options and options.connectData,
        }
        client.inbound[#client.inbound + 1] = {
            type = "connect", peer = peer, connectionId = network.nextPeerId,
            data = options and options.connectData,
            code = options and options.connectData,
        }
        return client
    end

    function network:injectHost(peer, payload, channel, reliable)
        self.host.inbound[#self.host.inbound + 1] = {
            type = "receive", peer = peer, data = payload, payload = payload,
            channel = channel, reliable = reliable,
        }
    end

    function network:injectHostDisconnect(peer, code)
        self.host.inbound[#self.host.inbound + 1] = {
            type = "disconnect", peer = peer, data = code, code = code,
        }
    end

    return network
end

local function injectHostConnect(network, peer, token)
    network.host.inbound[#network.host.inbound + 1] = {
        type = "connect",
        peer = peer,
        data = token,
        code = token,
    }
end

local function tableCount(values)
    local count = 0
    for _ in pairs(values or {}) do count = count + 1 end
    return count
end

local function countCalls(log, kind, stateIds)
    local count = 0
    for _, call in ipairs(log.calls) do
        if call.kind == kind and (not stateIds or stateIds[call.state]) then
            count = count + 1
        end
    end
    return count
end

local function lastCall(log, kind)
    for index = #log.calls, 1, -1 do
        if log.calls[index].kind == kind then return log.calls[index] end
    end
end

local function newSecureFactory(network, key, clock, timeout, limits)
    local cryptoLog = { states = {}, calls = {} }
    local options = {
        baseFactory = network.factory,
        cryptoProvider = fakeCryptoProvider(cryptoLog),
        key = key or SHARED_KEY,
        clock = clock or function() return 0 end,
        handshakeTimeout = timeout or 5,
    }
    for name, value in pairs(limits or {}) do options[name] = value end
    local factory, errorMessage = DirectTransport.newFactory(options)
    return factory, cryptoLog, errorMessage
end

local function containsEvent(events, eventType, payload)
    for _, event in ipairs(events or {}) do
        if event.type == eventType and (payload == nil or event.payload == payload) then
            return event
        end
    end
end

local function eventIndex(events, eventType, payload)
    for index, event in ipairs(events or {}) do
        if event.type == eventType and (payload == nil or event.payload == payload) then
            return index
        end
    end
end

local function connectClient(host, factory, network)
    local client = factory.createClient("direct.example:22122", { channels = 3 })
    local peer = network.clients[client.base.peer] and client.base.peer or nil

    -- The physical connect event is deliberately consumed before the initiator runs.
    local hostBefore = host:service(8)
    local clientBefore = client:service(8)
    host:service(8)
    client:service(8)
    local hostReady = host:service(8)
    local clientReady = client:service(8)
    return client, peer, hostBefore, clientBefore, hostReady, clientReady
end

local function establishSingle(key, clientKey)
    local network = fakeNetwork()
    local hostFactory, hostCrypto = newSecureFactory(network, key or SHARED_KEY)
    local clientFactory, clientCrypto = newSecureFactory(
        network, clientKey or key or SHARED_KEY)
    local host = hostFactory.createHost({ channels = 3 })
    local client, peer, hostBefore, clientBefore, hostReady, clientReady =
        connectClient(host, clientFactory, network)
    return {
        network = network,
        hostFactory = hostFactory,
        clientFactory = clientFactory,
        hostCrypto = hostCrypto,
        clientCrypto = clientCrypto,
        host = host,
        client = client,
        peer = peer,
        hostBefore = hostBefore,
        clientBefore = clientBefore,
        hostReady = hostReady,
        clientReady = clientReady,
    }
end

local function prepareClientHoldingArea(limits, clock, timeout, payloads)
    local network = fakeNetwork()
    local hostFactory, hostCrypto = newSecureFactory(
        network, SHARED_KEY, clock, timeout)
    local clientFactory, clientCrypto = newSecureFactory(
        network, SHARED_KEY, clock, timeout, limits)
    local host = hostFactory.createHost({ channels = 3 })
    local client = clientFactory.createClient(
        "direct.example:22122", { channels = 3 })
    local peer = client.base.peer

    host:service(8)
    client:service(8)
    host:service(8)
    client:service(8)
    local hostReady = host:service(8)

    -- Hold back the responder's final acknowledgement so authenticated host data
    -- can exercise the initiator-only, bounded pre-ready holding area.
    local finalAcknowledgement = table.remove(client.base.inbound, 1)
    local allSent = true
    for _, payload in ipairs(payloads or {}) do
        if not host:send(peer, payload, 2, true) then allSent = false end
    end

    return {
        network = network,
        host = host,
        client = client,
        peer = peer,
        hostCrypto = hostCrypto,
        clientCrypto = clientCrypto,
        hostReady = hostReady,
        finalAcknowledgement = finalAcknowledgement,
        allSent = allSent,
    }
end

local function checkClientHoldingAreaFailureModes(check)
    local heldTamper = prepareClientHoldingArea(nil, nil, nil, { "held-tamper" })
    local heldTamperRaw = heldTamper.client.base.inbound[1]
    local heldTamperLast = heldTamperRaw.data:sub(-1)
    heldTamperRaw.data = heldTamperRaw.data:sub(1, -2)
        .. (heldTamperLast == "0" and "1" or "0")
    heldTamperRaw.payload = heldTamperRaw.data
    heldTamper.client.base.inbound[#heldTamper.client.base.inbound + 1] =
        heldTamper.finalAcknowledgement
    local heldTamperEvents = heldTamper.client:service(8)
    local heldTamperDisconnect = containsEvent(heldTamperEvents, "disconnect")
    check("direct_transport_classifies_tampered_held_ciphertext_as_authentication_failure",
        heldTamper.allSent
        and containsEvent(heldTamper.hostReady, "connect") ~= nil
        and heldTamperDisconnect
        and heldTamperDisconnect.code == DirectTransport.DISCONNECT_AUTHENTICATION
        and not containsEvent(heldTamperEvents, "connect")
        and not containsEvent(heldTamperEvents, "receive")
        and heldTamper.client._peerStates[heldTamper.peer] == nil
        and countCalls(heldTamper.clientCrypto, "open") == 1
        and countCalls(heldTamper.clientCrypto, "close") == 1
        and heldTamper.network.disconnects[#heldTamper.network.disconnects].code
            == DirectTransport.DISCONNECT_AUTHENTICATION)
    heldTamper.client:close()
    heldTamper.host:close()

    local heldFrameOverflow = prepareClientHoldingArea({
        maxPreReadyDataFrames = 1,
    }, nil, nil, { "held-frame-one", "held-frame-two" })
    local heldFrameOverflowEvents = heldFrameOverflow.client:service(8)
    local heldFrameOverflowDisconnect = containsEvent(
        heldFrameOverflowEvents, "disconnect")
    check("direct_transport_caps_pre_ready_ciphertext_frame_count",
        heldFrameOverflow.allSent
        and heldFrameOverflowDisconnect
        and heldFrameOverflowDisconnect.code
            == DirectTransport.DISCONNECT_AUTHENTICATION
        and heldFrameOverflow.client._peerStates[heldFrameOverflow.peer] == nil
        and countCalls(heldFrameOverflow.clientCrypto, "open") == 0
        and countCalls(heldFrameOverflow.clientCrypto, "close") == 1
        and heldFrameOverflow.network.disconnects[
            #heldFrameOverflow.network.disconnects].code
            == DirectTransport.DISCONNECT_AUTHENTICATION)
    heldFrameOverflow.client:close()
    heldFrameOverflow.host:close()

    local heldByteOverflow = prepareClientHoldingArea({
        maxPreReadyDataFrames = 4,
        maxPreReadyDataBytes = 16,
    }, nil, nil, { "a", "b" })
    local firstHeldBodyBytes = #heldByteOverflow.client.base.inbound[1].data
        - DirectTransport.HEADER_BYTES
    local heldByteOverflowEvents = heldByteOverflow.client:service(8)
    local heldByteOverflowDisconnect = containsEvent(
        heldByteOverflowEvents, "disconnect")
    check("direct_transport_caps_aggregate_pre_ready_ciphertext_bytes",
        heldByteOverflow.allSent and firstHeldBodyBytes <= 16
        and heldByteOverflowDisconnect
        and heldByteOverflowDisconnect.code
            == DirectTransport.DISCONNECT_AUTHENTICATION
        and heldByteOverflow.client._peerStates[heldByteOverflow.peer] == nil
        and countCalls(heldByteOverflow.clientCrypto, "open") == 0
        and countCalls(heldByteOverflow.clientCrypto, "close") == 1)
    heldByteOverflow.client:close()
    heldByteOverflow.host:close()

    local responderEarlyNetwork = fakeNetwork()
    local responderEarlyHostFactory, responderEarlyHostCrypto =
        newSecureFactory(responderEarlyNetwork)
    local responderEarlyClientFactory = newSecureFactory(responderEarlyNetwork)
    local responderEarlyHost = responderEarlyHostFactory.createHost({ channels = 3 })
    local responderEarlyClient = responderEarlyClientFactory.createClient(
        "direct.example:22122", { channels = 3 })
    local responderEarlyPeer = responderEarlyClient.base.peer
    responderEarlyHost:service(8)
    responderEarlyNetwork:injectHost(responderEarlyPeer,
        directFrame(DirectTransport.TYPE_DATA, "early-ciphertext"), 2, true)
    responderEarlyHost:service(8)
    local responderEarlyDisconnect = responderEarlyNetwork.disconnects[
        #responderEarlyNetwork.disconnects]
    check("direct_transport_responder_rejects_data_before_mutual_authentication",
        responderEarlyDisconnect
        and responderEarlyDisconnect.code
            == DirectTransport.DISCONNECT_AUTHENTICATION
        and responderEarlyHost._peerStates[responderEarlyPeer] == nil
        and countCalls(responderEarlyHostCrypto, "open") == 0
        and countCalls(responderEarlyHostCrypto, "close") == 1)
    responderEarlyClient:close()
    responderEarlyHost:close()

    local heldNow = 0
    local heldTimeout = prepareClientHoldingArea(nil,
        function() return heldNow end, 3, { "held-until-timeout" })
    local heldBeforeTimeout = heldTimeout.client:service(8)
    local heldTimeoutEntry = heldTimeout.client._peerStates[heldTimeout.peer]
    local heldBytesBeforeTimeout = heldTimeoutEntry
        and heldTimeoutEntry.pendingDataBytes or 0
    heldNow = 3.1
    local heldTimeoutEvents = heldTimeout.client:service(8)
    local heldTimeoutDisconnect = containsEvent(heldTimeoutEvents, "disconnect")
    check("direct_transport_timeout_discards_held_ciphertext_and_closes_state",
        heldTimeout.allSent and #heldBeforeTimeout == 0
        and heldBytesBeforeTimeout > 0
        and heldTimeoutDisconnect
        and heldTimeoutDisconnect.code
            == DirectTransport.DISCONNECT_HANDSHAKE_TIMEOUT
        and heldTimeout.client._peerStates[heldTimeout.peer] == nil
        and countCalls(heldTimeout.clientCrypto, "open") == 0
        and countCalls(heldTimeout.clientCrypto, "close") == 1)
    heldTimeout.client:close()
    heldTimeout.host:close()

    local heldDisconnect = prepareClientHoldingArea(
        nil, nil, nil, { "held-until-disconnect" })
    local heldBeforeDisconnect = heldDisconnect.client:service(8)
    local heldDisconnectEntry = heldDisconnect.client._peerStates[heldDisconnect.peer]
    local heldBytesBeforeDisconnect = heldDisconnectEntry
        and heldDisconnectEntry.pendingDataBytes or 0
    heldDisconnect.client.base.inbound[#heldDisconnect.client.base.inbound + 1] = {
        type = "disconnect", peer = heldDisconnect.peer, data = 77, code = 77,
    }
    local heldDisconnectEvents = heldDisconnect.client:service(8)
    local heldDisconnectEvent = containsEvent(heldDisconnectEvents, "disconnect")
    check("direct_transport_disconnect_discards_held_ciphertext_and_closes_state",
        heldDisconnect.allSent and #heldBeforeDisconnect == 0
        and heldBytesBeforeDisconnect > 0
        and heldDisconnectEvent and heldDisconnectEvent.code == 77
        and heldDisconnect.client._peerStates[heldDisconnect.peer] == nil
        and countCalls(heldDisconnect.clientCrypto, "open") == 0
        and countCalls(heldDisconnect.clientCrypto, "close") == 1)
    heldDisconnect.client:close()
    heldDisconnect.host:close()
end

function Test.run(_, check)
    local Context = {
        _ = _,
        check = check,
        DirectTransport = DirectTransport,
        SHARED_KEY = SHARED_KEY,
        directFrame = directFrame,
        fakeAdmissionToken = fakeAdmissionToken,
        hexEncode = hexEncode,
        fakeCryptoProvider = fakeCryptoProvider,
        stallingCryptoProvider = stallingCryptoProvider,
        fakeNetwork = fakeNetwork,
        injectHostConnect = injectHostConnect,
        tableCount = tableCount,
        countCalls = countCalls,
        lastCall = lastCall,
        newSecureFactory = newSecureFactory,
        containsEvent = containsEvent,
        eventIndex = eventIndex,
        connectClient = connectClient,
        establishSingle = establishSingle,
        checkClientHoldingAreaFailureModes = checkClientHoldingAreaFailureModes,
    }
    require("src.tests.direct_transport_cases.base_factory_1").run(Context)
    require("src.tests.direct_transport_cases.checks_2").run(Context)
    require("src.tests.direct_transport_cases.checks_3").run(Context)
    require("src.tests.direct_transport_cases.pre_auth_peer_4").run(Context)

end

return Test
