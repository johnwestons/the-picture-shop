-- Fail-closed security boundary for Direct Internet Play. This module does not
-- implement cryptography. A production native provider must return Lua tables
-- or userdata exposing start, handshake, isReady, seal, open, and close. The
-- provider owns Noise transcript validation, direction-separated traffic keys,
-- per-channel nonces/replay windows, and native key zeroization. `productionReady`
-- is an API guard, not a substitute for provider conformance tests.
local DirectTransport = {}
local Instance = {}
Instance.__index = Instance

DirectTransport.MAGIC = "TPSD"
DirectTransport.VERSION = 1
DirectTransport.TYPE_HANDSHAKE = 1
DirectTransport.TYPE_DATA = 2
DirectTransport.HEADER_BYTES = #DirectTransport.MAGIC + 2
DirectTransport.HANDSHAKE_CHANNEL = 0
DirectTransport.DURABLE_CHANNEL = 2
DirectTransport.KEY_BYTES = 32

DirectTransport.DEFAULT_CHANNELS = 3
DirectTransport.DEFAULT_HANDSHAKE_TIMEOUT = 5
DirectTransport.DEFAULT_PEER_CAPACITY = 12
DirectTransport.DEFAULT_MAX_PENDING_PEERS = 4
DirectTransport.DEFAULT_ADMISSION_BURST = 4
DirectTransport.DEFAULT_ADMISSION_REFILL_SECONDS = 1
DirectTransport.DEFAULT_MAX_READY_PEERS = 3
DirectTransport.DEFAULT_MAX_HANDSHAKE_BYTES = 1024
DirectTransport.DEFAULT_MAX_HANDSHAKE_FRAMES = 4
DirectTransport.DEFAULT_MAX_HANDSHAKE_TOTAL_BYTES = 4096
DirectTransport.DEFAULT_MAX_PRE_READY_DATA_FRAMES = 8
DirectTransport.DEFAULT_MAX_REALTIME_PLAINTEXT_BYTES = 1200
DirectTransport.DEFAULT_MAX_PLAINTEXT_BYTES = 512 * 1024
DirectTransport.DEFAULT_MAX_CIPHERTEXT_OVERHEAD_BYTES = 256
DirectTransport.DEFAULT_MAX_WIRE_BYTES = DirectTransport.HEADER_BYTES
    + DirectTransport.DEFAULT_MAX_PLAINTEXT_BYTES
    + DirectTransport.DEFAULT_MAX_CIPHERTEXT_OVERHEAD_BYTES
DirectTransport.DEFAULT_MAX_PRE_READY_DATA_BYTES =
    DirectTransport.DEFAULT_MAX_PLAINTEXT_BYTES
    + DirectTransport.DEFAULT_MAX_CIPHERTEXT_OVERHEAD_BYTES
    + (DirectTransport.DEFAULT_MAX_PRE_READY_DATA_FRAMES - 1)
        * (DirectTransport.DEFAULT_MAX_REALTIME_PLAINTEXT_BYTES
            + DirectTransport.DEFAULT_MAX_CIPHERTEXT_OVERHEAD_BYTES)
DirectTransport.MAX_EVENTS_PER_SERVICE = 64

DirectTransport.DISCONNECT_AUTHENTICATION = 4201
DirectTransport.DISCONNECT_HANDSHAKE_TIMEOUT = 4202
DirectTransport.DISCONNECT_INTERNAL = 4203

local HANDSHAKE_PREFIX = DirectTransport.MAGIC
    .. string.char(DirectTransport.VERSION, DirectTransport.TYPE_HANDSHAKE)
local DATA_PREFIX = DirectTransport.MAGIC
    .. string.char(DirectTransport.VERSION, DirectTransport.TYPE_DATA)

local REQUIRED_STATE_METHODS = {
    "start", "handshake", "isReady", "seal", "open", "close",
}

local function wholeNumber(value, minimum, maximum)
    value = tonumber(value)
    return value and value == math.floor(value) and value >= minimum and value <= maximum
        and value or nil
end

local function finiteNumber(value, minimum, maximum)
    value = tonumber(value)
    return value and value == value and value > -math.huge and value < math.huge
        and value >= minimum and value <= maximum and value or nil
end

local function defaultClock()
    if love and love.timer and type(love.timer.getTime) == "function" then
        return love.timer.getTime()
    end
    return os.clock()
end

local function copyEvent(event, eventType)
    local result = {}
    if type(event) == "table" then
        for key, value in pairs(event) do result[key] = value end
    end
    result.type = eventType or result.type
    return result
end

local function methodFor(target, method)
    if target == nil then return nil end
    local ok, callable = pcall(function() return target[method] end)
    if not ok or type(callable) ~= "function" then return nil end
    return callable
end

local function callMethod(target, method, ...)
    local callable = methodFor(target, method)
    if not callable then return false, "missing " .. tostring(method) end
    return pcall(callable, target, ...)
end

local function callFactory(factory, method, ...)
    if type(factory) ~= "table" or type(factory[method]) ~= "function" then
        return false, "missing " .. tostring(method)
    end
    return pcall(factory[method], ...)
end

local function sendSucceeded(result)
    if result == false then return false end
    if type(result) == "number" and result < 0 then return false end
    return true
end

local function sendOptions(channelOrOptions, reliable)
    if type(channelOrOptions) == "table" then
        return channelOrOptions.channel or 0, channelOrOptions.reliable == true
    end
    return channelOrOptions or 0, reliable == true
end

local function validateProvider(provider)
    if type(provider) ~= "table" then
        return nil, "Direct Internet Play requires a cryptographic provider."
    end
    if type(provider.newInitiator) ~= "function"
        or type(provider.newResponder) ~= "function"
    then
        return nil, "The cryptographic provider must implement newInitiator and newResponder."
    end
    if type(provider.admissionToken) ~= "function" then
        return nil, "The cryptographic provider must implement admissionToken."
    end
    if provider.productionReady ~= true then
        return nil, "Direct Internet Play requires a production cryptographic provider."
    end
    return provider
end

local function validateState(state)
    if state == nil then
        return nil, "The cryptographic provider did not create a state object."
    end
    for _, method in ipairs(REQUIRED_STATE_METHODS) do
        if not methodFor(state, method) then
            return nil, "The cryptographic state must implement " .. method .. "."
        end
    end
    return state
end

local function closeState(entry)
    if not entry or entry.closed then return true end
    entry.closed = true
    local ok, result, errorMessage = callMethod(entry.state, "close")
    if not ok or result == false then return false, "Cryptographic state cleanup failed." end
    return true
end

local function frame(packetType, payload)
    local prefix = packetType == DirectTransport.TYPE_HANDSHAKE
        and HANDSHAKE_PREFIX or DATA_PREFIX
    return prefix .. payload
end

local function parseFrame(payload, maxHandshakeBytes, maxWireBytes)
    if type(payload) ~= "string" then return nil, nil, "Direct packet is not a string." end
    if #payload < DirectTransport.HEADER_BYTES + 1 then
        return nil, nil, "Direct packet is missing its authenticated frame."
    end
    if #payload > maxWireBytes then return nil, nil, "Direct packet exceeds the wire limit." end
    if payload:sub(1, #DirectTransport.MAGIC) ~= DirectTransport.MAGIC then
        return nil, nil, "Direct packet has the wrong magic."
    end
    local version = payload:byte(#DirectTransport.MAGIC + 1)
    if version ~= DirectTransport.VERSION then
        return nil, nil, "Direct packet has an unsupported version."
    end
    local packetType = payload:byte(#DirectTransport.MAGIC + 2)
    if packetType ~= DirectTransport.TYPE_HANDSHAKE
        and packetType ~= DirectTransport.TYPE_DATA
    then
        return nil, nil, "Direct packet has an invalid type."
    end
    local body = payload:sub(DirectTransport.HEADER_BYTES + 1)
    if #body == 0 then return nil, nil, "Direct packet has an empty body." end
    if packetType == DirectTransport.TYPE_HANDSHAKE and #body > maxHandshakeBytes then
        return nil, nil, "Direct handshake exceeds the handshake limit."
    end
    return packetType, body
end

function DirectTransport.aadForChannel(channel)
    channel = wholeNumber(channel, 0, 255)
    if not channel then return nil, "Direct packet channel must be between 0 and 255." end
    return DATA_PREFIX .. string.char(channel)
end

function DirectTransport.admissionToken(provider, key)
    if type(provider) ~= "table" or type(provider.admissionToken) ~= "function" then
        return nil, "Direct admission tokens require a cryptographic provider."
    end
    if type(key) ~= "string" or #key ~= DirectTransport.KEY_BYTES then
        return nil, "Direct admission tokens require a 32-byte shared key."
    end
    local ok, token, errorMessage = pcall(provider.admissionToken, key)
    if not ok or errorMessage ~= nil then
        return nil, "Cryptographic admission token derivation failed."
    end
    if type(token) ~= "number" or token ~= token or token ~= math.floor(token)
        or token < 0 or token > 2147483647
    then
        return nil, "The cryptographic provider returned an invalid admission token."
    end
    return token
end

function Instance:_plaintextLimit(channel, inbound)
    local guestToHost = (self.mode == "host" and inbound == true)
        or (self.mode == "client" and inbound ~= true)
    if guestToHost or channel ~= DirectTransport.DURABLE_CHANNEL then
        return self.maxRealtimePlaintextBytes
    end
    return self.maxPlaintextBytes
end

function Instance:_queue(event)
    self._events[#self._events + 1] = event
end

function Instance:_dequeue()
    if #self._events == 0 then return nil end
    return table.remove(self._events, 1)
end

function Instance:_ready(entry)
    local ok, ready, errorMessage = callMethod(entry.state, "isReady")
    if not ok or errorMessage ~= nil then return nil, "Cryptographic readiness check failed." end
    if type(ready) ~= "boolean" then
        return nil, "Cryptographic readiness check did not return a boolean."
    end
    return ready
end

function Instance:_readyPeerCount()
    local count = 0
    for _ in pairs(self._readyPeers) do count = count + 1 end
    return count
end

function Instance:_readClock()
    if self._clockFailed then
        return nil, "Direct authentication timing failed."
    end
    local ok, now = pcall(self.clock)
    if not ok or type(now) ~= "number" or now ~= now
        or now <= -math.huge or now >= math.huge
        or (self._lastClock ~= nil and now < self._lastClock)
    then
        self._clockFailed = true
        return nil, "Direct authentication timing failed."
    end
    self._lastClock = now
    return now
end

function Instance:_takeAdmissionPermit()
    local now, clockError = self:_readClock()
    if now == nil then return nil, nil, clockError end

    if self._admissionLastRefill == nil then
        self._admissionLastRefill = now
    else
        local elapsed = now - self._admissionLastRefill
        self._admissionTokens = math.min(self.admissionBurst,
            self._admissionTokens + elapsed / self.admissionRefillSeconds)
        self._admissionLastRefill = now
    end
    if self._admissionTokens < 1 then return false, now end
    self._admissionTokens = self._admissionTokens - 1
    return true, now
end

function Instance:_markReady(entry)
    if entry.logicalConnected then return true end
    local ready, readyError = self:_ready(entry)
    if ready == nil then return false, readyError end
    if not ready or not entry.handshakeSent or not entry.handshakeReceived then return true end
    if self.mode == "host" and self:_readyPeerCount() >= self.maxReadyPeers then
        return false, "Direct authentication capacity is temporarily full.", true
    end
    local pending = entry.pendingData
    entry.pendingData = {}
    entry.pendingDataBytes = 0
    local pendingEvents = {}
    for _, item in ipairs(pending) do
        local pendingEvent, processError = self:_decryptData(entry, item.body, item.raw)
        if not pendingEvent then return false, processError, true end
        pendingEvents[#pendingEvents + 1] = pendingEvent
    end
    entry.logicalConnected = true
    self._readyPeers[entry.peer] = true
    if self.mode == "client" then self.peer = entry.peer end
    local event = copyEvent(entry.connectEvent, "connect")
    event.peer = entry.peer
    self:_queue(event)
    for _, pendingEvent in ipairs(pendingEvents) do
        self:_queue(pendingEvent)
    end
    return true
end

function Instance:_sendHandshake(entry, payload)
    if payload == nil then return true end
    if type(payload) ~= "string" or #payload == 0 then
        return false, "Cryptographic handshake output must be a nonempty string."
    end
    if #payload > self.maxHandshakeBytes then
        return false, "Cryptographic handshake output exceeds the handshake limit."
    end
    local wire = frame(DirectTransport.TYPE_HANDSHAKE, payload)
    if #wire > self.maxWireBytes then
        return false, "Cryptographic handshake output exceeds the wire limit."
    end
    local ok, result, errorMessage = callMethod(self.base, "send", entry.peer, wire,
        DirectTransport.HANDSHAKE_CHANNEL, true)
    if not ok then return false, "Direct handshake send failed: " .. tostring(result) end
    if not sendSucceeded(result) then
        return false, tostring(errorMessage or "The network rejected the direct handshake.")
    end
    entry.handshakeSent = true
    return true
end

function Instance:_newState(role)
    local constructor = role == "initiator"
        and self.cryptoProvider.newInitiator or self.cryptoProvider.newResponder
    local ok, state, errorMessage = pcall(constructor, self._key)
    if not ok or errorMessage ~= nil then return nil, "Cryptographic state creation failed." end
    if not state then return nil, "Cryptographic state creation failed." end
    local validated, validationError = validateState(state)
    if validated and role == "initiator" then self._key = nil end
    return validated, validationError
end

function Instance:_forgetPeer(peer)
    local entry = self._peerStates[peer]
    if not entry then return nil end
    local closed, closeError = closeState(entry)
    if not closed then self.lastError = closeError end
    self._peerStates[peer] = nil
    self._readyPeers[peer] = nil
    if self.peer == peer then self.peer = nil end
    return entry, closeError
end

function Instance:_failPeer(peer, code, reason)
    local entry, closeError = self:_forgetPeer(peer)
    self.lastError = closeError and (reason .. "; " .. closeError) or reason
    local ok, result = callMethod(self.base, "disconnect", peer, code, true)
    if not ok or result == false then
        self.lastError = reason .. "; disconnect failed: " .. tostring(result)
    end
    if entry and (entry.logicalConnected or self.mode == "client") then
        local event = copyEvent(entry.connectEvent, "disconnect")
        event.peer = peer
        event.code = code
        event.data = code
        event.error = reason
        self:_queue(event)
    end
    return false, reason
end

function Instance:_startPeer(raw)
    local peer = raw.peer
    if not peer then return false, "Direct connection event is missing its peer." end
    if self._peerStates[peer] then
        return self:_failPeer(peer, DirectTransport.DISCONNECT_AUTHENTICATION,
            "Duplicate direct connection event.")
    end
    if self.mode == "host"
        and tonumber(raw.code or raw.data) ~= self.admissionToken
    then
        return self:_failPeer(peer, DirectTransport.DISCONNECT_AUTHENTICATION,
            "Direct invitation pre-authentication failed.")
    end
    if self.mode == "client" and next(self._peerStates) ~= nil then
        return self:_failPeer(peer, DirectTransport.DISCONNECT_AUTHENTICATION,
            "A direct client accepted more than one server peer.")
    end
    if self.mode == "host" then
        if self:_readyPeerCount() >= self.maxReadyPeers then
            return self:_failPeer(peer, DirectTransport.DISCONNECT_AUTHENTICATION,
                "Direct authentication capacity is temporarily full.")
        end
        local pending = 0
        for _, existing in pairs(self._peerStates) do
            if not existing.logicalConnected then pending = pending + 1 end
        end
        if pending >= self.maxPendingPeers then
            return self:_failPeer(peer, DirectTransport.DISCONNECT_AUTHENTICATION,
                "Direct authentication capacity is temporarily full.")
        end
    end

    local now
    if self.mode == "host" then
        local permitted, permitTime, permitError = self:_takeAdmissionPermit()
        if permitted == nil then
            return self:_failPeer(peer, DirectTransport.DISCONNECT_AUTHENTICATION,
                permitError)
        end
        if not permitted then
            return self:_failPeer(peer, DirectTransport.DISCONNECT_AUTHENTICATION,
                "Direct authentication capacity is temporarily full.")
        end
        now = permitTime
    else
        local clockError
        now, clockError = self:_readClock()
        if now == nil then
            return self:_failPeer(peer, DirectTransport.DISCONNECT_AUTHENTICATION,
                clockError)
        end
    end
    local deadline = now + self.handshakeTimeout
    if deadline ~= deadline or deadline <= -math.huge or deadline >= math.huge
        or deadline <= now
    then
        self._clockFailed = true
        return self:_failPeer(peer, DirectTransport.DISCONNECT_AUTHENTICATION,
            "Direct authentication timing failed.")
    end

    local role = self.mode == "client" and "initiator" or "responder"
    local state, stateError = self:_newState(role)
    if not state then
        return self:_failPeer(peer, DirectTransport.DISCONNECT_INTERNAL, stateError)
    end
    local entry = {
        peer = peer,
        state = state,
        role = role,
        connectEvent = copyEvent(raw, "connect"),
        startedAt = now,
        deadline = deadline,
        handshakeSent = false,
        handshakeReceived = false,
        handshakeFrames = 0,
        handshakeBytes = 0,
        pendingData = {},
        pendingDataBytes = 0,
        logicalConnected = false,
        closed = false,
    }
    self._peerStates[peer] = entry
    if self.mode == "client" then self._serverPeer = peer end

    local ok, outbound, errorMessage = callMethod(state, "start")
    if not ok then
        return self:_failPeer(peer, DirectTransport.DISCONNECT_INTERNAL,
            "Cryptographic handshake start failed.")
    end
    if errorMessage ~= nil then
        return self:_failPeer(peer, DirectTransport.DISCONNECT_AUTHENTICATION,
            "Direct authentication failed.")
    end
    local sent, sendError = self:_sendHandshake(entry, outbound)
    if not sent then
        return self:_failPeer(peer, DirectTransport.DISCONNECT_INTERNAL, sendError)
    end
    local marked, markError, markAuthenticationFailure = self:_markReady(entry)
    if not marked then
        return self:_failPeer(peer, markAuthenticationFailure
            and DirectTransport.DISCONNECT_AUTHENTICATION
            or DirectTransport.DISCONNECT_INTERNAL, markError)
    end
    return true
end

function Instance:_handleHandshake(entry, body, raw)
    if raw.channel ~= DirectTransport.HANDSHAKE_CHANNEL then
        return self:_failPeer(entry.peer, DirectTransport.DISCONNECT_AUTHENTICATION,
            "Direct handshakes are only accepted on channel zero.")
    end
    if entry.logicalConnected then
        return self:_failPeer(entry.peer, DirectTransport.DISCONNECT_AUTHENTICATION,
            "A handshake packet arrived after authentication completed.")
    end
    entry.handshakeFrames = entry.handshakeFrames + 1
    entry.handshakeBytes = entry.handshakeBytes + #body
    if entry.handshakeFrames > self.maxHandshakeFrames
        or entry.handshakeBytes > self.maxHandshakeTotalBytes
    then
        return self:_failPeer(entry.peer, DirectTransport.DISCONNECT_AUTHENTICATION,
            "Direct authentication exceeded its pre-authentication limit.")
    end
    entry.handshakeReceived = true
    local ok, outbound, errorMessage = callMethod(entry.state, "handshake", body)
    if not ok then
        return self:_failPeer(entry.peer, DirectTransport.DISCONNECT_AUTHENTICATION,
            "Direct authentication failed.")
    end
    if errorMessage ~= nil then
        return self:_failPeer(entry.peer, DirectTransport.DISCONNECT_AUTHENTICATION,
            "Direct authentication failed.")
    end
    local sent, sendError = self:_sendHandshake(entry, outbound)
    if not sent then
        return self:_failPeer(entry.peer, DirectTransport.DISCONNECT_INTERNAL, sendError)
    end
    local marked, markError, pendingAuthenticationFailure = self:_markReady(entry)
    if not marked then
        return self:_failPeer(entry.peer, pendingAuthenticationFailure
            and DirectTransport.DISCONNECT_AUTHENTICATION
            or DirectTransport.DISCONNECT_INTERNAL, markError)
    end
    return true
end

function Instance:_decryptData(entry, body, raw)
    local channel = wholeNumber(raw.channel, 0, self.channels - 1)
    if not channel then
        return nil, "Encrypted game data arrived on an invalid channel."
    end
    local plaintextLimit = self:_plaintextLimit(channel, true)
    if #body > plaintextLimit + self.maxCiphertextOverheadBytes then
        return nil, "Encrypted game data exceeds the inbound wire limit."
    end
    local aad = DirectTransport.aadForChannel(channel)
    local ok, plaintext, errorMessage = callMethod(entry.state, "open", body, aad)
    if not ok or errorMessage ~= nil then
        return nil, "Encrypted game data failed authentication."
    end
    if type(plaintext) ~= "string" then
        return nil, tostring(errorMessage or
            "Encrypted game data failed authentication.")
    end
    if #plaintext > plaintextLimit then
        return nil, "Decrypted game data exceeds the plaintext limit."
    end
    local event = copyEvent(raw, "receive")
    event.peer = entry.peer
    event.channel = channel
    event.data = plaintext
    event.payload = plaintext
    event.reliable = nil
    return event
end

function Instance:_processData(entry, body, raw)
    local event, processError = self:_decryptData(entry, body, raw)
    if not event then return false, processError end
    self:_queue(event)
    return true
end

function Instance:_handleData(entry, body, raw)
    if not entry.logicalConnected then
        if entry.role ~= "initiator" then
            return self:_failPeer(entry.peer,
                DirectTransport.DISCONNECT_AUTHENTICATION,
                "Encrypted game data arrived before mutual authentication.")
        end
        local channel = wholeNumber(raw.channel, 0, self.channels - 1)
        if not channel then
            return self:_failPeer(entry.peer,
                DirectTransport.DISCONNECT_AUTHENTICATION,
                "Pre-ready encrypted data arrived on an invalid channel.")
        end
        if #entry.pendingData >= self.maxPreReadyDataFrames
            or entry.pendingDataBytes + #body > self.maxPreReadyDataBytes
        then
            return self:_failPeer(entry.peer,
                DirectTransport.DISCONNECT_AUTHENTICATION,
                "Pre-ready encrypted data exceeded its bounded holding area.")
        end
        local metadata = copyEvent(raw)
        metadata.data = nil
        metadata.payload = nil
        entry.pendingData[#entry.pendingData + 1] = {
            body = body,
            raw = metadata,
        }
        entry.pendingDataBytes = entry.pendingDataBytes + #body
        return true
    end
    local processed, processError = self:_processData(entry, body, raw)
    if not processed then
        return self:_failPeer(entry.peer,
            DirectTransport.DISCONNECT_AUTHENTICATION, processError)
    end
    return true
end

function Instance:_handleReceive(raw)
    local peer = raw.peer
    local entry = peer and self._peerStates[peer] or nil
    if not entry then
        if peer then
            self:_failPeer(peer, DirectTransport.DISCONNECT_AUTHENTICATION,
                "Direct packet arrived before a connection event.")
        end
        return
    end
    local wire = raw.payload or raw.data
    local preReadyWireLimit = entry.role == "initiator"
        and self.maxWireBytes
        or DirectTransport.HEADER_BYTES + self.maxHandshakeBytes
    if not entry.logicalConnected
        and (type(wire) ~= "string"
            or #wire > preReadyWireLimit)
    then
        self:_failPeer(peer, DirectTransport.DISCONNECT_AUTHENTICATION,
            "Direct pre-authentication packet exceeds the wire limit.")
        return
    end
    local packetType, body, parseError = parseFrame(wire,
        self.maxHandshakeBytes, self.maxWireBytes)
    if not packetType then
        self:_failPeer(peer, DirectTransport.DISCONNECT_AUTHENTICATION, parseError)
    elseif packetType == DirectTransport.TYPE_HANDSHAKE then
        self:_handleHandshake(entry, body, raw)
    else
        self:_handleData(entry, body, raw)
    end
end

function Instance:_handleDisconnect(raw)
    local peer = raw.peer
    local entry, closeError
    if peer then entry, closeError = self:_forgetPeer(peer) end
    if not entry or (not entry.logicalConnected and self.mode ~= "client") then return end
    local event = copyEvent(raw, "disconnect")
    event.code = tonumber(event.code or event.data) or 0
    event.data = event.code
    event.error = closeError
    self:_queue(event)
end

function Instance:_handleRaw(raw)
    if type(raw) ~= "table" then return end
    if raw.type == "connect" then
        self:_startPeer(raw)
    elseif raw.type == "receive" then
        self:_handleReceive(raw)
    elseif raw.type == "disconnect" then
        self:_handleDisconnect(raw)
    end
end

function Instance:_expireHandshakes()
    local now, clockError = self:_readClock()
    if now == nil then
        local pending = {}
        for peer, entry in pairs(self._peerStates) do
            if not entry.logicalConnected then pending[#pending + 1] = peer end
        end
        for _, peer in ipairs(pending) do
            self:_failPeer(peer, DirectTransport.DISCONNECT_INTERNAL, clockError)
        end
        self.lastError = clockError
        return
    end
    local expired = {}
    for peer, entry in pairs(self._peerStates) do
        if not entry.logicalConnected and now >= entry.deadline then
            expired[#expired + 1] = peer
        end
    end
    for _, peer in ipairs(expired) do
        self:_failPeer(peer, DirectTransport.DISCONNECT_HANDSHAKE_TIMEOUT,
            "Direct authentication timed out.")
    end
end

function Instance:_poll(rawBudget)
    if self.closed then return nil end
    local queued = self:_dequeue()
    if queued then return queued, nil, 0 end
    self:_expireHandshakes()
    queued = self:_dequeue()
    if queued then return queued, nil, 0 end

    local consumed = 0
    for _ = 1, rawBudget do
        local ok, raw, errorMessage = callMethod(self.base, "poll")
        consumed = consumed + 1
        if not ok then
            return nil, "Direct network service failed: " .. tostring(raw), consumed
        end
        if errorMessage ~= nil then return nil, tostring(errorMessage), consumed end
        if raw == nil then break end
        self:_handleRaw(raw)
        queued = self:_dequeue()
        if queued then return queued, nil, consumed end
    end
    self:_expireHandshakes()
    return self:_dequeue(), nil, consumed
end

function Instance:poll()
    local event, errorMessage = self:_poll(DirectTransport.MAX_EVENTS_PER_SERVICE)
    return event, errorMessage
end

function Instance:service(maxEvents)
    maxEvents = wholeNumber(maxEvents or DirectTransport.MAX_EVENTS_PER_SERVICE, 1, 1024)
    if not maxEvents then return nil, "Event limit must be between 1 and 1024." end
    local events = {}
    local rawRemaining = DirectTransport.MAX_EVENTS_PER_SERVICE
    while #events < maxEvents and (rawRemaining > 0 or #self._events > 0) do
        local event, errorMessage, consumed = self:_poll(rawRemaining)
        rawRemaining = math.max(0, rawRemaining - (consumed or 0))
        if errorMessage then return events, errorMessage end
        if not event then break end
        events[#events + 1] = event
    end
    return events
end

function Instance:send(peer, payload, channelOrOptions, reliable)
    if self.closed then return false, "Transport is closed." end
    if type(payload) ~= "string" then return false, "Network payload must be a string." end
    local entry = self._peerStates[peer]
    if not entry or not entry.logicalConnected then
        return false, "Peer authentication is not complete."
    end
    local channel, useReliable = sendOptions(channelOrOptions, reliable)
    channel = wholeNumber(channel, 0, self.channels - 1)
    if not channel then return false, "Network channel is outside this session's channel range." end
    local plaintextLimit = self:_plaintextLimit(channel, false)
    if #payload > plaintextLimit then
        return false, "Network payload exceeds the direct plaintext limit."
    end
    local aad = DirectTransport.aadForChannel(channel)
    local ok, ciphertext, errorMessage = callMethod(entry.state, "seal", payload, aad)
    if not ok or errorMessage ~= nil then return false, "Game data encryption failed." end
    if type(ciphertext) ~= "string" or #ciphertext == 0 then
        return false, tostring(errorMessage or "Game data encryption failed.")
    end
    local wire = frame(DirectTransport.TYPE_DATA, ciphertext)
    if #wire > self.maxWireBytes
        or #ciphertext > plaintextLimit + self.maxCiphertextOverheadBytes
    then
        return false, "Encrypted game data exceeds the direct wire limit."
    end
    local sent, result, sendError = callMethod(self.base, "send", peer, wire,
        channel, useReliable)
    if not sent then return false, "Direct network send failed: " .. tostring(result) end
    if not sendSucceeded(result) then
        return false, tostring(sendError or "The network rejected the encrypted packet.")
    end
    return true
end

function Instance:sendToServer(payload, channelOrOptions, reliable)
    if not self.peer then return false, "Server authentication is not complete." end
    return self:send(self.peer, payload, channelOrOptions, reliable)
end

function Instance:broadcast(payload, channelOrOptions, reliable)
    if self.closed then return false, "Transport is closed." end
    if type(payload) ~= "string" then return false, "Network payload must be a string." end
    local peers = {}
    for peer in pairs(self._readyPeers) do peers[#peers + 1] = peer end
    for _, peer in ipairs(peers) do
        local ok, errorMessage = self:send(peer, payload, channelOrOptions, reliable)
        if not ok then return false, errorMessage end
    end
    return true
end

function Instance:flush()
    if self.closed or type(self.base.flush) ~= "function" then return true end
    local ok, result, errorMessage = callMethod(self.base, "flush")
    if not ok then return false, "Direct network flush failed: " .. tostring(result) end
    if result == false then return false, tostring(errorMessage or "Direct network flush failed.") end
    return true
end

function Instance:disconnect(peer, code, immediate)
    if self.closed then return false, "Transport is closed." end
    code = wholeNumber(code or 0, 0, 2147483647)
    if not code then return false, "Disconnect code must be a nonnegative whole number." end
    local ok, result, errorMessage = callMethod(self.base, "disconnect", peer, code, immediate)
    if not ok then return false, "Direct disconnect failed: " .. tostring(result) end
    if result == false then return false, tostring(errorMessage or "Direct disconnect failed.") end
    local _, closeError = self:_forgetPeer(peer)
    if closeError then return false, closeError end
    return true
end

function Instance:close(code, immediate)
    if self.closed then
        if self._closeOk == true then return true end
        return false, self._closeError
    end
    code = wholeNumber(code or 0, 0, 2147483647)
    if not code then return false, "Disconnect code must be a nonnegative whole number." end
    local errors = {}
    local peers = {}
    for peer in pairs(self._peerStates) do peers[#peers + 1] = peer end
    for _, peer in ipairs(peers) do
        local entry = self._peerStates[peer]
        local ok, closeError = closeState(entry)
        if not ok then errors[#errors + 1] = closeError end
    end
    self._peerStates = {}
    self._readyPeers = {}
    self._events = {}
    self.peer = nil
    self._serverPeer = nil
    self._key = nil
    local ok, result, errorMessage = callMethod(self.base, "close", code, immediate)
    if not ok then
        errors[#errors + 1] = "Direct network close failed: " .. tostring(result)
    elseif result == false then
        errors[#errors + 1] = tostring(errorMessage or "Direct network close failed.")
    end
    self.closed = true
    self._closeOk = #errors == 0
    self._closeError = nil
    if not self._closeOk then self._closeError = table.concat(errors, "; ") end
    return self._closeOk, self._closeError
end

Instance.destroy = Instance.close

local function wrapBase(base, mode, config, createOptions)
    if type(base) ~= "table" then return nil, "The base transport did not create an instance." end
    for _, method in ipairs({ "poll", "send", "disconnect", "close" }) do
        if type(base[method]) ~= "function" then
            return nil, "The base transport instance must implement " .. method .. "."
        end
    end
    local channels = wholeNumber(base.channels or (createOptions and createOptions.channels)
        or DirectTransport.DEFAULT_CHANNELS, 1, 255)
    if not channels then return nil, "Direct transport channel count must be between 1 and 255." end
    local baseMaxGuests = wholeNumber(base.maxGuests, 1,
        DirectTransport.DEFAULT_MAX_READY_PEERS)
    local maxReadyPeers = math.min(config.maxReadyPeers,
        baseMaxGuests or config.maxReadyPeers)
    return setmetatable({
        mode = mode,
        endpoint = base.endpoint,
        channels = channels,
        maxGuests = base.maxGuests,
        peerCapacity = base.peerCapacity,
        base = base,
        cryptoProvider = config.cryptoProvider,
        _key = config.key,
        admissionToken = config.admissionToken,
        clock = config.clock,
        handshakeTimeout = config.handshakeTimeout,
        maxHandshakeBytes = config.maxHandshakeBytes,
        maxHandshakeFrames = config.maxHandshakeFrames,
        maxHandshakeTotalBytes = config.maxHandshakeTotalBytes,
        maxPreReadyDataFrames = config.maxPreReadyDataFrames,
        maxPreReadyDataBytes = config.maxPreReadyDataBytes,
        maxPendingPeers = config.maxPendingPeers,
        admissionBurst = config.admissionBurst,
        admissionRefillSeconds = config.admissionRefillSeconds,
        maxReadyPeers = maxReadyPeers,
        maxRealtimePlaintextBytes = config.maxRealtimePlaintextBytes,
        maxPlaintextBytes = config.maxPlaintextBytes,
        maxCiphertextOverheadBytes = config.maxCiphertextOverheadBytes,
        maxWireBytes = config.maxWireBytes,
        peer = nil,
        closed = false,
        _serverPeer = mode == "client" and base.peer or nil,
        _peerStates = {},
        _readyPeers = {},
        _events = {},
        _admissionTokens = config.admissionBurst,
        _admissionLastRefill = nil,
        _lastClock = nil,
        _clockFailed = false,
    }, Instance)
end

function DirectTransport.newFactory(options)
    options = options or {}
    if type(options.baseFactory) ~= "table"
        or type(options.baseFactory.createHost) ~= "function"
        or type(options.baseFactory.createClient) ~= "function"
    then
        return nil, "Direct Internet Play requires a base transport factory."
    end
    local baseFactory = options.baseFactory
    local provider, providerError = validateProvider(options.cryptoProvider)
    if not provider then return nil, providerError end
    if type(options.key) ~= "string" or #options.key ~= DirectTransport.KEY_BYTES then
        return nil, "Direct Internet Play requires a 32-byte shared key."
    end
    local admissionToken, admissionTokenError = DirectTransport.admissionToken(
        provider, options.key)
    if admissionToken == nil then return nil, admissionTokenError end
    local clock = options.clock or defaultClock
    if type(clock) ~= "function" then return nil, "Direct transport clock must be a function." end
    local handshakeTimeout = finiteNumber(options.handshakeTimeout
        or DirectTransport.DEFAULT_HANDSHAKE_TIMEOUT, 0, 120)
    if not handshakeTimeout or handshakeTimeout <= 0 then
        return nil, "Direct handshake timeout must be greater than zero and at most 120 seconds."
    end
    local maxHandshakeBytes = wholeNumber(options.maxHandshakeBytes
        or DirectTransport.DEFAULT_MAX_HANDSHAKE_BYTES, 1, 65535)
    local maxHandshakeFrames = wholeNumber(options.maxHandshakeFrames
        or DirectTransport.DEFAULT_MAX_HANDSHAKE_FRAMES, 1, 16)
    local maxHandshakeTotalBytes = wholeNumber(options.maxHandshakeTotalBytes
        or DirectTransport.DEFAULT_MAX_HANDSHAKE_TOTAL_BYTES, 1, 65535)
    local maxPreReadyDataFrames = wholeNumber(options.maxPreReadyDataFrames
        or DirectTransport.DEFAULT_MAX_PRE_READY_DATA_FRAMES, 1, 16)
    local maxPlaintextBytes = wholeNumber(options.maxPlaintextBytes
        or DirectTransport.DEFAULT_MAX_PLAINTEXT_BYTES, 1, 1024 * 1024)
    local maxRealtimePlaintextBytes = wholeNumber(options.maxRealtimePlaintextBytes
        or math.min(DirectTransport.DEFAULT_MAX_REALTIME_PLAINTEXT_BYTES,
            maxPlaintextBytes or DirectTransport.DEFAULT_MAX_REALTIME_PLAINTEXT_BYTES),
        1, maxPlaintextBytes or DirectTransport.DEFAULT_MAX_PLAINTEXT_BYTES)
    local maxCiphertextOverheadBytes = wholeNumber(options.maxCiphertextOverheadBytes
        or DirectTransport.DEFAULT_MAX_CIPHERTEXT_OVERHEAD_BYTES, 16, 4096)
    local peerCapacity = wholeNumber(options.peerCapacity
        or DirectTransport.DEFAULT_PEER_CAPACITY, 4, 16)
    local maxReadyPeers = wholeNumber(options.maxReadyPeers
        or DirectTransport.DEFAULT_MAX_READY_PEERS, 1,
        DirectTransport.DEFAULT_MAX_READY_PEERS)
    local maxPendingPeers = peerCapacity and wholeNumber(options.maxPendingPeers
        or DirectTransport.DEFAULT_MAX_PENDING_PEERS, 1,
        peerCapacity - (maxReadyPeers or DirectTransport.DEFAULT_MAX_READY_PEERS)) or nil
    local admissionBurst = peerCapacity and wholeNumber(options.admissionBurst
        or DirectTransport.DEFAULT_ADMISSION_BURST, 1, peerCapacity) or nil
    local admissionRefillSeconds = finiteNumber(options.admissionRefillSeconds
        or DirectTransport.DEFAULT_ADMISSION_REFILL_SECONDS, 0.001, 3600)
    local maxWireBytes = wholeNumber(options.maxWireBytes
        or DirectTransport.DEFAULT_MAX_WIRE_BYTES,
        DirectTransport.HEADER_BYTES + 1, 2 * 1024 * 1024)
    local defaultPreReadyBytes = maxWireBytes and maxPreReadyDataFrames
        and math.min(4 * 1024 * 1024,
            maxWireBytes * maxPreReadyDataFrames,
            DirectTransport.DEFAULT_MAX_PRE_READY_DATA_BYTES)
        or DirectTransport.DEFAULT_MAX_PRE_READY_DATA_BYTES
    local maxPreReadyDataBytes = wholeNumber(options.maxPreReadyDataBytes
        or defaultPreReadyBytes, 1, 4 * 1024 * 1024)
    if not maxHandshakeBytes then return nil, "Direct handshake byte limit is invalid." end
    if not maxHandshakeFrames then return nil, "Direct handshake frame limit is invalid." end
    if not maxHandshakeTotalBytes then return nil, "Direct handshake total-byte limit is invalid." end
    if not maxPreReadyDataFrames or not maxPreReadyDataBytes then
        return nil, "Direct pre-ready data limits are invalid."
    end
    if not maxPlaintextBytes then return nil, "Direct plaintext byte limit is invalid." end
    if not maxRealtimePlaintextBytes then
        return nil, "Direct realtime plaintext byte limit is invalid."
    end
    if not maxCiphertextOverheadBytes then
        return nil, "Direct ciphertext overhead limit is invalid."
    end
    if not peerCapacity or not maxReadyPeers or not maxPendingPeers then
        return nil, "Direct peer capacity must reserve room for authenticated guests."
    end
    if not admissionBurst or not admissionRefillSeconds then
        return nil, "Direct admission rate limits are invalid."
    end
    if not maxWireBytes then return nil, "Direct wire byte limit is invalid." end
    if maxWireBytes < DirectTransport.HEADER_BYTES + maxHandshakeBytes then
        return nil, "Direct wire byte limit cannot contain the configured handshake limit."
    end
    if maxWireBytes < DirectTransport.HEADER_BYTES + maxPlaintextBytes then
        return nil, "Direct wire byte limit cannot contain the configured plaintext limit."
    end

    local config = {
        cryptoProvider = provider,
        key = options.key,
        admissionToken = admissionToken,
        clock = clock,
        handshakeTimeout = handshakeTimeout,
        maxHandshakeBytes = maxHandshakeBytes,
        maxHandshakeFrames = maxHandshakeFrames,
        maxHandshakeTotalBytes = maxHandshakeTotalBytes,
        maxPreReadyDataFrames = maxPreReadyDataFrames,
        maxPreReadyDataBytes = maxPreReadyDataBytes,
        maxPendingPeers = maxPendingPeers,
        admissionBurst = admissionBurst,
        admissionRefillSeconds = admissionRefillSeconds,
        maxReadyPeers = maxReadyPeers,
        maxRealtimePlaintextBytes = maxRealtimePlaintextBytes,
        maxPlaintextBytes = maxPlaintextBytes,
        maxCiphertextOverheadBytes = maxCiphertextOverheadBytes,
        maxWireBytes = maxWireBytes,
        peerCapacity = peerCapacity,
    }
    local factory = {
        DEFAULT_PORT = baseFactory.DEFAULT_PORT,
        MAX_GUESTS = baseFactory.MAX_GUESTS,
        MAX_PEERS = baseFactory.MAX_PEERS,
        MIN_CHANNELS = baseFactory.MIN_CHANNELS,
        DEFAULT_CHANNELS = baseFactory.DEFAULT_CHANNELS,
    }
    local created = false

    local function disposeFactory()
        if created then return true end
        created = true
        config.key = nil
        config.admissionToken = nil
        config.cryptoProvider = nil
        return true
    end

    function factory.close()
        return disposeFactory()
    end

    factory.dispose = factory.close

    function factory.createHost(createOptions)
        if created then return nil, "A Direct transport factory creates only one session." end
        createOptions = createOptions or {}
        local forwarded = {}
        for name, value in pairs(createOptions) do forwarded[name] = value end
        forwarded.peerCapacity = config.peerCapacity
        local ok, base, errorMessage = callFactory(baseFactory, "createHost", forwarded)
        if not ok then
            disposeFactory()
            return nil, "Base host creation failed: " .. tostring(base)
        end
        if not base then disposeFactory(); return nil, errorMessage end
        local wrapped, wrapError = wrapBase(base, "host", config, forwarded)
        if not wrapped then
            callMethod(base, "close", DirectTransport.DISCONNECT_INTERNAL, true)
            disposeFactory()
            return nil, wrapError
        end
        created = true
        config.key = nil
        return wrapped
    end

    function factory.createClient(address, createOptions)
        if created then return nil, "A Direct transport factory creates only one session." end
        createOptions = createOptions or {}
        local forwarded = {}
        for name, value in pairs(createOptions) do forwarded[name] = value end
        forwarded.connectData = config.admissionToken
        local ok, base, errorMessage = callFactory(baseFactory,
            "createClient", address, forwarded)
        if not ok then
            disposeFactory()
            return nil, "Base client creation failed: " .. tostring(base)
        end
        if not base then disposeFactory(); return nil, errorMessage end
        local wrapped, wrapError = wrapBase(base, "client", config, forwarded)
        if not wrapped then
            callMethod(base, "close", DirectTransport.DISCONNECT_INTERNAL, true)
            disposeFactory()
            return nil, wrapError
        end
        created = true
        config.key = nil
        return wrapped
    end

    return factory
end

DirectTransport.Instance = Instance
return DirectTransport
