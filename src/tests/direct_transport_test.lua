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
    local baseFactory = {
        createHost = function() return {} end,
        createClient = function() return {} end,
    }
    local providerLog = { states = {}, calls = {} }
    local validProvider = fakeCryptoProvider(providerLog)
    local noProvider, noProviderError = DirectTransport.newFactory({
        baseFactory = baseFactory, key = SHARED_KEY,
    })
    local noKey, noKeyError = DirectTransport.newFactory({
        baseFactory = baseFactory, cryptoProvider = validProvider,
    })
    local shortKey = DirectTransport.newFactory({
        baseFactory = baseFactory, cryptoProvider = validProvider, key = "too-short",
    })
    local longKey = DirectTransport.newFactory({
        baseFactory = baseFactory, cryptoProvider = validProvider,
        key = string.rep("x", DirectTransport.KEY_BYTES + 1),
    })
    local selfDeclaredTestProvider = fakeCryptoProvider({ states = {}, calls = {} })
    selfDeclaredTestProvider.productionReady = nil
    local nonProductionProvider = DirectTransport.newFactory({
        baseFactory = baseFactory, cryptoProvider = selfDeclaredTestProvider, key = SHARED_KEY,
    })
    local lowLevelOnly = DirectTransport.newFactory({
        baseFactory = baseFactory, cryptoProvider = { seal = function() end },
        key = SHARED_KEY,
    })
    local missingAdmissionProvider = fakeCryptoProvider({ states = {}, calls = {} })
    missingAdmissionProvider.admissionToken = nil
    local missingAdmissionToken = DirectTransport.newFactory({
        baseFactory = baseFactory, cryptoProvider = missingAdmissionProvider,
        key = SHARED_KEY,
    })
    check("direct_transport_fails_closed_without_high_level_crypto_and_key",
        noProvider == nil and type(noProviderError) == "string"
        and noKey == nil and type(noKeyError) == "string"
        and shortKey == nil and longKey == nil
        and nonProductionProvider == nil and lowLevelOnly == nil
        and missingAdmissionToken == nil)

    local tokenKey
    local maximumTokenProvider = fakeCryptoProvider({ states = {}, calls = {} })
    function maximumTokenProvider.admissionToken(key)
        tokenKey = key
        return 2147483647
    end
    local maximumTokenFactory = DirectTransport.newFactory({
        baseFactory = baseFactory, cryptoProvider = maximumTokenProvider,
        key = SHARED_KEY,
    })
    local zeroTokenProvider = fakeCryptoProvider({ states = {}, calls = {} })
    function zeroTokenProvider.admissionToken() return 0 end
    local zeroTokenFactory = DirectTransport.newFactory({
        baseFactory = baseFactory, cryptoProvider = zeroTokenProvider,
        key = SHARED_KEY,
    })
    check("direct_transport_uses_provider_owned_admission_token_with_inclusive_bounds",
        maximumTokenFactory ~= nil and zeroTokenFactory ~= nil and tokenKey == SHARED_KEY)

    local invalidTokenAccepted = false
    for _, invalidToken in ipairs({ -1, 0.5, 2147483648, "17", 0 / 0 }) do
        local invalidProvider = fakeCryptoProvider({ states = {}, calls = {} })
        function invalidProvider.admissionToken() return invalidToken end
        local invalidFactory = DirectTransport.newFactory({
            baseFactory = baseFactory, cryptoProvider = invalidProvider,
            key = SHARED_KEY,
        })
        if invalidFactory ~= nil then invalidTokenAccepted = true end
    end
    local tokenSecretError = "token-provider-error-" .. hexEncode(SHARED_KEY)
    local throwingTokenProvider = fakeCryptoProvider({ states = {}, calls = {} })
    function throwingTokenProvider.admissionToken() error(tokenSecretError) end
    local throwingTokenFactory, throwingTokenError = DirectTransport.newFactory({
        baseFactory = baseFactory, cryptoProvider = throwingTokenProvider,
        key = SHARED_KEY,
    })
    check("direct_transport_rejects_invalid_or_failing_provider_admission_tokens",
        not invalidTokenAccepted and throwingTokenFactory == nil
        and type(throwingTokenError) == "string"
        and throwingTokenError:find(tokenSecretError, 1, true) == nil
        and throwingTokenError:find(hexEncode(SHARED_KEY), 1, true) == nil)
    check("direct_transport_rejects_invalid_admission_rate_and_ready_caps",
        DirectTransport.newFactory({
            baseFactory = baseFactory, cryptoProvider = validProvider,
            key = SHARED_KEY, admissionBurst = 0,
        }) == nil
        and DirectTransport.newFactory({
            baseFactory = baseFactory, cryptoProvider = validProvider,
            key = SHARED_KEY, admissionRefillSeconds = 0,
        }) == nil
        and DirectTransport.newFactory({
            baseFactory = baseFactory, cryptoProvider = validProvider,
            key = SHARED_KEY, maxReadyPeers = 4,
        }) == nil)

    local session = establishSingle()
    check("direct_transport_suppresses_physical_connect_until_mutual_authentication",
        session.hostBefore and #session.hostBefore == 0
        and session.clientBefore and #session.clientBefore == 0
        and containsEvent(session.hostReady, "connect") ~= nil
        and containsEvent(session.clientReady, "connect") ~= nil
        and session.client.peer == session.peer)
    check("direct_transport_uses_invitation_prefilter_and_reserved_peer_capacity",
        session.network.hostOptions.peerCapacity == DirectTransport.DEFAULT_PEER_CAPACITY
        and session.host.peerCapacity == DirectTransport.DEFAULT_PEER_CAPACITY
        and session.host.maxPendingPeers == DirectTransport.DEFAULT_MAX_PENDING_PEERS
        and session.host.admissionBurst == DirectTransport.DEFAULT_ADMISSION_BURST
        and session.host.admissionRefillSeconds
            == DirectTransport.DEFAULT_ADMISSION_REFILL_SECONDS
        and session.host.maxReadyPeers == DirectTransport.DEFAULT_MAX_READY_PEERS
        and session.network.lastClientOptions.connectData
            == fakeAdmissionToken(SHARED_KEY))

    local firstHandshake = session.network.sends[1]
    local secondHandshake = session.network.sends[2]
    local thirdHandshake = session.network.sends[3]
    local fourthHandshake = session.network.sends[4]
    check("direct_transport_handshake_is_strictly_framed_on_reliable_channel_zero",
        firstHandshake and secondHandshake and thirdHandshake and fourthHandshake
        and firstHandshake.channel == 0 and firstHandshake.reliable
        and secondHandshake.channel == 0 and secondHandshake.reliable
        and thirdHandshake.channel == 0 and thirdHandshake.reliable
        and fourthHandshake.channel == 0 and fourthHandshake.reliable
        and firstHandshake.payload:sub(1, 4) == DirectTransport.MAGIC
        and firstHandshake.payload:byte(5) == DirectTransport.VERSION
        and firstHandshake.payload:byte(6) == DirectTransport.TYPE_HANDSHAKE)

    local reorderedNetwork = fakeNetwork()
    local reorderedHostFactory = newSecureFactory(reorderedNetwork)
    local reorderedClientFactory, reorderedClientCrypto =
        newSecureFactory(reorderedNetwork)
    local reorderedHost = reorderedHostFactory.createHost({ channels = 3 })
    local reorderedClient = reorderedClientFactory.createClient(
        "direct.example:22122", { channels = 3 })
    local reorderedPeer = reorderedClient.base.peer
    reorderedHost:service(8)
    reorderedClient:service(8)
    reorderedHost:service(8)
    reorderedClient:service(8)
    local reorderedHostEvents = reorderedHost:service(8)
    local earlySent = reorderedHost:send(reorderedPeer, "early-host-data", 2, true)
    local inbound = reorderedClient.base.inbound
    inbound[#inbound - 1], inbound[#inbound] = inbound[#inbound], inbound[#inbound - 1]
    local reorderedClientEvents = reorderedClient:service(8)
    local reorderedOpen = lastCall(reorderedClientCrypto, "open")
    local reorderedConnectIndex = eventIndex(reorderedClientEvents, "connect")
    local reorderedReceiveIndex = eventIndex(
        reorderedClientEvents, "receive", "early-host-data")
    check("direct_transport_bounds_and_releases_data_that_overtakes_final_ack",
        containsEvent(reorderedHostEvents, "connect") ~= nil
        and earlySent
        and containsEvent(reorderedClientEvents, "connect") ~= nil
        and containsEvent(reorderedClientEvents, "receive", "early-host-data") ~= nil
        and reorderedConnectIndex and reorderedReceiveIndex
        and reorderedConnectIndex < reorderedReceiveIndex
        and not containsEvent(reorderedClientEvents, "disconnect")
        and reorderedOpen and reorderedOpen.ready == true
        and #reorderedClient._peerStates[reorderedPeer].pendingData == 0)
    reorderedClient:close()
    reorderedHost:close()
    checkClientHoldingAreaFailureModes(check)

    local sentMotion, motionError = session.client:sendToServer("motion", 2, false)
    local motionWire = session.network.sends[#session.network.sends]
    local motionEvents = session.host:service(8)
    local motionReceive = containsEvent(motionEvents, "receive", "motion")
    local expectedStateAad = DirectTransport.aadForChannel(2)
    local lastSeal = lastCall(session.clientCrypto, "seal")
    local lastOpen = lastCall(session.hostCrypto, "open")
    check("direct_transport_encrypts_data_and_preserves_channel_and_delivery",
        sentMotion and motionError == nil and motionReceive
        and motionReceive.channel == 2
        and motionWire.channel == 2 and not motionWire.reliable
        and motionWire.payload ~= "motion"
        and motionWire.payload:byte(6) == DirectTransport.TYPE_DATA
        and lastSeal and lastSeal.aad == expectedStateAad
        and lastOpen and lastOpen.aad == expectedStateAad)

    local sentDurable = session.host:send(session.peer, "durable",
        { channel = 2, reliable = true })
    local durableWire = session.network.sends[#session.network.sends]
    local durableEvents = session.client:service(8)
    check("direct_transport_preserves_reliable_application_delivery_on_durable_channel_two",
        DirectTransport.DURABLE_CHANNEL == 2
        and sentDurable and durableWire.channel == 2 and durableWire.reliable
        and containsEvent(durableEvents, "receive", "durable") ~= nil)

    session.network:injectHostDisconnect(session.peer, 9)
    local disconnectEvents = session.host:service(8)
    check("direct_transport_emits_disconnect_only_for_an_authenticated_peer",
        containsEvent(disconnectEvents, "disconnect") ~= nil
        and containsEvent(disconnectEvents, "disconnect").code == 9
        and session.host._peerStates[session.peer] == nil)
    session.client:close()
    session.host:close()

    local wrongKey = establishSingle(SHARED_KEY, string.rep("w", DirectTransport.KEY_BYTES))
    check("direct_transport_rejects_a_peer_with_the_wrong_shared_key",
        wrongKey.hostReady and #wrongKey.hostReady == 0
        and containsEvent(wrongKey.clientBefore, "connect") == nil
        and containsEvent(wrongKey.clientReady, "connect") == nil
        and (containsEvent(wrongKey.clientBefore, "disconnect") ~= nil
            or containsEvent(wrongKey.clientReady, "disconnect") ~= nil)
        and #wrongKey.network.disconnects >= 1
        and wrongKey.network.disconnects[1].code == DirectTransport.DISCONNECT_AUTHENTICATION
        and #wrongKey.hostCrypto.states == 0
        and next(wrongKey.host._readyPeers) == nil)
    wrongKey.client:close()
    wrongKey.host:close()

    local plaintext = establishSingle()
    plaintext.network:injectHost(plaintext.peer, "hello from plaintext", 0, true)
    local plaintextEvents = plaintext.host:service(8)
    local plaintextDisconnect = containsEvent(plaintextEvents, "disconnect")
    check("direct_transport_rejects_plaintext_after_authentication_without_fallback",
        plaintextDisconnect
        and plaintextDisconnect.code == DirectTransport.DISCONNECT_AUTHENTICATION
        and not containsEvent(plaintextEvents, "receive"))
    plaintext.client:close()
    plaintext.host:close()

    local tampered = establishSingle()
    tampered.client:sendToServer("protected", 2, false)
    local tamperedRaw = tampered.network.host.inbound[#tampered.network.host.inbound]
    tamperedRaw.data = tamperedRaw.data:sub(1, -2)
        .. string.char((tamperedRaw.data:byte(-1) + 1) % 255)
    tamperedRaw.payload = tamperedRaw.data
    local tamperedEvents = tampered.host:service(8)
    check("direct_transport_rejects_tampered_ciphertext",
        containsEvent(tamperedEvents, "disconnect") ~= nil
        and not containsEvent(tamperedEvents, "receive"))
    tampered.client:close()
    tampered.host:close()

    local movedChannel = establishSingle()
    movedChannel.client:sendToServer("channel-bound", 2, false)
    local movedRaw = movedChannel.network.host.inbound[#movedChannel.network.host.inbound]
    movedRaw.channel = 1
    local movedEvents = movedChannel.host:service(8)
    check("direct_transport_authenticates_the_observed_channel_as_aad",
        containsEvent(movedEvents, "disconnect") ~= nil
        and not containsEvent(movedEvents, "receive"))
    movedChannel.client:close()
    movedChannel.host:close()

    local unreliableNetwork = fakeNetwork()
    local unreliableHostFactory = newSecureFactory(unreliableNetwork)
    local unreliableClientFactory = newSecureFactory(unreliableNetwork)
    local unreliableHost = unreliableHostFactory.createHost({ channels = 3 })
    local unreliableClient = unreliableClientFactory.createClient("direct.example:22122",
        { channels = 3 })
    local unreliablePeer = unreliableClient.base.peer
    unreliableHost:service(8)
    unreliableClient:service(8)
    local handshakeRaw = unreliableNetwork.host.inbound[#unreliableNetwork.host.inbound]
    handshakeRaw.reliable = false
    handshakeRaw.channel = 1
    local unreliableEvents = unreliableHost:service(8)
    check("direct_transport_rejects_handshakes_outside_reliable_channel_zero",
        unreliableEvents and #unreliableEvents == 0
        and unreliableNetwork.disconnects[#unreliableNetwork.disconnects].code
            == DirectTransport.DISCONNECT_AUTHENTICATION)
    unreliableClient:close()
    unreliableHost:close()

    local now = 0
    local timeoutNetwork = fakeNetwork()
    local timeoutFactory, timeoutCrypto = newSecureFactory(timeoutNetwork,
        SHARED_KEY, function() return now end, 3)
    local timeoutClientFactory = newSecureFactory(timeoutNetwork,
        SHARED_KEY, function() return now end, 3)
    local timeoutHost = timeoutFactory.createHost({ channels = 3 })
    local timeoutClient = timeoutClientFactory.createClient(
        "direct.example:22122", { channels = 3 })
    timeoutHost:service(8)
    now = 3.1
    local timeoutEvents = timeoutHost:service(8)
    local timeoutDisconnect = timeoutNetwork.disconnects[#timeoutNetwork.disconnects]
    check("direct_transport_expires_and_cleans_up_incomplete_handshakes",
        timeoutEvents and #timeoutEvents == 0
        and timeoutDisconnect
        and timeoutDisconnect.code == DirectTransport.DISCONNECT_HANDSHAKE_TIMEOUT
        and next(timeoutHost._peerStates) == nil
        and countCalls(timeoutCrypto, "close") == 1)
    timeoutClient:close()
    timeoutHost:close()

    local broadcastNetwork = fakeNetwork()
    local broadcastFactory, broadcastCrypto = newSecureFactory(broadcastNetwork)
    local broadcastClientFactoryOne = newSecureFactory(broadcastNetwork)
    local broadcastClientFactoryTwo = newSecureFactory(broadcastNetwork)
    local broadcastHost = broadcastFactory.createHost({ channels = 3 })
    local clientOne, peerOne, _, _, hostOne, readyOne =
        connectClient(broadcastHost, broadcastClientFactoryOne, broadcastNetwork)
    local clientTwo, peerTwo, _, _, hostTwo, readyTwo =
        connectClient(broadcastHost, broadcastClientFactoryTwo, broadcastNetwork)
    local sealBefore = countCalls(broadcastCrypto, "seal")
    local sendsBefore = #broadcastNetwork.sends
    local didBroadcast = broadcastHost:broadcast("snapshot", 2, false)
    local broadcastSends = {}
    for index = sendsBefore + 1, #broadcastNetwork.sends do
        broadcastSends[#broadcastSends + 1] = broadcastNetwork.sends[index]
    end
    local oneEvents = clientOne:service(8)
    local twoEvents = clientTwo:service(8)
    check("direct_transport_broadcast_seals_once_per_authenticated_peer",
        containsEvent(hostOne, "connect") and containsEvent(readyOne, "connect")
        and containsEvent(hostTwo, "connect") and containsEvent(readyTwo, "connect")
        and didBroadcast and #broadcastSends == 2
        and broadcastSends[1].peer ~= broadcastSends[2].peer
        and broadcastSends[1].channel == 2 and not broadcastSends[1].reliable
        and broadcastSends[2].channel == 2 and not broadcastSends[2].reliable
        and broadcastNetwork.broadcastCalls == 0
        and countCalls(broadcastCrypto, "seal") == sealBefore + 2
        and containsEvent(oneEvents, "receive", "snapshot")
        and containsEvent(twoEvents, "receive", "snapshot"))

    local responderIds = {}
    for _, state in ipairs(broadcastCrypto.states) do
        if state.role == "responder" then responderIds[state.id] = true end
    end
    local responderCloseBefore = countCalls(broadcastCrypto, "close", responderIds)
    local hostClosed = broadcastHost:close(0, true)
    local responderCloseAfter = countCalls(broadcastCrypto, "close", responderIds)
    check("direct_transport_close_cleans_every_per_peer_crypto_state",
        hostClosed and broadcastHost.closed and broadcastHost.base.closed
        and next(broadcastHost._peerStates) == nil
        and responderCloseBefore == 0 and responderCloseAfter == 2
        and peerOne ~= peerTwo)
    clientOne:close(0, true)
    clientTwo:close(0, true)

    local boundedNetwork = fakeNetwork()
    local boundedFactory = newSecureFactory(boundedNetwork, SHARED_KEY, nil, nil, {
        maxHandshakeBytes = 64,
        maxPlaintextBytes = 8,
        maxWireBytes = 128,
    })
    local boundedClientFactory = newSecureFactory(boundedNetwork, SHARED_KEY, nil, nil, {
        maxHandshakeBytes = 64,
        maxPlaintextBytes = 8,
        maxWireBytes = 128,
    })
    local boundedHost = boundedFactory.createHost({ channels = 3 })
    local boundedClient, boundedPeer, _, _, boundedHostReady, boundedClientReady =
        connectClient(boundedHost, boundedClientFactory, boundedNetwork)
    local oversizedSend = boundedClient:sendToServer("123456789", 2, false)
    boundedNetwork:injectHost(boundedPeer, string.rep("x", 129), 2, false)
    local oversizedEvents = boundedHost:service(8)
    check("direct_transport_enforces_plaintext_and_wire_byte_caps",
        containsEvent(boundedHostReady, "connect")
        and containsEvent(boundedClientReady, "connect")
        and oversizedSend == false
        and containsEvent(oversizedEvents, "disconnect") ~= nil
        and not containsEvent(oversizedEvents, "receive"))
    boundedClient:close()
    boundedHost:close()

    local prefilterNetwork = fakeNetwork()
    local prefilterHostFactory, prefilterHostCrypto = newSecureFactory(prefilterNetwork)
    local prefilterClientFactory = newSecureFactory(prefilterNetwork)
    local prefilterHost = prefilterHostFactory.createHost({ channels = 3 })
    for index = 1, 3 do
        prefilterNetwork.host.inbound[#prefilterNetwork.host.inbound + 1] = {
            type = "connect",
            peer = { id = "scanner-" .. tostring(index) },
            data = index,
            code = index,
        }
    end
    prefilterHost:service(16)
    local prefilterClient, _, _, _, prefilterHostReady, prefilterClientReady =
        connectClient(prefilterHost, prefilterClientFactory, prefilterNetwork)
    local secondHost = prefilterHostFactory.createHost({ channels = 3 })
    check("direct_transport_prefilter_releases_scanners_before_noise_state_allocation",
        #prefilterNetwork.disconnects >= 3
        and #prefilterHostCrypto.states == 1
        and containsEvent(prefilterHostReady, "connect") ~= nil
        and containsEvent(prefilterClientReady, "connect") ~= nil
        and secondHost == nil)
    check("direct_transport_factory_and_shared_key_are_session_scoped",
        prefilterHost._key == SHARED_KEY and prefilterClient._key == nil)
    prefilterClient:close()
    prefilterHost:close()
    check("direct_transport_close_releases_the_host_shared_key",
        prefilterHost._key == nil)

    do
    local burstNow = 0
    local burstNetwork = fakeNetwork()
    local burstFactory, burstCrypto = newSecureFactory(burstNetwork, SHARED_KEY,
        function() return burstNow end, nil, { maxPendingPeers = 8 })
    local burstHost = burstFactory.createHost({ channels = 3 })
    for index = 1, 10 do
        injectHostConnect(burstNetwork, { id = "burst-" .. tostring(index) },
            fakeAdmissionToken(SHARED_KEY))
    end
    burstHost:service(64)
    check("direct_transport_bounds_same_tick_valid_admissions_before_crypto_allocation",
        DirectTransport.DEFAULT_ADMISSION_BURST == 4
        and #burstCrypto.states == DirectTransport.DEFAULT_ADMISSION_BURST
        and tableCount(burstHost._peerStates) == DirectTransport.DEFAULT_ADMISSION_BURST
        and #burstNetwork.disconnects == 10 - DirectTransport.DEFAULT_ADMISSION_BURST
        and burstHost._admissionTokens == 0)
    burstHost:close()
    end

    do
    local scannerNetwork = fakeNetwork()
    local scannerFactory, scannerCrypto = newSecureFactory(scannerNetwork,
        SHARED_KEY, nil, nil, { admissionBurst = 3 })
    local scannerHost = scannerFactory.createHost({ channels = 3 })
    for index = 1, 8 do
        injectHostConnect(scannerNetwork, { id = "wrong-token-" .. tostring(index) },
            index)
    end
    for index = 1, 3 do
        injectHostConnect(scannerNetwork, { id = "valid-after-scan-" .. tostring(index) },
            fakeAdmissionToken(SHARED_KEY))
    end
    scannerHost:service(64)
    check("direct_transport_wrong_tokens_do_not_consume_admission_permits",
        #scannerCrypto.states == 3
        and tableCount(scannerHost._peerStates) == 3
        and #scannerNetwork.disconnects == 8
        and scannerHost._admissionTokens == 0)
    scannerHost:close()
    end

    do
    local pendingNetwork = fakeNetwork()
    local pendingFactory, pendingCrypto = newSecureFactory(pendingNetwork,
        SHARED_KEY, nil, nil, { admissionBurst = 8 })
    local pendingHost = pendingFactory.createHost({ channels = 3 })
    for index = 1, 8 do
        injectHostConnect(pendingNetwork, { id = "pending-" .. tostring(index) },
            fakeAdmissionToken(SHARED_KEY))
    end
    pendingHost:service(64)
    check("direct_transport_keeps_a_hard_four_state_pending_admission_cap",
        DirectTransport.DEFAULT_MAX_PENDING_PEERS == 4
        and pendingHost.maxPendingPeers == DirectTransport.DEFAULT_MAX_PENDING_PEERS
        and #pendingCrypto.states == DirectTransport.DEFAULT_MAX_PENDING_PEERS
        and tableCount(pendingHost._peerStates)
            == DirectTransport.DEFAULT_MAX_PENDING_PEERS
        and pendingHost._admissionTokens == 4
        and #pendingNetwork.disconnects == 4)
    pendingHost:close()
    end

    do
    local refillNow = 0
    local refillNetwork = fakeNetwork()
    local refillFactory, refillCrypto = newSecureFactory(refillNetwork,
        SHARED_KEY, function() return refillNow end, nil, {
            admissionBurst = 1,
            admissionRefillSeconds = 1,
        })
    local refillHost = refillFactory.createHost({ channels = 3 })
    local refillFirst = { id = "refill-first" }
    injectHostConnect(refillNetwork, refillFirst, fakeAdmissionToken(SHARED_KEY))
    refillHost:service(8)
    refillHost:disconnect(refillFirst, 0, true)
    refillNow = 0.999
    local refillEarly = { id = "refill-early" }
    injectHostConnect(refillNetwork, refillEarly, fakeAdmissionToken(SHARED_KEY))
    refillHost:service(8)
    refillNow = 1
    local refillExact = { id = "refill-exact" }
    injectHostConnect(refillNetwork, refillExact, fakeAdmissionToken(SHARED_KEY))
    refillHost:service(8)
    check("direct_transport_refills_one_admission_permit_per_second",
        #refillCrypto.states == 2
        and refillHost._peerStates[refillEarly] == nil
        and refillHost._peerStates[refillExact] ~= nil
        and refillHost._admissionTokens == 0)
    refillHost:close()
    end

    do
    local noRefundCalls = 0
    local noRefundSecret = "constructor-secret-" .. hexEncode(SHARED_KEY)
    local noRefundProvider = fakeCryptoProvider({ states = {}, calls = {} })
    function noRefundProvider.newResponder()
        noRefundCalls = noRefundCalls + 1
        error(noRefundSecret)
    end
    local noRefundNetwork = fakeNetwork()
    local noRefundFactory = DirectTransport.newFactory({
        baseFactory = noRefundNetwork.factory,
        cryptoProvider = noRefundProvider,
        key = SHARED_KEY,
        clock = function() return 0 end,
        admissionBurst = 1,
    })
    local noRefundHost = noRefundFactory.createHost({ channels = 3 })
    injectHostConnect(noRefundNetwork, { id = "constructor-failure" },
        fakeAdmissionToken(SHARED_KEY))
    injectHostConnect(noRefundNetwork, { id = "constructor-retry" },
        fakeAdmissionToken(SHARED_KEY))
    noRefundHost:service(8)
    check("direct_transport_does_not_refund_failed_crypto_state_admissions",
        noRefundCalls == 1
        and tableCount(noRefundHost._peerStates) == 0
        and #noRefundNetwork.disconnects == 2
        and type(noRefundHost.lastError) == "string"
        and noRefundHost.lastError:find(noRefundSecret, 1, true) == nil
        and noRefundHost.lastError:find(hexEncode(SHARED_KEY), 1, true) == nil)
    noRefundHost:close()
    end

    do
    local invalidClockSecret = "clock-secret-" .. hexEncode(SHARED_KEY)
    local invalidClockNetwork = fakeNetwork()
    local invalidClockFactory, invalidClockCrypto = newSecureFactory(
        invalidClockNetwork, SHARED_KEY, function() error(invalidClockSecret) end)
    local invalidClockHost = invalidClockFactory.createHost({ channels = 3 })
    injectHostConnect(invalidClockNetwork, { id = "invalid-clock" },
        fakeAdmissionToken(SHARED_KEY))
    invalidClockHost:service(8)
    check("direct_transport_invalid_clock_fails_closed_without_allocating_or_leaking",
        #invalidClockCrypto.states == 0
        and tableCount(invalidClockHost._peerStates) == 0
        and invalidClockHost._clockFailed == true
        and #invalidClockNetwork.disconnects == 1
        and type(invalidClockHost.lastError) == "string"
        and invalidClockHost.lastError:find(invalidClockSecret, 1, true) == nil
        and invalidClockHost.lastError:find(hexEncode(SHARED_KEY), 1, true) == nil)
    invalidClockHost:close()
    end

    do
    local backwardNow = 10
    local backwardNetwork = fakeNetwork()
    local backwardFactory, backwardCrypto = newSecureFactory(backwardNetwork,
        SHARED_KEY, function() return backwardNow end)
    local backwardClientFactory = newSecureFactory(backwardNetwork,
        SHARED_KEY, function() return backwardNow end)
    local backwardHost = backwardFactory.createHost({ channels = 3 })
    local backwardClient, backwardPeer, _, _, backwardHostReady,
        backwardClientReady = connectClient(
            backwardHost, backwardClientFactory, backwardNetwork)
    backwardNow = 9
    injectHostConnect(backwardNetwork, { id = "after-clock-rollback" },
        fakeAdmissionToken(SHARED_KEY))
    backwardHost:service(8)
    check("direct_transport_backward_clock_fails_closed_before_another_allocation",
        #backwardCrypto.states == 1
        and containsEvent(backwardHostReady, "connect") ~= nil
        and containsEvent(backwardClientReady, "connect") ~= nil
        and backwardHost._peerStates[backwardPeer] ~= nil
        and tableCount(backwardHost._peerStates) == 1
        and tableCount(backwardHost._readyPeers) == 1
        and backwardHost._clockFailed == true
        and type(backwardHost.lastError) == "string"
        and backwardHost.lastError:find(hexEncode(SHARED_KEY), 1, true) == nil)
    backwardClient:close()
    backwardHost:close()
    end

    do
    local readyNetwork = fakeNetwork()
    local readyHostFactory, readyHostCrypto = newSecureFactory(readyNetwork)
    local readyHost = readyHostFactory.createHost({ channels = 3 })
    local readyClients, readyPeers = {}, {}
    local firstThreeReady = true
    for index = 1, 3 do
        local readyClientFactory = newSecureFactory(readyNetwork)
        local client, peer, _, _, hostEvents, clientEvents =
            connectClient(readyHost, readyClientFactory, readyNetwork)
        readyClients[#readyClients + 1] = client
        readyPeers[#readyPeers + 1] = peer
        firstThreeReady = firstThreeReady
            and containsEvent(hostEvents, "connect") ~= nil
            and containsEvent(clientEvents, "connect") ~= nil
    end
    local fourthClientFactory = newSecureFactory(readyNetwork)
    local fourthClient, fourthPeer, _, _, fourthHostEvents, fourthClientEvents =
        connectClient(readyHost, fourthClientFactory, readyNetwork)
    local fourthRejected = containsEvent(fourthHostEvents, "connect") == nil
        and containsEvent(fourthClientEvents, "connect") == nil
        and readyHost._peerStates[fourthPeer] == nil
    readyHost:disconnect(readyPeers[1], 0, true)
    local replacementFactory = newSecureFactory(readyNetwork)
    local replacementClient, replacementPeer, _, _, replacementHostEvents,
        replacementClientEvents = connectClient(
            readyHost, replacementFactory, readyNetwork)
    check("direct_transport_caps_ready_guests_at_three_and_allows_replacement",
        DirectTransport.DEFAULT_MAX_READY_PEERS == 3
        and firstThreeReady and fourthRejected
        and containsEvent(replacementHostEvents, "connect") ~= nil
        and containsEvent(replacementClientEvents, "connect") ~= nil
        and readyHost._peerStates[replacementPeer] ~= nil
        and tableCount(readyHost._readyPeers) == 3
        and #readyHostCrypto.states == 4)
    fourthClient:close()
    replacementClient:close()
    for _, client in ipairs(readyClients) do client:close() end
    readyHost:close()
    end

    local preAuthNetwork = fakeNetwork()
    local preAuthHostFactory, preAuthHostCrypto = newSecureFactory(preAuthNetwork)
    local preAuthClientFactory = newSecureFactory(preAuthNetwork)
    local preAuthHost = preAuthHostFactory.createHost({ channels = 3 })
    local preAuthClient = preAuthClientFactory.createClient(
        "direct.example:22122", { channels = 3 })
    local preAuthPeer = preAuthClient.base.peer
    preAuthHost:service(8)
    local openBeforePreAuth = countCalls(preAuthHostCrypto, "open")
    preAuthNetwork:injectHost(preAuthPeer,
        directFrame(DirectTransport.TYPE_DATA,
            string.rep("x", DirectTransport.DEFAULT_MAX_HANDSHAKE_BYTES + 1)),
        2, false)
    preAuthHost:service(8)
    check("direct_transport_rejects_large_pre_auth_data_before_crypto_open",
        countCalls(preAuthHostCrypto, "open") == openBeforePreAuth
        and preAuthHost._peerStates[preAuthPeer] == nil)
    preAuthClient:close()
    preAuthHost:close()

    local inboundCap = establishSingle()
    local openBeforeInboundCap = countCalls(inboundCap.hostCrypto, "open")
    inboundCap.network:injectHost(inboundCap.peer,
        directFrame(DirectTransport.TYPE_DATA,
            string.rep("x", DirectTransport.DEFAULT_MAX_REALTIME_PLAINTEXT_BYTES
                + DirectTransport.DEFAULT_MAX_CIPHERTEXT_OVERHEAD_BYTES + 1)),
        2, false)
    local inboundCapEvents = inboundCap.host:service(8)
    check("direct_transport_caps_guest_wire_data_before_host_crypto_open",
        countCalls(inboundCap.hostCrypto, "open") == openBeforeInboundCap
        and containsEvent(inboundCapEvents, "disconnect") ~= nil)
    inboundCap.client:close()
    inboundCap.host:close()

    local secretError = "provider-error-" .. hexEncode(SHARED_KEY)
    local errorProvider = {
        productionReady = true,
        admissionToken = fakeAdmissionToken,
        newInitiator = function() error(secretError) end,
        newResponder = function() error(secretError) end,
    }
    local errorNetwork = fakeNetwork()
    local errorHostFactory = DirectTransport.newFactory({
        baseFactory = errorNetwork.factory,
        cryptoProvider = errorProvider,
        key = SHARED_KEY,
    })
    local errorClientFactory = newSecureFactory(errorNetwork)
    local errorHost = errorHostFactory.createHost({ channels = 3 })
    local errorClient = errorClientFactory.createClient(
        "direct.example:22122", { channels = 3 })
    errorHost:service(8)
    check("direct_transport_crypto_exceptions_never_echo_shared_key_material",
        type(errorHost.lastError) == "string"
        and errorHost.lastError:find(secretError, 1, true) == nil
        and errorHost.lastError:find(hexEncode(SHARED_KEY), 1, true) == nil)
    errorClient:close()
    errorHost:close()

    local frameLimitNetwork = fakeNetwork()
    local frameLimitLog = { handshakes = 0, bytes = 0 }
    local frameLimitFactory = DirectTransport.newFactory({
        baseFactory = frameLimitNetwork.factory,
        cryptoProvider = stallingCryptoProvider(frameLimitLog),
        key = SHARED_KEY,
        maxHandshakeFrames = 2,
        maxHandshakeTotalBytes = 100,
    })
    local frameLimitHost = frameLimitFactory.createHost({ channels = 3 })
    local frameLimitClient = frameLimitNetwork.factory.createClient(
        "direct.example:22122", {
            channels = 3,
            connectData = fakeAdmissionToken(SHARED_KEY),
        })
    local frameLimitPeer = frameLimitClient.peer
    frameLimitHost:service(8)
    for _ = 1, 3 do
        frameLimitNetwork:injectHost(frameLimitPeer,
            directFrame(DirectTransport.TYPE_HANDSHAKE, "aa"), 0, true)
    end
    frameLimitHost:service(8)
    check("direct_transport_caps_pre_auth_handshake_frame_count",
        frameLimitLog.handshakes == 2
        and frameLimitHost._peerStates[frameLimitPeer] == nil)
    frameLimitClient:close()
    frameLimitHost:close()

    local byteLimitNetwork = fakeNetwork()
    local byteLimitLog = { handshakes = 0, bytes = 0 }
    local byteLimitFactory = DirectTransport.newFactory({
        baseFactory = byteLimitNetwork.factory,
        cryptoProvider = stallingCryptoProvider(byteLimitLog),
        key = SHARED_KEY,
        maxHandshakeFrames = 4,
        maxHandshakeTotalBytes = 4,
    })
    local byteLimitHost = byteLimitFactory.createHost({ channels = 3 })
    local byteLimitClient = byteLimitNetwork.factory.createClient(
        "direct.example:22122", {
            channels = 3,
            connectData = fakeAdmissionToken(SHARED_KEY),
        })
    local byteLimitPeer = byteLimitClient.peer
    byteLimitHost:service(8)
    byteLimitNetwork:injectHost(byteLimitPeer,
        directFrame(DirectTransport.TYPE_HANDSHAKE, "abc"), 0, true)
    byteLimitNetwork:injectHost(byteLimitPeer,
        directFrame(DirectTransport.TYPE_HANDSHAKE, "de"), 0, true)
    byteLimitHost:service(8)
    check("direct_transport_caps_aggregate_pre_auth_handshake_bytes",
        byteLimitLog.handshakes == 1 and byteLimitLog.bytes == 3
        and byteLimitHost._peerStates[byteLimitPeer] == nil)
    byteLimitClient:close()
    byteLimitHost:close()

    local budgetNetwork = fakeNetwork()
    local budgetFactory = newSecureFactory(budgetNetwork)
    local budgetHost = budgetFactory.createHost({ channels = 3 })
    for index = 1, 100 do
        budgetNetwork.host.inbound[#budgetNetwork.host.inbound + 1] = {
            type = "receive",
            peer = { id = "raw-budget-" .. tostring(index) },
            data = "not-a-direct-frame",
            channel = 0,
        }
    end
    budgetHost:service(64)
    check("direct_transport_service_shares_one_bounded_raw_event_budget",
        #budgetNetwork.host.inbound == 100 - DirectTransport.MAX_EVENTS_PER_SERVICE)
    budgetHost:close()

    local disposedNetwork = fakeNetwork()
    local disposedFactory = newSecureFactory(disposedNetwork)
    local disposed, disposeError = disposedFactory.close()
    local disposedAgain, disposeAgainError = disposedFactory.close()
    local createAfterDispose = disposedFactory.createHost({ channels = 3 })
    check("direct_transport_factory_dispose_is_idempotent_and_one_session_scoped",
        disposed and not disposeError and disposedAgain and not disposeAgainError
        and createAfterDispose == nil)

    local stickyNetwork = fakeNetwork()
    local stickyFactory = newSecureFactory(stickyNetwork)
    local stickyHost = stickyFactory.createHost({ channels = 3 })
    stickyHost.base.close = function() return false, "injected close failure" end
    local stickyClosed, stickyError = stickyHost:close()
    local stickyClosedAgain, stickyErrorAgain = stickyHost:close()
    check("direct_transport_repeated_close_never_upgrades_unverified_cleanup",
        stickyClosed == false and type(stickyError) == "string"
        and stickyClosedAgain == false and stickyErrorAgain == stickyError)
end

return Test
